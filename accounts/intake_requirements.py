from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Iterable

from .report_extractors import _problem_key

INTAKE_SCHEMA_VERSION = "flicko_intake_schema_v1"


@dataclass(frozen=True)
class IntakeField:
    key: str
    label: str
    question: str
    why: str
    keywords: tuple[str, ...] = ()
    dashboard_keys: tuple[str, ...] = ()
    timeline: bool = False
    priority: int = 50
    memory_target: str = ""
    report_critical: bool = True


@dataclass(frozen=True)
class IntakeBlueprint:
    problem_key: str
    fields: tuple[IntakeField, ...]


@dataclass(frozen=True)
class IntakeAssessment:
    problem_key: str
    score: int
    is_complete: bool
    report_ready: bool
    answered_keys: tuple[str, ...]
    missing_fields: tuple[IntakeField, ...]
    timeline_gaps: tuple[str, ...]
    next_questions: tuple[str, ...]
    archive_targets_pending: tuple[str, ...]
    archive_targets_captured: tuple[str, ...]
    fields: tuple[dict[str, Any], ...]

    def to_payload(self) -> dict[str, Any]:
        return {
            "problem_key": self.problem_key,
            "score": self.score,
            "is_complete": self.is_complete,
            "report_ready": self.report_ready,
            "answered_keys": list(self.answered_keys),
            "missing_labels": [field.label for field in self.missing_fields],
            "timeline_gaps": list(self.timeline_gaps),
            "next_questions": list(self.next_questions),
            "archive_targets_pending": list(self.archive_targets_pending),
            "archive_targets_captured": list(self.archive_targets_captured),
            "fields": list(self.fields),
            "archive_markdown": self.archive_markdown(),
        }

    def archive_markdown(self) -> str:
        lines = [
            "## Structured intake assessment",
            f"- Condition family: {self.problem_key}",
            f"- Intake score: {self.score}%",
            f"- Intake complete: {'yes' if self.is_complete else 'no'}",
            f"- Report ready: {'yes' if self.report_ready else 'no'}",
        ]
        if self.timeline_gaps:
            lines.extend(
                [
                    "",
                    "## Timeline still missing",
                    *[f"- {label}" for label in self.timeline_gaps],
                ]
            )
        if self.next_questions:
            lines.extend(
                [
                    "",
                    "## Next questions",
                    *[f"- {question}" for question in self.next_questions],
                ]
            )
        if self.archive_targets_pending:
            lines.extend(
                [
                    "",
                    "## Memory targets still pending",
                    *[f"- {target}" for target in self.archive_targets_pending],
                ]
            )
        if self.archive_targets_captured:
            lines.extend(
                [
                    "",
                    "## Memory targets already captured",
                    *[f"- {target}" for target in self.archive_targets_captured],
                ]
            )
        return "\n".join(lines).strip()


def _field(
    key: str,
    label: str,
    question: str,
    why: str,
    *,
    keywords: Iterable[str] = (),
    dashboard_keys: Iterable[str] = (),
    timeline: bool = False,
    priority: int = 50,
    memory_target: str = "",
    report_critical: bool = True,
) -> IntakeField:
    return IntakeField(
        key=key,
        label=label,
        question=question,
        why=why,
        keywords=tuple(str(item).strip().lower() for item in keywords if str(item).strip()),
        dashboard_keys=tuple(str(item).strip() for item in dashboard_keys if str(item).strip()),
        timeline=timeline,
        priority=priority,
        memory_target=memory_target,
        report_critical=report_critical,
    )


