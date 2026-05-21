from __future__ import annotations

from dataclasses import dataclass
from typing import Iterable

from django.contrib.auth.models import User
from django.db.models import QuerySet

from .models import (
    FoodRule,
    HealthMemoryEntry,
    HealthProtocol,
    IntakeFlow,
    MemorySchema,
    OutcomeMetric,
    ReminderScript,
    ReportBlock,
    SafetyRule,
    UserProfile,
)
from .intake_requirements import assess_intake


SEVERITY_RANK = {
    SafetyRule.Severity.EMERGENCY: 4,
    SafetyRule.Severity.URGENT: 3,
    SafetyRule.Severity.SOON: 2,
    SafetyRule.Severity.SELF_CARE: 1,
}


@dataclass(frozen=True)
class ProtocolEngineRequest:
    user: User
    condition: str = ""
    text: str = ""
    memory_limit: int = 12


def build_protocol_context(request: ProtocolEngineRequest) -> dict:
    profile, _ = UserProfile.objects.get_or_create(user=request.user)
    selected_conditions = _selected_conditions(profile)
    primary_condition = _primary_condition(request.condition, selected_conditions)
    related_conditions = _related_conditions(primary_condition, selected_conditions)

    protocols = _protocols_for(related_conditions)
    safety_rules = _safety_rules_for(related_conditions)
    safety_matches = _match_safety_rules(safety_rules, request.text)
    highest_safety = safety_matches[0] if safety_matches else None
    memory_entries = _memory_entries(request.user, related_conditions, request.memory_limit)
    intake_status = assess_intake(
        primary_condition,
        dashboard_values=profile.dashboard_values if isinstance(profile.dashboard_values, dict) else {},
        transcript_lines=[request.text],
        intake_summary=profile.intake_summary,
        reminders=profile.reminders if isinstance(profile.reminders, list) else [],
        memory_entries=memory_entries,
    )

    return {
        "primary_condition": primary_condition,
        "selected_conditions": selected_conditions,
        "protocol_engine": {
            "protocol_ids": [protocol.protocol_id for protocol in protocols],
            "protocol_versions": {
                protocol.protocol_id: protocol.version for protocol in protocols
            },
            "review_status": {
                protocol.protocol_id: protocol.review_status for protocol in protocols
            },
            "evidence_source_ids": _evidence_source_ids(protocols),
            "must_use_protocol_ids": True,
            "safety_rules_override_normal_coaching": True,
        },
        "safety": {
            "must_escalate": bool(
                highest_safety
                and highest_safety["severity"]
                in (SafetyRule.Severity.EMERGENCY, SafetyRule.Severity.URGENT)
            ),
            "highest_severity": highest_safety["severity"] if highest_safety else "",
            "matches": safety_matches,
            "rules": [_safety_rule_payload(rule) for rule in safety_rules[:8]],
        },
        "protocols": [_protocol_payload(protocol) for protocol in protocols],
        "food_rules": [
            _food_rule_payload(rule) for rule in _food_rules_for(related_conditions)[:12]
        ],
        "intake_flows": [
            _intake_flow_payload(flow) for flow in _intake_flows_for(related_conditions)[:6]
        ],
        "reminder_scripts": [
            _reminder_payload(script)
            for script in _reminder_scripts_for(related_conditions)[:8]
        ],
        "report_blocks": [
            _report_block_payload(block) for block in _report_blocks_for(related_conditions)[:8]
        ],
        "outcome_metrics": [
            _metric_payload(metric) for metric in _outcome_metrics_for(related_conditions)[:12]
        ],
        "memory_schemas": [
            _memory_schema_payload(schema)
            for schema in _memory_schemas_for(related_conditions)[:8]
        ],
        "memory_timeline": [_memory_payload(entry) for entry in memory_entries],
        "intake_requirements": intake_status.to_payload(),
        "dashboard_seed": _dashboard_seed(profile, primary_condition, protocols, memory_entries),
        "ai_guardrails": _ai_guardrails(primary_condition, protocols),
    }


def _selected_conditions(profile: UserProfile) -> list[str]:
    selected = profile.selected_problems
    if not isinstance(selected, list):
        return []
    return _unique_clean(str(value) for value in selected)


def _primary_condition(requested: str, selected: list[str]) -> str:
    requested = requested.strip()
    if requested:
        return requested
    if selected:
        return selected[0]
    return "General wellness"


def _related_conditions(primary: str, selected: list[str]) -> list[str]:
    return _unique_clean([primary, *selected, "General wellness"])


def _protocols_for(conditions: list[str]) -> list[HealthProtocol]:
    return list(
        HealthProtocol.objects.filter(
            condition__in=conditions,
        )
        .exclude(review_status=HealthProtocol.ReviewStatus.DEPRECATED)
        .select_related("replaced_by")
        .prefetch_related("evidence__source", "source_chunks__source")
        .order_by("condition", "protocol_type", "-version")[:24]
    )


