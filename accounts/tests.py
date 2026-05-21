from __future__ import annotations

from html import escape as html_escape
from io import StringIO
import json
from pathlib import Path
from unittest.mock import patch

from django.conf import settings
from django.core.management import call_command
from django.core import mail
from django.contrib.auth.models import User
from django.test import TestCase, override_settings
from django.urls import reverse
from rest_framework.authtoken.models import Token
from rest_framework.test import APIClient

from .models import (
    EmailOTP,
    FoodRule,
    HealthIntakeReport,
    HealthMemoryEntry,
    HealthProtocol,
    SafetyRule,
    UserCareTaskRecord,
    UserHealthLogRecord,
    UserMealAnalysisRecord,
    UserProfile,
    UserReminderRecord,
)
from .html_reports import (
    _EXPLICIT_CONDITION_KEYS,
    _condition_evidence,
    _pair_lookup,
    _problem_key,
    _transcript_notes,
    build_health_report_html,
    parse_markdown_sections,
)
from .conversation_analysis import analyze_health_conversation
from .data_sync import summarize_records_for_dashboard
from .intake_requirements import assess_intake, intake_schema_payload
from .pdf_reports import _build_health_report_pdf_fallback, _structured_story, build_health_report_pdf
from .report_extractors import ConditionEvidence, _condition_schema, _symptom_rows_for_problem
from .report_templates import (
    SUPPORTED_REPORT_PROBLEMS,
    page_specs_for_problem,
    report_markdown_sections_for_problem,
    template_for_problem,
    template_slug,
)
from .services import verify_otp


def _flowable_plain_text(node) -> list[str]:
    texts: list[str] = []
    if node is None:
        return texts
    if isinstance(node, (list, tuple)):
        for item in node:
            texts.extend(_flowable_plain_text(item))
        return texts
    if isinstance(node, str):
        clean = node.strip()
        return [clean] if clean else []
    get_plain = getattr(node, "getPlainText", None)
    if callable(get_plain):
        clean = str(get_plain()).strip()
        if clean:
            texts.append(clean)
    content = getattr(node, "_content", None)
    if isinstance(content, list):
        for item in content:
            texts.extend(_flowable_plain_text(item))
    cell_values = getattr(node, "_cellvalues", None)
    if isinstance(cell_values, list):
        for row in cell_values:
            texts.extend(_flowable_plain_text(row))
    return texts


def _condition_specific_markdown(problem_name: str) -> str:
    blocks: list[str] = []
    for title in report_markdown_sections_for_problem(problem_name):
        blocks.append(
            f"## {title}\n"
            f"{problem_name} structured content for {title.lower()}.\n"
            f"- {problem_name} item captured for {title.lower()}\n"
        )
    return "\n".join(blocks)


