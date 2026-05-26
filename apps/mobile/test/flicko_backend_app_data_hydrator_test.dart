import 'package:flutter_test/flutter_test.dart';

import 'package:flicko_health/features/sync/flicko_backend_app_data_hydrator.dart';

void main() {
  const hydrator = FlickoBackendAppDataHydrator();

  test('hydrates backend summary and normalized app records', () {
    final snapshot = hydrator.fromResponse({
      'summary': {'dashboard_ready': true, 'profile_intake_completed': true},
      'health_logs': [
        {
          'external_id': 'log-1',
          'log_type': 'glucose',
          'title': 'Blood sugar log',
          'value': '132',
          'unit': 'mg/dL',
          'problem_name': 'Diabetes',
          'recorded_at': '2026-05-22T09:00:00.000Z',
        },
      ],
      'saved_reminders': [
        {
          'external_id': 'rem-1',
          'title': 'Morning medicine',
          'body': 'Take medicine',
          'hour': 9,
          'minute': 15,
          'problem_name': 'Diabetes',
          'updated_at': '2026-05-22T09:15:00.000Z',
        },
        {
          'external_id': 'rem-duplicate-time',
          'title': 'Breakfast call',
          'body': 'Review breakfast and medicine',
          'hour': 9,
          'minute': 15,
          'problem_name': 'Diabetes',
          'updated_at': '2026-05-22T09:16:00.000Z',
        },
      ],
      'care_tasks': [
        {
          'external_id': 'task-1',
          'task_type': 'medicine',
          'title': 'Take tablet',
          'detail': 'After breakfast',
          'time_label': '9:15 AM',
          'problem_name': 'Diabetes',
          'updated_at': '2026-05-22T09:15:00.000Z',
        },
      ],
      'chat_history': [
        {
          'role': 'assistant',
          'text': 'How was your sugar after breakfast?',
          'sent_at': '2026-05-22T09:20:00.000Z',
        },
      ],
      'memory': [
        {
          'id': 3,
          'source': 'call',
          'problem_name': 'Diabetes',
          'title': 'Daily routine call',
          'occurred_at': '2026-05-22T09:30:00.000Z',
          'created_at': '2026-05-22T09:31:00.000Z',
          'data': {
            'memorySummary': {
              'id': 'call-1',
              'problemName': 'Diabetes',
              'reason': 'daily_routine',
              'reasonTitle': 'Daily routine call',
              'startedAt': '2026-05-22T09:30:00.000Z',
              'endedAt': '2026-05-22T09:34:00.000Z',
              'durationSeconds': 240,
              'inviteMemoryIntent': 'Take a quick daily health check.',
              'structured': {
                'overview': 'User discussed sugar readings and meal timing.',
              },
            },
          },
        },
      ],
    });

    expect(snapshot.summary['dashboard_ready'], true);
    expect(snapshot.profileIntakeCompleted, true);
    expect(snapshot.healthLogs, hasLength(1));
    expect(snapshot.healthLogs.single.value, '132');
    expect(snapshot.savedReminders, hasLength(1));
    expect(snapshot.savedReminders.single.hour, 9);
    expect(snapshot.careTasks, hasLength(1));
    expect(snapshot.careTasks.single.timeLabel, '9:15 AM');
    expect(snapshot.chatHistory, hasLength(1));
    expect(snapshot.chatHistory.single.text, contains('sugar'));
    expect(snapshot.callMemories, hasLength(1));
    expect(snapshot.callMemories.single.reason, 'daily_routine');
    expect(
      snapshot.callMemories.single.structured.overview,
      contains('meal timing'),
    );
  });

  test('tracks explicit empty backend lists as authoritative', () {
    final snapshot = hydrator.fromResponse({
      'saved_reminders': <Map<String, Object?>>[],
      'care_tasks': <Map<String, Object?>>[],
      'chat_history': <Map<String, Object?>>[],
    });

    expect(snapshot.hasSavedReminders, true);
    expect(snapshot.savedReminders, isEmpty);
    expect(snapshot.hasCareTasks, true);
    expect(snapshot.careTasks, isEmpty);
    expect(snapshot.hasChatHistory, true);
    expect(snapshot.chatHistory, isEmpty);
  });
}