def _safety_rules_for(conditions: list[str]) -> list[SafetyRule]:
    rules = list(
        SafetyRule.objects.filter(condition__in=conditions)
        .select_related("protocol")
        .exclude(review_status=HealthProtocol.ReviewStatus.DEPRECATED)
    )
    return sorted(
        rules,
        key=lambda rule: (-SEVERITY_RANK.get(rule.severity, 0), rule.condition, rule.symptom_pattern),
    )


def _food_rules_for(conditions: list[str]) -> QuerySet[FoodRule]:
    return (
        FoodRule.objects.filter(condition__in=conditions)
        .select_related("protocol")
        .exclude(review_status=HealthProtocol.ReviewStatus.DEPRECATED)
        .order_by("condition", "food_name", "rule_type")
    )


def _intake_flows_for(conditions: list[str]) -> QuerySet[IntakeFlow]:
    return (
        IntakeFlow.objects.filter(condition__in=conditions, active=True)
        .select_related("protocol")
        .exclude(review_status=HealthProtocol.ReviewStatus.DEPRECATED)
        .order_by("condition", "priority", "flow_id")
    )


def _reminder_scripts_for(conditions: list[str]) -> QuerySet[ReminderScript]:
    return (
        ReminderScript.objects.filter(condition__in=conditions, active=True)
        .select_related("protocol")
        .order_by("condition", "trigger_type", "title")
    )


def _report_blocks_for(conditions: list[str]) -> QuerySet[ReportBlock]:
    return (
        ReportBlock.objects.filter(condition__in=conditions, active=True)
        .select_related("protocol")
        .exclude(review_status=HealthProtocol.ReviewStatus.DEPRECATED)
        .order_by("condition", "block_type", "title")
    )


def _outcome_metrics_for(conditions: list[str]) -> QuerySet[OutcomeMetric]:
    return OutcomeMetric.objects.filter(condition__in=conditions).order_by(
        "condition",
        "metric_key",
    )


def _memory_schemas_for(conditions: list[str]) -> QuerySet[MemorySchema]:
    return (
        MemorySchema.objects.filter(condition__in=conditions)
        .exclude(review_status=HealthProtocol.ReviewStatus.DEPRECATED)
        .order_by("condition", "category", "schema_key")
    )


def _memory_entries(user: User, conditions: list[str], limit: int) -> list[HealthMemoryEntry]:
    return list(
        HealthMemoryEntry.objects.filter(user=user)
        .filter(problem_name__in=conditions)
        .order_by("-occurred_at", "-created_at")[: max(1, min(50, limit))]
    )


def _match_safety_rules(rules: list[SafetyRule], text: str) -> list[dict]:
    normalized_text = _normalize(text)
    if not normalized_text:
        return []
    matches = []
    for rule in rules:
        tokens = [
            token
            for token in _normalize(rule.symptom_pattern).replace(",", " ").split()
            if len(token) >= 4
        ]
        if any(token in normalized_text for token in tokens):
            payload = _safety_rule_payload(rule)
            payload["matched_tokens"] = [
                token for token in tokens if token in normalized_text
            ][:8]
            matches.append(payload)
    return sorted(matches, key=lambda item: -SEVERITY_RANK.get(item["severity"], 0))


def _protocol_payload(protocol: HealthProtocol) -> dict:
    return {
        "protocol_id": protocol.protocol_id,
        "title": protocol.title,
        "condition": protocol.condition,
        "protocol_type": protocol.protocol_type,
        "summary": protocol.summary,
        "content": protocol.content,
        "rules": _list(protocol.rules),
        "tags": _list(protocol.tags),
        "risk_level": protocol.risk_level,
        "review_status": protocol.review_status,
        "version": protocol.version,
        "replaced_by_protocol_id": protocol.replaced_by.protocol_id
        if protocol.replaced_by
        else "",
        "evidence_source_ids": [
            evidence.source_id for evidence in protocol.evidence.all()
        ],
        "evidence": [
            {
                "source_id": evidence.source_id,
                "source_title": evidence.source.title,
                "publisher": evidence.source.publisher,
                "url": evidence.source.url,
                "chunk_uid": evidence.chunk.chunk_uid if evidence.chunk else "",
                "evidence_level": evidence.evidence_level,
                "note": evidence.note,
            }
            for evidence in protocol.evidence.all()
        ],
    }


