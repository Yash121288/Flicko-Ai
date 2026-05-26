from __future__ import annotations

from django.contrib.auth.models import User
from rest_framework import serializers

from .report_links import report_file_url, report_open_url
from .models import (
    FoodRule,
    HealthCorpusChunk,
    HealthIntakeReport,
    HealthMemoryEntry,
    HealthProtocol,
    HealthSourceDocument,
    IntakeFlow,
    MemorySchema,
    OutcomeMetric,
    ProtocolEvidence,
    ReminderScript,
    ReportBlock,
    SafetyRule,
    UserCareTaskRecord,
    UserChatMessageRecord,
    UserHealthLogRecord,
    UserMealAnalysisRecord,
    UserProfile,
    UserReminderRecord,
    UserSafetyEventRecord,
)


PROFILE_TEXT_FIELDS = (
    "middle_name",
    "gender",
    "height_cm",
    "height_feet",
    "height_inches",
    "weight_kg",
    "weight_lb",
    "goal_weight_kg",
    "goal_weight_lb",
    "timezone",
    "language",
    "food_preference",
    "medications",
    "allergies",
    "diagnosis",
    "surgery_history",
    "family_history",
    "pregnancy_cycle",
    "emergency_contact_name",
    "emergency_contact_phone",
    "intake_summary",
    "latest_chat_summary",
)

PROFILE_JSON_LIST_FIELDS = (
    "selected_problems",
    "dashboard_notes",
    "reminders",
    "reports",
)
PROFILE_JSON_OBJECT_LIST_FIELDS = (
    "saved_reminders",
    "care_tasks",
    "meal_analyses",
    "health_logs",
    "safety_events",
    "chat_history",
)
PROFILE_JSON_DICT_FIELDS = ("dashboard_values",)


class RegisterStartSerializer(serializers.Serializer):
    name = serializers.CharField(max_length=150)
    email = serializers.EmailField()
    mobile = serializers.CharField(max_length=24)
    password = serializers.CharField(min_length=6, max_length=128, write_only=True)


class RegisterVerifySerializer(serializers.Serializer):
    email = serializers.EmailField()
    otp = serializers.CharField(min_length=4, max_length=8)


class LoginSerializer(serializers.Serializer):
    email = serializers.EmailField()
    password = serializers.CharField(max_length=128, write_only=True)


class GoogleLoginSerializer(serializers.Serializer):
    id_token = serializers.CharField(max_length=12000, write_only=True)
    email = serializers.EmailField(required=False, allow_blank=True)
    name = serializers.CharField(max_length=150, required=False, allow_blank=True)
    photo_url = serializers.URLField(max_length=700, required=False, allow_blank=True)


class ForgotStartSerializer(serializers.Serializer):
    email = serializers.EmailField()


class PasswordResetSerializer(serializers.Serializer):
    email = serializers.EmailField()
    otp = serializers.CharField(min_length=4, max_length=8)
    new_password = serializers.CharField(min_length=6, max_length=128, write_only=True)


