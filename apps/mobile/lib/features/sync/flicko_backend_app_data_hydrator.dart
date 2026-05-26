import '../dashboard/ai_call_memory.dart';
import '../dashboard/gemini_health_chat_client.dart';
import '../logs/health_log_entry.dart';
import '../management/flicko_care_task.dart';
import '../meals/meal_analysis_entry.dart';
import '../reminders/flicko_saved_reminder.dart';
import '../safety/flicko_safety_engine.dart';

class FlickoBackendAppDataSnapshot {
  const FlickoBackendAppDataSnapshot({
    required this.summary,
    required this.profileIntakeCompleted,
    required this.hasHealthLogs,
    required this.hasMealAnalyses,
    required this.hasSavedReminders,
    required this.hasCareTasks,
    required this.hasSafetyEvents,
    required this.hasChatHistory,
    required this.hasCallMemories,
    required this.healthLogs,
    required this.mealAnalyses,
    required this.savedReminders,
    required this.careTasks,
    required this.safetyEvents,
    required this.chatHistory,
    required this.callMemories,
  });

  final Map<String, Object?> summary;
  final bool profileIntakeCompleted;
  final bool hasHealthLogs;
  final bool hasMealAnalyses;
  final bool hasSavedReminders;
  final bool hasCareTasks;
  final bool hasSafetyEvents;
  final bool hasChatHistory;
  final bool hasCallMemories;
  final List<HealthLogEntry> healthLogs;
  final List<MealAnalysisEntry> mealAnalyses;
  final List<FlickoSavedReminder> savedReminders;
  final List<FlickoCareTask> careTasks;
  final List<FlickoSafetyEvent> safetyEvents;
  final List<AiCoachMessage> chatHistory;
  final List<HealthCallMemorySummary> callMemories;
}

class FlickoBackendAppDataHydrator {
  const FlickoBackendAppDataHydrator();

  FlickoBackendAppDataSnapshot fromResponse(Map<String, dynamic> response) {
    final summary = response['summary'];
    final summaryMap = summary is Map
        ? Map<String, Object?>.from(summary)
        : const <String, Object?>{};
    return FlickoBackendAppDataSnapshot(
      summary: summaryMap,
      profileIntakeCompleted: _summaryBool(
        summaryMap,
        'profile_intake_completed',
      ),
      hasHealthLogs: response['health_logs'] is List,
      hasMealAnalyses: response['meal_analyses'] is List,
      hasSavedReminders: response['saved_reminders'] is List,
      hasCareTasks: response['care_tasks'] is List,
      hasSafetyEvents: response['safety_events'] is List,
      hasChatHistory: response['chat_history'] is List,
      hasCallMemories: response['memory'] is List,
      healthLogs: _healthLogsFromBackend(response['health_logs']),
      mealAnalyses: _mealAnalysesFromBackend(response['meal_analyses']),
      savedReminders: _savedRemindersFromBackend(response['saved_reminders']),
      careTasks: _careTasksFromBackend(response['care_tasks']),
      safetyEvents: _safetyEventsFromBackend(response['safety_events']),
      chatHistory: _chatMessagesFromBackend(response['chat_history']),
      callMemories: _callMemoriesFromBackend(response['memory']),
    );
  }

  List<HealthLogEntry> _healthLogsFromBackend(Object? value) {
    return _backendRecords(value)
        .map(
          (record) => HealthLogEntry.fromJson(
            _backendPayload(record, {
              'id': record['external_id'],
              'type': record['log_type'],
              'title': record['title'],
              'value': record['value'],
              'unit': record['unit'],
              'note': record['note'],
              'problemName': record['problem_name'],
              'createdAt': record['recorded_at'],
            }),
          ),
        )
        .toList(growable: false);
  }

  List<MealAnalysisEntry> _mealAnalysesFromBackend(Object? value) {
    return _backendRecords(value)
        .map(
          (record) => MealAnalysisEntry.fromJson(
            _backendPayload(record, {
              'id': record['external_id'],
              'problemName': record['problem_name'],
              'mealName': record['meal_name'],
              'score': record['score'],
              'decision': record['decision'],
              'calorieRange': record['calorie_range'],
              'riskFlags': record['risk_flags'],
              'createdAt': record['analyzed_at'],
            }),
          ),
        )
        .toList(growable: false);
  }

