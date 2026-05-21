from __future__ import annotations

from collections.abc import Iterable
from dataclasses import dataclass, field
import re
from typing import Any


@dataclass
class ConditionEvidence:
    symptom_slots: dict[str, str] = field(default_factory=dict)
    label_slots: dict[str, str] = field(default_factory=dict)
    slot_sources: dict[str, str] = field(default_factory=dict)
    medicine: str = ""
    medicine_source: str = ""
    timing: str = ""
    timing_source: str = ""
    side_effects: str = ""
    side_effects_source: str = ""
    raw_lines: tuple[str, ...] = ()

    def slot(self, slot_name: str) -> str:
        return self.symptom_slots.get(slot_name, "")

    def row(self, label: str) -> str:
        slot_name = self.label_slots.get(label) or _slot_name(label)
        return self.symptom_slots.get(slot_name, "")

    def source(self, key: str) -> str:
        if key == "__medicine":
            return self.medicine_source
        if key == "__timing":
            return self.timing_source
        if key == "__side_effects":
            return self.side_effects_source
        if key in self.symptom_slots:
            return self.slot_sources.get(key, "")
        slot_name = self.label_slots.get(key) or _slot_name(key)
        return self.slot_sources.get(slot_name, "")

    def get(self, key: str, default: str = "") -> str:
        if key == "__medicine":
            return self.medicine or default
        if key == "__timing":
            return self.timing or default
        if key == "__side_effects":
            return self.side_effects or default
        if key in self.symptom_slots:
            return self.symptom_slots.get(key, default)
        return self.row(key) or default

    def items(self) -> tuple[tuple[str, str], ...]:
        rows = list(self.symptom_slots.items())
        if self.medicine:
            rows.append(("__medicine", self.medicine))
        if self.timing:
            rows.append(("__timing", self.timing))
        if self.side_effects:
            rows.append(("__side_effects", self.side_effects))
        return tuple(rows)

    def __contains__(self, key: str) -> bool:
        if key in {"__medicine", "__timing", "__side_effects"}:
            return bool(self.get(key))
        if key in self.symptom_slots:
            return bool(self.symptom_slots.get(key))
        if key in self.label_slots:
            return bool(self.row(key))
        return False


@dataclass(frozen=True)
class SymptomFieldSchema:
    slot: str
    label: str
    guidance: str


@dataclass(frozen=True)
class ConditionSchema:
    key: str
    symptom_fields: tuple[SymptomFieldSchema, ...]


_EXPLICIT_CONDITION_KEYS = frozenset(
    {
        "autoimmune",
        "bp",
        "cholesterol",
        "diabetes",
        "digestive",
        "fitness",
        "general",
        "habit",
        "heart",
        "hormone",
        "mood",
        "pcos",
        "postpartum",
        "pregnancy",
        "senior",
        "sexual",
        "skin",
        "sleep",
        "thyroid",
        "weight",
        "women",
    }
)


def _field(slot: str, label: str, guidance: str) -> SymptomFieldSchema:
    return SymptomFieldSchema(slot=slot, label=label, guidance=guidance)


