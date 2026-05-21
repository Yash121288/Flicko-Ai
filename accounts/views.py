from __future__ import annotations

from django.conf import settings
from django.contrib.auth import authenticate
from django.contrib.auth.models import User
from django.core.files.base import ContentFile
from django.db import transaction
from django.db.models import Q
from django.utils import timezone
from rest_framework import status, throttling
from rest_framework.authtoken.models import Token
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView
from google.auth.transport import requests as google_requests
from google.oauth2 import id_token as google_id_token

from .models import (
    FoodRule,
    HealthCorpusChunk,
    HealthMemoryEntry,
    HealthProtocol,
    EmailOTP,
    IntakeFlow,
    MemorySchema,
    OutcomeMetric,
    ReminderScript,
    ReportBlock,
    SafetyRule,
    UserProfile,
)
from .serializers import (
    FoodRuleSerializer,
    ForgotStartSerializer,
    HealthAppDataSyncSerializer,
    HealthCorpusChunkSerializer,
    HealthMemoryEntryCreateSerializer,
    HealthMemoryEntrySerializer,
    HealthIntakeReportCreateSerializer,
    HealthIntakeReportSerializer,
    HealthProtocolDetailSerializer,
    HealthProtocolListSerializer,
    IntakeFlowSerializer,
    GoogleLoginSerializer,
    LoginSerializer,
    MemorySchemaSerializer,
    OutcomeMetricSerializer,
    PasswordResetSerializer,
    PROFILE_JSON_DICT_FIELDS,
    PROFILE_JSON_LIST_FIELDS,
    PROFILE_JSON_OBJECT_LIST_FIELDS,
    PROFILE_TEXT_FIELDS,
    ProfilePatchSerializer,
    RegisterStartSerializer,
    RegisterVerifySerializer,
    ReminderScriptSerializer,
    ReportBlockSerializer,
    SafetyRuleSerializer,
    UserCareTaskRecordSerializer,
    UserChatMessageRecordSerializer,
    UserHealthLogRecordSerializer,
    UserMealAnalysisRecordSerializer,
    UserReminderRecordSerializer,
    UserSafetyEventRecordSerializer,
    user_payload,
)
from .data_sync import summarize_records_for_dashboard, sync_app_data
from .conversation_analysis import analyze_health_conversation, transcript_to_text
from .db_utils import run_user_write
from .html_reports import build_health_report_html
from .pdf_reports import build_health_report_pdf
from .protocol_engine import ProtocolEngineRequest, build_protocol_context
from .services import create_otp, normalize_email, send_otp_email, split_name, verify_otp


class OTPThrottle(throttling.ScopedRateThrottle):
    scope = "otp"


class LoginThrottle(throttling.ScopedRateThrottle):
    scope = "login"


def token_payload(user: User) -> dict[str, object]:
    token, _ = Token.objects.get_or_create(user=user)
    return {"token": token.key, "user": user_payload(user)}


class RegisterStartView(APIView):
    throttle_classes = [OTPThrottle]

    @transaction.atomic
    def post(self, request):
        serializer = RegisterStartSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data
        email = normalize_email(data["email"])

        first_name, last_name = split_name(data["name"])
        existing = User.objects.filter(username=email).first()
        if existing and existing.is_active:
            return Response(
                {"detail": "This email is already registered. Please login."},
                status=status.HTTP_409_CONFLICT,
            )

        user = existing or User(username=email, email=email, is_active=False)
        user.email = email
        user.first_name = first_name
        user.last_name = last_name
        user.is_active = False
        user.set_password(data["password"])
        user.save()
        UserProfile.objects.update_or_create(
            user=user,
            defaults={"mobile": data["mobile"].strip()},
        )

        _, code = create_otp(email, EmailOTP.Purpose.REGISTER)
        send_otp_email(email, EmailOTP.Purpose.REGISTER, code)
        return Response(
            {"detail": "OTP sent to email.", "email": email},
            status=status.HTTP_200_OK,
        )


class RegisterVerifyView(APIView):
    throttle_classes = [OTPThrottle]

    @transaction.atomic
    def post(self, request):
        serializer = RegisterVerifySerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        email = normalize_email(serializer.validated_data["email"])
        try:
            verify_otp(email, EmailOTP.Purpose.REGISTER, serializer.validated_data["otp"])
        except ValueError as exc:
            return Response({"detail": str(exc)}, status=status.HTTP_400_BAD_REQUEST)

        user = User.objects.filter(username=email).first()
        if user is None:
            return Response({"detail": "User not found."}, status=status.HTTP_404_NOT_FOUND)
        user.is_active = True
        user.save(update_fields=["is_active"])
        return Response(token_payload(user), status=status.HTTP_200_OK)


class LoginView(APIView):
    throttle_classes = [LoginThrottle]

    def post(self, request):
        serializer = LoginSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        email = normalize_email(serializer.validated_data["email"])
        user = authenticate(
            request,
            username=email,
            password=serializer.validated_data["password"],
        )
        if user is None:
            return Response(
                {"detail": "Invalid email or password."},
                status=status.HTTP_401_UNAUTHORIZED,
            )
        if not user.is_active:
            return Response(
                {"detail": "Email is not verified."},
                status=status.HTTP_403_FORBIDDEN,
            )
        return Response(token_payload(user), status=status.HTTP_200_OK)