class ProfilePatchSerializer(serializers.Serializer):
    name = serializers.CharField(max_length=150, required=False, allow_blank=True)
    mobile = serializers.CharField(max_length=24, required=False, allow_blank=True)
    middle_name = serializers.CharField(max_length=80, required=False, allow_blank=True)
    age = serializers.IntegerField(required=False, allow_null=True, min_value=0, max_value=130)
    gender = serializers.CharField(max_length=40, required=False, allow_blank=True)
    height_cm = serializers.CharField(max_length=24, required=False, allow_blank=True)
    height_feet = serializers.CharField(max_length=24, required=False, allow_blank=True)
    height_inches = serializers.CharField(max_length=24, required=False, allow_blank=True)
    weight_kg = serializers.CharField(max_length=24, required=False, allow_blank=True)
    weight_lb = serializers.CharField(max_length=24, required=False, allow_blank=True)
    goal_weight_kg = serializers.CharField(max_length=24, required=False, allow_blank=True)
    goal_weight_lb = serializers.CharField(max_length=24, required=False, allow_blank=True)
    timezone = serializers.CharField(max_length=80, required=False, allow_blank=True)
    language = serializers.CharField(max_length=80, required=False, allow_blank=True)
    food_preference = serializers.CharField(max_length=120, required=False, allow_blank=True)
    medications = serializers.CharField(max_length=4000, required=False, allow_blank=True)
    allergies = serializers.CharField(max_length=4000, required=False, allow_blank=True)
    diagnosis = serializers.CharField(max_length=4000, required=False, allow_blank=True)
    surgery_history = serializers.CharField(max_length=4000, required=False, allow_blank=True)
    family_history = serializers.CharField(max_length=4000, required=False, allow_blank=True)
    pregnancy_cycle = serializers.CharField(max_length=4000, required=False, allow_blank=True)
    emergency_contact_name = serializers.CharField(max_length=120, required=False, allow_blank=True)
    emergency_contact_phone = serializers.CharField(max_length=32, required=False, allow_blank=True)
    selected_problems = serializers.ListField(
        child=serializers.CharField(max_length=180),
        required=False,
        max_length=40,
    )
    safety_consent_accepted = serializers.BooleanField(required=False)
    intake_summary = serializers.CharField(max_length=12000, required=False, allow_blank=True)
    intake_completed = serializers.BooleanField(required=False)
    dashboard_values = serializers.DictField(required=False)
    dashboard_notes = serializers.ListField(
        child=serializers.CharField(max_length=1200),
        required=False,
        max_length=80,
    )
    reminders = serializers.ListField(
        child=serializers.CharField(max_length=1200),
        required=False,
        max_length=80,
    )
    reports = serializers.ListField(
        child=serializers.CharField(max_length=2000),
        required=False,
        max_length=80,
    )
    saved_reminders = serializers.ListField(
        child=serializers.DictField(),
        required=False,
        max_length=200,
    )
    care_tasks = serializers.ListField(
        child=serializers.DictField(),
        required=False,
        max_length=200,
    )
    meal_analyses = serializers.ListField(
        child=serializers.DictField(),
        required=False,
        max_length=200,
    )
    health_logs = serializers.ListField(
        child=serializers.DictField(),
        required=False,
        max_length=300,
    )
    safety_events = serializers.ListField(
        child=serializers.DictField(),
        required=False,
        max_length=120,
    )
    chat_history = serializers.ListField(
        child=serializers.DictField(),
        required=False,
        max_length=160,
    )
    latest_chat_summary = serializers.CharField(max_length=12000, required=False, allow_blank=True)
    call_memories = serializers.ListField(
        child=serializers.DictField(),
        required=False,
        max_length=80,
    )
    latest_call_memory = serializers.CharField(max_length=12000, required=False, allow_blank=True)


class UserProfileSerializer(serializers.ModelSerializer):
    class Meta:
        model = UserProfile
        fields = (
            "mobile",
            "middle_name",
            "age",
            "gender",
            "height_cm",
            "height_feet",
            "height_inches",
            "weight_kg",
            "weight_lb",
            "goal_weight_kg",
            "goal_weight_lb",
            "timezone",
            "language",
            "food_preference",
            "medications",
            "allergies",
            "diagnosis",
            "surgery_history",
            "family_history",
            "pregnancy_cycle",
            "emergency_contact_name",
            "emergency_contact_phone",
            "selected_problems",
            "safety_consent_accepted",
            "intake_summary",
            "intake_completed",
            "dashboard_values",
            "dashboard_notes",
            "reminders",
            "reports",
            "saved_reminders",
            "care_tasks",
            "meal_analyses",
            "health_logs",
            "safety_events",
            "chat_history",
            "latest_chat_summary",
            "last_synced_at",
            "created_at",
            "updated_at",
        )
        read_only_fields = ("created_at", "updated_at", "last_synced_at")


class UserHealthLogRecordSerializer(serializers.ModelSerializer):
    class Meta:
        model = UserHealthLogRecord
        fields = (
            "id",
            "external_id",
            "problem_name",
            "log_type",
            "title",
            "value",
            "unit",
            "note",
            "recorded_at",
            "payload",
            "updated_at",
        )


class UserMealAnalysisRecordSerializer(serializers.ModelSerializer):
    class Meta:
        model = UserMealAnalysisRecord
        fields = (
            "id",
            "external_id",
            "problem_name",
            "meal_name",
            "score",
            "decision",
            "calorie_range",
            "risk_flags",
            "analyzed_at",
            "payload",
            "updated_at",
        )


class UserReminderRecordSerializer(serializers.ModelSerializer):
    class Meta:
        model = UserReminderRecord
        fields = (
            "id",
            "external_id",
            "problem_name",
            "title",
            "body",
            "hour",
            "minute",
            "enabled",
            "payload",
            "updated_at",
        )


class UserCareTaskRecordSerializer(serializers.ModelSerializer):
    class Meta:
        model = UserCareTaskRecord
        fields = (
            "id",
            "external_id",
            "problem_name",
            "task_type",
            "title",
            "detail",
            "time_label",
            "enabled",
            "last_completed_at",
            "payload",
            "updated_at",
        )