_CONDITION_SCHEMAS: dict[str, ConditionSchema] = {
    "weight": ConditionSchema(
        key="weight",
        symptom_fields=(
            _field("weight_trend", "Weight trend", "Look for weekly direction, not one-day fluctuation."),
            _field("hunger_cravings_context", "Hunger / cravings context", "Record whether urges follow stress, poor sleep, or long meal gaps."),
            _field("activity_steps_pattern", "Activity / steps pattern", "Daily movement changes the usefulness of any meal or medicine plan."),
            _field("sleep_routine_impact", "Sleep / routine impact", "Poor sleep often blocks fat-loss progress even when calories look controlled."),
        ),
    ),
    "bp": ConditionSchema(
        key="bp",
        symptom_fields=(
            _field("reading_pattern", "Reading pattern", "Note whether values are repeated, isolated, or technique dependent."),
            _field("associated_symptoms", "Associated symptoms", "Headache, dizziness, or chest symptoms change urgency."),
            _field("salt_stress_context", "Salt / stress context", "Pressure spikes are more actionable when the trigger is documented."),
            _field("medication_relation", "Medication relation", "Reading timing should be compared with medicine timing."),
        ),
    ),
    "diabetes": ConditionSchema(
        key="diabetes",
        symptom_fields=(
            _field("glucose_pattern", "Glucose pattern", "Include timing with meals or insulin to make the pattern clinically usable."),
            _field("low_high_episode_clues", "Low / high episode clues", "Document dizziness, shakiness, sweating, or marked fatigue if present."),
            _field("meal_timing_impact", "Meal timing impact", "Late or skipped meals often explain variability."),
            _field("activity_effect", "Activity effect", "Walking or inactivity changes readings and needs to be linked to the log."),
        ),
    ),
    "pcos": ConditionSchema(
        key="pcos",
        symptom_fields=(
            _field("cycle_pattern", "Cycle pattern", "Capture delay, irregularity, or heavy/light flow instead of generic cycle language."),
            _field("skin_hair_change", "Skin / hair change", "Acne, facial hair, or hair fall can indicate androgen-related burden."),
            _field("weight_cravings", "Weight / cravings", "These help assess insulin-resistance behavior patterns."),
            _field("mood_sleep_context", "Mood / sleep context", "Poor sleep and stress often amplify hormone symptoms."),
        ),
    ),
    "hormone": ConditionSchema(
        key="hormone",
        symptom_fields=(
            _field("cycle_pattern", "Cycle pattern", "Capture delay, irregularity, or heavy/light flow instead of generic cycle language."),
            _field("skin_hair_change", "Skin / hair change", "Acne, facial hair, or hair fall can indicate androgen-related burden."),
            _field("weight_cravings", "Weight / cravings", "These help assess insulin-resistance behavior patterns."),
            _field("mood_sleep_context", "Mood / sleep context", "Poor sleep and stress often amplify hormone symptoms."),
        ),
    ),
    "women": ConditionSchema(
        key="women",
        symptom_fields=(
            _field("cycle_symptom", "Cycle symptom", "Flow, pain, irregularity, or PMS pattern should be stated clearly."),
            _field("daily_impact", "Daily impact", "Work, sleep, mood, and activity impairment matter clinically."),
            _field("associated_symptom", "Associated symptom", "Headache, skin change, bowel change, or fatigue often helps pattern recognition."),
            _field("escalation_cue", "Escalation cue", "Very heavy bleeding, severe pain, or persistent irregularity needs review."),
        ),
    ),
    "thyroid": ConditionSchema(
        key="thyroid",
        symptom_fields=(
            _field("energy_fatigue", "Energy and fatigue", "Persistent fatigue should be paired with sleep and medicine timing."),
            _field("weight_bowel_change", "Weight / bowel change", "Slow gut, weight drift, or appetite shifts should be stated clearly."),
            _field("hair_skin_temperature_clues", "Hair / skin / temperature clues", "These often show endocrine pattern before labs are reviewed."),
            _field("medication_effect", "Medication effect", "Symptoms only become interpretable once timing and adherence are known."),
        ),
    ),
    "pregnancy": ConditionSchema(
        key="pregnancy",
        symptom_fields=(
            _field("current_symptom", "Current symptom", "Describe nausea, pain, swelling, headache, or reflux specifically."),
            _field("trimester_context", "Trimester context", "The same symptom can mean different things by gestational stage."),
            _field("bleeding_movement_pain", "Bleeding / movement / pain", "These features change urgency immediately."),
            _field("escalation_clues", "Escalation clues", "Fever, severe pain, heavy bleeding, or reduced movement need prompt action."),
        ),
    ),
    "postpartum": ConditionSchema(
        key="postpartum",
        symptom_fields=(
            _field("recovery_symptom", "Recovery symptom", "Bleeding, wound pain, fever, or urinary symptoms must be separated clearly."),
            _field("mood_bonding", "Mood and bonding", "Mood, panic, numbness, or inability to cope change the care plan."),
            _field("feeding_breast_issues", "Feeding / breast issues", "Latch, engorgement, pain, or low intake affect recovery load."),
            _field("safety_concern", "Safety concern", "Heavy bleeding, fever, suicidal thoughts, or chest pain need escalation."),
        ),
    ),
    "digestive": ConditionSchema(
        key="digestive",
        symptom_fields=(
            _field("main_gi_symptom", "Main GI symptom", "Specify bloating, reflux, burning, pain, or bowel discomfort."),
            _field("timing_after_food", "Timing after food", "Symptoms tied to meal timing are easier to troubleshoot."),
            _field("bowel_pattern", "Bowel pattern", "Constipation, urgency, or diarrhea change the differential."),
            _field("alarm_symptoms", "Alarm symptoms", "Blood, vomiting, severe weight loss, or persistent pain are not lifestyle-only issues."),
        ),
    ),
    "sleep": ConditionSchema(
        key="sleep",
        symptom_fields=(
            _field("sleep_schedule", "Sleep schedule", "Schedule matters less by clock purity than by repeatability."),
            _field("night_disruption", "Night disruption", "Repeated waking or snoring changes the differential completely."),
            _field("behavior_trigger", "Behavior trigger", "Late caffeine, screens, or stress are easier to fix when named directly."),
            _field("daytime_impact", "Daytime impact", "Measure sleep by next-day function, not only hours in bed."),
        ),
    ),
    "heart": ConditionSchema(
        key="heart",
        symptom_fields=(
            _field("primary_cardiac_symptom", "Primary cardiac symptom", "Chest pressure, breathlessness, or palpitations must be described directly."),
            _field("effort_relationship", "Effort relationship", "Symptoms on exertion carry more weight than vague discomfort."),
            _field("trigger_relief_pattern", "Trigger / relief pattern", "A clear trigger or relief factor helps triage and follow-up."),
            _field("urgent_review_clues", "Urgent review clues", "Radiation, sweating, fainting, or progressive breathlessness raise concern."),
        ),
    ),
    "mood": ConditionSchema(
        key="mood",
        symptom_fields=(
            _field("mood_state", "Mood state", "Describe anxiety, low mood, irritability, or overwhelm directly."),
            _field("trigger_pattern", "Trigger pattern", "Context improves actionability more than generic severity words."),
            _field("body_routine_impact", "Body routine impact", "Sleep, appetite, and energy are part of the symptom picture."),
            _field("safety_concern", "Safety concern", "Hopelessness, self-harm thoughts, or inability to function changes urgency."),
        ),
    ),
    "fitness": ConditionSchema(
        key="fitness",
        symptom_fields=(
            _field("current_training_load", "Current training load", "Training volume only matters when paired with actual tolerance."),
            _field("pain_injury_signal", "Pain / injury signal", "Name the joint, motion, and phase where pain appears."),
            _field("recovery_burden", "Recovery burden", "Soreness and fatigue define whether progression is realistic."),
            _field("progression_blocker", "Progression blocker", "Warmup, technique, fear, or time constraints need explicit naming."),
        ),
    ),
    "skin": ConditionSchema(
        key="skin",
        symptom_fields=(
            _field("primary_change", "Primary change", "Describe rash, acne, pigmentation, itch, or hair fall directly."),
            _field("pattern_and_spread", "Pattern and spread", "Timing, recurrence, and body area matter."),
            _field("possible_trigger", "Possible trigger", "Products, food, stress, hormones, or deficiency clues should be named."),
            _field("escalation_cue", "Escalation cue", "Infection signs, rapid spread, or marked hair loss need review."),
        ),
    ),
    "general": ConditionSchema(
        key="general",
        symptom_fields=(
            _field("primary_concern", "Primary concern", "Document onset, frequency, and severity with one clear sentence."),
            _field("routine_pattern", "Timeline", "A symptom without timing is hard to interpret."),
            _field("sleep_stress_context", "Daily impact", "Function matters as much as symptom presence."),
            _field("safety_clue", "Safety clue", "Red flags should be separated from routine discomfort."),
        ),
    ),
    "senior": ConditionSchema(
        key="senior",
        symptom_fields=(
            _field("mobility_falls_risk", "Mobility / falls risk", "Falls risk is a first-order safety variable, not a side note."),
            _field("confusion_dizziness", "Confusion / dizziness", "These often reflect medicine, hydration, infection, or blood-pressure issues."),
            _field("meals_hydration", "Meals / hydration", "Poor intake quickly destabilizes medicines and recovery."),
            _field("medicine_caregiver_context", "Medicine / caregiver context", "Adherence logistics matter as much as the prescription itself."),
        ),
    ),
    "sexual": ConditionSchema(
        key="sexual",
        symptom_fields=(
            _field("main_symptom", "Main symptom", "Name the actual symptom instead of vague discomfort language."),
            _field("timing_exposure", "Timing / exposure", "Onset after intercourse, partner exposure, or contraception changes the workup."),
            _field("pain_bleeding_discharge", "Pain / bleeding / discharge", "These features determine urgency and testing direction."),
            _field("pregnancy_sti_risk", "Pregnancy / STI risk", "Testing decisions depend on this being captured clearly."),
        ),
    ),
    "autoimmune": ConditionSchema(
        key="autoimmune",
        symptom_fields=(
            _field("pain_swelling", "Pain / swelling", "Joint pattern, stiffness, and location matter."),
            _field("fatigue_burden", "Fatigue burden", "Fatigue should be described as daily impact, not only severity."),
            _field("flare_trigger", "Flare trigger", "Stress, infection, missed medicines, or overexertion often matter."),
            _field("escalation_cue", "Escalation cue", "Fever, progressive swelling, weakness, or reduced function change urgency."),
        ),
    ),
    "cholesterol": ConditionSchema(
        key="cholesterol",
        symptom_fields=(
            _field("lipid_lab_context", "Lipid / lab context", "Lab numbers need diet, weight, and family context to be actionable."),
            _field("food_risk_pattern", "Food risk pattern", "Pattern beats aspiration; document the real intake triggers."),
            _field("activity_weight_context", "Activity / weight context", "Movement and waist trend determine how aggressive the plan must be."),
            _field("family_cardiovascular_risk", "Family / cardiovascular risk", "Family history changes thresholds for follow-up."),
        ),
    ),
    "habit": ConditionSchema(
        key="habit",
        symptom_fields=(
            _field("trigger", "Trigger", "If the trigger is vague, the replacement plan will fail."),
            _field("current_loop", "Current loop", "Describe the actual behavior loop, not the moral judgment about it."),
            _field("friction_blocker", "Friction blocker", "Small setup failures usually explain repeated non-adherence."),
            _field("escalation_relapse_risk", "Escalation / relapse risk", "Name the point where the habit stops being manageable."),
        ),
    ),
}


