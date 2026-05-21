from __future__ import annotations

from django.conf import settings
from django.contrib.auth.models import User
from django.db import models
from django.utils import timezone


class UserProfile(models.Model):
    user = models.OneToOneField(User, on_delete=models.CASCADE, related_name="profile")
    mobile = models.CharField(max_length=24, blank=True)
    middle_name = models.CharField(max_length=80, blank=True)
    age = models.PositiveSmallIntegerField(null=True, blank=True)
    gender = models.CharField(max_length=40, blank=True)
    height_cm = models.CharField(max_length=24, blank=True)
    height_feet = models.CharField(max_length=24, blank=True)
    height_inches = models.CharField(max_length=24, blank=True)
    weight_kg = models.CharField(max_length=24, blank=True)
    weight_lb = models.CharField(max_length=24, blank=True)
    goal_weight_kg = models.CharField(max_length=24, blank=True)
    goal_weight_lb = models.CharField(max_length=24, blank=True)
    timezone = models.CharField(max_length=80, blank=True)
    language = models.CharField(max_length=80, blank=True)
    food_preference = models.CharField(max_length=120, blank=True)
    medications = models.TextField(blank=True)
    allergies = models.TextField(blank=True)
    diagnosis = models.TextField(blank=True)
    surgery_history = models.TextField(blank=True)
    family_history = models.TextField(blank=True)
    pregnancy_cycle = models.TextField(blank=True)
    emergency_contact_name = models.CharField(max_length=120, blank=True)
    emergency_contact_phone = models.CharField(max_length=32, blank=True)
    selected_problems = models.JSONField(default=list, blank=True)
    safety_consent_accepted = models.BooleanField(default=False)
    intake_summary = models.TextField(blank=True)
    intake_completed = models.BooleanField(default=False)
    dashboard_values = models.JSONField(default=dict, blank=True)
    dashboard_notes = models.JSONField(default=list, blank=True)
    reminders = models.JSONField(default=list, blank=True)
    reports = models.JSONField(default=list, blank=True)
    saved_reminders = models.JSONField(default=list, blank=True)
    care_tasks = models.JSONField(default=list, blank=True)
    meal_analyses = models.JSONField(default=list, blank=True)
    health_logs = models.JSONField(default=list, blank=True)
    safety_events = models.JSONField(default=list, blank=True)
    chat_history = models.JSONField(default=list, blank=True)
    latest_chat_summary = models.TextField(blank=True)
    last_synced_at = models.DateTimeField(null=True, blank=True)

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self) -> str:
        return f"{self.user.email} profile"