class GoogleLoginView(APIView):
    throttle_classes = [LoginThrottle]

    @transaction.atomic
    def post(self, request):
        serializer = GoogleLoginSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data

        try:
            claims = _verify_google_id_token(data["id_token"])
        except ValueError as exc:
            return Response({"detail": str(exc)}, status=status.HTTP_401_UNAUTHORIZED)

        email = normalize_email(str(claims.get("email") or data.get("email") or ""))
        if not email:
            return Response(
                {"detail": "Google account did not include an email address."},
                status=status.HTTP_400_BAD_REQUEST,
            )
        if not bool(claims.get("email_verified", False)):
            return Response(
                {"detail": "Google email is not verified."},
                status=status.HTTP_403_FORBIDDEN,
            )

        name = str(claims.get("name") or data.get("name") or email).strip()
        first_name, last_name = split_name(name)

        user = User.objects.filter(username=email).first()
        if user is None:
            user = User(username=email, email=email, is_active=True)
            user.first_name = first_name
            user.last_name = last_name
            user.set_unusable_password()
            user.save()
        else:
            update_fields = []
            if not user.is_active:
                user.is_active = True
                update_fields.append("is_active")
            if first_name and not user.first_name:
                user.first_name = first_name
                update_fields.append("first_name")
            if last_name and not user.last_name:
                user.last_name = last_name
                update_fields.append("last_name")
            if update_fields:
                user.save(update_fields=update_fields)

        UserProfile.objects.get_or_create(user=user)
        return Response(token_payload(user), status=status.HTTP_200_OK)


class ForgotPasswordStartView(APIView):
    throttle_classes = [OTPThrottle]

    def post(self, request):
        serializer = ForgotStartSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        email = normalize_email(serializer.validated_data["email"])
        user = User.objects.filter(username=email, is_active=True).first()
        if user:
            _, code = create_otp(email, EmailOTP.Purpose.PASSWORD_RESET)
            send_otp_email(email, EmailOTP.Purpose.PASSWORD_RESET, code)
        return Response(
            {"detail": "If the email exists, an OTP has been sent."},
            status=status.HTTP_200_OK,
        )


class PasswordResetConfirmView(APIView):
    throttle_classes = [OTPThrottle]

    @transaction.atomic
    def post(self, request):
        serializer = PasswordResetSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        email = normalize_email(serializer.validated_data["email"])
        try:
            verify_otp(
                email,
                EmailOTP.Purpose.PASSWORD_RESET,
                serializer.validated_data["otp"],
            )
        except ValueError as exc:
            return Response({"detail": str(exc)}, status=status.HTTP_400_BAD_REQUEST)

        user = User.objects.filter(username=email, is_active=True).first()
        if user is None:
            return Response({"detail": "User not found."}, status=status.HTTP_404_NOT_FOUND)
        user.set_password(serializer.validated_data["new_password"])
        user.save(update_fields=["password"])
        Token.objects.filter(user=user).delete()
        return Response({"detail": "Password reset complete."}, status=status.HTTP_200_OK)


def _verify_google_id_token(token: str) -> dict:
    trimmed = token.strip()
    if not trimmed:
        raise ValueError("Missing Google ID token.")

    allowed_audiences = getattr(settings, "GOOGLE_OAUTH_CLIENT_IDS", [])
    allow_unconfigured_debug = bool(
        getattr(settings, "GOOGLE_OAUTH_ALLOW_UNCONFIGURED_DEBUG", False)
    )
    if not allowed_audiences and not allow_unconfigured_debug:
        raise ValueError("Google OAuth client IDs are not configured on the backend.")

    claims = google_id_token.verify_oauth2_token(
        trimmed,
        google_requests.Request(),
    )
    audience = str(claims.get("aud") or "")
    if allowed_audiences and audience not in allowed_audiences:
        raise ValueError("Google token audience is not allowed for Flicko.")
    return claims


class MeView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        UserProfile.objects.get_or_create(user=request.user)
        return Response({"user": user_payload(request.user)}, status=status.HTTP_200_OK)

    def patch(self, request):
        serializer = ProfilePatchSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        user = request.user
        data = serializer.validated_data

        def write_profile() -> dict[str, object]:
            profile, _ = UserProfile.objects.get_or_create(user=user)
            if "name" in data:
                user.first_name, user.last_name = split_name(data["name"])
                user.save(update_fields=["first_name", "last_name"])

            if "mobile" in data:
                profile.mobile = data["mobile"].strip()

            for field in PROFILE_TEXT_FIELDS:
                if field in data:
                    setattr(profile, field, data[field].strip())
            if "age" in data:
                profile.age = data["age"]
            if "safety_consent_accepted" in data:
                profile.safety_consent_accepted = data["safety_consent_accepted"]
            if "intake_completed" in data:
                profile.intake_completed = data["intake_completed"]
            for field in PROFILE_JSON_LIST_FIELDS:
                if field in data:
                    setattr(profile, field, _clean_string_list(data[field]))
            for field in PROFILE_JSON_OBJECT_LIST_FIELDS:
                if field in data:
                    setattr(profile, field, data[field])
            for field in PROFILE_JSON_DICT_FIELDS:
                if field in data:
                    setattr(profile, field, data[field])

            profile.last_synced_at = timezone.now()
            profile.save()
            _write_profile_memory(user, data)
            sync_app_data(user, data, problem_name=_primary_problem_from_profile(profile))
            return user_payload(user)

        return Response(
            {"user": run_user_write(user, write_profile)},
            status=status.HTTP_200_OK,
        )


