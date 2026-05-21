from __future__ import annotations

from base64 import b64encode
from collections.abc import Iterable
from dataclasses import dataclass
import mimetypes
from pathlib import Path
import re
from typing import Any

from django.conf import settings
from django.template.loader import render_to_string

from .report_extractors import (
    _EXPLICIT_CONDITION_KEYS,
    _condition_schema,
    _condition_evidence,
    _problem_key,
    _symptom_rows_for_problem,
)
from .report_templates import (
    ReportBoxSpec,
    ReportPageSpec,
    ReportTemplate,
    box_spec,
    page_specs_for_problem,
    template_for_problem,
    template_slug,
)


@dataclass(frozen=True)
class MarkdownSection:
    title: str
    body: tuple[str, ...]
    bullets: tuple[str, ...]


def parse_markdown_sections(markdown: str) -> tuple[MarkdownSection, ...]:
    text = _clean_text(markdown or "")
    if not text.strip():
        return ()

    sections: list[MarkdownSection] = []
    current_title = "Summary"
    body_parts: list[str] = []
    bullets: list[str] = []
    paragraph: list[str] = []

    def flush() -> None:
        nonlocal body_parts, bullets, paragraph
        if paragraph:
            body_parts.append(" ".join(paragraph).strip())
            paragraph = []
        if body_parts or bullets:
            sections.append(
                MarkdownSection(
                    title=current_title.strip() or "Summary",
                    body=tuple(item for item in body_parts if item),
                    bullets=tuple(item for item in bullets if item),
                )
            )
        body_parts = []
        bullets = []

    for raw_line in text.splitlines():
        line = raw_line.strip()
        if line.startswith("## "):
            flush()
            current_title = line[3:].strip() or "Summary"
            continue
        if not line:
            if paragraph:
                body_parts.append(" ".join(paragraph).strip())
                paragraph = []
            continue
        if line.startswith("- "):
            if paragraph:
                body_parts.append(" ".join(paragraph).strip())
                paragraph = []
            bullets.append(line[2:].strip())
            continue
        paragraph.append(line)

    flush()
    return tuple(sections)


def build_health_report_html(report) -> str:
    template = template_for_problem(getattr(report, "problem_name", "") or getattr(report, "title", ""))
    slug = template_slug(template)
    values = getattr(report, "dashboard_values", {})
    if not isinstance(values, dict):
        values = {}
    markdown = (
        getattr(report, "report_markdown", None)
        or getattr(report, "intake_summary", "")
        or ""
    )
    sections = parse_markdown_sections(markdown)
    reminders = _string_list(getattr(report, "reminders", ()))
    transcript_notes = _transcript_notes(getattr(report, "transcript", ()))
    pair_lookup = _pair_lookup(values, sections)
    score = _score_value(values)
    score_css = score if score is not None else 0
    has_score = score is not None

    badge = 1
    page_specs = page_specs_for_problem(template.problem_name)
    cover_page, badge = _build_page(
        page_specs[0],
        badge_start=badge,
        template=template,
        values=values,
        sections=sections,
        reminders=reminders,
        transcript_notes=transcript_notes,
        pair_lookup=pair_lookup,
        score=score,
    )
    detail_pages: list[dict[str, Any]] = []
    for spec in page_specs[1:]:
        page, badge = _build_page(
            spec,
            badge_start=badge,
            template=template,
            values=values,
            sections=sections,
            reminders=reminders,
            transcript_notes=transcript_notes,
            pair_lookup=pair_lookup,
            score=score,
        )
        detail_pages.append(page)

    context = {
        "report": report,
        "template": template,
        "slug": slug,
        "common_css": _load_css("common_report.css"),
        "report_css": _load_css(f"{slug}_report.css"),
        "logo_uri": _asset_data_uri("mainlogo.png"),
        "coach_uri": _asset_data_uri("dashboard", "live_coach.png"),
        "scale_uri": _asset_data_uri("dashboard", "weight_scale.png"),
        "meal_uri": _asset_data_uri("dashboard", "meal_plan.png"),
        "problem_uri": _asset_data_uri("problems", template.asset_name),
        "generated_for": _generated_for(report),
        "report_date": _report_date(report),
        "score": score,
        "score_css": score_css,
        "has_score": has_score,
        "score_phrase": _score_phrase(score),
        "executive_highlights": _executive_highlights(template, values, pair_lookup, reminders, score),
        "cover_page": cover_page,
        "detail_pages": detail_pages,
        "dashboard_items": _dashboard_items(template, values, pair_lookup, score),
        "focus_items": template.focus_areas,
        "transcript_notes": transcript_notes or ("No conversation transcript was saved with this report.",),
        "missing_info_items": _missing_info_items(sections),
        "safety_boundary": _safety_boundary(sections),
    }
    return render_to_string(f"accounts/reports/{slug}_report.html", context)


def _build_page(
    spec: ReportPageSpec,
    *,
    badge_start: int,
    template: ReportTemplate,
    values: dict[str, Any],
    sections: tuple[MarkdownSection, ...],
    reminders: tuple[str, ...],
    transcript_notes: tuple[str, ...],
    pair_lookup: dict[str, str],
    score: int | None,
) -> tuple[dict[str, Any], int]:
    boxes: list[dict[str, Any]] = []
    badge = badge_start
    for box_id in spec.box_ids:
        boxes.append(
            _build_box(
                box_spec(box_id),
                badge=badge,
                template=template,
                values=values,
                sections=sections,
                reminders=reminders,
                transcript_notes=transcript_notes,
                pair_lookup=pair_lookup,
                score=score,
            )
        )
        badge += 1
    return {
        "page_id": spec.page_id,
        "eyebrow": spec.eyebrow,
        "title": spec.title,
        "chip": spec.chip,
        "boxes": boxes,
    }, badge


def _build_box(
    spec: ReportBoxSpec,
    *,
    badge: int,
    template: ReportTemplate,
    values: dict[str, Any],
    sections: tuple[MarkdownSection, ...],
    reminders: tuple[str, ...],
    transcript_notes: tuple[str, ...],
    pair_lookup: dict[str, str],
    score: int | None,
) -> dict[str, Any]:
    if spec.kind == "metrics":
        metrics = _metrics_for_box(spec, template, values, pair_lookup, score)
        captured = any(not item["missing"] for item in metrics)
        return {
            "box_id": spec.box_id,
            "badge": f"{badge:02d}",
            "title": spec.title,
            "kind": spec.kind,
            "tone": spec.tone,
            "lead": (
                "Saved dashboard values only. Nothing is invented in this report."
                if captured
                else "No structured metric was captured yet. Add logs or reports to populate this box."
            ),
            "metrics": metrics,
        }

    matched_sections = _matched_sections(spec, sections)
    lead, items = _section_lead_and_items(matched_sections)
    if spec.kind in {"table", "meal_plan", "week_plan"}:
        headers, rows, note = _structured_table(
            spec,
            template=template,
            values=values,
            sections=sections,
            matched_sections=matched_sections,
            reminders=reminders,
            transcript_notes=transcript_notes,
            pair_lookup=pair_lookup,
            score=score,
        )
        return {
            "box_id": spec.box_id,
            "badge": f"{badge:02d}",
            "title": spec.title,
            "kind": spec.kind,
            "tone": spec.tone,
            "lead": lead or _default_lead(spec),
            "headers": headers,
            "rows": rows,
            "note": note,
        }
    if spec.kind == "timeline":
        if not items:
            items = _timeline_fallback(spec, reminders, transcript_notes)
        return {
            "box_id": spec.box_id,
            "badge": f"{badge:02d}",
            "title": spec.title,
            "kind": spec.kind,
            "tone": spec.tone,
            "lead": lead or _default_lead(spec),
            "items": items,
        }
    if spec.kind == "doctor":
        doctor_items = items or tuple(template.doctor_questions)
        return {
            "box_id": spec.box_id,
            "badge": f"{badge:02d}",
            "title": spec.title,
            "kind": spec.kind,
            "tone": spec.tone,
            "lead": lead or "Questions below are formatted for a clinician discussion.",
            "items": doctor_items,
        }

    if not items:
        items = _bullet_fallback(spec, template, reminders, transcript_notes, sections)
    return {
        "box_id": spec.box_id,
        "badge": f"{badge:02d}",
        "title": spec.title,
        "kind": spec.kind,
        "tone": spec.tone,
        "lead": lead or _default_lead(spec),
        "items": items,
    }


