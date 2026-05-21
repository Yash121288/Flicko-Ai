from __future__ import annotations

import multiprocessing
import os


def _int(name: str, default: int) -> int:
    try:
        return int(os.getenv(name, str(default)))
    except (TypeError, ValueError):
        return default


bind = os.getenv("GUNICORN_BIND", "0.0.0.0:8000")
workers = _int("WEB_CONCURRENCY", max(2, multiprocessing.cpu_count() * 2 + 1))
threads = _int("GUNICORN_THREADS", 2)
timeout = _int("GUNICORN_TIMEOUT", 180)
graceful_timeout = _int("GUNICORN_GRACEFUL_TIMEOUT", 30)
keepalive = _int("GUNICORN_KEEPALIVE", 5)
accesslog = "-"
errorlog = "-"
loglevel = os.getenv("GUNICORN_LOG_LEVEL", os.getenv("DJANGO_LOG_LEVEL", "info")).lower()
worker_tmp_dir = "/dev/shm"