class UserSafetyEventRecordSerializer(serializers.ModelSerializer):
    class Meta:
        model = UserSafetyEventRecord
        fields = (
            "id",
            "external_id",
            "problem_name",
            "source",
            "severity",
            "rule_id",
            "title",
            "matched_text",
            "action",
            "occurred_at",
            "payload",
            "updated_at",
        )


class UserChatMessageRecordSerializer(serializers.ModelSerializer):
    class Meta:
        model = UserChatMessageRecord
        fields = (
            "id",
            "external_id",
            "problem_name",
            "role",
            "text",
            "is_error",
            "sent_at",
            "payload",
            "updated_at",
        )


class HealthAppDataSyncSerializer(serializers.Serializer):
    health_logs = serializers.ListField(
        child=serializers.DictField(),
        required=False,
        max_length=500,
    )
    meal_analyses = serializers.ListField(
        child=serializers.DictField(),
        required=False,
        max_length=300,
    )
    saved_reminders = serializers.ListField(
        child=serializers.DictField(),
        required=False,
        max_length=300,
    )
    care_tasks = serializers.ListField(
        child=serializers.DictField(),
        required=False,
        max_length=300,
    )
    safety_events = serializers.ListField(
        child=serializers.DictField(),
        required=False,
        max_length=200,
    )
    chat_history = serializers.ListField(
        child=serializers.DictField(),
        required=False,
        max_length=300,
    )


class HealthIntakeReportCreateSerializer(serializers.Serializer):
    title = serializers.CharField(max_length=160, required=False, allow_blank=True)
    problem_name = serializers.CharField(max_length=120, required=False, allow_blank=True)
    intake_summary = serializers.CharField(required=False, allow_blank=True)
    dashboard_values = serializers.DictField(required=False)
    reminders = serializers.ListField(
        child=serializers.CharField(max_length=1200),
        required=False,
    )
    transcript = serializers.ListField(
        child=serializers.DictField(),
        required=False,
    )
    source = serializers.CharField(max_length=40, required=False, allow_blank=True)
    source_payload = serializers.DictField(required=False)
    raw_transcript_text = serializers.CharField(required=False, allow_blank=True)
    analyze_conversation = serializers.BooleanField(required=False, default=True)


class HealthIntakeReportSerializer(serializers.ModelSerializer):
    pdf_url = serializers.SerializerMethodField()
    html_url = serializers.SerializerMethodField()
    pdf_open_url = serializers.SerializerMethodField()
    html_open_url = serializers.SerializerMethodField()

    class Meta:
        model = HealthIntakeReport
        fields = (
            "id",
            "title",
            "problem_name",
            "intake_summary",
            "dashboard_values",
            "reminders",
            "pdf_url",
            "html_url",
            "pdf_open_url",
            "html_open_url",
            "created_at",
        )

    def get_pdf_url(self, obj: HealthIntakeReport) -> str:
        if not obj.pdf_file:
            return ""
        request = self.context.get("request")
        return report_file_url(request, obj.id, "pdf")

    def get_html_url(self, obj: HealthIntakeReport) -> str:
        if not obj.html_file:
            return ""
        request = self.context.get("request")
        return report_file_url(request, obj.id, "html")

    def get_pdf_open_url(self, obj: HealthIntakeReport) -> str:
        request = self.context.get("request")
        return report_open_url(request, obj, "pdf")

    def get_html_open_url(self, obj: HealthIntakeReport) -> str:
        request = self.context.get("request")
        return report_open_url(request, obj, "html")


MEMORY_SOURCE_ALIASES = {
    "profile": HealthMemoryEntry.Source.PROFILE,
    "profile_sync": HealthMemoryEntry.Source.PROFILE,
    "chat": HealthMemoryEntry.Source.CHAT,
    "ai_chat": HealthMemoryEntry.Source.CHAT,
    "call": HealthMemoryEntry.Source.CALL,
    "ai_call": HealthMemoryEntry.Source.CALL,
    "voice_call": HealthMemoryEntry.Source.CALL,
    "report": HealthMemoryEntry.Source.REPORT,
    "pdf_report": HealthMemoryEntry.Source.REPORT,
    "meal": HealthMemoryEntry.Source.MEAL,
    "meal_photo": HealthMemoryEntry.Source.MEAL,
    "meal_analysis": HealthMemoryEntry.Source.MEAL,
    "reminder": HealthMemoryEntry.Source.REMINDER,
    "notification": HealthMemoryEntry.Source.REMINDER,
    "manual": HealthMemoryEntry.Source.MANUAL,
    "local": HealthMemoryEntry.Source.MANUAL,
    "local_log": HealthMemoryEntry.Source.MANUAL,
    "health_log": HealthMemoryEntry.Source.MANUAL,
    "safety_engine": HealthMemoryEntry.Source.MANUAL,
}