class HealthAppDataView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        limit = _bounded_limit(request.query_params.get("limit", "50"), default=50, maximum=200)
        user = request.user
        chat_records = list(
            user.chat_message_records.order_by("-sent_at", "-created_at")[:limit]
        )
        chat_records.reverse()
        return Response(
            {
                "summary": summarize_records_for_dashboard(user),
                "health_logs": UserHealthLogRecordSerializer(
                    user.health_log_records.all()[:limit],
                    many=True,
                ).data,
                "meal_analyses": UserMealAnalysisRecordSerializer(
                    user.meal_analysis_records.all()[:limit],
                    many=True,
                ).data,
                "saved_reminders": UserReminderRecordSerializer(
                    user.reminder_records.all()[:limit],
                    many=True,
                ).data,
                "care_tasks": UserCareTaskRecordSerializer(
                    user.care_task_records.all()[:limit],
                    many=True,
                ).data,
                "safety_events": UserSafetyEventRecordSerializer(
                    user.safety_event_records.all()[:limit],
                    many=True,
                ).data,
                "chat_history": UserChatMessageRecordSerializer(chat_records, many=True).data,
                "memory": HealthMemoryEntrySerializer(
                    user.health_memory.all()[:limit],
                    many=True,
                ).data,
            },
            status=status.HTTP_200_OK,
        )

    def post(self, request):
        serializer = HealthAppDataSyncSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data

        def sync_records() -> dict[str, object]:
            profile, _ = UserProfile.objects.get_or_create(user=request.user)
            for field in PROFILE_JSON_OBJECT_LIST_FIELDS:
                if field in data:
                    setattr(profile, field, data[field])
            profile.last_synced_at = timezone.now()
            profile.save()

            counts = sync_app_data(
                request.user,
                data,
                problem_name=_primary_problem_from_profile(profile),
            )
            _write_profile_memory(request.user, data)
            return {
                "synced": counts,
                "summary": summarize_records_for_dashboard(request.user),
            }

        return Response(
            run_user_write(request.user, sync_records),
            status=status.HTTP_200_OK,
        )


class HealthAppDataCleanupView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request):
        def cleanup_records() -> dict[str, object]:
            profile, _ = UserProfile.objects.get_or_create(user=request.user)
            removed = _cleanup_stale_ai_artifacts(request.user, profile)
            return {
                "removed": removed,
                "summary": summarize_records_for_dashboard(request.user),
            }

        return Response(
            run_user_write(request.user, cleanup_records),
            status=status.HTTP_200_OK,
        )


APP_RECORD_TYPES = {
    "health-logs": {
        "profile_key": "health_logs",
        "model": "health_log_records",
        "serializer": UserHealthLogRecordSerializer,
    },
    "meal-analyses": {
        "profile_key": "meal_analyses",
        "model": "meal_analysis_records",
        "serializer": UserMealAnalysisRecordSerializer,
    },
    "reminders": {
        "profile_key": "saved_reminders",
        "model": "reminder_records",
        "serializer": UserReminderRecordSerializer,
    },
    "care-tasks": {
        "profile_key": "care_tasks",
        "model": "care_task_records",
        "serializer": UserCareTaskRecordSerializer,
    },
    "safety-events": {
        "profile_key": "safety_events",
        "model": "safety_event_records",
        "serializer": UserSafetyEventRecordSerializer,
    },
    "chat-messages": {
        "profile_key": "chat_history",
        "model": "chat_message_records",
        "serializer": UserChatMessageRecordSerializer,
    },
}


class HealthAppRecordCollectionView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request, record_type: str):
        config = _app_record_config(record_type)
        if config is None:
            return Response({"detail": "Unsupported app record type."}, status=status.HTTP_404_NOT_FOUND)
        limit = _bounded_limit(request.query_params.get("limit", "80"), default=80, maximum=300)
        records = getattr(request.user, config["model"]).all()[:limit]
        return Response(
            {
                "records": config["serializer"](records, many=True).data,
                "summary": summarize_records_for_dashboard(request.user),
            },
            status=status.HTTP_200_OK,
        )

    def post(self, request, record_type: str):
        config = _app_record_config(record_type)
        if config is None:
            return Response({"detail": "Unsupported app record type."}, status=status.HTTP_404_NOT_FOUND)
        if not isinstance(request.data, dict):
            return Response({"detail": "Record payload must be an object."}, status=status.HTTP_400_BAD_REQUEST)

        payload = dict(request.data)

        def sync_record() -> dict[str, object]:
            profile, _ = UserProfile.objects.get_or_create(user=request.user)
            data = {config["profile_key"]: [payload]}
            counts = sync_app_data(
                request.user,
                data,
                problem_name=_primary_problem_from_profile(profile),
            )
            _merge_profile_json_record(profile, str(config["profile_key"]), payload)
            _write_profile_memory(request.user, data)
            external_id = str(payload.get("id") or "").strip()
            record = (
                getattr(request.user, config["model"])
                .filter(external_id=external_id)
                .first()
                if external_id
                else getattr(request.user, config["model"]).first()
            )
            return {
                "record": config["serializer"](record).data if record else {},
                "synced": counts,
                "summary": summarize_records_for_dashboard(request.user),
            }

        return Response(
            run_user_write(request.user, sync_record),
            status=status.HTTP_200_OK,
        )


