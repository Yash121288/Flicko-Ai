import '../logs/health_log_entry.dart';
import '../management/flicko_care_task.dart';
import '../meals/meal_analysis_entry.dart';
import '../reminders/flicko_saved_reminder.dart';

class DiabetesDashboardData {
  const DiabetesDashboardData({
    required this.score,
    required this.scoreStatus,
    required this.metricValue,
    required this.metricUnit,
    required this.metricStatus,
    required this.planFocus,
    required this.planNote,
    required this.checkBody,
    required this.reportBody,
    required this.safetySeverity,
    required this.safetyTitle,
    required this.safetyAction,
  });

  final int score;
  final String scoreStatus;
  final String metricValue;
  final String metricUnit;
  final String metricStatus;
  final String planFocus;
  final String planNote;
  final String checkBody;
  final String reportBody;
  final String safetySeverity;
  final String safetyTitle;
  final String safetyAction;

  static DiabetesDashboardData fromData({
    required int fallbackScore,
    required String fallbackScoreStatus,
    required String fallbackMetricValue,
    required String fallbackMetricUnit,
    required String fallbackMetricStatus,
    required String fallbackPlanFocus,
    required String fallbackPlanNote,
    required String fallbackCheckBody,
    required String fallbackReportBody,
    required List<HealthLogEntry> healthLogs,
    required List<MealAnalysisEntry> mealAnalyses,
    required List<FlickoSavedReminder> savedReminders,
    required List<FlickoCareTask> careTasks,
    required Map<String, Object?> backendSummary,
    DateTime? now,
  }) {
    final effectiveNow = now ?? DateTime.now();
    final glucoseLogs =
        healthLogs.where((log) => log.type == HealthLogType.glucose).toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final latestGlucose = glucoseLogs.isEmpty ? null : glucoseLogs.first;
    final glucoseNumber = _number(latestGlucose?.value);
    final highCount = glucoseLogs
        .where((log) => (_number(log.value) ?? 0) >= 180)
        .length;
    final lowCount = glucoseLogs.where((log) {
      final value = _number(log.value);
      return value != null && value < 70;
    }).length;
    final diabetesMeals = mealAnalyses
        .where((meal) => meal.problemName.toLowerCase().contains('diabetes'))
        .toList();
    final effectiveMeals = diabetesMeals.isEmpty ? mealAnalyses : diabetesMeals;
    final averageMealScore = _averageMealScore(effectiveMeals);
    final highCarbMealCount = effectiveMeals
        .take(10)
        .where(_isHighCarbMeal)
        .length;
    final medicineCount =
        careTasks
            .where((task) => task.type == FlickoCareTaskType.medicine)
            .length +
        savedReminders.where(_looksMedicineReminder).length;
    final pendingMedicineCount = careTasks
        .where(
          (task) =>
              task.enabled &&
              task.type == FlickoCareTaskType.medicine &&
              !task.isDoneOn(effectiveNow),
        )
        .length;
    final localSafety = _diabetesSafety(
      glucose: glucoseNumber,
      highCount: highCount,
      lowCount: lowCount,
      pendingMedicineCount: pendingMedicineCount,
    );
    final safetyTitle = _firstNonEmpty([
      localSafety.title,
      _summaryString(backendSummary, 'diabetes_safety_title'),
    ]);
    final safetyAction = _firstNonEmpty([
      localSafety.action,
      _summaryString(backendSummary, 'diabetes_safety_action'),
    ]);
    final safetySeverity = _firstNonEmpty([
      localSafety.severity,
      _summaryString(backendSummary, 'diabetes_safety_severity'),
    ]);

    final backendScore = _summaryInt(backendSummary, 'diabetes_score');
    final score = backendScore > 0
        ? backendScore
        : _score(
            fallbackScore: fallbackScore,
            glucose: glucoseNumber,
            highCount: highCount,
            lowCount: lowCount,
            averageMealScore: averageMealScore,
            medicineCount: medicineCount,
          );
    final backendMetric = _summaryString(
      backendSummary,
      'diabetes_metric_value',
    );
    final metricValue = latestGlucose?.value.trim().isNotEmpty == true
        ? latestGlucose!.value.trim()
        : backendMetric.isEmpty
        ? fallbackMetricValue
        : backendMetric;
    final metricUnit = latestGlucose?.unit.trim().isNotEmpty == true
        ? latestGlucose!.unit.trim()
        : backendMetric.isEmpty
        ? fallbackMetricUnit
        : _summaryString(backendSummary, 'diabetes_metric_unit');
    final metricStatus = _firstNonEmpty([
      latestGlucose == null
          ? ''
          : _glucoseStatus(glucoseNumber, latestGlucose.title),
      _summaryString(backendSummary, 'diabetes_metric_status'),
      fallbackMetricStatus,
    ]);
    final planFocus = _firstNonEmpty([
      safetyTitle,
      _localPlanFocus(glucoseNumber, lowCount, highCarbMealCount),
      _summaryString(backendSummary, 'diabetes_plan_focus'),
      fallbackPlanFocus,
    ]);
    final planNote = _firstNonEmpty([
      safetyAction,
      _localPlanNote(glucoseNumber, highCount, lowCount, highCarbMealCount),
      _summaryString(backendSummary, 'diabetes_plan_note'),
      fallbackPlanNote,
    ]);
    final checkBody = effectiveMeals.isNotEmpty
        ? _mealCheckBody(effectiveMeals.first)
        : _summaryString(backendSummary, 'latest_meal_summary').isEmpty
        ? fallbackCheckBody
        : _summaryString(backendSummary, 'latest_meal_summary');
    final reportBody = _firstNonEmpty([
      _localReportBody(
        glucose: metricValue,
        hba1c: _summaryString(backendSummary, 'diabetes_hba1c'),
        highCarbMealCount: highCarbMealCount,
        lowCount: lowCount,
        pendingMedicineCount: pendingMedicineCount,
        safetyTitle: safetyTitle,
      ),
      _summaryString(backendSummary, 'diabetes_report_body'),
      fallbackReportBody,
    ]);

    return DiabetesDashboardData(
      score: score,
      scoreStatus: _scoreStatus(
        fallback: fallbackScoreStatus,
        score: score,
        glucose: glucoseNumber,
        lowCount: lowCount,
        highCount: highCount,
        highCarbMealCount: highCarbMealCount,
        safetyTitle: safetyTitle,
      ),
      metricValue: metricValue,
      metricUnit: metricUnit,
      metricStatus: metricStatus,
      planFocus: planFocus,
      planNote: planNote,
      checkBody: checkBody,
      reportBody: reportBody,
      safetySeverity: safetySeverity,
      safetyTitle: safetyTitle,
      safetyAction: safetyAction,
    );
  }
}

