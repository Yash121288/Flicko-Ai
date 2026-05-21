#!/usr/bin/env bash
set -Eeuo pipefail

APP_USER="${APP_USER:-deploy}"
APP_ROOT="${APP_ROOT:-/srv/flicko}"
APP_DIR="${APP_DIR:-${APP_ROOT}/backend}"
BACKUP_ROOT="${BACKUP_ROOT:-/var/backups/flicko}"
KEEP_DAYS="${KEEP_DAYS:-14}"

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run as root: sudo bash deploy/digitalocean/backup.sh"
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

set -a
# shellcheck disable=SC1090
source "${APP_DIR}/.env"
set +a

if [[ -z "${DATABASE_URL:-}" ]]; then
  echo "DATABASE_URL is missing in ${APP_DIR}/.env"
  exit 1
fi

STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
TARGET_DIR="${BACKUP_ROOT}/${STAMP}"
mkdir -p "${TARGET_DIR}"
chown -R "${APP_USER}:${APP_USER}" "${BACKUP_ROOT}"

runuser -u "${APP_USER}" -- pg_dump "${DATABASE_URL}" --format=custom --compress=9 --file="${TARGET_DIR}/postgres.dump"
runuser -u "${APP_USER}" -- git -C "${APP_DIR}" rev-parse HEAD > "${TARGET_DIR}/git_sha.txt"
runuser -u "${APP_USER}" -- "${APP_DIR}/.venv/bin/pip" freeze > "${TARGET_DIR}/requirements.lock"
runuser -u "${APP_USER}" -- bash -lc "cd '${APP_DIR}' && .venv/bin/python manage.py showmigrations" > "${TARGET_DIR}/migrations.txt"
runuser -u "${APP_USER}" -- bash -lc "cd '${APP_DIR}' && .venv/bin/python manage.py shell -c \"import json; from accounts.models import HealthIntakeReport; rows=list(HealthIntakeReport.objects.values('id','title','problem_name','pdf_file','html_file','created_at')); print(json.dumps(rows, default=str))\"" > "${TARGET_DIR}/report_file_manifest.json"

cat > "${TARGET_DIR}/backup_meta.txt" <<EOF
timestamp_utc=${STAMP}
app_dir=${APP_DIR}
backup_root=${BACKUP_ROOT}
cloudinary_delivery_type=${CLOUDINARY_DELIVERY_TYPE:-unknown}
cloudinary_media_prefix=${CLOUDINARY_MEDIA_PREFIX:-unknown}
database_ssl_require=${DATABASE_SSL_REQUIRE:-unknown}
EOF

find "${BACKUP_ROOT}" -mindepth 1 -maxdepth 1 -type d -mtime +"${KEEP_DAYS}" -exec rm -rf {} +

echo "Backup complete: ${TARGET_DIR}"
