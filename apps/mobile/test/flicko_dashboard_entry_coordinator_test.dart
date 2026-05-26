import 'package:flutter_test/flutter_test.dart';

import 'package:flicko_health/features/dashboard/flicko_dashboard_entry_coordinator.dart';

void main() {
  const coordinator = FlickoDashboardEntryCoordinator();

  FlickoDashboardEntrySnapshot snapshot({
    bool hasProfile = false,
    bool shouldOpenDashboard = false,
    bool safetyConsentAccepted = false,
    bool intakeCompleted = false,
    bool backendProfileIntakeCompleted = false,
    String lastAiCallCompletedAt = '',
    int callMemoryCount = 0,
    int reportCount = 0,
    int savedReminderCount = 0,
    int careTaskCount = 0,
    int healthLogCount = 0,
    int mealAnalysisCount = 0,
    int safetyEventCount = 0,
    int chatHistoryCount = 0,
    int reminderLineCount = 0,
    int dashboardNoteCount = 0,
    int backendDashboardSummaryCount = 0,
  }) {
    return FlickoDashboardEntrySnapshot(
      hasProfile: hasProfile,
      shouldOpenDashboard: shouldOpenDashboard,
      safetyConsentAccepted: safetyConsentAccepted,
      intakeCompleted: intakeCompleted,
      backendProfileIntakeCompleted: backendProfileIntakeCompleted,
      lastAiCallCompletedAt: lastAiCallCompletedAt,
      callMemoryCount: callMemoryCount,
      reportCount: reportCount,
      savedReminderCount: savedReminderCount,
      careTaskCount: careTaskCount,
      healthLogCount: healthLogCount,
      mealAnalysisCount: mealAnalysisCount,
      safetyEventCount: safetyEventCount,
      chatHistoryCount: chatHistoryCount,
      reminderLineCount: reminderLineCount,
      dashboardNoteCount: dashboardNoteCount,
      backendDashboardSummaryCount: backendDashboardSummaryCount,
    );
  }

  group('FlickoDashboardEntryCoordinator', () {
    test('detects completed AI setup from call or intake signals', () {
      expect(
        coordinator.hasCompletedAiSetupSignal(
          snapshot(lastAiCallCompletedAt: '2026-05-22T09:00:00Z'),
        ),
        true,
      );
      expect(
        coordinator.hasCompletedAiSetupSignal(snapshot(callMemoryCount: 1)),
        true,
      );
      expect(
        coordinator.hasCompletedAiSetupSignal(
          snapshot(backendProfileIntakeCompleted: true),
        ),
        true,
      );
      expect(coordinator.hasCompletedAiSetupSignal(snapshot()), false);
    });

    test(
      'opens dashboard for old user with real history even without consent flag',
      () {
        final oldUser = snapshot(
          hasProfile: true,
          savedReminderCount: 1,
          safetyConsentAccepted: false,
        );

        expect(coordinator.hasReturningUserHistory(oldUser), true);
        expect(coordinator.shouldOpenDashboardEntry(oldUser), true);
        expect(
          coordinator.authenticatedTarget(oldUser),
          FlickoDashboardEntryTarget.dashboard,
        );
      },
    );

    test('routes profiled but unfinished user to consent', () {
      final pendingConsent = snapshot(
        hasProfile: true,
        safetyConsentAccepted: false,
      );

      expect(
        coordinator.initialTarget(pendingConsent),
        FlickoDashboardEntryTarget.consent,
      );
      expect(
        coordinator.authenticatedTarget(pendingConsent),
        FlickoDashboardEntryTarget.consent,
      );
    });

    test('routes new authenticated user to problem selection', () {
      final freshUser = snapshot();

      expect(
        coordinator.authenticatedTarget(freshUser),
        FlickoDashboardEntryTarget.problemSelection,
      );
      expect(
        coordinator.initialTarget(freshUser),
        FlickoDashboardEntryTarget.onboarding,
      );
    });
  });
}
