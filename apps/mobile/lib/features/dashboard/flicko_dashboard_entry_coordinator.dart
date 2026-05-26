enum FlickoDashboardEntryTarget {
  onboarding,
  problemSelection,
  consent,
  dashboard,
}

class FlickoDashboardEntrySnapshot {
  const FlickoDashboardEntrySnapshot({
    required this.hasProfile,
    required this.shouldOpenDashboard,
    required this.safetyConsentAccepted,
    required this.intakeCompleted,
    required this.backendProfileIntakeCompleted,
    required this.lastAiCallCompletedAt,
    required this.callMemoryCount,
    required this.reportCount,
    required this.savedReminderCount,
    required this.careTaskCount,
    required this.healthLogCount,
    required this.mealAnalysisCount,
    required this.safetyEventCount,
    required this.chatHistoryCount,
    required this.reminderLineCount,
    required this.dashboardNoteCount,
    required this.backendDashboardSummaryCount,
  });

  final bool hasProfile;
  final bool shouldOpenDashboard;
  final bool safetyConsentAccepted;
  final bool intakeCompleted;
  final bool backendProfileIntakeCompleted;
  final String lastAiCallCompletedAt;
  final int callMemoryCount;
  final int reportCount;
  final int savedReminderCount;
  final int careTaskCount;
  final int healthLogCount;
  final int mealAnalysisCount;
  final int safetyEventCount;
  final int chatHistoryCount;
  final int reminderLineCount;
  final int dashboardNoteCount;
  final int backendDashboardSummaryCount;
}

class FlickoDashboardEntryCoordinator {
  const FlickoDashboardEntryCoordinator();

  bool hasCompletedAiSetupSignal(FlickoDashboardEntrySnapshot snapshot) {
    return snapshot.lastAiCallCompletedAt.trim().isNotEmpty ||
        snapshot.intakeCompleted ||
        snapshot.callMemoryCount > 0 ||
        snapshot.backendProfileIntakeCompleted;
  }

  bool hasReturningUserHistory(FlickoDashboardEntrySnapshot snapshot) {
    return hasCompletedAiSetupSignal(snapshot) ||
        snapshot.reportCount > 0 ||
        snapshot.savedReminderCount > 0 ||
        snapshot.careTaskCount > 0 ||
        snapshot.healthLogCount > 0 ||
        snapshot.mealAnalysisCount > 0 ||
        snapshot.safetyEventCount > 0 ||
        snapshot.chatHistoryCount > 0 ||
        snapshot.reminderLineCount > 0 ||
        snapshot.dashboardNoteCount > 0 ||
        snapshot.backendDashboardSummaryCount > 0;
  }

  bool shouldOpenDashboardEntry(FlickoDashboardEntrySnapshot snapshot) {
    return snapshot.shouldOpenDashboard ||
        (snapshot.hasProfile && hasReturningUserHistory(snapshot));
  }

  FlickoDashboardEntryTarget initialTarget(
    FlickoDashboardEntrySnapshot snapshot,
  ) {
    if (shouldOpenDashboardEntry(snapshot)) {
      return FlickoDashboardEntryTarget.dashboard;
    }
    if (snapshot.hasProfile && !snapshot.safetyConsentAccepted) {
      return FlickoDashboardEntryTarget.consent;
    }
    return FlickoDashboardEntryTarget.onboarding;
  }

  FlickoDashboardEntryTarget authenticatedTarget(
    FlickoDashboardEntrySnapshot snapshot,
  ) {
    if (shouldOpenDashboardEntry(snapshot)) {
      return FlickoDashboardEntryTarget.dashboard;
    }
    if (snapshot.hasProfile) {
      return FlickoDashboardEntryTarget.consent;
    }
    return FlickoDashboardEntryTarget.problemSelection;
  }
}
