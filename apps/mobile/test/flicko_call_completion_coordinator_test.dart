import 'package:flutter_test/flutter_test.dart';

import 'package:flicko_health/features/dashboard/ai_call_memory.dart';
import 'package:flicko_health/features/dashboard/ai_call_models.dart';
import 'package:flicko_health/features/dashboard/flicko_call_completion_coordinator.dart';
import 'package:flicko_health/features/management/flicko_care_task.dart';

void main() {
  const coordinator = FlickoCallCompletionCoordinator();

  FlickoCallCompletionSnapshot snapshot({
    String intakeSummary = '',
    bool intakeCompleted = false,
    List<String> dashboardNotes = const <String>[],
    List<String> reminders = const <String>[],
    List<HealthCallMemorySummary> callMemories =
        const <HealthCallMemorySummary>[],
    List<FlickoCareTask> careTasks = const <FlickoCareTask>[],
  }) {
    return FlickoCallCompletionSnapshot(
      intakeSummary: intakeSummary,
      intakeCompleted: intakeCompleted,
      dashboardNotes: dashboardNotes,
      reminders: reminders,
      callMemories: callMemories,
      savedReminders: const [],
      careTasks: careTasks,
    );
  }

  group('FlickoCallCompletionCoordinator', () {
    test('builds setup follow-up assets when call captured enough data', () {
      final startedAt = DateTime.utc(2026, 5, 22, 9, 0);
      final endedAt = startedAt.add(const Duration(minutes: 3));
      final transcript = [
        HealthCallTranscriptEntry(
          role: 'assistant',
          text: 'Done, I saved your daily call reminder for 9:00 PM.',
          createdAt: startedAt,
        ),
        HealthCallTranscriptEntry(
          role: 'user',
          text: 'Please call me every night after dinner.',
          createdAt: startedAt.add(const Duration(seconds: 30)),
        ),
      ];
      final memory = HealthCallMemorySummary.fromSession(
        problemName: 'Diabetes',
        reason: AiCallInviteReason.dailyRoutine.payloadKey,
        reasonTitle: AiCallInviteReason.dailyRoutine.title,
        startedAt: startedAt,
        endedAt: endedAt,
        duration: endedAt.difference(startedAt),
        inviteMemoryIntent: 'Daily routine update.',
        transcript: transcript,
      );
      final summary = AiCallSessionSummary(
        problemName: 'Diabetes',
        reason: AiCallInviteReason.dailyRoutine,
        startedAt: startedAt,
        endedAt: endedAt,
        duration: endedAt.difference(startedAt),
        inviteMemoryIntent: 'Daily routine update.',
        memorySummary: memory,
      );

      final plan = coordinator.build(
        snapshot: snapshot(
          intakeSummary: 'Existing summary',
          dashboardNotes: const ['Older note'],
          reminders: const ['Existing reminder'],
        ),
        summary: summary,
        firstName: 'Kartik',
        now: startedAt,
      );

      expect(plan.setupReady, true);
      expect(plan.preferredCallTime, isNotNull);
      expect(plan.dailyCallReminder, isNotNull);
      expect(plan.mealTask, isNotNull);
      expect(plan.routineTask, isNotNull);
      expect(plan.intakeCompleted, true);
      expect(plan.intakeSummary, contains('Existing summary'));
      expect(plan.dashboardNotes.first, summary.dashboardNote);
      expect(
        plan.reminders,
        contains('Meal photo missed: Flicko can call and ask what you ate.'),
      );
      expect(plan.callMemories, hasLength(1));
      expect(plan.scheduledReminderKey, isNotNull);
      expect(plan.dailyInvitePlan, isNotNull);
      expect(plan.recordSyncs, hasLength(3));
      expect(plan.memoryTitle, '${summary.reason.title} summary');
      expect(plan.memoryContent, isNotEmpty);
      expect(plan.memoryData['memorySummary'], isNotNull);
    });

    test(
      'preserves reminder/task state when setup evidence is insufficient',
      () {
        final startedAt = DateTime.utc(2026, 5, 22, 10, 0);
        final endedAt = startedAt.add(const Duration(seconds: 40));
        final memory = HealthCallMemorySummary.fromSession(
          problemName: 'Thyroid',
          reason: AiCallInviteReason.notification.payloadKey,
          reasonTitle: AiCallInviteReason.notification.title,
          startedAt: startedAt,
          endedAt: endedAt,
          duration: endedAt.difference(startedAt),
          inviteMemoryIntent: 'Short notification follow-up.',
          transcript: const [],
        );
        final summary = AiCallSessionSummary(
          problemName: 'Thyroid',
          reason: AiCallInviteReason.notification,
          startedAt: startedAt,
          endedAt: endedAt,
          duration: endedAt.difference(startedAt),
          inviteMemoryIntent: 'Short notification follow-up.',
          memorySummary: memory,
        );

        final plan = coordinator.build(
          snapshot: snapshot(
            intakeCompleted: false,
            reminders: const ['Keep medicine timing'],
          ),
          summary: summary,
          firstName: 'Kartik',
          now: startedAt,
        );

        expect(plan.setupReady, false);
        expect(plan.dailyCallReminder, isNull);
        expect(plan.mealTask, isNull);
        expect(plan.routineTask, isNull);
        expect(plan.reminders, const ['Keep medicine timing']);
        expect(plan.savedReminders, isEmpty);
        expect(plan.careTasks, isEmpty);
        expect(plan.dailyInvitePlan, isNull);
        expect(plan.recordSyncs, isEmpty);
      },
    );

    test(
      'marks the matching missed care task complete after follow-up call',
      () {
        final startedAt = DateTime.utc(2026, 5, 22, 18, 0);
        final endedAt = startedAt.add(const Duration(minutes: 2));
        final pendingTask = FlickoCareTask.create(
          type: FlickoCareTaskType.medicine,
          title: 'Take evening medicine',
          detail: 'After dinner dose',
          timeLabel: '9:00 PM',
          problemName: 'Diabetes',
          now: startedAt.subtract(const Duration(hours: 4)),
        );
        final memory = HealthCallMemorySummary.fromSession(
          problemName: 'Diabetes',
          reason: AiCallInviteReason.missedCareTask.payloadKey,
          reasonTitle: AiCallInviteReason.missedCareTask.title,
          startedAt: startedAt,
          endedAt: endedAt,
          duration: endedAt.difference(startedAt),
          inviteMemoryIntent: 'Missed task recovery call.',
          transcript: <HealthCallTranscriptEntry>[
            HealthCallTranscriptEntry(
              role: 'assistant',
              text: 'Aaj evening medicine task par follow-up karte hain.',
              createdAt: DateTime.utc(2026, 5, 22, 18, 0, 5),
            ),
            HealthCallTranscriptEntry(
              role: 'user',
              text: 'Theek hai, maine ab medicine le li hai.',
              createdAt: DateTime.utc(2026, 5, 22, 18, 0, 20),
            ),
          ],
        );
        final summary = AiCallSessionSummary(
          problemName: 'Diabetes',
          reason: AiCallInviteReason.missedCareTask,
          startedAt: startedAt,
          endedAt: endedAt,
          duration: endedAt.difference(startedAt),
          inviteMemoryIntent: 'Missed task recovery call.',
          inviteSubtitle: 'Take evening medicine',
          memorySummary: memory,
        );

        final plan = coordinator.build(
          snapshot: snapshot(careTasks: [pendingTask]),
          summary: summary,
          firstName: 'Kartik',
          now: endedAt,
        );

        final updatedTask = plan.careTasks.firstWhere(
          (task) => task.id == pendingTask.id,
        );
        expect(updatedTask.isDoneOn(endedAt), true);
        expect(
          plan.recordSyncs.any(
            (entry) =>
                entry.recordType == 'care-tasks' &&
                entry.record['id'] == pendingTask.id &&
                entry.record['lastCompletedAt'] == endedAt.toIso8601String(),
          ),
          true,
        );
      },
    );
  });
}
