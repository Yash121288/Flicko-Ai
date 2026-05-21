from __future__ import annotations

import hashlib
import json
import logging
import re
import urllib.error
import urllib.request
from dataclasses import dataclass
from typing import Any

from django.conf import settings
from django.contrib.auth.models import User
from django.utils import timezone

from .intake_requirements import assess_intake
from .report_templates import report_markdown_sections_for_problem

logger = logging.getLogger(__name__)


MAX_MODEL_TRANSCRIPT_CHARS = 60000


@dataclass(frozen=True)
class ConversationAnalysisResult:
    intake_summary: str
    report_markdown: str
    dashboard_values: dict[str, Any]
    dashboard_notes: list[str]
    reminders: list[str]
    app_data: dict[str, list[dict[str, Any]]]
    raw_transcript_text: str
    analyzer: str
    intake_assessment: dict[str, Any]

    def to_response(self) -> dict[str, Any]:
        return {
            "intake_summary": self.intake_summary,
            "report_markdown": self.report_markdown,
            "dashboard_values": self.dashboard_values,
            "dashboard_notes": self.dashboard_notes,
            "reminders": self.reminders,
            "app_data": self.app_data,
            "raw_transcript_text": self.raw_transcript_text,
            "analyzer": self.analyzer,
            "intake_assessment": self.intake_assessment,
        }


def analyze_health_conversation(
    *,
    user: User,
    problem_name: str,
    intake_summary: str,
    dashboard_values: dict[str, Any],
    reminders: list[str],
    transcript: list[dict[str, Any]],
    source_payload: dict[str, Any] | None = None,
    raw_transcript_text: str = "",
) -> ConversationAnalysisResult:
    """Turn the full AI call/chat transcript into dashboard/report records.

    Groq is used only when configured. The deterministic fallback keeps the
    product usable on slow/free backend deployments and in tests.
    """

    transcript_text = (
        raw_transcript_text.strip() or transcript_to_text(transcript)
    ).strip()
    profile_context = profile_to_context(user)
    model_input = transcript_text[:MAX_MODEL_TRANSCRIPT_CHARS]
    base_payload = {
        "problem_name": problem_name or _primary_problem(user),
        "profile_context": profile_context,
        "existing_intake_summary": intake_summary,
        "existing_dashboard_values": dashboard_values,
        "existing_reminders": reminders,
        "transcript": model_input,
        "source_payload": source_payload or {},
    }

    groq_result = _try_groq_analysis(base_payload)
    if groq_result:
        return _normalise_analysis_result(
            user=user,
            problem_name=problem_name,
            transcript=transcript,
            transcript_text=transcript_text,
            fallback_summary=intake_summary,
            model_payload=groq_result,
            analyzer="groq",
        )

    return _fallback_analysis(
        user=user,
        problem_name=problem_name,
        intake_summary=intake_summary,
        dashboard_values=dashboard_values,
        reminders=reminders,
        transcript=transcript,
        transcript_text=transcript_text,
    )


def transcript_to_text(transcript: list[dict[str, Any]]) -> str:
    lines: list[str] = []
    for item in transcript if isinstance(transcript, list) else []:
        if not isinstance(item, dict):
            continue
        text = str(item.get("text") or item.get("content") or "").strip()
        if not text:
            continue
        role = str(item.get("role") or "").strip().lower()
        label = "User" if role == "user" else "Flicko"
        created_at = str(item.get("createdAt") or item.get("created_at") or "").strip()
        prefix = f"[{created_at}] {label}" if created_at else label
        lines.append(f"{prefix}: {text}")
    return "\n".join(lines)


def profile_to_context(user: User) -> dict[str, Any]:
    profile = getattr(user, "profile", None)
    if profile is None:
        return {"name": user.get_full_name() or user.email, "email": user.email}
    return {
        "name": user.get_full_name() or user.email,
        "email": user.email,
        "mobile": profile.mobile,
        "age": profile.age,
        "gender": profile.gender,
        "height_cm": profile.height_cm,
        "weight_kg": profile.weight_kg,
        "goal_weight_kg": profile.goal_weight_kg,
        "timezone": profile.timezone,
        "language": profile.language,
        "food_preference": profile.food_preference,
        "medications": profile.medications,
        "allergies": profile.allergies,
        "diagnosis": profile.diagnosis,
        "surgery_history": profile.surgery_history,
        "family_history": profile.family_history,
        "pregnancy_cycle": profile.pregnancy_cycle,
        "selected_problems": profile.selected_problems,
    }


