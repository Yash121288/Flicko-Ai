import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flicko_health/features/dashboard/ai_call_memory.dart';
import 'package:flicko_health/features/dashboard/ai_call_models.dart';
import 'package:flicko_health/features/dashboard/flicko_call_completion_coordinator.dart';
import 'package:flicko_health/features/dashboard/flicko_call_completion_effect_executor.dart';
import 'package:flicko_health/features/dashboard/flicko_call_invite_coordinator.dart';
import 'package:flicko_health/features/management/flicko_care_task.dart';
import 'package:flicko_health/features/reminders/flicko_saved_reminder.dart';

void main() {
  const executor = FlickoCallCompletionEffectExecutor();

  HealthCallMemorySummary memory() {
    final startedAt = DateTime.utc(2026, 5, 22, 9, 0);
    final endedAt = startedAt.add(const Duration(minutes: 3));
    return HealthCallMemorySummary.fromSession(
      problemName: 'Diabetes',
      reason: AiCallInviteReason.dailyRoutine.payloadKey,
      reasonTitle: AiCallInviteReason.dailyRoutine.title,
      startedAt: startedAt,
      endedAt: endedAt,
      duration: endedAt.difference(startedAt),
      inviteMemoryIntent: 'Daily routine update.',
      transcript: const [],
    );
  }

  FlickoCallCompletionPlan buildPlan({
    bool includeReminder = true,
    bool includeBusyRetry = true,
  }) {
    final callMemory = memory();
    final reminder = FlickoSavedReminder.create(
      title: 'Flicko AI call window',
      body: 'Daily call',
      time: const TimeOfDay(hour: 21, minute: 0),
      problemName: 'Diabetes',
    );
    final mealTask = FlickoCareTask.create(
      type: FlickoCareTaskType.meal,
      title: 'Upload meal photo',
      detail: 'Daily meal check',
      timeLabel: '1:30 PM',
      problemName: 'Diabetes',
      now: DateTime.utc(2026, 5, 22, 9, 0),
    );
    final routineTask = FlickoCareTask.create(
      type: FlickoCareTaskType.custom,
      title: 'Daily AI routine check',
      detail: 'Routine review',
      timeLabel: '8:00 PM',
      problemName: 'Diabetes',
      now: DateTime.utc(2026, 5, 22, 9, 0),
    );
    final dailyInvitePlan = FlickoCallCompletionInvitePlan(
      spec: AiCallInviteSpec.dailyRoutine(
        firstName: 'Kartik',
        problemName: 'Diabetes',
      ),
      scheduledAt: DateTime.utc(2026, 5, 22, 21, 0),
      repeatsDaily: true,
      auditTitle: 'Daily Flicko call window set',
      auditContent: 'Call every night.',
    );
    final busyRetryPlan = FlickoRetryCallInvitePlan(
      spec: AiCallInviteSpec.dailyRoutine(
        firstName: 'Kartik',
        problemName: 'Diabetes',
      ),
      scheduledAt: DateTime.utc(2026, 5, 22, 12, 0),
      auditTitle: 'Busy call retry scheduled',
      auditContent: 'Retry later.',
    );

    return FlickoCallCompletionPlan(
      callMemory: callMemory,
      lastAiCallCompletedAt: callMemory.endedAt.toIso8601String(),
      intakeSummary: 'Summary',
      intakeCompleted: true,
      dashboardNotes: const ['note'],
      reminders: const ['Daily call'],
      callMemories: [callMemory],
      savedReminders: includeReminder ? [reminder] : const [],
      careTasks: includeReminder ? [mealTask, routineTask] : const [],
      setupReady: includeReminder,
      recordSyncs: includeReminder
          ? [
              FlickoCallCompletionRecordSync(
                recordType: 'reminders',
                record: reminder.toJson(),
              ),
              FlickoCallCompletionRecordSync(
                recordType: 'care-tasks',
                record: mealTask.toJson(),
              ),
              FlickoCallCompletionRecordSync(
                recordType: 'care-tasks',
                record: routineTask.toJson(),
              ),
            ]
          : const [],
      memoryTitle: 'Daily routine call summary',
      memoryContent: 'Memory content',
      memoryData: const {'memory': 'data'},
      preferredCallTime: includeReminder
          ? const TimeOfDay(hour: 21, minute: 0)
          : null,
      dailyCallReminder: includeReminder ? reminder : null,
      mealTask: includeReminder ? mealTask : null,
      routineTask: includeReminder ? routineTask : null,
      scheduledReminderKey: includeReminder
          ? '${reminder.payload}|${reminder.hour}:${reminder.minute}'
          : null,
      dailyInvitePlan: includeReminder ? dailyInvitePlan : null,
      busyRetryPlan: includeBusyRetry ? busyRetryPlan : null,
    );
  }

  group('FlickoCallCompletionEffectExecutor', () {
    test('executes planned effects in order', () async {
      final calls = <String>[];
      final plan = buildPlan();

      await executor.execute(
        plan: plan,
        onScheduledReminderKey: (key) => calls.add('key:$key'),
        scheduleReminder: (reminder) async =>
            calls.add('reminder:${reminder.id}'),
        scheduleDailyInvite: (invitePlan) async =>
            calls.add('daily-invite:${invitePlan.auditTitle}'),
        scheduleBusyRetryInvite: (retryPlan) async =>
            calls.add('busy-retry:${retryPlan.auditTitle}'),
        syncRecord: (recordSync) async => calls.add(
          'sync:${recordSync.recordType}:${recordSync.record['id']}',
        ),
        syncProfile: () async => calls.add('sync-profile'),
        saveMemory: (title, content, data) async =>
            calls.add('save-memory:$title'),
        syncCallReport: (callMemory) async =>
            calls.add('sync-call-report:${callMemory.id}'),
        syncReport: () async => calls.add('sync-report'),
      );

      expect(calls.first.startsWith('reminder:'), true);
      expect(calls[1].startsWith('key:'), true);
      expect(calls[2], 'daily-invite:Daily Flicko call window set');
      expect(calls.where((entry) => entry.startsWith('sync:')).length, 3);
      expect(calls, contains('sync-profile'));
      expect(calls, contains('save-memory:Daily routine call summary'));
      expect(calls.last, 'busy-retry:Busy call retry scheduled');
    });

    test('continues executing later effects when one stage throws', () async {
      final calls = <String>[];
      final errors = <String>[];
      final plan = buildPlan(includeReminder: false, includeBusyRetry: false);

      await executor.execute(
        plan: plan,
        onScheduledReminderKey: (_) => calls.add('key'),
        scheduleReminder: (_) async => calls.add('reminder'),
        scheduleDailyInvite: (_) async => calls.add('daily-invite'),
        scheduleBusyRetryInvite: (_) async => calls.add('busy-retry'),
        syncRecord: (_) async => calls.add('sync-record'),
        syncProfile: () async => calls.add('sync-profile'),
        saveMemory: (title, content, data) async {
          calls.add('save-memory');
          throw StateError('memory failed');
        },
        syncCallReport: (_) async => calls.add('sync-call-report'),
        syncReport: () async => calls.add('sync-report'),
        onError: (stage, error) => errors.add('$stage:$error'),
      );

      expect(calls, contains('sync-profile'));
      expect(calls, contains('save-memory'));
      expect(calls, contains('sync-call-report'));
      expect(calls, contains('sync-report'));
      expect(errors.single.startsWith('save memory:'), true);
    });
  });
}
