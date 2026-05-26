# Flicko AI

<p align="center">
  <img src="apps/mobile/assets/images/mainlogo.png" alt="Flicko AI logo" width="240" />
</p>

<h3 align="center">AI health coaching, live care calls, meal intelligence, reminders, and doctor-ready reports in one app.</h3>

<p align="center">
  <a href="#app-experience">App Experience</a> |
  <a href="#features">Features</a> |
  <a href="#architecture">Architecture</a> |
  <a href="#quick-start">Quick Start</a> |
  <a href="#deployment">Deployment</a>
</p>

<p align="center">
  <img alt="Flutter" src="https://img.shields.io/badge/Flutter-3.41-02569B?logo=flutter&logoColor=white" />
  <img alt="Django" src="https://img.shields.io/badge/Django-Backend-092E20?logo=django&logoColor=white" />
  <img alt="Android" src="https://img.shields.io/badge/Android-Live%20Calls-3DDC84?logo=android&logoColor=white" />
  <img alt="Reports" src="https://img.shields.io/badge/Reports-PDF%20%2B%20HTML-111827" />
</p>


## App Experience

Flicko AI is built as a real mobile-first health companion. The repository includes production app assets, Flutter source, native Android call services, local protocol packs, Django APIs, authenticated report delivery, and production deploy scripts.

<table>
  <tr>
    <td width="50%">
      <img src="apps/mobile/assets/images/demo_call.png" alt="Flicko live AI call" />
      <br />
      <strong>Live AI health calls</strong>
      <br />
      Voice-first guided check-ins, missed-task follow-ups, setup calls, and resumable call workflows.
    </td>
    <td width="50%">
      <img src="apps/mobile/assets/images/demo_meal.png" alt="Flicko meal photo analysis" />
      <br />
      <strong>Meal photo intelligence</strong>
      <br />
      Image-based meal review with condition-aware nutrition scoring and practical recommendations.
    </td>
  </tr>
  <tr>
    <td width="50%">
      <img src="apps/mobile/assets/images/dashboard/ai_coach.png" alt="Flicko AI coach" />
      <br />
      <strong>AI coach dashboard</strong>
      <br />
      Personalized guidance from profile context, health logs, reports, reminders, and call memory.
    </td>
    <td width="50%">
      <img src="apps/mobile/assets/images/dashboard/weekly_report.png" alt="Flicko weekly report" />
      <br />
      <strong>Structured reports</strong>
      <br />
      Setup, weekly, and special reports backed by app state and authenticated backend files.
    </td>
  </tr>
</table>

## Features

| Area | What Flicko AI does |
| --- | --- |
| Guided onboarding | Captures health problem, profile details, safety consent, baseline metrics, and setup context. |
| Live AI calls | Runs call warmup, opening generation, transcript memory, interruption recovery, invite scheduling, and native foreground call handling. |
| Health dashboard | Shows condition-specific insights, logs, care tasks, reminders, BMI, diabetes data, safety alerts, and report history. |
| Meal analysis | Reviews meal photos with Gemini-powered image prompts and stores meal analysis entries for dashboard context. |
| Care management | Tracks reminders, missed tasks, completed follow-ups, quick health logs, and syncable app records. |
| Reports | Creates PDF and HTML intake reports, protects file access behind authenticated API routes, and supports Cloudinary storage. |
| Backend sync | Hydrates profile state, app data, reports, reminders, call memory, chat history, health logs, and safety events. |

## Architecture

```text
Flicko-Ai
|-- apps/mobile/                 Flutter mobile app
|   |-- lib/features/dashboard/  AI calls, dashboard, reports, chat, management
|   |-- lib/features/meals/      Meal photo analysis
|   |-- lib/features/reminders/  Local notification and reminder logic
|   |-- android/                 Native Android call service and foreground call support
|   |-- assets/                  Real app artwork, protocol packs, audio, icons
|   `-- test/                    Focused Flutter unit and widget tests
|
|-- accounts/                    Django auth, profile, reports, memory, sync APIs
|-- flixo_backend/               Django project settings and WSGI config
|-- deploy/digitalocean/         Droplet runbook, systemd, Nginx, backup, smoke scripts
|-- data/health_corpus/          Seed protocol and health-corpus data
|-- Dockerfile                   Production backend image
`-- requirements.txt             Backend dependencies
```

### Data flow

```text
Flutter app
  -> Token auth and profile sync
  -> Django REST API
  -> Supabase PostgreSQL for durable records
  -> Cloudinary for authenticated report files
  -> Mobile dashboard, calls, reminders, and reports
```

## Quick Start

### 1. Run the Django backend