_BASE_FIELDS: tuple[IntakeField, ...] = (
    _field(
        "main_concern",
        "Main concern",
        "What is the main problem you want Flicko to track first?",
        "The report fails if the core complaint is vague.",
        keywords=("main problem", "concern", "issue", "pain", "symptom", "problem"),
        timeline=False,
        priority=100,
        memory_target="symptom_summary",
    ),
    _field(
        "symptom_timeline",
        "Symptom timeline",
        "When did this start, and was it sudden, gradual, or recurring?",
        "Reports need onset and duration, not just a symptom name.",
        keywords=("since", "started", "days", "weeks", "months", "today", "yesterday", "sudden", "gradual", "recurring", "duration"),
        timeline=True,
        priority=98,
        memory_target="symptom_timeline",
    ),
    _field(
        "severity_frequency",
        "Severity and frequency",
        "How often does it happen, and how strong does it get on the worst day?",
        "Frequency and severity decide urgency and follow-up.",
        keywords=("daily", "weekly", "often", "every", "repeated", "mild", "moderate", "severe", "worst", "frequency"),
        timeline=True,
        priority=96,
        memory_target="severity_pattern",
    ),
    _field(
        "trigger_relief_pattern",
        "Trigger and relief pattern",
        "What makes it worse, and what gives relief even for a short time?",
        "Triggers and relief patterns make the symptom usable for a doctor.",
        keywords=("after", "before", "worse", "better", "relief", "trigger", "during", "rest", "meal", "exercise", "stress"),
        timeline=True,
        priority=94,
        memory_target="trigger_relief_map",
    ),
    _field(
        "current_diagnosis",
        "Current diagnosis or doctor label",
        "Has any doctor already given this a name or diagnosis?",
        "Prior diagnosis changes the follow-up path.",
        keywords=("diagnosed", "diagnosis", "doctor said", "condition", "known issue"),
        dashboard_keys=("diagnosis",),
        priority=88,
        memory_target="diagnosis_context",
    ),
    _field(
        "current_medicines",
        "Current medicines",
        "Which medicines, supplements, injections, or devices are you using for this right now?",
        "Medication context is mandatory for safe summaries.",
        keywords=("medicine", "medicines", "tablet", "capsule", "insulin", "supplement", "spray", "device", "prescribed"),
        dashboard_keys=("medicine", "medications"),
        priority=90,
        memory_target="medicine_context",
    ),
    _field(
        "medicine_timing",
        "Medicine timing and missed doses",
        "What time do you take them, and have you missed any recent doses?",
        "Timing and adherence change interpretation of symptoms and readings.",
        keywords=("morning", "night", "after food", "before food", "missed dose", "timing", "dose time", "lunch", "dinner"),
        dashboard_keys=("medicine_timing", "medication_timing"),
        priority=89,
        memory_target="medicine_timing",
    ),
    _field(
        "allergies_reactions",
        "Allergies or reactions",
        "Do you have any allergy, medicine reaction, or treatment that did not suit you?",
        "Reports must surface reaction risk clearly.",
        keywords=("allergy", "allergic", "reaction", "rash", "not suit", "didn't suit"),
        dashboard_keys=("allergies",),
        priority=82,
        memory_target="allergy_risk",
    ),
    _field(
        "relevant_reports_labs",
        "Relevant reports, scans, or labs",
        "Do you have any recent report, lab, scan, or prescription related to this problem?",
        "Without concrete reports, the doctor-ready summary stays weaker.",
        keywords=("report", "lab", "test", "scan", "prescription", "hba1c", "ultrasound", "cbc", "ldl", "tsh"),
        dashboard_keys=("uploaded_report", "latest_lab", "report_available"),
        priority=87,
        memory_target="report_uploads",
    ),
    _field(
        "routine_sleep_stress",
        "Routine, sleep, and stress context",
        "What is your current meal routine, sleep pattern, and stress level around this problem?",
        "Routine context explains many symptom patterns better than isolated notes.",
        keywords=("sleep", "stress", "routine", "bedtime", "wake", "shift", "work", "meal timing", "late dinner"),
        priority=70,
        memory_target="routine_context",
        report_critical=False,
    ),
    _field(
        "reminder_preference",
        "Reminder or follow-up time",
        "If Flicko should remind or call you, what time is actually realistic?",
        "A plan without a usable follow-up window does not operationalize.",
        keywords=("remind", "reminder", "call me", "pm", "am", "morning", "evening", "night"),
        dashboard_keys=("preferred_call_window", "reminder_time"),
        priority=65,
        memory_target="reminder_schedule",
        report_critical=False,
    ),
    _field(
        "red_flags",
        "Red-flag safety symptoms",
        "Any severe warning signs like chest pain, fainting, heavy bleeding, breathing trouble, fever, suicidal thoughts, or severe pain?",
        "Red flags decide whether normal coaching must stop.",
        keywords=("chest pain", "fainting", "breathless", "breathing", "heavy bleeding", "fever", "suicidal", "severe pain", "confusion", "vomiting"),
        priority=99,
        memory_target="safety_flags",
    ),
)