def _safety_rule_payload(rule: SafetyRule) -> dict:
    return {
        "condition": rule.condition,
        "symptom_pattern": rule.symptom_pattern,
        "severity": rule.severity,
        "action": rule.action,
        "escalation_text": rule.escalation_text,
        "contraindications": _list(rule.contraindications),
        "protocol_id": rule.protocol.protocol_id if rule.protocol else "",
        "review_status": rule.review_status,
    }


def _food_rule_payload(rule: FoodRule) -> dict:
    return {
        "condition": rule.condition,
        "food_name": rule.food_name,
        "rule_type": rule.rule_type,
        "guidance": rule.guidance,
        "reason": rule.reason,
        "alternatives": _list(rule.alternatives),
        "safety_notes": rule.safety_notes,
        "protocol_id": rule.protocol.protocol_id if rule.protocol else "",
        "review_status": rule.review_status,
    }


def _intake_flow_payload(flow: IntakeFlow) -> dict:
    return {
        "flow_id": flow.flow_id,
        "condition": flow.condition,
        "title": flow.title,
        "questions": _list(flow.questions),
        "priority": flow.priority,
        "protocol_id": flow.protocol.protocol_id if flow.protocol else "",
        "review_status": flow.review_status,
    }


def _reminder_payload(script: ReminderScript) -> dict:
    return {
        "condition": script.condition,
        "trigger_type": script.trigger_type,
        "title": script.title,
        "script": script.script,
        "schedule_hint": script.schedule_hint,
        "channel": script.channel,
        "protocol_id": script.protocol.protocol_id if script.protocol else "",
    }


def _report_block_payload(block: ReportBlock) -> dict:
    return {
        "condition": block.condition,
        "block_type": block.block_type,
        "title": block.title,
        "markdown_template": block.markdown_template,
        "required_metrics": _list(block.required_metrics),
        "protocol_id": block.protocol.protocol_id if block.protocol else "",
        "review_status": block.review_status,
    }


def _metric_payload(metric: OutcomeMetric) -> dict:
    return {
        "metric_key": metric.metric_key,
        "condition": metric.condition,
        "label": metric.label,
        "unit": metric.unit,
        "normal_range": metric.normal_range,
        "high_risk_threshold": metric.high_risk_threshold,
        "dashboard_mapping": metric.dashboard_mapping,
    }


def _memory_schema_payload(schema: MemorySchema) -> dict:
    return {
        "schema_key": schema.schema_key,
        "condition": schema.condition,
        "category": schema.category,
        "json_schema": schema.json_schema,
        "extraction_prompt": schema.extraction_prompt,
        "review_status": schema.review_status,
    }


def _memory_payload(entry: HealthMemoryEntry) -> dict:
    return {
        "id": entry.id,
        "problem_name": entry.problem_name,
        "source": entry.source,
        "category": entry.category,
        "title": entry.title,
        "content": entry.content,
        "data": entry.data,
        "occurred_at": entry.occurred_at.isoformat(),
    }


def _evidence_source_ids(protocols: list[HealthProtocol]) -> dict[str, list[int]]:
    return {
        protocol.protocol_id: [
            evidence.source_id for evidence in protocol.evidence.all()
        ]
        for protocol in protocols
    }


def _dashboard_seed(
    profile: UserProfile,
    primary_condition: str,
    protocols: list[HealthProtocol],
    memory_entries: list[HealthMemoryEntry],
) -> dict:
    score = 68
    if profile.intake_completed:
        score += 8
    if profile.reminders:
        score += 6
    if memory_entries:
        score += 5
    score = min(92, score)
    return {
        "primary_problem": primary_condition,
        "score": score,
        "active_protocol_count": len(protocols),
        "latest_memory_count": len(memory_entries),
        "dashboard_values": profile.dashboard_values,
        "dashboard_notes": profile.dashboard_notes,
        "reminders": profile.reminders,
    }


def _ai_guardrails(condition: str, protocols: list[HealthProtocol]) -> list[str]:
    protocol_ids = ", ".join(protocol.protocol_id for protocol in protocols) or "none"
    return [
        f"Use the active condition context: {condition}.",
        f"Cite internal protocol IDs when using protocol guidance: {protocol_ids}.",
        "If a safety rule matches urgent or emergency severity, stop normal coaching and show escalation guidance.",
        "Do not diagnose, prescribe, or change medication. Education and tracking only.",
        "Keep public source corpus separate from private user memory.",
    ]


def _list(value) -> list:
    return value if isinstance(value, list) else []


def _normalize(value: str) -> str:
    return " ".join(value.lower().strip().split())


def _unique_clean(values: Iterable[str]) -> list[str]:
    seen: set[str] = set()
    result: list[str] = []
    for value in values:
        cleaned = " ".join(str(value).strip().split())
        key = cleaned.lower()
        if cleaned and key not in seen:
            seen.add(key)
            result.append(cleaned)
    return result
