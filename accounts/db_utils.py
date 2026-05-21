from __future__ import annotations

from collections.abc import Callable
from contextlib import contextmanager
from threading import RLock
from time import sleep
from typing import TypeVar

from django.contrib.auth.models import AnonymousUser, User
from django.db import OperationalError, transaction


T = TypeVar("T")

_registry_lock = RLock()
_user_write_locks: dict[str, RLock] = {}


def run_user_write(
    user: User | AnonymousUser,
    operation: Callable[[], T],
    *,
    attempts: int = 7,
    base_delay_seconds: float = 0.08,
) -> T:
    """Serialize writes for one user and retry transient SQLite lock errors.

    SQLite has a single-writer model. The app can legitimately send profile,
    reminder, task, report, and chat sync requests together, so local/dev
    backend writes must be short, serialized, and retried.
    """

    def guarded_operation() -> T:
        with user_write_lock(user), transaction.atomic():
            return operation()

    return run_sqlite_lock_retry(
        guarded_operation,
        attempts=attempts,
        base_delay_seconds=base_delay_seconds,
    )


def run_sqlite_lock_retry(
    operation: Callable[[], T],
    *,
    attempts: int = 7,
    base_delay_seconds: float = 0.08,
) -> T:
    last_error: OperationalError | None = None
    for attempt in range(max(1, attempts)):
        try:
            return operation()
        except OperationalError as error:
            if not is_sqlite_locked(error):
                raise
            last_error = error
            if attempt >= attempts - 1:
                break
            sleep(min(1.2, base_delay_seconds * (2**attempt)))
    raise last_error or OperationalError("database is locked")


@contextmanager
def user_write_lock(user: User | AnonymousUser):
    key = _user_lock_key(user)
    with _registry_lock:
        lock = _user_write_locks.setdefault(key, RLock())
    with lock:
        yield


def is_sqlite_locked(error: BaseException) -> bool:
    text = " ".join(str(arg).lower() for arg in getattr(error, "args", ()))
    return "database is locked" in text or "database table is locked" in text


def _user_lock_key(user: User | AnonymousUser) -> str:
    user_id = getattr(user, "pk", None)
    if user_id is not None:
        return f"user:{user_id}"
    return "anonymous"
