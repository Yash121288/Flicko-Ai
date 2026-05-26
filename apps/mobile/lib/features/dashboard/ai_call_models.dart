import '../management/flicko_care_task.dart';
import '../meals/meal_analysis_entry.dart';
import 'ai_call_memory.dart';

enum AiCallInviteReason {
  setupIntake,
  dailyRoutine,
  missedMealPhoto,
  missedCareTask,
  notification,
}

extension AiCallInviteReasonLabel on AiCallInviteReason {
  String get title => switch (this) {
    AiCallInviteReason.setupIntake => 'Health setup call',
    AiCallInviteReason.dailyRoutine => 'Daily routine call',
    AiCallInviteReason.missedMealPhoto => 'Meal photo follow-up',
    AiCallInviteReason.missedCareTask => 'Care task follow-up',
    AiCallInviteReason.notification => 'Flicko health call',
  };

  String get payloadKey => switch (this) {
    AiCallInviteReason.setupIntake => 'setup-intake',
    AiCallInviteReason.dailyRoutine => 'daily-routine',
    AiCallInviteReason.missedMealPhoto => 'missed-meal-photo',
    AiCallInviteReason.missedCareTask => 'missed-care-task',
    AiCallInviteReason.notification => 'notification',
  };

  static AiCallInviteReason fromPayloadKey(String value) {
    return AiCallInviteReason.values.firstWhere(
      (reason) => reason.payloadKey == value.trim(),
      orElse: () => AiCallInviteReason.notification,
    );
  }
}

class AiCallInviteSpec {
  const AiCallInviteSpec({
    required this.reason,
    required this.problemName,
    required this.title,
    required this.subtitle,
    required this.body,
    required this.memoryIntent,
    this.focusPoints = const <String>[],
    this.initiatedByUser = false,
  });

  final AiCallInviteReason reason;
  final String problemName;
  final String title;
  final String subtitle;
  final String body;
  final String memoryIntent;
  final List<String> focusPoints;
  final bool initiatedByUser;

  String get payload => 'call-invite:${reason.payloadKey}';

  String payloadFor(DateTime scheduledAt) {
    return '$payload:${scheduledAt.millisecondsSinceEpoch}';
  }

  static AiCallInviteSpec setup({
    required String firstName,
    required String problemName,
    bool initiatedByUser = false,
  }) {
    final name = firstName.trim().isEmpty ? 'there' : firstName.trim();
    return AiCallInviteSpec(
      reason: AiCallInviteReason.setupIntake,
      problemName: problemName,
      title: 'Flicko AI is calling',
      subtitle: '$name, your $problemName setup is ready',
      body:
          'Pick up to share your free time, daily routine, meals, sleep, medicines, and first 7-day goal.',
      memoryIntent:
          'Initial AI call should lead a condition-specific intake using Flicko protocol questions. Flicko asks and explains one step at a time, collects current symptoms/readings, routine, medicines, relevant lab/report values, preferred free call window, meal photo timing, missed-task recovery, and asks once whether the user has a medical/lab report to upload after the call. If user gives a reminder time, confirm with a structured Reminder: HH:MM - title/body line so the app can save it. Keep the exact user time. Do not round it or guess morning/evening. If the user says an ambiguous hour like 9 baje, ask one short clarification question before confirming it. If user gives a daily free-time call window, save it as the future AI call window.',
      focusPoints: const [
        'Preferred daily free time',
        'Meal photo routine',
        'Medical report upload',
        'Important reminders',
        'Weekly report notes',
      ],
      initiatedByUser: initiatedByUser,
    );
  }

  static AiCallInviteSpec dailyRoutine({
    required String firstName,
    required String problemName,
    bool initiatedByUser = false,
  }) {
    final name = firstName.trim().isEmpty ? 'your routine' : firstName.trim();
    return AiCallInviteSpec(
      reason: AiCallInviteReason.dailyRoutine,
      problemName: problemName,
      title: 'Daily Flicko check-in',
      subtitle: 'Quick routine call for $name',
      body:
          'Pick up so Flicko can update meals, sleep, tasks, reminders, and this week\'s report.',
      memoryIntent:
          'Daily call should update routine adherence, missed items, next reminder timing, and report-ready progress notes. Start from saved memory instead of repeating onboarding. Open with one short continuity line, then ask whether the current reminder or plan worked properly and whether any new problem happened today. The opening should feel fresh each day and naturally mention that this call happened at the user\'s agreed reminder time when that context exists. Ask only one broad follow-up question first. Only ask reminder or call timing details if the user says the reminder failed, felt inconvenient, was missed, or they want a change. If context already shows a confirmed reminder time, do not ask for that same time again unless the user wants to change it. Use structured Reminder: HH:MM - title/body lines only for real user-approved reminders. Keep the exact user time. Do not round it or guess morning/evening. If the user says an ambiguous hour like 9 baje, ask one short clarification question before confirming it.',
      focusPoints: const [
        'Today\'s meals',
        'Sleep and stress',
        'Task progress',
        'Tomorrow\'s plan',
      ],
      initiatedByUser: initiatedByUser,
    );
  }