_CONDITION_FIELDS: dict[str, tuple[IntakeField, ...]] = {
    "diabetes": (
        _field(
            "glucose_readings",
            "Glucose readings and HbA1c",
            "What are your latest fasting, post-meal, or HbA1c values, and when were they recorded?",
            "Diabetes reports without real values are weak.",
            keywords=("fasting", "post meal", "post-meal", "glucose", "sugar", "hba1c", "a1c"),
            dashboard_keys=("fasting_glucose", "post_meal_glucose", "hba1c", "latest_glucose"),
            timeline=True,
            priority=97,
            memory_target="glucose_logs",
        ),
        _field(
            "hypo_hyper_clues",
            "Low or high sugar clues",
            "Have you had shakiness, sweating, dizziness, thirst, frequent urination, blurry vision, or vomiting?",
            "Symptoms anchor risk better than a single number.",
            keywords=("shaky", "sweating", "dizzy", "thirst", "urination", "blurred vision", "vomiting", "low sugar", "high sugar"),
            priority=93,
            memory_target="symptom_logs",
        ),
    ),
    "pregnancy": (
        _field(
            "gestation_stage",
            "Pregnancy week or trimester",
            "Which pregnancy week or trimester are you in right now?",
            "Pregnancy symptoms mean different things by gestational stage.",
            keywords=("weeks pregnant", "pregnancy week", "trimester", "gestation"),
            dashboard_keys=("pregnancy_week", "gestation_week", "trimester"),
            priority=99,
            memory_target="pregnancy_context",
        ),
        _field(
            "obstetric_risk",
            "Pregnancy risk context",
            "Any BP, sugar, thyroid, previous complication, twins, or doctor-marked high-risk note?",
            "Risk status changes urgency and follow-up intensity.",
            keywords=("bp", "blood pressure", "sugar", "thyroid", "high risk", "twins", "gestational", "doctor follow-up"),
            dashboard_keys=("pregnancy_risk", "risk_status"),
            priority=92,
            memory_target="pregnancy_risk",
        ),
        _field(
            "bleeding_movement_pain",
            "Bleeding, movement, swelling, or pain",
            "Any bleeding, reduced movement, swelling, severe pain, severe headache, or leaking fluid?",
            "These are core pregnancy escalation items.",
            keywords=("bleeding", "spotting", "movement", "kicks", "swelling", "severe pain", "headache", "fluid leak"),
            timeline=True,
            priority=98,
            memory_target="pregnancy_symptoms",
        ),
    ),
    "heart": (
        _field(
            "cardiac_symptom",
            "Chest or heart symptom",
            "What exactly happens: chest pressure, chest pain, palpitations, breathlessness, or something else?",
            "Heart complaints need a direct symptom label.",
            keywords=("chest pain", "chest pressure", "palpitations", "breathless", "shortness of breath", "heart"),
            timeline=True,
            priority=99,
            memory_target="heart_symptoms",
        ),
        _field(
            "exertion_relation",
            "Effort or rest relationship",
            "Does it happen on stairs, walking, exertion, or even at rest?",
            "Exertional relation changes urgency.",
            keywords=("stairs", "walking", "exertion", "exercise", "rest", "climbing"),
            timeline=True,
            priority=95,
            memory_target="heart_symptoms",
        ),
        _field(
            "risk_history",
            "Heart risk history",
            "Any BP, diabetes, cholesterol, smoking, family heart disease, or prior procedure?",
            "Baseline risk factors belong in any cardiac report.",
            keywords=("bp", "diabetes", "cholesterol", "smoking", "family history", "angioplasty", "stent"),
            priority=88,
            memory_target="risk_context",
        ),
    ),
    "mood": (
        _field(
            "mood_trigger",
            "Mood or trigger pattern",
            "What is the main feeling or stress pattern, and what usually triggers it?",
            "Mood reports need a pattern, not just a label.",
            keywords=("stress", "anxiety", "panic", "low mood", "depressed", "trigger", "overthinking"),
            timeline=True,
            priority=97,
            memory_target="mood_logs",
        ),
        _field(
            "sleep_appetite_energy",
            "Sleep, appetite, and energy impact",
            "How has this affected sleep, appetite, energy, or focus?",
            "Function impact is what makes the symptom actionable.",
            keywords=("sleep", "appetite", "energy", "fatigue", "focus", "tired"),
            priority=92,
            memory_target="mood_logs",
        ),
        _field(
            "self_harm_risk",
            "Self-harm or safety concern",
            "Any self-harm thoughts, feeling unsafe, or substance use making things worse?",
            "This is a non-negotiable safety field.",
            keywords=("self harm", "suicidal", "kill myself", "unsafe", "substance", "alcohol", "drug"),
            priority=100,
            memory_target="safety_flags",
        ),
    ),
    "sexual": (
        _field(
            "private_symptom",
            "Private symptom details",
            "What exact symptom is happening: discharge, itching, sores, pain, bleeding, erection, libido, urinary burning, or something else?",
            "Sexual-health reports fail fast when the symptom stays vague.",
            keywords=("discharge", "itching", "sores", "burning", "urine", "urinary", "bleeding", "pelvic", "erection", "libido", "pain"),
            timeline=True,
            priority=99,
            memory_target="private_symptom_logs",
        ),
        _field(
            "exposure_risk",
            "Exposure, partner, contraception, or pregnancy risk",
            "Any unprotected sex, STI exposure, new partner, contraception issue, pregnancy risk, or consent concern?",
            "Risk context changes testing and urgency.",
            keywords=("unprotected", "sti", "partner", "condom", "pregnancy risk", "contraception", "consent"),
            priority=98,
            memory_target="risk_context",
        ),
        _field(
            "testing_history",
            "Testing or doctor-referral history",
            "Any STI test, urine test, pregnancy test, scan, or doctor visit already done?",
            "This avoids duplicate advice and strengthens the report.",
            keywords=("sti test", "urine test", "pregnancy test", "doctor", "referral", "swab", "clinic"),
            priority=88,
            memory_target="testing_history",
        ),
    ),
    "weight": (
        _field(
            "weight_goal",
            "Current and goal weight",
            "What is your current weight, goal weight, and waist or BMI if known?",
            "Weight reports need a baseline and target.",
            keywords=("weight", "goal weight", "waist", "bmi"),
            dashboard_keys=("weight_kg", "goal_weight_kg", "bmi", "waist_cm"),
            priority=96,
            memory_target="weight_logs",
        ),
        _field(
            "meal_pattern",
            "Meal and craving pattern",
            "What do you usually eat across the day, and when do cravings or overeating hit hardest?",
            "The meal pattern is more useful than one isolated good day.",
            keywords=("breakfast", "lunch", "dinner", "snacks", "cravings", "binge", "late dinner"),
            timeline=True,
            priority=94,
            memory_target="meal_photos",
        ),
        _field(
            "activity_pattern",
            "Activity and step pattern",
            "How active are you now: steps, walks, workouts, or mostly sedentary?",
            "Weight plans break if activity capacity is assumed.",
            keywords=("steps", "walk", "workout", "gym", "sedentary", "exercise"),
            priority=80,
            memory_target="workouts",
        ),
    ),
    "bp": (
        _field(
            "bp_readings",
            "BP reading pattern",
            "What were the latest BP readings, at what time, and with what symptoms?",
            "BP advice without reading context is weak.",
            keywords=("bp", "blood pressure", "/", "systolic", "diastolic"),
            dashboard_keys=("latest_bp", "bp_reading", "systolic", "diastolic"),
            timeline=True,
            priority=98,
            memory_target="bp_logs",
        ),
        _field(
            "measurement_context",
            "Measurement technique context",
            "Were you seated and resting, and what device/cuff did you use?",
            "Technique errors create fake spikes.",
            keywords=("resting", "seated", "sitting", "cuff", "machine", "device"),
            priority=88,
            memory_target="bp_logs",
        ),
        _field(
            "salt_stimulant_context",
            "Salt, caffeine, alcohol, or smoking context",
            "Any recent high salt intake, caffeine, alcohol, smoking, or missed medicine around the reading?",
            "BP spikes are often context dependent.",
            keywords=("salt", "caffeine", "coffee", "tea", "alcohol", "smoking", "missed dose"),
            priority=84,
            memory_target="salt_logs",
        ),
    ),
    "pcos": (
        _field(
            "cycle_pattern",
            "Cycle pattern",
            "How long are your cycles, and are you missing periods, bleeding heavily, or having severe pain?",
            "Cycle pattern is the anchor for PCOS reports.",
            keywords=("cycle", "period", "missed", "bleeding", "pain", "irregular"),
            timeline=True,
            priority=97,
            memory_target="cycle_logs",
        ),
        _field(
            "skin_hair_change",
            "Acne, facial hair, or hair fall",
            "Any acne, facial hair growth, scalp hair fall, or skin change?",
            "These are core PCOS symptom markers.",
            keywords=("acne", "hair growth", "facial hair", "hair fall", "skin"),
            priority=88,
            memory_target="symptom_logs",
        ),
    ),
    "hormone": (
        _field(
            "fertility_cycle_context",
            "Cycle and fertility context",
            "How long have you been trying, what is the cycle pattern, and is pregnancy possible now?",
            "Preconception reports need cycle timing and fertility context.",
            keywords=("trying", "cycle", "period", "pregnancy", "fertility"),
            timeline=True,
            priority=96,
            memory_target="cycle_logs",
        ),
        _field(
            "supplement_diagnosis_context",
            "Supplements and hormone diagnosis context",
            "Are you taking folic acid or other supplements, and do you have PCOS, thyroid, diabetes, or BP history?",
            "Preconception planning depends on these basics.",
            keywords=("folic acid", "pcos", "thyroid", "diabetes", "bp", "supplement"),
            priority=86,
            memory_target="supplement_logs",
        ),
    ),
    "thyroid": (
        _field(
            "thyroid_lab_context",
            "Thyroid lab context",
            "What were the latest TSH or thyroid test values, and when were they checked?",
            "Thyroid guidance without lab timing is incomplete.",
            keywords=("tsh", "t3", "t4", "thyroid test", "lab"),
            dashboard_keys=("tsh", "t3", "t4"),
            timeline=True,
            priority=97,
            memory_target="lab_values",
        ),
    ),
    "postpartum": (
        _field(
            "delivery_context",
            "Delivery and recovery context",
            "When was the delivery, vaginal or C-section, and what recovery issue is most active now?",
            "Postpartum symptoms are meaningless without delivery context.",
            keywords=("delivery", "c section", "c-section", "normal delivery", "postpartum", "after birth"),
            timeline=True,
            priority=99,
            memory_target="recovery_timeline",
        ),
        _field(
            "feeding_sleep_support",
            "Feeding, sleep, and support context",
            "How are feeding, sleep, hydration, and support at home going right now?",
            "Recovery load matters as much as the symptom label.",
            keywords=("feeding", "breast", "sleep", "hydration", "support", "caregiver"),
            priority=88,
            memory_target="caregiver_notes",
        ),
    ),
    "digestive": (
        _field(
            "gi_symptom",
            "GI symptom pattern",
            "What is the main symptom: bloating, reflux, burning, constipation, diarrhea, or pain, and when does it happen?",
            "Digestive plans depend on timing and bowel pattern.",
            keywords=("bloating", "reflux", "burning", "constipation", "diarrhea", "stool", "pain"),
            timeline=True,
            priority=97,
            memory_target="symptom_logs",
        ),
    ),
    "sleep": (
        _field(
            "sleep_schedule",
            "Sleep schedule details",
            "What time do you sleep, wake, and how long does it take to fall asleep?",
            "Sleep problems need timing detail, not just 'poor sleep'.",
            keywords=("sleep", "bedtime", "wake", "latency", "awakenings", "nap"),
            timeline=True,
            priority=97,
            memory_target="sleep_logs",
        ),
        _field(
            "snore_breathing",
            "Snoring or breathing pauses",
            "Do you snore, stop breathing, wake choking, or have morning headaches?",
            "This changes the differential from habit to sleep-breathing risk.",
            keywords=("snore", "breathing pauses", "choking", "morning headache", "sleepy"),
            priority=90,
            memory_target="sleep_logs",
        ),
    ),
    "fitness": (
        _field(
            "fitness_goal_baseline",
            "Goal and baseline",
            "What is the fitness goal, and what is your current training or step baseline?",
            "Programming without a baseline is fake personalization.",
            keywords=("goal", "training", "steps", "strength", "baseline", "workout"),
            priority=96,
            memory_target="workout_logs",
        ),
        _field(
            "injury_limit",
            "Injury or medical limit",
            "Any pain, injury, dizziness, or medical restriction that limits exercise?",
            "This is the main safety gate for fitness advice.",
            keywords=("injury", "pain", "restriction", "dizziness", "medical limit"),
            priority=95,
            memory_target="pain_logs",
        ),
    ),
    "skin": (
        _field(
            "skin_hair_primary",
            "Primary skin or hair issue",
            "What is the main concern, for how long, and is there itch, pain, pus, or rapid worsening?",
            "Surface symptoms still need a time course and severity.",
            keywords=("acne", "itch", "pain", "pus", "hair fall", "rash", "worsening"),
            timeline=True,
            priority=96,
            memory_target="photo_progress",
        ),
    ),
    "general": (
        _field(
            "general_goal",
            "General health goal",
            "What exact health goal should Flicko help with first in the next 7 days?",
            "General wellness becomes useless if the goal stays broad.",
            keywords=("goal", "improve", "health goal", "next week"),
            priority=92,
            memory_target="daily_logs",
        ),
    ),
    "women": (
        _field(
            "cycle_flow_pain",
            "Cycle, flow, and pain pattern",
            "What are the cycle length, bleeding pattern, and pain pattern?",
            "Women's wellness reports need cycle structure first.",
            keywords=("cycle", "period", "flow", "bleeding", "pain", "pms"),
            timeline=True,
            priority=96,
            memory_target="cycle_logs",
        ),
    ),
    "senior": (
        _field(
            "mobility_falls",
            "Mobility, falls, or memory issues",
            "Any falls, near falls, dizziness, confusion, or memory decline recently?",
            "Senior-care summaries need fall and cognition risk up front.",
            keywords=("fall", "fell", "near fall", "dizzy", "confusion", "memory"),
            timeline=True,
            priority=98,
            memory_target="fall_logs",
        ),
        _field(
            "caregiver_support",
            "Caregiver or medicine support",
            "Who helps with medicines, meals, and appointments, and where are doses getting missed?",
            "Caregiver context often explains adherence problems.",
            keywords=("caregiver", "daughter", "son", "help", "missed dose", "support"),
            priority=88,
            memory_target="caregiver_notes",
        ),
    ),
    "autoimmune": (
        _field(
            "flare_pattern",
            "Flare pattern",
            "What does a flare look like, how long does it last, and what usually triggers it?",
            "Autoimmune support must separate flare pattern from baseline symptoms.",
            keywords=("flare", "pain", "fatigue", "joint", "trigger", "infection"),
            timeline=True,
            priority=97,
            memory_target="flare_logs",
        ),
    ),
    "cholesterol": (
        _field(
            "lipid_context",
            "Lipid values and date",
            "What are the latest LDL, HDL, triglyceride, or total cholesterol values, and when were they checked?",
            "Cholesterol reports need actual values or dates.",
            keywords=("ldl", "hdl", "triglyceride", "cholesterol", "lipid"),
            dashboard_keys=("ldl", "hdl", "triglycerides", "cholesterol_total"),
            timeline=True,
            priority=97,
            memory_target="lab_values",
        ),
        _field(
            "statin_adherence",
            "Medicine adherence",
            "Are you missing statin or other cholesterol medicines, and at what time are they taken?",
            "Adherence is usually the first operational fix.",
            keywords=("statin", "atorvastatin", "rosuvastatin", "missed", "night"),
            priority=90,
            memory_target="medicine_logs",
        ),
    ),
    "habit": (
        _field(
            "habit_target",
            "Habit target and timing",
            "Which habit needs reset, when does it usually happen, and what is the immediate trigger?",
            "Habit change without trigger timing is not actionable.",
            keywords=("habit", "scrolling", "smoking", "late night", "trigger", "craving"),
            timeline=True,
            priority=97,
            memory_target="habit_logs",
        ),
        _field(
            "replacement_plan",
            "Replacement action and blocker",
            "What replacement action is realistic, and what stops it right now?",
            "Replacement friction must be named or the plan fails.",
            keywords=("replacement", "walk", "blocker", "not ready", "craving", "relapse"),
            priority=88,
            memory_target="replacement_actions",
        ),
    ),
}