def _condition_evidence(
    problem_name: str,
    *,
    values: dict[str, Any],
    sections: tuple[Any, ...],
    matched_sections: tuple[Any, ...],
    transcript_notes: tuple[str, ...],
    pair_lookup: dict[str, str],
) -> ConditionEvidence:
    problem_key = _problem_key(problem_name)
    lines = _evidence_lines(values, sections, matched_sections, transcript_notes, pair_lookup)
    if problem_key == "weight":
        return _extract_weight_evidence(lines, values, pair_lookup)
    if problem_key == "bp":
        return _extract_bp_evidence(lines, values, pair_lookup)
    if problem_key == "diabetes":
        return _extract_diabetes_evidence(lines, values, pair_lookup)
    if problem_key in {"pcos", "hormone"}:
        return _extract_hormone_evidence(lines, values, pair_lookup, problem_key=problem_key)
    if problem_key == "women":
        return _extract_womens_wellness_evidence(lines, values, pair_lookup)
    if problem_key == "thyroid":
        return _extract_thyroid_evidence(lines, values, pair_lookup)
    if problem_key == "pregnancy":
        return _extract_pregnancy_evidence(lines, values, pair_lookup)
    if problem_key == "postpartum":
        return _extract_postpartum_evidence(lines, values, pair_lookup)
    if problem_key == "digestive":
        return _extract_digestive_evidence(lines, values, pair_lookup)
    if problem_key == "sleep":
        return _extract_sleep_evidence(lines, values, pair_lookup)
    if problem_key == "heart":
        return _extract_heart_evidence(lines, values, pair_lookup)
    if problem_key == "mood":
        return _extract_stress_mood_evidence(lines, values, pair_lookup)
    if problem_key == "fitness":
        return _extract_fitness_evidence(lines, values, pair_lookup)
    if problem_key == "skin":
        return _extract_skin_hair_evidence(lines, values, pair_lookup)
    if problem_key == "general":
        return _extract_general_evidence(lines, values, pair_lookup)
    if problem_key == "senior":
        return _extract_senior_evidence(lines, values, pair_lookup)
    if problem_key == "sexual":
        return _extract_sexual_health_evidence(lines, values, pair_lookup)
    if problem_key == "autoimmune":
        return _extract_autoimmune_evidence(lines, values, pair_lookup)
    if problem_key == "cholesterol":
        return _extract_cholesterol_evidence(lines, values, pair_lookup)
    if problem_key == "habit":
        return _extract_habit_evidence(lines, values, pair_lookup)
    return _build_evidence(problem_key, raw_lines=lines)


def _build_evidence(
    problem_key: str,
    *,
    symptom_slots: dict[str, str] | None = None,
    slot_sources: dict[str, str] | None = None,
    medicine: str = "",
    medicine_source: str = "",
    timing: str = "",
    timing_source: str = "",
    side_effects: str = "",
    side_effects_source: str = "",
    raw_lines: tuple[str, ...] = (),
) -> ConditionEvidence:
    cleaned_slots = {key: value for key, value in (symptom_slots or {}).items() if value}
    cleaned_slot_sources = {
        key: value
        for key, value in (slot_sources or {}).items()
        if key in cleaned_slots and value
    }
    for key in cleaned_slots:
        cleaned_slot_sources.setdefault(key, "transcript")
    return ConditionEvidence(
        symptom_slots=cleaned_slots,
        label_slots=_symptom_slot_map_for_key(problem_key),
        slot_sources=cleaned_slot_sources,
        medicine=medicine,
        medicine_source=medicine_source or ("derived" if medicine else ""),
        timing=timing,
        timing_source=timing_source or ("derived" if timing else ""),
        side_effects=side_effects,
        side_effects_source=side_effects_source or ("derived" if side_effects else ""),
        raw_lines=raw_lines,
    )


def _symptom_rows_for_problem(
    problem_name: str,
    evidence: ConditionEvidence,
    captures: Iterable[str] = (),
) -> tuple[tuple[str, str, str], ...]:
    remaining = [capture for capture in captures if capture]
    rows: list[tuple[str, str, str]] = []
    for field in _condition_schema(problem_name).symptom_fields:
        captured = evidence.slot(field.slot) or (remaining.pop(0) if remaining else "Not clearly documented yet.")
        rows.append((field.label, captured, field.guidance))
    return tuple(rows)


def _symptom_slot_map(problem_name: str) -> dict[str, str]:
    return _symptom_slot_map_for_key(_problem_key(problem_name))


def _symptom_slot_map_for_key(problem_key: str) -> dict[str, str]:
    return {field.label: field.slot for field in _condition_schema_for_key(problem_key).symptom_fields}


def _condition_schema(problem_name: str) -> ConditionSchema:
    return _condition_schema_for_key(_problem_key(problem_name))


def _condition_schema_for_key(problem_key: str) -> ConditionSchema:
    return _CONDITION_SCHEMAS.get(problem_key, _CONDITION_SCHEMAS["general"])


def _slot_for_symptom_label(problem_name: str, label: str) -> str:
    return _symptom_slot_map(problem_name).get(label, _slot_name(label))


