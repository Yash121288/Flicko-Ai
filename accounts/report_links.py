from __future__ import annotations

from django.urls import reverse


def report_file_path(report_id: int, file_kind: str) -> str:
    return reverse(
        "health-intake-report-file",
        kwargs={"report_id": int(report_id), "file_kind": str(file_kind)},
    )


def report_file_url(request, report_id: int, file_kind: str) -> str:
    path = report_file_path(report_id, file_kind)
    return request.build_absolute_uri(path) if request else path