def _metrics_for_box(
    spec: ReportBoxSpec,
    template: ReportTemplate,
    values: dict[str, Any],
    pair_lookup: dict[str, str],
    score: int | None,
) -> tuple[dict[str, Any], ...]:
    entries: list[tuple[str, str, bool]] = []
    seen: set[str] = set()

    def add(label: str, value: str | None, *, missing_fallback: str = "Not captured yet.") -> None:
        normalized = _normalize(label)
        if normalized in seen:
            return
        seen.add(normalized)
        if value:
            entries.append((label, value, False))
        else:
            entries.append((label, missing_fallback, True))

    if spec.box_id == "trend_summary" and score is not None:
        add(template.score_label, f"{score}/100")
    metric_value = _metric_value(values)
    if metric_value:
        add(template.metric_labels[0] if template.metric_labels else "Captured metric", metric_value)
    if spec.box_id == "trend_summary":
        add("Status", _string_value(values.get("metric_status")))
        add("Plan focus", _string_value(values.get("plan_focus")))
        add("Daily goal", _string_value(values.get("daily_goal")))

    labels = template.metric_labels[:5] if spec.box_id == "trend_summary" else template.metric_labels[:4]
    for label in labels:
        add(label, _lookup_pair(label, pair_lookup))

    if spec.box_id == "snapshot_strip" and _string_value(values.get("primary_problem")):
        add("Primary problem", _string_value(values.get("primary_problem")))

    metrics = [
        {"label": label, "value": value, "missing": missing}
        for label, value, missing in entries[:6]
    ]
    if not metrics:
        metrics = [{"label": "Data", "value": "No structured values saved yet.", "missing": True}]
    return tuple(metrics)


def _matched_sections(spec: ReportBoxSpec, sections: tuple[MarkdownSection, ...]) -> tuple[MarkdownSection, ...]:
    matches: list[MarkdownSection] = []
    exact = _normalize(spec.title)
    extra_keywords = list(spec.keywords)
    if spec.box_id == "referral_next_steps":
        extra_keywords.extend(("missing information", "follow-up", "doctor-ready questions"))
    if spec.box_id == "plan_tracker":
        extra_keywords.extend(("app care task", "tracking plan"))
    if spec.box_id == "meds_adherence":
        extra_keywords.extend(("current routine", "routine, medicines"))
    if spec.box_id == "routine_review":
        extra_keywords.extend(("current routine", "meal", "sleep"))
    for section in sections:
        title = _normalize(section.title)
        if title == exact:
            matches.append(section)
            continue
        if any(_normalize(keyword) in title for keyword in extra_keywords):
            matches.append(section)
    return tuple(matches)


def _section_lead_and_items(sections: tuple[MarkdownSection, ...]) -> tuple[str | None, tuple[str, ...]]:
    if not sections:
        return None, ()
    lead: str | None = None
    items: list[str] = []
    for section in sections:
        if section.body and lead is None:
            lead = section.body[0]
            items.extend(section.body[1:])
        elif section.body:
            items.extend(section.body)
        items.extend(section.bullets)
    if not items and lead:
        items = [lead]
        lead = None
    return lead, _unique(items)[:6]


def _timeline_fallback(
    spec: ReportBoxSpec,
    reminders: tuple[str, ...],
    transcript_notes: tuple[str, ...],
) -> tuple[str, ...]:
    if spec.box_id == "plan_tracker" and reminders:
        return reminders[:6]
    if transcript_notes:
        return transcript_notes[:4]
    return ("No timeline details were captured yet.",)


def _bullet_fallback(
    spec: ReportBoxSpec,
    template: ReportTemplate,
    reminders: tuple[str, ...],
    transcript_notes: tuple[str, ...],
    sections: tuple[MarkdownSection, ...],
) -> tuple[str, ...]:
    if spec.box_id == "chief_concern":
        source = transcript_notes[:4] or _summary_sentences(sections)[:4]
        return source or ("The main concern was not structured clearly in the saved intake yet.",)
    if spec.box_id == "safety_review":
        return ("No emergency red flag was detected from the saved intake summary.",)
    if spec.box_id == "labs_testing_history":
        return ("No lab report, test result, or prescription upload was captured yet.",)
    if spec.box_id == "meds_adherence":
        return ("Medicine names, doses, and timing still need confirmation.",)
    if spec.box_id == "referral_next_steps":
        return (
            "Book clinician review if symptoms persist, worsen, or new red flags appear.",
            "Carry this report, any prescription, and recent test results to the appointment.",
        )
    if spec.box_id == "support_context":
        return ("Support-system details were not fully captured yet.",)
    if spec.box_id == "risk_factors":
        return ("Family history and major risk factors were not fully captured yet.",)
    if spec.box_id == "exercise_readiness":
        return ("Workout tolerance, pain triggers, and recovery status were not fully captured yet.",)
    if spec.box_id == "habit_loop":
        return ("Trigger, routine, and reward pattern still need clearer logging.",)
    if spec.box_id == "exposure_context":
        return ("Partner, exposure, contraception, and consent context were not fully captured yet.",)
    if spec.box_id == "trigger_context":
        lines = reminders[:3]
        if lines:
            return tuple(f"Reminder context: {line}" for line in lines)
        return tuple(f"{focus}: needs clearer tracking." for focus in template.focus_areas[:3])
    if spec.box_id == "routine_review":
        return ("Meal, sleep, hydration, and medicine routine details were not fully captured yet.",)
    if spec.box_id == "symptom_cluster":
        return ("Symptom pattern is still too sparse. Capture timing, severity, and triggers next.",)
    return ("No structured detail was captured for this box yet.",)


def _default_lead(spec: ReportBoxSpec) -> str:
    if spec.box_id == "chief_concern":
        return "This summary is pulled from the saved intake note and recent transcript."
    if spec.box_id == "safety_review":
        return "Escalation cues are listed below exactly as saved in the intake summary."
    if spec.box_id == "monitoring_table":
        return "This table uses saved dashboard values first, then converts them into a usable follow-up snapshot."
    if spec.box_id == "symptom_review_table":
        return "Symptoms are organized into a clinical format so the report reads like a real case summary."
    if spec.box_id == "testing_followup_table":
        return "These are suggested review items based on the reported condition, not a diagnosis."
    if spec.box_id == "medicine_schedule_table":
        return "Use this to reconcile actual prescriptions, timing, and adherence gaps."
    if spec.box_id == "trigger_response_table":
        return "Triggers are paired with practical responses so the report becomes actionable."
    if spec.box_id == "recovery_checklist_table":
        return "This checklist highlights what to track daily and what should trigger escalation."
    if spec.box_id == "training_split_table":
        return "The split below is structured for progression without making the report look like a generic card deck."
    if spec.box_id == "habit_reset_table":
        return "The loop is reframed as a practical tracker rather than a generic behavior summary."
    if spec.box_id == "meal_plan_table":
        return "This is a suggested structure built from the condition focus and any saved routine data."
    if spec.box_id == "week_plan_table":
        return "The next seven days are laid out in a real operational sequence, not as loose reminder bullets."
    if spec.box_id == "plan_tracker":
        return "These are the next actions already recorded for the coming week."
    if spec.box_id == "doctor_questions":
        return "Use these points directly during a clinician conversation."
    return "This card uses only saved intake content, reminders, and dashboard values."


