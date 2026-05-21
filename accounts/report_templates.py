from __future__ import annotations

from dataclasses import dataclass


def _normalize_name(value: str) -> str:
    return " ".join(value.strip().lower().replace("/", " ").split())


@dataclass(frozen=True)
class ReportTemplate:
    problem_name: str
    title: str
    subtitle: str
    asset_name: str
    primary_hex: str
    light_hex: str
    score_label: str
    metric_labels: tuple[str, ...]
    focus_areas: tuple[str, ...]
    report_sections: tuple[str, ...]
    doctor_questions: tuple[str, ...]


@dataclass(frozen=True)
class ReportBoxSpec:
    box_id: str
    title: str
    kind: str
    keywords: tuple[str, ...] = ()
    metric_labels: tuple[str, ...] = ()
    tone: str = "normal"


@dataclass(frozen=True)
class ReportPageSpec:
    page_id: str
    eyebrow: str
    title: str
    chip: str
    box_ids: tuple[str, ...]


DEFAULT_PRIMARY = "#149447"
DEFAULT_LIGHT = "#EAF7EE"


SUPPORTED_REPORT_PROBLEMS = (
    "Weight management",
    "Diabetes Type 1",
    "Diabetes Type 2",
    "Blood pressure",
    "Heart health",
    "PCOS/PCOD",
    "Thyroid",
    "Pregnancy",
    "Preconception",
    "Postpartum",
    "Digestive health",
    "Sleep health",
    "Stress and mood",
    "Fitness",
    "Skin and hair",
    "General wellness",
    "Women's wellness",
    "Senior care",
    "Sexual health",
    "Autoimmune support",
    "Acidity and bloating",
    "Cholesterol",
    "Habit reset",
    "Other problem",
)


