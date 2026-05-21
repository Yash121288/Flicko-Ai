from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from django.conf import settings
from django.core.management.base import BaseCommand, CommandError
from django.db import transaction
from django.utils import timezone

from accounts.models import (
    FoodRule,
    HealthCorpusChunk,
    HealthProtocol,
    HealthSourceDocument,
    IntakeFlow,
    MemorySchema,
    OutcomeMetric,
    ProtocolEvidence,
    ReminderScript,
    ReportBlock,
    SafetyRule,
)


class Command(BaseCommand):
    help = "Import Flicko health corpus JSONL files into source, protocol, food, safety, and flow tables."

    def add_arguments(self, parser):
        parser.add_argument(
            "--base-dir",
            default=str(settings.BASE_DIR / "data" / "health_corpus"),
            help="Corpus root. Defaults to apps/backend/data/health_corpus.",
        )
        parser.add_argument(
            "--dry-run",
            action="store_true",
            help="Validate files and print counts without writing records.",
        )

    @transaction.atomic
    def handle(self, *args, **options):
        base_dir = Path(options["base_dir"])
        if not base_dir.exists():
            raise CommandError(f"Corpus directory does not exist: {base_dir}")

        stats: dict[str, int] = {}
        dry_run = bool(options["dry_run"])

        stats["sources"] = self._import_sources(base_dir)
        stats["chunks"] = self._import_chunks(base_dir)
        stats["protocols"] = self._import_protocols(base_dir)
        stats["food_rules"] = self._import_food_rules(base_dir)
        stats["safety_rules"] = self._import_safety_rules(base_dir)
        stats["intake_flows"] = self._import_intake_flows(base_dir)
        stats["reminder_scripts"] = self._import_reminder_scripts(base_dir)
        stats["report_blocks"] = self._import_report_blocks(base_dir)
        stats["outcome_metrics"] = self._import_outcome_metrics(base_dir)
        stats["memory_schemas"] = self._import_memory_schemas(base_dir)

        if dry_run:
            transaction.set_rollback(True)

        mode = "Validated" if dry_run else "Imported"
        summary = ", ".join(f"{key}={value}" for key, value in stats.items())
        self.stdout.write(self.style.SUCCESS(f"{mode} health corpus: {summary}"))

    def _import_sources(self, base_dir: Path) -> int:
        count = 0
        for row in self._rows(base_dir / "source_registry"):
            url = self._required(row, "url")
            defaults = {
                "title": self._required(row, "title"),
                "publisher": self._required(row, "publisher"),
                "source_type": row.get("source_type") or HealthSourceDocument.SourceType.WEB_PAGE,
                "language": row.get("language") or "en",
                "country_scope": row.get("country_scope", ""),
                "license_note": row.get("license_note", ""),
                "file_path": row.get("file_path", ""),
                "checksum_sha256": row.get("checksum_sha256", ""),
                "fetched_at": self._parse_datetime(row.get("fetched_at")),
                "last_reviewed_at": self._parse_datetime(row.get("last_reviewed_at")),
                "is_public": bool(row.get("is_public", True)),
                "metadata": row.get("metadata") or {},
            }
            HealthSourceDocument.objects.update_or_create(url=url, defaults=defaults)
            count += 1
        return count

    def _import_chunks(self, base_dir: Path) -> int:
        count = 0
        for row in self._rows(base_dir / "normalized_chunks"):
            source = self._source_for(row)
            HealthCorpusChunk.objects.update_or_create(
                chunk_uid=self._required(row, "chunk_uid"),
                defaults={
                    "source": source,
                    "title": self._required(row, "title"),
                    "condition": row.get("condition", ""),
                    "section_type": row.get("section_type") or HealthCorpusChunk.SectionType.GENERAL,
                    "text": self._required(row, "text"),
                    "token_count": int(row.get("token_count") or 0),
                    "embedding_key": row.get("embedding_key", ""),
                    "metadata": row.get("metadata") or {},
                },
            )
            count += 1
        return count

    def _import_protocols(self, base_dir: Path) -> int:
        count = 0
        for row in self._rows(base_dir / "protocols"):
            protocol, _ = HealthProtocol.objects.update_or_create(
                protocol_id=self._required(row, "protocol_id"),
                defaults={
                    "title": self._required(row, "title"),
                    "condition": self._required(row, "condition"),
                    "protocol_type": self._required(row, "protocol_type"),
                    "summary": row.get("summary", ""),
                    "content": self._required(row, "content"),
                    "rules": self._list(row.get("rules")),
                    "tags": self._list(row.get("tags")),
                    "risk_level": row.get("risk_level") or HealthProtocol.RiskLevel.LOW,
                    "review_status": row.get("review_status")
                    or HealthProtocol.ReviewStatus.UNREVIEWED,
                    "version": int(row.get("version") or 1),
                },
            )
            chunk_uids = self._list(row.get("source_chunk_uids"))
            if chunk_uids:
                protocol.source_chunks.set(
                    HealthCorpusChunk.objects.filter(chunk_uid__in=chunk_uids)
                )
            for evidence in self._list(row.get("evidence")):
                if isinstance(evidence, dict):
                    self._upsert_evidence(protocol, evidence)
            count += 1
        return count

    def _import_food_rules(self, base_dir: Path) -> int:
        count = 0
        for row in self._rows(base_dir / "food_rules"):
            FoodRule.objects.update_or_create(
                condition=self._required(row, "condition"),
                food_name=self._required(row, "food_name"),
                rule_type=self._required(row, "rule_type"),
                defaults={
                    "cuisine_context": row.get("cuisine_context", ""),
                    "guidance": self._required(row, "guidance"),
                    "reason": row.get("reason", ""),
                    "alternatives": self._list(row.get("alternatives")),
                    "tags": self._list(row.get("tags")),
                    "safety_notes": row.get("safety_notes", ""),
                    "protocol": self._protocol_for(row),
                    "review_status": row.get("review_status")
                    or HealthProtocol.ReviewStatus.UNREVIEWED,
                },
            )
            count += 1
        return count

    def _import_safety_rules(self, base_dir: Path) -> int:
        count = 0
        for row in self._rows(base_dir / "safety_rules"):
            SafetyRule.objects.update_or_create(
                condition=self._required(row, "condition"),
                symptom_pattern=self._required(row, "symptom_pattern"),
                severity=self._required(row, "severity"),
                defaults={
                    "action": self._required(row, "action"),
                    "escalation_text": row.get("escalation_text", ""),
                    "contraindications": self._list(row.get("contraindications")),
                    "protocol": self._protocol_for(row),
                    "review_status": row.get("review_status")
                    or HealthProtocol.ReviewStatus.UNREVIEWED,
                },
            )
            count += 1
        return count

    def _import_intake_flows(self, base_dir: Path) -> int:
        count = 0
        for row in self._rows(base_dir / "flows"):
            IntakeFlow.objects.update_or_create(
                flow_id=self._required(row, "flow_id"),
                defaults={
                    "condition": self._required(row, "condition"),
                    "title": self._required(row, "title"),
                    "questions": self._list(row.get("questions")),
                    "priority": int(row.get("priority") or 100),
                    "active": bool(row.get("active", True)),
                    "review_status": row.get("review_status")
                    or HealthProtocol.ReviewStatus.UNREVIEWED,
                    "protocol": self._protocol_for(row),
                },
            )
            count += 1
        return count

    def _import_reminder_scripts(self, base_dir: Path) -> int:
        count = 0
        for row in self._rows(base_dir / "reminders"):
            ReminderScript.objects.update_or_create(
                condition=self._required(row, "condition"),
                trigger_type=self._required(row, "trigger_type"),
                title=self._required(row, "title"),
                defaults={
                    "script": self._required(row, "script"),
                    "schedule_hint": row.get("schedule_hint", ""),
                    "channel": row.get("channel") or ReminderScript.Channel.PUSH,
                    "active": bool(row.get("active", True)),
                    "protocol": self._protocol_for(row),
                },
            )
            count += 1
        return count

    def _import_report_blocks(self, base_dir: Path) -> int:
        count = 0
        for row in self._rows(base_dir / "reports"):
            ReportBlock.objects.update_or_create(
                condition=self._required(row, "condition"),
                block_type=self._required(row, "block_type"),
                title=self._required(row, "title"),
                defaults={
                    "markdown_template": self._required(row, "markdown_template"),
                    "required_metrics": self._list(row.get("required_metrics")),
                    "active": bool(row.get("active", True)),
                    "review_status": row.get("review_status")
                    or HealthProtocol.ReviewStatus.UNREVIEWED,
                    "protocol": self._protocol_for(row),
                },
            )
            count += 1
        return count

    def _import_outcome_metrics(self, base_dir: Path) -> int:
        count = 0
        for row in self._rows(base_dir / "metrics"):
            OutcomeMetric.objects.update_or_create(
                metric_key=self._required(row, "metric_key"),
                defaults={
                    "condition": self._required(row, "condition"),
                    "label": self._required(row, "label"),
                    "unit": row.get("unit", ""),
                    "normal_range": row.get("normal_range", ""),
                    "high_risk_threshold": row.get("high_risk_threshold", ""),
                    "dashboard_mapping": row.get("dashboard_mapping") or {},
                },
            )
            count += 1
        return count

    def _import_memory_schemas(self, base_dir: Path) -> int:
        count = 0
        for row in self._rows(base_dir / "memory_schemas"):
            MemorySchema.objects.update_or_create(
                schema_key=self._required(row, "schema_key"),
                defaults={
                    "condition": self._required(row, "condition"),
                    "category": self._required(row, "category"),
                    "json_schema": row.get("json_schema") or {},
                    "extraction_prompt": row.get("extraction_prompt", ""),
                    "review_status": row.get("review_status")
                    or HealthProtocol.ReviewStatus.UNREVIEWED,
                },
            )
            count += 1
        return count

    def _rows(self, directory: Path):
        if not directory.exists():
            return
        for path in sorted(directory.glob("*.jsonl")):
            with path.open("r", encoding="utf-8") as handle:
                for line_number, line in enumerate(handle, start=1):
                    stripped = line.strip()
                    if not stripped or stripped.startswith("#"):
                        continue
                    try:
                        row = json.loads(stripped)
                    except json.JSONDecodeError as exc:
                        raise CommandError(f"{path}:{line_number} invalid JSON: {exc}") from exc
                    if not isinstance(row, dict):
                        raise CommandError(f"{path}:{line_number} row must be a JSON object")
                    yield row

    def _source_for(self, row: dict[str, Any]) -> HealthSourceDocument:
        url = row.get("source_url")
        if url:
            source = HealthSourceDocument.objects.filter(url=url).first()
            if source:
                return source
        title = row.get("source_title")
        if title:
            source = HealthSourceDocument.objects.filter(title=title).first()
            if source:
                return source
        raise CommandError(f"Missing source for row: {row}")

    def _protocol_for(self, row: dict[str, Any]) -> HealthProtocol | None:
        protocol_id = row.get("protocol_id")
        if not protocol_id:
            return None
        return HealthProtocol.objects.filter(protocol_id=protocol_id).first()

    def _upsert_evidence(self, protocol: HealthProtocol, evidence: dict[str, Any]) -> None:
        source = self._source_for(evidence)
        chunk = None
        chunk_uid = evidence.get("chunk_uid")
        if chunk_uid:
            chunk = HealthCorpusChunk.objects.filter(chunk_uid=chunk_uid).first()
        ProtocolEvidence.objects.update_or_create(
            protocol=protocol,
            source=source,
            chunk=chunk,
            defaults={
                "evidence_level": evidence.get("evidence_level", ""),
                "note": evidence.get("note", ""),
                "quote": evidence.get("quote", ""),
            },
        )

    def _required(self, row: dict[str, Any], key: str) -> str:
        value = row.get(key)
        if value is None or str(value).strip() == "":
            raise CommandError(f"Missing required field '{key}' in row: {row}")
        return str(value).strip()

    def _list(self, value: Any) -> list:
        if value is None:
            return []
        if isinstance(value, list):
            return value
        return [value]

    def _parse_datetime(self, value: Any):
        if not value:
            return None
        if isinstance(value, str):
            parsed = timezone.datetime.fromisoformat(value.replace("Z", "+00:00"))
            if timezone.is_naive(parsed):
                return timezone.make_aware(parsed)
            return parsed
        return value
