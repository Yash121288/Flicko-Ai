import 'package:flutter/material.dart';

import '../management/flicko_care_task.dart';
import '../reminders/flicko_saved_reminder.dart';
import 'ai_call_memory.dart';
import 'ai_call_models.dart';
import 'ai_call_schedule_parser.dart';
import 'flicko_call_invite_coordinator.dart';

class FlickoCallCompletionSnapshot {
  const FlickoCallCompletionSnapshot({
    required this.intakeSummary,
    required this.intakeCompleted,
    required this.dashboardNotes,
    required this.reminders,
    required this.callMemories,
    required this.savedReminders,
    required this.careTasks,
  });

  final String intakeSummary;
  final bool intakeCompleted;
  final List<String> dashboardNotes;
  final List<String> reminders;
  final List<HealthCallMemorySummary> callMemories;
  final List<FlickoSavedReminder> savedReminders;
  final List<FlickoCareTask> careTasks;
}

class FlickoCallCompletionPlan {
  const FlickoCallCompletionPlan({
    required this.callMemory,
    required this.lastAiCallCompletedAt,
    required this.intakeSummary,
    required this.intakeCompleted,
    required this.dashboardNotes,
    required this.reminders,
    required this.callMemories,
    required this.savedReminders,
    required this.careTasks,
    required this.setupReady,
    required this.recordSyncs,
    required this.memoryTitle,
    required this.memoryContent,
    required this.memoryData,
    this.preferredCallTime,
    this.dailyCallReminder,
    this.mealTask,
    this.routineTask,
    this.scheduledReminderKey,
    this.dailyInvitePlan,
    this.busyRetryPlan,
  });

  final HealthCallMemorySummary callMemory;
  final String lastAiCallCompletedAt;
  final String intakeSummary;
  final bool intakeCompleted;
  final List<String> dashboardNotes;
  final List<String> reminders;
  final List<HealthCallMemorySummary> callMemories;
  final List<FlickoSavedReminder> savedReminders;
  final List<FlickoCareTask> careTasks;
  final bool setupReady;
  final List<FlickoCallCompletionRecordSync> recordSyncs;
  final String memoryTitle;
  final String memoryContent;
  final Map<String, Object?> memoryData;
  final TimeOfDay? preferredCallTime;
  final FlickoSavedReminder? dailyCallReminder;
  final FlickoCareTask? mealTask;
  final FlickoCareTask? routineTask;
  final String? scheduledReminderKey;
  final FlickoCallCompletionInvitePlan? dailyInvitePlan;
  final FlickoRetryCallInvitePlan? busyRetryPlan;
}

class FlickoCallCompletionRecordSync {
  const FlickoCallCompletionRecordSync({
    required this.recordType,
    required this.record,
  });

  final String recordType;
  final Map<String, Object?> record;
}

class FlickoCallCompletionInvitePlan {
  const FlickoCallCompletionInvitePlan({
    required this.spec,
    required this.scheduledAt,
    required this.repeatsDaily,
    required this.auditTitle,
    required this.auditContent,
  });

  final AiCallInviteSpec spec;
  final DateTime scheduledAt;
  final bool repeatsDaily;
  final String auditTitle;
  final String auditContent;
}

class FlickoCallCompletionCoordinator {
  const FlickoCallCompletionCoordinator({
    this.callInviteCoordinator = const FlickoCallInviteCoordinator(),
  });

  final FlickoCallInviteCoordinator callInviteCoordinator;

