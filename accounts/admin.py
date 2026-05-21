from django.contrib import admin

from .models import (
    ConditionProtocolMap,
    EmailOTP,
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


@admin.register(UserProfile)
class UserProfileAdmin(admin.ModelAdmin):
    list_display = (
        "user",
        "mobile",
        "gender",
        "language",
        "safety_consent_accepted",
        "intake_completed",
        "updated_at",
    )
    list_filter = (
        "gender",
        "language",
        "safety_consent_accepted",
        "intake_completed",
        "updated_at",
    )
    search_fields = (
        "user__email",
        "user__first_name",
        "user__last_name",
        "mobile",
        "diagnosis",
        "medications",
        "allergies",
    )
    readonly_fields = ("created_at", "updated_at", "last_synced_at")


@admin.register(EmailOTP)
class EmailOTPAdmin(admin.ModelAdmin):
    list_display = ("email", "purpose", "attempts", "consumed_at", "expires_at", "created_at")
    list_filter = ("purpose", "consumed_at")
    search_fields = ("email",)
    readonly_fields = ("code_hash", "created_at")


@admin.register(HealthIntakeReport)
class HealthIntakeReportAdmin(admin.ModelAdmin):
    list_display = ("user", "title", "problem_name", "created_at")
    list_filter = ("problem_name", "created_at")
    search_fields = ("user__email", "title", "problem_name", "intake_summary")
    readonly_fields = ("created_at", "pdf_file")


@admin.register(HealthMemoryEntry)
class HealthMemoryEntryAdmin(admin.ModelAdmin):
    list_display = ("user", "category", "source", "problem_name", "title", "occurred_at")
    list_filter = ("category", "source", "problem_name", "occurred_at")
    search_fields = ("user__email", "problem_name", "title", "content")
    readonly_fields = ("created_at",)


@admin.register(UserHealthLogRecord)
class UserHealthLogRecordAdmin(admin.ModelAdmin):
    list_display = ("user", "log_type", "title", "value", "unit", "problem_name", "recorded_at")
    list_filter = ("log_type", "problem_name", "recorded_at")
    search_fields = ("user__email", "title", "value", "note", "problem_name")
    readonly_fields = ("created_at", "updated_at")


@admin.register(UserMealAnalysisRecord)
class UserMealAnalysisRecordAdmin(admin.ModelAdmin):
    list_display = ("user", "meal_name", "score", "decision", "problem_name", "analyzed_at")
    list_filter = ("problem_name", "score", "analyzed_at")
    search_fields = ("user__email", "meal_name", "decision", "problem_name")
    readonly_fields = ("created_at", "updated_at")


@admin.register(UserReminderRecord)
class UserReminderRecordAdmin(admin.ModelAdmin):
    list_display = ("user", "title", "problem_name", "hour", "minute", "enabled")
    list_filter = ("enabled", "problem_name")
    search_fields = ("user__email", "title", "body", "problem_name")
    readonly_fields = ("created_at", "updated_at")


@admin.register(UserCareTaskRecord)
class UserCareTaskRecordAdmin(admin.ModelAdmin):
    list_display = ("user", "task_type", "title", "problem_name", "time_label", "enabled")
    list_filter = ("task_type", "enabled", "problem_name")
    search_fields = ("user__email", "title", "detail", "problem_name")
    readonly_fields = ("created_at", "updated_at")


@admin.register(UserSafetyEventRecord)
class UserSafetyEventRecordAdmin(admin.ModelAdmin):
    list_display = ("user", "severity", "title", "problem_name", "source", "occurred_at")
    list_filter = ("severity", "problem_name", "source", "occurred_at")
    search_fields = ("user__email", "title", "matched_text", "action", "problem_name")
    readonly_fields = ("created_at", "updated_at")


@admin.register(UserChatMessageRecord)
class UserChatMessageRecordAdmin(admin.ModelAdmin):
    list_display = ("user", "role", "problem_name", "is_error", "sent_at")
    list_filter = ("role", "is_error", "problem_name", "sent_at")
    search_fields = ("user__email", "text", "problem_name")
    readonly_fields = ("created_at", "updated_at")


@admin.register(HealthSourceDocument)
class HealthSourceDocumentAdmin(admin.ModelAdmin):
    list_display = ("publisher", "title", "source_type", "language", "is_public", "updated_at")
    list_filter = ("publisher", "source_type", "language", "is_public")
    search_fields = ("title", "publisher", "url", "license_note")
    readonly_fields = ("created_at", "updated_at")


@admin.register(HealthCorpusChunk)
class HealthCorpusChunkAdmin(admin.ModelAdmin):
    list_display = ("chunk_uid", "condition", "section_type", "source", "token_count")
    list_filter = ("condition", "section_type", "source__publisher")
    search_fields = ("chunk_uid", "title", "text", "condition")


class ProtocolEvidenceInline(admin.TabularInline):
    model = ProtocolEvidence
    extra = 0
    autocomplete_fields = ("source", "chunk")


@admin.register(HealthProtocol)
class HealthProtocolAdmin(admin.ModelAdmin):
    list_display = (
        "protocol_id",
        "condition",
        "protocol_type",
        "risk_level",
        "review_status",
        "version",
    )
    list_filter = ("condition", "protocol_type", "risk_level", "review_status")
    search_fields = ("protocol_id", "title", "summary", "content", "condition")
    filter_horizontal = ("source_chunks",)
    inlines = (ProtocolEvidenceInline,)
    readonly_fields = ("created_at", "updated_at")


@admin.register(ProtocolEvidence)
class ProtocolEvidenceAdmin(admin.ModelAdmin):
    list_display = ("protocol", "source", "evidence_level", "created_at")
    list_filter = ("source__publisher", "evidence_level")
    search_fields = ("protocol__protocol_id", "source__title", "note", "quote")
    autocomplete_fields = ("protocol", "source", "chunk")


@admin.register(ConditionProtocolMap)
class ConditionProtocolMapAdmin(admin.ModelAdmin):
    list_display = ("condition", "protocol", "priority", "created_at")
    list_filter = ("condition",)
    search_fields = ("condition", "protocol__protocol_id", "applicability")
    autocomplete_fields = ("protocol",)


@admin.register(FoodRule)
class FoodRuleAdmin(admin.ModelAdmin):
    list_display = ("condition", "food_name", "rule_type", "review_status", "updated_at")
    list_filter = ("condition", "rule_type", "review_status")
    search_fields = ("condition", "food_name", "guidance", "reason")
    autocomplete_fields = ("protocol",)


@admin.register(SafetyRule)
class SafetyRuleAdmin(admin.ModelAdmin):
    list_display = ("condition", "symptom_pattern", "severity", "review_status", "updated_at")
    list_filter = ("condition", "severity", "review_status")
    search_fields = ("condition", "symptom_pattern", "action", "escalation_text")
    autocomplete_fields = ("protocol",)


@admin.register(IntakeFlow)
class IntakeFlowAdmin(admin.ModelAdmin):
    list_display = ("flow_id", "condition", "priority", "active", "review_status")
    list_filter = ("condition", "active", "review_status")
    search_fields = ("flow_id", "condition", "title")
    autocomplete_fields = ("protocol",)


@admin.register(ReminderScript)
class ReminderScriptAdmin(admin.ModelAdmin):
    list_display = ("condition", "trigger_type", "title", "channel", "active")
    list_filter = ("condition", "trigger_type", "channel", "active")
    search_fields = ("condition", "title", "script")
    autocomplete_fields = ("protocol",)


@admin.register(ReportBlock)
class ReportBlockAdmin(admin.ModelAdmin):
    list_display = ("condition", "block_type", "title", "active", "review_status")
    list_filter = ("condition", "block_type", "active", "review_status")
    search_fields = ("condition", "title", "markdown_template")
    autocomplete_fields = ("protocol",)


@admin.register(OutcomeMetric)
class OutcomeMetricAdmin(admin.ModelAdmin):
    list_display = ("metric_key", "condition", "label", "unit")
    list_filter = ("condition", "unit")
    search_fields = ("metric_key", "condition", "label")


@admin.register(MemorySchema)
class MemorySchemaAdmin(admin.ModelAdmin):
    list_display = ("schema_key", "condition", "category", "review_status")
    list_filter = ("condition", "category", "review_status")
    search_fields = ("schema_key", "condition", "category", "extraction_prompt")