def _structured_table(
    spec: ReportBoxSpec,
    *,
    template: ReportTemplate,
    values: dict[str, Any],
    sections: tuple[MarkdownSection, ...],
    matched_sections: tuple[MarkdownSection, ...],
    reminders: tuple[str, ...],
    transcript_notes: tuple[str, ...],
    pair_lookup: dict[str, str],
    score: int | None,
) -> tuple[tuple[str, ...], tuple[tuple[str, ...], ...], str | None]:
    if spec.kind == "meal_plan":
        return _meal_plan_table(template, values, pair_lookup)
    if spec.kind == "week_plan":
        return _week_plan_table(template, values, reminders)
    if spec.box_id == "monitoring_table":
        return _monitoring_table(template, values, pair_lookup, score)
    if spec.box_id == "symptom_review_table":
        return _symptom_review_table(
            template,
            values,
            sections,
            matched_sections,
            transcript_notes,
            pair_lookup,
        )
    if spec.box_id == "testing_followup_table":
        return _testing_followup_table(template)
    if spec.box_id == "medicine_schedule_table":
        return _medicine_schedule_table(
            template,
            values,
            pair_lookup,
            sections,
            matched_sections,
            transcript_notes,
        )
    if spec.box_id == "trigger_response_table":
        return _trigger_response_table(template)
    if spec.box_id == "recovery_checklist_table":
        return _recovery_checklist_table(template)
    if spec.box_id == "training_split_table":
        return _training_split_table(values)
    if spec.box_id == "habit_reset_table":
        return _habit_reset_table(template, reminders)
    return (
        ("Section", "Saved detail", "Next action"),
        (("No structured table", "No row builder matched this box yet.", "Review report template mapping."),),
        None,
    )




def _monitoring_table(
    template: ReportTemplate,
    values: dict[str, Any],
    pair_lookup: dict[str, str],
    score: int | None,
) -> tuple[tuple[str, ...], tuple[tuple[str, ...], ...], str | None]:
    rows: list[tuple[str, str, str]] = []

    def add(label: str, captured: str | None, guidance: str, *, fallback: str = "Not captured yet.") -> None:
        rows.append((label, captured or fallback, guidance))

    if score is not None:
        add(template.score_label, f"{score}/100", "Use this as a routine snapshot only; trends matter more than one score.")

    metric_value = _metric_value(values)
    labels = template.metric_labels[:3]
    if labels:
        add(labels[0], metric_value or _lookup_pair(labels[0], pair_lookup), _monitoring_hint(template.problem_name, labels[0]))
    for label in labels[1:]:
        add(label, _lookup_pair(label, pair_lookup), _monitoring_hint(template.problem_name, label))

    add(
        "Primary goal",
        _string_value(values.get("daily_goal")) or _string_value(values.get("plan_focus")),
        "This should be the single anchor for the next weekly review.",
    )
    return (
        ("Area", "Current record", "How to use it"),
        tuple(rows[:5]),
        "All values shown here come from saved dashboard fields or uploaded intake context.",
    )


def _symptom_review_table(
    template: ReportTemplate,
    values: dict[str, Any],
    sections: tuple[MarkdownSection, ...],
    matched_sections: tuple[MarkdownSection, ...],
    transcript_notes: tuple[str, ...],
    pair_lookup: dict[str, str],
) -> tuple[tuple[str, ...], tuple[tuple[str, ...], ...], str | None]:
    extracted = _condition_evidence(
        template.problem_name,
        values=values,
        sections=sections,
        matched_sections=matched_sections,
        transcript_notes=transcript_notes,
        pair_lookup=pair_lookup,
    )
    captures = list(_summary_sentences(matched_sections) or transcript_notes or _summary_sentences(sections))
    return (
        ("Clinical area", "What was captured", "What still matters"),
        _symptom_rows_for_problem(template.problem_name, extracted, captures),
        "Missing cells mean the intake needs clearer timing, severity, or trigger documentation.",
    )


def _testing_followup_table(template: ReportTemplate) -> tuple[tuple[str, ...], tuple[tuple[str, ...], ...], str | None]:
    return (
        ("Review item", "Why it matters", "Suggested timing"),
        tuple(_testing_items(template.problem_name)),
        "Suggested timing is a planning aid. Clinical urgency still depends on red flags and clinician judgment.",
    )


def _medicine_schedule_table(
    template: ReportTemplate,
    values: dict[str, Any],
    pair_lookup: dict[str, str],
    sections: tuple[MarkdownSection, ...],
    matched_sections: tuple[MarkdownSection, ...],
    transcript_notes: tuple[str, ...],
) -> tuple[tuple[str, ...], tuple[tuple[str, ...], ...], str | None]:
    extracted = _condition_evidence(
        template.problem_name,
        values=values,
        sections=sections,
        matched_sections=matched_sections,
        transcript_notes=transcript_notes,
        pair_lookup=pair_lookup,
    )
    captured_lines = list(_summary_sentences(matched_sections))
    medicine_names = (
        _string_value(values.get("medicine"))
        or _string_value(values.get("medicines"))
        or _lookup_pair("Medicine", pair_lookup)
        or _lookup_pair("Medication", pair_lookup)
        or extracted.medicine
    )
    timing = (
        _string_value(values.get("medicine_timing"))
        or _lookup_pair("Timing", pair_lookup)
        or _lookup_pair("Meal timing", pair_lookup)
        or extracted.timing
    )
    side_effects = extracted.side_effects or (captured_lines[0] if captured_lines else "")
    rows = (
        ("Current medicines", medicine_names or "No medicine list saved yet.", "Verify exact name, dose, and who prescribed it."),
        ("Timing window", timing or "Timing not recorded yet.", _medicine_timing_hint(template.problem_name)),
        ("Missed dose plan", _string_value(values.get("missed_dose")) or "No missed-dose instruction saved.", "Document what to do after a missed dose instead of guessing later."),
        ("Side-effect watch", side_effects or "No side-effect note saved yet.", _side_effect_watch(template.problem_name)),
    )
    return (
        ("Treatment item", "Current note", "What to verify"),
        rows,
        "If prescriptions exist, the written label always overrides this summary.",
    )


def _trigger_response_table(template: ReportTemplate) -> tuple[tuple[str, ...], tuple[tuple[str, ...], ...], str | None]:
    return (
        ("Trigger or context", "Likely effect", "Recommended response"),
        tuple(_trigger_items(template.problem_name)),
        "These are practical responses suitable for a coaching report; escalate if symptoms become severe.",
    )


def _recovery_checklist_table(template: ReportTemplate) -> tuple[tuple[str, ...], tuple[tuple[str, ...], ...], str | None]:
    return (
        ("Recovery area", "Track daily", "Escalate when"),
        tuple(_recovery_items(template.problem_name)),
        "This checklist is for structured observation, not for delaying urgent care.",
    )


def _training_split_table(values: dict[str, Any]) -> tuple[tuple[str, ...], tuple[tuple[str, ...], ...], str | None]:
    rows = (
        ("Day A", "Strength base: 4-6 compound movements, controlled sets, no all-out finish.", "Log pain, form breakdown, and next-day soreness."),
        ("Day B", "Zone-2 cardio plus mobility block.", "Keep pace conversational and finish with stretch work."),
        ("Day C", "Strength progression or technique refinement.", "Increase only one variable: load, reps, or total sets."),
        ("Day D", "Active recovery, sleep catch-up, and tissue care.", _string_value(values.get("daily_goal")) or "Use this day to protect consistency, not to chase intensity."),
    )
    return (
        ("Training block", "Planned focus", "Coach note"),
        rows,
        "This split assumes no acute injury, chest symptoms, or exercise contraindication.",
    )


def _habit_reset_table(
    template: ReportTemplate,
    reminders: tuple[str, ...],
) -> tuple[tuple[str, ...], tuple[tuple[str, ...], ...], str | None]:
    cue = reminders[0] if reminders else "Use one visible cue in the environment."
    rows = (
        ("Trigger", "Identify the exact time, place, or emotion that starts the unwanted pattern.", "A vague trigger cannot be redesigned."),
        ("Replacement action", "Choose a 2-minute version of the preferred behavior.", "The substitute must be easier than the old habit."),
        ("Cue / reminder", cue, "The cue should be external and difficult to ignore."),
        ("Reward / review", "Close the loop with a check mark, short note, or visible streak.", "Track consistency before intensity."),
    )
    return (
        ("Habit-loop step", "Current design", "Upgrade"),
        rows,
        "The goal is friction reduction and repeatability, not willpower theater.",
    )


