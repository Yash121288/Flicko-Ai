import 'dart:async';

class FlickoCallInviteRuntimeCoordinator {
  FlickoCallInviteRuntimeCoordinator({
    this.maxTimerDelay = const Duration(hours: 24),
  });

  final Duration maxTimerDelay;
  final Map<String, Timer> _timers = <String, Timer>{};
  String? _pendingPayload;

  String? get pendingPayload => _pendingPayload;

  void queuePendingPayload(String payload) {
    final cleanPayload = payload.trim();
    if (cleanPayload.isEmpty) {
      return;
    }
    _pendingPayload = cleanPayload;
  }

  String? takePendingPayloadIfReady({
    required bool canOpenDashboard,
    required bool callInviteRouteOpen,
    required bool liveCallInProgress,
  }) {
    if (!canOpenDashboard || callInviteRouteOpen || liveCallInProgress) {
      return null;
    }
    final payload = _pendingPayload;
    if (payload == null || payload.trim().isEmpty) {
      return null;
    }
    _pendingPayload = null;
    return payload;
  }

  void armTimer({
    required String payload,
    required DateTime scheduledAt,
    required void Function(String payload) onPayloadDue,
    DateTime? now,
  }) {
    final resolvedNow = now ?? DateTime.now();
    final delay = scheduledAt.difference(resolvedNow);
    if (delay <= Duration.zero || delay > maxTimerDelay) {
      return;
    }
    _timers[payload]?.cancel();
    _timers[payload] = Timer(delay, () {
      _timers.remove(payload);
      queuePendingPayload(payload);
      onPayloadDue(payload);
    });
  }

  void cancelTrackedPayload(String payload) {
    _timers.remove(payload)?.cancel();
    if (_pendingPayload == payload) {
      _pendingPayload = null;
    }
  }

  void dispose() {
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
    _pendingPayload = null;
  }
}