def _problem_key(problem_name: str) -> str:
    normalized = _normalize(problem_name)
    if "diabetes" in normalized:
        return "diabetes"
    if "weight" in normalized:
        return "weight"
    if "bloodpressure" in normalized or normalized == "bp":
        return "bp"
    if "hearthealth" in normalized:
        return "heart"
    if "pcos" in normalized or "pcod" in normalized:
        return "pcos"
    if "thyroid" in normalized:
        return "thyroid"
    if "pregnancy" in normalized:
        return "pregnancy"
    if "preconception" in normalized:
        return "hormone"
    if "postpartum" in normalized:
        return "postpartum"
    if "digestivehealth" in normalized or "acidityandbloating" in normalized:
        return "digestive"
    if "sleephealth" in normalized:
        return "sleep"
    if "stressandmood" in normalized:
        return "mood"
    if "fitness" in normalized:
        return "fitness"
    if "skinandhair" in normalized:
        return "skin"
    if "generalwellness" in normalized:
        return "general"
    if "womenswellness" in normalized:
        return "women"
    if "seniorcare" in normalized:
        return "senior"
    if "sexualhealth" in normalized:
        return "sexual"
    if "autoimmunesupport" in normalized:
        return "autoimmune"
    if "cholesterol" in normalized:
        return "cholesterol"
    if "habitreset" in normalized:
        return "habit"
    return "general"


def _evidence_lines(
    values: dict[str, Any],
    sections: tuple[Any, ...],
    matched_sections: tuple[Any, ...],
    transcript_notes: tuple[str, ...],
    pair_lookup: dict[str, str],
) -> tuple[str, ...]:
    rows: list[str] = []
    rows.extend(_summary_sentences(matched_sections))
    rows.extend(transcript_notes)
    rows.extend(_summary_sentences(sections))
    for key, value in values.items():
        if _skip_dashboard_key(str(key)):
            continue
        clean_value = _string_value(value)
        if clean_value:
            rows.append(f"{_humanize_key(str(key))}: {clean_value}")
    for key, value in pair_lookup.items():
        clean_value = _clean_text(value).strip()
        if clean_value:
            rows.append(f"{_humanize_key(key)}: {clean_value}")
    return _unique(rows)


def _match_line(lines: tuple[str, ...], *patterns: str | tuple[str, ...]) -> str:
    normalized_patterns: list[tuple[str, ...]] = []
    for pattern in patterns:
        if isinstance(pattern, tuple):
            normalized_patterns.append(tuple(_normalize(part) for part in pattern if part))
        else:
            normalized = _normalize(pattern)
            if normalized:
                normalized_patterns.append((normalized,))
    for line in lines:
        normalized_line = _normalize(line)
        if any(all(part in normalized_line for part in pattern) for pattern in normalized_patterns):
            return line
    return ""


def _pick_text(*candidates: tuple[str, Any]) -> tuple[str, str]:
    for source, value in candidates:
        clean = _clean_text(value).strip()
        if clean:
            return clean, source
    return "", ""


def _medicine_choice(
    values: dict[str, Any],
    pair_lookup: dict[str, str],
    lines: tuple[str, ...],
    *patterns: str | tuple[str, ...],
) -> tuple[str, str]:
    return _pick_text(
        ("dashboard", _string_value(values.get("medicine"))),
        ("dashboard", _string_value(values.get("medicines"))),
        ("transcript", _match_line(lines, *patterns)),
        ("pair", _lookup_pair("Medicine", pair_lookup) or _lookup_pair("Medication", pair_lookup)),
    )


def _timing_choice(
    values: dict[str, Any],
    pair_lookup: dict[str, str],
    lines: tuple[str, ...],
    *patterns: str | tuple[str, ...],
    pair_labels: tuple[str, ...] = ("Timing",),
) -> tuple[str, str]:
    pair_value = ""
    for label in pair_labels:
        pair_value = _lookup_pair(label, pair_lookup)
        if pair_value:
            break
    return _pick_text(
        ("dashboard", _string_value(values.get("medicine_timing"))),
        ("transcript", _match_line(lines, *patterns)),
        ("pair", pair_value),
    )


def _side_effect_choice(
    lines: tuple[str, ...],
    *patterns: str | tuple[str, ...],
) -> tuple[str, str]:
    return _pick_text(("transcript", _match_line(lines, *patterns)))


def _extract_diabetes_evidence(
    lines: tuple[str, ...],
    values: dict[str, Any],
    pair_lookup: dict[str, str],
) -> ConditionEvidence:
    medicine, medicine_source = _medicine_choice(values, pair_lookup, lines, "insulin", "metformin", "glimepiride", "medicine", "tablet")
    timing, timing_source = _timing_choice(
        values,
        pair_lookup,
        lines,
        ("before", "breakfast"),
        ("after", "food"),
        ("with", "meal"),
        ("before", "meal"),
        pair_labels=("Timing", "Meal timing"),
    )
    side_effects, side_effects_source = _side_effect_choice(
        lines,
        "nausea",
        "stomach",
        "vomiting",
        "diarrhea",
        "low sugar",
        "hypo",
        "shaky",
        "sweating",
        "weak",
    )
    return _build_evidence(
        "diabetes",
        symptom_slots={
            "glucose_pattern": _match_line(lines, "fasting", "post meal", "blood sugar", "glucose", "hba1c"),
            "low_high_episode_clues": _match_line(lines, "hypo", "hyper", "low sugar", "high sugar", "shaky", "sweating", "dizzy", "weak"),
            "meal_timing_impact": _match_line(lines, ("meal", "timing"), ("skipped", "meal"), ("late", "meal"), "breakfast", ("long", "gap")),
            "activity_effect": _match_line(lines, ("walk",), ("steps",), ("exercise",), ("activity",), ("post", "meal", "walk")),
        },
        medicine=medicine,
        medicine_source=medicine_source,
        timing=timing,
        timing_source=timing_source,
        side_effects=side_effects,
        side_effects_source=side_effects_source,
        raw_lines=lines,
    )


def _extract_weight_evidence(
    lines: tuple[str, ...],
    values: dict[str, Any],
    pair_lookup: dict[str, str],
) -> ConditionEvidence:
    medicine, medicine_source = _medicine_choice(values, pair_lookup, lines, "orlistat", "semaglutide", "liraglutide", "weight medicine", "supplement")
    timing, timing_source = _timing_choice(
        values,
        pair_lookup,
        lines,
        ("before", "meal"),
        ("after", "breakfast"),
        ("weekly", "injection"),
    )
    side_effects, side_effects_source = _side_effect_choice(lines, "nausea", "vomiting", "loose stool", "constipation", "bloating", "weakness")
    return _build_evidence(
        "weight",
        symptom_slots={
            "weight_trend": _match_line(lines, "weight gain", "weight loss", "plateau", "scale", "waist"),
            "hunger_cravings_context": _match_line(lines, "cravings", "late snacking", "emotional eating", "hunger", "binge"),
            "activity_steps_pattern": _match_line(lines, "steps", "walk", "activity", "exercise", "sedentary"),
            "sleep_routine_impact": _match_line(lines, "sleep", "late night", "night shift", "poor sleep", "fatigue"),
        },
        medicine=medicine,
        medicine_source=medicine_source,
        timing=timing,
        timing_source=timing_source,
        side_effects=side_effects,
        side_effects_source=side_effects_source,
        raw_lines=lines,
    )


