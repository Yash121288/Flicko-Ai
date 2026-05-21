from __future__ import annotations

import json
from pathlib import Path

from django.conf import settings
from django.core.management.base import BaseCommand

from accounts.intake_requirements import intake_schema_payload


class Command(BaseCommand):
    help = "Export the shared intake schema JSON asset used by the Flutter app."

    def add_arguments(self, parser) -> None:
        parser.add_argument(
            "--output",
            default="",
            help="Optional output path. Defaults to apps/mobile/assets/health_protocols/flicko_intake_schema_v1.json",
        )

    def handle(self, *args, **options) -> None:
        output = str(options.get("output") or "").strip()
        target = Path(output) if output else (
            Path(settings.BASE_DIR).parent
            / "mobile"
            / "assets"
            / "health_protocols"
            / "flicko_intake_schema_v1.json"
        )
        target.parent.mkdir(parents=True, exist_ok=True)
        payload = intake_schema_payload()
        target.write_text(f"{json.dumps(payload, indent=2)}\n", encoding="utf-8")
        self.stdout.write(self.style.SUCCESS(f"Exported intake schema to {target}"))