MEMORY_CATEGORY_ALIASES = {
    "profile_fact": HealthMemoryEntry.Category.PROFILE_FACT,
    "profile": HealthMemoryEntry.Category.PROFILE_FACT,
    "health_log": HealthMemoryEntry.Category.PROFILE_FACT,
    "log": HealthMemoryEntry.Category.PROFILE_FACT,
    "bloodpressure": HealthMemoryEntry.Category.PROFILE_FACT,
    "blood_pressure": HealthMemoryEntry.Category.PROFILE_FACT,
    "bp": HealthMemoryEntry.Category.PROFILE_FACT,
    "glucose": HealthMemoryEntry.Category.PROFILE_FACT,
    "sugar": HealthMemoryEntry.Category.PROFILE_FACT,
    "weight": HealthMemoryEntry.Category.PROFILE_FACT,
    "water": HealthMemoryEntry.Category.PROFILE_FACT,
    "steps": HealthMemoryEntry.Category.PROFILE_FACT,
    "activity": HealthMemoryEntry.Category.PROFILE_FACT,
    "intake_summary": HealthMemoryEntry.Category.INTAKE_SUMMARY,
    "intake": HealthMemoryEntry.Category.INTAKE_SUMMARY,
    "dashboard_update": HealthMemoryEntry.Category.DASHBOARD_UPDATE,
    "dashboard": HealthMemoryEntry.Category.DASHBOARD_UPDATE,
    "reminder": HealthMemoryEntry.Category.REMINDER,
    "notification": HealthMemoryEntry.Category.REMINDER,
    "report": HealthMemoryEntry.Category.REPORT,
    "pdf_report": HealthMemoryEntry.Category.REPORT,
    "safety": HealthMemoryEntry.Category.SAFETY,
    "safety_event": HealthMemoryEntry.Category.SAFETY,
    "red_flag": HealthMemoryEntry.Category.SAFETY,
    "meal": HealthMemoryEntry.Category.MEAL,
    "meal_photo": HealthMemoryEntry.Category.MEAL,
    "meal_analysis": HealthMemoryEntry.Category.MEAL,
    "food": HealthMemoryEntry.Category.MEAL,
    "mood": HealthMemoryEntry.Category.MOOD,
    "stress": HealthMemoryEntry.Category.MOOD,
    "sleep": HealthMemoryEntry.Category.SLEEP,
    "medicine": HealthMemoryEntry.Category.MEDICATION,
    "medication": HealthMemoryEntry.Category.MEDICATION,
    "symptom": HealthMemoryEntry.Category.SYMPTOM,
    "symptoms": HealthMemoryEntry.Category.SYMPTOM,
    "note": HealthMemoryEntry.Category.NOTE,
    "custom": HealthMemoryEntry.Category.NOTE,
}


class HealthMemoryEntryCreateSerializer(serializers.Serializer):
    problem_name = serializers.CharField(max_length=120, required=False, allow_blank=True)
    source = serializers.CharField(max_length=40, required=False, allow_blank=True)
    category = serializers.CharField(max_length=40, required=False, allow_blank=True)
    title = serializers.CharField(max_length=180)
    content = serializers.CharField(max_length=120000, required=False, allow_blank=True)
    data = serializers.DictField(required=False)

    def validate_source(self, value: str) -> str:
        key = _normalise_memory_key(value)
        if not key:
            return HealthMemoryEntry.Source.MANUAL
        return MEMORY_SOURCE_ALIASES.get(key, HealthMemoryEntry.Source.MANUAL)

    def validate_category(self, value: str) -> str:
        key = _normalise_memory_key(value)
        if not key:
            return HealthMemoryEntry.Category.NOTE
        return MEMORY_CATEGORY_ALIASES.get(key, HealthMemoryEntry.Category.NOTE)


class HealthMemoryEntrySerializer(serializers.ModelSerializer):
    class Meta:
        model = HealthMemoryEntry
        fields = (
            "id",
            "problem_name",
            "source",
            "category",
            "title",
            "content",
            "data",
            "occurred_at",
            "created_at",
        )


class HealthSourceDocumentSerializer(serializers.ModelSerializer):
    class Meta:
        model = HealthSourceDocument
        fields = (
            "id",
            "title",
            "publisher",
            "url",
            "source_type",
            "language",
            "country_scope",
            "license_note",
            "fetched_at",
            "last_reviewed_at",
        )