_REPORT_CRITICAL_BY_PROBLEM: dict[str, tuple[str, ...]] = {
    "diabetes": ("glucose_readings", "hypo_hyper_clues"),
    "pregnancy": ("gestation_stage", "bleeding_movement_pain"),
    "heart": ("cardiac_symptom", "exertion_relation"),
    "mood": ("mood_trigger", "self_harm_risk"),
    "sexual": ("private_symptom", "exposure_risk"),
    "weight": ("weight_goal", "meal_pattern"),
    "bp": ("bp_readings",),
    "pcos": ("cycle_pattern",),
    "hormone": ("fertility_cycle_context",),
    "thyroid": ("thyroid_lab_context",),
    "postpartum": ("delivery_context",),
    "digestive": ("gi_symptom",),
    "sleep": ("sleep_schedule",),
    "fitness": ("fitness_goal_baseline", "injury_limit"),
    "skin": ("skin_hair_primary",),
    "women": ("cycle_flow_pain",),
    "senior": ("mobility_falls",),
    "autoimmune": ("flare_pattern",),
    "cholesterol": ("lipid_context",),
    "habit": ("habit_target",),
    "general": ("general_goal",),
}

_INTAKE_SCHEMA_DISPLAY_NAMES: dict[str, str] = {
    "autoimmune": "Autoimmune support",
    "bp": "Blood pressure",
    "cholesterol": "Cholesterol",
    "diabetes": "Diabetes",
    "digestive": "Digestive health",
    "fitness": "Fitness",
    "general": "General wellness",
    "habit": "Habit reset",
    "heart": "Heart health",
    "hormone": "Preconception",
    "mood": "Stress and mood",
    "pcos": "PCOS/PCOD",
    "postpartum": "Postpartum",
    "pregnancy": "Pregnancy",
    "senior": "Senior care",
    "sexual": "Sexual health",
    "skin": "Skin and hair",
    "sleep": "Sleep health",
    "thyroid": "Thyroid",
    "weight": "Weight management",
    "women": "Women's wellness",
}

