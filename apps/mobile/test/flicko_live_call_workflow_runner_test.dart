import 'package:flutter_test/flutter_test.dart';

import 'package:flicko_health/features/dashboard/ai_call_invite_page.dart';
import 'package:flicko_health/features/dashboard/ai_call_memory.dart';
import 'package:flicko_health/features/dashboard/ai_call_models.dart';
import 'package:flicko_health/features/dashboard/ai_call_transcript_store.dart';
import 'package:flicko_health/features/dashboard/ai_call_warmup.dart';
import 'package:flicko_health/features/dashboard/ai_health_call_page.dart';
import 'package:flicko_health/features/dashboard/flicko_live_call_workflow_runner.dart';

void main() {
  const runner = FlickoLiveCallWorkflowRunner();

  group('FlickoLiveCallWorkflowRunner', () {
    test('returns retry plan when invite is declined', () async {
      final spec = AiCallInviteSpec.dailyRoutine(
        firstName: 'Kartik',
        problemName: 'Diabetes',
      );

      final outcome = await runner.runInviteFlow(
        spec: spec,
        profileContext: 'profile',
        showInviteSheet: (inviteSpec) async => const AiCallInviteResponse(
          decision: AiCallInviteDecision.decline,
          retryAfter: Duration(minutes: 11),
        ),
        beforeLiveCallStart: () async => fail('call should not start'),
        prepareWarmup: (inviteSpec, profileContext) async =>
            fail('warmup should not run'),
        prestartWarmLiveCall: (warmup, problemName) async =>
            fail('prestart should not run'),
        launchCallPage: (request) async => fail('page should not open'),
      );

      expect(outcome.summary, isNull);
      expect(outcome.retryPlan, isNotNull);
      expect(outcome.retryPlan!.spec.reason, AiCallInviteReason.dailyRoutine);
    });

    test(
      'runs invite accept flow through warmup, prestart, and page launch',
      () async {
        final calls = <String>[];
        final spec = AiCallInviteSpec.dailyRoutine(
          firstName: 'Kartik',
          problemName: 'Diabetes',
        );
        final warmup = AiCallWarmupBundle(
          profileContext: 'prewarmed profile',
          openingScript: 'Hello Kartik',
          createdAt: DateTime.utc(2026, 5, 22, 10),
        );
        late FlickoLiveCallPageRequest request;
        final transcript = <HealthCallTranscriptEntry>[
          HealthCallTranscriptEntry(
            role: 'assistant',
            text: 'Hello Kartik',
            createdAt: DateTime.utc(2026, 5, 22, 10, 0, 2),
          ),
          HealthCallTranscriptEntry(
            role: 'user',
            text: 'Aaj routine theek tha.',
            createdAt: DateTime.utc(2026, 5, 22, 10, 0, 10),
          ),
        ];

        final outcome = await runner.runInviteFlow(
          spec: spec,
          profileContext: 'raw profile',
          showInviteSheet: (_) async {
            calls.add('sheet');
            return const AiCallInviteResponse(
              decision: AiCallInviteDecision.accept,
            );
          },
          beforeLiveCallStart: () async => calls.add('before'),
          prepareWarmup: (incomingSpec, profileContext) async {
            calls.add('warmup:$profileContext');
            expect(incomingSpec, same(spec));
            return warmup;
          },
          prestartWarmLiveCall: (incomingWarmup, problemName) async {
            calls.add('prestart:$problemName');
            expect(incomingWarmup, same(warmup));
          },
          launchCallPage: (incomingRequest) async {
            calls.add('launch');
            request = incomingRequest;
            return FlickoLiveCallPageOutcome(
              result: AiHealthCallResult.ended,
              transcript: transcript,
            );
          },
        );

        expect(calls, <String>[
          'sheet',
          'before',
          'warmup:raw profile',
          'prestart:Diabetes',
          'launch',
        ]);
        expect(request.problemName, 'Diabetes');
        expect(request.profileContext, 'raw profile');
        expect(request.prewarmedProfileContext, 'prewarmed profile');
        expect(request.prewarmedOpeningScript, 'Hello Kartik');
        expect(request.subtitle, AiCallInviteReason.dailyRoutine.title);
        expect(request.playConnectTone, true);
        expect(request.callSessionId, startsWith('call-'));
        expect(outcome.retryPlan, isNull);
        expect(outcome.summary, isNotNull);
        expect(outcome.summary!.problemName, 'Diabetes');
        expect(outcome.summary!.reason, AiCallInviteReason.dailyRoutine);
        expect(
          outcome.summary!.memorySummary!.transcript.last.text,
          'Aaj routine theek tha.',
        );
      },
    );

    test(
      'uses resume fallback context, session metadata, and no connect tone',
      () async {
        final session = AiCallTranscriptSessionDraft(
          sessionId: 'session-42',
          problemName: '',
          reason: AiCallInviteReason.missedCareTask,
          subtitle: '',
          profileContext: '',
          startedAt: DateTime.utc(2026, 5, 22, 11, 15),
          updatedAt: DateTime.utc(2026, 5, 22, 11, 20),
        );
        final warmup = AiCallWarmupBundle(
          profileContext: 'resume prewarmed profile',
          openingScript: 'Resume opening',
          createdAt: DateTime.utc(2026, 5, 22, 11, 14),
        );
        late FlickoLiveCallPageRequest request;

        final outcome = await runner.runResumeFlow(
          session: session,
          firstName: 'Kartik',
          fallbackProblemName: 'Thyroid',
          fallbackProfileContext: 'fallback profile',
          beforeLiveCallStart: () async {},
          prepareWarmup: (spec, profileContext) async {
            expect(profileContext, 'fallback profile');
            expect(spec.problemName, 'Thyroid');
            expect(spec.subtitle, AiCallInviteReason.missedCareTask.title);
            return warmup;
          },
          prestartWarmLiveCall: (warmupBundle, problemName) async {},
          launchCallPage: (incomingRequest) async {
            request = incomingRequest;
            return const FlickoLiveCallPageOutcome(
              result: AiHealthCallResult.ended,
              transcript: <HealthCallTranscriptEntry>[],
            );
          },
        );

        expect(request.problemName, 'Thyroid');
        expect(request.profileContext, 'fallback profile');
        expect(request.subtitle, AiCallInviteReason.missedCareTask.title);
        expect(request.callSessionId, 'session-42');
        expect(request.startedAt, session.startedAt);
        expect(request.playConnectTone, false);
        expect(outcome.summary, isNotNull);
        expect(outcome.summary!.startedAt, session.startedAt);
        expect(outcome.summary!.reason, AiCallInviteReason.missedCareTask);
      },
    );

    test('returns empty outcome when page launch is cancelled', () async {
      final spec = AiCallInviteSpec.dailyRoutine(
        firstName: 'Kartik',
        problemName: 'Diabetes',
      );

      final outcome = await runner.runInviteFlow(
        spec: spec,
        profileContext: 'profile',
        showInviteSheet: (inviteSpec) async =>
            const AiCallInviteResponse(decision: AiCallInviteDecision.accept),
        beforeLiveCallStart: () async {},
        prepareWarmup: (inviteSpec, profileContext) async => AiCallWarmupBundle(
          profileContext: 'profile',
          openingScript: 'opening',
          createdAt: DateTime.utc(2026, 5, 22, 9),
        ),
        prestartWarmLiveCall: (warmupBundle, problemName) async {},
        launchCallPage: (request) async => null,
      );

      expect(outcome.summary, isNull);
      expect(outcome.retryPlan, isNull);
    });
  });
}
