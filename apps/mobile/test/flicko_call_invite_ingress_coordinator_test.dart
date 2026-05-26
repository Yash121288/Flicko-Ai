import 'package:flutter_test/flutter_test.dart';

import 'package:flicko_health/features/dashboard/flicko_call_invite_ingress_coordinator.dart';

void main() {
  const coordinator = FlickoCallInviteIngressCoordinator();

  group('FlickoCallInviteIngressCoordinator', () {
    test('normalizes payloads by trimming empties and duplicates', () {
      final payloads = coordinator.normalizedPayloads(const [
        ' call-invite:daily-routine:1 ',
        '',
        null,
        'call-invite:daily-routine:1',
        'call-invite:setup-intake:2',
      ]);

      expect(payloads, [
        'call-invite:daily-routine:1',
        'call-invite:setup-intake:2',
      ]);
    });
  });
}