class HealthAppRecordDetailView(APIView):
    permission_classes = [IsAuthenticated]

    def delete(self, request, record_type: str, external_id: str):
        config = _app_record_config(record_type)
        if config is None:
            return Response({"detail": "Unsupported app record type."}, status=status.HTTP_404_NOT_FOUND)

        def delete_record() -> dict[str, object]:
            deleted, _ = getattr(request.user, config["model"]).filter(
                external_id=external_id,
            ).delete()
            profile, _ = UserProfile.objects.get_or_create(user=request.user)
            _remove_profile_json_record(profile, str(config["profile_key"]), external_id)
            return {
                "deleted": deleted > 0,
                "summary": summarize_records_for_dashboard(request.user),
            }

        return Response(
            run_user_write(request.user, delete_record),
            status=status.HTTP_200_OK,
        )


class HealthMemoryEntryView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        entries = request.user.health_memory.all()
        category = request.query_params.get("category", "").strip()
        source = request.query_params.get("source", "").strip()
        problem_name = request.query_params.get("problem_name", "").strip()
        if category:
            entries = entries.filter(category=category)
        if source:
            entries = entries.filter(source=source)
        if problem_name:
            entries = entries.filter(problem_name=problem_name)
        try:
            limit = max(1, min(100, int(request.query_params.get("limit", "50"))))
        except ValueError:
            limit = 50
        serializer = HealthMemoryEntrySerializer(entries[:limit], many=True)
        return Response({"memory": serializer.data}, status=status.HTTP_200_OK)

    def post(self, request):
        serializer = HealthMemoryEntryCreateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)

        def create_memory() -> dict[str, object]:
            entry = HealthMemoryEntry.objects.create(
                user=request.user,
                **serializer.validated_data,
            )
            return HealthMemoryEntrySerializer(entry).data

        return Response(
            run_user_write(request.user, create_memory),
            status=status.HTTP_201_CREATED,
        )


class HealthCorpusSearchView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        condition = request.query_params.get("condition", "").strip()
        query = request.query_params.get("q", "").strip()
        corpus_type = request.query_params.get("type", "all").strip().lower()
        limit = _bounded_limit(request.query_params.get("limit", "8"), default=8, maximum=30)

        response = {
            "condition": condition,
            "query": query,
            "protocols": [],
            "food_rules": [],
            "safety_rules": [],
            "intake_flows": [],
            "reminders": [],
            "report_blocks": [],
            "outcome_metrics": [],
            "memory_schemas": [],
            "source_chunks": [],
        }

        if corpus_type in ("all", "protocols"):
            protocols = HealthProtocol.objects.all().prefetch_related("evidence")
            protocols = _filter_condition(protocols, condition)
            if query:
                protocols = protocols.filter(
                    _text_query(
                        query,
                        "protocol_id",
                        "title",
                        "summary",
                        "content",
                        "condition",
                    )
                )
            response["protocols"] = HealthProtocolListSerializer(
                protocols[:limit],
                many=True,
            ).data

        if corpus_type in ("all", "food", "food_rules"):
            food_rules = FoodRule.objects.select_related("protocol")
            food_rules = _filter_condition(food_rules, condition)
            if query:
                food_rules = food_rules.filter(
                    _text_query(query, "food_name", "guidance", "reason", "condition")
                )
            response["food_rules"] = FoodRuleSerializer(food_rules[:limit], many=True).data

        if corpus_type in ("all", "safety", "safety_rules"):
            safety_rules = SafetyRule.objects.select_related("protocol")
            safety_rules = _filter_condition(safety_rules, condition)
            if query:
                safety_rules = safety_rules.filter(
                    _text_query(query, "symptom_pattern", "action", "escalation_text", "condition")
                )
            response["safety_rules"] = SafetyRuleSerializer(
                safety_rules[:limit],
                many=True,
            ).data

        if corpus_type in ("all", "intake", "intake_flows"):
            intake_flows = IntakeFlow.objects.select_related("protocol").filter(active=True)
            intake_flows = _filter_condition(intake_flows, condition)
            if query:
                intake_flows = intake_flows.filter(_text_query(query, "flow_id", "title", "condition"))
            response["intake_flows"] = IntakeFlowSerializer(
                intake_flows[:limit],
                many=True,
            ).data

        if corpus_type in ("all", "reminders"):
            reminders = ReminderScript.objects.select_related("protocol").filter(active=True)
            reminders = _filter_condition(reminders, condition)
            if query:
                reminders = reminders.filter(
                    _text_query(query, "trigger_type", "title", "script", "condition")
                )
            response["reminders"] = ReminderScriptSerializer(
                reminders[:limit],
                many=True,
            ).data

        if corpus_type in ("all", "reports", "report_blocks"):
            report_blocks = ReportBlock.objects.select_related("protocol").filter(active=True)
            report_blocks = _filter_condition(report_blocks, condition)
            if query:
                report_blocks = report_blocks.filter(
                    _text_query(query, "block_type", "title", "markdown_template", "condition")
                )
            response["report_blocks"] = ReportBlockSerializer(
                report_blocks[:limit],
                many=True,
            ).data

        if corpus_type in ("all", "metrics", "outcome_metrics"):
            metrics = OutcomeMetric.objects.all()
            metrics = _filter_condition(metrics, condition)
            if query:
                metrics = metrics.filter(_text_query(query, "metric_key", "label", "condition"))
            response["outcome_metrics"] = OutcomeMetricSerializer(
                metrics[:limit],
                many=True,
            ).data

        if corpus_type in ("all", "memory", "memory_schemas"):
            schemas = MemorySchema.objects.all()
            schemas = _filter_condition(schemas, condition)
            if query:
                schemas = schemas.filter(
                    _text_query(query, "schema_key", "category", "extraction_prompt", "condition")
                )
            response["memory_schemas"] = MemorySchemaSerializer(
                schemas[:limit],
                many=True,
            ).data

        if corpus_type in ("all", "chunks", "source_chunks"):
            chunks = HealthCorpusChunk.objects.select_related("source")
            chunks = _filter_condition(chunks, condition)
            if query:
                chunks = chunks.filter(_text_query(query, "chunk_uid", "title", "text", "condition"))
            response["source_chunks"] = HealthCorpusChunkSerializer(
                chunks[:limit],
                many=True,
            ).data

        return Response(response, status=status.HTTP_200_OK)