class _DiabetesSafetySnapshot {
  const _DiabetesSafetySnapshot({
    required this.severity,
    required this.title,
    required this.action,
  });

  final String severity;
  final String title;
  final String action;
}

int _score({
  required int fallbackScore,
  required double? glucose,
  required int highCount,
  required int lowCount,
  required int averageMealScore,
  required int medicineCount,
}) {
  var score = fallbackScore;
  if (glucose != null) {
    if (glucose < 70) {
      score = 48;
    } else if (glucose <= 140) {
      score = 86;
    } else if (glucose <= 180) {
      score = 76;
    } else if (glucose <= 250) {
      score = 61;
    } else {
      score = 44;
    }
  }
  if (averageMealScore > 0) {
    score = ((score * 0.72) + (averageMealScore * 0.28)).round();
  }
  score -= highCount.clamp(0, 4) * 3;
  score -= lowCount.clamp(0, 3) * 7;
  if (medicineCount > 0) {
    score += 3;
  }
  return score.clamp(0, 100);
}

String _scoreStatus({
  required String fallback,
  required int score,
  required double? glucose,
  required int lowCount,
  required int highCount,
  required int highCarbMealCount,
  required String safetyTitle,
}) {
  if (safetyTitle.trim().isNotEmpty) {
    return safetyTitle.trim();
  }
  if (glucose == null && highCarbMealCount == 0) {
    return fallback;
  }
  if (lowCount > 0 || (glucose != null && glucose < 70)) {
    return 'Low sugar flag, follow your clinician safety plan';
  }
  if (glucose != null && glucose >= 250) {
    return 'Very high sugar flag, review safety plan now';
  }
  if (glucose != null && glucose >= 180) {
    return 'High sugar pattern, tighten meals and follow-up';
  }
  if (highCarbMealCount > 0 || highCount > 0) {
    return 'Stable, reduce high-carb repeats';
  }
  if (score >= 82) {
    return 'Good glucose routine, keep meal timing consistent';
  }
  return 'Needs glucose logs, meal checks, and medicine consistency';
}

String _glucoseStatus(double? value, String title) {
  final lower = title.toLowerCase();
  final context = lower.contains('fast')
      ? 'fasting'
      : lower.contains('post') || lower.contains('pp')
      ? 'post-meal'
      : 'latest';
  if (value == null) {
    return 'Latest saved glucose reading';
  }
  if (value < 70) {
    return 'Low $context glucose - follow hypo plan';
  }
  if (value <= 140) {
    return '${_title(context)} glucose in target range';
  }
  if (value <= 180) {
    return '${_title(context)} glucose mildly high';
  }
  if (value <= 250) {
    return '${_title(context)} glucose high';
  }
  return '${_title(context)} glucose very high';
}

String _localPlanFocus(double? glucose, int lowCount, int highCarbMealCount) {
  if (lowCount > 0 || (glucose != null && glucose < 70)) {
    return 'Low sugar safety check';
  }
  if (glucose != null && glucose >= 180) {
    return 'Post-meal glucose follow-up';
  }
  if (highCarbMealCount > 0) {
    return 'Lower-carb next meal';
  }
  return '';
}

