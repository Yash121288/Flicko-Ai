from __future__ import annotations

import hashlib
from typing import Any

from django.contrib.auth.models import User
from django.db.models import Avg
from django.utils import timezone
from django.utils.dateparse import parse_datetime

from .diabetes_dashboard import build_diabetes_dashboard_summary
from .models import (
    UserCareTaskRecord,
    UserChatMessageRecord,
    UserHealthLogRecord,
    UserMealAnalysisRecord,
    UserReminderRecord,
    UserSafetyEventRecord,
)


APP_DATA_KEYS = (
    "health_logs",
    "meal_analyses",
    "saved_reminders",
    "care_tasks",
    "safety_events",
    "chat_history",
)


def sync_app_data(
    user: User,
    data: dict[str, Any],
    *,
    problem_name: str = "",
) -> dict[str, int]:
    """Upsert local app records into normalized backend tables.

    The Flutter app still sends full JSON snapshots. Backend normalization makes
    those snapshots queryable for dashboards, reports, safety audit, and future
    analytics while preserving the original payload for forward compatibility.
    """

    counts = {
        "health_logs": _sync_health_logs(user, data.get("health_logs"), problem_name),
        "meal_analyses": _sync_meal_analyses(
            user,
            data.get("meal_analyses"),
            problem_name,
        ),
        "saved_reminders": _sync_reminders(
            user,
            data.get("saved_reminders"),
            problem_name,
        ),
        "care_tasks": _sync_care_tasks(user, data.get("care_tasks"), problem_name),
        "safety_events": _sync_safety_events(
            user,
            data.get("safety_events"),
            problem_name,
        ),
        "chat_history": _sync_chat_history(user, data.get("chat_history"), problem_name),
    }
    return counts


def summarize_records_for_dashboard(user: User) -> dict[str, object]:
    profile = getattr(user, "profile", None)
    meal_qs = user.meal_analysis_records.all()
    log_qs = user.health_log_records.all()
    reminder_qs = user.reminder_records.filter(enabled=True)
    task_qs = user.care_task_records.filter(enabled=True)
    safety_qs = user.safety_event_records.all()
    chat_qs = user.chat_message_records.all()

    latest_meal = meal_qs.first()
    latest_log = log_qs.first()
    latest_safety = safety_qs.first()
    latest_chat = chat_qs.order_by("-sent_at", "-created_at").first()
    average_meal_score = meal_qs.aggregate(value=Avg("score"))["value"]

    summary: dict[str, object] = {
        "dashboard_ready": bool(
            profile
            and profile.intake_completed
            and str(profile.intake_summary or "").strip()
        ),
        "dashboard_ready_reason": (
            "Structured AI intake is complete and backend has generated dashboard state."
            if profile
            and profile.intake_completed
            and str(profile.intake_summary or "").strip()
            else "Waiting for a completed AI intake summary before unlocking real dashboard cards."
        ),
        "profile_intake_completed": bool(profile and profile.intake_completed),
        "profile_has_intake_summary": bool(
            profile and str(profile.intake_summary or "").strip()
        ),
        "normalized_health_log_count": log_qs.count(),
        "normalized_meal_analysis_count": meal_qs.count(),
        "normalized_average_meal_score": round(float(average_meal_score or 0), 1),
        "normalized_high_risk_meal_count": meal_qs.filter(score__lt=55).count(),
        "normalized_active_reminder_count": reminder_qs.count(),
        "normalized_active_care_task_count": task_qs.count(),
        "normalized_safety_event_count": safety_qs.count(),
        "normalized_chat_message_count": chat_qs.count(),
    }

    if latest_meal:
        summary.update(
            {
                "latest_meal_name": latest_meal.meal_name,
                "latest_meal_score": latest_meal.score,
                "latest_meal_decision": latest_meal.decision,
                "latest_meal_summary": _join_nonempty(
                    latest_meal.meal_name,
                    f"{latest_meal.score}/100" if latest_meal.score else "",
                    latest_meal.decision,
                    latest_meal.calorie_range,
                ),
            }
        )
    if latest_log:
        summary.update(
            {
                "latest_log_type": latest_log.log_type,
                "latest_log_title": latest_log.title,
                "latest_log_value": _join_nonempty(latest_log.value, latest_log.unit),
                "latest_log_summary": _join_nonempty(
                    latest_log.title,
                    _join_nonempty(latest_log.value, latest_log.unit),
                    latest_log.note,
                ),
            }
        )
    if latest_safety:
        summary.update(
            {
                "latest_safety_severity": latest_safety.severity,
                "latest_safety_title": latest_safety.title,
                "latest_safety_summary": _join_nonempty(
                    latest_safety.severity,
                    latest_safety.title,
                    latest_safety.action,
                ),
            }
        )
    if latest_chat:
        summary["latest_chat_summary"] = latest_chat.text[:500]

    summary.update(build_diabetes_dashboard_summary(user))
    return summary