class HealthProtocolDetailView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request, protocol_id: str):
        protocol = (
            HealthProtocol.objects.prefetch_related("source_chunks__source", "evidence__source")
            .filter(protocol_id=protocol_id)
            .first()
        )
        if protocol is None:
            return Response({"detail": "Protocol not found."}, status=status.HTTP_404_NOT_FOUND)
        return Response(
            {"protocol": HealthProtocolDetailSerializer(protocol).data},
            status=status.HTTP_200_OK,
        )


class HealthProtocolEngineContextView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        condition = request.query_params.get("condition", "").strip()
        text = request.query_params.get("text", "").strip()
        limit = _bounded_limit(request.query_params.get("memory_limit", "12"), default=12, maximum=50)
        context = build_protocol_context(
            ProtocolEngineRequest(
                user=request.user,
                condition=condition,
                text=text,
                memory_limit=limit,
            )
        )
        return Response(context, status=status.HTTP_200_OK)


class HealthIntakeReportView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        reports = request.user.health_reports.all()[:20]
        serializer = HealthIntakeReportSerializer(
            reports,
            many=True,
            context={"request": request},
        )
        return Response({"reports": serializer.data}, status=status.HTTP_200_OK)

    def post(self, request):
        serializer = HealthIntakeReportCreateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data
        current_profile = UserProfile.objects.filter(user=request.user).first()
        problem_name = data.get("problem_name") or (
            _primary_problem_from_profile(current_profile)
            if current_profile is not None
            else "General health"
        )
        transcript = data.get("transcript", [])
        analysis = None
        if data.get("analyze_conversation", True):
            analysis = analyze_health_conversation(
                user=request.user,
                problem_name=problem_name,
                intake_summary=data.get("intake_summary", ""),
                dashboard_values=data.get("dashboard_values", {}),
                reminders=data.get("reminders", []),
                transcript=transcript,
                source_payload=data.get("source_payload", {}),
                raw_transcript_text=data.get("raw_transcript_text", ""),
            )

        report_summary = (
            analysis.report_markdown
            if analysis is not None and analysis.report_markdown.strip()
            else data.get("intake_summary", "")
        )
        report_reminders = (
            analysis.reminders
            if analysis is not None and analysis.reminders
            else data.get("reminders", [])
        )

        def create_report_shell() -> int:
            profile, _ = UserProfile.objects.get_or_create(user=request.user)
            if analysis is not None:
                _apply_conversation_analysis_to_profile(profile, analysis)
                sync_app_data(
                    request.user,
                    analysis.app_data,
                    problem_name=problem_name,
                )
            dashboard_values = {
                **data.get("dashboard_values", {}),
                **(analysis.dashboard_values if analysis is not None else {}),
                **summarize_records_for_dashboard(request.user),
            }
            report = request.user.health_reports.create(
                title=data.get("title") or "Flicko AI Intake Report",
                problem_name=problem_name,
                intake_summary=report_summary,
                dashboard_values=dashboard_values,
                reminders=report_reminders,
                transcript=transcript,
            )
            return int(report.id)

        report_id = run_user_write(
            request.user,
            create_report_shell,
            attempts=10,
            base_delay_seconds=0.12,
        )
        report = request.user.health_reports.get(id=report_id)
        pdf_bytes = build_health_report_pdf(report)
        html = build_health_report_html(report)

        def finalize_report() -> dict[str, object]:
            fresh_report = request.user.health_reports.get(id=report_id)
            fresh_report.pdf_file.save(
                f"flicko-report-{fresh_report.id}.pdf",
                ContentFile(pdf_bytes),
                save=False,
            )
            fresh_report.html_file.save(
                f"flicko-report-{fresh_report.id}.html",
                ContentFile(html.encode("utf-8")),
                save=False,
            )
            fresh_report.save(update_fields=["pdf_file", "html_file"])
            profile, _ = UserProfile.objects.get_or_create(user=request.user)
            _attach_report_to_profile(profile, fresh_report)
            if analysis is not None:
                HealthMemoryEntry.objects.create(
                    user=request.user,
                    problem_name=fresh_report.problem_name,
                    source=HealthMemoryEntry.Source.CALL
                    if data.get("source") == "call"
                    else HealthMemoryEntry.Source.CHAT,
                    category=HealthMemoryEntry.Category.INTAKE_SUMMARY,
                    title=f"{fresh_report.title} source transcript",
                    content=analysis.raw_transcript_text[:120000],
                    data={
                        "report_id": fresh_report.id,
                        "analyzer": analysis.analyzer,
                        "analysis": analysis.to_response(),
                        "source_payload": data.get("source_payload", {}),
                    },
                )
                HealthMemoryEntry.objects.create(
                    user=request.user,
                    problem_name=fresh_report.problem_name,
                    source=HealthMemoryEntry.Source.CALL
                    if data.get("source") == "call"
                    else HealthMemoryEntry.Source.CHAT,
                    category=HealthMemoryEntry.Category.INTAKE_SUMMARY,
                    title=f"{fresh_report.title} structured intake map",
                    content=str(
                        analysis.intake_assessment.get("archive_markdown") or ""
                    )[:120000],
                    data={
                        "report_id": fresh_report.id,
                        "intake_assessment": analysis.intake_assessment,
                    },
                )
            HealthMemoryEntry.objects.create(
                user=request.user,
                problem_name=fresh_report.problem_name,
                source=HealthMemoryEntry.Source.REPORT,
                category=HealthMemoryEntry.Category.REPORT,
                title=fresh_report.title,
                content=fresh_report.intake_summary[:120000],
                data={
                    "report_id": fresh_report.id,
                    "pdf_url": fresh_report.pdf_file.url if fresh_report.pdf_file else "",
                    "html_url": fresh_report.html_file.url if fresh_report.html_file else "",
                    "dashboard_values": fresh_report.dashboard_values,
                    "reminders": fresh_report.reminders,
                    "analyzer": analysis.analyzer if analysis is not None else "request_payload",
                },
            )
            output = HealthIntakeReportSerializer(
                fresh_report,
                context={"request": request},
            )
            response_data = dict(output.data)
            response_data.update(
                {
                    "summary": summarize_records_for_dashboard(request.user),
                    "dashboard_notes": profile.dashboard_notes,
                    "saved_reminders": analysis.app_data.get("saved_reminders", [])
                    if analysis is not None
                    else [],
                    "care_tasks": analysis.app_data.get("care_tasks", [])
                    if analysis is not None
                    else [],
                    "health_logs": analysis.app_data.get("health_logs", [])
                    if analysis is not None
                    else [],
                    "safety_events": analysis.app_data.get("safety_events", [])
                    if analysis is not None
                    else [],
                    "intake_completed": profile.intake_completed,
                    "analysis": analysis.to_response() if analysis is not None else {},
                }
            )
            return response_data

        response_data = run_user_write(
            request.user,
            finalize_report,
            attempts=10,
            base_delay_seconds=0.12,
        )
        return Response(response_data, status=status.HTTP_201_CREATED)


