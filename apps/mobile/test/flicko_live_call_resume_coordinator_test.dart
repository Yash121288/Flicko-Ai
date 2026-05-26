import 'package:flutter_test/flutter_test.dart';

import 'package:flicko_health/features/dashboard/ai_call_models.dart';
import 'package:flicko_health/features/dashboard/ai_call_transcript_store.dart';
import 'package:flicko_health/features/dashboard/flicko_live_call_resume_coordinator.dart';

void main() {
  const coordinator = FlickoLiveCallResumeCoordinator();

  AiCallTranscriptSessionDraft activeSession({bool completed = false}) {
    final startedAt = DateTime.utc(2026, 5, 22, 9, 0);
    return AiCallTranscriptSessionDraft(
      sessionId: 'session-1',
      problemName: 'Diabetes',
      reason: AiCallInviteReason.dailyRoutine,
      subtitle: 'Daily routine call',
      profileContext: 'Profile context',
      startedAt: startedAt,
      updatedAt: startedAt.add(const Duration(minutes: 4)),
      completedAt: completed ? startedAt.add(const Duration(minutes: 4)) : null,
    );
  }

  group('FlickoLiveCallResumeCoordinator', () {
    test('skips signal checks when route or live call already active', () {
      expect(
        coordinator.shouldCheckResumeSignal(
          callInviteRouteOpen: true,
          liveCallInProgress: false,
        ),
        false,
      );
      expect(
        coordinator.shouldCheckResumeSignal(
          callInviteRouteOpen: false,
          liveCallInProgress: true,
        ),
        false,
      );
      expect(
        coordinator.shouldCheckResumeSignal(
          callInviteRouteOpen: false,
          liveCallInProgress: false,
        ),
        true,
      );
    });

    test('returns resumable session only for active valid resume state', () {
      final session = activeSession();

      final resumable = coordinator.resumableSession(
        FlickoLiveCallResumeSnapshot(
          callInviteRouteOpen: false,
          liveCallInProgress: false,
          openSignalConsumed: true,
          serviceRunning: true,
          session: session,
        ),
      );
      final noSignal = coordinator.resumableSession(
        FlickoLiveCallResumeSnapshot(
          callInviteRouteOpen: false,
          liveCallInProgress: false,
          openSignalConsumed: false,
          serviceRunning: true,
          session: session,
        ),
      );
      final completed = coordinator.resumableSession(
        FlickoLiveCallResumeSnapshot(
          callInviteRouteOpen: false,
          liveCallInProgress: false,
          openSignalConsumed: true,
          serviceRunning: true,
          session: activeSession(completed: true),
        ),
      );

      expect(resumable, isNotNull);
      expect(resumable!.sessionId, 'session-1');
      expect(noSignal, isNull);
      expect(completed, isNull);
    });
  });
}
