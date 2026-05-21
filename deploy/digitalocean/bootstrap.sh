#!/usr/bin/env bash
set -Eeuo pipefail

APP_USER="${APP_USER:-deploy}"
APP_ROOT="${APP_ROOT:-/srv/flicko}"
APP_DIR="${APP_DIR:-${APP_ROOT}/backend}"
REPO_URL="${REPO_URL:-https://github.com/kartkbhalodiya/Flicko-Ai.git}"
SERVICE_NAME="${SERVICE_NAME:-flixo}"
DOMAIN="${DOMAIN:-api.example.com}"

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run as root: sudo bash deploy/digitalocean/bootstrap.sh"
  exit 1
fi

apt-get update
apt-get install -y python3-venv python3-pip nginx certbot python3-certbot-nginx git ufw

if ! id "${APP_USER}" >/dev/null 2>&1; then
  adduser --disabled-password --gecos "" "${APP_USER}"
  usermod -aG sudo "${APP_USER}"
fi

mkdir -p "${APP_ROOT}"
chown -R "${APP_USER}:${APP_USER}" "${APP_ROOT}"

if [[ ! -d "${APP_DIR}/.git" ]]; then
  runuser -u "${APP_USER}" -- git clone "${REPO_URL}" "${APP_DIR}"
else
  runuser -u "${APP_USER}" -- git -C "${APP_DIR}" pull --ff-only
fi

runuser -u "${APP_USER}" -- python3 -m venv "${APP_DIR}/.venv"
runuser -u "${APP_USER}" -- "${APP_DIR}/.venv/bin/pip" install --upgrade pip
runuser -u "${APP_USER}" -- "${APP_DIR}/.venv/bin/pip" install -r "${APP_DIR}/requirements.txt"

if [[ ! -f "${APP_DIR}/.env" ]]; then
  cp "${APP_DIR}/.env.example" "${APP_DIR}/.env"
  chown "${APP_USER}:${APP_USER}" "${APP_DIR}/.env"
fi

sed \
  -e "s|/srv/flicko/backend|${APP_DIR}|g" \
  -e "s|User=deploy|User=${APP_USER}|g" \
  "s|Description=Flicko Django backend|Description=${SERVICE_NAME} Django backend|g" \
  "${APP_DIR}/deploy/digitalocean/flixo.service.example" \
  > "/etc/systemd/system/${SERVICE_NAME}.service"

sed \
  "s|api.example.com|${DOMAIN}|g" \
  "${APP_DIR}/deploy/digitalocean/nginx.conf.example" \
  > "/etc/nginx/sites-available/${SERVICE_NAME}"

ln -sf "/etc/nginx/sites-available/${SERVICE_NAME}" "/etc/nginx/sites-enabled/${SERVICE_NAME}"
rm -f /etc/nginx/sites-enabled/default

systemctl daemon-reload
systemctl enable "${SERVICE_NAME}"

nginx -t
systemctl reload nginx

ufw allow OpenSSH || true
ufw allow 'Nginx Full' || true

cat <<EOF
Bootstrap complete.

Next steps:
1. Edit ${APP_DIR}/.env
2. Set DOMAIN=${DOMAIN} DNS to this Droplet IP
3. Run: sudo bash ${APP_DIR}/deploy/digitalocean/update.sh
4. Run: sudo certbot --nginx -d ${DOMAIN}
EOF