class HealthCorpusChunkSerializer(serializers.ModelSerializer):
    source = HealthSourceDocumentSerializer(read_only=True)

    class Meta:
        model = HealthCorpusChunk
        fields = (
            "id",
            "chunk_uid",
            "title",
            "condition",
            "section_type",
            "text",
            "token_count",
            "embedding_key",
            "source",
            "metadata",
        )


class ProtocolEvidenceSerializer(serializers.ModelSerializer):
    source = HealthSourceDocumentSerializer(read_only=True)
    chunk_uid = serializers.CharField(source="chunk.chunk_uid", read_only=True, default="")

    class Meta:
        model = ProtocolEvidence
        fields = (
            "id",
            "source",
            "chunk_uid",
            "evidence_level",
            "note",
            "quote",
            "created_at",
        )


class HealthProtocolListSerializer(serializers.ModelSerializer):
    class Meta:
        model = HealthProtocol
        fields = (
            "id",
            "protocol_id",
            "title",
            "condition",
            "protocol_type",
            "summary",
            "risk_level",
            "review_status",
            "version",
            "tags",
            "updated_at",
        )


class HealthProtocolDetailSerializer(serializers.ModelSerializer):
    evidence = ProtocolEvidenceSerializer(many=True, read_only=True)
    source_chunks = HealthCorpusChunkSerializer(many=True, read_only=True)

    class Meta:
        model = HealthProtocol
        fields = (
            "id",
            "protocol_id",
            "title",
            "condition",
            "protocol_type",
            "summary",
            "content",
            "rules",
            "tags",
            "risk_level",
            "review_status",
            "version",
            "source_chunks",
            "evidence",
            "created_at",
            "updated_at",
        )


class FoodRuleSerializer(serializers.ModelSerializer):
    protocol_id = serializers.CharField(source="protocol.protocol_id", read_only=True, default="")

    class Meta:
        model = FoodRule
        fields = (
            "id",
            "condition",
            "food_name",
            "cuisine_context",
            "rule_type",
            "guidance",
            "reason",
            "alternatives",
            "tags",
            "safety_notes",
            "protocol_id",
            "review_status",
        )


class SafetyRuleSerializer(serializers.ModelSerializer):
    protocol_id = serializers.CharField(source="protocol.protocol_id", read_only=True, default="")

    class Meta:
        model = SafetyRule
        fields = (
            "id",
            "condition",
            "symptom_pattern",
            "severity",
            "action",
            "escalation_text",
            "contraindications",
            "protocol_id",
            "review_status",
        )


class IntakeFlowSerializer(serializers.ModelSerializer):
    protocol_id = serializers.CharField(source="protocol.protocol_id", read_only=True, default="")

    class Meta:
        model = IntakeFlow
        fields = (
            "id",
            "flow_id",
            "condition",
            "title",
            "questions",
            "priority",
            "active",
            "review_status",
            "protocol_id",
        )


class ReminderScriptSerializer(serializers.ModelSerializer):
    protocol_id = serializers.CharField(source="protocol.protocol_id", read_only=True, default="")

    class Meta:
        model = ReminderScript
        fields = (
            "id",
            "condition",
            "trigger_type",
            "title",
            "script",
            "schedule_hint",
            "channel",
            "active",
            "protocol_id",
        )


class ReportBlockSerializer(serializers.ModelSerializer):
    protocol_id = serializers.CharField(source="protocol.protocol_id", read_only=True, default="")

    class Meta:
        model = ReportBlock
        fields = (
            "id",
            "condition",
            "block_type",
            "title",
            "markdown_template",
            "required_metrics",
            "active",
            "review_status",
            "protocol_id",
        )


class OutcomeMetricSerializer(serializers.ModelSerializer):
    class Meta:
        model = OutcomeMetric
        fields = (
            "id",
            "metric_key",
            "condition",
            "label",
            "unit",
            "normal_range",
            "high_risk_threshold",
            "dashboard_mapping",
        )


class MemorySchemaSerializer(serializers.ModelSerializer):
    class Meta:
        model = MemorySchema
        fields = (
            "id",
            "schema_key",
            "condition",
            "category",
            "json_schema",
            "extraction_prompt",
            "review_status",
        )


def user_payload(user: User) -> dict[str, object]:
    profile = getattr(user, "profile", None)
    return {
        "id": user.id,
        "name": user.get_full_name() or user.first_name or user.email,
        "email": user.email,
        "mobile": profile.mobile if profile else "",
        "is_verified": user.is_active,
        "profile": UserProfileSerializer(profile).data if profile else {},
    }


def _normalise_memory_key(value: object) -> str:
    return str(value or "").strip().lower().replace("-", "_")