class HealthMemoryEntry(models.Model):
    class Source(models.TextChoices):
        PROFILE = "profile", "Profile"
        CHAT = "chat", "Chat"
        CALL = "call", "Call"
        REPORT = "report", "Report"
        MEAL = "meal", "Meal"
        REMINDER = "reminder", "Reminder"
        MANUAL = "manual", "Manual"

    class Category(models.TextChoices):
        PROFILE_FACT = "profile_fact", "Profile fact"
        INTAKE_SUMMARY = "intake_summary", "Intake summary"
        DASHBOARD_UPDATE = "dashboard_update", "Dashboard update"
        REMINDER = "reminder", "Reminder"
        REPORT = "report", "Report"
        SAFETY = "safety", "Safety"
        MEAL = "meal", "Meal"
        MOOD = "mood", "Mood"
        SLEEP = "sleep", "Sleep"
        MEDICATION = "medication", "Medication"
        SYMPTOM = "symptom", "Symptom"
        NOTE = "note", "Note"

    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name="health_memory")
    problem_name = models.CharField(max_length=120, blank=True, db_index=True)
    source = models.CharField(max_length=24, choices=Source.choices, default=Source.MANUAL)
    category = models.CharField(max_length=32, choices=Category.choices, default=Category.NOTE)
    title = models.CharField(max_length=180)
    content = models.TextField(blank=True)
    data = models.JSONField(default=dict, blank=True)
    occurred_at = models.DateTimeField(default=timezone.now, db_index=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-occurred_at", "-created_at"]
        indexes = [
            models.Index(fields=["user", "category", "occurred_at"]),
            models.Index(fields=["user", "source", "occurred_at"]),
        ]

    def __str__(self) -> str:
        return f"{self.user.email} {self.category}: {self.title}"


class UserHealthLogRecord(models.Model):
    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name="health_log_records")
    external_id = models.CharField(max_length=140)
    problem_name = models.CharField(max_length=120, blank=True, db_index=True)
    log_type = models.CharField(max_length=60, db_index=True)
    title = models.CharField(max_length=180, blank=True)
    value = models.CharField(max_length=120, blank=True)
    unit = models.CharField(max_length=60, blank=True)
    note = models.TextField(blank=True)
    recorded_at = models.DateTimeField(default=timezone.now, db_index=True)
    payload = models.JSONField(default=dict, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["-recorded_at", "-created_at"]
        unique_together = ("user", "external_id")
        indexes = [
            models.Index(fields=["user", "log_type", "recorded_at"]),
            models.Index(fields=["user", "problem_name", "recorded_at"]),
        ]

    def __str__(self) -> str:
        return f"{self.user.email} {self.log_type}: {self.value} {self.unit}".strip()


class UserMealAnalysisRecord(models.Model):
    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name="meal_analysis_records")
    external_id = models.CharField(max_length=140)
    problem_name = models.CharField(max_length=120, blank=True, db_index=True)
    meal_name = models.CharField(max_length=180, blank=True)
    score = models.PositiveSmallIntegerField(default=0, db_index=True)
    decision = models.CharField(max_length=120, blank=True)
    calorie_range = models.CharField(max_length=120, blank=True)
    risk_flags = models.JSONField(default=list, blank=True)
    analyzed_at = models.DateTimeField(default=timezone.now, db_index=True)
    payload = models.JSONField(default=dict, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["-analyzed_at", "-created_at"]
        unique_together = ("user", "external_id")
        indexes = [
            models.Index(fields=["user", "problem_name", "analyzed_at"]),
            models.Index(fields=["user", "score", "analyzed_at"]),
        ]

    def __str__(self) -> str:
        return f"{self.user.email} {self.meal_name}: {self.score}"


class UserReminderRecord(models.Model):
    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name="reminder_records")
    external_id = models.CharField(max_length=140)
    problem_name = models.CharField(max_length=120, blank=True, db_index=True)
    title = models.CharField(max_length=180)
    body = models.TextField(blank=True)
    hour = models.PositiveSmallIntegerField(null=True, blank=True)
    minute = models.PositiveSmallIntegerField(null=True, blank=True)
    enabled = models.BooleanField(default=True, db_index=True)
    payload = models.JSONField(default=dict, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["hour", "minute", "title"]
        unique_together = ("user", "external_id")
        indexes = [
            models.Index(fields=["user", "enabled"]),
            models.Index(fields=["user", "problem_name"]),
        ]

    def __str__(self) -> str:
        return f"{self.user.email} reminder: {self.title}"


class UserCareTaskRecord(models.Model):
    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name="care_task_records")
    external_id = models.CharField(max_length=140)
    problem_name = models.CharField(max_length=120, blank=True, db_index=True)
    task_type = models.CharField(max_length=60, db_index=True)
    title = models.CharField(max_length=180)
    detail = models.TextField(blank=True)
    time_label = models.CharField(max_length=80, blank=True)
    enabled = models.BooleanField(default=True, db_index=True)
    last_completed_at = models.DateTimeField(null=True, blank=True, db_index=True)
    payload = models.JSONField(default=dict, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["time_label", "title"]
        unique_together = ("user", "external_id")
        indexes = [
            models.Index(fields=["user", "task_type", "enabled"]),
            models.Index(fields=["user", "problem_name", "enabled"]),
        ]

    def __str__(self) -> str:
        return f"{self.user.email} task: {self.title}"


class UserSafetyEventRecord(models.Model):
    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name="safety_event_records")
    external_id = models.CharField(max_length=140)
    problem_name = models.CharField(max_length=120, blank=True, db_index=True)
    source = models.CharField(max_length=80, blank=True)
    severity = models.CharField(max_length=40, db_index=True)
    rule_id = models.CharField(max_length=120, blank=True)
    title = models.CharField(max_length=180, blank=True)
    matched_text = models.TextField(blank=True)
    action = models.TextField(blank=True)
    occurred_at = models.DateTimeField(default=timezone.now, db_index=True)
    payload = models.JSONField(default=dict, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["-occurred_at", "-created_at"]
        unique_together = ("user", "external_id")
        indexes = [
            models.Index(fields=["user", "severity", "occurred_at"]),
            models.Index(fields=["user", "problem_name", "occurred_at"]),
        ]

    def __str__(self) -> str:
        return f"{self.user.email} safety: {self.severity} {self.title}"


class UserChatMessageRecord(models.Model):
    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name="chat_message_records")
    external_id = models.CharField(max_length=140)
    problem_name = models.CharField(max_length=120, blank=True, db_index=True)
    role = models.CharField(max_length=24, db_index=True)
    text = models.TextField()
    is_error = models.BooleanField(default=False)
    sent_at = models.DateTimeField(default=timezone.now, db_index=True)
    payload = models.JSONField(default=dict, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["sent_at", "created_at"]
        unique_together = ("user", "external_id")
        indexes = [
            models.Index(fields=["user", "problem_name", "sent_at"]),
            models.Index(fields=["user", "role", "sent_at"]),
        ]

    def __str__(self) -> str:
        return f"{self.user.email} {self.role}: {self.text[:40]}"


class HealthSourceDocument(models.Model):
    class SourceType(models.TextChoices):
        GUIDELINE = "guideline", "Guideline"
        PDF = "pdf", "PDF"
        WEB_PAGE = "web_page", "Web page"
        JOURNAL = "journal", "Journal"
        DATASET = "dataset", "Dataset"
        INTERNAL = "internal", "Internal"
        OTHER = "other", "Other"

    title = models.CharField(max_length=260)
    publisher = models.CharField(max_length=160)
    url = models.URLField(max_length=700, unique=True)
    source_type = models.CharField(
        max_length=32,
        choices=SourceType.choices,
        default=SourceType.WEB_PAGE,
    )
    language = models.CharField(max_length=40, default="en")
    country_scope = models.CharField(max_length=80, blank=True)
    license_note = models.CharField(max_length=260, blank=True)
    file_path = models.CharField(max_length=500, blank=True)
    checksum_sha256 = models.CharField(max_length=64, blank=True)
    fetched_at = models.DateTimeField(null=True, blank=True)
    last_reviewed_at = models.DateTimeField(null=True, blank=True)
    is_public = models.BooleanField(default=True)
    metadata = models.JSONField(default=dict, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["publisher", "title"]
        indexes = [
            models.Index(fields=["publisher", "source_type"]),
            models.Index(fields=["language", "country_scope"]),
        ]

    def __str__(self) -> str:
        return f"{self.publisher}: {self.title}"


class HealthCorpusChunk(models.Model):
    class SectionType(models.TextChoices):
        CONDITION = "condition", "Condition"
        SYMPTOM = "symptom", "Symptom"
        DIET = "diet", "Diet"
        EXERCISE = "exercise", "Exercise"
        SAFETY = "safety", "Safety"
        FOLLOW_UP = "follow_up", "Follow up"
        INTAKE = "intake", "Intake"
        FOOD = "food", "Food"
        MEDICATION = "medication", "Medication"
        REPORT = "report", "Report"
        GENERAL = "general", "General"

    source = models.ForeignKey(
        HealthSourceDocument,
        on_delete=models.CASCADE,
        related_name="chunks",
    )
    chunk_uid = models.CharField(max_length=160, unique=True)
    title = models.CharField(max_length=220)
    condition = models.CharField(max_length=120, blank=True, db_index=True)
    section_type = models.CharField(
        max_length=32,
        choices=SectionType.choices,
        default=SectionType.GENERAL,
        db_index=True,
    )
    text = models.TextField()
    token_count = models.PositiveIntegerField(default=0)
    embedding_key = models.CharField(max_length=220, blank=True)
    metadata = models.JSONField(default=dict, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["condition", "section_type", "chunk_uid"]
        indexes = [
            models.Index(fields=["condition", "section_type"]),
            models.Index(fields=["source", "section_type"]),
        ]

    def __str__(self) -> str:
        return self.chunk_uid


class HealthProtocol(models.Model):
    class ProtocolType(models.TextChoices):
        CONDITION_CARE = "condition_care", "Condition care"
        DIET_NUTRITION = "diet_nutrition", "Diet and nutrition"
        INDIAN_FOOD_SUBSTITUTION = (
            "indian_food_substitution",
            "Indian food substitution",
        )
        EXERCISE_FITNESS = "exercise_fitness", "Exercise and fitness"
        SYMPTOM_RISK_TRIAGE = "symptom_risk_triage", "Symptom and risk triage"
        INTAKE_QUESTION_FLOW = "intake_question_flow", "Intake question flow"
        REMINDER_CHECKIN = "reminder_checkin", "Reminder and check-in"
        REPORT_BLOCK = "report_block", "Report block"
        EMOTIONAL_COACHING = "emotional_coaching", "Emotional coaching"
        FAQ_SAFETY_BOUNDARY = "faq_safety_boundary", "FAQ, safety, boundary"

    class ReviewStatus(models.TextChoices):
        UNREVIEWED = "unreviewed", "Unreviewed"
        EXPERT_REVIEWED = "expert_reviewed", "Expert reviewed"
        DEPRECATED = "deprecated", "Deprecated"
        REPLACED = "replaced", "Replaced"

    class RiskLevel(models.TextChoices):
        LOW = "low", "Low"
        MODERATE = "moderate", "Moderate"
        HIGH = "high", "High"
        EMERGENCY = "emergency", "Emergency"

    protocol_id = models.CharField(max_length=80, unique=True)
    title = models.CharField(max_length=220)
    condition = models.CharField(max_length=120, db_index=True)
    protocol_type = models.CharField(
        max_length=40,
        choices=ProtocolType.choices,
        db_index=True,
    )
    summary = models.TextField(blank=True)
    content = models.TextField()
    rules = models.JSONField(default=list, blank=True)
    tags = models.JSONField(default=list, blank=True)
    risk_level = models.CharField(
        max_length=20,
        choices=RiskLevel.choices,
        default=RiskLevel.LOW,
        db_index=True,
    )
    review_status = models.CharField(
        max_length=24,
        choices=ReviewStatus.choices,
        default=ReviewStatus.UNREVIEWED,
        db_index=True,
    )
    version = models.PositiveIntegerField(default=1)
    source_chunks = models.ManyToManyField(
        HealthCorpusChunk,
        related_name="protocols",
        blank=True,
    )
    replaced_by = models.ForeignKey(
        "self",
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        related_name="replaces",
    )
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["condition", "protocol_type", "protocol_id"]
        indexes = [
            models.Index(fields=["condition", "protocol_type", "review_status"]),
            models.Index(fields=["risk_level", "review_status"]),
        ]

    def __str__(self) -> str:
        return f"{self.protocol_id}: {self.title}"


class ProtocolEvidence(models.Model):
    protocol = models.ForeignKey(
        HealthProtocol,
        on_delete=models.CASCADE,
        related_name="evidence",
    )
    source = models.ForeignKey(
        HealthSourceDocument,
        on_delete=models.PROTECT,
        related_name="protocol_evidence",
    )
    chunk = models.ForeignKey(
        HealthCorpusChunk,
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        related_name="protocol_evidence",
    )
    evidence_level = models.CharField(max_length=80, blank=True)
    note = models.TextField(blank=True)
    quote = models.TextField(blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["protocol", "source"]

    def __str__(self) -> str:
        return f"{self.protocol.protocol_id} evidence"


class ConditionProtocolMap(models.Model):
    condition = models.CharField(max_length=120, db_index=True)
    protocol = models.ForeignKey(
        HealthProtocol,
        on_delete=models.CASCADE,
        related_name="condition_maps",
    )
    priority = models.PositiveSmallIntegerField(default=100)
    applicability = models.TextField(blank=True)
    contraindications = models.JSONField(default=list, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["condition", "priority"]
        unique_together = ("condition", "protocol")

    def __str__(self) -> str:
        return f"{self.condition} -> {self.protocol.protocol_id}"


class FoodRule(models.Model):
    class RuleType(models.TextChoices):
        RECOMMEND = "recommend", "Recommend"
        LIMIT = "limit", "Limit"
        AVOID = "avoid", "Avoid"
        SUBSTITUTE = "substitute", "Substitute"
        PORTION = "portion", "Portion"
        TIMING = "timing", "Timing"

    condition = models.CharField(max_length=120, db_index=True)
    food_name = models.CharField(max_length=140, db_index=True)
    cuisine_context = models.CharField(max_length=120, blank=True)
    rule_type = models.CharField(max_length=24, choices=RuleType.choices)
    guidance = models.TextField()
    reason = models.TextField(blank=True)
    alternatives = models.JSONField(default=list, blank=True)
    tags = models.JSONField(default=list, blank=True)
    safety_notes = models.TextField(blank=True)
    protocol = models.ForeignKey(
        HealthProtocol,
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        related_name="food_rules",
    )
    review_status = models.CharField(
        max_length=24,
        choices=HealthProtocol.ReviewStatus.choices,
        default=HealthProtocol.ReviewStatus.UNREVIEWED,
        db_index=True,
    )
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["condition", "food_name", "rule_type"]
        indexes = [
            models.Index(fields=["condition", "rule_type"]),
            models.Index(fields=["food_name", "rule_type"]),
        ]

    def __str__(self) -> str:
        return f"{self.condition} {self.food_name}: {self.rule_type}"


class SafetyRule(models.Model):
    class Severity(models.TextChoices):
        SELF_CARE = "self_care", "Self-care"
        SOON = "soon", "Book appointment"
        URGENT = "urgent", "Urgent care"
        EMERGENCY = "emergency", "Emergency"

    condition = models.CharField(max_length=120, db_index=True)
    symptom_pattern = models.CharField(max_length=220)
    severity = models.CharField(
        max_length=24,
        choices=Severity.choices,
        db_index=True,
    )
    action = models.TextField()
    escalation_text = models.TextField(blank=True)
    contraindications = models.JSONField(default=list, blank=True)
    protocol = models.ForeignKey(
        HealthProtocol,
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        related_name="safety_rules",
    )
    review_status = models.CharField(
        max_length=24,
        choices=HealthProtocol.ReviewStatus.choices,
        default=HealthProtocol.ReviewStatus.UNREVIEWED,
        db_index=True,
    )
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["condition", "-severity", "symptom_pattern"]
        indexes = [
            models.Index(fields=["condition", "severity"]),
            models.Index(fields=["review_status", "severity"]),
        ]

    def __str__(self) -> str:
        return f"{self.condition}: {self.symptom_pattern}"


class IntakeFlow(models.Model):
    flow_id = models.CharField(max_length=80, unique=True)
    condition = models.CharField(max_length=120, db_index=True)
    title = models.CharField(max_length=180)
    questions = models.JSONField(default=list)
    priority = models.PositiveSmallIntegerField(default=100)
    active = models.BooleanField(default=True)
    review_status = models.CharField(
        max_length=24,
        choices=HealthProtocol.ReviewStatus.choices,
        default=HealthProtocol.ReviewStatus.UNREVIEWED,
    )
    protocol = models.ForeignKey(
        HealthProtocol,
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        related_name="intake_flows",
    )

    class Meta:
        ordering = ["condition", "priority", "flow_id"]

    def __str__(self) -> str:
        return self.flow_id


class ReminderScript(models.Model):
    class Channel(models.TextChoices):
        CHAT = "chat", "Chat"
        CALL = "call", "Call"
        PUSH = "push", "Push"
        REPORT = "report", "Report"

    condition = models.CharField(max_length=120, db_index=True)
    trigger_type = models.CharField(max_length=80, db_index=True)
    title = models.CharField(max_length=160)
    script = models.TextField()
    schedule_hint = models.CharField(max_length=120, blank=True)
    channel = models.CharField(
        max_length=20,
        choices=Channel.choices,
        default=Channel.PUSH,
    )
    active = models.BooleanField(default=True)
    protocol = models.ForeignKey(
        HealthProtocol,
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        related_name="reminder_scripts",
    )

    class Meta:
        ordering = ["condition", "trigger_type", "title"]

    def __str__(self) -> str:
        return f"{self.condition}: {self.title}"


class ReportBlock(models.Model):
    condition = models.CharField(max_length=120, db_index=True)
    block_type = models.CharField(max_length=80, db_index=True)
    title = models.CharField(max_length=180)
    markdown_template = models.TextField()
    required_metrics = models.JSONField(default=list, blank=True)
    active = models.BooleanField(default=True)
    review_status = models.CharField(
        max_length=24,
        choices=HealthProtocol.ReviewStatus.choices,
        default=HealthProtocol.ReviewStatus.UNREVIEWED,
    )
    protocol = models.ForeignKey(
        HealthProtocol,
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        related_name="report_blocks",
    )

    class Meta:
        ordering = ["condition", "block_type", "title"]

    def __str__(self) -> str:
        return f"{self.condition}: {self.title}"


class OutcomeMetric(models.Model):
    metric_key = models.CharField(max_length=100, unique=True)
    condition = models.CharField(max_length=120, db_index=True)
    label = models.CharField(max_length=140)
    unit = models.CharField(max_length=40, blank=True)
    normal_range = models.CharField(max_length=120, blank=True)
    high_risk_threshold = models.CharField(max_length=120, blank=True)
    dashboard_mapping = models.JSONField(default=dict, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["condition", "metric_key"]

    def __str__(self) -> str:
        return self.metric_key


class MemorySchema(models.Model):
    schema_key = models.CharField(max_length=100, unique=True)
    condition = models.CharField(max_length=120, db_index=True)
    category = models.CharField(max_length=80, db_index=True)
    json_schema = models.JSONField(default=dict)
    extraction_prompt = models.TextField(blank=True)
    review_status = models.CharField(
        max_length=24,
        choices=HealthProtocol.ReviewStatus.choices,
        default=HealthProtocol.ReviewStatus.UNREVIEWED,
    )
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["condition", "category", "schema_key"]

    def __str__(self) -> str:
        return self.schema_key


class HealthIntakeReport(models.Model):
    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name="health_reports")
    title = models.CharField(max_length=160)
    problem_name = models.CharField(max_length=120, blank=True)
    intake_summary = models.TextField(blank=True)
    dashboard_values = models.JSONField(default=dict, blank=True)
    reminders = models.JSONField(default=list, blank=True)
    transcript = models.JSONField(default=list, blank=True)
    pdf_file = models.FileField(upload_to="health_reports/", blank=True)
    html_file = models.FileField(upload_to="health_reports/html/", blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-created_at"]

    def __str__(self) -> str:
        return f"{self.user.email} {self.title}"


class EmailOTP(models.Model):
    class Purpose(models.TextChoices):
        REGISTER = "register", "Register"
        PASSWORD_RESET = "password_reset", "Password reset"

    email = models.EmailField(db_index=True)
    purpose = models.CharField(max_length=32, choices=Purpose.choices, db_index=True)
    code_hash = models.CharField(max_length=256)
    attempts = models.PositiveSmallIntegerField(default=0)
    consumed_at = models.DateTimeField(null=True, blank=True)
    expires_at = models.DateTimeField(db_index=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        indexes = [
            models.Index(fields=["email", "purpose", "created_at"]),
        ]

    @property
    def is_expired(self) -> bool:
        return timezone.now() >= self.expires_at

    @property
    def is_consumed(self) -> bool:
        return self.consumed_at is not None

    @property
    def attempts_exhausted(self) -> bool:
        return self.attempts >= settings.OTP_MAX_ATTEMPTS

    def mark_consumed(self) -> None:
        self.consumed_at = timezone.now()
        self.save(update_fields=["consumed_at"])

    def __str__(self) -> str:
        return f"{self.email} {self.purpose} OTP"