_TEMPLATES = {
    "Weight management": ReportTemplate(
        problem_name="Weight management",
        title="Weight Management Progress Report",
        subtitle="Calories, hunger pattern, BMI trend, activity, and sustainable habits.",
        asset_name="weight_management.png",
        primary_hex="#149447",
        light_hex="#EAF7EE",
        score_label="Weight score",
        metric_labels=("Weight", "Goal weight", "BMI", "Calories", "Steps"),
        focus_areas=("Meal timing", "Protein and fiber", "Cravings", "Activity", "Sleep"),
        report_sections=("Weight trend", "Food pattern", "Habit blockers", "7-day target"),
        doctor_questions=("Is weight change medically safe?", "Should thyroid, sugar, or lipid labs be checked?"),
    ),
    "Diabetes Type 1": ReportTemplate(
        problem_name="Diabetes Type 1",
        title="Type 1 Diabetes Care Report",
        subtitle="Glucose pattern, meal timing, insulin safety notes, activity, and hypoglycemia risk.",
        asset_name="diabetes_type_1.png",
        primary_hex="#128E4A",
        light_hex="#E8F7EC",
        score_label="Glucose stability score",
        metric_labels=("Blood sugar", "Meal timing", "Hypo episodes", "Activity", "Sleep"),
        focus_areas=("Hypoglycemia safety", "Carbohydrate pattern", "Insulin discussion", "Sick-day awareness"),
        report_sections=("Glucose pattern", "Meal log", "Risk flags", "Clinician questions"),
        doctor_questions=("Any insulin dose changes needed?", "Do frequent lows or highs need urgent review?"),
    ),
    "Diabetes Type 2": ReportTemplate(
        problem_name="Diabetes Type 2",
        title="Type 2 Diabetes Care Report",
        subtitle="Blood sugar, meals, medicine adherence, walking routine, and risk flags.",
        asset_name="diabetes_type_2.png",
        primary_hex="#149447",
        light_hex="#EAF7EE",
        score_label="Diabetes score",
        metric_labels=("Blood sugar", "Meal plan", "Medicine", "Steps", "Weight"),
        focus_areas=("Sugar spikes", "High-protein meals", "Medicine reminders", "Post-meal walking"),
        report_sections=("Sugar trend", "Food score", "Medicine routine", "Doctor-ready summary"),
        doctor_questions=("Should HbA1c or fasting sugar be checked?", "Are medicines and meal timing aligned?"),
    ),
    "Blood pressure": ReportTemplate(
        problem_name="Blood pressure",
        title="Blood Pressure Control Report",
        subtitle="BP readings, salt pattern, stress, sleep, medicine timing, and warning signs.",
        asset_name="blood_pressure.jpg",
        primary_hex="#188B5A",
        light_hex="#E9F6EF",
        score_label="BP control score",
        metric_labels=("Systolic", "Diastolic", "Pulse", "Salt", "Medicine"),
        focus_areas=("Reading technique", "Salt reduction", "Stress spikes", "Medicine adherence"),
        report_sections=("BP trend", "Lifestyle triggers", "Medication routine", "Urgent flags"),
        doctor_questions=("Are readings consistently high?", "Should medication timing be reviewed?"),
    ),
    "Heart health": ReportTemplate(
        problem_name="Heart health",
        title="Heart Health Risk Report",
        subtitle="Chest symptoms, cholesterol habits, activity tolerance, BP, and safety triage.",
        asset_name="heart_health.jpg",
        primary_hex="#0F8B55",
        light_hex="#E7F6EE",
        score_label="Heart score",
        metric_labels=("Activity", "BP", "Cholesterol", "Symptoms", "Sleep"),
        focus_areas=("Chest-pain red flags", "Walking capacity", "Fat and salt pattern", "Stress load"),
        report_sections=("Symptom timeline", "Risk factors", "Lifestyle plan", "Doctor checklist"),
        doctor_questions=("Do symptoms need cardiac evaluation?", "Which labs or ECG should be considered?"),
    ),
    "PCOS/PCOD": ReportTemplate(
        problem_name="PCOS/PCOD",
        title="PCOS/PCOD Balance Report",
        subtitle="Cycle pattern, acne/hair, weight, cravings, insulin resistance, and mood.",
        asset_name="pcos_pcod.png",
        primary_hex="#148C6A",
        light_hex="#E9F7F2",
        score_label="Hormone balance score",
        metric_labels=("Cycle", "Cravings", "Weight", "Mood", "Activity"),
        focus_areas=("Cycle regularity", "Insulin-friendly meals", "Skin and hair", "Stress and sleep"),
        report_sections=("Cycle notes", "Food routine", "Symptom tracker", "Clinician questions"),
        doctor_questions=("Should thyroid, prolactin, sugar, or hormone labs be checked?", "Is medication needed?"),
    ),
    "Thyroid": ReportTemplate(
        problem_name="Thyroid",
        title="Thyroid Routine Report",
        subtitle="Medication timing, fatigue, weight, bowel pattern, mood, and lab discussion.",
        asset_name="thyroid.png",
        primary_hex="#1B8F72",
        light_hex="#E8F7F3",
        score_label="Thyroid routine score",
        metric_labels=("TSH notes", "Medicine", "Energy", "Weight", "Sleep"),
        focus_areas=("Medicine timing", "Energy pattern", "Weight change", "Lab follow-up"),
        report_sections=("Symptom pattern", "Medicine routine", "Lifestyle support", "Lab questions"),
        doctor_questions=("When should TSH be repeated?", "Is medication timing or dose review needed?"),
    ),
    "Pregnancy": ReportTemplate(
        problem_name="Pregnancy",
        title="Pregnancy Wellness Report",
        subtitle="Trimester notes, nutrition, sleep, warning symptoms, supplements, and care reminders.",
        asset_name="pregnancy.jpg",
        primary_hex="#159A70",
        light_hex="#E8F8F1",
        score_label="Pregnancy wellness score",
        metric_labels=("Trimester", "Meals", "Hydration", "Sleep", "Symptoms"),
        focus_areas=("Red-flag symptoms", "Prenatal nutrition", "Medication safety", "Appointment reminders"),
        report_sections=("Pregnancy notes", "Nutrition checklist", "Warning signs", "Doctor discussion"),
        doctor_questions=("Are any symptoms urgent?", "Are supplements and medicines pregnancy-safe?"),
    ),
    "Preconception": ReportTemplate(
        problem_name="Preconception",
        title="Preconception Readiness Report",
        subtitle="Cycle, folate routine, lifestyle, labs, partner factors, and fertility preparation.",
        asset_name="preconception.png",
        primary_hex="#168D73",
        light_hex="#E8F6F3",
        score_label="Readiness score",
        metric_labels=("Cycle", "Folate", "Sleep", "Stress", "Activity"),
        focus_areas=("Cycle tracking", "Nutrition readiness", "Folate reminder", "Lab planning"),
        report_sections=("Cycle pattern", "Lifestyle readiness", "Risk review", "Clinician checklist"),
        doctor_questions=("Which preconception labs are needed?", "Are medicines safe before pregnancy?"),
    ),
    "Postpartum": ReportTemplate(
        problem_name="Postpartum",
        title="Postpartum Recovery Report",
        subtitle="Recovery, feeding, sleep, mood, bleeding, pain, and support system.",
        asset_name="postpartum.png",
        primary_hex="#15976A",
        light_hex="#E8F8F1",
        score_label="Recovery score",
        metric_labels=("Sleep", "Mood", "Pain", "Bleeding", "Support"),
        focus_areas=("Mood safety", "Recovery symptoms", "Feeding routine", "Rest blocks"),
        report_sections=("Recovery timeline", "Mood check", "Support plan", "Doctor flags"),
        doctor_questions=("Do bleeding, fever, pain, or mood symptoms need urgent care?", "Is recovery on track?"),
    ),
    "Digestive health": ReportTemplate(
        problem_name="Digestive health",
        title="Digestive Health Report",
        subtitle="Bloating, bowel pattern, trigger foods, hydration, stress, and red flags.",
        asset_name="digestive_health.jpg",
        primary_hex="#208B56",
        light_hex="#EDF7EF",
        score_label="Gut comfort score",
        metric_labels=("Bloating", "Bowel", "Triggers", "Water", "Stress"),
        focus_areas=("Trigger meals", "Fiber pattern", "Hydration", "Red flags"),
        report_sections=("Symptom timeline", "Food triggers", "Bowel tracker", "Care plan"),
        doctor_questions=("Are there alarm symptoms?", "Should tests or GI review be considered?"),
    ),
    "Sleep health": ReportTemplate(
        problem_name="Sleep health",
        title="Sleep Health Report",
        subtitle="Sleep duration, wakeups, snoring, screens, caffeine, stress, and recovery score.",
        asset_name="sleep_health.png",
        primary_hex="#167E64",
        light_hex="#E8F5F1",
        score_label="Sleep readiness score",
        metric_labels=("Sleep hours", "Wakeups", "Caffeine", "Screens", "Mood"),
        focus_areas=("Bedtime rhythm", "Caffeine cutoff", "Screen routine", "Sleep apnea flags"),
        report_sections=("Sleep pattern", "Trigger habits", "Evening routine", "Doctor flags"),
        doctor_questions=("Could snoring or daytime sleepiness suggest sleep apnea?", "Are medicines affecting sleep?"),
    ),
    "Stress and mood": ReportTemplate(
        problem_name="Stress and mood",
        title="Stress and Mood Support Report",
        subtitle="Mood pattern, triggers, sleep, appetite, energy, coping plan, and safety flags.",
        asset_name="stress_mood.png",
        primary_hex="#147F6A",
        light_hex="#E7F5F2",
        score_label="Calm score",
        metric_labels=("Stress", "Mood", "Sleep", "Energy", "Support"),
        focus_areas=("Stress triggers", "Mood pattern", "Coping tools", "Safety support"),
        report_sections=("Mood timeline", "Trigger map", "Daily reset plan", "Escalation signs"),
        doctor_questions=("Is professional mental health support needed?", "Are there safety concerns?"),
    ),
    "Fitness": ReportTemplate(
        problem_name="Fitness",
        title="Fitness Plan Report",
        subtitle="Strength, cardio, mobility, recovery, injury risk, and weekly progression.",
        asset_name="fitness.png",
        primary_hex="#168B54",
        light_hex="#EAF7EE",
        score_label="Fitness score",
        metric_labels=("Steps", "Workout", "Mobility", "Recovery", "Pain"),
        focus_areas=("Workout level", "Progression", "Recovery", "Injury prevention"),
        report_sections=("Fitness baseline", "Weekly split", "Recovery rules", "Safety notes"),
        doctor_questions=("Is exercise safe with current symptoms?", "Any injury needing review?"),
    ),
    "Skin and hair": ReportTemplate(
        problem_name="Skin and hair",
        title="Skin and Hair Wellness Report",
        subtitle="Skin changes, hair fall, sleep, stress, diet, hormones, and care routine.",
        asset_name="skin_hair.png",
        primary_hex="#168D63",
        light_hex="#EAF7F0",
        score_label="Skin/hair score",
        metric_labels=("Skin", "Hair fall", "Stress", "Sleep", "Diet"),
        focus_areas=("Routine consistency", "Nutrition", "Hormonal clues", "Irritant triggers"),
        report_sections=("Symptom pattern", "Care routine", "Nutrition support", "Doctor questions"),
        doctor_questions=("Should thyroid, iron, vitamin D, or hormone labs be checked?", "Is dermatology review needed?"),
    ),
    "General wellness": ReportTemplate(
        problem_name="General wellness",
        title="General Wellness Report",
        subtitle="Energy, meals, movement, sleep, stress, prevention, and habit plan.",
        asset_name="general_wellness.jpg",
        primary_hex="#149447",
        light_hex="#EAF7EE",
        score_label="Wellness score",
        metric_labels=("Energy", "Meals", "Steps", "Sleep", "Stress"),
        focus_areas=("Daily routine", "Preventive habits", "Meal quality", "Sleep consistency"),
        report_sections=("Wellness baseline", "Habit plan", "Risk flags", "Follow-up goals"),
        doctor_questions=("Which preventive tests are due?", "Any symptoms needing evaluation?"),
    ),
    "Women's wellness": ReportTemplate(
        problem_name="Women's wellness",
        title="Women's Wellness Report",
        subtitle="Cycle, hormones, energy, mood, skin, nutrition, and reproductive health notes.",
        asset_name="womens_wellness.png",
        primary_hex="#158F6C",
        light_hex="#E8F7F2",
        score_label="Cycle wellness score",
        metric_labels=("Cycle", "Mood", "Energy", "Pain", "Sleep"),
        focus_areas=("Cycle symptoms", "Hormonal clues", "Nutrition", "Mood and sleep"),
        report_sections=("Cycle notes", "Symptom pattern", "Care plan", "Clinician questions"),
        doctor_questions=("Are cycle changes abnormal?", "Should hormone or anemia labs be checked?"),
    ),
    "Senior care": ReportTemplate(
        problem_name="Senior care",
        title="Senior Care Summary Report",
        subtitle="Medicines, mobility, falls risk, nutrition, sleep, memory, and caregiver notes.",
        asset_name="senior_care.png",
        primary_hex="#178B5E",
        light_hex="#EAF6EF",
        score_label="Care score",
        metric_labels=("Mobility", "Medicine", "Nutrition", "Sleep", "Safety"),
        focus_areas=("Fall prevention", "Medicine routine", "Hydration and meals", "Caregiver support"),
        report_sections=("Daily care baseline", "Risk flags", "Reminder plan", "Doctor checklist"),
        doctor_questions=("Any fall, confusion, or medicine side effect risk?", "Is geriatric review needed?"),
    ),
    "Sexual health": ReportTemplate(
        problem_name="Sexual health",
        title="Private Sexual Wellness Report",
        subtitle="Confidential symptom timeline, safety checklist, relationship stress, and doctor-ready notes.",
        asset_name="sexual_health.png",
        primary_hex="#147E68",
        light_hex="#E8F5F2",
        score_label="Private health score",
        metric_labels=("Concern", "Timeline", "Pain", "Safety", "Stress"),
        focus_areas=("Main concern", "STI or infection flags", "Pain or bleeding", "Consent and safety", "Stress and confidence"),
        report_sections=("Private concern summary", "Symptom timeline", "Safety checklist", "Doctor questions"),
        doctor_questions=("Is STI testing or clinician exam needed?", "Are pain, bleeding, fever, or pregnancy risk present?"),
    ),
    "Autoimmune support": ReportTemplate(
        problem_name="Autoimmune support",
        title="Autoimmune Flare Support Report",
        subtitle="Flare pattern, fatigue, pain, sleep, stress, medicines, and clinician follow-up.",
        asset_name="autoimmune_support.png",
        primary_hex="#17876B",
        light_hex="#E8F6F3",
        score_label="Flare control score",
        metric_labels=("Pain", "Fatigue", "Sleep", "Stress", "Medicine"),
        focus_areas=("Flare triggers", "Rest pacing", "Medicine adherence", "Inflammation clues"),
        report_sections=("Flare timeline", "Trigger map", "Pacing plan", "Doctor checklist"),
        doctor_questions=("Does this flare need medication review?", "Are labs or specialist follow-up due?"),
    ),
    "Acidity and bloating": ReportTemplate(
        problem_name="Acidity and bloating",
        title="Acidity and Bloating Relief Report",
        subtitle="Meal triggers, reflux timing, bowel pattern, hydration, stress, and warning signs.",
        asset_name="acidity_bloating.png",
        primary_hex="#208B56",
        light_hex="#EDF7EF",
        score_label="Relief score",
        metric_labels=("Acidity", "Bloating", "Triggers", "Dinner time", "Stress"),
        focus_areas=("Late meals", "Spicy/fatty triggers", "Portion size", "Alarm symptoms"),
        report_sections=("Trigger foods", "Symptom timing", "Relief routine", "Doctor flags"),
        doctor_questions=("Are alarm symptoms present?", "Is persistent reflux needing medical review?"),
    ),
    "Cholesterol": ReportTemplate(
        problem_name="Cholesterol",
        title="Cholesterol and Lipid Support Report",
        subtitle="Food pattern, activity, weight, family risk, medicines, and lab follow-up.",
        asset_name="cholesterol.png",
        primary_hex="#128B55",
        light_hex="#E8F7EE",
        score_label="Cholesterol score",
        metric_labels=("LDL notes", "Fiber", "Exercise", "Weight", "Medicine"),
        focus_areas=("Fiber intake", "Saturated fat", "Walking routine", "Family risk"),
        report_sections=("Food risk pattern", "Activity plan", "Lab follow-up", "Doctor checklist"),
        doctor_questions=("When should lipid profile be repeated?", "Is medication discussion needed?"),
    ),
    "Habit reset": ReportTemplate(
        problem_name="Habit reset",
        title="Habit Reset Report",
        subtitle="Trigger loop, routine design, reminders, accountability, and 7-day behavior plan.",
        asset_name="habit_reset.png",
        primary_hex="#168D63",
        light_hex="#EAF7F0",
        score_label="Habit reset score",
        metric_labels=("Trigger", "Routine", "Reward", "Reminder", "Consistency"),
        focus_areas=("Trigger awareness", "Small actions", "Cue design", "Weekly consistency"),
        report_sections=("Habit loop", "Reset plan", "Reminder schedule", "Progress check"),
        doctor_questions=("Could stress, sleep, or medical issues be driving the habit?", "Is support needed?"),
    ),
    "Other problem": ReportTemplate(
        problem_name="Other problem",
        title="Custom Health Intake Report",
        subtitle="Personalized symptom summary, routine context, risk flags, and next-step plan.",
        asset_name="other_problem.png",
        primary_hex="#149447",
        light_hex="#EAF7EE",
        score_label="Custom health score",
        metric_labels=("Concern", "Timeline", "Severity", "Routine", "Follow-up"),
        focus_areas=("Main concern", "Symptom pattern", "Lifestyle context", "Safety triage"),
        report_sections=("Concern summary", "Timeline", "Action plan", "Doctor questions"),
        doctor_questions=("Does this need clinical evaluation?", "Which tests or specialist review may help?"),
    ),
}