def _extract_bp_evidence(
    lines: tuple[str, ...],
    values: dict[str, Any],
    pair_lookup: dict[str, str],
) -> ConditionEvidence:
    medicine, medicine_source = _medicine_choice(values, pair_lookup, lines, "amlodipine", "telmisartan", "losartan", "bp medicine")
    timing, timing_source = _timing_choice(
        values,
        pair_lookup,
        lines,
        ("morning", "bp"),
        ("night", "bp"),
        ("after", "breakfast"),
        ("before", "sleep"),
    )
    side_effects, side_effects_source = _side_effect_choice(lines, "dizziness", "swelling", "cough", "lightheaded", "weakness")
    return _build_evidence(
        "bp",
        symptom_slots={
            "reading_pattern": _match_line(lines, "bp", "blood pressure", "systolic", "diastolic", "reading"),
            "associated_symptoms": _match_line(lines, "headache", "dizziness", "chest pain", "blurred vision", "palpitations"),
            "salt_stress_context": _match_line(lines, "salt", "salty", "stress", "work stress", "takeaway", "packaged food"),
            "medication_relation": _match_line(lines, "missed dose", "after medicine", "before medicine", "timing", "bp medicine"),
        },
        medicine=medicine,
        medicine_source=medicine_source,
        timing=timing,
        timing_source=timing_source,
        side_effects=side_effects,
        side_effects_source=side_effects_source,
        raw_lines=lines,
    )


def _extract_pregnancy_evidence(
    lines: tuple[str, ...],
    values: dict[str, Any],
    pair_lookup: dict[str, str],
) -> ConditionEvidence:
    trimester_context, trimester_source = _pick_text(
        ("dashboard", _string_value(values.get("trimester"))),
        ("pair", _lookup_pair("Trimester", pair_lookup)),
        ("transcript", _match_line(lines, "trimester", "weeks pregnant", "pregnant")),
    )
    return _build_evidence(
        "pregnancy",
        symptom_slots={
            "current_symptom": _match_line(lines, "nausea", "vomiting", "reflux", "swelling", "headache", "pain", "cramping"),
            "trimester_context": trimester_context,
            "bleeding_movement_pain": _match_line(lines, "bleeding", "spotting", "movement", "baby movement", "kicks", "pain", "cramping"),
            "escalation_clues": _match_line(lines, "fever", "heavy bleeding", "severe pain", "reduced movement", "vision", "swelling", "persistent vomiting"),
        },
        slot_sources={"trimester_context": trimester_source},
        raw_lines=lines,
    )


def _extract_hormone_evidence(
    lines: tuple[str, ...],
    values: dict[str, Any],
    pair_lookup: dict[str, str],
    *,
    problem_key: str,
) -> ConditionEvidence:
    medicine, medicine_source = _medicine_choice(values, pair_lookup, lines, "metformin", "inositol", "birth control", "progesterone", "supplement")
    timing, timing_source = _timing_choice(
        values,
        pair_lookup,
        lines,
        ("after", "breakfast"),
        ("after", "dinner"),
        ("once", "daily"),
        ("twice", "daily"),
    )
    side_effects, side_effects_source = _side_effect_choice(lines, "nausea", "bloating", "spotting", "headache", "side effect")
    return _build_evidence(
        problem_key,
        symptom_slots={
            "cycle_pattern": _match_line(lines, "cycle", "period", "irregular", "delay", "missed period", "heavy flow"),
            "skin_hair_change": _match_line(lines, "acne", "hair fall", "facial hair", "hair growth", "oily skin"),
            "weight_cravings": _match_line(lines, "cravings", "weight gain", "weight", "sugar craving", "binge"),
            "mood_sleep_context": _match_line(lines, "mood", "sleep", "stress", "insomnia", "irritable", "fatigue"),
        },
        medicine=medicine,
        medicine_source=medicine_source,
        timing=timing,
        timing_source=timing_source,
        side_effects=side_effects,
        side_effects_source=side_effects_source,
        raw_lines=lines,
    )


def _extract_womens_wellness_evidence(
    lines: tuple[str, ...],
    values: dict[str, Any],
    pair_lookup: dict[str, str],
) -> ConditionEvidence:
    return _build_evidence(
        "women",
        symptom_slots={
            "cycle_symptom": _match_line(lines, "period pain", "heavy flow", "spotting", "missed period", "irregular cycle", "cramps"),
            "daily_impact": _match_line(lines, "missed work", "fatigue", "sleep", "unable to function", "tired all day", "bed rest"),
            "associated_symptom": _match_line(lines, "headache", "bloating", "breast pain", "acne", "back pain", "mood"),
            "escalation_cue": _match_line(lines, "soaking pads", "fainting", "severe pain", "large clots", "heavy bleeding", "persistent irregularity"),
        },
        medicine=(
            _string_value(values.get("medicine"))
            or _string_value(values.get("medicines"))
            or _lookup_pair("Medicine", pair_lookup)
            or _match_line(lines, "iron", "pain killer", "tranexamic", "birth control", "supplement")
        ),
        timing=(
            _string_value(values.get("medicine_timing"))
            or _lookup_pair("Timing", pair_lookup)
            or _match_line(lines, ("during", "period"), ("twice", "daily"), ("after", "food"))
        ),
        side_effects=_match_line(lines, "nausea", "constipation", "headache", "drowsy", "spotting"),
        raw_lines=lines,
    )


def _extract_thyroid_evidence(
    lines: tuple[str, ...],
    values: dict[str, Any],
    pair_lookup: dict[str, str],
) -> ConditionEvidence:
    return _build_evidence(
        "thyroid",
        symptom_slots={
            "energy_fatigue": _match_line(lines, "fatigue", "tired", "low energy", "sluggish", "sleepy"),
            "weight_bowel_change": _match_line(lines, "weight gain", "weight loss", "constipation", "loose stool", "bowel"),
            "hair_skin_temperature_clues": _match_line(lines, "hair fall", "dry skin", "cold", "heat intolerance", "sweating"),
            "medication_effect": _match_line(lines, "levothyroxine", "thyroxine", "empty stomach", "missed thyroid dose"),
        },
        medicine=(
            _string_value(values.get("medicine"))
            or _string_value(values.get("medicines"))
            or _lookup_pair("Medicine", pair_lookup)
            or _match_line(lines, "levothyroxine", "thyroxine")
        ),
        timing=(
            _string_value(values.get("medicine_timing"))
            or _lookup_pair("Timing", pair_lookup)
            or _match_line(lines, "empty stomach", ("before", "breakfast"), ("30", "minutes"))
        ),
        side_effects=_match_line(lines, "palpitations", "anxiety", "tremor", "overheating", "dizziness"),
        raw_lines=lines,
    )