  static AiCallInviteSpec missedMeal({
    required String firstName,
    required String problemName,
  }) {
    final name = firstName.trim().isEmpty ? 'your meal' : firstName.trim();
    return AiCallInviteSpec(
      reason: AiCallInviteReason.missedMealPhoto,
      problemName: problemName,
      title: 'Meal photo missed',
      subtitle: 'Flicko wants to check $name\'s meal',
      body:
          'Pick up if you missed a meal photo. Flicko will ask what you ate and update the dashboard/report.',
      memoryIntent:
          'Missed meal call should first ask what problem happened and what the user wants to share about the missed meal. Do not start by asking for reminder timing. After the user explains, collect only the missing meal timing, plate details, hunger, cravings, or blocker. Ask about a stronger meal-photo reminder only if the user says the current reminder was not enough or asks for help. If user agrees, capture the exact time once and confirm with Reminder: HH:MM - Meal photo check. Keep the exact user time. Do not round it or guess morning/evening. If the user says an ambiguous hour like 9 baje, ask one short clarification question before confirming it. Do not create duplicate reminders if one already exists, and do not ask again for details the user already gave clearly.',
      focusPoints: const [
        'Meal timing',
        'Plate details',
        'Food score',
        'Next reminder',
      ],
    );
  }

  static AiCallInviteSpec missedTask({
    required String firstName,
    required String problemName,
    required String taskTitle,
  }) {
    final cleanTask = taskTitle.trim().isEmpty ? 'care task' : taskTitle.trim();
    return AiCallInviteSpec(
      reason: AiCallInviteReason.missedCareTask,
      problemName: problemName,
      title: 'Important task missed',
      subtitle: cleanTask,
      body:
          'Pick up so Flicko can understand what blocked this task and reset the plan without pressure.',
      memoryIntent:
          'Missed task call should first ask what blocked the task and whether any new difficulty happened. Do not jump straight to reminder timing. Capture blocker, preferred recovery time, task priority, and whether reminders need adjustment only after the user explains the problem. Confirm the exact next reminder time only if the user approves or asks for a change. Use Reminder: HH:MM - task title/body for the app parser. Keep the exact user time. Do not round it or guess morning/evening. If the user says an ambiguous hour like 9 baje, ask one short clarification question before confirming it. Avoid duplicate reminders, and do not re-ask details the user already answered clearly.',
      focusPoints: const [
        'Reason missed',
        'Recovery time',
        'Reminder change',
        'Report note',
      ],
    );
  }

  static AiCallInviteSpec fromNotification({
    required String firstName,
    required String problemName,
    required String payload,
  }) {
    final reasonKey = payload.split(':').length > 1
        ? payload.split(':')[1]
        : '';
    final reason = AiCallInviteReasonLabel.fromPayloadKey(reasonKey);
    return switch (reason) {
      AiCallInviteReason.missedMealPhoto => missedMeal(
        firstName: firstName,
        problemName: problemName,
      ),
      AiCallInviteReason.missedCareTask => missedTask(
        firstName: firstName,
        problemName: problemName,
        taskTitle: 'Pending health task',
      ),
      AiCallInviteReason.dailyRoutine => dailyRoutine(
        firstName: firstName,
        problemName: problemName,
      ),
      AiCallInviteReason.setupIntake => setup(
        firstName: firstName,
        problemName: problemName,
      ),
      AiCallInviteReason.notification => dailyRoutine(
        firstName: firstName,
        problemName: problemName,
      ),
    };
  }
}

class AiCallSessionSummary {
  const AiCallSessionSummary({
    required this.problemName,
    required this.reason,
    required this.startedAt,
    required this.endedAt,
    required this.duration,
    required this.inviteMemoryIntent,
    this.inviteSubtitle = '',
    this.memorySummary,
  });

  final String problemName;
  final AiCallInviteReason reason;
  final DateTime startedAt;
  final DateTime endedAt;
  final Duration duration;
  final String inviteMemoryIntent;
  final String inviteSubtitle;
  final HealthCallMemorySummary? memorySummary;

