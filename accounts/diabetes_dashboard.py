from __future__ import annotations

import re
from typing import Any

from django.contrib.auth.models import User
from django.db.models import Avg
from django.utils import timezone


def build_diabetes_dashboard_summary(user: User) -> dict[str, object]:
    """Return diabetes-specific dashboard values from normalized records."""

    if not _looks_diabetes_user(user):
        return {}

    glucose_logs = list(
        user.health_log_records.filter(log_type="glucose").order_by(
            "-recorded_at",
            "-created_at",
        )[:30]
    )
    all_logs = list(
        user.health_log_records.order_by("-recorded_at", "-created_at")[:80]
    )
    diabetes_meals = user.meal_analysis_records.filter(
        problem_name__icontains="diabetes",
    )
    if not diabetes_meals.exists():
        diabetes_meals = user.meal_analysis_records.all()
    diabetes_meals = diabetes_meals.order_by("-analyzed_at", "-created_at")
    latest_glucose = glucose_logs[0] if glucose_logs else None
    latest_glucose_number = _number(latest_glucose.value) if latest_glucose else None
    high_count = sum(
        1 for log in glucose_logs if (_number(log.value) or 0) >= 180
    )
    hypo_count = sum(
        1 for log in glucose_logs if 0 < (_number(log.value) or 999) < 70
    )
    hypo_count += sum(1 for log in all_logs if _text_has_hypo(log))
    hba1c = _latest_hba1c(all_logs)
    average_meal_score = diabetes_meals.aggregate(value=Avg("score"))["value"]
    high_carb_meal_count = sum(
        1
        for meal in list(diabetes_meals[:20])
        if meal.score < 60 or _meal_has_carb_risk(meal)
    )
    medicine_count = user.care_task_records.filter(
        enabled=True,
        task_type="medicine",
    ).count() + user.reminder_records.filter(
        enabled=True,
        title__icontains="medicine",
    ).count()
    pending_medicine_count = _pending_medicine_count(user)
    safety = _diabetes_safety(
        latest_glucose=latest_glucose_number,
        high_count=high_count,
        hypo_count=hypo_count,
        pending_medicine_count=pending_medicine_count,
    )

    score = _diabetes_score(
        latest_glucose=latest_glucose_number,
        high_count=high_count,
        hypo_count=hypo_count,
        average_meal_score=average_meal_score,
        medicine_count=medicine_count,
    )
    glucose_display = (
        _join_nonempty(latest_glucose.value, latest_glucose.unit)
        if latest_glucose
        else "Add glucose"
    )
    status = _glucose_status(latest_glucose_number, latest_glucose.title if latest_glucose else "")
    plan_focus, plan_note = _plan_from_diabetes_state(
        latest_glucose=latest_glucose_number,
        high_count=high_count,
        hypo_count=hypo_count,
        high_carb_meal_count=high_carb_meal_count,
        hba1c=hba1c,
    )
    if safety["title"]:
        plan_focus = safety["title"]
        plan_note = safety["action"]
    return {
        "diabetes_score": score,
        "diabetes_metric_value": glucose_display,
        "diabetes_metric_unit": "",
        "diabetes_metric_status": status,
        "diabetes_latest_glucose_value": glucose_display,
        "diabetes_latest_glucose_status": status,
        "diabetes_latest_glucose_recorded_at": latest_glucose.recorded_at.isoformat()
        if latest_glucose
        else "",
        "diabetes_hba1c": hba1c or "Not captured yet",
        "diabetes_hypo_event_count": hypo_count,
        "diabetes_high_glucose_count": high_count,
        "diabetes_high_carb_meal_count": high_carb_meal_count,
        "diabetes_medicine_task_count": medicine_count,
        "diabetes_pending_medicine_count": pending_medicine_count,
        "diabetes_safety_severity": safety["severity"],
        "diabetes_safety_title": safety["title"],
        "diabetes_safety_action": safety["action"],
        "diabetes_safety_flags": safety["flags"],
        "diabetes_plan_focus": plan_focus,
        "diabetes_plan_note": plan_note,
        "diabetes_report_body": _join_nonempty(
            safety["title"],
            f"Glucose: {glucose_display}" if latest_glucose else "",
            f"HbA1c: {hba1c}" if hba1c else "",
            f"{high_carb_meal_count} carb-risk meals" if high_carb_meal_count else "",
            f"{hypo_count} low-sugar flags" if hypo_count else "",
            f"{pending_medicine_count} medicine tasks pending"
            if pending_medicine_count
            else "",
        )
        or "Needs glucose, meal, medicine, and HbA1c records.",
    }


def _looks_diabetes_user(user: User) -> bool:
    profile = getattr(user, "profile", None)
    selected = getattr(profile, "selected_problems", []) if profile else []
    if isinstance(selected, list) and any("diabetes" in str(item).lower() for item in selected):
        return True
    return user.health_log_records.filter(log_type="glucose").exists()


def _diabetes_score(
    *,
    latest_glucose: float | None,
    high_count: int,
    hypo_count: int,
    average_meal_score: Any,
    medicine_count: int,
) -> int:
    score = 78
    if latest_glucose is not None:
        if latest_glucose < 70:
            score = 48
        elif latest_glucose <= 140:
            score = 86
        elif latest_glucose <= 180:
            score = 76
        elif latest_glucose <= 250:
            score = 61
        else:
            score = 44
    if average_meal_score:
        score = round((score * 0.72) + (float(average_meal_score) * 0.28))
    score -= min(high_count, 4) * 3
    score -= min(hypo_count, 3) * 7
    if medicine_count:
        score += 3
    return max(0, min(100, score))