_INTAKE_SCHEMA_MATCH_TERMS: dict[str, tuple[str, ...]] = {
    "autoimmune": ("Autoimmune support",),
    "bp": ("Blood pressure", "BP", "Hypertension", "High blood pressure", "Low blood pressure"),
    "cholesterol": ("Cholesterol",),
    "diabetes": ("Diabetes", "Diabetes Type 1", "Diabetes Type 2", "Blood sugar", "T1D", "T2D"),
    "digestive": ("Digestive health", "Acidity and bloating"),
    "fitness": ("Fitness",),
    "general": ("General wellness", "Other problem"),
    "habit": ("Habit reset",),
    "heart": ("Heart health", "Cardiac", "Heart disease"),
    "hormone": ("Preconception",),
    "mood": ("Stress and mood",),
    "pcos": ("PCOS/PCOD", "PCOS", "PCOD"),
    "postpartum": ("Postpartum",),
    "pregnancy": ("Pregnancy",),
    "senior": ("Senior care",),
    "sexual": ("Sexual health", "Private health"),
    "skin": ("Skin and hair",),
    "sleep": ("Sleep health",),
    "thyroid": ("Thyroid",),
    "weight": ("Weight management", "Weight loss", "Weight gain"),
    "women": ("Women's wellness", "Womens wellness"),
}


