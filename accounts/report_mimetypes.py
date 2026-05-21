from __future__ import annotations


REPORT_FILE_MIME_TYPES = {
    "pdf": "application/pdf",
    "html": "text/html; charset=utf-8",
}


def report_content_type(file_kind: str) -> str:
    return REPORT_FILE_MIME_TYPES.get(str(file_kind).lower(), "application/octet-stream")