def _meal_plan_table(
    template: ReportTemplate,
    values: dict[str, Any],
    pair_lookup: dict[str, str],
) -> tuple[tuple[str, ...], tuple[tuple[str, ...], ...], str | None]:
    problem_key = _problem_key(template.problem_name)
    variant_key = {
        "pcos": "hormone",
        "thyroid": "hormone",
        "women": "hormone",
        "skin": "hormone",
        "autoimmune": "hormone",
    }.get(problem_key, problem_key)
    plan_focus = _string_value(values.get("plan_focus")) or "Follow the condition-specific focus noted in this report."
    daily_goal = _string_value(values.get("daily_goal")) or "Repeat the same structure daily before adding complexity."
    plan_map = {
        "weight": (
            ("Morning", "Water, weigh-in if prescribed, then delay grazing.", "Avoid starting the day with sugary drinks."),
            ("Breakfast", "Protein first: eggs, Greek yogurt, tofu, or dal-based option.", "If hunger returns early, breakfast was too low in protein or fiber."),
            ("Lunch", "Half plate vegetables, quarter protein, quarter starch.", "Photograph or log the plate to catch hidden calories."),
            ("Evening", "Fruit + nuts / curd instead of random snacking.", "Protect the high-craving window, do not rely on willpower."),
            ("Dinner", "Earlier, lighter, and protein anchored.", daily_goal),
        ),
        "diabetes": (
            ("Morning", "Check fasting value if advised, hydrate, and do not skip breakfast.", "Use the same morning meal pattern on most days."),
            ("Breakfast", "Controlled carb plus protein: oats + eggs, dal chilla, tofu, or unsweetened yogurt.", "Post-breakfast spike is the first pattern to review."),
            ("Lunch", "Measured carbohydrate, vegetables, and reliable protein.", "Pair meals with medicine/insulin timing already prescribed."),
            ("Evening", "Small snack only if needed: nuts, sprouts, boiled chana, or curd.", "Prevent long gaps that trigger overeating."),
            ("Dinner", "Finish earlier and walk 10-15 minutes after the meal if safe.", plan_focus),
        ),
        "bp": (
            ("Morning", "Hydration first; avoid salty packaged breakfast options.", "Morning BP should be measured under the same conditions."),
            ("Breakfast", "Low-salt, high-potassium plate with protein.", "Watch hidden sodium in breads, sauces, and ready-to-eat foods."),
            ("Lunch", "Home-style meal with vegetables, pulses, lean protein, and modest starch.", "Restaurant and takeaway meals distort BP control quickly."),
            ("Evening", "Unsalted snack and caffeine cutoff if pressure rises with stress.", "Do not pair stress with processed snacks."),
            ("Dinner", "Light dinner, no extra table salt, no heavy late-night meal.", daily_goal),
        ),
        "heart": (
            ("Morning", "Hydrate and avoid tobacco or energy drinks.", "Any chest symptom changes override the meal plan."),
            ("Breakfast", "Oats, fruit, nuts, and protein with minimal saturated fat.", "Use labels to spot salt and trans fat."),
            ("Lunch", "Vegetables, beans or lean protein, whole grains, and limited fried food.", "Keep restaurant meals exceptional, not routine."),
            ("Evening", "Fruit, nuts, or curd rather than packaged snacks.", "Avoid heavy evening intake if breathlessness or reflux follows."),
            ("Dinner", "Smaller portions, less oil, and finish early.", plan_focus),
        ),
        "hormone": (
            ("Morning", "Hydrate and anchor wake time before caffeine.", "Consistency is more important than perfection."),
            ("Breakfast", "Protein + fiber breakfast to reduce cravings and hormone-related energy dips.", "Skipping breakfast often worsens cravings later."),
            ("Lunch", "Steady plate: vegetables, pulses or protein, and moderate carbs.", "Use lunch as the most stable meal of the day."),
            ("Evening", "Planned snack if cravings are frequent; prefer protein or fruit over sweets.", "Cravings are data, not a character flaw."),
            ("Dinner", "Earlier dinner with less refined starch and enough protein.", daily_goal),
        ),
        "pregnancy": (
            ("Morning", "Hydration, small tolerated food first if nausea is present.", "Escalate if vomiting or low intake persists."),
            ("Breakfast", "Protein plus complex carbs; avoid long gaps between meals.", "Frequent small meals can control nausea better than large ones."),
            ("Lunch", "Iron, protein, vegetables, and calcium support somewhere in the day.", "Food safety matters as much as nutrition quality."),
            ("Evening", "Fruit, nuts, milk/curd, or other clinician-safe snack.", "Hydration should continue through the afternoon."),
            ("Dinner", "Lighter dinner with reflux awareness and early finish if possible.", plan_focus),
        ),
        "postpartum": (
            ("Morning", "Hydrate early and eat before exhaustion builds.", "Low intake worsens recovery and feeding stamina."),
            ("Breakfast", "Protein plus easy-to-eat complex carbs.", "Choose foods you can repeat even on a disrupted schedule."),
            ("Lunch", "Warm, simple, nutrient-dense meal with protein, vegetables, and starch.", "Postpartum meals must prioritize practicality."),
            ("Evening", "Portable snack near feeding or caregiving blocks.", "Do not wait until you are already depleted."),
            ("Dinner", "Early, comforting, and not overly heavy.", daily_goal),
        ),
        "gut": (
            ("Morning", "Hydrate and avoid starting with spicy, acidic, or fried food.", "Timing matters as much as ingredients."),
            ("Breakfast", "Simple, easy-to-digest meal with protein and low irritant load.", "Track whether symptoms start immediately or later."),
            ("Lunch", "Moderate portions; avoid piling multiple trigger foods into one meal.", "One change per meal makes trigger detection possible."),
            ("Evening", "Light snack only if needed; avoid lying down soon after eating.", "Reflux worsens with late heavy intake."),
            ("Dinner", "Earlier dinner with low spice, moderate fat, and smaller volume.", plan_focus),
        ),
        "cholesterol": (
            ("Morning", "Hydrate and remove buttered or processed breakfast defaults.", "Reduce saturated fat quietly but consistently."),
            ("Breakfast", "Fiber-rich breakfast with protein: oats, dal, sprouts, nuts, curd.", "Breakfast is the easiest place to add soluble fiber."),
            ("Lunch", "Vegetable-heavy plate, pulses/lean protein, modest whole grains.", "Use lunch to replace fried and creamy foods."),
            ("Evening", "Nuts or fruit instead of bakery snacks.", "Packaged snacks often bring both fat and salt."),
            ("Dinner", "Light, oil-aware dinner with vegetables and lean protein.", daily_goal),
        ),
        "senior": (
            ("Morning", "Hydrate, review morning medicines, and avoid long fasting windows.", "Confusion, dizziness, or poor intake should be noted early."),
            ("Breakfast", "Soft, easy-to-chew protein and familiar foods.", "Meal simplicity improves adherence."),
            ("Lunch", "Protein, vegetables, and adequate fluids with manageable portions.", "Watch swallowing, appetite, and bowel comfort."),
            ("Evening", "Small snack if large gaps trigger weakness or missed medicines.", "Keep snacks easy to access."),
            ("Dinner", "Early dinner with hydration review and safe medicine timing.", daily_goal),
        ),
        "general": (
            ("Morning", "Hydrate, get light exposure, and set the day’s main health goal.", "Routine quality starts before breakfast."),
            ("Breakfast", "Balanced meal with protein and fiber.", "Do not let breakfast be only refined carbs."),
            ("Lunch", "Vegetables, reliable protein, and moderate starch.", "This is the anchor meal for the day."),
            ("Evening", "Planned snack if needed; avoid grazing.", "Unplanned snacking hides most routine breakdowns."),
            ("Dinner", "Light enough to protect sleep and digestion.", daily_goal),
        ),
    }
    rows = plan_map.get(variant_key, plan_map["general"])
    return (
        ("Meal block", "Suggested structure", "What to monitor"),
        rows,
        "This is a suggested framework. Adjust for kidney disease, allergies, pregnancy complications, and clinician-prescribed diets.",
    )