def intake_blueprint(problem_name: str) -> IntakeBlueprint:
    problem_key = _problem_key(problem_name)
    return intake_blueprint_for_problem_key(problem_key)


def intake_blueprint_for_problem_key(problem_key: str) -> IntakeBlueprint:
    fields = tuple(_unique_fields([*_BASE_FIELDS, *_CONDITION_FIELDS.get(problem_key, ())]))
    return IntakeBlueprint(problem_key=problem_key, fields=fields)


def intake_schema_payload() -> dict[str, Any]:
    condition_keys = sorted({"general", *_CONDITION_FIELDS.keys()})
    return {
        "schema_version": INTAKE_SCHEMA_VERSION,
        "default_problem_key": "general",
        "generated_from": "apps.backend.accounts.intake_requirements",
        "conditions": [_condition_schema_payload(problem_key) for problem_key in condition_keys],
    }


def _condition_schema_payload(problem_key: str) -> dict[str, Any]:
    blueprint = intake_blueprint_for_problem_key(problem_key)
    return {
        "problem_key": problem_key,
        "display_name": _INTAKE_SCHEMA_DISPLAY_NAMES.get(problem_key, problem_key.title()),
        "match_terms": list(_INTAKE_SCHEMA_MATCH_TERMS.get(problem_key, (_INTAKE_SCHEMA_DISPLAY_NAMES.get(problem_key, problem_key.title()),))),
        "critical_keys": [
            field.key for field in blueprint.fields if field.report_critical
        ],
        "fields": [_field_payload(field) for field in blueprint.fields],
    }


