from __future__ import annotations

from django.db.backends.signals import connection_created


def configure_sqlite_connection(sender, connection, **kwargs) -> None:
    if connection.vendor != "sqlite":
        return

    with connection.cursor() as cursor:
        cursor.execute("PRAGMA busy_timeout = 30000")
        cursor.execute("PRAGMA journal_mode = WAL")
        cursor.execute("PRAGMA synchronous = NORMAL")


def register_sqlite_pragmas() -> None:
    connection_created.connect(
        configure_sqlite_connection,
        dispatch_uid="accounts.configure_sqlite_connection",
    )
