# Flicko Django Backend

Local backend for Flicko authentication.

## Endpoints

- `POST /api/auth/register/start/` - create inactive user and email OTP.
- `POST /api/auth/register/verify/` - verify registration OTP, activate user, return token and profile.
- `POST /api/auth/login/` - email/password login, return token and profile.
- `POST /api/auth/password/forgot/start/` - email reset OTP if account exists.
- `POST /api/auth/password/reset/` - verify reset OTP and set a new password.
- `GET/PATCH /api/auth/me/` - authenticated profile fetch/update with `Authorization: Token <token>`.

## Run

```powershell
cd apps\backend
python manage.py migrate
python manage.py runserver 0.0.0.0:8000
```

For real email delivery, copy `.env.example` values into your environment and set SMTP credentials.
Without SMTP credentials, Django prints OTP emails in the console for development.

For Flutter:

```powershell
cd apps\mobile
flutter run --dart-define=FLICKO_API_BASE_URL=http://YOUR_PC_IP:8000/api
```

Use `http://10.0.2.2:8000/api` for Android emulator.

## Production

This backend is now wired for:

- Supabase PostgreSQL via `DATABASE_URL`
- Cloudinary raw-file storage for generated PDFs / HTML reports
- Gunicorn + WhiteNoise for production serving

### Required environment

Set these in production:

```env
DJANGO_SECRET_KEY=change-me
DJANGO_DEBUG=false
DJANGO_ALLOWED_HOSTS=api.example.com
CORS_ALLOWED_ORIGINS=https://app.example.com
CSRF_TRUSTED_ORIGINS=https://api.example.com

DATABASE_URL=postgresql://postgres.project:password@aws-0-region.pooler.supabase.com:6543/postgres
DATABASE_SSL_REQUIRE=true

USE_CLOUDINARY_MEDIA=true
CLOUDINARY_CLOUD_NAME=your-cloud-name
CLOUDINARY_API_KEY=your-api-key
CLOUDINARY_API_SECRET=your-api-secret
CLOUDINARY_DELIVERY_TYPE=authenticated
```

### Health check

The backend exposes:

```text
GET /api/auth/health/
```

Expected response includes database state and active storage mode.

### Docker run

```powershell
cd apps\backend
docker build -t flicko-backend .
docker run --env-file .env -p 8000:8000 flicko-backend
```

### Non-Docker run

```powershell
cd apps\backend
python -m venv .venv
.venv\Scripts\activate
pip install -r requirements.txt
python manage.py migrate
python manage.py collectstatic --noinput
gunicorn flixo_backend.wsgi:application -c gunicorn.conf.py
```
