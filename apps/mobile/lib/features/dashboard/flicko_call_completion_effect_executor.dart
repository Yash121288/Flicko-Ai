import '../reminders/flicko_saved_reminder.dart';
import 'ai_call_memory.dart';
import 'flicko_call_completion_coordinator.dart';
import 'flicko_call_invite_coordinator.dart';

typedef FlickoScheduleSavedReminder =
    Future<void> Function(FlickoSavedReminder reminder);
typedef FlickoScheduleCompletionInvite =
    Future<void> Function(FlickoCallCompletionInvitePlan plan);
typedef FlickoScheduleRetryInvite =
    Future<void> Function(FlickoRetryCallInvitePlan plan);
typedef FlickoSyncCompletionRecord =
    Future<void> Function(FlickoCallCompletionRecordSync sync);
typedef FlickoSaveCompletionMemory =
    Future<void> Function(
      String title,
      String content,
      Map<String, Object?> data,
    );
typedef FlickoSyncCompletionReport =
    Future<void> Function(HealthCallMemorySummary callMemory);
typedef FlickoCompletionEffectErrorHandler =
    void Function(String stage, Object error);

class FlickoCallCompletionEffectExecutor {
  const FlickoCallCompletionEffectExecutor();

  Future<void> execute({
    required FlickoCallCompletionPlan plan,
    required void Function(String scheduledReminderKey) onScheduledReminderKey,
    required FlickoScheduleSavedReminder scheduleReminder,
    required FlickoScheduleCompletionInvite scheduleDailyInvite,
    required FlickoScheduleRetryInvite scheduleBusyRetryInvite,
    required FlickoSyncCompletionRecord syncRecord,
    required Future<void> Function() syncProfile,
    required FlickoSaveCompletionMemory saveMemory,
    required FlickoSyncCompletionReport syncCallReport,
    required Future<void> Function() syncReport,
    FlickoCompletionEffectErrorHandler? onError,
  }) async {
    if (plan.dailyCallReminder != null && plan.scheduledReminderKey != null) {
      await _run('schedule reminder', onError, () async {
        await scheduleReminder(plan.dailyCallReminder!);
        onScheduledReminderKey(plan.scheduledReminderKey!);
      });
    }

    if (plan.dailyInvitePlan != null) {
      await _run('schedule daily invite', onError, () async {
        await scheduleDailyInvite(plan.dailyInvitePlan!);
      });
    }

    for (final recordSync in plan.recordSyncs) {
      await _run('sync ${recordSync.recordType}', onError, () async {
        await syncRecord(recordSync);
      });
    }

    await _run('sync profile', onError, syncProfile);
    await _run('save memory', onError, () async {
      await saveMemory(plan.memoryTitle, plan.memoryContent, plan.memoryData);
    });
    await _run('sync call report', onError, () async {
      await syncCallReport(plan.callMemory);
    });
    await _run('sync report', onError, syncReport);

    if (plan.busyRetryPlan != null) {
      await _run('schedule busy retry', onError, () async {
        await scheduleBusyRetryInvite(plan.busyRetryPlan!);
      });
    }
  }

  Future<void> _run(
    String stage,
    FlickoCompletionEffectErrorHandler? onError,
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } catch (error) {
      onError?.call(stage, error);
    }
  }
}