_NORMALIZED_TEMPLATES = {
    _normalize_name(name): template for name, template in _TEMPLATES.items()
}


def template_for_problem(problem_name: str) -> ReportTemplate:
    normalized = _normalize_name(problem_name)
    if normalized in _NORMALIZED_TEMPLATES:
        return _NORMALIZED_TEMPLATES[normalized]
    if "diabetes" in normalized:
        return _TEMPLATES["Diabetes Type 2"]
    if "bp" in normalized or "blood pressure" in normalized:
        return _TEMPLATES["Blood pressure"]
    if "sexual" in normalized or "private" in normalized:
        return _TEMPLATES["Sexual health"]
    if "weight" in normalized:
        return _TEMPLATES["Weight management"]
    return _TEMPLATES["Other problem"]


def template_slug(template: ReportTemplate) -> str:
    normalized = template.problem_name.lower().replace("&", "and")
    chars = [char if char.isalnum() else "_" for char in normalized]
    return "_".join("".join(chars).split("_")).strip("_")


def _page(
    page_id: str,
    eyebrow: str,
    title: str,
    chip: str,
    *box_ids: str,
) -> ReportPageSpec:
    return ReportPageSpec(
        page_id=page_id,
        eyebrow=eyebrow,
        title=title,
        chip=chip,
        box_ids=tuple(box_ids),
    )


