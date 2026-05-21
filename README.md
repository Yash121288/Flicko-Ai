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