```powershell
python -m venv .venv
.venv\Scripts\activate
pip install -r requirements.txt
python manage.py migrate
python manage.py runserver 0.0.0.0:8000
```

Development email OTPs print in the console unless SMTP credentials are configured.

### 2. Run the Flutter app

```powershell
cd apps\mobile
flutter pub get
flutter run --dart-define=FLICKO_API_BASE_URL=http://YOUR_PC_IP:8000/api
```

For Android emulator backend access, use:

```powershell
flutter run --dart-define=FLICKO_API_BASE_URL=http://10.0.2.2:8000/api
```

### 3. Enable Gemini features

Gemini keys are intentionally not committed. Pass them at build or run time:

```powershell
flutter run `
  --dart-define=FLICKO_API_BASE_URL=http://YOUR_PC_IP:8000/api `
  --dart-define=FLICKO_GEMINI_API_KEY=your-gemini-key `
  --dart-define=FLICKO_GEMINI_IMAGE_API_KEY=your-gemini-key
```

## Backend API

| Route | Purpose |
| --- | --- |
| `POST /api/auth/register/start/` | Create inactive user and send registration OTP. |
| `POST /api/auth/register/verify/` | Verify registration OTP, activate user, return token and profile. |
| `POST /api/auth/login/` | Email and password login. |
| `POST /api/auth/password/forgot/start/` | Start password reset OTP flow. |
| `POST /api/auth/password/reset/` | Verify reset OTP and set a new password. |
| `GET /api/auth/me/` | Fetch authenticated profile. |
| `PATCH /api/auth/me/` | Update authenticated profile and app data. |
| `GET /api/auth/health/` | Backend health check with database and storage status. |
| `GET /api/auth/intake-reports/<id>/pdf/` | Authenticated PDF report download. |
| `GET /api/auth/intake-reports/<id>/html/` | Authenticated HTML report download. |

## Deployment

The backend is wired for:

- Supabase PostgreSQL through `DATABASE_URL`
- Cloudinary authenticated raw-file storage for generated PDF and HTML reports
- Gunicorn and WhiteNoise for production serving
- DigitalOcean Droplet deployment through `deploy/digitalocean/`
- DigitalOcean App Platform deployment through Python buildpack settings

Minimum production environment:

```env
DJANGO_SECRET_KEY=change-me
DJANGO_DEBUG=false
DJANGO_ALLOWED_HOSTS=api.example.com,flickoai-d4i2i.ondigitalocean.app
CORS_ALLOWED_ORIGINS=https://app.example.com
CSRF_TRUSTED_ORIGINS=https://api.example.com,https://flickoai-d4i2i.ondigitalocean.app
APP_DOMAIN=flickoai-d4i2i.ondigitalocean.app
APP_URL=https://flickoai-d4i2i.ondigitalocean.app

DATABASE_URL=postgresql://postgres.project:password@aws-0-region.pooler.supabase.com:6543/postgres
DATABASE_SSL_REQUIRE=true

USE_CLOUDINARY_MEDIA=true
CLOUDINARY_CLOUD_NAME=your-cloud-name
CLOUDINARY_API_KEY=your-api-key
CLOUDINARY_API_SECRET=your-api-secret
CLOUDINARY_DELIVERY_TYPE=authenticated
```

### Docker

```powershell
docker build -t flicko-backend .
docker run --env-file .env -p 8000:8000 flicko-backend
```

### DigitalOcean Droplet

Use the production runbook:

- `deploy/digitalocean/README.md`
- `deploy/digitalocean/bootstrap.sh`
- `deploy/digitalocean/update.sh`
- `deploy/digitalocean/backup.sh`
- `deploy/digitalocean/health-smoke.sh`

### DigitalOcean App Platform

Use:

```text
Build command: python manage.py collectstatic --noinput
Run command: gunicorn flixo_backend.wsgi:application -c gunicorn.conf.py
```

Set `APP_DOMAIN=${APP_DOMAIN}` and `APP_URL=${APP_URL}` as bindable values, then include the final App Platform domain in `DJANGO_ALLOWED_HOSTS` and `CSRF_TRUSTED_ORIGINS`.

## Security Notes

- Do not commit `.env`, `android/local.properties`, API keys, OAuth secrets, database URLs, or Cloudinary secrets.
- Public OAuth client IDs may be present in client configuration; OAuth client secrets must stay server-side.
- Report files are served through authenticated API routes instead of raw public storage URLs.
- Mobile Gemini features require `--dart-define` keys at build/run time.

## Project Status

Flicko AI currently includes the mobile app source, backend API, native Android live-call support, health protocol assets, report generation, authenticated file access, and production deployment scaffolding.
