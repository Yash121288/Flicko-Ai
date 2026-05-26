import 'flicko_pending_app_record_op.dart';

typedef FlickoAppRecordUpsertRequest =
    Future<Map<String, dynamic>> Function(
      String recordType,
      Map<String, Object?> record,
    );
typedef FlickoAppRecordDeleteRequest =
    Future<Map<String, dynamic>> Function(String recordType, String externalId);

class FlickoAppRecordReplayResult {
  const FlickoAppRecordReplayResult({
    required this.replayedQueue,
    required this.remainingQueue,
    this.latestResponse,
  });

  final List<FlickoPendingAppRecordOp> replayedQueue;
  final List<FlickoPendingAppRecordOp> remainingQueue;
  final Map<String, dynamic>? latestResponse;
}

class FlickoAppRecordSyncCoordinator {
  const FlickoAppRecordSyncCoordinator({this.maxQueueSize = 120});

  final int maxQueueSize;

  List<FlickoPendingAppRecordOp> coalesceQueue(
    Iterable<FlickoPendingAppRecordOp> operations,
  ) {
    final latestByMergeKey = <String, FlickoPendingAppRecordOp>{};
    for (final operation in operations) {
      final mergeKey = operation.mergeKey;
      final current = latestByMergeKey[mergeKey];
      if (current == null ||
          operation.createdAt.isAfter(current.createdAt) ||
          (operation.createdAt.isAtSameMomentAs(current.createdAt) &&
              operation.attemptCount >= current.attemptCount)) {
        latestByMergeKey[mergeKey] = operation;
      }
    }

    final output = latestByMergeKey.values.toList(growable: false)
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return output.take(maxQueueSize).toList(growable: false);
  }

  List<FlickoPendingAppRecordOp> queueOperation(
    List<FlickoPendingAppRecordOp> currentQueue,
    FlickoPendingAppRecordOp operation,
  ) {
    if (operation.externalId.trim().isEmpty) {
      return currentQueue;
    }
    return coalesceQueue([
      ...currentQueue.where((entry) => entry.mergeKey != operation.mergeKey),
      operation,
    ]);
  }

  List<FlickoPendingAppRecordOp> removeMergeKey(
    List<FlickoPendingAppRecordOp> currentQueue,
    String mergeKey,
  ) {
    final retained = currentQueue
        .where((entry) => entry.mergeKey != mergeKey)
        .toList(growable: false);
    return retained.length == currentQueue.length
        ? currentQueue
        : coalesceQueue(retained);
  }

  Future<FlickoAppRecordReplayResult> replayQueued({
    required List<FlickoPendingAppRecordOp> currentQueue,
    required FlickoAppRecordUpsertRequest upsertRecord,
    required FlickoAppRecordDeleteRequest deleteRecord,
    void Function(Object error, FlickoPendingAppRecordOp operation)? onError,
  }) async {
    final replayedQueue = coalesceQueue(currentQueue);
    final remaining = <FlickoPendingAppRecordOp>[];
    Map<String, dynamic>? latestResponse;

    for (final operation in replayedQueue) {
      try {
        latestResponse = operation.isDelete
            ? await deleteRecord(operation.recordType, operation.externalId)
            : await upsertRecord(operation.recordType, operation.payload);
      } catch (error) {
        remaining.add(operation.copyWithAttempt());
        onError?.call(error, operation);
      }
    }

    return FlickoAppRecordReplayResult(
      replayedQueue: replayedQueue,
      remainingQueue: coalesceQueue(remaining),
      latestResponse: latestResponse,
    );
  }

  List<FlickoPendingAppRecordOp> reconcileQueueAfterReplay({
    required List<FlickoPendingAppRecordOp> replayedQueue,
    required List<FlickoPendingAppRecordOp> liveQueue,
    required List<FlickoPendingAppRecordOp> remainingQueue,
  }) {
    final replayedIds = replayedQueue.map((entry) => entry.id).toSet();
    final newer = liveQueue
        .where((entry) => !replayedIds.contains(entry.id))
        .toList(growable: false);
    return coalesceQueue([...remainingQueue, ...newer]);
  }
}