def _apply_conversation_analysis_to_profile(
    profile: UserProfile,
    analysis,
) -> None:
    app_data = analysis.app_data
    profile.intake_summary = analysis.report_markdown or analysis.intake_summary
    profile.intake_completed = bool(profile.intake_completed) or bool(
        analysis.intake_assessment.get("is_complete")
    )
    profile.dashboard_values = {
        **(profile.dashboard_values if isinstance(profile.dashboard_values, dict) else {}),
        **analysis.dashboard_values,
    }
    profile.dashboard_notes = _merge_string_values(
        analysis.dashboard_notes,
        profile.dashboard_notes,
        limit=120,
    )
    profile.reminders = _merge_string_values(
        analysis.reminders,
        profile.reminders,
        limit=120,
    )
    profile.saved_reminders = _merge_json_records(
        app_data.get("saved_reminders", []),
        profile.saved_reminders,
        limit=300,
    )
    profile.care_tasks = _merge_json_records(
        app_data.get("care_tasks", []),
        profile.care_tasks,
        limit=300,
    )
    profile.health_logs = _merge_json_records(
        app_data.get("health_logs", []),
        profile.health_logs,
        limit=500,
    )
    profile.safety_events = _merge_json_records(
        app_data.get("safety_events", []),
        profile.safety_events,
        limit=200,
    )
    profile.chat_history = _merge_json_records(
        app_data.get("chat_history", []),
        profile.chat_history,
        limit=500,
    )
    profile.latest_chat_summary = transcript_to_text(app_data.get("chat_history", []))[:12000]
    profile.last_synced_at = timezone.now()
    profile.save()


