#!/usr/bin/env bash
set -Eeuo pipefail

APP_USER="${APP_USER:-deploy}"
APP_ROOT="${APP_ROOT:-/srv/flicko}"
APP_DIR="${APP_DIR:-${APP_ROOT}/backend}"
SERVICE_NAME="${SERVICE_NAME:-flixo}"
HEALTH_URL="${HEALTH_URL:-http://127.0.0.1:8000/api/auth/health/}"

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run as root: sudo bash deploy/digitalocean/update.sh"
  exit 1
fi

if [[ ! -d "${APP_DIR}" ]]; then
  echo "Missing app directory: ${APP_DIR}"
  exit 1
fi

if [[ ! -f "${APP_DIR}/.env" ]]; then
  echo "Missing ${APP_DIR}/.env"
  exit 1
fi

runuser -u "${APP_USER}" -- git -C "${APP_DIR}" pull --ff-only
runuser -u "${APP_USER}" -- "${APP_DIR}/.venv/bin/pip" install -r "${APP_DIR}/requirements.txt"
runuser -u "${APP_USER}" -- bash -lc "cd '${APP_DIR}' && .venv/bin/python manage.py check"
runuser -u "${APP_USER}" -- bash -lc "cd '${APP_DIR}' && .venv/bin/python manage.py migrate"
runuser -u "${APP_USER}" -- bash -lc "cd '${APP_DIR}' && .venv/bin/python manage.py collectstatic --noinput"

systemctl restart "${SERVICE_NAME}"
systemctl --no-pager --full status "${SERVICE_NAME}" || true
nginx -t
systemctl reload nginx

sleep 3
curl --fail --silent --show-error "${HEALTH_URL}"
echo
echo "Update complete."
