import '../management/flicko_care_task.dart';
import '../meals/meal_analysis_entry.dart';
import 'ai_call_models.dart';

class FlickoProactiveCallInvitePlan {
  const FlickoProactiveCallInvitePlan({
    required this.spec,
    required this.scheduledAt,
    required this.auditTitle,
    required this.auditContent,
    this.repeatsDaily = false,
  });

  final AiCallInviteSpec spec;
  final DateTime scheduledAt;
  final String auditTitle;
  final String auditContent;
  final bool repeatsDaily;
}

class FlickoScheduledCallInvitePlan {
  const FlickoScheduledCallInvitePlan({
    required this.effectiveScheduledAt,
    required this.payload,
    required this.immediate,
  });

  final DateTime effectiveScheduledAt;
  final String payload;
  final bool immediate;
}

class FlickoRetryCallInvitePlan {
  const FlickoRetryCallInvitePlan({
    required this.spec,
    required this.scheduledAt,
    required this.auditTitle,
    required this.auditContent,
  });

  final AiCallInviteSpec spec;
  final DateTime scheduledAt;
  final String auditTitle;
  final String auditContent;
}

class FlickoCallInviteCoordinator {
  const FlickoCallInviteCoordinator();

  AiCallInviteSpec resumeInviteSpec({
    required String firstName,
    required String problemName,
    required AiCallInviteReason reason,
    required String subtitle,
  }) {
    switch (reason) {
      case AiCallInviteReason.setupIntake:
        return AiCallInviteSpec.setup(
          firstName: firstName,
          problemName: problemName,
        );
      case AiCallInviteReason.dailyRoutine:
      case AiCallInviteReason.notification:
        return AiCallInviteSpec.dailyRoutine(
          firstName: firstName,
          problemName: problemName,
        );
      case AiCallInviteReason.missedMealPhoto:
        return AiCallInviteSpec.missedMeal(
          firstName: firstName,
          problemName: problemName,
        );
      case AiCallInviteReason.missedCareTask:
        return AiCallInviteSpec.missedTask(
          firstName: firstName,
          problemName: problemName,
          taskTitle: subtitle.trim().isEmpty ? 'Pending health task' : subtitle,
        );
    }
  }

  FlickoProactiveCallInvitePlan? proactivePlan({
    required bool shouldOpenDashboardEntry,
    required bool hasReturningUserHistory,
    required bool callInviteRouteOpen,
    required bool liveCallInProgress,
    required Map<String, String> inviteLog,
    required String firstName,
    required String problemName,
    required List<MealAnalysisEntry> mealAnalyses,
    required List<FlickoCareTask> careTasks,
    DateTime? now,
  }) {
    if (!shouldOpenDashboardEntry ||
        callInviteRouteOpen ||
        liveCallInProgress) {
      return null;
    }
    final resolvedNow = now ?? DateTime.now();
    if (!hasReturningUserHistory &&
        lastInviteAt(inviteLog, AiCallInviteReason.setupIntake).isEmpty) {
      return FlickoProactiveCallInvitePlan(
        spec: AiCallInviteSpec.setup(
          firstName: firstName,
          problemName: problemName,
        ),
        scheduledAt: resolvedNow.add(const Duration(minutes: 3)),
        auditTitle: 'First Flicko setup call scheduled',
        auditContent:
            'Flicko will call in 3 minutes to start the structured health intake.',
      );
    }

    final spec = AiCallTriggerPlanner.missedFollowUp(
      firstName: firstName,
      problemName: problemName,
      mealAnalyses: mealAnalyses,
      careTasks: careTasks,
      lastInviteAt: latestInviteAt(inviteLog, const {
        AiCallInviteReason.missedCareTask,
        AiCallInviteReason.missedMealPhoto,
      }),
      now: resolvedNow,
    );
    if (spec == null) {
      return null;
    }
    return FlickoProactiveCallInvitePlan(
      spec: spec,
      scheduledAt: resolvedNow,
      auditTitle: spec.title,
      auditContent: spec.memoryIntent,
    );
  }

  FlickoScheduledCallInvitePlan schedulePlan({
    required AiCallInviteSpec spec,
    required DateTime scheduledAt,
    required bool callInviteRouteOpen,
    required bool liveCallInProgress,
    DateTime? now,
  }) {
    final resolvedNow = now ?? DateTime.now();
    var effectiveScheduledAt = scheduledAt;
    final busyNow = callInviteRouteOpen || liveCallInProgress;
    if (busyNow &&
        !effectiveScheduledAt.isAfter(
          resolvedNow.add(const Duration(minutes: 1)),
        )) {
      effectiveScheduledAt = resolvedNow.add(const Duration(minutes: 12));
    }
    final immediate = !effectiveScheduledAt.isAfter(
      resolvedNow.add(const Duration(seconds: 5)),
    );
    return FlickoScheduledCallInvitePlan(
      effectiveScheduledAt: effectiveScheduledAt,
      payload: spec.payloadFor(effectiveScheduledAt),
      immediate: immediate,
    );
  }