  FlickoCallCompletionPlan build({
    required FlickoCallCompletionSnapshot snapshot,
    required AiCallSessionSummary summary,
    required String firstName,
    DateTime? now,
  }) {
    final resolvedNow = now ?? DateTime.now();
    final callMemory =
        summary.memorySummary ??
        HealthCallMemorySummary.fromSession(
          problemName: summary.problemName,
          reason: summary.reason.payloadKey,
          reasonTitle: summary.reason.title,
          startedAt: summary.startedAt,
          endedAt: summary.endedAt,
          duration: summary.duration,
          inviteMemoryIntent: summary.inviteMemoryIntent,
          transcript: const <HealthCallTranscriptEntry>[],
        );
    final preferredCallTime = AiCallScheduleParser.preferredDailyCallTime(
      callMemory,
    );
    final intakeSummary = snapshot.intakeSummary.trim().isEmpty
        ? summary.memoryContent
        : '${snapshot.intakeSummary.trim()}\n\n${summary.memoryContent}';
    final setupReady = hasEnoughSetupData(callMemory);
    final completedMissedTask = _resolveCompletedMissedTask(
      snapshot.careTasks,
      summary,
    );
    final careTasksWithResolvedMissedTask = completedMissedTask == null
        ? snapshot.careTasks
        : [
            completedMissedTask,
            ...snapshot.careTasks.where(
              (task) => task.id != completedMissedTask.id,
            ),
          ];
    final mealTask = setupReady
        ? FlickoCareTask.create(
            type: FlickoCareTaskType.meal,
            title: 'Upload meal photo',
            detail: 'If a meal photo is missed, Flicko can follow up by call.',
            timeLabel: '1:30 PM',
            problemName: summary.problemName,
          )
        : null;
    final routineTask = setupReady
        ? FlickoCareTask.create(
            type: FlickoCareTaskType.custom,
            title: 'Daily AI routine check',
            detail:
                'Confirm meals, sleep, medicine, mood, and key missed tasks.',
            timeLabel: '8:00 PM',
            problemName: summary.problemName,
          )
        : null;
    final dailyCallReminder = setupReady && preferredCallTime != null
        ? FlickoSavedReminder.create(
            title: 'Flicko AI call window',
            body:
                'Free-time check-in: update routine, missed meal photos, tasks, and weekly report notes.',
            time: preferredCallTime,
            problemName: summary.problemName,
          )
        : null;
    final nextSavedReminders = dailyCallReminder == null
        ? snapshot.savedReminders
        : [
            dailyCallReminder,
            ...snapshot.savedReminders.where(
              (reminder) => reminder.id != dailyCallReminder.id,
            ),
          ].take(60).toList(growable: false);
    final nextCareTasks = mealTask == null || routineTask == null
        ? careTasksWithResolvedMissedTask
        : [
            mealTask,
            routineTask,
            ...careTasksWithResolvedMissedTask.where(
              (task) => task.id != mealTask.id && task.id != routineTask.id,
            ),
          ].take(80).toList(growable: false);
    final recordSyncs = <FlickoCallCompletionRecordSync>[
      if (completedMissedTask != null)
        FlickoCallCompletionRecordSync(
          recordType: 'care-tasks',
          record: completedMissedTask.toJson(),
        ),
      if (dailyCallReminder != null)
        FlickoCallCompletionRecordSync(
          recordType: 'reminders',
          record: dailyCallReminder.toJson(),
        ),
      if (mealTask != null)
        FlickoCallCompletionRecordSync(
          recordType: 'care-tasks',
          record: mealTask.toJson(),
        ),
      if (routineTask != null)
        FlickoCallCompletionRecordSync(
          recordType: 'care-tasks',
          record: routineTask.toJson(),
        ),
    ];
    final dailyInvitePlan =
        dailyCallReminder != null && preferredCallTime != null
        ? FlickoCallCompletionInvitePlan(
            spec: AiCallInviteSpec.dailyRoutine(
              firstName: firstName,
              problemName: summary.problemName,
            ),
            scheduledAt: AiCallScheduleParser.nextOccurrence(
              preferredCallTime,
              now: resolvedNow,
            ),
            repeatsDaily: true,
            auditTitle: 'Daily Flicko call window set',
            auditContent:
                'User preferred ${dailyCallReminder.timeLabel}. Flicko will send a call-style invite daily at this time for routine, reminders, missed tasks, and report notes.',
          )
        : null;
    final userText = callMemory.transcript
        .where((entry) => entry.isUser)
        .map((entry) => entry.text.toLowerCase())
        .join(' ');
    final busyRetryPlan = callInviteCoordinator.busyCallRetryPlan(
      userText: userText,
      firstName: firstName,
      problemName: summary.problemName,
      now: resolvedNow,
    );

    return FlickoCallCompletionPlan(
      callMemory: callMemory,
      lastAiCallCompletedAt: summary.endedAt.toIso8601String(),
      intakeSummary: intakeSummary,
      intakeCompleted: snapshot.intakeCompleted || setupReady,
      dashboardNotes: _mergeUnique([
        summary.dashboardNote,
        ...snapshot.dashboardNotes,
      ]).take(20).toList(growable: false),
      reminders: setupReady
          ? _mergeUnique([
              if (dailyCallReminder != null) dailyCallReminder.body,
              'Meal photo missed: Flicko can call and ask what you ate.',
              ...snapshot.reminders,
            ]).take(20).toList(growable: false)
          : snapshot.reminders,
      callMemories: _mergeCallMemories([callMemory, ...snapshot.callMemories]),
      savedReminders: nextSavedReminders,
      careTasks: nextCareTasks,
      setupReady: setupReady,
      recordSyncs: recordSyncs,
      memoryTitle: '${summary.reason.title} summary',
      memoryContent: callMemory.fullTranscriptText.trim().isNotEmpty
          ? callMemory.fullTranscriptText
          : callMemory.memoryContent,
      memoryData: {
        ...summary.toJson(),
        'memorySummary': callMemory.toJson(),
        'fullTranscriptText': callMemory.fullTranscriptText,
      },
      preferredCallTime: preferredCallTime,
      dailyCallReminder: dailyCallReminder,
      mealTask: mealTask,
      routineTask: routineTask,
      scheduledReminderKey: dailyCallReminder == null
          ? null
          : '${dailyCallReminder.payload}|${dailyCallReminder.hour}:${dailyCallReminder.minute}',
      dailyInvitePlan: dailyInvitePlan,
      busyRetryPlan: busyRetryPlan,
    );
  }