def _sync_health_logs(user: User, values: Any, fallback_problem: str) -> int:
    count = 0
    for index, item in enumerate(_dict_items(values)):
        external_id = _external_id(item, "health-log", index)
        problem = _problem_name(item, fallback_problem)
        UserHealthLogRecord.objects.update_or_create(
            user=user,
            external_id=external_id,
            defaults={
                "problem_name": problem,
                "log_type": _clean_string(item.get("type"), fallback="symptom")[:60],
                "title": _clean_string(item.get("title"))[:180],
                "value": _clean_string(item.get("value") or item.get("valueText"))[:120],
                "unit": _clean_string(item.get("unit"))[:60],
                "note": _clean_string(item.get("note")),
                "recorded_at": _parse_dt(item.get("createdAt")),
                "payload": item,
            },
        )
        count += 1
    return count


def _sync_meal_analyses(user: User, values: Any, fallback_problem: str) -> int:
    count = 0
    for index, item in enumerate(_dict_items(values)):
        external_id = _external_id(item, "meal-analysis", index)
        score = max(0, min(100, _clean_int(item.get("score"), default=0)))
        UserMealAnalysisRecord.objects.update_or_create(
            user=user,
            external_id=external_id,
            defaults={
                "problem_name": _problem_name(item, fallback_problem),
                "meal_name": _clean_string(item.get("mealName"), fallback="Meal check")[:180],
                "score": score,
                "decision": _clean_string(item.get("decision"), fallback="Review")[:120],
                "calorie_range": _clean_string(item.get("calorieRange"))[:120],
                "risk_flags": _clean_string_list(item.get("riskFlags")),
                "analyzed_at": _parse_dt(item.get("createdAt")),
                "payload": item,
            },
        )
        count += 1
    return count


def _sync_reminders(user: User, values: Any, fallback_problem: str) -> int:
    count = 0
    for index, item in enumerate(_dict_items(values)):
        external_id = _external_id(item, "reminder", index)
        UserReminderRecord.objects.update_or_create(
            user=user,
            external_id=external_id,
            defaults={
                "problem_name": _problem_name(item, fallback_problem),
                "title": _clean_string(item.get("title"), fallback="Flicko reminder")[:180],
                "body": _clean_string(item.get("body")),
                "hour": _bounded_int(item.get("hour"), lower=0, upper=23),
                "minute": _bounded_int(item.get("minute"), lower=0, upper=59),
                "enabled": _clean_bool(item.get("enabled"), default=True),
                "payload": item,
            },
        )
        count += 1
    return count


def _sync_care_tasks(user: User, values: Any, fallback_problem: str) -> int:
    count = 0
    for index, item in enumerate(_dict_items(values)):
        external_id = _external_id(item, "care-task", index)
        UserCareTaskRecord.objects.update_or_create(
            user=user,
            external_id=external_id,
            defaults={
                "problem_name": _problem_name(item, fallback_problem),
                "task_type": _clean_string(item.get("type"), fallback="custom")[:60],
                "title": _clean_string(item.get("title"), fallback="Care task")[:180],
                "detail": _clean_string(item.get("detail")),
                "time_label": _clean_string(item.get("timeLabel"))[:80],
                "enabled": _clean_bool(item.get("enabled"), default=True),
                "last_completed_at": _parse_optional_dt(item.get("lastCompletedAt")),
                "payload": item,
            },
        )
        count += 1
    return count


