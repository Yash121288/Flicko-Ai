from __future__ import annotations

import os
from pathlib import Path
from urllib.parse import urlparse

import cloudinary
import dj_database_url

BASE_DIR = Path(__file__).resolve().parent.parent


def load_local_env(path: Path) -> None:
    if not path.exists():
        return

    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue

        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip()
        if (
            (value.startswith('"') and value.endswith('"'))
            or (value.startswith("'") and value.endswith("'"))
        ):
            value = value[1:-1]

        os.environ.setdefault(key, value)


load_local_env(BASE_DIR / ".env")


def env_bool(name: str, default: bool = False) -> bool:
    value = os.getenv(name)
    if value is None:
        return default
    return value.strip().lower() in {"1", "true", "yes", "on"}


def env_list(name: str, default: str = "") -> list[str]:
    return [item.strip() for item in os.getenv(name, default).split(",") if item.strip()]


def env_int(name: str, default: int) -> int:
    try:
        return int(os.getenv(name, str(default)))
    except (TypeError, ValueError):
        return default


def _merge_unique(values: list[str]) -> list[str]:
    seen: set[str] = set()
    merged: list[str] = []
    for value in values:
        item = str(value or "").strip()
        if not item or item in seen:
            continue
        seen.add(item)
        merged.append(item)
    return merged


def env_host(name: str) -> str:
    return os.getenv(name, "").strip().split(":")[0].strip()


def env_url_origin(name: str) -> str:
    raw = os.getenv(name, "").strip()
    if not raw:
        return ""
    parsed = urlparse(raw)
    if not parsed.scheme or not parsed.netloc:
        return ""
    return f"{parsed.scheme}://{parsed.netloc}"


def env_url_host(name: str) -> str:
    raw = os.getenv(name, "").strip()
    if not raw:
        return ""
    parsed = urlparse(raw)
    return str(parsed.hostname or "").strip()


SECRET_KEY = os.getenv("DJANGO_SECRET_KEY", "dev-only-flicko-secret-key")
DEBUG = env_bool("DJANGO_DEBUG", True)
ALLOWED_HOSTS = _merge_unique(
    env_list("DJANGO_ALLOWED_HOSTS", "127.0.0.1,localhost,10.0.2.2")
    + [
        env_host("APP_DOMAIN"),
        env_host("DIGITALOCEAN_APP_DOMAIN"),
        env_url_host("APP_URL"),
        env_url_host("DIGITALOCEAN_APP_URL"),
    ]
)

INSTALLED_APPS = [
    "whitenoise.runserver_nostatic",
    "django.contrib.admin",
    "django.contrib.auth",
    "django.contrib.contenttypes",
    "django.contrib.sessions",
    "django.contrib.messages",
    "django.contrib.staticfiles",
    "corsheaders",
    "rest_framework",
    "rest_framework.authtoken",
    "accounts.apps.AccountsConfig",
]

MIDDLEWARE = [
    "corsheaders.middleware.CorsMiddleware",
    "django.middleware.security.SecurityMiddleware",
    "whitenoise.middleware.WhiteNoiseMiddleware",
    "django.contrib.sessions.middleware.SessionMiddleware",
    "django.middleware.common.CommonMiddleware",
    "django.middleware.csrf.CsrfViewMiddleware",
    "django.contrib.auth.middleware.AuthenticationMiddleware",
    "django.contrib.messages.middleware.MessageMiddleware",
    "django.middleware.clickjacking.XFrameOptionsMiddleware",
]

ROOT_URLCONF = "flixo_backend.urls"

TEMPLATES = [
    {
        "BACKEND": "django.template.backends.django.DjangoTemplates",
        "DIRS": [],
        "APP_DIRS": True,
        "OPTIONS": {
            "context_processors": [
                "django.template.context_processors.request",
                "django.contrib.auth.context_processors.auth",
                "django.contrib.messages.context_processors.messages",
            ],
        },
    },
]

WSGI_APPLICATION = "flixo_backend.wsgi.application"