  List<FlickoSavedReminder> _savedRemindersFromBackend(Object? value) {
    return FlickoSavedReminder.dedupe(
      _backendRecords(value)
          .map(
            (record) => FlickoSavedReminder.fromJson(
              _backendPayload(record, {
                'id': record['external_id'],
                'problemName': record['problem_name'],
                'title': record['title'],
                'body': record['body'],
                'hour': record['hour'],
                'minute': record['minute'],
                'enabled': record['enabled'],
                'createdAt': record['updated_at'],
                'updatedAt': record['updated_at'],
              }),
            ),
          )
          .whereType<FlickoSavedReminder>(),
    );
  }

  List<FlickoCareTask> _careTasksFromBackend(Object? value) {
    return _backendRecords(value)
        .map(
          (record) => FlickoCareTask.fromJson(
            _backendPayload(record, {
              'id': record['external_id'],
              'problemName': record['problem_name'],
              'type': record['task_type'],
              'title': record['title'],
              'detail': record['detail'],
              'timeLabel': record['time_label'],
              'enabled': record['enabled'],
              'lastCompletedAt': record['last_completed_at'],
              'createdAt': record['updated_at'],
              'updatedAt': record['updated_at'],
            }),
          ),
        )
        .whereType<FlickoCareTask>()
        .toList(growable: false);
  }

  List<FlickoSafetyEvent> _safetyEventsFromBackend(Object? value) {
    return _backendRecords(value)
        .map(
          (record) => FlickoSafetyEvent.fromJson(
            _backendPayload(record, {
              'id': record['external_id'],
              'problemName': record['problem_name'],
              'source': record['source'],
              'severity': record['severity'],
              'ruleId': record['rule_id'],
              'title': record['title'],
              'matchedText': record['matched_text'],
              'action': record['action'],
              'createdAt': record['occurred_at'],
            }),
          ),
        )
        .toList(growable: false);
  }

  List<AiCoachMessage> _chatMessagesFromBackend(Object? value) {
    return _backendRecords(value)
        .map(
          (record) => AiCoachMessage.fromJson(
            _backendPayload(record, {
              'role': record['role'],
              'text': record['text'],
              'isError': record['is_error'],
              'createdAt': record['sent_at'],
            }),
          ),
        )
        .where((message) => message.text.trim().isNotEmpty)
        .toList(growable: false);
  }

  List<HealthCallMemorySummary> _callMemoriesFromBackend(Object? value) {
    return _backendRecords(value)
        .where((record) => record['source']?.toString() == 'call')
        .map((record) {
          final data = record['data'];
          if (data is Map && data['memorySummary'] is Map) {
            return HealthCallMemorySummary.fromJson(
              Map<String, dynamic>.from(data['memorySummary'] as Map),
            ).copyWith(backendSyncedAt: record['created_at']?.toString() ?? '');
          }
          if (data is Map) {
            return HealthCallMemorySummary.fromJson(
              Map<String, dynamic>.from(data),
            ).copyWith(backendSyncedAt: record['created_at']?.toString() ?? '');
          }
          return HealthCallMemorySummary.fromJson({
            'id': 'backend-memory-${record['id']}',
            'problemName': record['problem_name'],
            'reason': 'notification',
            'reasonTitle': record['title'],
            'startedAt': record['occurred_at'],
            'endedAt': record['occurred_at'],
            'durationSeconds': 0,
            'structured': {'overview': record['content']?.toString() ?? ''},
            'backendSyncedAt': record['created_at']?.toString() ?? '',
          });
        })
        .where((memory) => memory.memoryContent.trim().isNotEmpty)
        .toList(growable: false);
  }

  List<Map<String, dynamic>> _backendRecords(Object? value) {
    if (value is! List) {
      return const <Map<String, dynamic>>[];
    }
    return value
        .whereType<Map>()
        .map((record) => Map<String, dynamic>.from(record))
        .toList(growable: false);
  }

  Map<String, dynamic> _backendPayload(
    Map<String, dynamic> record,
    Map<String, Object?> fallback,
  ) {
    final payload = record['payload'];
    final output = Map<String, dynamic>.from(fallback);
    if (payload is Map) {
      output.addAll(Map<String, dynamic>.from(payload));
    }
    for (final entry in fallback.entries) {
      final current = output[entry.key];
      if ((current == null || current.toString().trim().isEmpty) &&
          entry.value != null) {
        output[entry.key] = entry.value;
      }
    }
    return output;
  }

  bool _summaryBool(Map<String, Object?> summary, String key) {
    final value = summary[key];
    if (value is bool) {
      return value;
    }
    return value?.toString().toLowerCase() == 'true';
  }
}
