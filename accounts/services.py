from __future__ import annotations

from datetime import timedelta
from secrets import randbelow

from django.conf import settings
from django.contrib.auth.hashers import check_password, make_password
from django.core.mail import send_mail
from django.utils import timezone

from .models import EmailOTP


def normalize_email(email: str) -> str:
    return email.strip().lower()


def split_name(name: str) -> tuple[str, str]:
    parts = [part for part in name.strip().split() if part]
    if not parts:
        return "", ""
    if len(parts) == 1:
        return parts[0], ""
    return parts[0], " ".join(parts[1:])


def create_otp(email: str, purpose: str) -> tuple[EmailOTP, str]:
    clean_email = normalize_email(email)
    code = f"{randbelow(1_000_000):06d}"
    expires_at = timezone.now() + timedelta(minutes=settings.OTP_TTL_MINUTES)
    EmailOTP.objects.filter(
        email=clean_email,
        purpose=purpose,
        consumed_at__isnull=True,
    ).update(consumed_at=timezone.now())
    otp = EmailOTP.objects.create(
        email=clean_email,
        purpose=purpose,
        code_hash=make_password(code),
        expires_at=expires_at,
    )
    return otp, code


def verify_otp(email: str, purpose: str, code: str) -> EmailOTP:
    clean_email = normalize_email(email)
    otp = (
        EmailOTP.objects.filter(
            email=clean_email,
            purpose=purpose,
            consumed_at__isnull=True,
        )
        .order_by("-created_at")
        .first()
    )
    if otp is None:
        raise ValueError("OTP not found")
    if otp.is_expired:
        raise ValueError("OTP expired")
    if otp.attempts_exhausted:
        raise ValueError("Too many OTP attempts")

    otp.attempts += 1
    otp.save(update_fields=["attempts"])
    if not check_password(code.strip(), otp.code_hash):
        raise ValueError("Invalid OTP")

    otp.mark_consumed()
    return otp


def send_otp_email(email: str, purpose: str, code: str) -> None:
    subject = "Your Flicko AI verification code"
    label = "registration" if purpose == EmailOTP.Purpose.REGISTER else "password reset"
    message = (
        f"Your Flicko AI {label} code is {code}.\n\n"
        f"This code expires in {settings.OTP_TTL_MINUTES} minutes. "
        "If you did not request this, ignore this email."
    )
    send_mail(subject, message, settings.DEFAULT_FROM_EMAIL, [email], fail_silently=False)