def _field_payload(field: IntakeField) -> dict[str, Any]:
    return {
        "key": field.key,
        "label": field.label,
        "question": field.question,
        "why": field.why,
        "keywords": list(field.keywords),
        "dashboard_keys": list(field.dashboard_keys),
        "timeline": field.timeline,
        "priority": field.priority,
        "memory_target": field.memory_target,
        "report_critical": field.report_critical,
    }


def assess_intake(
    problem_name: str,
    *,
    dashboard_values: dict[str, Any] | None = None,
    transcript_lines: Iterable[str] = (),
    intake_summary: str = "",
    reminders: Iterable[str] = (),
    memory_entries: Iterable[Any] = (),
    source_payload: dict[str, Any] | None = None,
) -> IntakeAssessment:
    dashboard_values = dashboard_values if isinstance(dashboard_values, dict) else {}
    reminder_lines = _clean_list(reminders)
    blueprint = intake_blueprint(problem_name)
    corpus = _normalize(
        " ".join(
            [
                *_clean_list(transcript_lines),
                intake_summary,
                *_memory_entry_text(memory_entries),
                *_payload_strings(source_payload),
                *reminder_lines,
            ]
        )
    )
    fields_payload: list[dict[str, Any]] = []
    answered_keys: list[str] = []
    missing_fields: list[IntakeField] = []
    timeline_gaps: list[str] = []
    pending_targets: list[str] = []
    captured_targets: list[str] = []

    for field in blueprint.fields:
        answered = _field_answered(field, dashboard_values, corpus)
        fields_payload.append(
            {
                "key": field.key,
                "label": field.label,
                "question": field.question,
                "why": field.why,
                "timeline": field.timeline,
                "priority": field.priority,
                "memory_target": field.memory_target,
                "answered": answered,
            }
        )
        if answered:
            answered_keys.append(field.key)
            if field.memory_target:
                captured_targets.append(field.memory_target)
            continue
        missing_fields.append(field)
        if field.timeline:
            timeline_gaps.append(field.label)
        if field.memory_target:
            pending_targets.append(field.memory_target)

    total = max(len(blueprint.fields), 1)
    score = round(len(answered_keys) * 100 / total)
    critical_keys = {
        field.key for field in blueprint.fields if field.report_critical
    }
    critical_keys.update(_REPORT_CRITICAL_BY_PROBLEM.get(blueprint.problem_key, ()))
    report_ready = all(key in answered_keys for key in critical_keys)
    next_questions = tuple(
        field.question
        for field in sorted(missing_fields, key=lambda item: (-item.priority, item.label))[:3]
    )
    is_complete = report_ready and score >= 72 and len(timeline_gaps) <= 1
    return IntakeAssessment(
        problem_key=blueprint.problem_key,
        score=score,
        is_complete=is_complete,
        report_ready=report_ready,
        answered_keys=tuple(answered_keys),
        missing_fields=tuple(sorted(missing_fields, key=lambda item: (-item.priority, item.label))),
        timeline_gaps=tuple(timeline_gaps),
        next_questions=next_questions,
        archive_targets_pending=tuple(_unique_strings(pending_targets)),
        archive_targets_captured=tuple(_unique_strings(captured_targets)),
        fields=tuple(fields_payload),
    )


