import 'package:flutter_test/flutter_test.dart';

import 'package:flicko_health/features/dashboard/ai_call_invite_page.dart';
import 'package:flicko_health/features/dashboard/ai_call_memory.dart';
import 'package:flicko_health/features/dashboard/ai_call_models.dart';
import 'package:flicko_health/features/dashboard/ai_call_transcript_store.dart';
import 'package:flicko_health/features/dashboard/flicko_call_route_coordinator.dart';

void main() {
  const coordinator = FlickoCallRouteCoordinator();

  final spec = AiCallInviteSpec.dailyRoutine(
    firstName: 'Kartik',
    problemName: 'Diabetes',
  );

  group('FlickoCallRouteCoordinator', () {
    test(
      'blocks route open when invite route or live call is already active',
      () {
        expect(
          coordinator.canOpenRoute(
            callInviteRouteOpen: true,
            liveCallInProgress: false,
          ),
          false,
        );
        expect(
          coordinator.canOpenRoute(
            callInviteRouteOpen: false,
            liveCallInProgress: true,
          ),
          false,
        );
        expect(
          coordinator.canOpenRoute(
            callInviteRouteOpen: false,
            liveCallInProgress: false,
          ),
          true,
        );
      },
    );

    test('maps invite responses to accept, retry, or ignore', () {
      final accept = coordinator.inviteResponseDecision(
        spec: spec,
        response: const AiCallInviteResponse(
          decision: AiCallInviteDecision.accept,
        ),
      );
      final decline = coordinator.inviteResponseDecision(
        spec: spec,
        response: const AiCallInviteResponse(
          decision: AiCallInviteDecision.decline,
          retryAfter: Duration(minutes: 12),
        ),
      );
      final later = coordinator.inviteResponseDecision(
        spec: spec,
        response: const AiCallInviteResponse(
          decision: AiCallInviteDecision.later,
          note: 'Retry after dinner',
        ),
      );
      final ignore = coordinator.inviteResponseDecision(
        spec: spec,
        response: null,
      );

      expect(accept.action, FlickoInviteRouteAction.accept);
      expect(decline.action, FlickoInviteRouteAction.scheduleRetry);
      expect(
        decline.retryPlan!.scheduledAt.difference(DateTime.now()).inMinutes >=
            0,
        true,
      );
      expect(later.action, FlickoInviteRouteAction.scheduleRetry);
      expect(later.retryPlan!.auditContent, 'Retry after dinner');
      expect(ignore.action, FlickoInviteRouteAction.ignore);
    });

    test('resolves resume context from session with fallback values', () {
      final session = AiCallTranscriptSessionDraft(
        sessionId: 'session-1',
        problemName: '',
        reason: AiCallInviteReason.missedCareTask,
        subtitle: '',
        profileContext: '',
        startedAt: DateTime.utc(2026, 5, 22, 9),
        updatedAt: DateTime.utc(2026, 5, 22, 9, 5),
      );

      final context = coordinator.resumeContext(
        fallbackProblemName: 'Thyroid',
        fallbackProfileContext: 'Fallback profile',
        session: session,
        fallbackSubtitle: 'Care task follow-up',
      );

      expect(context.problemName, 'Thyroid');
      expect(context.profileContext, 'Fallback profile');
      expect(context.subtitle, 'Care task follow-up');
    });

    test('builds completed summary with structured memory transcript', () {
      final startedAt = DateTime.utc(2026, 5, 22, 10, 0);
      final endedAt = startedAt.add(const Duration(minutes: 4));
      final transcript = [
        HealthCallTranscriptEntry(
          role: 'assistant',
          text: 'Hello Kartik',
          createdAt: startedAt,
        ),
        HealthCallTranscriptEntry(
          role: 'user',
          text: 'I missed my lunch photo today.',
          createdAt: startedAt.add(const Duration(seconds: 20)),
        ),
      ];

      final summary = coordinator.buildCompletedSummary(
        problemName: 'Diabetes',
        reason: AiCallInviteReason.missedMealPhoto,
        startedAt: startedAt,
        endedAt: endedAt,
        inviteMemoryIntent: spec.memoryIntent,
        transcript: transcript,
      );

      expect(summary.problemName, 'Diabetes');
      expect(summary.duration, const Duration(minutes: 4));
      expect(summary.memorySummary, isNotNull);
      expect(
        summary.memorySummary!.transcript.where((entry) => entry.isUser).length,
        1,
      );
    });
  });
}