DATABASE_URL = os.getenv("DATABASE_URL", "").strip()
if DATABASE_URL:
    DATABASES = {
        "default": dj_database_url.parse(
            DATABASE_URL,
            conn_max_age=env_int("DATABASE_CONN_MAX_AGE", 600),
            ssl_require=env_bool("DATABASE_SSL_REQUIRE", True),
        )
    }
else:
    DATABASES = {
        "default": {
            "ENGINE": "django.db.backends.sqlite3",
            "NAME": BASE_DIR / "db.sqlite3",
            "OPTIONS": {
                "timeout": 30,
            },
        }
    }

AUTH_PASSWORD_VALIDATORS = [
    {"NAME": "django.contrib.auth.password_validation.UserAttributeSimilarityValidator"},
    {"NAME": "django.contrib.auth.password_validation.MinimumLengthValidator"},
    {"NAME": "django.contrib.auth.password_validation.CommonPasswordValidator"},
    {"NAME": "django.contrib.auth.password_validation.NumericPasswordValidator"},
]

LANGUAGE_CODE = "en-us"
TIME_ZONE = "UTC"
USE_I18N = True
USE_TZ = True

STATIC_URL = "static/"
STATIC_ROOT = BASE_DIR / "staticfiles"
MEDIA_URL = "/media/"
MEDIA_ROOT = BASE_DIR / "media"
DEFAULT_AUTO_FIELD = "django.db.models.BigAutoField"

USE_CLOUDINARY_MEDIA = env_bool("USE_CLOUDINARY_MEDIA", False)
CLOUDINARY_CLOUD_NAME = os.getenv("CLOUDINARY_CLOUD_NAME", "").strip()
CLOUDINARY_API_KEY = os.getenv("CLOUDINARY_API_KEY", "").strip()
CLOUDINARY_API_SECRET = os.getenv("CLOUDINARY_API_SECRET", "").strip()
CLOUDINARY_MEDIA_PREFIX = os.getenv("CLOUDINARY_MEDIA_PREFIX", "flicko")
CLOUDINARY_DELIVERY_TYPE = os.getenv("CLOUDINARY_DELIVERY_TYPE", "authenticated").strip() or "authenticated"
CLOUDINARY_INVALIDATE = env_bool("CLOUDINARY_INVALIDATE", True)

if USE_CLOUDINARY_MEDIA:
    missing_cloudinary = [
        name
        for name, value in {
            "CLOUDINARY_CLOUD_NAME": CLOUDINARY_CLOUD_NAME,
            "CLOUDINARY_API_KEY": CLOUDINARY_API_KEY,
            "CLOUDINARY_API_SECRET": CLOUDINARY_API_SECRET,
        }.items()
        if not value
    ]
    if missing_cloudinary:
        raise RuntimeError(
            "USE_CLOUDINARY_MEDIA=true but Cloudinary credentials are missing: "
            + ", ".join(missing_cloudinary)
        )
    cloudinary.config(
        cloud_name=CLOUDINARY_CLOUD_NAME,
        api_key=CLOUDINARY_API_KEY,
        api_secret=CLOUDINARY_API_SECRET,
        secure=True,
    )

STORAGES = {
    "default": {
        "BACKEND": (
            "accounts.storage_backends.CloudinaryRawMediaStorage"
            if USE_CLOUDINARY_MEDIA
            else "django.core.files.storage.FileSystemStorage"
        ),
    },
    "staticfiles": {
        "BACKEND": "whitenoise.storage.CompressedManifestStaticFilesStorage",
    },
}

if not USE_CLOUDINARY_MEDIA:
    STORAGES["default"]["OPTIONS"] = {
        "location": MEDIA_ROOT,
        "base_url": MEDIA_URL,
    }

REST_FRAMEWORK = {
    "DEFAULT_AUTHENTICATION_CLASSES": [
        "rest_framework.authentication.TokenAuthentication",
    ],
    "DEFAULT_PERMISSION_CLASSES": [
        "rest_framework.permissions.AllowAny",
    ],
    "DEFAULT_THROTTLE_CLASSES": [
        "rest_framework.throttling.AnonRateThrottle",
        "rest_framework.throttling.UserRateThrottle",
    ],
    "DEFAULT_THROTTLE_RATES": {
        "anon": "100/hour",
        "user": "1000/hour",
        "otp": "8/hour",
        "login": "20/hour",
    },
}