  String get durationLabel {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  String get dashboardNote {
    final structuredNote = memorySummary?.structured.dashboardNote.trim() ?? '';
    if (structuredNote.isNotEmpty) {
      return structuredNote;
    }
    return '${reason.title} completed for $problemName. Duration $durationLabel. Flicko should use this call for routine, reminder, task, meal, and report personalization.';
  }

  String get memoryContent {
    final structuredMemory = memorySummary?.memoryContent.trim() ?? '';
    if (structuredMemory.isNotEmpty) {
      return structuredMemory;
    }
    return [
      dashboardNote,
      inviteMemoryIntent,
      'Next calls should ask one question at a time, collect preferred free time, update missed meal/task status, and create weekly report notes.',
    ].join('\n');
  }

  String get chatTimelineText {
    return '''
Live AI call completed.
Problem: $problemName
Reason: ${reason.title}
Duration: $durationLabel
Memory: $inviteMemoryIntent
${memorySummary == null ? '' : '\nStructured summary:\n${memorySummary!.structured.toMarkdown()}\n'}

Use this call as context for the next chat, reminders, dashboard values, and weekly report.
''';
  }

  Map<String, Object> toJson() {
    return {
      'problemName': problemName,
      'reason': reason.payloadKey,
      'startedAt': startedAt.toIso8601String(),
      'endedAt': endedAt.toIso8601String(),
      'durationSeconds': duration.inSeconds,
      'memoryIntent': inviteMemoryIntent,
      'inviteSubtitle': inviteSubtitle,
      'summary': dashboardNote,
      if (memorySummary != null) 'memorySummary': memorySummary!.toJson(),
    };
  }
}

class AiCallTriggerPlanner {
  const AiCallTriggerPlanner._();

  static AiCallInviteSpec? missedFollowUp({
    required String firstName,
    required String problemName,
    required List<MealAnalysisEntry> mealAnalyses,
    required List<FlickoCareTask> careTasks,
    required String lastInviteAt,
    DateTime? now,
  }) {
    final resolvedNow = now ?? DateTime.now();
    if (_isSameDay(DateTime.tryParse(lastInviteAt), resolvedNow)) {
      return null;
    }

    final missedTask = _missedCareTask(careTasks, resolvedNow);
    if (missedTask != null) {
      return AiCallInviteSpec.missedTask(
        firstName: firstName,
        problemName: problemName,
        taskTitle: missedTask.title,
      );
    }

    if (resolvedNow.hour >= 14 &&
        !_hasMealPhotoToday(mealAnalyses, resolvedNow)) {
      return AiCallInviteSpec.missedMeal(
        firstName: firstName,
        problemName: problemName,
      );
    }

    return null;
  }

  static bool _hasMealPhotoToday(
    List<MealAnalysisEntry> mealAnalyses,
    DateTime now,
  ) {
    return mealAnalyses.any((entry) => _isSameDay(entry.createdAt, now));
  }

  static FlickoCareTask? _missedCareTask(
    List<FlickoCareTask> tasks,
    DateTime now,
  ) {
    for (final task in tasks) {
      if (!task.enabled || task.isDoneOn(now)) {
        continue;
      }
      final dueTime = _timeLabelToDate(task.timeLabel, now);
      if (dueTime != null && now.difference(dueTime).inMinutes >= 45) {
        return task;
      }
      if (dueTime == null &&
          (task.type == FlickoCareTaskType.meal ||
              task.type == FlickoCareTaskType.medicine ||
              task.type == FlickoCareTaskType.measurement) &&
          now.hour >= 18) {
        return task;
      }
    }
    return null;
  }

  static DateTime? _timeLabelToDate(String label, DateTime now) {
    final match = RegExp(
      r'^(\d{1,2}):(\d{2})\s*(AM|PM)$',
      caseSensitive: false,
    ).firstMatch(label.trim());
    if (match == null) {
      return null;
    }
    var hour = int.tryParse(match.group(1) ?? '') ?? -1;
    final minute = int.tryParse(match.group(2) ?? '') ?? -1;
    final suffix = (match.group(3) ?? '').toUpperCase();
    if (hour < 1 || hour > 12 || minute < 0 || minute > 59) {
      return null;
    }
    if (suffix == 'PM' && hour != 12) {
      hour += 12;
    }
    if (suffix == 'AM' && hour == 12) {
      hour = 0;
    }
    return DateTime(now.year, now.month, now.day, hour, minute);
  }

  static bool _isSameDay(DateTime? value, DateTime now) {
    if (value == null) {
      return false;
    }
    return value.year == now.year &&
        value.month == now.month &&
        value.day == now.day;
  }
}