@override_settings(EMAIL_BACKEND="django.core.mail.backends.locmem.EmailBackend")
class AuthFlowTests(TestCase):
    def setUp(self) -> None:
        self.client = APIClient()

    def test_register_verify_login_and_me(self):
        response = self.client.post(
            reverse("register-start"),
            {
                "name": "Aarav Shah",
                "email": "AARAV@example.com",
                "mobile": "9876543210",
                "password": "secret123",
            },
            format="json",
        )
        self.assertEqual(response.status_code, 200)
        self.assertEqual(len(mail.outbox), 1)
        otp = EmailOTP.objects.get(email="aarav@example.com", purpose=EmailOTP.Purpose.REGISTER)
        code = mail.outbox[0].body.split("code is ", 1)[1].split(".", 1)[0]

        response = self.client.post(
            reverse("register-verify"),
            {"email": "aarav@example.com", "otp": code},
            format="json",
        )
        self.assertEqual(response.status_code, 200)
        self.assertIn("token", response.data)
        self.assertEqual(response.data["user"]["mobile"], "9876543210")
        otp.refresh_from_db()
        self.assertIsNotNone(otp.consumed_at)

        response = self.client.post(
            reverse("login"),
            {"email": "aarav@example.com", "password": "secret123"},
            format="json",
        )
        self.assertEqual(response.status_code, 200)
        self.client.credentials(HTTP_AUTHORIZATION=f"Token {response.data['token']}")
        response = self.client.get(reverse("me"))
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data["user"]["email"], "aarav@example.com")
        self.assertIn("profile", response.data["user"])

    def test_google_login_creates_active_user_and_profile(self):
        with patch(
            "accounts.views._verify_google_id_token",
            return_value={
                "email": "googleuser@example.com",
                "email_verified": True,
                "name": "Google User",
                "aud": "test-client-id.apps.googleusercontent.com",
                "sub": "google-sub-123",
            },
        ):
            response = self.client.post(
                reverse("google-login"),
                {
                    "id_token": "valid-google-id-token",
                    "email": "googleuser@example.com",
                    "name": "Google User",
                },
                format="json",
            )

        self.assertEqual(response.status_code, 200)
        self.assertIn("token", response.data)
        self.assertEqual(response.data["user"]["email"], "googleuser@example.com")
        self.assertEqual(response.data["user"]["name"], "Google User")
        user = User.objects.get(username="googleuser@example.com")
        self.assertTrue(user.is_active)
        self.assertFalse(user.has_usable_password())
        self.assertTrue(hasattr(user, "profile"))

    def test_google_login_rejects_unverified_google_email(self):
        with patch(
            "accounts.views._verify_google_id_token",
            return_value={
                "email": "googleuser@example.com",
                "email_verified": False,
                "name": "Google User",
                "aud": "test-client-id.apps.googleusercontent.com",
            },
        ):
            response = self.client.post(
                reverse("google-login"),
                {"id_token": "valid-google-id-token"},
                format="json",
            )

        self.assertEqual(response.status_code, 403)

    def test_profile_sync_saves_medical_fields_and_memory(self):
        user = User.objects.create_user(
            username="profile@example.com",
            email="profile@example.com",
            password="secret123",
        )
        token = Token.objects.create(user=user)
        self.client.credentials(HTTP_AUTHORIZATION=f"Token {token.key}")

        response = self.client.patch(
            reverse("me"),
            {
                "name": "Kartik Patel",
                "mobile": "9998887777",
                "age": 29,
                "gender": "Male",
                "height_cm": "172",
                "weight_kg": "86",
                "goal_weight_kg": "75",
                "language": "Hindi",
                "food_preference": "Vegetarian",
                "medications": "No daily medicine",
                "allergies": "Peanut allergy",
                "diagnosis": "Weight gain",
                "family_history": "Diabetes in father",
                "emergency_contact_name": "Maya",
                "emergency_contact_phone": "9000000000",
                "selected_problems": ["Weight management", "Sleep health"],
                "safety_consent_accepted": True,
                "intake_summary": "Intake status: complete. User wants weight loss.",
                "intake_completed": True,
                "dashboard_values": {"score": 78, "Weight": "86 kg"},
                "dashboard_notes": ["Improve protein consistency"],
                "reminders": ["07:00 AM weigh-in"],
                "reports": ["Weight Management Report\nPDF: https://example.com/report.pdf"],
                "saved_reminders": [{"title": "Drink water", "body": "2L water", "hour": 7}],
                "care_tasks": [{"title": "Walk", "status": "active"}],
                "meal_analyses": [{"mealName": "Lunch", "score": 82}],
                "health_logs": [{"type": "weight", "valueText": "86 kg"}],
                "safety_events": [{"severity": "self_care", "title": "No red flag"}],
                "chat_history": [{"role": "user", "text": "I want weight help."}],
            },
            format="json",
        )

        self.assertEqual(response.status_code, 200)
        profile = response.data["user"]["profile"]
        self.assertEqual(profile["weight_kg"], "86")
        self.assertEqual(profile["selected_problems"][0], "Weight management")
        self.assertTrue(profile["safety_consent_accepted"])
        self.assertTrue(profile["intake_completed"])
        self.assertEqual(profile["reports"][0], "Weight Management Report\nPDF: https://example.com/report.pdf")
        self.assertEqual(profile["saved_reminders"][0]["title"], "Drink water")
        self.assertEqual(profile["care_tasks"][0]["title"], "Walk")
        self.assertEqual(profile["meal_analyses"][0]["mealName"], "Lunch")
        self.assertEqual(profile["health_logs"][0]["valueText"], "86 kg")
        self.assertEqual(profile["safety_events"][0]["title"], "No red flag")
        self.assertEqual(profile["chat_history"][0]["text"], "I want weight help.")
        self.assertEqual(user.health_log_records.count(), 1)
        self.assertEqual(user.meal_analysis_records.count(), 1)
        self.assertEqual(user.reminder_records.count(), 1)
        self.assertEqual(user.care_task_records.count(), 1)
        self.assertEqual(user.safety_event_records.count(), 1)
        self.assertEqual(user.chat_message_records.count(), 1)
        self.assertEqual(user.meal_analysis_records.first().score, 82)
        self.assertEqual(
            HealthMemoryEntry.objects.filter(
                user=user,
                category=HealthMemoryEntry.Category.INTAKE_SUMMARY,
            ).count(),
            1,
        )

    def test_app_data_endpoint_syncs_normalized_records(self):
        user = User.objects.create_user(
            username="appdata@example.com",
            email="appdata@example.com",
            password="secret123",
        )
        token = Token.objects.create(user=user)
        self.client.credentials(HTTP_AUTHORIZATION=f"Token {token.key}")

        response = self.client.patch(
            reverse("me"),
            {
                "name": "App Data User",
                "selected_problems": ["Diabetes Type 2"],
                "safety_consent_accepted": True,
            },
            format="json",
        )
        self.assertEqual(response.status_code, 200)

        response = self.client.post(
            reverse("health-app-data"),
            {
                "health_logs": [
                    {
                        "id": "glucose-1",
                        "type": "glucose",
                        "title": "Fasting sugar",
                        "value": "118",
                        "unit": "mg/dL",
                        "problemName": "Diabetes Type 2",
                        "createdAt": "2026-05-20T07:00:00+05:30",
                    }
                ],
                "meal_analyses": [
                    {
                        "id": "meal-1",
                        "problemName": "Diabetes Type 2",
                        "mealName": "Lunch plate",
                        "score": 74,
                        "decision": "Eat with portion control",
                        "calorieRange": "550-650 kcal",
                        "riskFlags": ["High rice portion"],
                        "createdAt": "2026-05-20T13:30:00+05:30",
                    }
                ],
                "saved_reminders": [
                    {
                        "id": "reminder-1",
                        "title": "Meal photo",
                        "body": "Upload lunch photo",
                        "hour": 13,
                        "minute": 0,
                        "enabled": True,
                    }
                ],
                "care_tasks": [
                    {
                        "id": "task-1",
                        "type": "measurement",
                        "title": "Log fasting sugar",
                        "detail": "Before breakfast",
                        "timeLabel": "7:00 AM",
                        "enabled": True,
                    }
                ],
                "safety_events": [
                    {
                        "id": "safety-1",
                        "severity": "clinician",
                        "title": "High sugar pattern",
                        "action": "Discuss recurring high readings with clinician.",
                    }
                ],
                "chat_history": [
                    {"role": "user", "text": "My fasting sugar is 118."},
                    {"role": "assistant", "text": "Track post-meal values today."},
                ],
            },
            format="json",
        )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data["synced"]["health_logs"], 1)
        self.assertEqual(response.data["summary"]["normalized_meal_analysis_count"], 1)
        self.assertEqual(user.health_log_records.get().value, "118")
        self.assertEqual(user.meal_analysis_records.get().score, 74)
        self.assertEqual(user.chat_message_records.count(), 2)

        repeat_response = self.client.post(
            reverse("health-app-data"),
            {
                "chat_history": [
                    {
                        "role": "user",
                        "text": "My fasting sugar is 118.",
                        "source": "chat",
                    },
                    {
                        "role": "assistant",
                        "text": "Track post-meal values today.",
                        "source": "chat",
                    },
                ],
            },
            format="json",
        )
        self.assertEqual(repeat_response.status_code, 200)
        self.assertEqual(user.chat_message_records.count(), 2)

        response = self.client.get(reverse("health-app-data"), {"limit": 5})
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data["meal_analyses"][0]["meal_name"], "Lunch plate")
        self.assertEqual(response.data["summary"]["latest_log_value"], "118 - mg/dL")

    def test_app_record_crud_endpoint_upserts_and_deletes_records(self):
        user = User.objects.create_user(
            username="crud@example.com",
            email="crud@example.com",
            password="secret123",
        )
        token = Token.objects.create(user=user)
        self.client.credentials(HTTP_AUTHORIZATION=f"Token {token.key}")
        self.client.patch(
            reverse("me"),
            {
                "name": "Crud User",
                "selected_problems": ["Blood pressure"],
                "safety_consent_accepted": True,
            },
            format="json",
        )

        response = self.client.post(
            reverse("health-app-records", args=["health-logs"]),
            {
                "id": "bp-log-1",
                "type": "bloodPressure",
                "title": "Evening BP",
                "value": "128/82",
                "unit": "",
                "note": "After walk",
                "problemName": "Blood pressure",
                "createdAt": "2026-05-20T20:00:00+05:30",
            },
            format="json",
        )
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data["record"]["external_id"], "bp-log-1")
        self.assertEqual(user.health_log_records.get().value, "128/82")
        user.profile.refresh_from_db()
        self.assertEqual(user.profile.health_logs[0]["id"], "bp-log-1")

        response = self.client.post(
            reverse("health-app-records", args=["care-tasks"]),
            {
                "id": "bp-task-1",
                "type": "measurement",
                "title": "Check BP",
                "detail": "Before dinner",
                "timeLabel": "7:30 PM",
                "enabled": True,
            },
            format="json",
        )
        self.assertEqual(response.status_code, 200)
        self.assertEqual(user.care_task_records.count(), 1)

        response = self.client.delete(
            reverse("health-app-record-detail", args=["care-tasks", "bp-task-1"]),
        )
        self.assertEqual(response.status_code, 200)
        self.assertTrue(response.data["deleted"])
        self.assertEqual(user.care_task_records.count(), 0)
        user.profile.refresh_from_db()
        self.assertEqual(user.profile.care_tasks, [])

    def test_diabetes_dashboard_summary_uses_real_glucose_and_meal_risk(self):
        user = User.objects.create_user(
            username="diabetes-summary@example.com",
            email="diabetes-summary@example.com",
            password="secret123",
        )
        profile, _ = UserProfile.objects.get_or_create(user=user)
        profile.selected_problems = ["Diabetes Type 2"]
        profile.intake_completed = True
        profile.intake_summary = "Diabetes intake complete."
        profile.save()
        UserHealthLogRecord.objects.create(
            user=user,
            external_id="glucose-180",
            problem_name="Diabetes Type 2",
            log_type="glucose",
            title="Post-meal sugar",
            value="198",
            unit="mg/dL",
        )
        UserMealAnalysisRecord.objects.create(
            user=user,
            external_id="meal-carb-risk",
            problem_name="Diabetes Type 2",
            meal_name="Rice-heavy lunch",
            score=52,
            decision="Reduce",
            calorie_range="650-750 kcal",
            risk_flags=["High refined carb portion"],
        )

        summary = summarize_records_for_dashboard(user)

        self.assertEqual(summary["diabetes_latest_glucose_value"], "198 - mg/dL")
        self.assertIn("high", summary["diabetes_latest_glucose_status"].lower())
        self.assertGreaterEqual(summary["diabetes_high_glucose_count"], 1)
        self.assertGreaterEqual(summary["diabetes_high_carb_meal_count"], 1)
        self.assertIn("Post-meal glucose", summary["diabetes_plan_focus"])

    def test_diabetes_dashboard_summary_exposes_safety_flags(self):
        user = User.objects.create_user(
            username="diabetes-safety@example.com",
            email="diabetes-safety@example.com",
            password="secret123",
        )
        profile, _ = UserProfile.objects.get_or_create(user=user)
        profile.selected_problems = ["Diabetes Type 2"]
        profile.intake_completed = True
        profile.intake_summary = "Diabetes intake complete."
        profile.save()
        UserHealthLogRecord.objects.create(
            user=user,
            external_id="glucose-268",
            problem_name="Diabetes Type 2",
            log_type="glucose",
            title="Post-meal sugar",
            value="268",
            unit="mg/dL",
        )
        UserCareTaskRecord.objects.create(
            user=user,
            external_id="metformin-morning",
            problem_name="Diabetes Type 2",
            task_type="medicine",
            title="Metformin",
            detail="Morning dose",
            time_label="8:00 AM",
            enabled=True,
        )

        summary = summarize_records_for_dashboard(user)

        self.assertEqual(summary["diabetes_safety_severity"], "urgent")
        self.assertIn("Very high sugar", summary["diabetes_safety_title"])
        self.assertGreaterEqual(summary["diabetes_pending_medicine_count"], 1)
        self.assertIn("safety", summary["diabetes_plan_focus"].lower())

    def test_app_data_cleanup_removes_stale_ai_artifacts(self):
        user = User.objects.create_user(
            username="cleanup@example.com",
            email="cleanup@example.com",
            password="secret123",
        )
        token = Token.objects.create(user=user)
        self.client.credentials(HTTP_AUTHORIZATION=f"Token {token.key}")
        profile, _ = UserProfile.objects.get_or_create(user=user)
        profile.reminders = [
            "Daily Flicko routine call in preferred free time",
            "8:00 PM drink water",
        ]
        profile.reports = [
            "Weight management AI setup report",
            "Weight Management Report\nPDF: https://example.com/weight.pdf",
        ]
        profile.saved_reminders = [
            {
                "id": "bad-reminder",
                "title": "Daily Flicko routine call in preferred free time",
                "body": "AI can call after more details.",
            },
            {
                "id": "good-reminder",
                "title": "Drink water",
                "body": "8 PM",
            },
        ]
        profile.care_tasks = [
            {
                "id": "bad-task",
                "title": "Upload meal photo",
                "detail": "AI will score eat / avoid from the old demo card.",
            },
            {
                "id": "good-task",
                "title": "Check fasting sugar",
                "detail": "Before breakfast",
            },
        ]
        profile.save()
        UserReminderRecord.objects.create(
            user=user,
            external_id="bad-reminder",
            title="Daily Flicko routine call in preferred free time",
            body="AI can call later.",
        )
        UserReminderRecord.objects.create(
            user=user,
            external_id="good-reminder",
            title="Drink water",
            body="8 PM",
        )
        UserCareTaskRecord.objects.create(
            user=user,
            external_id="bad-task",
            task_type="meal",
            title="Upload meal photo",
            detail="Let Flicko score eat / avoid from the old demo card.",
        )
        UserCareTaskRecord.objects.create(
            user=user,
            external_id="good-task",
            task_type="measurement",
            title="Check fasting sugar",
            detail="Before breakfast",
        )

        response = self.client.post(
            reverse("health-app-data-cleanup"),
            {},
            format="json",
        )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data["removed"]["profile_reminders"], 1)
        self.assertEqual(response.data["removed"]["profile_reports"], 1)
        self.assertEqual(response.data["removed"]["profile_saved_reminders"], 1)
        self.assertEqual(response.data["removed"]["profile_care_tasks"], 1)
        self.assertEqual(response.data["removed"]["reminder_records"], 1)
        self.assertEqual(response.data["removed"]["care_task_records"], 1)
        profile.refresh_from_db()
        self.assertEqual(profile.reminders, ["8:00 PM drink water"])
        self.assertEqual(len(profile.reports), 1)
        self.assertEqual(profile.saved_reminders[0]["id"], "good-reminder")
        self.assertEqual(profile.care_tasks[0]["id"], "good-task")
        self.assertEqual(user.reminder_records.count(), 1)
        self.assertEqual(user.care_task_records.count(), 1)

    def test_memory_entry_api(self):
        user = User.objects.create_user(
            username="memory@example.com",
            email="memory@example.com",
            password="secret123",
        )
        token = Token.objects.create(user=user)
        self.client.credentials(HTTP_AUTHORIZATION=f"Token {token.key}")

        response = self.client.post(
            reverse("health-memory"),
            {
                "problem_name": "Diabetes Type 2",
                "source": "chat",
                "category": "symptom",
                "title": "Post-meal sugar note",
                "content": "User reported sleepiness after high-carb lunch.",
                "data": {"meal": "rice-heavy lunch"},
            },
            format="json",
        )
        self.assertEqual(response.status_code, 201)
        self.assertEqual(response.data["category"], "symptom")

        response = self.client.get(reverse("health-memory"), {"category": "symptom"})
        self.assertEqual(response.status_code, 200)
        self.assertEqual(len(response.data["memory"]), 1)
        self.assertEqual(response.data["memory"][0]["title"], "Post-meal sugar note")

        response = self.client.post(
            reverse("health-memory"),
            {
                "problem_name": "Weight management",
                "source": "meal_photo",
                "category": "meal_analysis",
                "title": "Lunch photo score",
                "content": "Meal score 78/100 with high protein suggestion.",
                "data": {"score": 78},
            },
            format="json",
        )
        self.assertEqual(response.status_code, 201)
        self.assertEqual(response.data["source"], HealthMemoryEntry.Source.MEAL)
        self.assertEqual(response.data["category"], HealthMemoryEntry.Category.MEAL)

        response = self.client.post(
            reverse("health-memory"),
            {
                "problem_name": "Blood pressure",
                "source": "local_log",
                "category": "bloodPressure",
                "title": "Evening BP",
                "content": "128/82 after walk.",
            },
            format="json",
        )
        self.assertEqual(response.status_code, 201)
        self.assertEqual(response.data["source"], HealthMemoryEntry.Source.MANUAL)
        self.assertEqual(
            response.data["category"],
            HealthMemoryEntry.Category.PROFILE_FACT,
        )

    def test_password_reset_with_otp(self):
        self.client.post(
            reverse("register-start"),
            {
                "name": "Maya Patel",
                "email": "maya@example.com",
                "mobile": "9999999999",
                "password": "oldpass123",
            },
            format="json",
        )
        register_code = mail.outbox[-1].body.split("code is ", 1)[1].split(".", 1)[0]
        self.client.post(
            reverse("register-verify"),
            {"email": "maya@example.com", "otp": register_code},
            format="json",
        )

        response = self.client.post(
            reverse("forgot-start"),
            {"email": "maya@example.com"},
            format="json",
        )
        self.assertEqual(response.status_code, 200)
        reset_code = mail.outbox[-1].body.split("code is ", 1)[1].split(".", 1)[0]

        response = self.client.post(
            reverse("password-reset"),
            {
                "email": "maya@example.com",
                "otp": reset_code,
                "new_password": "newpass123",
            },
            format="json",
        )
        self.assertEqual(response.status_code, 200)
        response = self.client.post(
            reverse("login"),
            {"email": "maya@example.com", "password": "newpass123"},
            format="json",
        )
        self.assertEqual(response.status_code, 200)

    def test_invalid_otp_rejected(self):
        self.client.post(
            reverse("register-start"),
            {
                "name": "Bad Otp",
                "email": "bad@example.com",
                "mobile": "9000000000",
                "password": "secret123",
            },
            format="json",
        )
        with self.assertRaises(ValueError):
            verify_otp("bad@example.com", EmailOTP.Purpose.REGISTER, "000000")

    def test_authenticated_intake_report_generates_pdf(self):
        user = User.objects.create_user(
            username="report@example.com",
            email="report@example.com",
            password="secret123",
        )
        token = Token.objects.create(user=user)
        self.client.credentials(HTTP_AUTHORIZATION=f"Token {token.key}")

        response = self.client.post(
            reverse("intake-reports"),
            {
                "title": "Diabetes intake report",
                "problem_name": "Diabetes Type 2",
                "intake_summary": "User eats late dinner and needs meal reminders.",
                "dashboard_values": {"score": 82, "next_meal": "High-protein lunch"},
                "reminders": ["Lunch photo reminder at 1 PM", "Walk after dinner"],
                "transcript": [
                    {"role": "user", "text": "I want sugar control."},
                    {"role": "assistant", "text": "Let's start with meal timing."},
                ],
            },
            format="json",
        )

        self.assertEqual(response.status_code, 201)
        self.assertIn("pdf_url", response.data)
        self.assertIn("html_url", response.data)
        report = HealthIntakeReport.objects.get(user=user)
        self.assertTrue(report.pdf_file.name.endswith(".pdf"))
        self.assertTrue(report.html_file.name.endswith(".html"))
        self.assertEqual(report.reminders[0], "Lunch photo reminder at 1 PM")
        user.profile.refresh_from_db()
        self.assertTrue(user.profile.intake_completed)
        self.assertIn("score", user.profile.dashboard_values)
        self.assertGreaterEqual(user.reminder_records.count(), 1)
        self.assertGreaterEqual(user.care_task_records.count(), 1)
        self.assertTrue(
            HealthMemoryEntry.objects.filter(
                user=user,
                source=HealthMemoryEntry.Source.REPORT,
                category=HealthMemoryEntry.Category.REPORT,
            ).exists()
        )

    def test_full_call_transcript_analysis_updates_backend_records(self):
        user = User.objects.create_user(
            username="callreport@example.com",
            email="callreport@example.com",
            password="secret123",
        )
        token = Token.objects.create(user=user)
        self.client.credentials(HTTP_AUTHORIZATION=f"Token {token.key}")
        profile, _ = UserProfile.objects.get_or_create(user=user)
        profile.selected_problems = ["Diabetes Type 2"]
        profile.save()

        response = self.client.post(
            reverse("intake-reports"),
            {
                "title": "AI call setup report",
                "problem_name": "Diabetes Type 2",
                "source": "call",
                "intake_summary": "Short seed summary.",
                "dashboard_values": {"score": 70},
                "reminders": ["Lunch photo reminder at 1 PM"],
                "transcript": [
                    {
                        "role": "assistant",
                        "text": "Main Flicko health coach hoon. Aap apni routine batao.",
                        "createdAt": "2026-05-21T09:00:00+05:30",
                    },
                    {
                        "role": "user",
                        "text": (
                            "Mera sugar 118 hai. Lunch ke baad meal photo reminder "
                            "1 PM par chahiye aur raat ko 8 PM walk call karna."
                        ),
                        "createdAt": "2026-05-21T09:01:00+05:30",
                    },
                    {
                        "role": "user",
                        "text": "Sleep 6 hours hoti hai, medicine metformin raat ko leta hoon.",
                        "createdAt": "2026-05-21T09:02:00+05:30",
                    },
                ],
                "raw_transcript_text": (
                    "User: Mera sugar 118 hai. Lunch ke baad meal photo reminder "
                    "1 PM par chahiye aur raat ko 8 PM walk call karna."
                ),
                "source_payload": {"callId": "call-123"},
                "analyze_conversation": True,
            },
            format="json",
        )

        self.assertEqual(response.status_code, 201)
        self.assertTrue(response.data["intake_completed"])
        self.assertGreaterEqual(len(response.data["saved_reminders"]), 1)
        self.assertGreaterEqual(len(response.data["care_tasks"]), 1)
        self.assertGreaterEqual(len(response.data["health_logs"]), 1)
        self.assertEqual(response.data["analysis"]["analyzer"], "local_fallback")
        user.profile.refresh_from_db()
        self.assertTrue(user.profile.intake_completed)
        self.assertIn("full_transcript_saved", user.profile.dashboard_values)
        self.assertGreaterEqual(user.reminder_records.count(), 1)
        self.assertGreaterEqual(user.care_task_records.count(), 1)
        self.assertGreaterEqual(user.health_log_records.count(), 1)
        call_memory = HealthMemoryEntry.objects.filter(
            user=user,
            source=HealthMemoryEntry.Source.CALL,
            category=HealthMemoryEntry.Category.INTAKE_SUMMARY,
        ).first()
        self.assertIsNotNone(call_memory)
        self.assertIn("sugar 118", call_memory.content)

    @override_settings(GROQ_API_KEY="")
    def test_conversation_analysis_does_not_fabricate_reminders(self):
        user = User.objects.create_user(
            username="nofakereminder@example.com",
            email="nofakereminder@example.com",
            password="secret123",
        )

        analysis = analyze_health_conversation(
            user=user,
            problem_name="Weight management",
            intake_summary="User discussed food, water, and walking habits.",
            dashboard_values={},
            reminders=[],
            transcript=[
                {
                    "role": "user",
                    "text": "I drink water and walk sometimes, but I did not ask for reminders.",
                }
            ],
        )

        self.assertEqual(analysis.reminders, [])
        self.assertEqual(analysis.app_data["saved_reminders"], [])

        explicit = analyze_health_conversation(
            user=user,
            problem_name="Weight management",
            intake_summary="User asked for one water reminder.",
            dashboard_values={},
            reminders=[],
            transcript=[
                {
                    "role": "user",
                    "text": "Please set a reminder at 8 PM to drink water.",
                }
            ],
        )

        self.assertEqual(len(explicit.app_data["saved_reminders"]), 1)
        self.assertIn("8 PM", explicit.reminders[0])

    @override_settings(GROQ_API_KEY="")
    def test_conversation_analysis_uses_condition_specific_report_sections(self):
        user = User.objects.create_user(
            username="reportsections@example.com",
            email="reportsections@example.com",
            password="secret123",
        )

        for problem_name in SUPPORTED_REPORT_PROBLEMS:
            analysis = analyze_health_conversation(
                user=user,
                problem_name=problem_name,
                intake_summary="",
                dashboard_values={
                    "score": 70,
                    "daily_goal": "Follow the next 7-day plan",
                    "plan_focus": f"{problem_name} follow-up routine",
                },
                reminders=["7:30 AM check-in", "8:00 PM review"],
                transcript=[
                    {
                        "role": "user",
                        "text": (
                            f"I need help with {problem_name}. "
                            "I have symptoms, routine issues, and need a structured plan."
                        ),
                    },
                    {
                        "role": "user",
                        "text": (
                            "Please track medicines, meals, sleep, and any important warning signs."
                        ),
                    },
                ],
                raw_transcript_text=(
                    f"User discussed {problem_name}, symptoms, routine, medicines, meals, sleep, "
                    "and asked for a structured plan."
                ),
            )
            self.assertEqual(
                [line[3:] for line in analysis.report_markdown.splitlines() if line.startswith("## ")],
                list(report_markdown_sections_for_problem(problem_name)),
                msg=problem_name,
            )

    def test_every_problem_has_pdf_template_and_generates_pdf(self):
        user = User.objects.create_user(
            username="templates@example.com",
            email="templates@example.com",
            password="secret123",
        )

        self.assertGreaterEqual(len(SUPPORTED_REPORT_PROBLEMS), 23)
        with patch("accounts.pdf_reports._render_pdf_with_playwright", return_value=None):
            for problem_name in SUPPORTED_REPORT_PROBLEMS:
                template = template_for_problem(problem_name)
                slug = template_slug(template)
                html_template_path = (
                    settings.BASE_DIR
                    / "accounts"
                    / "templates"
                    / "accounts"
                    / "reports"
                    / f"{slug}_report.html"
                )
                css_path = settings.BASE_DIR / "accounts" / "report_styles" / f"{slug}_report.css"
                self.assertTrue(html_template_path.exists(), msg=problem_name)
                self.assertTrue(css_path.exists(), msg=problem_name)
                self.assertEqual(template.problem_name, problem_name)
                report = HealthIntakeReport(
                    user=user,
                    title=f"{problem_name} report",
                    problem_name=problem_name,
                    intake_summary=(
                        "Intake status: complete. User shared symptoms, routine, "
                        "risk flags, and preferred reminders."
                    ),
                    dashboard_values={
                        "score": 82,
                        "primary_problem": problem_name,
                        "daily_goal": "Follow the 7-day plan",
                    },
                    reminders=["Morning check-in", "Evening symptom log"],
                    transcript=[
                        {"role": "user", "text": "I want a report."},
                        {"role": "assistant", "text": "Intake status: complete."},
                    ],
                )
                pdf_bytes = build_health_report_pdf(report)
                self.assertTrue(pdf_bytes.startswith(b"%PDF"), msg=problem_name)
                self.assertGreater(len(pdf_bytes), 2000, msg=problem_name)
                html = build_health_report_html(report)
                self.assertIn("report-shell", html, msg=problem_name)
                self.assertIn(html_escape(template.title), html, msg=problem_name)
                self.assertIn(f"report-{slug}", html, msg=problem_name)
                self.assertIn("report-table", html, msg=problem_name)

    def test_pdf_fallback_story_uses_dynamic_condition_specific_sections(self):
        user = User.objects.create_user(
            username="fallbackstory@example.com",
            email="fallbackstory@example.com",
            password="secret123",
        )
        report = HealthIntakeReport(
            user=user,
            title="Sexual health report",
            problem_name="Sexual health",
            intake_summary=(
                "## Chief Concern\n"
                "Confidential irritation and discharge concern captured from the conversation.\n"
                "- Symptoms started 5 days ago\n"
                "\n"
                "## Structured Symptom Review\n"
                "Symptoms are organized for clinician review.\n"
                "- Burning after urination was mentioned\n"
                "\n"
                "## Safety Review\n"
                "- No emergency red flag detected from the saved transcript.\n"
                "\n"
                "## Testing and Follow-up Table\n"
                "- STI testing history not captured yet\n"
                "\n"
                "## Medicine Timing Table\n"
                "- Self-treatment was mentioned but dose not confirmed\n"
                "\n"
                "## Day-wise 7-Day Plan\n"
                "- Day 1: log symptoms and avoid unverified self-medication\n"
                "\n"
                "## Safety Boundary\n"
                "- This AI report supports doctor discussion only.\n"
            ),
            dashboard_values={
                "score": 72,
                "primary_problem": "Sexual health",
                "plan_focus": "Symptom logging and clinician review",
            },
            reminders=["8:00 PM private symptom check-in"],
            transcript=[{"role": "user", "text": "I have burning and discharge for 5 days."}],
        )
        template = template_for_problem(report.problem_name)
        values = report.dashboard_values
        sections = parse_markdown_sections(report.intake_summary)
        story = _structured_story(
            report=report,
            template=template,
            values=values,
            sections=sections,
            reminders=tuple(report.reminders),
            transcript_notes=_transcript_notes(report.transcript),
            pair_lookup=_pair_lookup(values, sections),
            score=72,
        )
        plain_text = "\n".join(_flowable_plain_text(story))
        self.assertIn("Confidential Symptom Review", plain_text)
        self.assertIn("Structured Symptom Review", plain_text)
        self.assertIn("Testing and Follow-up Table", plain_text)
        self.assertIn("Medicine Timing Table", plain_text)
        self.assertIn("Day-wise 7-Day Plan", plain_text)
        self.assertIn("Follow-up and Referral", plain_text)
        self.assertEqual(
            len(page_specs_for_problem("Sexual health")),
            3,
        )

    def test_pdf_fallback_direct_render_returns_real_pdf_bytes(self):
        user = User.objects.create_user(
            username="fallbackpdf@example.com",
            email="fallbackpdf@example.com",
            password="secret123",
        )
        report = HealthIntakeReport(
            user=user,
            title="Weight management report",
            problem_name="Weight management",
            intake_summary=(
                "## Clinical Snapshot Table\n"
                "- Current routine captured from intake.\n"
                "\n"
                "## Suggested Daily Meal Structure\n"
                "- Breakfast: protein-first meal with fiber.\n"
                "\n"
                "## Day-wise 7-Day Plan\n"
                "- Day 1: food log and hydration check.\n"
                "\n"
                "## Doctor Discussion\n"
                "- Discuss persistent cravings and sleep debt.\n"
            ),
            dashboard_values={
                "score": 81,
                "daily_goal": "Follow the 7-day meal and activity plan",
                "plan_focus": "Meal timing, step count, and sleep repair",
                "primary_problem": "Weight management",
            },
            reminders=["7:00 AM weigh-in", "8:30 PM meal review"],
            transcript=[
                {
                    "role": "user",
                    "text": "I need a structured weight-loss plan with meals, activity, and sleep targets.",
                }
            ],
        )
        pdf_bytes = _build_health_report_pdf_fallback(report)
        self.assertTrue(pdf_bytes.startswith(b"%PDF"))
        self.assertGreater(len(pdf_bytes), 2000)

    def test_representative_problems_render_unique_titles_in_html_and_fallback_story(self):
        user = User.objects.create_user(
            username="conditionmatrix@example.com",
            email="conditionmatrix@example.com",
            password="secret123",
        )
        cases = {
            "Diabetes Type 2": (
                "Clinical Snapshot Table",
                "Suggested Daily Meal Structure",
                "Medicine Timing Table",
                "Testing and Follow-up Table",
                "Doctor Discussion",
            ),
            "Pregnancy": (
                "Structured Symptom Review",
                "Suggested Daily Meal Structure",
                "Recovery Checklist",
                "Support and Recovery Context",
                "Follow-up and Referral",
            ),
            "Heart health": (
                "Structured Symptom Review",
                "Risk Factors",
                "Clinical Snapshot Table",
                "Suggested Daily Meal Structure",
                "Testing and Follow-up Table",
            ),
            "Stress and mood": (
                "Structured Symptom Review",
                "Support and Recovery Context",
                "Trigger and Response Map",
                "Clinical Snapshot Table",
                "Doctor Discussion",
            ),
        }

        for problem_name, expected_titles in cases.items():
            report = HealthIntakeReport(
                user=user,
                title=f"{problem_name} report",
                problem_name=problem_name,
                intake_summary=_condition_specific_markdown(problem_name),
                dashboard_values={
                    "score": 76,
                    "primary_problem": problem_name,
                    "daily_goal": "Follow the structured 7-day report plan",
                    "plan_focus": f"{problem_name} structured follow-up",
                },
                reminders=["7:00 AM review", "8:30 PM symptom log"],
                transcript=[
                    {
                        "role": "user",
                        "text": f"I need a structured professional report for {problem_name}.",
                    }
                ],
            )
            html = build_health_report_html(report)
            self.assertIn("report-shell", html, msg=problem_name)
            self.assertIn("report-table", html, msg=problem_name)

            sections = parse_markdown_sections(report.intake_summary)
            story = _structured_story(
                report=report,
                template=template_for_problem(problem_name),
                values=report.dashboard_values,
                sections=sections,
                reminders=tuple(report.reminders),
                transcript_notes=_transcript_notes(report.transcript),
                pair_lookup=_pair_lookup(report.dashboard_values, sections),
                score=76,
            )
            plain_text = "\n".join(_flowable_plain_text(story))

            for title in expected_titles:
                self.assertIn(title, html, msg=f"{problem_name}:html:{title}")
                self.assertIn(title, plain_text, msg=f"{problem_name}:pdf:{title}")

    def test_representative_problems_render_condition_specific_table_content(self):
        user = User.objects.create_user(
            username="conditioncontent@example.com",
            email="conditioncontent@example.com",
            password="secret123",
        )
        cases = {
            "Diabetes Type 2": (
                "Controlled carb plus protein: oats + eggs, dal chilla, tofu, or unsweetened yogurt.",
                "Record fasting and one post-meal glucose value if advised.",
            ),
            "Pregnancy": (
                "Frequent small meals can control nausea better than large ones.",
                "Track swelling, headache, pain, bleeding, or reduced movement if relevant.",
            ),
            "Heart health": (
                "Any chest symptom changes override the meal plan.",
                "Do not negotiate with chest pain red flags.",
            ),
            "Stress and mood": (
                "Use one coping skill on schedule, not only during crisis.",
                "Mood work fails if physiology is unstable.",
            ),
        }

        for problem_name, expected_snippets in cases.items():
            report = HealthIntakeReport(
                user=user,
                title=f"{problem_name} report",
                problem_name=problem_name,
                intake_summary=_condition_specific_markdown(problem_name),
                dashboard_values={
                    "score": 79,
                    "primary_problem": problem_name,
                    "daily_goal": "Follow the structured next-step plan",
                    "plan_focus": f"{problem_name} focused weekly review",
                },
                reminders=["7:00 AM review", "8:30 PM symptom log"],
                transcript=[
                    {
                        "role": "user",
                        "text": f"I need a real table-based report for {problem_name}.",
                    }
                ],
            )
            html = build_health_report_html(report)
            sections = parse_markdown_sections(report.intake_summary)
            story = _structured_story(
                report=report,
                template=template_for_problem(problem_name),
                values=report.dashboard_values,
                sections=sections,
                reminders=tuple(report.reminders),
                transcript_notes=_transcript_notes(report.transcript),
                pair_lookup=_pair_lookup(report.dashboard_values, sections),
                score=79,
            )
            plain_text = "\n".join(_flowable_plain_text(story))

            for snippet in expected_snippets:
                self.assertIn(snippet, html, msg=f"{problem_name}:html:{snippet}")
                self.assertIn(snippet, plain_text, msg=f"{problem_name}:pdf:{snippet}")

    def test_explicit_condition_extractors_place_captured_evidence_in_rows(self):
        user = User.objects.create_user(
            username="extractorevidence@example.com",
            email="extractorevidence@example.com",
            password="secret123",
        )
        cases = {
            "Diabetes Type 2": {
                "transcript": [
                    {
                        "role": "user",
                        "text": (
                            "My fasting sugar stays near 182, I feel shaky if lunch is delayed, "
                            "and a 15 minute walk after dinner lowers readings."
                        ),
                    }
                ],
                "dashboard": {
                    "score": 74,
                    "primary_problem": "Diabetes Type 2",
                    "medicine": "Metformin 500 mg",
                    "medicine_timing": "After breakfast and dinner",
                    "daily_goal": "Stabilize fasting and post-meal glucose pattern",
                },
                "expected": (
                    "fasting sugar stays near 182",
                    "shaky if lunch is delayed",
                    "15 minute walk after dinner lowers readings",
                    "Metformin 500 mg",
                    "After breakfast and dinner",
                ),
            },
            "Pregnancy": {
                "transcript": [
                    {
                        "role": "user",
                        "text": (
                            "I am 12 weeks pregnant with morning nausea, and I had light spotting yesterday."
                        ),
                    }
                ],
                "dashboard": {
                    "score": 71,
                    "primary_problem": "Pregnancy",
                    "trimester": "12 weeks pregnant",
                    "daily_goal": "Track nausea tolerance and bleeding red flags",
                },
                "expected": (
                    "12 weeks pregnant",
                    "morning nausea",
                    "light spotting yesterday",
                ),
            },
            "Heart health": {
                "transcript": [
                    {
                        "role": "user",
                        "text": (
                            "I get chest pressure on stairs, it is relieved by rest, and sometimes comes with sweating."
                        ),
                    }
                ],
                "dashboard": {
                    "score": 69,
                    "primary_problem": "Heart health",
                    "daily_goal": "Track exertional symptoms and escalation thresholds",
                },
                "expected": (
                    "chest pressure on stairs",
                    "relieved by rest",
                    "comes with sweating",
                ),
            },
            "Stress and mood": {
                "transcript": [
                    {
                        "role": "user",
                        "text": (
                            "My anxiety spikes after skipped meals, I am sleeping only 4 hours, "
                            "and I feel hopeless at night."
                        ),
                    }
                ],
                "dashboard": {
                    "score": 63,
                    "primary_problem": "Stress and mood",
                    "daily_goal": "Protect meals, sleep, and crisis support",
                },
                "expected": (
                    "anxiety spikes after skipped meals",
                    "sleeping only 4 hours",
                    "feel hopeless at night",
                ),
            },
            "Sexual health": {
                "transcript": [
                    {
                        "role": "user",
                        "text": (
                            "I have burning after urination and yellow discharge after unprotected sex. "
                            "I took azithromycin last week and got nausea."
                        ),
                    }
                ],
                "dashboard": {
                    "score": 68,
                    "primary_problem": "Sexual health",
                    "medicine_timing": "Once daily after food",
                    "daily_goal": "Track discharge, exposure context, and follow-up testing",
                },
                "expected": (
                    "burning after urination",
                    "yellow discharge after unprotected sex",
                    "azithromycin last week",
                    "Once daily after food",
                    "got nausea",
                ),
            },
        }

        for problem_name, payload in cases.items():
            report = HealthIntakeReport(
                user=user,
                title=f"{problem_name} extractor report",
                problem_name=problem_name,
                intake_summary=_condition_specific_markdown(problem_name),
                dashboard_values=payload["dashboard"],
                reminders=["7:00 AM review", "8:30 PM symptom log"],
                transcript=payload["transcript"],
            )
            html = build_health_report_html(report)
            sections = parse_markdown_sections(report.intake_summary)
            story = _structured_story(
                report=report,
                template=template_for_problem(problem_name),
                values=report.dashboard_values,
                sections=sections,
                reminders=tuple(report.reminders),
                transcript_notes=_transcript_notes(report.transcript),
                pair_lookup=_pair_lookup(report.dashboard_values, sections),
                score=int(report.dashboard_values["score"]),
            )
            plain_text = "\n".join(_flowable_plain_text(story)).lower()
            html_lower = html.lower()

            for snippet in payload["expected"]:
                expected = snippet.lower()
                self.assertIn(expected, html_lower, msg=f"{problem_name}:html:{snippet}")
                self.assertIn(expected, plain_text, msg=f"{problem_name}:pdf:{snippet}")

    def test_additional_condition_extractors_place_evidence_in_rows(self):
        user = User.objects.create_user(
            username="extractorevidence2@example.com",
            email="extractorevidence2@example.com",
            password="secret123",
        )
        cases = {
            "Blood pressure": {
                "transcript": [
                    {
                        "role": "user",
                        "text": (
                            "My blood pressure reading was 158 over 96, I get dizziness during work stress, "
                            "and I missed my amlodipine dose last night."
                        ),
                    }
                ],
                "dashboard": {
                    "score": 67,
                    "primary_problem": "Blood pressure",
                    "medicine_timing": "Night after dinner",
                    "daily_goal": "Track readings and medicine timing consistently",
                },
                "expected": (
                    "blood pressure reading was 158 over 96",
                    "dizziness during work stress",
                    "missed my amlodipine dose last night",
                    "Night after dinner",
                ),
            },
            "PCOS/PCOD": {
                "transcript": [
                    {
                        "role": "user",
                        "text": (
                            "My periods are irregular, I have acne and facial hair, and my sugar cravings get worse when I sleep badly."
                        ),
                    }
                ],
                "dashboard": {
                    "score": 66,
                    "primary_problem": "PCOS/PCOD",
                    "medicine": "Metformin 500 mg",
                    "daily_goal": "Track cycle, cravings, and sleep consistency",
                },
                "expected": (
                    "periods are irregular",
                    "acne and facial hair",
                    "sugar cravings get worse",
                ),
            },
            "Thyroid": {
                "transcript": [
                    {
                        "role": "user",
                        "text": (
                            "I feel tired all day, have constipation and hair fall, and I take levothyroxine on an empty stomach."
                        ),
                    }
                ],
                "dashboard": {
                    "score": 72,
                    "primary_problem": "Thyroid",
                    "daily_goal": "Keep thyroid medicine timing consistent",
                },
                "expected": (
                    "tired all day",
                    "constipation and hair fall",
                    "levothyroxine on an empty stomach",
                ),
            },
            "Postpartum": {
                "transcript": [
                    {
                        "role": "user",
                        "text": (
                            "I still have wound pain, breast pain during feeding, and I feel overwhelmed at night."
                        ),
                    }
                ],
                "dashboard": {
                    "score": 64,
                    "primary_problem": "Postpartum",
                    "daily_goal": "Track recovery pain, feeding, and mood",
                },
                "expected": (
                    "wound pain",
                    "breast pain during feeding",
                    "feel overwhelmed at night",
                ),
            },
            "Digestive health": {
                "transcript": [
                    {
                        "role": "user",
                        "text": (
                            "I get bloating and burning after spicy meals, with constipation and one episode of vomiting."
                        ),
                    }
                ],
                "dashboard": {
                    "score": 61,
                    "primary_problem": "Digestive health",
                    "medicine": "Pantoprazole",
                    "daily_goal": "Identify meal triggers and bowel pattern",
                },
                "expected": (
                    "bloating and burning after spicy meals",
                    "constipation",
                    "episode of vomiting",
                ),
            },
            "Skin and hair": {
                "transcript": [
                    {
                        "role": "user",
                        "text": (
                            "I have acne on my face, hair fall from the scalp, and my new shampoo makes the itching worse."
                        ),
                    }
                ],
                "dashboard": {
                    "score": 62,
                    "primary_problem": "Skin and hair",
                    "daily_goal": "Track trigger products and hair loss pattern",
                },
                "expected": (
                    "acne on my face",
                    "hair fall from the scalp",
                    "new shampoo makes the itching worse",
                ),
            },
            "Autoimmune support": {
                "transcript": [
                    {
                        "role": "user",
                        "text": (
                            "I have joint pain and swelling in my hands, severe fatigue, and stress seems to trigger flares."
                        ),
                    }
                ],
                "dashboard": {
                    "score": 58,
                    "primary_problem": "Autoimmune support",
                    "medicine": "Methotrexate weekly",
                    "daily_goal": "Track swelling, fatigue, and flare triggers",
                },
                "expected": (
                    "joint pain and swelling in my hands",
                    "severe fatigue",
                    "stress seems to trigger flares",
                    "Methotrexate weekly",
                ),
            },
        }

        for problem_name, payload in cases.items():
            report = HealthIntakeReport(
                user=user,
                title=f"{problem_name} extractor report",
                problem_name=problem_name,
                intake_summary=_condition_specific_markdown(problem_name),
                dashboard_values=payload["dashboard"],
                reminders=["7:00 AM review", "8:30 PM symptom log"],
                transcript=payload["transcript"],
            )
            html = build_health_report_html(report)
            sections = parse_markdown_sections(report.intake_summary)
            story = _structured_story(
                report=report,
                template=template_for_problem(problem_name),
                values=report.dashboard_values,
                sections=sections,
                reminders=tuple(report.reminders),
                transcript_notes=_transcript_notes(report.transcript),
                pair_lookup=_pair_lookup(report.dashboard_values, sections),
                score=int(report.dashboard_values["score"]),
            )
            plain_text = "\n".join(_flowable_plain_text(story)).lower()
            html_lower = html.lower()

            for snippet in payload["expected"]:
                expected = snippet.lower()
                self.assertIn(expected, html_lower, msg=f"{problem_name}:html:{snippet}")
                self.assertIn(expected, plain_text, msg=f"{problem_name}:pdf:{snippet}")

    def test_remaining_condition_extractors_map_evidence_for_all_problem_families(self):
        cases = {
            "Weight management": {
                "transcript": "I have weight gain, late snacking, only 2500 steps, and poor sleep after midnight.",
                "dashboard": {
                    "medicine": "Semaglutide weekly",
                    "medicine_timing": "Weekly on Sunday morning",
                },
                "expected": {
                    "weight_trend": "weight gain",
                    "hunger_cravings_context": "late snacking",
                    "activity_steps_pattern": "2500 steps",
                    "sleep_routine_impact": "poor sleep",
                    "__medicine": "Semaglutide weekly",
                    "__timing": "Weekly on Sunday morning",
                },
            },
            "Sleep health": {
                "transcript": "I sleep at 1 am, wake 3 times, snore loudly, drink coffee at 7 pm, and feel sleepy all day.",
                "dashboard": {
                    "medicine": "Melatonin",
                    "medicine_timing": "30 minutes before bed",
                },
                "expected": {
                    "sleep_schedule": "sleep at 1 am",
                    "night_disruption": "wake 3 times",
                    "behavior_trigger": "coffee at 7 pm",
                    "daytime_impact": "sleepy all day",
                    "__medicine": "Melatonin",
                    "__timing": "30 minutes before bed",
                },
            },
            "Fitness": {
                "transcript": "Knee pain after squats, cardio makes me breathless, soreness lasts 2 days, and I skipped warmup.",
                "dashboard": {
                    "medicine": "Pain spray",
                    "medicine_timing": "After workout",
                },
                "expected": {
                    "current_training_load": "cardio makes me breathless",
                    "pain_injury_signal": "Knee pain after squats",
                    "recovery_burden": "soreness lasts 2 days",
                    "progression_blocker": "skipped warmup",
                    "__medicine": "Pain spray",
                    "__timing": "After workout",
                },
            },
            "General wellness": {
                "transcript": "I feel fatigue, eat irregular meals, have poor sleep, and stress at work is high.",
                "dashboard": {
                    "medicine": "Vitamin D",
                    "medicine_timing": "Morning after food",
                },
                "expected": {
                    "primary_concern": "fatigue",
                    "routine_pattern": "irregular meals",
                    "sleep_stress_context": "poor sleep",
                    "__medicine": "Vitamin D",
                    "__timing": "Morning after food",
                },
            },
            "Women's wellness": {
                "transcript": "I have heavy flow with period pain, headache before periods, and I am soaking pads quickly.",
                "dashboard": {
                    "medicine": "Iron tablet",
                    "medicine_timing": "During period after food",
                },
                "expected": {
                    "cycle_symptom": "heavy flow with period pain",
                    "associated_symptom": "headache before periods",
                    "escalation_cue": "soaking pads quickly",
                    "__medicine": "Iron tablet",
                    "__timing": "During period after food",
                },
            },
            "Senior care": {
                "transcript": "He nearly fell in the bathroom, gets dizzy after morning pills, has poor appetite, and the caregiver missed the evening dose.",
                "dashboard": {
                    "medicine": "BP medicine",
                    "medicine_timing": "Morning pills and evening dose",
                },
                "expected": {
                    "mobility_falls_risk": "nearly fell in the bathroom",
                    "confusion_dizziness": "dizzy after morning pills",
                    "meals_hydration": "poor appetite",
                    "medicine_caregiver_context": "caregiver missed the evening dose",
                    "__medicine": "BP medicine",
                    "__timing": "Morning pills and evening dose",
                },
            },
            "Cholesterol": {
                "transcript": "My LDL is 162, I eat fried snacks daily, my father had heart disease, and I miss atorvastatin at night.",
                "dashboard": {
                    "medicine": "Atorvastatin",
                    "medicine_timing": "Night after dinner",
                },
                "expected": {
                    "lipid_lab_context": "LDL is 162",
                    "food_risk_pattern": "fried snacks daily",
                    "family_cardiovascular_risk": "father had heart disease",
                    "__medicine": "atorvastatin",
                    "__timing": "Night after dinner",
                },
            },
            "Habit reset": {
                "transcript": "Phone scrolling starts when stressed at 11 pm, the loop becomes all-night doomscrolling, and shoes are not ready for a replacement walk.",
                "dashboard": {
                    "medicine": "Nicotine gum",
                    "medicine_timing": "At night if craving spikes",
                },
                "expected": {
                    "trigger": "when stressed at 11 pm",
                    "current_loop": "all-night doomscrolling",
                    "friction_blocker": "shoes are not ready",
                    "__medicine": "Nicotine gum",
                    "__timing": "At night if craving spikes",
                },
            },
        }

        for problem_name, payload in cases.items():
            sections = parse_markdown_sections(_condition_specific_markdown(problem_name))
            transcript_notes = _transcript_notes([{"role": "user", "text": payload["transcript"]}])
            evidence = _condition_evidence(
                problem_name,
                values=payload["dashboard"],
                sections=sections,
                matched_sections=(),
                transcript_notes=transcript_notes,
                pair_lookup=_pair_lookup(payload["dashboard"], sections),
            )
            lowered = {key: value.lower() for key, value in evidence.items() if value}
            for key, snippet in payload["expected"].items():
                self.assertIn(key, evidence, msg=f"{problem_name}:missing-key:{key}")
                self.assertIn(snippet.lower(), lowered.get(key, ""), msg=f"{problem_name}:{key}:{snippet}")

    def test_all_supported_problems_route_to_explicit_extractor_family(self):
        for problem_name in SUPPORTED_REPORT_PROBLEMS:
            self.assertIn(
                _problem_key(problem_name),
                _EXPLICIT_CONDITION_KEYS,
                msg=f"{problem_name} still falls through to generic extractor routing.",
            )

    def test_condition_extractors_return_structured_evidence_schema(self):
        sections = parse_markdown_sections(_condition_specific_markdown("Diabetes Type 2"))
        evidence = _condition_evidence(
            "Diabetes Type 2",
            values={
                "medicine": "Metformin 500 mg",
                "medicine_timing": "After breakfast and dinner",
            },
            sections=sections,
            matched_sections=(),
            transcript_notes=_transcript_notes(
                [
                    {
                        "role": "user",
                        "text": "My fasting sugar is 182 and I feel shaky if lunch is delayed.",
                    }
                ]
            ),
            pair_lookup=_pair_lookup(
                {"medicine": "Metformin 500 mg", "medicine_timing": "After breakfast and dinner"},
                sections,
            ),
        )

        self.assertIsInstance(evidence, ConditionEvidence)
        self.assertIn("fasting sugar", evidence.slot("glucose_pattern").lower())
        self.assertIn("fasting sugar", evidence.row("Glucose pattern").lower())
        self.assertEqual(evidence.medicine, "Metformin 500 mg")
        self.assertEqual(evidence.timing, "After breakfast and dinner")
        self.assertIn(("__medicine", "Metformin 500 mg"), evidence.items())
        self.assertIn(("glucose_pattern", evidence.slot("glucose_pattern")), evidence.items())
        self.assertIn("glucose_pattern", evidence)
        self.assertIn("Glucose pattern", evidence)

    def test_condition_schema_drives_symptom_row_mapping(self):
        sections = parse_markdown_sections(_condition_specific_markdown("Heart health"))
        evidence = _condition_evidence(
            "Heart health",
            values={"daily_goal": "Track cardiac red flags"},
            sections=sections,
            matched_sections=(),
            transcript_notes=_transcript_notes(
                [
                    {
                        "role": "user",
                        "text": "I get chest pressure on stairs and it gets better with rest but sometimes comes with sweating.",
                    }
                ]
            ),
            pair_lookup=_pair_lookup({"daily_goal": "Track cardiac red flags"}, sections),
        )
        schema = _condition_schema("Heart health")
        rows = _symptom_rows_for_problem("Heart health", evidence)

        self.assertEqual([row[0] for row in rows], [field.label for field in schema.symptom_fields])
        self.assertEqual([row[2] for row in rows], [field.guidance for field in schema.symptom_fields])
        mapped = {label: captured for label, captured, _ in rows}
        self.assertIn("chest pressure on stairs", mapped["Primary cardiac symptom"].lower())
        self.assertIn("rest", mapped["Trigger / relief pattern"].lower())

    def test_condition_extractors_track_evidence_sources(self):
        diabetes_sections = parse_markdown_sections(_condition_specific_markdown("Diabetes Type 2"))
        diabetes = _condition_evidence(
            "Diabetes Type 2",
            values={
                "medicine": "Metformin 500 mg",
                "medicine_timing": "After breakfast and dinner",
            },
            sections=diabetes_sections,
            matched_sections=(),
            transcript_notes=_transcript_notes(
                [
                    {
                        "role": "user",
                        "text": "My fasting sugar is 182 and I feel shaky if lunch is delayed.",
                    }
                ]
            ),
            pair_lookup=_pair_lookup(
                {"medicine": "Metformin 500 mg", "medicine_timing": "After breakfast and dinner"},
                diabetes_sections,
            ),
        )
        self.assertEqual(diabetes.source("glucose_pattern"), "transcript")
        self.assertEqual(diabetes.source("__medicine"), "dashboard")
        self.assertEqual(diabetes.source("__timing"), "dashboard")
        self.assertEqual(diabetes.source("Glucose pattern"), "transcript")

        pregnancy_sections = parse_markdown_sections(_condition_specific_markdown("Pregnancy"))
        pregnancy = _condition_evidence(
            "Pregnancy",
            values={"trimester": "12 weeks pregnant"},
            sections=pregnancy_sections,
            matched_sections=(),
            transcript_notes=_transcript_notes(
                [
                    {
                        "role": "user",
                        "text": "I have morning nausea and light spotting yesterday.",
                    }
                ]
            ),
            pair_lookup=_pair_lookup({"trimester": "12 weeks pregnant"}, pregnancy_sections),
        )
        self.assertEqual(pregnancy.source("trimester_context"), "dashboard")
        self.assertEqual(pregnancy.source("Trimester context"), "dashboard")
        self.assertEqual(pregnancy.source("current_symptom"), "transcript")

        sexual_sections = parse_markdown_sections(_condition_specific_markdown("Sexual health"))
        sexual = _condition_evidence(
            "Sexual health",
            values={"medicine_timing": "Once daily after food"},
            sections=sexual_sections,
            matched_sections=(),
            transcript_notes=_transcript_notes(
                [
                    {
                        "role": "user",
                        "text": "I took azithromycin last week and got nausea after unprotected sex with yellow discharge.",
                    }
                ]
            ),
            pair_lookup=_pair_lookup({"medicine_timing": "Once daily after food"}, sexual_sections),
        )
        self.assertEqual(sexual.source("__medicine"), "transcript")
        self.assertEqual(sexual.source("__timing"), "dashboard")
        self.assertEqual(sexual.source("__side_effects"), "transcript")

    def test_intake_assessment_tracks_timeline_and_next_questions(self):
        assessment = assess_intake(
            "Sexual health",
            transcript_lines=[
                "I have itching and discharge.",
                "This started 4 days ago after unprotected sex.",
            ],
            dashboard_values={"medicine": "Clotrimazole cream"},
            reminders=["Call me at 8 PM if needed."],
        )

        self.assertEqual(assessment.problem_key, "sexual")
        self.assertFalse(assessment.report_ready)
        self.assertIn("Severity and frequency", assessment.timeline_gaps)
        self.assertIn("Testing or doctor-referral history", [field.label for field in assessment.missing_fields])
        self.assertGreaterEqual(len(assessment.next_questions), 1)
        self.assertIn("how often", " ".join(assessment.next_questions).lower())
        self.assertIn("testing_history", assessment.archive_targets_pending)
        self.assertIn("medicine_context", assessment.archive_targets_captured)

    def test_protocol_engine_context_includes_structured_intake_requirements(self):
        user = User.objects.create_user(
            username="intakectx@example.com",
            email="intakectx@example.com",
            password="secret123",
        )
        token = Token.objects.create(user=user)
        self.client.credentials(HTTP_AUTHORIZATION=f"Token {token.key}")
        self.client.patch(
            reverse("me"),
            {
                "name": "Nisha Verma",
                "selected_problems": ["Sexual health"],
                "dashboard_values": {"medicine": "Pain killer"},
            },
            format="json",
        )
        HealthMemoryEntry.objects.create(
            user=user,
            problem_name="Sexual health",
            source=HealthMemoryEntry.Source.CHAT,
            category=HealthMemoryEntry.Category.SYMPTOM,
            title="Existing symptom note",
            content="Burning started 2 days ago after sex.",
        )

        response = self.client.get(
            reverse("protocol-engine-context"),
            {
                "condition": "Sexual health",
                "text": "I still have burning and discharge.",
            },
        )

        self.assertEqual(response.status_code, 200)
        intake = response.data["intake_requirements"]
        self.assertEqual(intake["problem_key"], "sexual")
        self.assertIn("Severity and frequency", intake["missing_labels"])
        self.assertIn("Testing or doctor-referral history", intake["missing_labels"])
        self.assertGreaterEqual(len(intake["next_questions"]), 1)
        self.assertIn("report_ready", intake)
        self.assertIn("timeline_gaps", intake)

    def test_mobile_intake_schema_asset_matches_backend_source_of_truth(self):
        asset_path = (
            Path(__file__).resolve().parents[3]
            / "apps"
            / "mobile"
            / "assets"
            / "health_protocols"
            / "flicko_intake_schema_v1.json"
        )
        payload = json.loads(asset_path.read_text(encoding="utf-8"))

        self.assertEqual(payload, intake_schema_payload())
        sexual = next(
            condition
            for condition in payload["conditions"]
            if condition["problem_key"] == "sexual"
        )
        self.assertIn("Sexual health", sexual["match_terms"])
        self.assertIn("private_symptom", [field["key"] for field in sexual["fields"]])

    def test_incomplete_report_sync_does_not_mark_profile_intake_complete(self):
        user = User.objects.create_user(
            username="reportgap@example.com",
            email="reportgap@example.com",
            password="secret123",
        )
        token = Token.objects.create(user=user)
        self.client.credentials(HTTP_AUTHORIZATION=f"Token {token.key}")

        response = self.client.post(
            reverse("intake-reports"),
            {
                "title": "Quick sexual health note",
                "problem_name": "Sexual health",
                "transcript": [
                    {
                        "role": "user",
                        "text": "I have itching only.",
                    }
                ],
                "analyze_conversation": True,
            },
            format="json",
        )

        self.assertEqual(response.status_code, 201)
        self.assertFalse(response.data["intake_completed"])
        self.assertFalse(response.data["analysis"]["intake_assessment"]["is_complete"])
        self.assertFalse(response.data["analysis"]["intake_assessment"]["report_ready"])
        self.assertGreaterEqual(
            len(response.data["analysis"]["intake_assessment"]["next_questions"]),
            1,
        )

    def test_health_corpus_import_and_search_api(self):
        user = User.objects.create_user(
            username="corpus@example.com",
            email="corpus@example.com",
            password="secret123",
        )
        token = Token.objects.create(user=user)
        self.client.credentials(HTTP_AUTHORIZATION=f"Token {token.key}")

        output = StringIO()
        call_command("import_health_corpus", stdout=output)

        self.assertTrue(HealthProtocol.objects.filter(protocol_id="FLK-DM2-CARE-001").exists())
        self.assertTrue(FoodRule.objects.filter(condition="Diabetes Type 2").exists())
        self.assertTrue(SafetyRule.objects.filter(condition="Blood pressure").exists())

        response = self.client.get(
            reverse("health-corpus-search"),
            {"condition": "Diabetes Type 2", "limit": 5},
        )
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data["condition"], "Diabetes Type 2")
        self.assertGreaterEqual(len(response.data["protocols"]), 1)
        self.assertEqual(response.data["protocols"][0]["protocol_id"], "FLK-DM2-CARE-001")
        self.assertGreaterEqual(len(response.data["food_rules"]), 1)

        response = self.client.get(
            reverse("health-protocol-detail", args=["FLK-DM2-CARE-001"])
        )
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data["protocol"]["protocol_id"], "FLK-DM2-CARE-001")
        self.assertGreaterEqual(len(response.data["protocol"]["evidence"]), 1)

    def test_protocol_engine_context_merges_protocols_evidence_and_memory(self):
        user = User.objects.create_user(
            username="engine@example.com",
            email="engine@example.com",
            password="secret123",
        )
        token = Token.objects.create(user=user)
        self.client.credentials(HTTP_AUTHORIZATION=f"Token {token.key}")
        call_command("import_health_corpus", stdout=StringIO())

        self.client.patch(
            reverse("me"),
            {
                "name": "Kartik Patel",
                "selected_problems": ["Blood pressure", "Diabetes Type 2"],
                "safety_consent_accepted": True,
                "intake_completed": True,
                "dashboard_values": {"latest_bp": "170/105"},
                "dashboard_notes": ["Evening BP log pending"],
                "reminders": ["8 PM BP log"],
            },
            format="json",
        )
        HealthMemoryEntry.objects.create(
            user=user,
            problem_name="Blood pressure",
            source=HealthMemoryEntry.Source.CHAT,
            category=HealthMemoryEntry.Category.SYMPTOM,
            title="Headache and BP note",
            content="User reported severe headache with high BP reading.",
            data={"latest_bp": "170/105"},
        )

        response = self.client.get(
            reverse("protocol-engine-context"),
            {
                "condition": "Blood pressure",
                "text": "I have chest pain and severe headache",
            },
        )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data["primary_condition"], "Blood pressure")
        self.assertIn("FLK-BP-CARE-001", response.data["protocol_engine"]["protocol_ids"])
        self.assertEqual(
            response.data["protocol_engine"]["protocol_versions"]["FLK-BP-CARE-001"],
            1,
        )
        self.assertGreaterEqual(
            len(response.data["protocol_engine"]["evidence_source_ids"]["FLK-BP-CARE-001"]),
            1,
        )
        self.assertTrue(response.data["safety"]["must_escalate"])
        self.assertEqual(response.data["safety"]["highest_severity"], "emergency")
        self.assertGreaterEqual(len(response.data["memory_timeline"]), 1)
        self.assertEqual(response.data["dashboard_seed"]["dashboard_values"]["latest_bp"], "170/105")
        self.assertIn("Cite internal protocol IDs", response.data["ai_guardrails"][1])
