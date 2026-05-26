import 'ai_call_transcript_store.dart';

class FlickoLiveCallResumeSnapshot {
  const FlickoLiveCallResumeSnapshot({
    required this.callInviteRouteOpen,
    required this.liveCallInProgress,
    required this.openSignalConsumed,
    required this.serviceRunning,
    required this.session,
  });

  final bool callInviteRouteOpen;
  final bool liveCallInProgress;
  final bool openSignalConsumed;
  final bool serviceRunning;
  final AiCallTranscriptSessionDraft? session;
}

class FlickoLiveCallResumeCoordinator {
  const FlickoLiveCallResumeCoordinator();

  bool shouldCheckResumeSignal({
    required bool callInviteRouteOpen,
    required bool liveCallInProgress,
  }) {
    return !callInviteRouteOpen && !liveCallInProgress;
  }

  AiCallTranscriptSessionDraft? resumableSession(
    FlickoLiveCallResumeSnapshot snapshot,
  ) {
    if (!shouldCheckResumeSignal(
      callInviteRouteOpen: snapshot.callInviteRouteOpen,
      liveCallInProgress: snapshot.liveCallInProgress,
    )) {
      return null;
    }
    if (!snapshot.openSignalConsumed || !snapshot.serviceRunning) {
      return null;
    }
    final session = snapshot.session;
    if (session == null || session.isCompleted) {
      return null;
    }
    return session;
  }
}