def _glucose_status(value: float | None, title: str) -> str:
    title_lower = title.lower()
    context = "fasting" if "fast" in title_lower else "post-meal" if "post" in title_lower or "pp" in title_lower else "latest"
    if value is None:
        return "No glucose reading saved yet"
    if value < 70:
        return f"Low {context} glucose - follow clinician hypo plan"
    if value <= 140:
        return f"{context.title()} glucose looks in target range"
    if value <= 180:
        return f"{context.title()} glucose mildly high; watch meal timing"
    if value <= 250:
        return f"{context.title()} glucose high; review meals and medicines"
    return f"{context.title()} glucose very high; check clinician safety plan"


def _plan_from_diabetes_state(
    *,
    latest_glucose: float | None,
    high_count: int,
    hypo_count: int,
    high_carb_meal_count: int,
    hba1c: str,
) -> tuple[str, str]:
    if hypo_count:
        return (
            "Low sugar safety check",
            "Review hypo symptoms, quick sugar plan, and medicine timing with clinician.",
        )
    if latest_glucose is not None and latest_glucose >= 180:
        return (
            "Post-meal glucose follow-up",
            "Log next meal, walk if safe, and compare 2-hour reading.",
        )
    if high_carb_meal_count:
        return (
            "Lower-carb next meal",
            "Add protein/fiber and reduce refined-carb portion.",
        )
    if not hba1c:
        return (
            "Capture HbA1c report",
            "Upload recent lab or ask doctor when HbA1c should be checked.",
        )
    if high_count:
        return (
            "Glucose pattern review",
            "Look for repeat high readings by meal and time of day.",
        )
    return (
        "Keep diabetes routine steady",
        "Continue glucose logs, medicine reminders, and meal-photo checks.",
    )


def _pending_medicine_count(user: User) -> int:
    today = timezone.localdate()
    count = 0
    for task in user.care_task_records.filter(enabled=True, task_type="medicine"):
        completed = task.last_completed_at
        if completed is None or timezone.localtime(completed).date() != today:
            count += 1
    return count


def _diabetes_safety(
    *,
    latest_glucose: float | None,
    high_count: int,
    hypo_count: int,
    pending_medicine_count: int,
) -> dict[str, object]:
    flags: list[str] = []
    if hypo_count:
        flags.append("low-glucose")
    if high_count >= 3:
        flags.append("repeated-high-glucose")
    if pending_medicine_count:
        flags.append("medicine-pending")

    if latest_glucose is not None and latest_glucose < 70:
        return {
            "severity": "urgent",
            "title": "Low sugar safety flag",
            "action": (
                "Follow the clinician-given hypo plan now. Recheck glucose and "
                "seek urgent help if confused, fainting, unable to swallow, or not improving."
            ),
            "flags": [*flags, "latest-glucose-low"],
        }
    if latest_glucose is not None and latest_glucose >= 250:
        return {
            "severity": "urgent",
            "title": "Very high sugar safety flag",
            "action": (
                "Check the clinician safety plan, hydration, ketone guidance if prescribed, "
                "and get urgent medical advice for vomiting, belly pain, deep breathing, "
                "dehydration, confusion, or persistent high readings."
            ),
            "flags": [*flags, "latest-glucose-very-high"],
        }
    if high_count >= 3:
        return {
            "severity": "clinician",
            "title": "Repeated high sugar pattern",
            "action": (
                "Review the last meals, medicine timing, and glucose readings with a clinician "
                "if this pattern continues."
            ),
            "flags": flags,
        }
    if hypo_count:
        return {
            "severity": "clinician",
            "title": "Recent low sugar pattern",
            "action": "Review low-sugar symptoms, meal timing, and medicine timing before repeating the same routine.",
            "flags": flags,
        }
    if pending_medicine_count:
        return {
            "severity": "clinician",
            "title": "Medicine task pending",
            "action": "Confirm whether the medicine was taken or intentionally skipped, then update the task.",
            "flags": flags,
        }
    return {"severity": "", "title": "", "action": "", "flags": flags}


def _latest_hba1c(logs) -> str:
    for log in logs:
        text = " ".join([log.title, log.value, log.unit, log.note])
        if "hba1c" not in text.lower() and "a1c" not in text.lower():
            continue
        value = _number(text)
        if value is not None:
            return f"{value:g}%"
    return ""


def _text_has_hypo(log) -> bool:
    text = " ".join([log.title, log.value, log.unit, log.note]).lower()
    return any(
        token in text
        for token in ("hypo", "low sugar", "shaking", "sweating", "confusion", "chakkar")
    )


def _meal_has_carb_risk(meal) -> bool:
    text = " ".join(
        [
            meal.decision,
            meal.calorie_range,
            " ".join(str(item) for item in meal.risk_flags),
            str(meal.payload),
        ]
    ).lower()
    return any(
        token in text
        for token in ("carb", "sugar", "sweet", "rice", "refined", "high glycemic")
    )


def _number(value: object) -> float | None:
    match = re.search(r"(\d+(?:\.\d+)?)", str(value or ""))
    if not match:
        return None
    try:
        return float(match.group(1))
    except ValueError:
        return None


def _join_nonempty(*values: object) -> str:
    return " - ".join(str(value).strip() for value in values if str(value).strip())