CORS_ALLOW_CREDENTIALS = True
CORS_ALLOWED_ORIGINS = _merge_unique(
    env_list("CORS_ALLOWED_ORIGINS")
    + [
        env_url_origin("APP_URL"),
        env_url_origin("DIGITALOCEAN_APP_URL"),
    ]
)
CORS_ALLOW_ALL_ORIGINS = DEBUG and not CORS_ALLOWED_ORIGINS
CSRF_TRUSTED_ORIGINS = _merge_unique(
    env_list("CSRF_TRUSTED_ORIGINS")
    + [
        env_url_origin("APP_URL"),
        env_url_origin("DIGITALOCEAN_APP_URL"),
    ]
)

USE_X_FORWARDED_HOST = True
SECURE_PROXY_SSL_HEADER = ("HTTP_X_FORWARDED_PROTO", "https")
SECURE_SSL_REDIRECT = env_bool("DJANGO_SECURE_SSL_REDIRECT", not DEBUG)
SESSION_COOKIE_SECURE = env_bool("SESSION_COOKIE_SECURE", not DEBUG)
CSRF_COOKIE_SECURE = env_bool("CSRF_COOKIE_SECURE", not DEBUG)
SECURE_HSTS_SECONDS = env_int("SECURE_HSTS_SECONDS", 31536000 if not DEBUG else 0)
SECURE_HSTS_INCLUDE_SUBDOMAINS = env_bool(
    "SECURE_HSTS_INCLUDE_SUBDOMAINS",
    not DEBUG,
)
SECURE_HSTS_PRELOAD = env_bool("SECURE_HSTS_PRELOAD", False)

EMAIL_HOST = os.getenv("EMAIL_HOST", "")
EMAIL_PORT = env_int("EMAIL_PORT", 587)
EMAIL_HOST_USER = os.getenv("EMAIL_HOST_USER", "")
EMAIL_HOST_PASSWORD = os.getenv("EMAIL_HOST_PASSWORD", "")
EMAIL_USE_TLS = env_bool("EMAIL_USE_TLS", True)
EMAIL_TIMEOUT = env_int("EMAIL_TIMEOUT", 20)
DEFAULT_FROM_EMAIL = os.getenv("DEFAULT_FROM_EMAIL", "Flicko AI <no-reply@flicko.local>")
EMAIL_BACKEND = (
    "django.core.mail.backends.smtp.EmailBackend"
    if EMAIL_HOST and EMAIL_HOST_USER and EMAIL_HOST_PASSWORD
    else "django.core.mail.backends.console.EmailBackend"
)

OTP_TTL_MINUTES = env_int("OTP_TTL_MINUTES", 10)
OTP_MAX_ATTEMPTS = env_int("OTP_MAX_ATTEMPTS", 5)

GOOGLE_OAUTH_CLIENT_IDS = env_list("GOOGLE_OAUTH_CLIENT_IDS")
GOOGLE_OAUTH_ALLOW_UNCONFIGURED_DEBUG = env_bool(
    "GOOGLE_OAUTH_ALLOW_UNCONFIGURED_DEBUG",
    DEBUG,
)

# Optional server-side conversation analyzer. If these are not configured, the
# backend uses a deterministic local extractor so Vercel/free deployments keep
# working without blocking report generation.
GROQ_API_KEY = os.getenv("GROQ_API_KEY", "")
GROQ_MODEL = os.getenv("GROQ_MODEL", "llama-3.1-8b-instant")
GROQ_TIMEOUT_SECONDS = env_int("GROQ_TIMEOUT_SECONDS", 22)

LOG_LEVEL = os.getenv("DJANGO_LOG_LEVEL", "INFO").upper()
LOGGING = {
    "version": 1,
    "disable_existing_loggers": False,
    "formatters": {
        "standard": {
            "format": "%(asctime)s %(levelname)s %(name)s %(message)s",
        }
    },
    "handlers": {
        "console": {
            "class": "logging.StreamHandler",
            "formatter": "standard",
        }
    },
    "root": {
        "handlers": ["console"],
        "level": LOG_LEVEL,
    },
}
