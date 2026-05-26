import 'package:flutter_test/flutter_test.dart';

import 'package:flicko_health/features/sync/flicko_app_record_sync_coordinator.dart';
import 'package:flicko_health/features/sync/flicko_pending_app_record_op.dart';

void main() {
  const coordinator = FlickoAppRecordSyncCoordinator(maxQueueSize: 12);

  group('FlickoAppRecordSyncCoordinator', () {
    test('coalesceQueue keeps latest operation per merge key', () {
      final older = _op(
        id: 'older',
        createdAt: DateTime.utc(2026, 1, 1, 8),
        externalId: 'reminder-1',
        payload: const {'id': 'reminder-1', 'title': 'Old'},
      );
      final newer = _op(
        id: 'newer',
        createdAt: DateTime.utc(2026, 1, 1, 9),
        externalId: 'reminder-1',
        payload: const {'id': 'reminder-1', 'title': 'New'},
      );
      final other = _op(
        id: 'other',
        recordType: 'care-tasks',
        externalId: 'task-1',
        createdAt: DateTime.utc(2026, 1, 1, 7),
        payload: const {'id': 'task-1', 'title': 'Task'},
      );

      final queue = coordinator.coalesceQueue([newer, other, older]);

      expect(queue.map((entry) => entry.id).toList(), ['other', 'newer']);
      expect(queue.last.payload['title'], 'New');
    });

    test(
      'queueOperation replaces same merge key instead of stacking duplicates',
      () {
        final first = _op(
          id: 'first',
          createdAt: DateTime.utc(2026, 1, 1, 8),
          externalId: 'log-1',
          recordType: 'health-logs',
          payload: const {'id': 'log-1', 'title': 'Morning'},
        );
        final second = _op(
          id: 'second',
          createdAt: DateTime.utc(2026, 1, 1, 9),
          externalId: 'log-1',
          recordType: 'health-logs',
          payload: const {'id': 'log-1', 'title': 'Evening'},
        );

        final queue = coordinator.queueOperation([first], second);

        expect(queue, hasLength(1));
        expect(queue.single.id, 'second');
        expect(queue.single.payload['title'], 'Evening');
      },
    );

    test('replayQueued increments attempts only for failures', () async {
      final success = _op(
        id: 'success',
        createdAt: DateTime.utc(2026, 1, 1, 8),
        externalId: 'meal-1',
        recordType: 'meal-analyses',
        payload: const {'id': 'meal-1'},
      );
      final failure = _op(
        id: 'failure',
        createdAt: DateTime.utc(2026, 1, 1, 9),
        externalId: 'task-1',
        recordType: 'care-tasks',
        payload: const {'id': 'task-1'},
      );

      final result = await coordinator.replayQueued(
        currentQueue: [success, failure],
        upsertRecord: (recordType, record) async {
          if (recordType == 'care-tasks') {
            throw Exception('boom');
          }
          return {'recordType': recordType, 'id': record['id']};
        },
        deleteRecord: (recordType, externalId) async => <String, dynamic>{},
      );

      expect(result.replayedQueue.map((entry) => entry.id).toList(), [
        'success',
        'failure',
      ]);
      expect(result.remainingQueue, hasLength(1));
      expect(result.remainingQueue.single.id, 'failure');
      expect(result.remainingQueue.single.attemptCount, 1);
      expect(result.latestResponse?['recordType'], 'meal-analyses');
    });

    test('reconcileQueueAfterReplay preserves newer live operations', () {
      final replayed = _op(
        id: 'replayed',
        createdAt: DateTime.utc(2026, 1, 1, 8),
        externalId: 'reminder-1',
        payload: const {'id': 'reminder-1'},
      );
      final failedReplay = replayed.copyWithAttempt();
      final newerLive = _op(
        id: 'newer-live',
        createdAt: DateTime.utc(2026, 1, 1, 10),
        externalId: 'chat-1',
        recordType: 'chat-messages',
        payload: const {'id': 'chat-1', 'text': 'hello'},
      );

      final queue = coordinator.reconcileQueueAfterReplay(
        replayedQueue: [replayed],
        liveQueue: [replayed, newerLive],
        remainingQueue: [failedReplay],
      );

      expect(queue.map((entry) => entry.id).toList(), [
        'replayed',
        'newer-live',
      ]);
      expect(queue.first.attemptCount, 1);
    });
  });
}

FlickoPendingAppRecordOp _op({
  required String id,
  required DateTime createdAt,
  required String externalId,
  required Map<String, Object?> payload,
  String recordType = 'reminders',
  String action = 'upsert',
  int attemptCount = 0,
}) {
  return FlickoPendingAppRecordOp(
    id: id,
    action: action,
    recordType: recordType,
    externalId: externalId,
    payload: payload,
    createdAt: createdAt,
    attemptCount: attemptCount,
  );
}
