from __future__ import annotations

from django.core import signing
from django.urls import reverse

REPORT_FILE_ACCESS_SALT = "accounts.report-file-access"
REPORT_FILE_ACCESS_MAX_AGE_SECONDS = 60 * 20


def report_file_path(report_id: int, file_kind: str) -> str:
    return reverse(
        "health-intake-report-file",
        kwargs={"report_id": int(report_id), "file_kind": str(file_kind)},
    )


def report_file_url(request, report_id: int, file_kind: str) -> str:
    path = report_file_path(report_id, file_kind)
    return request.build_absolute_uri(path) if request else path


def report_file_access_token(*, report_id: int, user_id: int, file_kind: str) -> str:
    return signing.dumps(
        {
            "report_id": int(report_id),
            "user_id": int(user_id),
            "file_kind": str(file_kind).strip().lower(),
        },
        salt=REPORT_FILE_ACCESS_SALT,
        compress=True,
    )


def load_report_file_access_token(token: str, *, report_id: int, file_kind: str) -> int | None:
    clean_token = str(token or "").strip()
    if not clean_token:
        return None
    try:
        payload = signing.loads(
            clean_token,
            salt=REPORT_FILE_ACCESS_SALT,
            max_age=REPORT_FILE_ACCESS_MAX_AGE_SECONDS,
        )
    except signing.BadSignature:
        return None

    payload_report_id = int(payload.get("report_id") or 0)
    payload_file_kind = str(payload.get("file_kind") or "").strip().lower()
    payload_user_id = int(payload.get("user_id") or 0)
    if (
        payload_report_id != int(report_id)
        or payload_file_kind != str(file_kind).strip().lower()
        or payload_user_id <= 0
    ):
        return None
    return payload_user_id


def report_open_url(request, report, file_kind: str) -> str:
    report_file = report.pdf_file if str(file_kind).strip().lower() == "pdf" else report.html_file
    if not report_file:
        return ""
    file_url = str(report_file.url or "").strip()
    if not file_url:
        return ""
    if file_url.startswith(("http://", "https://")):
        return file_url
    return request.build_absolute_uri(file_url) if request else file_url