def _extract_heart_evidence(
    lines: tuple[str, ...],
    values: dict[str, Any],
    pair_lookup: dict[str, str],
) -> ConditionEvidence:
    return _build_evidence(
        "heart",
        symptom_slots={
            "primary_cardiac_symptom": _match_line(lines, "chest pain", "chest pressure", "breathlessness", "shortness of breath", "palpitations"),
            "effort_relationship": _match_line(lines, "stairs", "walking", "exertion", "activity", "rest"),
            "trigger_relief_pattern": _match_line(lines, "relieved", "rest", "after walking", "after climbing", "worse with"),
            "urgent_review_clues": _match_line(lines, "sweating", "radiating", "radiation", "fainting", "dizziness", "progressive breathlessness"),
        },
        medicine=(
            _string_value(values.get("medicine"))
            or _string_value(values.get("medicines"))
            or _lookup_pair("Medicine", pair_lookup)
            or _match_line(lines, "aspirin", "statin", "bp medicine", "nitroglycerin")
        ),
        timing=(
            _string_value(values.get("medicine_timing"))
            or _lookup_pair("Timing", pair_lookup)
            or _match_line(lines, ("morning", "medicine"), ("night", "medicine"), ("before", "walk"))
        ),
        side_effects=_match_line(lines, "dizziness", "swelling", "cough", "weakness", "palpitations"),
        raw_lines=lines,
    )


def _extract_postpartum_evidence(
    lines: tuple[str, ...],
    values: dict[str, Any],
    pair_lookup: dict[str, str],
) -> ConditionEvidence:
    return _build_evidence(
        "postpartum",
        symptom_slots={
            "recovery_symptom": _match_line(lines, "bleeding", "wound pain", "fever", "stitches", "urination", "clots"),
            "mood_bonding": _match_line(lines, "crying", "panic", "bonding", "overwhelmed", "hopeless", "anxious"),
            "feeding_breast_issues": _match_line(lines, "breast pain", "engorgement", "feeding", "latch", "milk", "nipple"),
            "safety_concern": _match_line(lines, "heavy bleeding", "fever", "suicidal", "self harm", "chest pain", "breathless"),
        },
        medicine=(
            _string_value(values.get("medicine"))
            or _string_value(values.get("medicines"))
            or _lookup_pair("Medicine", pair_lookup)
            or _match_line(lines, "iron", "pain killer", "antibiotic", "supplement")
        ),
        timing=(
            _string_value(values.get("medicine_timing"))
            or _lookup_pair("Timing", pair_lookup)
            or _match_line(lines, ("after", "food"), ("morning",), ("night",))
        ),
        side_effects=_match_line(lines, "drowsy", "constipation", "nausea", "rash", "worsening pain"),
        raw_lines=lines,
    )


def _extract_digestive_evidence(
    lines: tuple[str, ...],
    values: dict[str, Any],
    pair_lookup: dict[str, str],
) -> ConditionEvidence:
    return _build_evidence(
        "digestive",
        symptom_slots={
            "main_gi_symptom": _match_line(lines, "bloating", "reflux", "burning", "acidity", "gas", "abdominal pain"),
            "timing_after_food": _match_line(lines, ("after", "meal"), ("after", "eating"), ("late", "night"), ("after", "spicy")),
            "bowel_pattern": _match_line(lines, "constipation", "diarrhea", "loose stool", "hard stool", "urgency"),
            "alarm_symptoms": _match_line(lines, "blood", "vomiting", "weight loss", "severe pain", "black stool", "persistent fever"),
        },
        medicine=(
            _string_value(values.get("medicine"))
            or _string_value(values.get("medicines"))
            or _lookup_pair("Medicine", pair_lookup)
            or _match_line(lines, "antacid", "ppi", "pantoprazole", "omeprazole", "digestive enzyme")
        ),
        timing=(
            _string_value(values.get("medicine_timing"))
            or _lookup_pair("Timing", pair_lookup)
            or _match_line(lines, ("before", "food"), ("after", "food"), ("morning", "empty"))
        ),
        side_effects=_match_line(lines, "nausea", "diarrhea", "constipation", "bloating", "worsening reflux"),
        raw_lines=lines,
    )


def _extract_sleep_evidence(
    lines: tuple[str, ...],
    values: dict[str, Any],
    pair_lookup: dict[str, str],
) -> ConditionEvidence:
    return _build_evidence(
        "sleep",
        symptom_slots={
            "sleep_schedule": _match_line(lines, "sleep at", "bedtime", "wake time", "1 am", "late sleep", "shift"),
            "night_disruption": _match_line(lines, "wake", "snore", "apnea", "restless", "waking", "3 times"),
            "behavior_trigger": _match_line(lines, "coffee", "caffeine", "screen", "late meal", "stress", "phone"),
            "daytime_impact": _match_line(lines, "sleepy", "daytime fatigue", "low focus", "headache", "4 hours", "tired all day"),
        },
        medicine=(
            _string_value(values.get("medicine"))
            or _string_value(values.get("medicines"))
            or _lookup_pair("Medicine", pair_lookup)
            or _match_line(lines, "melatonin", "sleep medicine", "clonazepam", "zolpidem")
        ),
        timing=(
            _string_value(values.get("medicine_timing"))
            or _lookup_pair("Timing", pair_lookup)
            or _match_line(lines, ("before", "bed"), ("bedtime",), ("30", "minutes"))
        ),
        side_effects=_match_line(lines, "groggy", "drowsy", "hangover", "nightmares", "dependency"),
        raw_lines=lines,
    )


def _extract_stress_mood_evidence(
    lines: tuple[str, ...],
    values: dict[str, Any],
    pair_lookup: dict[str, str],
) -> ConditionEvidence:
    return _build_evidence(
        "mood",
        symptom_slots={
            "mood_state": _match_line(lines, "anxiety", "anxious", "low mood", "depressed", "irritable", "overwhelmed", "panic"),
            "trigger_pattern": _match_line(lines, "trigger", "stress", "workload", "conflict", "skipped meals", "late night", "overload"),
            "body_routine_impact": _match_line(lines, "sleeping", "sleep", "appetite", "energy", "fatigue", "4 hours"),
            "safety_concern": _match_line(lines, "hopeless", "self harm", "suicidal", "unsafe", "cannot function", "panic attack"),
        },
        medicine=(
            _string_value(values.get("medicine"))
            or _string_value(values.get("medicines"))
            or _lookup_pair("Medicine", pair_lookup)
            or _match_line(lines, "ssri", "antidepressant", "anti anxiety", "sertraline", "escitalopram")
        ),
        timing=(
            _string_value(values.get("medicine_timing"))
            or _lookup_pair("Timing", pair_lookup)
            or _match_line(lines, ("bedtime",), ("morning",), ("after", "food"))
        ),
        side_effects=_match_line(lines, "drowsy", "nausea", "restless", "headache", "side effect"),
        raw_lines=lines,
    )


