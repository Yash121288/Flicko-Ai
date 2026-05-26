import '../logs/health_log_entry.dart';
import '../management/flicko_care_task.dart';
import '../meals/meal_analysis_entry.dart';
import '../reminders/flicko_saved_reminder.dart';
import 'diabetes_dashboard_data.dart';

class DashboardLiveInsights {
  const DashboardLiveInsights({
    required this.score,
    required this.scoreStatus,
    required this.metricValue,
    required this.metricUnit,
    required this.metricStatus,
    required this.planFocus,
    required this.planNote,
    required this.checkBody,
    required this.reportBody,
    required this.mealCount,
    required this.averageMealScore,
    required this.highRiskMealCount,
    required this.latestMealSummary,
    required this.latestLogSummary,
    required this.doneCareTaskCount,
    required this.enabledCareTaskCount,
    required this.enabledReminderCount,
    this.safetySeverity = '',
    this.safetyTitle = '',
    this.safetyAction = '',
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
  final int mealCount;
  final int averageMealScore;
  final int highRiskMealCount;
  final String latestMealSummary;
  final String latestLogSummary;
  final int doneCareTaskCount;
  final int enabledCareTaskCount;
  final int enabledReminderCount;
  final String safetySeverity;
  final String safetyTitle;
  final String safetyAction;

  bool get hasSafetyWarning => safetyTitle.trim().isNotEmpty;

  Map<String, Object?> toReportValues() {
    return {
      'score': score,
      'health_score': score,
      'score_status': scoreStatus,
      'live_metric': _valueWithUnit(metricValue, metricUnit),
      'live_metric_status': metricStatus,
      'plan_focus': planFocus,
      'plan_note': planNote,
      'meal_photo_count': mealCount,
      'meal_score_average': averageMealScore,
      'meal_high_risk_count': highRiskMealCount,
      'latest_meal_summary': latestMealSummary,
      'latest_log_summary': latestLogSummary,
      'care_tasks_done_today': doneCareTaskCount,
      'care_tasks_enabled': enabledCareTaskCount,
      'active_local_reminders': enabledReminderCount,
      'safety_severity': safetySeverity,
      'safety_title': safetyTitle,
      'safety_action': safetyAction,
    };
  }

  static DashboardLiveInsights fromData({
    required String problemName,
    required int fallbackScore,
    required String fallbackScoreStatus,
    required String fallbackMetricValue,
    required String fallbackMetricUnit,
    required String fallbackMetricStatus,
    required String fallbackPlanFocus,
    required String fallbackPlanNote,
    required String fallbackCheckBody,
    required String fallbackReportBody,
    List<MealAnalysisEntry> mealAnalyses = const <MealAnalysisEntry>[],
    List<HealthLogEntry> healthLogs = const <HealthLogEntry>[],
    List<FlickoSavedReminder> savedReminders = const <FlickoSavedReminder>[],
    List<FlickoCareTask> careTasks = const <FlickoCareTask>[],
    Map<String, Object?> backendSummary = const <String, Object?>{},
    DateTime? now,
  }) {
    final effectiveNow = now ?? DateTime.now();
    final recentMeals = [...mealAnalyses]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final recentLogs = [...healthLogs]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final enabledTasks = careTasks.where((task) => task.enabled).toList();
    final doneTasks = enabledTasks
        .where((task) => task.isDoneOn(effectiveNow))
        .length;
    final enabledReminderCount = savedReminders
        .where((reminder) => reminder.enabled)
        .length;

    final averageMealScore = _averageMealScore(recentMeals);
    final highRiskMealCount = recentMeals
        .take(10)
        .where((meal) => _isHighRiskMeal(meal))
        .length;
    final backendMealCount = _summaryInt(
      backendSummary,
      'normalized_meal_analysis_count',
    );
    final backendAverageMealScore = _summaryInt(
      backendSummary,
      'normalized_average_meal_score',
    );
    final backendHighRiskMealCount = _summaryInt(
      backendSummary,
      'normalized_high_risk_meal_count',
    );
    final backendReminderCount = _summaryInt(
      backendSummary,
      'normalized_active_reminder_count',
    );
    final backendTaskCount = _summaryInt(
      backendSummary,
      'normalized_active_care_task_count',
    );
    final backendLogCount = _summaryInt(
      backendSummary,
      'normalized_health_log_count',
    );
    final effectiveMealCount = recentMeals.isNotEmpty
        ? recentMeals.length
        : backendMealCount;
    final effectiveAverageMealScore = averageMealScore > 0
        ? averageMealScore
        : backendAverageMealScore;
    final effectiveHighRiskMealCount = highRiskMealCount > 0
        ? highRiskMealCount
        : backendHighRiskMealCount;
    final effectiveReminderCount = enabledReminderCount > 0
        ? enabledReminderCount
        : backendReminderCount;
    final effectiveTaskCount = enabledTasks.isNotEmpty
        ? enabledTasks.length
        : backendTaskCount;
    final effectiveLogCount = recentLogs.isNotEmpty
        ? recentLogs.length
        : backendLogCount;
    final score = _combinedScore(
      fallbackScore: fallbackScore,
      averageMealScore: effectiveAverageMealScore,
      mealCount: effectiveMealCount,
      highRiskMealCount: effectiveHighRiskMealCount,
      doneTasks: doneTasks,
      enabledTasks: effectiveTaskCount,
      enabledReminderCount: effectiveReminderCount,
      recentLogCount: effectiveLogCount,
    );

    final latestMeal = recentMeals.isEmpty ? null : recentMeals.first;
    final metricOverride = _latestMetricForProblem(problemName, recentLogs);
    final backendLatestMealSummary = _summaryString(
      backendSummary,
      'latest_meal_summary',
    );
    final backendLatestLogSummary = _summaryString(
      backendSummary,
      'latest_log_summary',
    );
    final backendLatestLogValue = _summaryString(
      backendSummary,
      'latest_log_value',
    );
    final backendLatestLogTitle = _summaryString(
      backendSummary,
      'latest_log_title',
    );
    final latestLogSummary = recentLogs.isEmpty
        ? _clip(backendLatestLogSummary, 110)
        : _clip(recentLogs.first.compactSummary, 110);
    final latestMealSummary = latestMeal == null
        ? _clip(backendLatestMealSummary, 135)
        : _clip(latestMeal.compactSummary, 135);
    final backendMetricStatus = backendLatestLogTitle.isEmpty
        ? 'Latest saved backend health record'
        : backendLatestLogTitle;
    final diabetesData = problemName.toLowerCase().contains('diabetes')
        ? DiabetesDashboardData.fromData(
            fallbackScore: fallbackScore,
            fallbackScoreStatus: fallbackScoreStatus,
            fallbackMetricValue: fallbackMetricValue,
            fallbackMetricUnit: fallbackMetricUnit,
            fallbackMetricStatus: fallbackMetricStatus,
            fallbackPlanFocus: fallbackPlanFocus,
            fallbackPlanNote: fallbackPlanNote,
            fallbackCheckBody: fallbackCheckBody,
            fallbackReportBody: fallbackReportBody,
            healthLogs: recentLogs,
            mealAnalyses: recentMeals,
            savedReminders: savedReminders,
            careTasks: careTasks,
            backendSummary: backendSummary,
            now: effectiveNow,
          )
        : null;

    return DashboardLiveInsights(
      score: diabetesData?.score ?? score,
      scoreStatus:
          diabetesData?.scoreStatus ??
          _scoreStatus(
            fallbackScoreStatus: fallbackScoreStatus,
            score: score,
            mealCount: effectiveMealCount,
            highRiskMealCount: effectiveHighRiskMealCount,
            enabledTasks: effectiveTaskCount,
            doneTasks: doneTasks,
          ),
      metricValue:
          diabetesData?.metricValue ??
          metricOverride?.value ??
          (backendLatestLogValue.isEmpty
              ? fallbackMetricValue
              : backendLatestLogValue),
      metricUnit:
          diabetesData?.metricUnit ??
          metricOverride?.unit ??
          (backendLatestLogValue.isEmpty ? fallbackMetricUnit : ''),
      metricStatus:
          diabetesData?.metricStatus ??
          metricOverride?.status ??
          (backendLatestLogValue.isEmpty ? null : backendMetricStatus) ??
          _metricStatusFromMeals(
            fallbackMetricStatus,
            effectiveAverageMealScore,
            effectiveMealCount,
          ),
      planFocus:
          diabetesData?.planFocus ??
          _planFocusFromMeal(
            latestMeal,
            _summaryString(backendSummary, 'latest_meal_decision').isEmpty
                ? fallbackPlanFocus
                : _summaryString(backendSummary, 'latest_meal_decision'),
          ),
      planNote:
          diabetesData?.planNote ??
          _planNoteFromMeal(
            latestMeal,
            backendLatestMealSummary.isEmpty
                ? fallbackPlanNote
                : backendLatestMealSummary,
          ),
      checkBody:
          diabetesData?.checkBody ??
          (latestMeal == null
              ? (backendLatestMealSummary.isEmpty
                    ? fallbackCheckBody
                    : backendLatestMealSummary)
              : 'Last scan ${latestMeal.score}/100\n${latestMeal.decision}'),
      reportBody:
          diabetesData?.reportBody ??
          _reportBody(
            fallbackReportBody,
            mealCount: effectiveMealCount,
            averageMealScore: effectiveAverageMealScore,
            highRiskMealCount: effectiveHighRiskMealCount,
            recentLogCount: effectiveLogCount,
          ),
      mealCount: effectiveMealCount,
      averageMealScore: effectiveAverageMealScore,
      highRiskMealCount: effectiveHighRiskMealCount,
      latestMealSummary: latestMealSummary,
      latestLogSummary: latestLogSummary,
      doneCareTaskCount: doneTasks,
      enabledCareTaskCount: effectiveTaskCount,
      enabledReminderCount: effectiveReminderCount,
      safetySeverity: diabetesData?.safetySeverity ?? '',
      safetyTitle: diabetesData?.safetyTitle ?? '',
      safetyAction: diabetesData?.safetyAction ?? '',
    );
  }
}

class _MetricOverride {
  const _MetricOverride({
    required this.value,
    required this.unit,
    required this.status,
  });

  final String value;
  final String unit;
  final String status;
}

int _averageMealScore(List<MealAnalysisEntry> meals) {
  final scored = meals.where((meal) => meal.score > 0).take(10).toList();
  if (scored.isEmpty) {
    return 0;
  }
  final total = scored.fold<int>(0, (sum, meal) => sum + meal.score);
  return (total / scored.length).round().clamp(0, 100);
}

bool _isHighRiskMeal(MealAnalysisEntry meal) {
  final decision = meal.decision.toLowerCase();
  return meal.score < 60 ||
      decision.contains('avoid') ||
      decision.contains('limit') ||
      decision.contains('high') ||
      meal.riskFlags.isNotEmpty;
}

int _combinedScore({
  required int fallbackScore,
  required int averageMealScore,
  required int mealCount,
  required int highRiskMealCount,
  required int doneTasks,
  required int enabledTasks,
  required int enabledReminderCount,
  required int recentLogCount,
}) {
  var score = fallbackScore;
  if (mealCount > 0) {
    score = ((averageMealScore * 0.72) + (fallbackScore * 0.28)).round();
  }
  if (enabledTasks > 0) {
    score += ((doneTasks / enabledTasks) * 7).round();
  }
  if (enabledReminderCount > 0) {
    score += 2;
  }
  if (recentLogCount > 0) {
    score += 2;
  }
  score -= highRiskMealCount.clamp(0, 4) * 3;
  return score.clamp(0, 100);
}

String _scoreStatus({
  required String fallbackScoreStatus,
  required int score,
  required int mealCount,
  required int highRiskMealCount,
  required int enabledTasks,
  required int doneTasks,
}) {
  if (mealCount == 0 && enabledTasks == 0) {
    return fallbackScoreStatus;
  }
  if (score >= 86) {
    return 'Strong day, keep the same meal and routine pattern';
  }
  if (score >= 72) {
    return highRiskMealCount == 0
        ? 'Stable, keep meals and reminders consistent'
        : 'Good, but reduce risky meal repeats';
  }
  if (score >= 55) {
    return doneTasks < enabledTasks
        ? 'Needs task follow-through and better meal consistency'
        : 'Needs cleaner meals and closer follow-up';
  }
  return 'High priority, review symptoms and food choices carefully';
}

String _metricStatusFromMeals(
  String fallback,
  int averageMealScore,
  int mealCount,
) {
  if (mealCount == 0 || averageMealScore == 0) {
    return fallback;
  }
  if (averageMealScore >= 85) {
    return 'Recent meals are strongly aligned';
  }
  if (averageMealScore >= 70) {
    return 'Recent meals are acceptable, improve consistency';
  }
  if (averageMealScore >= 50) {
    return 'Recent meals need portion and timing correction';
  }
  return 'Recent meals need safer choices before repeating';
}

String _planFocusFromMeal(MealAnalysisEntry? meal, String fallback) {
  if (meal == null || meal.recommendations.isEmpty) {
    return fallback;
  }
  return _clip(meal.recommendations.first, 38);
}

String _planNoteFromMeal(MealAnalysisEntry? meal, String fallback) {
  if (meal == null) {
    return fallback;
  }
  final risks = meal.riskFlags.take(2).join(', ');
  if (risks.isNotEmpty) {
    return _clip('Watch: $risks', 58);
  }
  return _clip('Last meal: ${meal.decision}', 58);
}

String _reportBody(
  String fallback, {
  required int mealCount,
  required int averageMealScore,
  required int highRiskMealCount,
  required int recentLogCount,
}) {
  if (mealCount == 0 && recentLogCount == 0) {
    return fallback;
  }
  final lines = <String>[
    if (mealCount > 0) 'Meal avg $averageMealScore/100',
    if (highRiskMealCount > 0) '$highRiskMealCount food risks',
    if (recentLogCount > 0) '$recentLogCount logs saved',
  ];
  return lines.take(2).join('\n');
}

_MetricOverride? _latestMetricForProblem(
  String problemName,
  List<HealthLogEntry> logs,
) {
  final problem = problemName.toLowerCase();
  if (problem.contains('diabetes')) {
    return _metricFromLatestLog(
      logs,
      HealthLogType.glucose,
      status: 'Latest saved glucose reading',
    );
  }
  if (problem.contains('pressure')) {
    return _metricFromLatestLog(
      logs,
      HealthLogType.bloodPressure,
      status: 'Latest saved BP reading',
    );
  }
  if (problem.contains('weight')) {
    return _metricFromLatestLog(
      logs,
      HealthLogType.weight,
      status: 'Latest saved weigh-in',
    );
  }
  if (problem.contains('sleep')) {
    return _metricFromLatestLog(
      logs,
      HealthLogType.sleep,
      status: 'Latest saved sleep log',
    );
  }
  if (problem.contains('stress') || problem.contains('mood')) {
    return _metricFromLatestLog(
      logs,
      HealthLogType.mood,
      status: 'Latest saved mood check',
    );
  }
  if (problem.contains('fitness')) {
    return _metricFromLatestLog(
      logs,
      HealthLogType.steps,
      status: 'Latest saved step count',
    );
  }
  if (problem.contains('heart')) {
    return _metricFromLatestLog(
      logs,
      HealthLogType.activity,
      status: 'Latest saved activity log',
    );
  }
  return null;
}

_MetricOverride? _metricFromLatestLog(
  List<HealthLogEntry> logs,
  HealthLogType type, {
  required String status,
}) {
  for (final log in logs) {
    if (log.type == type && log.value.trim().isNotEmpty) {
      return _MetricOverride(
        value: log.value.trim(),
        unit: log.unit.trim(),
        status: status,
      );
    }
  }
  return null;
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

String _clip(String value, int maxLength) {
  final normalized = value.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (normalized.length <= maxLength) {
    return normalized;
  }
  return '${normalized.substring(0, maxLength - 3)}...';
}

String _valueWithUnit(String value, String unit) {
  final cleanValue = value.trim();
  final cleanUnit = unit.trim();
  if (cleanValue.isEmpty) {
    return '';
  }
  return cleanUnit.isEmpty ? cleanValue : '$cleanValue $cleanUnit';
}