def _week_plan_table(
    template: ReportTemplate,
    values: dict[str, Any],
    reminders: tuple[str, ...],
) -> tuple[tuple[str, ...], tuple[tuple[str, ...], ...], str | None]:
    problem_key = _problem_key(template.problem_name)
    variant_key = {
        "pcos": "hormone",
        "thyroid": "hormone",
        "women": "hormone",
        "skin": "hormone",
        "autoimmune": "hormone",
    }.get(problem_key, problem_key)
    plan_focus = _string_value(values.get("plan_focus")) or "Keep the routine consistent."
    daily_goal = _string_value(values.get("daily_goal")) or "Repeat the best-performing habit tomorrow."
    reminder_a = reminders[0] if reminders else "Use one morning reminder."
    reminder_b = reminders[1] if len(reminders) > 1 else "Use one evening review."
    plan_map = {
        "weight": (
            ("Day 1", "Capture weight, waist if tracked, and photograph every meal.", reminder_a),
            ("Day 2", "Lock breakfast protein and remove liquid calories.", "Hunger before lunch means the meal was too weak."),
            ("Day 3", "Hit the step floor and complete a short walk after dinner.", reminder_b),
            ("Day 4", "Audit craving window and pre-plan the afternoon snack.", "Do not leave the highest-risk time unplanned."),
            ("Day 5", "Finish dinner earlier and protect sleep duration.", "Weight control breaks when sleep collapses."),
            ("Day 6", "Review weekend eating risks before they happen.", "Plan one indulgence, not a full-day drift."),
            ("Day 7", "Close the week against the main goal.", daily_goal),
        ),
        "diabetes": (
            ("Day 1", "Record fasting and one post-meal glucose value if advised.", reminder_a),
            ("Day 2", "Fix breakfast timing and align medicines exactly as prescribed.", "Glucose patterns are unreadable without timing."),
            ("Day 3", "Add a 10-15 minute walk after two meals if safe.", reminder_b),
            ("Day 4", "Check which meal produced the biggest rise or symptoms.", "One reproducible pattern is enough to improve next week."),
            ("Day 5", "Avoid long meal gaps and late heavy dinner.", "Spikes often begin with erratic timing."),
            ("Day 6", "Review low/high risk, carry snacks or glucose support if needed.", "Safety beats perfect numbers."),
            ("Day 7", "Summarize glucose, meal timing, and medicine adherence for review.", daily_goal),
        ),
        "bp": (
            ("Day 1", "Measure pressure using the same technique and timing.", reminder_a),
            ("Day 2", "Remove obvious sodium sources from breakfast and snacks.", "Packaged salt often outweighs table salt."),
            ("Day 3", "Add one stress-lowering block and a steady walk.", reminder_b),
            ("Day 4", "Check if poor sleep or caffeine changed readings.", "BP often reflects recovery quality."),
            ("Day 5", "Review medicine timing and refill status.", "Control fails when timing drifts."),
            ("Day 6", "Repeat home reading after a quiet seated rest.", "Technique errors create fake alarms."),
            ("Day 7", "Compare the week against the home routine target.", daily_goal),
        ),
        "heart": (
            ("Day 1", "Document any chest, breathlessness, or exertion symptom clearly.", reminder_a),
            ("Day 2", "Keep meals lighter and cut fried/packaged foods.", "Cardiac risk is cumulative, not meal-by-meal only."),
            ("Day 3", "Perform only symptom-safe activity.", reminder_b),
            ("Day 4", "Review BP, sleep, and stress together.", "These often travel as a cluster."),
            ("Day 5", "Keep emergency escalation thresholds visible.", "Do not negotiate with chest pain red flags."),
            ("Day 6", "Prepare reports, medicines, and questions for review if needed.", "Organized follow-up shortens unsafe delay."),
            ("Day 7", "Reassess symptom burden and next clinician step.", daily_goal),
        ),
        "hormone": (
            ("Day 1", "Start a clear symptom and cycle or energy log.", reminder_a),
            ("Day 2", "Stabilize breakfast and lunch composition.", "Hormone-related cravings often track meal quality."),
            ("Day 3", "Add a short walk or light movement block.", reminder_b),
            ("Day 4", "Track one trigger: stress, sleep loss, refined sugar, or inactivity.", "One measured trigger is better than many guesses."),
            ("Day 5", "Review medicine or supplement timing if prescribed.", "Consistency beats sporadic catch-up."),
            ("Day 6", "Plan the next three days of meals in advance.", "Reactive eating keeps symptoms noisy."),
            ("Day 7", "Close the week with a short symptom summary.", daily_goal),
        ),
        "pregnancy": (
            ("Day 1", "Log symptoms, hydration, and current trimester issues.", reminder_a),
            ("Day 2", "Spread intake across smaller tolerated meals.", "Escalate if you cannot maintain intake."),
            ("Day 3", "Review supplements and medicine safety.", reminder_b),
            ("Day 4", "Track swelling, headache, pain, bleeding, or reduced movement if relevant.", "Red flags override the routine."),
            ("Day 5", "Protect rest and ask for support on the hardest daily task.", "Recovery capacity is part of maternal care."),
            ("Day 6", "Prepare questions for the next antenatal review.", "Do not rely on memory during appointments."),
            ("Day 7", "Summarize the week’s symptoms and tolerance.", daily_goal),
        ),
        "postpartum": (
            ("Day 1", "Track bleeding, pain, sleep, and one mood note.", reminder_a),
            ("Day 2", "Protect one reliable meal and hydration block.", "Caregiving pressure should not erase intake."),
            ("Day 3", "Check feeding or breast symptoms and current support.", reminder_b),
            ("Day 4", "Review fever, wound, urinary, or clotting red flags.", "Infection or heavy bleeding cannot wait."),
            ("Day 5", "Ask for help with one task that steals rest.", "Support is treatment, not luxury."),
            ("Day 6", "Reconcile medicines, supplements, and appointments.", "Postpartum drift is usually organizational."),
            ("Day 7", "Close the week with a recovery summary.", daily_goal),
        ),
        "digestive": (
            ("Day 1", "Start meal and symptom timing log.", reminder_a),
            ("Day 2", "Remove one likely trigger only; do not change everything at once.", "Single-variable changes are easier to interpret."),
            ("Day 3", "Walk gently after meals if safe and note bloating response.", reminder_b),
            ("Day 4", "Review bowel pattern and hydration.", "Constipation and dehydration amplify symptom noise."),
            ("Day 5", "Keep dinner early and smaller.", "Night symptoms often improve first."),
            ("Day 6", "Flag any blood, weight loss, vomiting, or severe pain.", "Alarm symptoms cancel the self-experiment."),
            ("Day 7", "Write the top three triggers and relief habits.", daily_goal),
        ),
        "sleep": (
            ("Day 1", "Fix wake time first; bedtime follows later.", reminder_a),
            ("Day 2", "Set caffeine cutoff and reduce late screen exposure.", "Sleep hygiene fails when timing stays vague."),
            ("Day 3", "Use a short wind-down routine before bed.", reminder_b),
            ("Day 4", "Track wakeups, snoring, or early-morning alertness.", "Daytime sleepiness matters as much as hours slept."),
            ("Day 5", "Protect movement and daylight exposure.", "Circadian signals are physical, not motivational."),
            ("Day 6", "Review whether stress or heavy dinner is disturbing sleep.", "Evening inputs often explain fragmented nights."),
            ("Day 7", "Compare sleep length, quality, and daytime function.", daily_goal),
        ),
        "mood": (
            ("Day 1", "Write one-line mood and trigger log.", reminder_a),
            ("Day 2", "Protect meals and sleep from collapse.", "Mood work fails if physiology is unstable."),
            ("Day 3", "Use one coping skill on schedule, not only during crisis.", reminder_b),
            ("Day 4", "Reduce one known trigger or overload source.", "Avoid broad promises; remove one pressure point."),
            ("Day 5", "Check support contact, therapy plan, or escalation route.", "Support systems should be ready before crisis."),
            ("Day 6", "Review energy, appetite, and irritability together.", "Mood often shows up as behavior drift first."),
            ("Day 7", "Summarize what improved and what still feels unsafe.", daily_goal),
        ),
        "fitness": (
            ("Day 1", "Set the week’s training split and recovery boundaries.", reminder_a),
            ("Day 2", "Complete strength block with conservative progression.", "Technique quality beats ego load."),
            ("Day 3", "Add cardio or mobility day.", reminder_b),
            ("Day 4", "Review pain points, soreness, and sleep.", "Recovery failure is programming data."),
            ("Day 5", "Second strength or skill block.", "Repeatable effort beats random intensity."),
            ("Day 6", "Active recovery and nutrition check.", "Training gains are limited by recovery."),
            ("Day 7", "Close the week with session review.", daily_goal),
        ),
        "senior": (
            ("Day 1", "Check medicines, fluids, meals, and baseline alertness.", reminder_a),
            ("Day 2", "Protect safe mobility and one supervised walk if possible.", "Falls are usually multifactorial."),
            ("Day 3", "Review appetite, bowel pattern, and hydration.", reminder_b),
            ("Day 4", "Track dizziness, confusion, or missed doses.", "Small changes can signal real deterioration."),
            ("Day 5", "Check caregiver workload and support coverage.", "Care plans fail when helpers are overloaded."),
            ("Day 6", "Prepare questions for doctor or caregiver review.", "Bring actual timings, not vague descriptions."),
            ("Day 7", "Summarize the week’s safety issues and wins.", daily_goal),
        ),
        "private": (
            ("Day 1", "Document the exact symptom, onset, and current risk.", reminder_a),
            ("Day 2", "Avoid irritants or unsafe exposure until the cause is clearer.", "Do not keep guessing while symptoms persist."),
            ("Day 3", "Book STI, urine, pregnancy, or clinician review if indicated.", reminder_b),
            ("Day 4", "Track pain, discharge, bleeding, fever, or urinary change.", "Red flags require escalation, not self-monitoring."),
            ("Day 5", "Review medicines, protection, and partner context.", "The follow-up plan fails if context stays hidden."),
            ("Day 6", "Prepare direct doctor questions and a symptom timeline.", "A clean timeline shortens time to diagnosis."),
            ("Day 7", "Close the week with testing or follow-up status.", daily_goal),
        ),
        "cholesterol": (
            ("Day 1", "Audit the main saturated-fat and snack sources.", reminder_a),
            ("Day 2", "Upgrade breakfast to a higher-fiber option.", "Start where repetition is easiest."),
            ("Day 3", "Add a planned walk and reduce restaurant meals.", reminder_b),
            ("Day 4", "Check labels for oil, fried food, and packaged snacks.", "What looks small often drives the weekly total."),
            ("Day 5", "Review weight trend and waist if relevant.", "Lipid work is strongly linked to routine consistency."),
            ("Day 6", "Confirm medicine adherence if prescribed.", "Statin or non-statin success is mostly adherence."),
            ("Day 7", "Summarize food changes and next lab plan.", daily_goal),
        ),
        "habit": (
            ("Day 1", "Write the exact trigger and the smallest replacement action.", reminder_a),
            ("Day 2", "Install one visible cue in the real environment.", "Behavior is environmental engineering first."),
            ("Day 3", "Repeat the replacement action even if motivation is low.", reminder_b),
            ("Day 4", "Track which moment breaks the chain.", "Failure data is part of the plan."),
            ("Day 5", "Reduce friction for the replacement behavior.", "Prepare tools, clothes, or food ahead of time."),
            ("Day 6", "Add a simple reward or streak cue.", "Feedback loops maintain consistency."),
            ("Day 7", "Review trigger strength and replacement success.", daily_goal),
        ),
        "general": (
            ("Day 1", "Set the week’s main health goal and baseline log.", reminder_a),
            ("Day 2", "Stabilize breakfast, lunch, and hydration.", "Routine consistency beats occasional extreme effort."),
            ("Day 3", "Add one predictable movement block.", reminder_b),
            ("Day 4", "Review sleep and stress before adding new goals.", "Recovery sets the ceiling for everything else."),
            ("Day 5", "Check medication, supplements, and preventive tasks.", "Health admin is part of health behavior."),
            ("Day 6", "Simplify the hardest part of the routine.", "If the plan is too hard, the plan is wrong."),
            ("Day 7", "End the week with a brief self-review.", daily_goal),
        ),
    }
    rows = plan_map.get(variant_key, plan_map["general"])
    return (
        ("Day", "Main action", "Checkpoint"),
        rows,
        "Day labels are sequencing tools. Shift them to the real calendar as needed.",
    )