def _extract_fitness_evidence(
    lines: tuple[str, ...],
    values: dict[str, Any],
    pair_lookup: dict[str, str],
) -> ConditionEvidence:
    return _build_evidence(
        "fitness",
        symptom_slots={
            "current_training_load": _match_line(lines, "workout", "cardio", "steps", "strength", "training", "squats"),
            "pain_injury_signal": _match_line(lines, "knee pain", "back pain", "injury", "shoulder pain", "ankle pain"),
            "recovery_burden": _match_line(lines, "soreness", "sleep", "fatigue", "recovery", "2 days"),
            "progression_blocker": _match_line(lines, "skipped warmup", "no time", "breathless", "form breakdown", "fear"),
        },
        medicine=(
            _string_value(values.get("medicine"))
            or _string_value(values.get("medicines"))
            or _lookup_pair("Medicine", pair_lookup)
            or _match_line(lines, "pain killer", "spray", "muscle relaxant", "supplement")
        ),
        timing=(
            _string_value(values.get("medicine_timing"))
            or _lookup_pair("Timing", pair_lookup)
            or _match_line(lines, ("before", "workout"), ("after", "workout"), ("night",))
        ),
        side_effects=_match_line(lines, "drowsy", "stomach upset", "worsening pain", "cramps"),
        raw_lines=lines,
    )


def _extract_skin_hair_evidence(
    lines: tuple[str, ...],
    values: dict[str, Any],
    pair_lookup: dict[str, str],
) -> ConditionEvidence:
    return _build_evidence(
        "skin",
        symptom_slots={
            "primary_change": _match_line(lines, "acne", "rash", "itching", "hair fall", "pigmentation", "dandruff"),
            "pattern_and_spread": _match_line(lines, "spreading", "face", "scalp", "patches", "recurring", "worsens"),
            "possible_trigger": _match_line(lines, "shampoo", "cream", "stress", "food", "periods", "weather"),
            "escalation_cue": _match_line(lines, "infection", "pus", "rapid hair loss", "bleeding", "painful rash"),
        },
        medicine=(
            _string_value(values.get("medicine"))
            or _string_value(values.get("medicines"))
            or _lookup_pair("Medicine", pair_lookup)
            or _match_line(lines, "minoxidil", "biotin", "ketoconazole", "ointment", "serum")
        ),
        timing=(
            _string_value(values.get("medicine_timing"))
            or _lookup_pair("Timing", pair_lookup)
            or _match_line(lines, ("twice", "daily"), ("night",), ("after", "wash"))
        ),
        side_effects=_match_line(lines, "irritation", "dryness", "itching", "rash", "shedding"),
        raw_lines=lines,
    )


def _extract_general_evidence(
    lines: tuple[str, ...],
    values: dict[str, Any],
    pair_lookup: dict[str, str],
) -> ConditionEvidence:
    return _build_evidence(
        "general",
        symptom_slots={
            "primary_concern": _match_line(lines, "fatigue", "pain", "weakness", "bloating", "headache", "stress"),
            "routine_pattern": _match_line(lines, "irregular meals", "hydration", "sedentary", "late dinner", "exercise"),
            "sleep_stress_context": _match_line(lines, "poor sleep", "stress at work", "anxiety", "late night", "sleep"),
            "safety_clue": _match_line(lines, "fainting", "chest pain", "fever", "bleeding", "persistent vomiting", "shortness of breath"),
        },
        medicine=(
            _string_value(values.get("medicine"))
            or _string_value(values.get("medicines"))
            or _lookup_pair("Medicine", pair_lookup)
            or _match_line(lines, "vitamin", "supplement", "tablet", "capsule", "medicine")
        ),
        timing=(
            _string_value(values.get("medicine_timing"))
            or _lookup_pair("Timing", pair_lookup)
            or _match_line(lines, ("morning",), ("night",), ("after", "food"))
        ),
        side_effects=_match_line(lines, "nausea", "dizziness", "constipation", "rash", "headache"),
        raw_lines=lines,
    )


def _extract_senior_evidence(
    lines: tuple[str, ...],
    values: dict[str, Any],
    pair_lookup: dict[str, str],
) -> ConditionEvidence:
    return _build_evidence(
        "senior",
        symptom_slots={
            "mobility_falls_risk": _match_line(lines, "fall", "nearly fell", "unsteady", "walker", "mobility", "bathroom"),
            "confusion_dizziness": _match_line(lines, "dizzy", "confusion", "memory", "forgetful", "lightheaded"),
            "meals_hydration": _match_line(lines, "poor appetite", "not drinking", "dehydration", "skipped meals", "low intake"),
            "medicine_caregiver_context": _match_line(lines, "caregiver", "missed dose", "morning pills", "evening dose", "organizer"),
        },
        medicine=(
            _string_value(values.get("medicine"))
            or _string_value(values.get("medicines"))
            or _lookup_pair("Medicine", pair_lookup)
            or _match_line(lines, "bp medicine", "diabetes medicine", "blood thinner", "pain medicine")
        ),
        timing=(
            _string_value(values.get("medicine_timing"))
            or _lookup_pair("Timing", pair_lookup)
            or _match_line(lines, ("morning", "pills"), ("evening", "dose"), ("after", "breakfast"))
        ),
        side_effects=_match_line(lines, "dizzy", "confusion", "sleepy", "constipation", "weakness"),
        raw_lines=lines,
    )


def _extract_sexual_health_evidence(
    lines: tuple[str, ...],
    values: dict[str, Any],
    pair_lookup: dict[str, str],
) -> ConditionEvidence:
    medicine, medicine_source = _medicine_choice(values, pair_lookup, lines, "azithromycin", "doxycycline", "fluconazole", "antibiotic", "self treatment")
    timing, timing_source = _timing_choice(
        values,
        pair_lookup,
        lines,
        ("after", "food"),
        ("once", "daily"),
        ("twice", "daily"),
        ("for", "days"),
    )
    side_effects, side_effects_source = _side_effect_choice(lines, "nausea", "rash", "worsening pain", "fever", "persistent discharge", "vomiting")
    return _build_evidence(
        "sexual",
        symptom_slots={
            "main_symptom": _match_line(lines, "burning", "discharge", "itching", "painful sex", "ulcer", "rash", "odor"),
            "timing_exposure": _match_line(lines, "unprotected", "after sex", "new partner", "partner", "exposure", "condom"),
            "pain_bleeding_discharge": _match_line(lines, "bleeding", "spotting", "pain", "pelvic pain", "discharge", "burning urination"),
            "pregnancy_sti_risk": _match_line(lines, "missed period", "pregnancy", "sti", "std", "testing", "exposure"),
        },
        medicine=medicine,
        medicine_source=medicine_source,
        timing=timing,
        timing_source=timing_source,
        side_effects=side_effects,
        side_effects_source=side_effects_source,
        raw_lines=lines,
    )


