import 'package:flutter_test/flutter_test.dart';

import 'package:flicko_health/features/dashboard/ai_call_models.dart';
import 'package:flicko_health/features/dashboard/flicko_call_invite_dispatch_coordinator.dart';

void main() {
  const coordinator = FlickoCallInviteDispatchCoordinator();

  FlickoCallInviteDispatchSnapshot snapshot({
    bool callInviteRouteOpen = false,
    bool liveCallInProgress = false,
    bool canOpenDashboard = true,
    String firstName = 'Kartik',
    String problemName = 'Diabetes',
  }) {
    return FlickoCallInviteDispatchSnapshot(
      callInviteRouteOpen: callInviteRouteOpen,
      liveCallInProgress: liveCallInProgress,
      canOpenDashboard: canOpenDashboard,
      firstName: firstName,
      problemName: problemName,
    );
  }

  group('FlickoCallInviteDispatchCoordinator', () {
    test('ignores unrelated payloads', () {
      final decision = coordinator.decide(
        payload: 'reminder:water',
        snapshot: snapshot(),
      );

      expect(decision.action, FlickoCallInviteDispatchAction.ignore);
    });

    test('cancels active invite payload when call stack is busy', () {
      final decision = coordinator.decide(
        payload: 'call-invite:daily-routine:123',
        snapshot: snapshot(callInviteRouteOpen: true),
      );

      expect(
        decision.action,
        FlickoCallInviteDispatchAction.cancelActiveInvite,
      );
    });

    test('queues valid invite payload when dashboard cannot open yet', () {
      final decision = coordinator.decide(
        payload: 'call-invite:setup-intake:123',
        snapshot: snapshot(canOpenDashboard: false),
      );

      expect(decision.action, FlickoCallInviteDispatchAction.queuePending);
    });

    test('creates declined retry decision from declined payload', () {
      final decision = coordinator.decide(
        payload: 'call-invite-declined:missed-care-task:123',
        snapshot: snapshot(),
      );

      expect(decision.action, FlickoCallInviteDispatchAction.retryDeclined);
      expect(decision.spec, isNotNull);
      expect(decision.spec!.reason, AiCallInviteReason.missedCareTask);
      expect(decision.retryPlan, isNotNull);
      expect(decision.retryPlan!.auditTitle, contains('declined'));
    });

    test('opens invite for valid incoming payload', () {
      final decision = coordinator.decide(
        payload: 'call-invite:missed-meal-photo:123',
        snapshot: snapshot(),
      );

      expect(decision.action, FlickoCallInviteDispatchAction.openInvite);
      expect(decision.spec, isNotNull);
      expect(decision.spec!.reason, AiCallInviteReason.missedMealPhoto);
    });
  });
}