def _attach_report_to_profile(profile: UserProfile, report) -> None:
    links = [
        f"PDF: {report.pdf_file.url}" if report.pdf_file else "",
        f"HTML: {report.html_file.url}" if report.html_file else "",
    ]
    label = "\n".join(
        [report.title, *[link for link in links if link]]
    ).strip()
    profile.reports = _merge_string_values([label], profile.reports, limit=80)
    profile.last_synced_at = timezone.now()
    profile.save(update_fields=["reports", "last_synced_at", "updated_at"])


def _merge_string_values(*groups, limit: int) -> list[str]:
    seen: set[str] = set()
    result: list[str] = []
    for group in groups:
        if not isinstance(group, list):
            continue
        for value in group:
            text = str(value).strip()
            if not text or text.lower() in seen:
                continue
            seen.add(text.lower())
            result.append(text)
            if len(result) >= limit:
                return result
    return result


def _merge_json_records(incoming, existing, *, limit: int) -> list[dict]:
    records: list[dict] = []
    seen: set[str] = set()
    for group in (incoming, existing):
        if not isinstance(group, list):
            continue
        for value in group:
            if not isinstance(value, dict):
                continue
            record = dict(value)
            marker = str(
                record.get("id")
                or record.get("external_id")
                or record.get("title")
                or record
            ).lower()
            if marker in seen:
                continue
            seen.add(marker)
            records.append(record)
            if len(records) >= limit:
                return records
    return records


def _bounded_limit(value: str, *, default: int, maximum: int) -> int:
    try:
        return max(1, min(maximum, int(value)))
    except ValueError:
        return default


def _filter_condition(queryset, condition: str):
    if not condition:
        return queryset
    return queryset.filter(condition__iexact=condition)


def _text_query(query: str, *fields: str) -> Q:
    criteria = Q()
    for field in fields:
        criteria |= Q(**{f"{field}__icontains": query})
    return criteria


def _clean_string_list(values) -> list[str]:
    if not isinstance(values, list):
        return []
    result: list[str] = []
    seen: set[str] = set()
    for value in values:
        cleaned = str(value).strip()
        if not cleaned or cleaned.lower() in seen:
            continue
        seen.add(cleaned.lower())
        result.append(cleaned)
    return result


def _app_record_config(record_type: str) -> dict[str, object] | None:
    return APP_RECORD_TYPES.get(record_type.strip().lower())


def _merge_profile_json_record(
    profile: UserProfile,
    field: str,
    payload: dict,
) -> None:
    current = getattr(profile, field, [])
    records = list(current) if isinstance(current, list) else []
    external_id = str(payload.get("id") or "").strip()
    if external_id:
        records = [
            item
            for item in records
            if not (isinstance(item, dict) and str(item.get("id") or "").strip() == external_id)
        ]
    records.insert(0, payload)
    setattr(profile, field, records[:500])
    profile.last_synced_at = timezone.now()
    profile.save(update_fields=[field, "last_synced_at", "updated_at"])


def _remove_profile_json_record(
    profile: UserProfile,
    field: str,
    external_id: str,
) -> None:
    current = getattr(profile, field, [])
    if not isinstance(current, list):
        return
    records = [
        item
        for item in current
        if not (isinstance(item, dict) and str(item.get("id") or "").strip() == external_id)
    ]
    setattr(profile, field, records)
    profile.last_synced_at = timezone.now()
    profile.save(update_fields=[field, "last_synced_at", "updated_at"])


def _cleanup_stale_ai_artifacts(user: User, profile: UserProfile) -> dict[str, int]:
    removed: dict[str, int] = {
        "profile_reminders": 0,
        "profile_reports": 0,
        "profile_saved_reminders": 0,
        "profile_care_tasks": 0,
        "reminder_records": 0,
        "care_task_records": 0,
    }
    changed_fields: list[str] = []

    reminders = profile.reminders if isinstance(profile.reminders, list) else []
    clean_reminders = [
        value
        for value in reminders
        if not _is_stale_ai_reminder_text(str(value))
    ]
    removed["profile_reminders"] = len(reminders) - len(clean_reminders)
    if removed["profile_reminders"]:
        profile.reminders = clean_reminders
        changed_fields.append("reminders")

    reports = profile.reports if isinstance(profile.reports, list) else []
    clean_reports = [
        value
        for value in reports
        if not _is_stale_ai_report_text(str(value))
    ]
    removed["profile_reports"] = len(reports) - len(clean_reports)
    if removed["profile_reports"]:
        profile.reports = clean_reports
        changed_fields.append("reports")

    saved_reminders = (
        profile.saved_reminders
        if isinstance(profile.saved_reminders, list)
        else []
    )
    clean_saved_reminders = [
        item
        for item in saved_reminders
        if not (
            isinstance(item, dict)
            and _is_stale_ai_reminder_text(_artifact_blob(item))
        )
    ]
    removed["profile_saved_reminders"] = len(saved_reminders) - len(clean_saved_reminders)
    if removed["profile_saved_reminders"]:
        profile.saved_reminders = clean_saved_reminders
        changed_fields.append("saved_reminders")

    care_tasks = profile.care_tasks if isinstance(profile.care_tasks, list) else []
    clean_care_tasks = [
        item
        for item in care_tasks
        if not (
            isinstance(item, dict)
            and _is_stale_ai_care_task_text(_artifact_blob(item))
        )
    ]
    removed["profile_care_tasks"] = len(care_tasks) - len(clean_care_tasks)
    if removed["profile_care_tasks"]:
        profile.care_tasks = clean_care_tasks
        changed_fields.append("care_tasks")

    if changed_fields:
        profile.last_synced_at = timezone.now()
        profile.save(update_fields=[*changed_fields, "last_synced_at", "updated_at"])

    reminder_ids = [
        record.id
        for record in user.reminder_records.all().only("id", "title", "body")
        if _is_stale_ai_reminder_text(f"{record.title}\n{record.body}")
    ]
    if reminder_ids:
        deleted, _ = user.reminder_records.filter(id__in=reminder_ids).delete()
        removed["reminder_records"] = deleted

    care_task_ids = [
        record.id
        for record in user.care_task_records.all().only("id", "title", "detail")
        if _is_stale_ai_care_task_text(f"{record.title}\n{record.detail}")
    ]
    if care_task_ids:
        deleted, _ = user.care_task_records.filter(id__in=care_task_ids).delete()
        removed["care_task_records"] = deleted

    return removed


