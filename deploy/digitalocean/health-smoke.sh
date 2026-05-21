#!/usr/bin/env bash
set -Eeuo pipefail

SERVICE_NAME="${SERVICE_NAME:-flixo}"
LOCAL_HEALTH_URL="${LOCAL_HEALTH_URL:-http://127.0.0.1:8000/api/auth/health/}"
PUBLIC_HEALTH_URL="${PUBLIC_HEALTH_URL:-}"
EXPECT_STORAGE="${EXPECT_STORAGE:-cloudinary}"
EXPECT_DATABASE="${EXPECT_DATABASE:-ok}"

check_json() {
  local label="$1"
  local payload="$2"
  local expect_storage="$3"
  local expect_database="$4"

  python3 - "$label" "$payload" "$expect_storage" "$expect_database" <<'PY'
import json
import sys

label, payload, expect_storage, expect_database = sys.argv[1:5]
data = json.loads(payload)
database = data.get("database")
storage = data.get("storage")
status = data.get("status")
if status != "ok":
    raise SystemExit(f"{label}: health status is {status!r}")
if database != expect_database:
    raise SystemExit(f"{label}: database expected {expect_database!r} but got {database!r}")
if storage != expect_storage:
    raise SystemExit(f"{label}: storage expected {expect_storage!r} but got {storage!r}")
print(f"{label}: ok database={database} storage={storage}")
PY
}

if command -v systemctl >/dev/null 2>&1; then
  systemctl is-active --quiet "${SERVICE_NAME}" || {
    echo "Systemd service ${SERVICE_NAME} is not active"
    exit 1
  }
  echo "systemd:${SERVICE_NAME}: active"
fi

LOCAL_PAYLOAD="$(curl --fail --silent --show-error "${LOCAL_HEALTH_URL}")"
check_json "local" "${LOCAL_PAYLOAD}" "${EXPECT_STORAGE}" "${EXPECT_DATABASE}"

if [[ -n "${PUBLIC_HEALTH_URL}" ]]; then
  PUBLIC_PAYLOAD="$(curl --fail --silent --show-error "${PUBLIC_HEALTH_URL}")"
  check_json "public" "${PUBLIC_PAYLOAD}" "${EXPECT_STORAGE}" "${EXPECT_DATABASE}"
fi

echo "Health smoke passed."