_BOX_LIBRARY = {
    "chief_concern": ReportBoxSpec(
        box_id="chief_concern",
        title="Chief Concern",
        kind="bullets",
        keywords=("chief concern", "patient snapshot", "concern summary", "private concern summary", "wellness baseline"),
    ),
    "snapshot_strip": ReportBoxSpec(
        box_id="snapshot_strip",
        title="Current Snapshot",
        kind="metrics",
    ),
    "trend_summary": ReportBoxSpec(
        box_id="trend_summary",
        title="Trend and Measurements",
        kind="metrics",
    ),
    "symptom_timeline": ReportBoxSpec(
        box_id="symptom_timeline",
        title="Symptom Timeline",
        kind="timeline",
        keywords=("timeline", "symptom timeline", "recovery timeline", "mood timeline", "flare timeline", "cycle notes"),
    ),
    "safety_review": ReportBoxSpec(
        box_id="safety_review",
        title="Safety Review",
        kind="bullets",
        keywords=("risk", "red flag", "safety", "warning sign", "urgent"),
        tone="warning",
    ),
    "routine_review": ReportBoxSpec(
        box_id="routine_review",
        title="Daily Routine Review",
        kind="bullets",
        keywords=("routine", "meal", "nutrition", "sleep", "hydration", "activity", "food"),
    ),
    "trigger_context": ReportBoxSpec(
        box_id="trigger_context",
        title="Trigger and Lifestyle Context",
        kind="bullets",
        keywords=("trigger", "habit", "food trigger", "stress", "lifestyle"),
    ),
    "meds_adherence": ReportBoxSpec(
        box_id="meds_adherence",
        title="Medicine and Treatment",
        kind="bullets",
        keywords=("medicine", "medication", "dose", "insulin", "tablet", "treatment"),
    ),
    "labs_testing_history": ReportBoxSpec(
        box_id="labs_testing_history",
        title="Labs and Testing",
        kind="bullets",
        keywords=("report", "lab", "test", "scan", "ultrasound", "prescription"),
    ),
    "symptom_cluster": ReportBoxSpec(
        box_id="symptom_cluster",
        title="Symptom Cluster",
        kind="bullets",
        keywords=("symptom", "pattern", "pain", "bleeding", "discharge", "acne", "hair", "fatigue"),
    ),
    "support_context": ReportBoxSpec(
        box_id="support_context",
        title="Support and Recovery Context",
        kind="bullets",
        keywords=("support", "caregiver", "feeding", "recovery", "mood", "rest"),
    ),
    "risk_factors": ReportBoxSpec(
        box_id="risk_factors",
        title="Risk Factors",
        kind="bullets",
        keywords=("risk factor", "family", "cholesterol", "blood pressure", "cardiac", "history"),
    ),
    "exercise_readiness": ReportBoxSpec(
        box_id="exercise_readiness",
        title="Training and Recovery",
        kind="bullets",
        keywords=("fitness", "workout", "cardio", "mobility", "recovery", "injury"),
    ),
    "habit_loop": ReportBoxSpec(
        box_id="habit_loop",
        title="Habit Loop",
        kind="bullets",
        keywords=("habit loop", "trigger", "routine", "reward", "craving"),
    ),
    "exposure_context": ReportBoxSpec(
        box_id="exposure_context",
        title="Exposure and Relationship Context",
        kind="bullets",
        keywords=("exposure", "partner", "relationship", "consent", "contraception", "private concern"),
    ),
    "monitoring_table": ReportBoxSpec(
        box_id="monitoring_table",
        title="Clinical Snapshot Table",
        kind="table",
        keywords=("trend", "measurement", "reading", "snapshot", "baseline"),
    ),
    "symptom_review_table": ReportBoxSpec(
        box_id="symptom_review_table",
        title="Structured Symptom Review",
        kind="table",
        keywords=("symptom", "timeline", "pattern", "severity", "cluster"),
    ),
    "testing_followup_table": ReportBoxSpec(
        box_id="testing_followup_table",
        title="Testing and Follow-up Table",
        kind="table",
        keywords=("lab", "test", "scan", "doctor", "follow-up", "referral"),
    ),
    "medicine_schedule_table": ReportBoxSpec(
        box_id="medicine_schedule_table",
        title="Medicine Timing Table",
        kind="table",
        keywords=("medicine", "medication", "dose", "timing", "insulin", "tablet"),
    ),
    "trigger_response_table": ReportBoxSpec(
        box_id="trigger_response_table",
        title="Trigger and Response Map",
        kind="table",
        keywords=("trigger", "stress", "food", "habit", "response"),
    ),
    "recovery_checklist_table": ReportBoxSpec(
        box_id="recovery_checklist_table",
        title="Recovery Checklist",
        kind="table",
        keywords=("recovery", "rest", "feeding", "pain", "bleeding", "support"),
    ),
    "training_split_table": ReportBoxSpec(
        box_id="training_split_table",
        title="Training Split Table",
        kind="table",
        keywords=("fitness", "workout", "mobility", "recovery", "injury"),
    ),
    "habit_reset_table": ReportBoxSpec(
        box_id="habit_reset_table",
        title="Habit Reset Table",
        kind="table",
        keywords=("habit loop", "trigger", "routine", "reward", "cue"),
    ),
    "meal_plan_table": ReportBoxSpec(
        box_id="meal_plan_table",
        title="Suggested Daily Meal Structure",
        kind="meal_plan",
        keywords=("meal plan", "nutrition", "food pattern", "meal timing", "plate"),
    ),
    "week_plan_table": ReportBoxSpec(
        box_id="week_plan_table",
        title="Day-wise 7-Day Plan",
        kind="week_plan",
        keywords=("next 7", "7-day", "care plan", "weekly plan", "action plan"),
    ),
    "plan_tracker": ReportBoxSpec(
        box_id="plan_tracker",
        title="Next 7 Days",
        kind="timeline",
        keywords=("care plan", "next 7", "7-day", "action plan", "reminder", "tracking"),
    ),
    "referral_next_steps": ReportBoxSpec(
        box_id="referral_next_steps",
        title="Follow-up and Referral",
        kind="bullets",
        keywords=("doctor", "clinician", "follow-up", "next step", "referral"),
    ),
    "doctor_questions": ReportBoxSpec(
        box_id="doctor_questions",
        title="Doctor Discussion",
        kind="doctor",
        keywords=("doctor", "clinician", "question"),
    ),
}


