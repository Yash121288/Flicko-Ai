import 'package:flutter_test/flutter_test.dart';

import 'package:flicko_health/features/dashboard/ai_call_memory.dart';
import 'package:flicko_health/features/dashboard/ai_call_models.dart';
import 'package:flicko_health/features/dashboard/ai_call_transcript_store.dart';
import 'package:flicko_health/features/dashboard/flicko_interrupted_call_recovery_coordinator.dart';

void main() {
  const coordinator = FlickoInterruptedCallRecoveryCoordinator();

  group('FlickoInterruptedCallRecoveryCoordinator', () {
    test('merges transcript entries, trims text, dedupes, and sorts', () {
      final t1 = DateTime.utc(2026, 5, 22, 9, 0, 0);
      final t2 = DateTime.utc(2026, 5, 22, 9, 0, 5);
      final merged = coordinator.mergeTranscript(
        <HealthCallTranscriptEntry>[
          HealthCallTranscriptEntry(
            role: 'USER',
            text: '  Hello   there  ',
            createdAt: t2,
          ),
          HealthCallTranscriptEntry(role: 'assistant', text: '', createdAt: t1),
        ],
        <HealthCallTranscriptEntry>[
          HealthCallTranscriptEntry(
            role: 'user',
            text: 'Hello there',
            createdAt: t2,
          ),
          HealthCallTranscriptEntry(
            role: 'assistant',
            text: 'Good morning',
            createdAt: t1,
          ),
        ],
      );

      expect(merged, hasLength(2));
      expect(merged.first.role, 'assistant');
      expect(merged.first.text, 'Good morning');
      expect(merged.last.role, 'user');
      expect(merged.last.text, 'Hello there');
    });

    test(
      'builds recovery summary with fallback values when session is partial',
      () {
        final startedAt = DateTime.utc(2026, 5, 22, 10, 0);
        final session = AiCallTranscriptSessionDraft(
          sessionId: 'session-1',
          problemName: '',
          reason: AiCallInviteReason.notification,
          subtitle: '',
          profileContext: '',
          startedAt: startedAt,
          updatedAt: startedAt.subtract(const Duration(minutes: 1)),
          transcript: <HealthCallTranscriptEntry>[
            HealthCallTranscriptEntry(
              role: 'assistant',
              text: 'Hello',
              createdAt: startedAt,
            ),
          ],
        );
        final now = startedAt.add(const Duration(minutes: 2));

        final plan = coordinator.build(
          session: session,
          fallbackProblemName: 'Diabetes',
          nativeTranscript: <HealthCallTranscriptEntry>[
            HealthCallTranscriptEntry(
              role: 'user',
              text: 'I missed my walk.',
              createdAt: startedAt.add(const Duration(seconds: 20)),
            ),
          ],
          now: now,
        );

        expect(plan, isNotNull);
        expect(plan!.transcript, hasLength(2));
        expect(plan.summary.problemName, 'Diabetes');
        expect(plan.summary.startedAt, startedAt);
        expect(plan.summary.endedAt, now);
        expect(plan.summary.reason, AiCallInviteReason.notification);
        expect(
          plan.summary.memorySummary!.structured.dashboardNote,
          isNotEmpty,
        );
      },
    );

    test('returns null for completed session or empty merged transcript', () {
      final startedAt = DateTime.utc(2026, 5, 22, 12, 0);
      final completed = AiCallTranscriptSessionDraft(
        sessionId: 'session-2',
        problemName: 'Thyroid',
        reason: AiCallInviteReason.dailyRoutine,
        subtitle: 'Daily routine call',
        profileContext: '',
        startedAt: startedAt,
        updatedAt: startedAt.add(const Duration(minutes: 1)),
        completedAt: startedAt.add(const Duration(minutes: 2)),
        transcript: const <HealthCallTranscriptEntry>[],
      );
      final empty = AiCallTranscriptSessionDraft(
        sessionId: 'session-3',
        problemName: 'Thyroid',
        reason: AiCallInviteReason.dailyRoutine,
        subtitle: 'Daily routine call',
        profileContext: '',
        startedAt: startedAt,
        updatedAt: startedAt.add(const Duration(minutes: 1)),
        transcript: const <HealthCallTranscriptEntry>[],
      );

      expect(
        coordinator.build(
          session: completed,
          fallbackProblemName: 'Thyroid',
          nativeTranscript: const <HealthCallTranscriptEntry>[],
        ),
        isNull,
      );
      expect(
        coordinator.build(
          session: empty,
          fallbackProblemName: 'Thyroid',
          nativeTranscript: const <HealthCallTranscriptEntry>[],
        ),
        isNull,
      );
    });
  });
}