  FlickoCareTask? _resolveCompletedMissedTask(
    List<FlickoCareTask> tasks,
    AiCallSessionSummary summary,
  ) {
    if (summary.reason != AiCallInviteReason.missedCareTask) {
      return null;
    }
    final cleanSubtitle = summary.inviteSubtitle.trim().toLowerCase();
    if (cleanSubtitle.isEmpty) {
      return null;
    }
    for (final task in tasks) {
      if (!task.enabled) {
        continue;
      }
      if (task.problemName.trim().isNotEmpty &&
          task.problemName.trim().toLowerCase() !=
              summary.problemName.trim().toLowerCase()) {
        continue;
      }
      if (task.title.trim().toLowerCase() != cleanSubtitle) {
        continue;
      }
      return task.copyWith(
        lastCompletedAt: summary.endedAt,
        updatedAt: summary.endedAt,
      );
    }
    return null;
  }

  bool hasEnoughSetupData(HealthCallMemorySummary callMemory) {
    final structured = callMemory.structured;
    final covered = [
      structured.problems.isNotEmpty,
      structured.symptoms.isNotEmpty,
      structured.routine.isNotEmpty,
      structured.food.isNotEmpty,
      structured.medicine.isNotEmpty,
      structured.reminders.isNotEmpty,
      structured.goals.isNotEmpty,
    ].where((value) => value).length;
    final userLineCount = callMemory.transcript
        .where((entry) => entry.isUser && entry.text.trim().length >= 8)
        .length;
    return covered >= 4 ||
        userLineCount >= 4 ||
        callMemory.durationSeconds >= 120;
  }

  List<HealthCallMemorySummary> _mergeCallMemories(
    List<HealthCallMemorySummary> memories,
  ) {
    final seen = <String>{};
    final result = <HealthCallMemorySummary>[];
    for (final memory in memories) {
      if (!seen.add(memory.id)) {
        continue;
      }
      result.add(memory);
    }
    result.sort((a, b) => b.endedAt.compareTo(a.endedAt));
    return result.take(30).toList(growable: false);
  }

  List<String> _mergeUnique(List<String> values) {
    final seen = <String>{};
    return values
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty && seen.add(value.toLowerCase()))
        .toList(growable: false);
  }
}