  FlickoRetryCallInvitePlan declinedNotificationRetryPlan(
    AiCallInviteSpec spec, {
    DateTime? now,
  }) {
    final resolvedNow = now ?? DateTime.now();
    return FlickoRetryCallInvitePlan(
      spec: spec,
      scheduledAt: resolvedNow.add(const Duration(minutes: 8)),
      auditTitle: '${spec.title} declined',
      auditContent:
          'User declined the incoming call notification. Flicko will retry once in 8 minutes.',
    );
  }

  FlickoRetryCallInvitePlan declinedInviteRetryPlan(
    AiCallInviteSpec spec, {
    Duration? retryAfter,
    String note = '',
    DateTime? now,
  }) {
    final resolvedNow = now ?? DateTime.now();
    return FlickoRetryCallInvitePlan(
      spec: spec,
      scheduledAt: resolvedNow.add(retryAfter ?? const Duration(minutes: 8)),
      auditTitle: '${spec.title} declined',
      auditContent: note.isEmpty
          ? 'User cut the call. Flicko will retry once in 8 minutes.'
          : note,
    );
  }

  FlickoRetryCallInvitePlan postponedInviteRetryPlan(
    AiCallInviteSpec spec, {
    Duration? retryAfter,
    String note = '',
    DateTime? now,
  }) {
    final resolvedNow = now ?? DateTime.now();
    return FlickoRetryCallInvitePlan(
      spec: spec,
      scheduledAt: resolvedNow.add(retryAfter ?? const Duration(hours: 3)),
      auditTitle: '${spec.title} postponed',
      auditContent: note.isEmpty
          ? 'User is busy. Flicko will call again after 3 hours.'
          : note,
    );
  }

  FlickoRetryCallInvitePlan? busyCallRetryPlan({
    required String userText,
    required String firstName,
    required String problemName,
    DateTime? now,
  }) {
    if (!looksLikeBusyCallResponse(userText)) {
      return null;
    }
    final resolvedNow = now ?? DateTime.now();
    return FlickoRetryCallInvitePlan(
      spec: AiCallInviteSpec.dailyRoutine(
        firstName: firstName,
        problemName: problemName,
      ),
      scheduledAt: resolvedNow.add(const Duration(hours: 3)),
      auditTitle: 'Busy call retry scheduled',
      auditContent:
          'User sounded busy during the AI call. No clear free time was captured, so Flicko will retry after 3 hours.',
    );
  }

  bool looksLikeBusyCallResponse(String text) {
    if (text.trim().isEmpty) {
      return false;
    }
    const signals = <String>[
      'busy',
      'dont call',
      "don't call",
      'not now',
      'call later',
      'later',
      'abhi nahi',
      'abhi nahin',
      'baad me',
      'bad me',
      'free nahi',
      'free nahin',
      'vyast',
      'meeting',
    ];
    return signals.any(text.contains);
  }

  String lastInviteAt(
    Map<String, String> inviteLog,
    AiCallInviteReason reason,
  ) {
    return inviteLog[reason.payloadKey]?.trim() ?? '';
  }

  String lastInvitePayload(
    Map<String, String> inviteLog,
    AiCallInviteReason reason,
  ) {
    return inviteLog['${reason.payloadKey}:payload']?.trim() ?? '';
  }

  String latestInviteAt(
    Map<String, String> inviteLog,
    Set<AiCallInviteReason> reasons,
  ) {
    final values = reasons
        .map((reason) => DateTime.tryParse(lastInviteAt(inviteLog, reason)))
        .whereType<DateTime>()
        .toList();
    if (values.isEmpty) {
      return '';
    }
    values.sort();
    return values.last.toIso8601String();
  }

  Map<String, String> recordInviteLog(
    Map<String, String> inviteLog, {
    required AiCallInviteReason reason,
    required DateTime invitedAt,
    required DateTime scheduledAt,
    required String payload,
  }) {
    return <String, String>{
      ...inviteLog,
      reason.payloadKey: invitedAt.toIso8601String(),
      '${reason.payloadKey}:scheduledAt': scheduledAt.toIso8601String(),
      '${reason.payloadKey}:payload': payload,
    };
  }
}
