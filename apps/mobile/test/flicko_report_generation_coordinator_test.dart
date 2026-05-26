import 'package:flutter_test/flutter_test.dart';

import 'package:flicko_health/features/dashboard/ai_call_models.dart';
import 'package:flicko_health/features/dashboard/coach_update_parser.dart';
import 'package:flicko_health/features/dashboard/flicko_report_generation_coordinator.dart';
import 'package:flicko_health/features/dashboard/gemini_health_chat_client.dart';

void main() {
  const coordinator = FlickoReportGenerationCoordinator();

  FlickoReportGenerationSnapshot snapshot({
    String problemName = 'Diabetes',
    bool intakeCompleted = true,
    String intakeSummary = 'Complete intake summary',
    List<String> syncedReportKeys = const <String>[],
    int reportCount = 0,
  }) {
    return FlickoReportGenerationSnapshot(
      problemName: problemName,
      intakeCompleted: intakeCompleted,
      intakeSummary: intakeSummary,
      syncedReportKeys: syncedReportKeys,
      reportCount: reportCount,
    );
  }

  group('FlickoReportGenerationCoordinator', () {
    test('creates first setup report only once', () {
      final first = coordinator.setupReportIfNeeded(snapshot());
      final existing = coordinator.setupReportIfNeeded(
        snapshot(
          syncedReportKeys: const ['setup-report:diabetes'],
          reportCount: 1,
        ),
      );

      expect(first, isNotNull);
      expect(first!.kind, FlickoReportGenerationKind.setup);
      expect(first.title, 'Diabetes Setup Report');
      expect(existing, isNull);
    });

    test('creates weekly report once per week after baseline exists', () {
      final now = DateTime.utc(2026, 5, 22);
      final request = coordinator.weeklyReportIfDue(
        snapshot(reportCount: 1),
        now: now,
      );
      final skipped = coordinator.weeklyReportIfDue(
        snapshot(
          reportCount: 1,
          syncedReportKeys: const ['weekly-report:diabetes:2026-20'],
        ),
        now: now,
      );

      expect(request, isNotNull);
      expect(request!.kind, FlickoReportGenerationKind.weekly);
      expect(request.title, 'Diabetes Weekly Report');
      expect(request.syncKey, 'weekly-report:diabetes:2026-20');
      expect(skipped, isNull);
    });

    test(
      'chat auto request creates setup report on first intake completion',
      () {
        final request = coordinator.chatAutoRequest(
          previous: snapshot(intakeCompleted: false, intakeSummary: ''),
          next: snapshot(),
          update: const CoachAppUpdate(intakeComplete: true),
          history: const <AiCoachMessage>[
            AiCoachMessage.user('Start health intake'),
            AiCoachMessage.assistant('Intake status: complete'),
          ],
          now: DateTime.utc(2026, 5, 22),
        );

        expect(request, isNotNull);
        expect(request!.kind, FlickoReportGenerationKind.setup);
      },
    );

    test(
      'chat auto request creates special report only for explicit user ask',
      () {
        final request = coordinator.chatAutoRequest(
          previous: snapshot(reportCount: 1),
          next: snapshot(reportCount: 1),
          update: const CoachAppUpdate(),
          history: const <AiCoachMessage>[
            AiCoachMessage.user('Please create a special report for my doctor'),
            AiCoachMessage.assistant('I can prepare that.'),
          ],
          now: DateTime.utc(2026, 5, 22),
        );
        final skipped = coordinator.chatAutoRequest(
          previous: snapshot(reportCount: 1),
          next: snapshot(reportCount: 1),
          update: const CoachAppUpdate(),
          history: const <AiCoachMessage>[
            AiCoachMessage.user('I uploaded my lab report yesterday'),
            AiCoachMessage.assistant('I saved that report summary.'),
          ],
          now: DateTime.utc(2026, 5, 22),
        );

        expect(request, isNotNull);
        expect(request!.kind, FlickoReportGenerationKind.special);
        expect(request.title, 'Diabetes Special Report');
        expect(skipped, isNull);
      },
    );

    test('call auto request only makes weekly report on routine calls', () {
      final summary = AiCallSessionSummary(
        problemName: 'Diabetes',
        reason: AiCallInviteReason.dailyRoutine,
        startedAt: DateTime.utc(2026, 5, 22, 9),
        endedAt: DateTime.utc(2026, 5, 22, 9, 10),
        duration: const Duration(minutes: 10),
        inviteMemoryIntent: 'Daily check-in',
      );
      final missedTask = AiCallSessionSummary(
        problemName: 'Diabetes',
        reason: AiCallInviteReason.missedCareTask,
        startedAt: DateTime.utc(2026, 5, 22, 9),
        endedAt: DateTime.utc(2026, 5, 22, 9, 10),
        duration: const Duration(minutes: 10),
        inviteMemoryIntent: 'Missed task follow-up',
      );

      final weekly = coordinator.callAutoRequest(
        snapshot: snapshot(reportCount: 1),
        summary: summary,
        now: DateTime.utc(2026, 5, 22),
      );
      final skipped = coordinator.callAutoRequest(
        snapshot: snapshot(reportCount: 1),
        summary: missedTask,
        now: DateTime.utc(2026, 5, 22),
      );

      expect(weekly, isNotNull);
      expect(weekly!.kind, FlickoReportGenerationKind.weekly);
      expect(skipped, isNull);
    });
  });
}