def _extract_autoimmune_evidence(
    lines: tuple[str, ...],
    values: dict[str, Any],
    pair_lookup: dict[str, str],
) -> ConditionEvidence:
    return _build_evidence(
        "autoimmune",
        symptom_slots={
            "pain_swelling": _match_line(lines, "joint pain", "swelling", "stiffness", "hands", "knees", "flare"),
            "fatigue_burden": _match_line(lines, "fatigue", "exhausted", "low energy", "cannot function", "bed rest"),
            "flare_trigger": _match_line(lines, "stress", "infection", "missed medicine", "overexertion", "weather"),
            "escalation_cue": _match_line(lines, "fever", "weakness", "progressive swelling", "reduced movement", "shortness of breath"),
        },
        medicine=(
            _string_value(values.get("medicine"))
            or _string_value(values.get("medicines"))
            or _lookup_pair("Medicine", pair_lookup)
            or _match_line(lines, "steroid", "methotrexate", "hydroxychloroquine", "immunosuppressant")
        ),
        timing=(
            _string_value(values.get("medicine_timing"))
            or _lookup_pair("Timing", pair_lookup)
            or _match_line(lines, ("weekly",), ("after", "food"), ("morning",), ("night",))
        ),
        side_effects=_match_line(lines, "nausea", "mouth ulcers", "infection", "rash", "stomach upset"),
        raw_lines=lines,
    )


def _extract_cholesterol_evidence(
    lines: tuple[str, ...],
    values: dict[str, Any],
    pair_lookup: dict[str, str],
) -> ConditionEvidence:
    return _build_evidence(
        "cholesterol",
        symptom_slots={
            "lipid_lab_context": _match_line(lines, "ldl", "triglycerides", "lipid", "cholesterol", "hdl"),
            "food_risk_pattern": _match_line(lines, "fried", "bakery", "red meat", "takeaway", "butter", "ghee"),
            "activity_weight_context": _match_line(lines, "walk", "exercise", "sedentary", "weight gain", "waist"),
            "family_cardiovascular_risk": _match_line(lines, "father", "mother", "family history", "heart disease", "stroke"),
        },
        medicine=(
            _string_value(values.get("medicine"))
            or _string_value(values.get("medicines"))
            or _lookup_pair("Medicine", pair_lookup)
            or _match_line(lines, "statin", "atorvastatin", "rosuvastatin", "ezetimibe")
        ),
        timing=(
            _string_value(values.get("medicine_timing"))
            or _lookup_pair("Timing", pair_lookup)
            or _match_line(lines, ("night",), ("after", "dinner"), ("bedtime",))
        ),
        side_effects=_match_line(lines, "muscle pain", "weakness", "cramps", "stomach upset", "headache"),
        raw_lines=lines,
    )


def _extract_habit_evidence(
    lines: tuple[str, ...],
    values: dict[str, Any],
    pair_lookup: dict[str, str],
) -> ConditionEvidence:
    return _build_evidence(
        "habit",
        symptom_slots={
            "trigger": _match_line(lines, "when stressed", "11 pm", "after work", "bored", "lonely", "trigger"),
            "current_loop": _match_line(lines, "scrolling", "snacking", "smoking", "drinking", "doomscrolling", "habit"),
            "friction_blocker": _match_line(lines, "shoes are not ready", "no time", "forgot", "phone nearby", "too hard"),
            "escalation_relapse_risk": _match_line(lines, "binge", "all night", "unsafe", "panic", "cannot stop"),
        },
        medicine=(
            _string_value(values.get("medicine"))
            or _string_value(values.get("medicines"))
            or _lookup_pair("Medicine", pair_lookup)
            or _match_line(lines, "nicotine patch", "nicotine gum", "craving medicine", "supplement")
        ),
        timing=(
            _string_value(values.get("medicine_timing"))
            or _lookup_pair("Timing", pair_lookup)
            or _match_line(lines, ("morning",), ("after", "meal"), ("at", "night"))
        ),
        side_effects=_match_line(lines, "headache", "nausea", "vivid dreams", "irritability", "rash"),
        raw_lines=lines,
    )


def _lookup_pair(label: str, pairs: dict[str, str]) -> str | None:
    direct = pairs.get(_normalize(label))
    if direct:
        return direct
    normalized_label = _normalize(label)
    for key, value in pairs.items():
        if normalized_label in key or key in normalized_label:
            return value
    return None


def _summary_sentences(sections: tuple[Any, ...]) -> tuple[str, ...]:
    rows: list[str] = []
    for section in sections:
        rows.extend(getattr(section, "body", ()))
        rows.extend(getattr(section, "bullets", ()))
    return _unique(rows)


def _skip_dashboard_key(key: str) -> bool:
    return key in {
        "score",
        "health_score",
        "daily_score",
        "weight_score",
        "metric_value",
        "metric_unit",
        "full_transcript_saved",
        "transcript_message_count",
    }


def _humanize_key(value: str) -> str:
    words = re.sub(r"[_-]+", " ", str(value)).strip()
    return " ".join(word.capitalize() for word in words.split())


def _string_value(value: Any) -> str:
    if value is None:
        return ""
    if isinstance(value, bool):
        return "Yes" if value else "No"
    if isinstance(value, (list, tuple, set)):
        rows = [_clean_text(item).strip() for item in value if _clean_text(item).strip()]
        return ", ".join(rows)
    if isinstance(value, dict):
        rows = []
        for key, item in value.items():
            clean_item = _clean_text(item).strip()
            if not clean_item:
                continue
            rows.append(f"{_humanize_key(str(key))}: {clean_item}")
        return ", ".join(rows)
    return _clean_text(value).strip()


def _normalize(value: str) -> str:
    return "".join(ch for ch in _clean_text(value).lower() if ch.isalnum())


def _slot_name(value: str) -> str:
    return re.sub(r"[^a-z0-9]+", "_", _clean_text(value).lower()).strip("_")


def _unique(items: Iterable[str]) -> tuple[str, ...]:
    seen: set[str] = set()
    rows: list[str] = []
    for item in items:
        clean = _clean_text(item).strip()
        if not clean:
            continue
        key = clean.lower()
        if key in seen:
            continue
        seen.add(key)
        rows.append(clean)
    return tuple(rows)


def _clean_text(value: Any) -> str:
    text = str(value or "")
    replacements = {
        "\ufeff": "",
        "\u2013": "-",
        "\u2014": "-",
        "\u2018": "'",
        "\u2019": "'",
        "\u201c": '"',
        "\u201d": '"',
        "\u2022": "-",
        "\u00a0": " ",
    }
    for old, new in replacements.items():
        text = text.replace(old, new)
    return text