String _localPlanNote(
  double? glucose,
  int highCount,
  int lowCount,
  int highCarbMealCount,
) {
  if (lowCount > 0 || (glucose != null && glucose < 70)) {
    return 'Log symptoms and review medicine timing with doctor.';
  }
  if (glucose != null && glucose >= 180) {
    return 'Compare next 2-hour reading after meal.';
  }
  if (highCarbMealCount > 0) {
    return 'Add protein/fiber, reduce refined-carb portion.';
  }
  if (highCount > 0) {
    return 'Watch repeated high readings by time of day.';
  }
  return '';
}

String _mealCheckBody(MealAnalysisEntry meal) {
  final parts = [
    'Last meal ${meal.score}/100',
    if (meal.carbLoad.trim().isNotEmpty) meal.carbLoad.trim(),
    if (meal.decision.trim().isNotEmpty) meal.decision.trim(),
  ];
  return parts.take(3).join('\n');
}

String _localReportBody({
  required String glucose,
  required String hba1c,
  required int highCarbMealCount,
  required int lowCount,
  required int pendingMedicineCount,
  required String safetyTitle,
}) {
  final lines = <String>[
    if (safetyTitle.trim().isNotEmpty) safetyTitle.trim(),
    if (glucose.trim().isNotEmpty && glucose != '118') 'Glucose $glucose',
    if (hba1c.trim().isNotEmpty && hba1c != 'Not captured yet') 'HbA1c $hba1c',
    if (highCarbMealCount > 0) '$highCarbMealCount carb risks',
    if (lowCount > 0) '$lowCount low-sugar flags',
    if (pendingMedicineCount > 0) '$pendingMedicineCount medicine pending',
  ];
  return lines.take(2).join('\n');
}

_DiabetesSafetySnapshot _diabetesSafety({
  required double? glucose,
  required int highCount,
  required int lowCount,
  required int pendingMedicineCount,
}) {
  if (glucose != null && glucose < 70) {
    return const _DiabetesSafetySnapshot(
      severity: 'urgent',
      title: 'Low sugar safety flag',
      action:
          'Follow your hypo plan now, recheck glucose, and get urgent help if not improving.',
    );
  }
  if (glucose != null && glucose >= 250) {
    return const _DiabetesSafetySnapshot(
      severity: 'urgent',
      title: 'Very high sugar safety flag',
      action:
          'Check your clinician safety plan and get urgent advice for symptoms or persistent high readings.',
    );
  }
  if (highCount >= 3) {
    return const _DiabetesSafetySnapshot(
      severity: 'clinician',
      title: 'Repeated high sugar pattern',
      action:
          'Review meals, medicine timing, and glucose pattern with a clinician.',
    );
  }
  if (lowCount > 0) {
    return const _DiabetesSafetySnapshot(
      severity: 'clinician',
      title: 'Recent low sugar pattern',
      action: 'Review low-sugar symptoms, meal timing, and medicine timing.',
    );
  }
  if (pendingMedicineCount > 0) {
    return const _DiabetesSafetySnapshot(
      severity: 'clinician',
      title: 'Medicine task pending',
      action: 'Confirm whether medicine was taken or intentionally skipped.',
    );
  }
  return const _DiabetesSafetySnapshot(severity: '', title: '', action: '');
}

bool _isHighCarbMeal(MealAnalysisEntry meal) {
  final text = [
    meal.carbLoad,
    meal.decision,
    meal.riskFlags.join(' '),
    meal.detectedFoods.join(' '),
  ].join(' ').toLowerCase();
  return meal.score < 60 ||
      text.contains('high') ||
      text.contains('carb') ||
      text.contains('sugar') ||
      text.contains('rice') ||
      text.contains('sweet');
}

bool _looksMedicineReminder(FlickoSavedReminder reminder) {
  final text = '${reminder.title} ${reminder.body}'.toLowerCase();
  return text.contains('medicine') ||
      text.contains('tablet') ||
      text.contains('metformin') ||
      text.contains('insulin');
}

int _averageMealScore(List<MealAnalysisEntry> meals) {
  final scored = meals.where((meal) => meal.score > 0).take(10).toList();
  if (scored.isEmpty) {
    return 0;
  }
  return (scored.fold<int>(0, (sum, meal) => sum + meal.score) / scored.length)
      .round()
      .clamp(0, 100);
}

double? _number(String? value) {
  final match = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(value ?? '');
  if (match == null) {
    return null;
  }
  return double.tryParse(match.group(1) ?? '');
}

int _summaryInt(Map<String, Object?> summary, String key) {
  final value = summary[key];
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.round();
  }
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

String _summaryString(Map<String, Object?> summary, String key) {
  return summary[key]?.toString().trim() ?? '';
}

String _firstNonEmpty(List<String> values) {
  for (final value in values) {
    if (value.trim().isNotEmpty) {
      return value.trim();
    }
  }
  return '';
}

String _title(String value) {
  if (value.isEmpty) {
    return value;
  }
  return '${value[0].toUpperCase()}${value.substring(1)}';
}