def _monitoring_hint(problem_name: str, label: str) -> str:
    problem_key = _problem_key(problem_name)
    label_key = _normalize(label)
    if problem_key == "diabetes":
        if "bloodsugar" in label_key or "glucose" in label_key:
            return "Capture fasting or post-meal timing with the reading, otherwise the number is not interpretable."
        if "meal" in label_key:
            return "Meal timing matters because it changes spikes, lows, and medication fit."
    if problem_key == "bp" and ("systolic" in label_key or "diastolic" in label_key):
        return "Interpret only with proper home technique, seated rest, and repeat context."
    if problem_key == "weight" and ("weight" in label_key or "bmi" in label_key):
        return "Look for weekly direction, not daily noise."
    if problem_key == "sleep":
        return "Compare the value against daytime function, not sleep duration alone."
    return "Use this value together with symptom pattern and routine consistency."


def _symptom_domains(problem_name: str) -> tuple[tuple[str, str], ...]:
    return tuple((field.label, field.guidance) for field in _condition_schema(problem_name).symptom_fields)


def _testing_items(problem_name: str) -> tuple[tuple[str, str, str], ...]:
    problem_key = _problem_key(problem_name)
    mapping = {
        "weight": (
            ("Weight / waist trend", "Direction matters more than single-day fluctuation.", "Review weekly."),
            ("Sugar / thyroid / lipid labs if indicated", "Unexplained weight changes may have metabolic drivers.", "Discuss if plateau or rapid change persists."),
            ("Lifestyle review", "The plan fails when sleep, meals, and activity are not reviewed together.", "At the next coaching or clinician follow-up."),
        ),
        "diabetes": (
            ("Fasting and post-meal glucose log", "Numbers need timing context to guide safe adjustments.", "Review through the week."),
            ("HbA1c / long-range control review", "One week of readings does not replace longer trend assessment.", "Discuss with clinician at scheduled follow-up."),
            ("Hypo / hyper safety plan", "Safety actions matter before control looks perfect.", "Confirm immediately if episodes are recurring."),
        ),
        "bp": (
            ("Home BP log", "Proper technique and repeated readings matter more than a single high value.", "Track through the next 7 days."),
            ("Kidney / medication review", "Persistent high readings often need treatment review.", "Discuss if readings remain elevated."),
            ("Urgent symptom check", "Headache, chest symptoms, or neuro symptoms change urgency.", "Escalate the same day if present."),
        ),
        "heart": (
            ("ECG / cardiac review if symptomatic", "Chest symptoms need a lower threshold for formal assessment.", "Arrange promptly if symptoms persist."),
            ("BP / lipid / risk factor review", "Cardiac symptoms rarely stand alone.", "Discuss at clinician follow-up."),
            ("Emergency escalation plan", "Worsening chest pain or breathlessness is not a watch-and-wait problem.", "Immediate if red flags appear."),
        ),
        "pregnancy": (
            ("Antenatal symptom review", "Trimester changes and red flags must be assessed in context.", "Raise at the next antenatal visit or sooner."),
            ("Supplement and medicine safety", "Not every 'safe' routine from pre-pregnancy remains appropriate.", "Verify now."),
            ("Urgent red-flag escalation", "Bleeding, severe pain, headache, fever, or reduced movement need prompt care.", "Same day if present."),
        ),
        "postpartum": (
            ("Recovery check", "Bleeding, pain, fever, wound, urinary, and feeding issues need structured review.", "Within the usual postpartum follow-up window or sooner."),
            ("Mood review", "Low mood or overwhelm can become urgent quickly.", "Escalate immediately if safety concerns exist."),
            ("Support-system review", "Care plans fail when the mother has no protected recovery time.", "Review this week."),
        ),
        "sexual": (
            ("STI / infection testing if indicated", "Symptoms, exposure, and discharge or pain patterns guide testing.", "Arrange promptly if risk exists."),
            ("Pregnancy risk review", "Missed period, emergency contraception need, or uncertain exposure changes the pathway.", "Same day if relevant."),
            ("Clinician exam", "Pain, bleeding, ulcers, fever, or persistent symptoms often need examination, not chat-only advice.", "Prompt follow-up."),
        ),
        "cholesterol": (
            ("Lipid profile repeat plan", "Food changes need a lab anchor to judge response.", "Follow clinician interval."),
            ("Medication review if prescribed", "Adherence and tolerance matter before calling treatment ineffective.", "Discuss at follow-up."),
            ("Risk-factor bundle review", "BP, weight, diabetes risk, and family history shift the threshold for action.", "Review with clinician."),
        ),
    }
    return mapping.get(
        problem_key,
        (
            ("Symptom review", "The pattern should be reviewed against duration, severity, and function.", "Within the next follow-up."),
            ("Testing / labs if indicated", "Persistent symptoms without objective review stay ambiguous.", "Discuss with clinician."),
            ("Escalation check", "Urgent symptoms should be separated from routine planning.", "Same day if red flags appear."),
        ),
    )