def _artifact_blob(value: dict) -> str:
    parts: list[str] = []
    for key in (
        "title",
        "body",
        "detail",
        "note",
        "description",
        "timeLabel",
        "problemName",
    ):
        text = str(value.get(key) or "").strip()
        if text:
            parts.append(text)
    return "\n".join(parts)


def _is_stale_ai_report_text(value: str) -> bool:
    clean = value.strip()
    lower = clean.lower()
    if not clean:
        return False
    if _looks_like_deferred_ai_artifact(lower):
        return True
    has_real_link = (
        "pdf:" in lower
        or "html:" in lower
        or "http://" in lower
        or "https://" in lower
    )
    return "report" in lower and not has_real_link


def _is_stale_ai_reminder_text(value: str) -> bool:
    lower = value.strip().lower()
    if not lower:
        return False
    if _looks_like_deferred_ai_artifact(lower):
        return True
    return any(
        phrase in lower
        for phrase in (
            "daily flicko routine call in preferred free time",
            "medicine reminder based on user medicine timing",
            "meal photo check after lunch",
        )
    )


def _is_stale_ai_care_task_text(value: str) -> bool:
    lower = value.strip().lower()
    if not lower:
        return False
    if _looks_like_deferred_ai_artifact(lower):
        return True
    return (
        "upload meal photo" in lower
        and ("let flicko score eat" in lower or "ai will score eat" in lower)
    )


def _looks_like_deferred_ai_artifact(lower_text: str) -> bool:
    return any(
        phrase in lower_text
        for phrase in (
            "can be",
            "could be",
            "later",
            "after more details",
            "not ready",
            "if you want",
            "do not",
            "don't",
            "without",
            "not enough",
        )
    )


def _primary_problem_from_profile(profile: UserProfile) -> str:
    selected = profile.selected_problems
    if isinstance(selected, list) and selected:
        first = str(selected[0]).strip()
        if first:
            return first
    return "General health"


def _write_profile_memory(user: User, data: dict) -> None:
    profile, _ = UserProfile.objects.get_or_create(user=user)
    problem_name = _primary_problem_from_profile(profile)

    if data.get("intake_summary"):
        HealthMemoryEntry.objects.create(
            user=user,
            problem_name=problem_name,
            source=HealthMemoryEntry.Source.PROFILE,
            category=HealthMemoryEntry.Category.INTAKE_SUMMARY,
            title="Latest structured intake summary",
            content=str(data["intake_summary"])[:12000],
            data={"intake_completed": bool(data.get("intake_completed", False))},
        )

    if data.get("dashboard_values") or data.get("dashboard_notes"):
        HealthMemoryEntry.objects.create(
            user=user,
            problem_name=problem_name,
            source=HealthMemoryEntry.Source.PROFILE,
            category=HealthMemoryEntry.Category.DASHBOARD_UPDATE,
            title="Dashboard profile sync",
            content="Dashboard values or notes updated from app profile sync.",
            data={
                "dashboard_values": data.get("dashboard_values", {}),
                "dashboard_notes": data.get("dashboard_notes", []),
            },
        )

    if data.get("reminders"):
        HealthMemoryEntry.objects.create(
            user=user,
            problem_name=problem_name,
            source=HealthMemoryEntry.Source.PROFILE,
            category=HealthMemoryEntry.Category.REMINDER,
            title="Reminder profile sync",
            content="Reminder list updated from app profile sync.",
            data={"reminders": data.get("reminders", [])},
        )

    rich_keys = (
        "saved_reminders",
        "care_tasks",
        "meal_analyses",
        "health_logs",
        "safety_events",
        "call_memories",
    )
    if any(data.get(key) for key in rich_keys):
        HealthMemoryEntry.objects.create(
            user=user,
            problem_name=problem_name,
            source=HealthMemoryEntry.Source.PROFILE,
            category=HealthMemoryEntry.Category.PROFILE_FACT,
            title="Full app data background sync",
            content=str(
                data.get("latest_call_memory")
                or "Local Flicko app data synced to Django after login or profile update."
            )[:12000],
            data={key: data.get(key, []) for key in rich_keys},
        )
