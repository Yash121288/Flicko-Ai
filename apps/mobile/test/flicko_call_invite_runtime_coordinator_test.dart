import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flicko_health/features/dashboard/flicko_call_invite_runtime_coordinator.dart';

void main() {
  group('FlickoCallInviteRuntimeCoordinator', () {
    test('queues and consumes pending payload only when route is ready', () {
      final coordinator = FlickoCallInviteRuntimeCoordinator();
      coordinator.queuePendingPayload('call-invite:daily-routine:1');

      expect(
        coordinator.takePendingPayloadIfReady(
          canOpenDashboard: false,
          callInviteRouteOpen: false,
          liveCallInProgress: false,
        ),
        isNull,
      );

      expect(
        coordinator.takePendingPayloadIfReady(
          canOpenDashboard: true,
          callInviteRouteOpen: false,
          liveCallInProgress: false,
        ),
        'call-invite:daily-routine:1',
      );

      expect(
        coordinator.takePendingPayloadIfReady(
          canOpenDashboard: true,
          callInviteRouteOpen: false,
          liveCallInProgress: false,
        ),
        isNull,
      );
    });

    test('cancelTrackedPayload clears pending payload', () {
      final coordinator = FlickoCallInviteRuntimeCoordinator();
      coordinator.queuePendingPayload('call-invite:setup-intake:1');

      coordinator.cancelTrackedPayload('call-invite:setup-intake:1');

      expect(coordinator.pendingPayload, isNull);
    });

    test('armTimer queues payload when due and invokes callback once', () {
      fakeAsync((async) {
        final coordinator = FlickoCallInviteRuntimeCoordinator();
        var firedPayload = '';
        final now = DateTime.utc(2026, 5, 22, 18, 0);

        coordinator.armTimer(
          payload: 'call-invite:missed-care-task:1',
          scheduledAt: now.add(const Duration(minutes: 10)),
          now: now,
          onPayloadDue: (payload) => firedPayload = payload,
        );

        async.elapse(const Duration(minutes: 9));
        expect(firedPayload, isEmpty);
        expect(coordinator.pendingPayload, isNull);

        async.elapse(const Duration(minutes: 1));
        expect(firedPayload, 'call-invite:missed-care-task:1');
        expect(coordinator.pendingPayload, 'call-invite:missed-care-task:1');
      });
    });

    test('ignores invalid timer windows', () {
      fakeAsync((async) {
        final coordinator = FlickoCallInviteRuntimeCoordinator();
        var fireCount = 0;
        final now = DateTime.utc(2026, 5, 22, 18, 0);

        coordinator.armTimer(
          payload: 'past',
          scheduledAt: now.subtract(const Duration(seconds: 1)),
          now: now,
          onPayloadDue: (_) => fireCount++,
        );
        coordinator.armTimer(
          payload: 'far-future',
          scheduledAt: now.add(const Duration(hours: 25)),
          now: now,
          onPayloadDue: (_) => fireCount++,
        );

        async.elapse(const Duration(hours: 26));
        expect(fireCount, 0);
        expect(coordinator.pendingPayload, isNull);
      });
    });
  });
}