def _trigger_items(problem_name: str) -> tuple[tuple[str, str, str], ...]:
    problem_key = _problem_key(problem_name)
    if problem_key in {"digestive"}:
        return (
            ("Late, large meals", "Worsens bloating, reflux, and sleep quality.", "Reduce volume and bring dinner earlier."),
            ("Spicy / fried / acidic foods", "Can trigger burning, gas, or urgency.", "Remove one trigger at a time and re-test later."),
            ("Stress eating", "Amplifies symptom noise and makes triggers harder to spot.", "Add a pause before the first high-risk snack."),
            ("Poor hydration", "Worsens constipation and food sensitivity patterns.", "Track water across the day, not only at night."),
        )
    if problem_key in {"mood", "sleep"}:
        return (
            ("Unplanned late nights", "Destabilizes sleep, appetite, stress, and mood.", "Anchor wake time and evening shutdown."),
            ("High-stimulation evenings", "Raises arousal and prolongs sleep onset.", "Cut screens and intense work before bed."),
            ("Skipped meals", "Mimics or worsens anxiety and irritability.", "Protect meal timing before solving the rest."),
            ("Isolation or overload", "Keeps symptoms high and support low.", "Pre-schedule one support or reset block."),
        )
    if problem_key == "habit":
        return (
            ("Specific cue", "The habit keeps firing automatically.", "Make the cue visible and design a competing action."),
            ("Low-energy moment", "Behavior falls back to the easiest option.", "Shrink the replacement behavior to two minutes."),
            ("Environment friction", "Desired behavior loses to convenience.", "Prepare tools and remove setup cost."),
            ("No reward loop", "The new habit feels invisible.", "Add a visible streak, note, or check mark."),
        )
    if problem_key == "weight":
        return (
            ("Liquid calories or random snacking", "Adds intake without satiety.", "Convert to planned meals or structured snacks."),
            ("Poor sleep", "Raises cravings and weakens appetite control.", "Protect sleep before tightening calories further."),
            ("Weekend drift", "Erases weekday progress silently.", "Plan the risky meal before the day starts."),
            ("All-or-nothing mindset", "Turns one miss into a lost week.", "Return to the next meal, not next Monday."),
        )
    return (
        ("Stress spike", "Symptoms and routine discipline usually worsen together.", "Use one pre-decided reset action, not a vague intention."),
        ("Poor sleep", "Recovery drops and symptoms become noisier.", "Improve bedtime consistency before adding harder goals."),
        ("Missed routine window", "The whole day becomes reactive.", "Use reminders and reduce the first barrier."),
        ("Unplanned food or schedule change", "Makes patterns hard to interpret.", "Return to the simplest stable routine."),
    )


def _recovery_items(problem_name: str) -> tuple[tuple[str, str, str], ...]:
    if _problem_key(problem_name) == "pregnancy":
        return (
            ("Hydration and intake", "Enough fluids and regular tolerated meals.", "You cannot keep food or fluids down."),
            ("Pain / bleeding / movement", "Track what changed, when, and how strong it feels.", "Pain, bleeding, or movement changes cross red-flag thresholds."),
            ("Sleep and rest", "Protect recovery blocks even if sleep is fragmented.", "Exhaustion is so severe that intake and function are collapsing."),
            ("Support and appointments", "Keep the next contact point visible.", "You cannot safely manage symptoms at home."),
        )
    return (
        ("Bleeding and pain", "Track volume, trend, fever, and wound status.", "Bleeding becomes heavy, pain escalates, or fever develops."),
        ("Mood and coping", "Write one mood note and one support action daily.", "Panic, hopelessness, or self-harm thoughts appear."),
        ("Feeding and nutrition", "Watch breast symptoms, intake, and hydration.", "Feeding pain, poor intake, or dehydration persists."),
        ("Rest and support", "Protect one recovery block every day.", "You are unable to rest or function without distress."),
    )


def _medicine_timing_hint(problem_name: str) -> str:
    problem_key = _problem_key(problem_name)
    if problem_key == "thyroid":
        return "Confirm empty-stomach timing and what should stay away from the dose."
    if problem_key == "diabetes":
        return "Timing must be tied to meals, glucose checks, and any hypo risk."
    if problem_key == "bp":
        return "Keep timing consistent so home readings are interpretable."
    if problem_key == "sexual":
        return "Verify duration, abstinence or protection advice, and whether partner treatment matters."
    return "Verify timing against meals, sleep, and actual prescription instructions."


def _side_effect_watch(problem_name: str) -> str:
    problem_key = _problem_key(problem_name)
    if problem_key == "bp":
        return "Record dizziness, swelling, cough, or other changes that appeared after treatment."
    if problem_key == "diabetes":
        return "Log lows, stomach upset, weakness, or GI side effects with timing."
    if problem_key == "sexual":
        return "Track rash, worsening pain, fever, or persistent discharge despite treatment."
    return "Track new symptoms that started only after the medicine or supplement routine changed."





def _executive_highlights(
    template: ReportTemplate,
    values: dict[str, Any],
    pair_lookup: dict[str, str],
    reminders: tuple[str, ...],
    score: int | None,
) -> tuple[dict[str, str], ...]:
    rows: list[dict[str, str]] = []
    seen: set[str] = set()

    def add(label: str, value: str | None) -> None:
        clean_value = _clean_text(value or "").strip()
        if not clean_value:
            return
        key = _normalize(label)
        if key in seen:
            return
        seen.add(key)
        rows.append({"label": label, "value": clean_value})

    if score is not None:
        add(template.score_label, f"{score}/100")
    add("Captured metric", _metric_value(values))
    add("Status", _string_value(values.get("metric_status")))
    add("Plan focus", _string_value(values.get("plan_focus")))
    add("Daily goal", _string_value(values.get("daily_goal")))
    for label in template.metric_labels:
        add(label, _lookup_pair(label, pair_lookup))
        if len(rows) >= 4:
            break
    if len(rows) < 4 and reminders:
        add("Reminders", f"{len(reminders)} saved")
    if len(rows) < 4:
        add("Data quality", "Add fresh logs or reports to fill missing boxes.")
    return tuple(rows[:4])