def _sync_safety_events(user: User, values: Any, fallback_problem: str) -> int:
    count = 0
    for index, item in enumerate(_dict_items(values)):
        external_id = _external_id(item, "safety-event", index)
        UserSafetyEventRecord.objects.update_or_create(
            user=user,
            external_id=external_id,
            defaults={
                "problem_name": _problem_name(item, fallback_problem),
                "source": _clean_string(item.get("source"), fallback="local")[:80],
                "severity": _clean_string(item.get("severity"), fallback="clinician")[:40],
                "rule_id": _clean_string(item.get("ruleId"))[:120],
                "title": _clean_string(item.get("title"))[:180],
                "matched_text": _clean_string(item.get("matchedText")),
                "action": _clean_string(item.get("action")),
                "occurred_at": _parse_dt(item.get("createdAt")),
                "payload": item,
            },
        )
        count += 1
    return count


def _sync_chat_history(user: User, values: Any, fallback_problem: str) -> int:
    count = 0
    for index, item in enumerate(_dict_items(values)):
        text = _clean_string(item.get("text"))
        if not text:
            continue
        role = _clean_string(item.get("role"), fallback="user")[:24]
        external_item = dict(item)
        if _clean_string(external_item.get("source")).lower() == "chat":
            external_item.pop("source", None)
        external_id = _external_id(external_item, f"chat-{role}-{text}", index)
        UserChatMessageRecord.objects.update_or_create(
            user=user,
            external_id=external_id,
            defaults={
                "problem_name": _problem_name(item, fallback_problem),
                "role": role,
                "text": text,
                "is_error": _clean_bool(item.get("isError"), default=False),
                "sent_at": _parse_dt(item.get("createdAt")),
                "payload": item,
            },
        )
        count += 1
    return count


def _dict_items(values: Any) -> list[dict[str, Any]]:
    if not isinstance(values, list):
        return []
    return [dict(item) for item in values if isinstance(item, dict)]


def _external_id(item: dict[str, Any], prefix: str, index: int) -> str:
    raw_id = _clean_string(item.get("id"))
    if raw_id:
        return raw_id[:140]
    source = f"{prefix}|{index}|{item}"
    return f"{prefix}-{_stable_key(source)}"[:140]


def _stable_key(source: str) -> str:
    return hashlib.sha256(source.encode("utf-8")).hexdigest()[:40]


def _problem_name(item: dict[str, Any], fallback: str) -> str:
    return _clean_string(item.get("problemName") or item.get("problem_name") or fallback)[:120]


def _clean_string(value: Any, *, fallback: str = "") -> str:
    text = "" if value is None else str(value).strip()
    return text or fallback


def _clean_string_list(value: Any) -> list[str]:
    if not isinstance(value, list):
        return []
    cleaned: list[str] = []
    seen: set[str] = set()
    for item in value:
        text = _clean_string(item)
        if not text or text.lower() in seen:
            continue
        seen.add(text.lower())
        cleaned.append(text)
    return cleaned


def _clean_int(value: Any, *, default: int) -> int:
    if isinstance(value, bool):
        return default
    if isinstance(value, int):
        return value
    if isinstance(value, float):
        return round(value)
    try:
        return int(str(value).strip())
    except (TypeError, ValueError):
        return default


def _bounded_int(value: Any, *, lower: int, upper: int) -> int | None:
    parsed = _clean_int(value, default=-1)
    if parsed < lower or parsed > upper:
        return None
    return parsed


def _clean_bool(value: Any, *, default: bool) -> bool:
    if value is None:
        return default
    if isinstance(value, bool):
        return value
    return str(value).strip().lower() not in {"false", "0", "no", "off"}


def _parse_dt(value: Any):
    return _parse_optional_dt(value) or timezone.now()


def _parse_optional_dt(value: Any):
    text = _clean_string(value)
    if not text:
        return None
    parsed = parse_datetime(text)
    if parsed is None:
        return None
    if timezone.is_naive(parsed):
        return timezone.make_aware(parsed, timezone.get_current_timezone())
    return parsed


def _join_nonempty(*parts: object) -> str:
    return " - ".join(str(part).strip() for part in parts if str(part).strip())