def _try_groq_analysis(payload: dict[str, Any]) -> dict[str, Any] | None:
    api_key = str(getattr(settings, "GROQ_API_KEY", "") or "").strip()
    if not api_key:
        return None

    model = str(getattr(settings, "GROQ_MODEL", "") or "llama-3.1-8b-instant").strip()
    timeout = int(getattr(settings, "GROQ_TIMEOUT_SECONDS", 22))
    prompt = _groq_prompt(payload)
    body = json.dumps(
        {
            "model": model,
            "temperature": 0.15,
            "max_tokens": 4200,
            "messages": [
                {
                    "role": "system",
                    "content": (
                        "You are Flicko's clinical data extraction engine. "
                        "Return only strict JSON. Do not diagnose. Do not invent values. "
                        "If data is missing, use cautious follow-up tasks."
                    ),
                },
                {"role": "user", "content": prompt},
            ],
        }
    ).encode("utf-8")
    request = urllib.request.Request(
        "https://api.groq.com/openai/v1/chat/completions",
        data=body,
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
            "Accept": "application/json",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            decoded = json.loads(response.read().decode("utf-8"))
    except (urllib.error.URLError, TimeoutError, json.JSONDecodeError, OSError) as exc:
        logger.warning("Groq conversation analysis failed: %s", exc)
        return None

    content = (
        decoded.get("choices", [{}])[0]
        .get("message", {})
        .get("content", "")
    )
    return _extract_json_object(str(content))


def _groq_prompt(payload: dict[str, Any]) -> str:
    required_sections = list(
        report_markdown_sections_for_problem(str(payload.get("problem_name") or ""))
    )
    return json.dumps(
        {
            "task": "Analyze this full Flicko health call/chat and extract backend-ready app data plus a professional condition-specific report narrative.",
            "report_quality_rules": [
                "Use only facts present in profile_context, existing records, source_payload, or transcript.",
                "Write a clinician-readable report, not a casual chatbot summary.",
                "Keep sensitive topics private, neutral, and non-judgmental.",
                "If a value is missing, write 'Not captured yet' and ask for it as a follow-up.",
                "Do not diagnose, prescribe, or invent medicines, doses, lab values, timelines, or risk scores.",
                "Separate patient-stated facts from AI recommendations.",
                "Include safety red flags and clear doctor-review triggers.",
                "Use the exact markdown section headings provided in required_markdown_sections.",
                "Prefer structured, report-like language over generic wellness summaries.",
                "Do not treat intake as complete unless onset/duration, medicines, timing, report/lab status, and red flags are actually captured.",
            ],
            "required_markdown_sections": required_sections,
            "required_json_schema": {
                "intake_summary": "same professional markdown as report_markdown, concise enough for app memory",
                "report_markdown": "markdown using every required_markdown_sections item, detailed and user-specific",
                "dashboard_values": {
                    "score": "0-100 integer",
                    "primary_problem": "string",
                    "metric_value": "string",
                    "metric_unit": "string",
                    "metric_status": "string",
                    "plan_focus": "string",
                    "plan_note": "string",
                    "report_body": "string",
                },
                "dashboard_notes": ["short user-specific dashboard notes"],
                "reminders": ["short reminder lines"],
                "intake_assessment": {
                    "report_ready": True,
                    "missing_labels": ["missing required intake field labels"],
                    "next_questions": ["the next 1-3 precise questions Flicko should ask"],
                },
                "saved_reminders": [
                    {
                        "title": "string",
                        "body": "string",
                        "hour": "0-23 integer",
                        "minute": "0-59 integer",
                        "enabled": True,
                    }
                ],
                "care_tasks": [
                    {
                        "type": "medicine|meal|measurement|activity|water|sleep|symptom|appointment|custom",
                        "title": "string",
                        "detail": "string",
                        "timeLabel": "string",
                        "enabled": True,
                    }
                ],
                "health_logs": [
                    {
                        "type": "weight|glucose|bloodPressure|meal|water|steps|sleep|mood|medicine|symptom|activity",
                        "title": "string",
                        "value": "string",
                        "unit": "string",
                        "note": "string",
                    }
                ],
                "safety_events": [
                    {
                        "severity": "clinician|urgent|emergency",
                        "title": "string",
                        "matchedText": "string",
                        "action": "string",
                    }
                ],
            },
            "input": payload,
        },
        ensure_ascii=True,
    )


def _fallback_analysis(
    *,
    user: User,
    problem_name: str,
    intake_summary: str,
    dashboard_values: dict[str, Any],
    reminders: list[str],
    transcript: list[dict[str, Any]],
    transcript_text: str,
) -> ConversationAnalysisResult:
    problem = problem_name or _primary_problem(user)
    user_lines = _role_lines(transcript, "user")
    user_text = "\n".join(user_lines).strip() or transcript_text
    all_text = " ".join([user_text, intake_summary]).strip()
    extracted_reminders = _extract_reminder_lines(user_text, reminders)
    health_logs = _extract_health_logs(all_text, problem)
    safety_events = _extract_safety_events(all_text, problem)
    saved_reminders = _build_saved_reminders(problem, extracted_reminders)
    care_tasks = _build_care_tasks(problem, extracted_reminders, health_logs, all_text)
    score = _score_from_data(dashboard_values, safety_events, health_logs)
    intake_assessment = assess_intake(
        problem,
        dashboard_values=dashboard_values,
        transcript_lines=user_lines,
        intake_summary=intake_summary,
        reminders=extracted_reminders,
    ).to_payload()

    overview = (
        f"Flicko reviewed the full {problem} conversation. "
        f"The user shared {len(user_lines)} user response(s), "
        f"{len(health_logs)} measurable log item(s), and "
        f"{len(saved_reminders)} follow-up reminder(s)."
    )
    overview = (
        f"{overview} Intake completeness scored {intake_assessment['score']}% "
        f"and report readiness is {'ready' if intake_assessment['report_ready'] else 'not ready yet'}."
    )
    if intake_summary.strip():
        overview = f"{overview} Existing intake note: {intake_summary.strip()[:650]}"

    report_markdown = _build_report_markdown(
        problem=problem,
        overview=overview,
        user_lines=user_lines,
        reminders=extracted_reminders,
        health_logs=health_logs,
        safety_events=safety_events,
        care_tasks=care_tasks,
    )
    dashboard = {
        **dashboard_values,
        "score": score,
        "health_score": score,
        "primary_problem": problem,
        "metric_value": _primary_metric_value(problem, health_logs),
        "metric_unit": _primary_metric_unit(problem, health_logs),
        "metric_status": "Needs routine follow-up" if score < 75 else "Stable routine",
        "plan_focus": _plan_focus(problem, care_tasks),
        "plan_note": "Updated from full call transcript and saved backend records.",
        "check_body": "Flicko will follow missed meals, medicines, sleep, and measurement tasks.",
        "report_body": "Doctor-ready report generated from full transcript, logs, reminders, and safety scan.",
        "full_transcript_saved": bool(transcript_text),
        "transcript_message_count": len(transcript),
    }
    app_data = {
        "saved_reminders": saved_reminders,
        "care_tasks": care_tasks,
        "health_logs": health_logs,
        "safety_events": safety_events,
        "chat_history": _chat_records_from_transcript(transcript, problem),
        "meal_analyses": [],
    }
    return ConversationAnalysisResult(
        intake_summary=report_markdown,
        report_markdown=report_markdown,
        dashboard_values=dashboard,
        dashboard_notes=[
            overview,
            "Dashboard values now come from saved call/chat records, not static demo cards.",
        ],
        reminders=extracted_reminders,
        app_data=app_data,
        raw_transcript_text=transcript_text,
        analyzer="local_fallback",
        intake_assessment=intake_assessment,
    )


def _normalise_analysis_result(
    *,
    user: User,
    problem_name: str,
    transcript: list[dict[str, Any]],
    transcript_text: str,
    fallback_summary: str,
    model_payload: dict[str, Any],
    analyzer: str,
) -> ConversationAnalysisResult:
    problem = problem_name or _primary_problem(user)
    fallback = _fallback_analysis(
        user=user,
        problem_name=problem,
        intake_summary=fallback_summary,
        dashboard_values=_dict(model_payload.get("dashboard_values")),
        reminders=_string_list(model_payload.get("reminders")),
        transcript=transcript,
        transcript_text=transcript_text,
    )
    app_data = {
        "saved_reminders": _normalise_app_records(
            model_payload.get("saved_reminders"),
            problem,
            record_type="reminder",
        )
        or fallback.app_data["saved_reminders"],
        "care_tasks": _normalise_app_records(
            model_payload.get("care_tasks"),
            problem,
            record_type="task",
        )
        or fallback.app_data["care_tasks"],
        "health_logs": _normalise_app_records(
            model_payload.get("health_logs"),
            problem,
            record_type="log",
        )
        or fallback.app_data["health_logs"],
        "safety_events": _normalise_app_records(
            model_payload.get("safety_events"),
            problem,
            record_type="safety",
        )
        or fallback.app_data["safety_events"],
        "chat_history": fallback.app_data["chat_history"],
        "meal_analyses": [],
    }
    dashboard_values = {
        **fallback.dashboard_values,
        **_dict(model_payload.get("dashboard_values")),
        "primary_problem": problem,
        "full_transcript_saved": bool(transcript_text),
        "transcript_message_count": len(transcript),
    }
    candidate_report_markdown = (
        str(model_payload.get("report_markdown") or "").strip()
        or str(model_payload.get("intake_summary") or "").strip()
    )
    report_markdown = _coerce_report_markdown(
        problem=problem,
        candidate=candidate_report_markdown,
        fallback=fallback.report_markdown,
    )
    return ConversationAnalysisResult(
        intake_summary=str(model_payload.get("intake_summary") or report_markdown).strip(),
        report_markdown=report_markdown,
        dashboard_values=dashboard_values,
        dashboard_notes=_string_list(model_payload.get("dashboard_notes"))
        or fallback.dashboard_notes,
        reminders=_string_list(model_payload.get("reminders")) or fallback.reminders,
        app_data=app_data,
        raw_transcript_text=transcript_text,
        analyzer=analyzer,
        intake_assessment={
            **fallback.intake_assessment,
            **_dict(model_payload.get("intake_assessment")),
        },
    )


def _role_lines(transcript: list[dict[str, Any]], role: str) -> list[str]:
    target = role.lower()
    lines: list[str] = []
    for item in transcript if isinstance(transcript, list) else []:
        if not isinstance(item, dict):
            continue
        item_role = str(item.get("role") or "").strip().lower()
        text = str(item.get("text") or "").strip()
        if item_role == target and text:
            lines.append(_clean(text))
    return lines


def _build_report_markdown(
    *,
    problem: str,
    overview: str,
    user_lines: list[str],
    reminders: list[str],
    health_logs: list[dict[str, Any]],
    safety_events: list[dict[str, Any]],
    care_tasks: list[dict[str, Any]],
) -> str:
    user_notes = user_lines[:10] or ["User did not share enough structured details yet."]
    log_lines = [
        f"{item.get('title')}: {item.get('value')} {item.get('unit')}".strip()
        for item in health_logs
    ] or ["No numeric reading captured yet."]
    safety_lines = [
        f"{item.get('severity')}: {item.get('title')} - {item.get('action')}"
        for item in safety_events
    ] or ["No emergency red flag detected from the saved transcript."]
    task_lines = [
        f"{item.get('timeLabel')}: {item.get('title')} - {item.get('detail')}".strip(": ")
        for item in care_tasks
    ] or ["Continue daily Flicko check-ins."]
    reminder_lines = reminders or ["Daily Flicko check-in reminder."]
    missing_lines = _missing_report_fields(problem, user_lines, health_logs, reminders)
    plan_lines = _problem_specific_plan(problem, care_tasks, reminders)
    doctor_lines = _problem_specific_doctor_questions(problem)
    routine_lines = _routine_report_lines(user_lines)
    sections: list[str] = []
    for title in report_markdown_sections_for_problem(problem):
        body_lines, bullet_lines = _report_section_content(
            title=title,
            problem=problem,
            overview=overview,
            user_notes=user_notes,
            log_lines=log_lines,
            routine_lines=routine_lines,
            safety_lines=safety_lines,
            task_lines=task_lines,
            reminder_lines=reminder_lines,
            missing_lines=missing_lines,
            plan_lines=plan_lines,
            doctor_lines=doctor_lines,
        )
        sections.append(_markdown_section(title, body_lines, bullet_lines))
    return "\n\n".join(section for section in sections if section.strip())


def _coerce_report_markdown(*, problem: str, candidate: str, fallback: str) -> str:
    text = str(candidate or "").strip()
    if not text:
        return fallback
    expected_sections = report_markdown_sections_for_problem(problem)
    lowered = text.lower()
    matched = sum(
        1 for title in expected_sections
        if f"## {title}".lower() in lowered
    )
    minimum_required = min(3, len(expected_sections))
    return text if matched >= minimum_required else fallback


def _markdown_section(title: str, body_lines: list[str], bullet_lines: list[str]) -> str:
    lines = [f"## {title}"]
    lines.extend(line.strip() for line in body_lines if line.strip())
    lines.extend(f"- {line.strip()}" for line in bullet_lines if line.strip())
    return "\n".join(lines)


def _report_section_content(
    *,
    title: str,
    problem: str,
    overview: str,
    user_notes: list[str],
    log_lines: list[str],
    routine_lines: list[str],
    safety_lines: list[str],
    task_lines: list[str],
    reminder_lines: list[str],
    missing_lines: list[str],
    plan_lines: list[str],
    doctor_lines: list[str],
) -> tuple[list[str], list[str]]:
    normalized = title.lower()
    if title == "Safety Boundary":
        return (
            [],
            [
                "This AI report is informational and supports doctor discussion only.",
                "Confirm diagnosis, medicines, pregnancy status, allergies, abnormal readings, and report uploads with a licensed clinician.",
                "Emergency symptoms should trigger local emergency care immediately.",
            ],
        )
    if "chief concern" in normalized:
        return ([overview], user_notes[:6])
    if "snapshot" in normalized or "monitoring" in normalized:
        return (
            ["Structured monitoring summary from saved dashboard values and measurable logs."],
            _merge_unique(log_lines, missing_lines)[:6],
        )
    if "symptom review" in normalized or "symptom timeline" in normalized or "symptom cluster" in normalized:
        return (
            ["Symptoms are organized in a clinician-readable sequence rather than as chat fragments."],
            _merge_unique(user_notes, log_lines)[:6],
        )
    if "safety" in normalized or "risk review" in normalized or "warning sign" in normalized or "risk factors" in normalized:
        return (
            ["Escalation cues and clinical risk flags extracted from the saved conversation."],
            _merge_unique(safety_lines, missing_lines)[:6],
        )
    if "meal structure" in normalized or "nutrition" in normalized or "food routine" in normalized:
        return (
            ["Meal structure should support the primary condition, medication timing, and symptom control."],
            _merge_unique(_meal_structure_lines(problem, routine_lines, plan_lines), reminder_lines)[:6],
        )
    if "7-day plan" in normalized or "daily reset plan" in normalized or "recovery timeline" in normalized:
        return (
            ["The next seven days should be operational, repeatable, and easy to review against adherence."],
            _merge_unique(plan_lines, reminder_lines)[:7],
        )
    if "testing and follow-up" in normalized or "lab" in normalized or "doctor discussion" in normalized or "clinician review" in normalized:
        return (
            ["Tests, report uploads, and clinician review points that still need confirmation."],
            _merge_unique(_testing_followup_lines(problem, doctor_lines, missing_lines), plan_lines)[:7],
        )
    if "medicine timing" in normalized or "medicine routine" in normalized or "medication" in normalized:
        return (
            ["Any medicine list here must be reconciled against the written prescription before use."],
            _merge_unique(routine_lines, missing_lines)[:6],
        )
    if "trigger" in normalized:
        return (
            ["Triggers should be paired with a specific response so the plan is actionable, not generic."],
            _merge_unique(_trigger_response_lines(problem, plan_lines, reminder_lines), task_lines)[:6],
        )
    if "recovery checklist" in normalized:
        return (
            ["Use this checklist daily to decide whether recovery is stable or clinician input is needed."],
            _merge_unique(plan_lines, safety_lines)[:6],
        )
    if "training split" in normalized or "exercise readiness" in normalized or "fitness baseline" in normalized:
        return (
            ["Training load should respect symptoms, recovery, and any clinician restrictions."],
            _merge_unique(plan_lines, routine_lines)[:6],
        )
    if "habit reset" in normalized or "habit blocker" in normalized:
        return (
            ["Behavior change is framed as a trackable loop: trigger, response, review, repeat."],
            _merge_unique(task_lines, reminder_lines, missing_lines)[:6],
        )
    if "routine" in normalized:
        return (
            ["Current routine factors affecting the condition are summarized below."],
            routine_lines[:6],
        )
    if "context" in normalized or "support" in normalized or "family" in normalized or "exposure" in normalized:
        return (
            ["Context from the conversation that may affect symptoms, adherence, privacy, or safety."],
            _merge_unique(user_notes, reminder_lines, missing_lines)[:6],
        )
    if "doctor" in normalized or "referral" in normalized or "follow-up" in normalized:
        return (
            ["These points are suitable to carry directly into the next clinician conversation."],
            _merge_unique(doctor_lines, missing_lines)[:6],
        )
    return ([overview], _merge_unique(plan_lines, user_notes, missing_lines)[:6])


def _meal_structure_lines(problem: str, routine_lines: list[str], plan_lines: list[str]) -> list[str]:
    lower = problem.lower()
    if "diabetes" in lower:
        base = [
            "Anchor breakfast and medicine timing to reduce unplanned glucose variation.",
            "Use measured carbohydrate portions with protein in each main meal.",
            "Avoid long meal gaps that lead to overeating or delayed medicines.",
        ]
    elif "weight" in lower:
        base = [
            "Keep each main meal protein-anchored and portion-aware.",
            "Use a planned afternoon or evening snack instead of reactive grazing.",
            "Review liquid calories, weekend meals, and late-night eating separately.",
        ]
    elif any(token in lower for token in ("pregnancy", "postpartum", "pcos", "thyroid", "women", "skin", "hair", "autoimmune")):
        base = [
            "Prioritize repeatable meals that support energy stability and symptom control.",
            "Avoid skipping meals when fatigue, cravings, or nausea make the routine erratic.",
            "Keep hydration and one tolerated protein source visible every day.",
        ]
    else:
        base = [
            "Build meals around one stable protein source, vegetables or fiber, and predictable timing.",
            "Keep the hardest eating window planned in advance.",
            "Document any food that repeatedly worsens symptoms.",
        ]
    return _merge_unique(base, routine_lines, plan_lines)


def _testing_followup_lines(problem: str, doctor_lines: list[str], missing_lines: list[str]) -> list[str]:
    lower = problem.lower()
    if "sexual" in lower:
        base = [
            "Clarify whether STI testing, urine testing, pregnancy testing, or pelvic/urology review is needed.",
            "Upload any prescription, prior report, or test result before the next review.",
        ]
    elif "diabetes" in lower:
        base = [
            "Review whether fasting glucose, post-meal glucose, and HbA1c timing are documented.",
            "Check if kidney profile, lipids, and complication screening are due.",
        ]
    elif "weight" in lower:
        base = [
            "Confirm whether BMI, waist, thyroid, glucose, lipid, or liver markers need updating.",
            "Bring weight trend and food pattern notes to the next review.",
        ]
    else:
        base = [
            "Confirm which tests, uploads, or measurements are needed before the next clinician review.",
            "Document exact dates on any available reports so they can be interpreted in sequence.",
        ]
    return _merge_unique(base, doctor_lines, missing_lines)


def _trigger_response_lines(problem: str, plan_lines: list[str], reminder_lines: list[str]) -> list[str]:
    lower = problem.lower()
    if "stress" in lower or "mood" in lower or "habit" in lower:
        base = [
            "Match the high-risk trigger with one replacement action that can be done in under two minutes.",
            "Use the reminder as an external cue, not as a vague suggestion.",
        ]
    elif "digestive" in lower or "acidity" in lower or "bloating" in lower:
        base = [
            "Track the specific food, timing, posture, or stress link before changing the whole diet.",
            "When a trigger repeats, remove only one suspected factor at a time.",
        ]
    else:
        base = [
            "Identify the time, behavior, or context that reliably causes the setback.",
            "Assign one immediate response so the user does not improvise under stress.",
        ]
    return _merge_unique(base, plan_lines, reminder_lines)


def _merge_unique(*groups: list[str] | tuple[str, ...]) -> list[str]:
    merged: list[str] = []
    seen: set[str] = set()
    for group in groups:
        for item in group:
            clean = str(item).strip()
            if not clean:
                continue
            key = clean.lower()
            if key in seen:
                continue
            seen.add(key)
            merged.append(clean)
    return merged


def _routine_report_lines(user_lines: list[str]) -> list[str]:
    text = " ".join(user_lines).lower()
    rows: list[str] = []
    checks = (
        ("Medicine routine", ("medicine", "tablet", "dose", "metformin", "insulin")),
        ("Meal and hydration routine", ("meal", "breakfast", "lunch", "dinner", "water", "protein")),
        ("Sleep and recovery", ("sleep", "neend", "wake", "bedtime")),
        ("Uploaded reports or lab values", ("report", "lab", "test", "hba1c", "thyroid", "lipid", "cbc")),
        ("Allergy or surgery history", ("allergy", "allergic", "surgery", "operation")),
    )
    for label, keywords in checks:
        if any(keyword in text for keyword in keywords):
            rows.append(f"{label}: mentioned during conversation; verify exact details before clinical use.")
        else:
            rows.append(f"{label}: Not captured yet.")
    return rows


def _missing_report_fields(
    problem: str,
    user_lines: list[str],
    health_logs: list[dict[str, Any]],
    reminders: list[str],
) -> list[str]:
    assessment = assess_intake(
        problem,
        transcript_lines=user_lines,
        reminders=reminders,
    )
    text = " ".join(user_lines).lower()
    missing: list[str] = []
    missing.extend(field.label for field in assessment.missing_fields[:6])
    if not health_logs:
        missing.append("Latest measurable reading or lab value with date/time.")
    if not reminders:
        missing.append("Preferred reminder time and notification frequency.")
    if not any(token in text for token in ("medicine", "tablet", "dose", "insulin", "metformin")):
        missing.append("Medicine name, dose, timing, and whether doses are missed.")
    if not any(token in text for token in ("allergy", "allergic")):
        missing.append("Allergies and medication reactions.")
    if not any(token in text for token in ("report", "lab", "test")):
        missing.append("Recent doctor report, lab test, or prescription upload.")
    lower = problem.lower()
    if "sexual" in lower:
        sexual_items = (
            "Symptom timeline, pain/bleeding/discharge details, STI exposure risk, contraception status, and partner factors.",
            "Whether urgent symptoms exist: severe pelvic/testicular pain, fever, bleeding, pregnancy risk, or assault concern.",
        )
        missing.extend(item for item in sexual_items if item not in missing)
    if "diabetes" in lower and not any(token in text for token in ("hba1c", "fasting", "post meal", "post-meal")):
        missing.append("Fasting glucose, post-meal glucose, HbA1c date, and hypo/hyper symptoms.")
    if "weight" in lower and not any(token in text for token in ("waist", "bmi", "calorie", "protein")):
        missing.append("BMI/waist, usual calories, protein intake, hunger timing, and activity level.")
    return _unique_strings(missing)[:8]


def _problem_specific_plan(
    problem: str,
    care_tasks: list[dict[str, Any]],
    reminders: list[str],
) -> list[str]:
    lower = problem.lower()
    if "sexual" in lower:
        base = [
            "Keep a private symptom log with date, trigger, pain level, discharge/bleeding changes, and medicine use.",
            "Upload any prescription, lab report, STI test, ultrasound, or clinician note after the call if available.",
            "Avoid self-medication for sexual-health symptoms until clinician review when infection, pregnancy risk, or severe pain is possible.",
            "Book clinician review if symptoms persist, repeat, worsen, or involve partner exposure.",
        ]
    elif "diabetes" in lower:
        base = [
            "Log fasting and post-meal glucose values with meal context.",
            "Use meal-photo checks for high-carbohydrate meals and late dinners.",
            "Track medicine timing and missed doses without changing dose unless a clinician advises it.",
            "Walk after major meals if safe and already tolerated.",
        ]
    elif "weight" in lower:
        base = [
            "Track weight trend weekly, not only one daily reading.",
            "Keep protein and fiber visible in each main meal.",
            "Use meal-photo checks for lunch/dinner portion review.",
            "Add walking or workout reminders based on realistic availability.",
        ]
    else:
        base = [
            "Track the main symptom or health metric daily for seven days.",
            "Keep reminders simple: one measurement, one habit, one follow-up.",
            "Upload reports or prescriptions so the next AI call uses real context.",
            "Review persistent or worsening symptoms with a clinician.",
        ]
    task_titles = [
        f"App task: {item.get('title')} - {item.get('detail')}"
        for item in care_tasks[:3]
        if item.get("title")
    ]
    reminder_titles = [f"Reminder: {line}" for line in reminders[:2]]
    return _unique_strings([*base, *task_titles, *reminder_titles])[:8]


def _problem_specific_doctor_questions(problem: str) -> list[str]:
    lower = problem.lower()
    if "sexual" in lower:
        return [
            "Do symptoms suggest infection, STI exposure, hormonal issue, medication side effect, or relationship/psychological trigger?",
            "Are STI testing, urine test, pregnancy test, pelvic/urology exam, or blood tests needed?",
            "Which symptoms should trigger urgent care: severe pain, fever, heavy bleeding, pregnancy concern, or assault/safety concern?",
            "Is any current medicine, supplement, or self-treatment unsafe to continue?",
        ]
    if "diabetes" in lower:
        return [
            "Should HbA1c, fasting glucose, post-meal glucose, kidney profile, lipids, or eye/foot screening be updated?",
            "Do medicines, meal timing, or hypoglycemia/hyperglycemia symptoms need clinician review?",
            "Which sugar range should this user target based on age, medicines, and comorbidities?",
        ]
    if "weight" in lower:
        return [
            "Is weight change medically safe for this user and current BMI/medical history?",
            "Should thyroid, glucose, cholesterol, liver, or vitamin labs be checked?",
            "Are hunger, sleep, mood, medicine, or hormonal factors blocking progress?",
        ]
    return [
        "Which diagnosis or differential needs clinician confirmation?",
        "Which tests, reports, or measurements should be uploaded next?",
        "Which symptom changes require urgent or emergency care?",
    ]


def _extract_reminder_lines(text: str, existing: list[str]) -> list[str]:
    lines = [str(line).strip() for line in (existing or []) if str(line).strip()]
    keyword_sentences = _sentences_with_keywords(
        text,
        ["reminder", "notify", "alarm", "medicine", "tablet", "meal photo", "water", "sleep", "walk", "exercise"],
    )
    lines.extend(line for line in keyword_sentences if _is_explicit_reminder_line(line))
    return _unique_strings(lines)[:10]


def _build_saved_reminders(problem: str, reminders: list[str]) -> list[dict[str, Any]]:
    defaults = [(13, 30), (20, 0), (7, 30), (22, 0)]
    records: list[dict[str, Any]] = []
    for index, line in enumerate(reminders[:8]):
        hour, minute = _time_from_text(line) or defaults[index % len(defaults)]
        title = _title_from_reminder(line)
        records.append(
            {
                "id": _stable_id("reminder", problem, title, str(hour), str(minute)),
                "title": title,
                "body": line[:220],
                "hour": hour,
                "minute": minute,
                "problemName": problem,
                "enabled": True,
                "createdAt": timezone.now().isoformat(),
                "updatedAt": timezone.now().isoformat(),
            }
        )
    return records


def _build_care_tasks(
    problem: str,
    reminders: list[str],
    health_logs: list[dict[str, Any]],
    text: str,
) -> list[dict[str, Any]]:
    tasks: list[dict[str, Any]] = []
    if health_logs:
        tasks.append(_task(problem, "measurement", "Log key health reading", "Repeat the captured measurement and track trend.", "Morning"))
    if "medicine" in text.lower() or "tablet" in text.lower():
        tasks.append(_task(problem, "medicine", "Confirm medicine dose", "Mark medicine as taken or skipped.", "As prescribed"))
    if "sleep" in text.lower():
        tasks.append(_task(problem, "sleep", "Sleep check", "Log last night's sleep quality and wake-up time.", "Morning"))
    for line in reminders[:3]:
        tasks.append(_task(problem, "custom", _title_from_reminder(line), line, _time_label_from_text(line)))
    return _dedupe_records(tasks, "id")[:10]


def _extract_health_logs(text: str, problem: str) -> list[dict[str, Any]]:
    records: list[dict[str, Any]] = []
    for match in re.finditer(r"\b(\d{2,3})\s*/\s*(\d{2,3})\b", text):
        value = f"{match.group(1)}/{match.group(2)}"
        records.append(_log(problem, "bloodPressure", "Blood pressure", value, "", "Captured from call transcript."))
    for match in re.finditer(r"\b(?:sugar|glucose|blood sugar)\D{0,20}(\d{2,3})\b", text, re.I):
        records.append(_log(problem, "glucose", "Blood sugar", match.group(1), "mg/dL", "Captured from call transcript."))
    for match in re.finditer(r"\b(\d{2,3}(?:\.\d+)?)\s*(?:kg|kilo|kilogram)\b", text, re.I):
        records.append(_log(problem, "weight", "Weight", match.group(1), "kg", "Captured from call transcript."))
    for match in re.finditer(r"\b(?:sleep|slept|neend)\D{0,20}(\d{1,2}(?:\.\d+)?)\s*(?:h|hr|hrs|hour|hours|ghanta)\b", text, re.I):
        records.append(_log(problem, "sleep", "Sleep", match.group(1), "hrs", "Captured from call transcript."))
    return _dedupe_records(records, "id")[:12]


def _extract_safety_events(text: str, problem: str) -> list[dict[str, Any]]:
    rules = [
        ("emergency", "Chest pain or breathing red flag", ["chest pain", "severe chest", "breathless", "difficulty breathing"]),
        ("emergency", "Fainting or unconsciousness red flag", ["faint", "unconscious", "behosh"]),
        ("urgent", "Severe bleeding or severe pain", ["heavy bleeding", "severe bleeding", "severe pain", "bahut dard"]),
        ("urgent", "Self-harm safety flag", ["suicide", "self harm", "kill myself"]),
    ]
    lowered = text.lower()
    events: list[dict[str, Any]] = []
    for severity, title, keywords in rules:
        matched = next((keyword for keyword in keywords if keyword in lowered), "")
        if not matched:
            continue
        if _is_negated_match(lowered, matched):
            continue
        events.append(
            {
                "id": _stable_id("safety", problem, title, matched),
                "problemName": problem,
                "source": "conversation_analysis",
                "severity": severity,
                "ruleId": _stable_id("rule", title),
                "title": title,
                "matchedText": matched,
                "action": "Seek urgent local medical care now." if severity == "emergency" else "Contact a clinician urgently.",
                "createdAt": timezone.now().isoformat(),
            }
        )
    return events


def _is_negated_match(text: str, matched: str) -> bool:
    index = text.find(matched)
    if index < 0:
        return False
    sentence_start = max(text.rfind(".", 0, index), text.rfind("\n", 0, index), 0)
    sentence_end_candidates = [
        pos for pos in (text.find(".", index), text.find("\n", index)) if pos >= 0
    ]
    sentence_end = min(sentence_end_candidates) if sentence_end_candidates else len(text)
    sentence = text[sentence_start:sentence_end]
    negations = (
        "no ",
        "not ",
        "none",
        "never",
        "nahi",
        "nahin",
        "nai ",
        "kuch nahi",
        "without",
    )
    return any(token in sentence for token in negations)


def _chat_records_from_transcript(transcript: list[dict[str, Any]], problem: str) -> list[dict[str, Any]]:
    records: list[dict[str, Any]] = []
    for index, item in enumerate(transcript if isinstance(transcript, list) else []):
        if not isinstance(item, dict):
            continue
        text = str(item.get("text") or "").strip()
        if not text:
            continue
        role = str(item.get("role") or "user").strip().lower()
        records.append(
            {
                "id": _stable_id("chat", problem, str(index), role, text[:120]),
                "problemName": problem,
                "role": "user" if role == "user" else "assistant",
                "text": text,
                "isError": False,
                "createdAt": str(item.get("createdAt") or item.get("created_at") or timezone.now().isoformat()),
            }
        )
    return records


def _normalise_app_records(value: Any, problem: str, *, record_type: str) -> list[dict[str, Any]]:
    records = [dict(item) for item in value if isinstance(item, dict)] if isinstance(value, list) else []
    now = timezone.now().isoformat()
    normalised: list[dict[str, Any]] = []
    for index, item in enumerate(records[:20]):
        clean = dict(item)
        clean.setdefault("problemName", clean.get("problem_name") or problem)
        clean.setdefault("createdAt", now)
        clean.setdefault("updatedAt", now)
        clean.setdefault("enabled", True)
        if record_type == "reminder":
            clean["hour"] = _bounded_int(clean.get("hour"), 8, 0, 23)
            clean["minute"] = _bounded_int(clean.get("minute"), 0, 0, 59)
            clean.setdefault("title", "Flicko reminder")
            clean.setdefault("body", clean.get("title", "Flicko health reminder"))
        elif record_type == "task":
            clean.setdefault("type", "custom")
            clean.setdefault("title", "Care task")
            clean.setdefault("detail", "")
            clean.setdefault("timeLabel", "")
        elif record_type == "log":
            clean.setdefault("type", "symptom")
            clean.setdefault("title", "Health log")
            clean.setdefault("value", "")
            clean.setdefault("unit", "")
            clean.setdefault("note", "")
        elif record_type == "safety":
            clean.setdefault("source", "conversation_analysis")
            clean.setdefault("severity", "clinician")
            clean.setdefault("title", "Safety note")
            clean.setdefault("matchedText", "")
            clean.setdefault("action", "Review with a clinician if symptoms continue.")
        clean.setdefault("id", _stable_id(record_type, problem, str(index), json.dumps(clean, sort_keys=True, default=str)))
        normalised.append(clean)
    return normalised


def _log(problem: str, log_type: str, title: str, value: str, unit: str, note: str) -> dict[str, Any]:
    return {
        "id": _stable_id("log", problem, log_type, value, unit),
        "type": log_type,
        "title": title,
        "value": value,
        "unit": unit,
        "note": note,
        "problemName": problem,
        "createdAt": timezone.now().isoformat(),
    }


def _task(problem: str, task_type: str, title: str, detail: str, time_label: str) -> dict[str, Any]:
    return {
        "id": _stable_id("task", problem, task_type, title, time_label),
        "type": task_type,
        "title": title,
        "detail": detail,
        "timeLabel": time_label,
        "problemName": problem,
        "enabled": True,
        "createdAt": timezone.now().isoformat(),
        "updatedAt": timezone.now().isoformat(),
    }


def _score_from_data(
    dashboard_values: dict[str, Any],
    safety_events: list[dict[str, Any]],
    health_logs: list[dict[str, Any]],
) -> int:
    for key in ("score", "health_score", "daily_score"):
        value = dashboard_values.get(key)
        try:
            return max(0, min(100, int(float(str(value)))))
        except (TypeError, ValueError):
            continue
    if any(event.get("severity") == "emergency" for event in safety_events):
        return 42
    if any(event.get("severity") == "urgent" for event in safety_events):
        return 58
    if health_logs:
        return 76
    return 72


def _primary_metric_value(problem: str, logs: list[dict[str, Any]]) -> str:
    if logs:
        latest = logs[0]
        return str(latest.get("value") or "")
    lower = problem.lower()
    if "weight" in lower:
        return "Track weight"
    if "diabetes" in lower:
        return "Track glucose"
    if "pressure" in lower or "bp" in lower:
        return "Track BP"
    return "Track daily check-in"


def _primary_metric_unit(problem: str, logs: list[dict[str, Any]]) -> str:
    if logs:
        return str(logs[0].get("unit") or "")
    lower = problem.lower()
    if "diabetes" in lower:
        return "mg/dL"
    if "weight" in lower:
        return "kg"
    return ""


def _plan_focus(problem: str, tasks: list[dict[str, Any]]) -> str:
    if tasks:
        return str(tasks[0].get("title") or "Daily care task")
    lower = problem.lower()
    if "diabetes" in lower:
        return "Meal timing and glucose pattern"
    if "weight" in lower:
        return "Meal photo, protein, steps, and sleep"
    if "sexual" in lower:
        return "Private symptom timeline and clinician-safe follow-up"
    return "Daily symptoms, routines, reminders, and reports"


def _sentences_with_keywords(text: str, keywords: list[str]) -> list[str]:
    pieces = re.split(r"[\n.!?]+", text)
    matches: list[str] = []
    for piece in pieces:
        clean = _clean(piece)
        lower = clean.lower()
        if clean and any(keyword in lower for keyword in keywords):
            matches.append(clean[:220])
    return _unique_strings(matches)


def _is_explicit_reminder_line(text: str) -> bool:
    clean = _clean(text)
    lower = clean.lower()
    if len(clean) < 8 or len(clean) > 220:
        return False
    if re.search(r"\b(no|not|don't|do not|without|if you want|can be|could be|later|after more details)\b", lower):
        return False
    has_explicit_intent = any(
        token in lower
        for token in ("reminder", "notify", "alarm", "call me", "remind me")
    )
    has_time = _time_from_text(clean) is not None or re.search(
        r"\b(morning|evening|night|lunch|dinner|breakfast|bedtime)\b",
        lower,
    )
    has_action = re.search(
        r"\b(meal|photo|medicine|tablet|water|walk|exercise|sleep|steps|bp|sugar|glucose|weight|log|check|drink|take|upload)\b",
        lower,
    )
    return has_explicit_intent and (has_time or has_action is not None)


def _time_from_text(text: str) -> tuple[int, int] | None:
    match = re.search(r"\b(\d{1,2})(?::(\d{2}))?\s*(am|pm)\b", text, re.I)
    if match:
        hour = int(match.group(1))
        minute = int(match.group(2) or "0")
        meridiem = match.group(3).lower()
        if meridiem == "pm" and hour < 12:
            hour += 12
        if meridiem == "am" and hour == 12:
            hour = 0
        if 0 <= hour <= 23 and 0 <= minute <= 59:
            return hour, minute
    match = re.search(r"\b([01]?\d|2[0-3]):([0-5]\d)\b", text)
    if match:
        return int(match.group(1)), int(match.group(2))
    return None


def _time_label_from_text(text: str) -> str:
    parsed = _time_from_text(text)
    if parsed is None:
        return "Daily"
    hour, minute = parsed
    suffix = "PM" if hour >= 12 else "AM"
    display_hour = hour % 12 or 12
    return f"{display_hour}:{minute:02d} {suffix}"


def _title_from_reminder(text: str) -> str:
    clean = _clean(text)
    if len(clean) <= 34:
        return clean or "Flicko reminder"
    return clean[:31].rstrip(" ,.-") + "..."


def _primary_problem(user: User) -> str:
    profile = getattr(user, "profile", None)
    selected = getattr(profile, "selected_problems", []) if profile else []
    if isinstance(selected, list) and selected:
        first = str(selected[0]).strip()
        if first:
            return first
    return "General health"


def _extract_json_object(text: str) -> dict[str, Any] | None:
    start = text.find("{")
    end = text.rfind("}")
    if start < 0 or end <= start:
        return None
    try:
        value = json.loads(text[start : end + 1])
    except json.JSONDecodeError as exc:
        logger.warning("Groq analysis JSON parse failed: %s", exc)
        return None
    return value if isinstance(value, dict) else None


def _dict(value: Any) -> dict[str, Any]:
    return dict(value) if isinstance(value, dict) else {}


def _string_list(value: Any) -> list[str]:
    if not isinstance(value, list):
        return []
    return _unique_strings(str(item).strip() for item in value if str(item).strip())


def _unique_strings(values) -> list[str]:
    seen: set[str] = set()
    result: list[str] = []
    for value in values:
        clean = _clean(str(value))
        if not clean or clean.lower() in seen:
            continue
        seen.add(clean.lower())
        result.append(clean)
    return result


def _dedupe_records(records: list[dict[str, Any]], key: str) -> list[dict[str, Any]]:
    seen: set[str] = set()
    result: list[dict[str, Any]] = []
    for record in records:
        marker = str(record.get(key) or record).lower()
        if marker in seen:
            continue
        seen.add(marker)
        result.append(record)
    return result


def _bounded_int(value: Any, fallback: int, lower: int, upper: int) -> int:
    try:
        parsed = int(float(str(value)))
    except (TypeError, ValueError):
        parsed = fallback
    return max(lower, min(upper, parsed))


def _clean(value: str) -> str:
    return re.sub(r"\s+", " ", value).strip()


def _stable_id(*parts: str) -> str:
    raw = "|".join(str(part) for part in parts)
    return hashlib.sha256(raw.encode("utf-8")).hexdigest()[:28]