def _dashboard_items(
    template: ReportTemplate,
    values: dict[str, Any],
    pair_lookup: dict[str, str],
    score: int | None,
) -> tuple[tuple[str, str], ...]:
    rows: list[tuple[str, str]] = []
    seen: set[str] = set()

    def add(label: str, value: str | None) -> None:
        clean_value = _clean_text(value or "").strip()
        if not clean_value:
            return
        key = _normalize(label)
        if key in seen:
            return
        seen.add(key)
        rows.append((label, clean_value))

    if score is not None:
        add(template.score_label, f"{score}/100")
    add("Captured metric", _metric_value(values))
    for label in template.metric_labels:
        add(label, _lookup_pair(label, pair_lookup))
    for key, value in values.items():
        if _skip_dashboard_key(key):
            continue
        label = _humanize_key(key)
        if key in {"metric_value", "metric_unit"}:
            continue
        add(label, _string_value(value))
    if not rows:
        return (("Dashboard", "No saved dashboard values yet."),)
    return tuple(rows[:8])


def _missing_info_items(sections: tuple[MarkdownSection, ...]) -> tuple[str, ...]:
    rows = []
    for section in sections:
        title = _normalize(section.title)
        if "missing information" in title:
            rows.extend(section.bullets)
            rows.extend(section.body)
    if not rows:
        return ("No explicit missing-information section was saved with this intake.",)
    return _unique(rows)[:6]


def _safety_boundary(sections: tuple[MarkdownSection, ...]) -> str:
    for section in sections:
        title = _normalize(section.title)
        if "safety boundary" not in title:
            continue
        lines = [*section.body, *section.bullets]
        if lines:
            return " ".join(lines)
    return (
        "This report supports lifestyle coaching and doctor discussion only. "
        "It is not a diagnosis, prescription, emergency-care document, or substitute for a licensed clinician."
    )


def _pair_lookup(values: dict[str, Any], sections: tuple[MarkdownSection, ...]) -> dict[str, str]:
    pairs: dict[str, str] = {}
    for key, value in values.items():
        label = _humanize_key(key)
        text = _string_value(value)
        if text:
            pairs.setdefault(_normalize(label), text)
            pairs.setdefault(_normalize(str(key)), text)
    for section in sections:
        for line in (*section.body, *section.bullets):
            for label, value in _inline_pairs(line):
                pairs.setdefault(_normalize(label), value)
    return pairs


def _inline_pairs(text: str) -> tuple[tuple[str, str], ...]:
    rows: list[tuple[str, str]] = []
    clean = _clean_text(text)
    if ":" not in clean:
        return ()
    label, value = clean.split(":", 1)
    label = label.strip(" -")
    value = value.strip()
    if label and value and len(label) <= 40:
        rows.append((label, value))
    return tuple(rows)


def _lookup_pair(label: str, pairs: dict[str, str]) -> str | None:
    direct = pairs.get(_normalize(label))
    if direct:
        return direct
    normalized_label = _normalize(label)
    for key, value in pairs.items():
        if normalized_label in key or key in normalized_label:
            return value
    return None


def _metric_value(values: dict[str, Any]) -> str | None:
    value = _string_value(values.get("metric_value"))
    unit = _string_value(values.get("metric_unit"))
    combined = " ".join(part for part in (value, unit) if part).strip()
    return combined or None


def _score_value(values: dict[str, Any]) -> int | None:
    for key in ("score", "health_score", "daily_score", "weight_score"):
        raw = values.get(key)
        try:
            return max(0, min(100, int(float(raw))))
        except (TypeError, ValueError):
            continue
    return None


def _score_phrase(score: int | None) -> str:
    if score is None:
        return "No structured health score was saved yet."
    if score >= 85:
        return "Current records suggest strong routine consistency."
    if score >= 70:
        return "Current records suggest moderate stability with room to tighten the routine."
    return "Current records suggest follow-up is needed to stabilize the routine."


def _summary_sentences(sections: tuple[MarkdownSection, ...]) -> tuple[str, ...]:
    rows: list[str] = []
    for section in sections:
        rows.extend(section.body)
        rows.extend(section.bullets)
    return _unique(rows)


def _transcript_notes(transcript: Any) -> tuple[str, ...]:
    notes: list[str] = []
    if not isinstance(transcript, list):
        return ()
    for item in transcript[-6:]:
        if not isinstance(item, dict):
            continue
        text = _clean_text(item.get("text") or "").strip()
        if not text:
            continue
        role = _clean_text(item.get("role") or "note").strip().title()
        notes.append(f"{role}: {text}")
    return tuple(notes)


def _report_date(report) -> str:
    created_at = getattr(report, "created_at", None)
    if created_at is None:
        return ""
    try:
        return created_at.strftime("%d %b %Y")
    except Exception:
        return str(created_at)


def _generated_for(report) -> str:
    user = getattr(report, "user", None)
    if user is None:
        return "User"
    full_name = _clean_text(getattr(user, "get_full_name", lambda: "")() or "").strip()
    if full_name:
        return full_name
    email = _clean_text(getattr(user, "email", "") or "").strip()
    if email:
        return email
    username = _clean_text(getattr(user, "username", "") or "").strip()
    return username or "User"


def _load_css(filename: str) -> str:
    path = settings.BASE_DIR / "accounts" / "report_styles" / filename
    if not path.exists():
        return ""
    return path.read_text(encoding="utf-8").lstrip("\ufeff")


def _asset_path(*parts: str) -> Path:
    return settings.BASE_DIR.parent / "mobile" / "assets" / "images" / Path(*parts)


def _asset_data_uri(*parts: str) -> str:
    path = _asset_path(*parts)
    if not path.exists():
        return ""
    mime_type, _ = mimetypes.guess_type(path.name)
    mime_type = mime_type or "application/octet-stream"
    payload = b64encode(path.read_bytes()).decode("ascii")
    return f"data:{mime_type};base64,{payload}"


def _skip_dashboard_key(key: str) -> bool:
    return key in {
        "score",
        "health_score",
        "daily_score",
        "weight_score",
        "metric_value",
        "metric_unit",
        "full_transcript_saved",
        "transcript_message_count",
    }


def _humanize_key(value: str) -> str:
    words = re.sub(r"[_-]+", " ", str(value)).strip()
    return " ".join(word.capitalize() for word in words.split())


def _string_list(value: Any) -> tuple[str, ...]:
    if not isinstance(value, Iterable) or isinstance(value, (str, bytes, dict)):
        return ()
    rows = [_clean_text(item).strip() for item in value if _clean_text(item).strip()]
    return tuple(rows)


def _string_value(value: Any) -> str:
    if value is None:
        return ""
    if isinstance(value, bool):
        return "Yes" if value else "No"
    if isinstance(value, (list, tuple, set)):
        rows = [_clean_text(item).strip() for item in value if _clean_text(item).strip()]
        return ", ".join(rows)
    if isinstance(value, dict):
        rows = []
        for key, item in value.items():
            clean_item = _clean_text(item).strip()
            if not clean_item:
                continue
            rows.append(f"{_humanize_key(str(key))}: {clean_item}")
        return ", ".join(rows)
    return _clean_text(value).strip()


def _normalize(value: str) -> str:
    return "".join(ch for ch in _clean_text(value).lower() if ch.isalnum())


def _unique(items: Iterable[str]) -> tuple[str, ...]:
    seen: set[str] = set()
    rows: list[str] = []
    for item in items:
        clean = _clean_text(item).strip()
        if not clean:
            continue
        key = clean.lower()
        if key in seen:
            continue
        seen.add(key)
        rows.append(clean)
    return tuple(rows)


def _clean_text(value: Any) -> str:
    text = str(value or "")
    replacements = {
        "\ufeff": "",
        "\u2013": "-",
        "\u2014": "-",
        "\u2018": "'",
        "\u2019": "'",
        "\u201c": '"',
        "\u201d": '"',
        "\u2022": "-",
        "\u00a0": " ",
    }
    for old, new in replacements.items():
        text = text.replace(old, new)
    return text