_PAGE_LAYOUTS = {
    "Weight management": (
        _page("page_1", "What matters now", "Weight Trend and Current Risks", "Weight management", "chief_concern", "monitoring_table", "routine_review", "safety_review"),
        _page("page_2", "Drivers and plan", "Food Pattern, Barriers, and Weekly Plan", "7-day focus", "meal_plan_table", "week_plan_table", "trigger_response_table", "testing_followup_table"),
    ),
    "Diabetes Type 1": (
        _page("page_1", "What matters now", "Glucose Pattern and Safety", "Type 1 diabetes", "chief_concern", "monitoring_table", "symptom_review_table", "safety_review"),
        _page("page_2", "Routine and treatment", "Insulin, Meals, and Monitoring", "Daily management", "meal_plan_table", "medicine_schedule_table", "week_plan_table", "testing_followup_table"),
        _page("page_3", "Escalation and review", "Doctor Review and Next Steps", "Clinician follow-up", "referral_next_steps", "doctor_questions"),
    ),
    "Diabetes Type 2": (
        _page("page_1", "What matters now", "Sugar Pattern and Current Risk", "Type 2 diabetes", "chief_concern", "monitoring_table", "risk_factors", "safety_review"),
        _page("page_2", "Routine and treatment", "Meals, Medicines, and Follow-up", "Daily management", "meal_plan_table", "medicine_schedule_table", "week_plan_table", "testing_followup_table"),
        _page("page_3", "Escalation and review", "Doctor Review and Next Steps", "Clinician follow-up", "referral_next_steps", "doctor_questions"),
    ),
    "Blood pressure": (
        _page("page_1", "What matters now", "Current Readings and Warning Signs", "Blood pressure", "chief_concern", "monitoring_table", "medicine_schedule_table", "safety_review"),
        _page("page_2", "Drivers and plan", "Salt, Stress, Sleep, and Follow-up", "Home routine", "meal_plan_table", "trigger_response_table", "week_plan_table", "testing_followup_table"),
    ),
    "Heart health": (
        _page("page_1", "What matters now", "Symptoms and Cardiac Risk", "Heart health", "chief_concern", "symptom_review_table", "risk_factors", "safety_review"),
        _page("page_2", "Review and referral", "Lifestyle Context and Next Steps", "Urgent review", "monitoring_table", "meal_plan_table", "week_plan_table", "testing_followup_table"),
    ),
    "PCOS/PCOD": (
        _page("page_1", "What matters now", "Cycle, Symptoms, and Current Pattern", "PCOS/PCOD", "chief_concern", "symptom_review_table", "monitoring_table", "safety_review"),
        _page("page_2", "Hormones and lifestyle", "Context, Labs, and Plan", "Follow-up plan", "meal_plan_table", "trigger_response_table", "week_plan_table", "testing_followup_table"),
    ),
    "Thyroid": (
        _page("page_1", "What matters now", "Medicine Timing and Symptoms", "Thyroid", "chief_concern", "symptom_review_table", "medicine_schedule_table", "monitoring_table"),
        _page("page_2", "Labs and routine", "Follow-up and Weekly Support", "Routine review", "meal_plan_table", "week_plan_table", "testing_followup_table", "doctor_questions"),
    ),
    "Pregnancy": (
        _page("page_1", "What matters now", "Trimester Status and Red Flags", "Pregnancy", "chief_concern", "symptom_review_table", "monitoring_table", "safety_review"),
        _page("page_2", "Care and support", "Nutrition, Testing, and Follow-up", "Maternal care", "meal_plan_table", "week_plan_table", "recovery_checklist_table", "testing_followup_table"),
        _page("page_3", "Escalation", "Urgent Review and Referral", "Doctor follow-up", "support_context", "doctor_questions", "referral_next_steps"),
    ),
    "Preconception": (
        _page("page_1", "What matters now", "Cycle and Readiness Snapshot", "Preconception", "chief_concern", "monitoring_table", "routine_review", "testing_followup_table"),
        _page("page_2", "Readiness plan", "Lifestyle Context and Next Steps", "Fertility prep", "meal_plan_table", "week_plan_table", "trigger_response_table", "doctor_questions"),
    ),
    "Postpartum": (
        _page("page_1", "What matters now", "Recovery, Mood, and Safety", "Postpartum", "chief_concern", "symptom_review_table", "recovery_checklist_table", "safety_review"),
        _page("page_2", "Recovery plan", "Routine, Follow-up, and Review", "Recovery support", "meal_plan_table", "week_plan_table", "support_context", "testing_followup_table"),
    ),
    "Digestive health": (
        _page("page_1", "What matters now", "Symptoms, Triggers, and Red Flags", "Digestive health", "chief_concern", "symptom_review_table", "trigger_response_table", "safety_review"),
        _page("page_2", "Care plan", "Food Context, Testing, and Follow-up", "Gut support", "meal_plan_table", "monitoring_table", "week_plan_table", "testing_followup_table"),
    ),
    "Sleep health": (
        _page("page_1", "What matters now", "Sleep Pattern and Daytime Impact", "Sleep health", "chief_concern", "monitoring_table", "routine_review", "safety_review"),
        _page("page_2", "Drivers and plan", "Triggers, Next Steps, and Review", "Sleep reset", "trigger_response_table", "week_plan_table", "testing_followup_table", "doctor_questions"),
    ),
    "Stress and mood": (
        _page("page_1", "What matters now", "Mood Pattern and Safety", "Stress and mood", "chief_concern", "symptom_review_table", "support_context", "safety_review"),
        _page("page_2", "Daily reset", "Triggers, Next Steps, and Review", "Support plan", "trigger_response_table", "week_plan_table", "monitoring_table", "doctor_questions"),
    ),
    "Fitness": (
        _page("page_1", "What matters now", "Training Load and Injury Risk", "Fitness", "chief_concern", "monitoring_table", "training_split_table", "safety_review"),
        _page("page_2", "Progression plan", "Recovery, Support, and Review", "Weekly split", "routine_review", "week_plan_table", "testing_followup_table", "doctor_questions"),
    ),
    "Skin and hair": (
        _page("page_1", "What matters now", "Current Symptoms and Pattern", "Skin and hair", "chief_concern", "symptom_review_table", "monitoring_table", "safety_review"),
        _page("page_2", "Routine and review", "Triggers, Labs, and Next Steps", "Care routine", "meal_plan_table", "trigger_response_table", "testing_followup_table", "week_plan_table"),
    ),
    "General wellness": (
        _page("page_1", "What matters now", "Daily Baseline and Follow-up Needs", "General wellness", "chief_concern", "monitoring_table", "routine_review", "safety_review"),
        _page("page_2", "Wellness plan", "Context, Tests, and Next Steps", "Weekly reset", "meal_plan_table", "week_plan_table", "trigger_response_table", "testing_followup_table"),
    ),
    "Women's wellness": (
        _page("page_1", "What matters now", "Cycle, Symptoms, and Safety", "Women's wellness", "chief_concern", "symptom_review_table", "monitoring_table", "safety_review"),
        _page("page_2", "Routine and review", "Labs, Plan, and Clinician Questions", "Hormonal support", "meal_plan_table", "week_plan_table", "testing_followup_table", "doctor_questions"),
    ),
    "Senior care": (
        _page("page_1", "What matters now", "Medicines, Mobility, and Safety", "Senior care", "chief_concern", "monitoring_table", "medicine_schedule_table", "safety_review"),
        _page("page_2", "Care plan", "Daily Routine, Follow-up, and Referral", "Caregiver support", "meal_plan_table", "week_plan_table", "support_context", "testing_followup_table"),
    ),
    "Sexual health": (
        _page("page_1", "What matters now", "Confidential Symptom Review", "Sexual health", "chief_concern", "symptom_review_table", "safety_review", "testing_followup_table"),
        _page("page_2", "Context and symptoms", "Exposure, Treatment, and Plan", "Private follow-up", "exposure_context", "medicine_schedule_table", "week_plan_table", "referral_next_steps"),
        _page("page_3", "Referral and testing", "Clinician Review and Next Steps", "Doctor follow-up", "doctor_questions"),
    ),
    "Autoimmune support": (
        _page("page_1", "What matters now", "Flare Pattern and Current Impact", "Autoimmune support", "chief_concern", "symptom_review_table", "monitoring_table", "safety_review"),
        _page("page_2", "Triggers and plan", "Medicines, Pacing, and Review", "Flare support", "meal_plan_table", "medicine_schedule_table", "week_plan_table", "testing_followup_table"),
    ),
    "Acidity and bloating": (
        _page("page_1", "What matters now", "Timing, Triggers, and Warning Signs", "Acidity and bloating", "chief_concern", "symptom_review_table", "trigger_response_table", "safety_review"),
        _page("page_2", "Relief plan", "Trigger Context, Tests, and Review", "Daily relief", "meal_plan_table", "monitoring_table", "week_plan_table", "testing_followup_table"),
    ),
    "Cholesterol": (
        _page("page_1", "What matters now", "Lipid Risk and Current Routine", "Cholesterol", "chief_concern", "monitoring_table", "risk_factors", "medicine_schedule_table"),
        _page("page_2", "Follow-up plan", "Food Context, Labs, and Review", "Cardio support", "meal_plan_table", "week_plan_table", "testing_followup_table", "doctor_questions"),
    ),
    "Habit reset": (
        _page("page_1", "What matters now", "Trigger Loop and Current Risks", "Habit reset", "chief_concern", "habit_reset_table", "routine_review", "safety_review"),
        _page("page_2", "Reset plan", "Context, Support, and Follow-up", "7-day reset", "trigger_response_table", "week_plan_table", "support_context", "doctor_questions"),
    ),
    "Other problem": (
        _page("page_1", "What matters now", "Concern, Timeline, and Current Risk", "Custom intake", "chief_concern", "symptom_review_table", "monitoring_table", "safety_review"),
        _page("page_2", "Next steps", "Context, Tests, and Clinician Questions", "Follow-up plan", "trigger_response_table", "week_plan_table", "testing_followup_table", "doctor_questions"),
    ),
}


def box_spec(box_id: str) -> ReportBoxSpec:
    return _BOX_LIBRARY[box_id]


def page_specs_for_problem(problem_name: str) -> tuple[ReportPageSpec, ...]:
    template = template_for_problem(problem_name)
    return _PAGE_LAYOUTS.get(template.problem_name, _PAGE_LAYOUTS["Other problem"])


def report_markdown_sections_for_problem(problem_name: str) -> tuple[str, ...]:
    titles: list[str] = []
    for page in page_specs_for_problem(problem_name):
        for box_id in page.box_ids:
            title = box_spec(box_id).title
            if title not in titles:
                titles.append(title)
    titles.append("Safety Boundary")
    return tuple(titles)