def _field_answered(field: IntakeField, dashboard_values: dict[str, Any], corpus: str) -> bool:
    if any(_clean_text(dashboard_values.get(key)).strip() for key in field.dashboard_keys):
        return True
    return any(keyword in corpus for keyword in field.keywords)


def _memory_entry_text(entries: Iterable[Any]) -> list[str]:
    lines: list[str] = []
    for entry in entries or ():
        if isinstance(entry, dict):
            lines.extend(
                [
                    _clean_text(entry.get("title")),
                    _clean_text(entry.get("content")),
                ]
            )
            continue
        lines.extend(
            [
                _clean_text(getattr(entry, "title", "")),
                _clean_text(getattr(entry, "content", "")),
            ]
        )
    return [line for line in lines if line]


def _payload_strings(value: Any) -> list[str]:
    if value is None:
        return []
    if isinstance(value, dict):
        rows: list[str] = []
        for key, item in value.items():
            rows.append(_clean_text(key))
            rows.extend(_payload_strings(item))
        return rows
    if isinstance(value, (list, tuple, set)):
        rows: list[str] = []
        for item in value:
            rows.extend(_payload_strings(item))
        return rows
    clean = _clean_text(value)
    return [clean] if clean else []


def _clean_text(value: Any) -> str:
    return " ".join(str(value or "").strip().split())


def _clean_list(values: Iterable[Any]) -> list[str]:
    return [clean for item in values or () if (clean := _clean_text(item))]


def _normalize(value: str) -> str:
    return " ".join(value.lower().strip().split())


def _unique_fields(fields: Iterable[IntakeField]) -> list[IntakeField]:
    seen: set[str] = set()
    output: list[IntakeField] = []
    for field in fields:
        if field.key in seen:
            continue
        seen.add(field.key)
        output.append(field)
    return output


def _unique_strings(values: Iterable[str]) -> list[str]:
    seen: set[str] = set()
    output: list[str] = []
    for value in values:
        cleaned = _clean_text(value)
        key = cleaned.lower()
        if cleaned and key not in seen:
            seen.add(key)
            output.append(cleaned)
    return output
