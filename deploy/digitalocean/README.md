# DigitalOcean deployment guide

This backend is designed to run on a single DigitalOcean Droplet with:

- Django + Gunicorn on the Droplet
- Supabase PostgreSQL as the primary database
- Cloudinary raw storage for PDFs / HTML reports / uploads
- Nginx as the reverse proxy
- Let's Encrypt for TLS

This is the recommended deployment path for the current backend because:

1. report file access stays behind authenticated API routes
2. Gunicorn already has production config in `gunicorn.conf.py`
3. database and report-file storage are already externalized

## 1. Create the Droplet

Recommended baseline:

- Ubuntu 24.04 LTS
- Basic shared CPU, 2 GB RAM minimum
- Region close to your users and Supabase region
- Add your SSH key during droplet creation

Point your domain A record:

- `api.example.com` -> `<droplet_public_ip>`

## 2. First boot packages

SSH into the droplet and run:

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y python3-venv python3-pip nginx certbot python3-certbot-nginx git ufw
```

Optional firewall:

```bash
sudo ufw allow OpenSSH
sudo ufw allow 'Nginx Full'
sudo ufw --force enable
```

## 3. Create deploy user

```bash
sudo adduser deploy
sudo usermod -aG sudo deploy
sudo mkdir -p /srv/flicko
sudo chown -R deploy:deploy /srv/flicko
```

## 4. Clone the backend repo

As the `deploy` user:

```bash
cd /srv/flicko
git clone https://github.com/kartkbhalodiya/Flicko-Ai.git backend
cd backend
python3 -m venv .venv
source .venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt
```

## 5. Configure environment

```bash
cd /srv/flicko/backend
cp .env.example .env
nano .env
```

Minimum production values:

```env
DJANGO_SECRET_KEY=replace-with-long-random-secret
DJANGO_DEBUG=false
DJANGO_ALLOWED_HOSTS=api.example.com
CORS_ALLOWED_ORIGINS=https://your-flutter-web-domain.example
CSRF_TRUSTED_ORIGINS=https://api.example.com
DJANGO_SECURE_SSL_REDIRECT=true
SESSION_COOKIE_SECURE=true
CSRF_COOKIE_SECURE=true
SECURE_HSTS_SECONDS=31536000
SECURE_HSTS_INCLUDE_SUBDOMAINS=true
SECURE_HSTS_PRELOAD=false
DJANGO_LOG_LEVEL=INFO

DATABASE_URL=postgresql://postgres.project:password@aws-0-region.pooler.supabase.com:6543/postgres
DATABASE_SSL_REQUIRE=true
DATABASE_CONN_MAX_AGE=600

USE_CLOUDINARY_MEDIA=true
CLOUDINARY_CLOUD_NAME=your-cloudinary-cloud
CLOUDINARY_API_KEY=your-cloudinary-key
CLOUDINARY_API_SECRET=your-cloudinary-secret
CLOUDINARY_MEDIA_PREFIX=flicko
CLOUDINARY_DELIVERY_TYPE=authenticated
CLOUDINARY_INVALIDATE=true

EMAIL_HOST=smtp.gmail.com
EMAIL_PORT=587
EMAIL_HOST_USER=your-email@gmail.com
EMAIL_HOST_PASSWORD=your-app-password
EMAIL_USE_TLS=true
DEFAULT_FROM_EMAIL=Flicko AI <no-reply@yourdomain.com>

GOOGLE_OAUTH_CLIENT_IDS=your-web-client-id.apps.googleusercontent.com
GROQ_API_KEY=optional-groq-key
```

## 6. Run first-time backend checks

```bash
cd /srv/flicko/backend
source .venv/bin/activate
python manage.py check
python manage.py migrate
python manage.py collectstatic --noinput
python manage.py createsuperuser
curl http://127.0.0.1:8000/api/auth/health/ || true
```

## 7. Install systemd service

Copy the example:

```bash
sudo cp deploy/digitalocean/flixo.service.example /etc/systemd/system/flixo.service
sudo systemctl daemon-reload
sudo systemctl enable flixo
sudo systemctl start flixo
sudo systemctl status flixo
```

View logs:

```bash
sudo journalctl -u flixo -f
```

If you want to automate the first boot instead of running each step manually:

```bash
sudo DOMAIN=api.example.com bash deploy/digitalocean/bootstrap.sh
```

## 8. Install Nginx reverse proxy

```bash
sudo cp deploy/digitalocean/nginx.conf.example /etc/nginx/sites-available/flixo
sudo ln -sf /etc/nginx/sites-available/flixo /etc/nginx/sites-enabled/flixo
sudo nginx -t
sudo systemctl reload nginx
```

## 9. Add HTTPS

```bash
sudo certbot --nginx -d api.example.com
```

After TLS is issued:

```bash
curl https://api.example.com/api/auth/health/
```

Expected result:

- `database: ok`
- `storage: cloudinary`
- `status: ok`

## 10. Update on deploy

```bash
cd /srv/flicko/backend
git pull
source .venv/bin/activate
pip install -r requirements.txt
python manage.py migrate
python manage.py collectstatic --noinput
sudo systemctl restart flixo
sudo systemctl status flixo
```

Or use the included update script:

```bash
sudo bash /srv/flicko/backend/deploy/digitalocean/update.sh
```

## Operational notes

1. Report PDFs and HTML files are fetched through authenticated API routes:
   - `/api/auth/intake-reports/<id>/pdf/`
   - `/api/auth/intake-reports/<id>/html/`
2. This means application uptime matters for report downloads even though files live in Cloudinary.
3. `CLOUDINARY_DELIVERY_TYPE=authenticated` is the correct default for health-report privacy.
4. Supabase should remain the only primary relational database.
5. Do not store production `.env`, local SQLite files, or `media/` in git.

## Optional log rotation

Gunicorn currently logs to journald through systemd, so app logs are not file-rotated here.

If you later switch to file-based logs under `/var/log/flicko/`, use:

```bash
sudo cp deploy/digitalocean/logrotate-flixo.conf.example /etc/logrotate.d/flixo
```
