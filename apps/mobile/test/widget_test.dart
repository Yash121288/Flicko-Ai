import 'dart:convert';

import 'package:flicko_health/main.dart';
import 'package:flicko_health/features/bmi/bmi_snapshot.dart';
import 'package:flicko_health/features/dashboard/coach_update_parser.dart';
import 'package:flicko_health/features/dashboard/ai_call_memory.dart';
import 'package:flicko_health/features/dashboard/ai_call_schedule_parser.dart';
import 'package:flicko_health/features/dashboard/dashboard.dart';
import 'package:flicko_health/features/dashboard/dashboard_live_insights.dart';
import 'package:flicko_health/features/dashboard/flicko_voice_context_engine.dart';
import 'package:flicko_health/features/dashboard/gemini_health_chat_client.dart';
import 'package:flicko_health/features/dashboard/live_call_foreground_service.dart';
import 'package:flicko_health/features/logs/health_log_entry.dart';
import 'package:flicko_health/features/management/flicko_care_task.dart';
import 'package:flicko_health/features/onboarding/consent_safety_screen.dart';
import 'package:flicko_health/features/reminders/flicko_saved_reminder.dart';
import 'package:flicko_health/features/reminders/flicko_notification_memory_store.dart';
import 'package:flicko_health/features/safety/flicko_safety_alert_sheet.dart';
import 'package:flicko_health/features/safety/flicko_safety_engine.dart';
import 'package:flicko_health/features/storage/flicko_profile_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('emergency dialer normalizes saved mobile numbers', () {
    expect(normalizeFlickoDialNumber(' +91 98765-43210 '), '+919876543210');
    expect(normalizeFlickoDialNumber('98765 43210'), '9876543210');
    expect(normalizeFlickoDialNumber('++1 (555) 010-2200'), '+15550102200');
    expect(normalizeFlickoDialNumber('not added'), '');
  });

  test('emergency handoff message names user and chest pain', () {
    final event = FlickoSafetyEngine.evaluate(
      text: 'I have chest pain',
      problemName: 'Heart health',
      source: 'call',
    );

    final message = buildFlickoEmergencyHandoffMessage(
      userName: 'Kartik',
      event: event!,
    );

    expect(message, contains('Kartik'));
    expect(message, contains('chest pain'));
    expect(message, contains('emergency'));
  });

  test('native live call flush returns final transcript entries', () async {
    const channel = MethodChannel('flicko.health/live_call_service');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'endCallAndFlushTranscript');
      return [
        {
          'type': 'transcript',
          'role': 'user',
          'text': 'Meri sugar breakfast ke baad 150 hai.',
          'isFinal': true,
          'source': 'gemini_live_input_audio_transcription',
          'createdAt': 1770000000000,
        },
        {
          'type': 'transcript',
          'role': 'assistant',
          'text':
              'Theek hai, main isko report aur dashboard mein save karungi.',
          'isFinal': true,
          'source': 'gemini_live_output_audio_transcription',
          'createdAt': 1770000000400,
        },
      ];
    });

    final transcript = await const LiveCallForegroundService()
        .endCallAndFlushTranscript();

    expect(transcript, hasLength(2));
    expect(transcript.first.isUser, isTrue);
    expect(transcript.first.text, contains('150'));
    expect(transcript.last.isUser, isFalse);
    expect(transcript.last.source, 'gemini_live_output_audio_transcription');
  });

  test('ai call schedule parser captures explicit spoken free time', () {
    final startedAt = DateTime(2026, 5, 21, 20);
    final memory = HealthCallMemorySummary.fromSession(
      problemName: 'Weight management',
      reason: 'setup-intake',
      reasonTitle: 'Health setup call',
      startedAt: startedAt,
      endedAt: startedAt.add(const Duration(minutes: 4)),
      duration: const Duration(minutes: 4),
      inviteMemoryIntent: 'Ask preferred free call time.',
      transcript: [
        HealthCallTranscriptEntry(
          role: 'assistant',
          text: 'Theek hai, main kis time call karun?',
          createdAt: startedAt,
        ),
        HealthCallTranscriptEntry(
          role: 'user',
          text: 'raat 9 baje free hota hoon',
          createdAt: startedAt.add(const Duration(seconds: 20)),
        ),
      ],
    );

    final time = AiCallScheduleParser.preferredDailyCallTime(memory);

    expect(time, isNotNull);
    expect(time!.hour, 21);
    expect(time.minute, 0);
  });

  test('ai call schedule parser uses assistant reminder confirmation time', () {
    final startedAt = DateTime(2026, 5, 21, 20);
    final memory = HealthCallMemorySummary.fromSession(
      problemName: 'Diabetes Type 2',
      reason: 'daily-routine',
      reasonTitle: 'Daily routine call',
      startedAt: startedAt,
      endedAt: startedAt.add(const Duration(minutes: 3)),
      duration: const Duration(minutes: 3),
      inviteMemoryIntent: 'Confirm the daily call window exactly once.',
      transcript: [
        HealthCallTranscriptEntry(
          role: 'assistant',
          text: 'Theek hai, main kis time call karun?',
          createdAt: startedAt,
        ),
        HealthCallTranscriptEntry(
          role: 'user',
          text: '9 baje',
          createdAt: startedAt.add(const Duration(seconds: 15)),
        ),
        HealthCallTranscriptEntry(
          role: 'assistant',
          text:
              'Theek hai, aapka daily routine call reminder 9:00 PM par save kar rahi hoon. Reminder: 9:00 PM - Daily call check-in.',
          createdAt: startedAt.add(const Duration(seconds: 28)),
        ),
      ],
    );

    final time = AiCallScheduleParser.preferredDailyCallTime(memory);

    expect(time, isNotNull);
    expect(time!.hour, 21);
    expect(time.minute, 0);
  });

  test(
    'ai call schedule parser ignores ambiguous bare hour without confirmation',
    () {
      final startedAt = DateTime(2026, 5, 21, 20);
      final memory = HealthCallMemorySummary.fromSession(
        problemName: 'Weight management',
        reason: 'setup-intake',
        reasonTitle: 'Health setup call',
        startedAt: startedAt,
        endedAt: startedAt.add(const Duration(minutes: 4)),
        duration: const Duration(minutes: 4),
        inviteMemoryIntent: 'Ask preferred free call time.',
        transcript: [
          HealthCallTranscriptEntry(
            role: 'assistant',
            text: 'Theek hai, main kis time call karun?',
            createdAt: startedAt,
          ),
          HealthCallTranscriptEntry(
            role: 'user',
            text: '9 baje free hota hoon',
            createdAt: startedAt.add(const Duration(seconds: 20)),
          ),
        ],
      );

      final time = AiCallScheduleParser.preferredDailyCallTime(memory);

      expect(time, isNull);
    },
  );

  test('ai call schedule parser rolls past daily time to tomorrow', () {
    final next = AiCallScheduleParser.nextOccurrence(
      const TimeOfDay(hour: 9, minute: 0),
      now: DateTime(2026, 5, 21, 10),
    );

    expect(next, DateTime(2026, 5, 22, 9));
  });

  test(
    'voice context engine includes user name and notification memory',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      final store = FlickoNotificationMemoryStore();
      await store.record(
        eventType: 'reminder_scheduled',
        title: 'Medicine reminder',
        body: '8:00 PM Metformin',
        payload: 'saved-reminder:metformin',
        createdAt: DateTime(2026, 5, 21, 20),
      );

      final context = await FlickoVoiceContextEngine(memoryStore: store)
          .buildContext(
            problemName: 'Diabetes Type 2',
            profileContext:
                'User name: Kartik\nSaved AI call memory: Last call discussed sugar after breakfast.\nFlicko: Last time I asked about dinner timing.',
          );

      expect(context, contains('User name for speech: Kartik'));
      expect(context, contains('Medicine reminder'));
      expect(context, contains('Dynamic greeting seed:'));
      expect(context, contains('Last assistant wording to avoid repeating'));
    },
  );

  test('voice context uses first name as speech name', () async {
    final context = await const FlickoVoiceContextEngine().buildContext(
      problemName: 'Diabetes Type 2',
      profileContext: 'User first name: Aarav\nUser name: Aarav Shah',
    );

    expect(context, contains('User name for speech: Aarav'));
    expect(context, isNot(contains('User name for speech: Aarav Shah')));
  });

  test(
    'diabetes dashboard insights prefer real glucose over fallback value',
    () {
      final insights = DashboardLiveInsights.fromData(
        problemName: 'Diabetes Type 2',
        fallbackScore: 82,
        fallbackScoreStatus: 'Stable, needs meal consistency',
        fallbackMetricValue: '118',
        fallbackMetricUnit: 'mg/dL',
        fallbackMetricStatus: 'Normal after breakfast',
        fallbackPlanFocus: 'High-protein lunch',
        fallbackPlanNote: 'Avoid high sugar drinks',
        fallbackCheckBody: 'Upload meal photo',
        fallbackReportBody: 'Doctor-ready PDF',
        healthLogs: [
          HealthLogEntry.create(
            type: HealthLogType.glucose,
            title: 'Post-meal sugar',
            value: '198',
            unit: 'mg/dL',
            problemName: 'Diabetes Type 2',
          ),
        ],
      );

      expect(insights.metricValue, '198');
      expect(insights.metricStatus.toLowerCase(), contains('high'));
      expect(insights.planFocus, 'Post-meal glucose follow-up');
      expect(insights.score, lessThan(82));
    },
  );

  test('diabetes dashboard insights expose urgent safety warning', () {
    final insights = DashboardLiveInsights.fromData(
      problemName: 'Diabetes Type 2',
      fallbackScore: 82,
      fallbackScoreStatus: 'Stable, needs meal consistency',
      fallbackMetricValue: '118',
      fallbackMetricUnit: 'mg/dL',
      fallbackMetricStatus: 'Normal after breakfast',
      fallbackPlanFocus: 'High-protein lunch',
      fallbackPlanNote: 'Avoid high sugar drinks',
      fallbackCheckBody: 'Upload meal photo',
      fallbackReportBody: 'Doctor-ready PDF',
      healthLogs: [
        HealthLogEntry.create(
          type: HealthLogType.glucose,
          title: 'Fasting sugar',
          value: '62',
          unit: 'mg/dL',
          problemName: 'Diabetes Type 2',
        ),
      ],
      careTasks: [
        FlickoCareTask.create(
          type: FlickoCareTaskType.medicine,
          title: 'Metformin',
          detail: 'Morning medicine',
          timeLabel: '8:00 AM',
          problemName: 'Diabetes Type 2',
        ),
      ],
    );

    expect(insights.hasSafetyWarning, isTrue);
    expect(insights.safetySeverity, 'urgent');
    expect(insights.safetyTitle, contains('Low sugar'));
    expect(insights.planFocus, contains('Low sugar'));
    expect(insights.reportBody, contains('Low sugar'));
  });

  test('profile load hides legacy call transcript from visible chat', () {
    final draft = HealthProfileDraft.fromStorage(
      jsonEncode({
        'callMemories': [
          {
            'id': 'call-legacy',
            'problemName': 'Diabetes Type 2',
            'reason': 'daily-routine',
            'reasonTitle': 'Daily routine call',
            'startedAt': '2026-05-21T10:00:00.000',
            'endedAt': '2026-05-21T10:08:00.000',
            'durationSeconds': 480,
            'inviteMemoryIntent': 'Daily follow-up',
            'structured': {'overview': 'Sugar follow-up done.'},
            'transcript': [
              {
                'role': 'user',
                'text': 'Meri sugar breakfast ke baad 150 hai.',
                'createdAt': '2026-05-21T10:02:00.000',
              },
              {
                'role': 'assistant',
                'text': 'Main isko dashboard memory mein save kar rahi hoon.',
                'createdAt': '2026-05-21T10:02:10.000',
              },
            ],
          },
        ],
        'reminders': [
          'Reminder can be added later after more details.',
          '8 PM medicine check reminder',
        ],
        'reports': [
          'Doctor-ready report can be generated after more details.',
          'Weight Management Report\nPDF: https://example.com/report.pdf',
        ],
        'savedReminders': [
          {
            'title': 'Daily Flicko routine call in preferred free time',
            'body': 'Daily Flicko routine call in preferred free time',
            'hour': 20,
            'minute': 0,
          },
          {
            'title': 'Medicine reminder',
            'body': '8 PM medicine check reminder',
            'hour': 20,
            'minute': 0,
          },
        ],
        'chatHistory': [
          {'role': 'user', 'text': 'Meri sugar breakfast ke baad 150 hai.'},
          {
            'role': 'assistant',
            'text': 'Hidden call metadata line without matching transcript.',
            'source': 'call',
          },
          {
            'role': 'assistant',
            'text':
                'Live AI call completed.\nProblem: Diabetes Type 2\nDuration: 08:00\nUse this call as context for the next chat.',
          },
          {
            'role': 'user',
            'text': 'Uploaded medical report: blood-work.pdf',
            'source': 'upload',
          },
          {'role': 'user', 'text': 'Please make my dinner plan.'},
        ],
      }),
    );

    expect(draft.callMemories, hasLength(1));
    expect(draft.chatHistory, hasLength(2));
    expect(
      draft.chatHistory.first.text,
      'Uploaded medical report: blood-work.pdf',
    );
    expect(draft.chatHistory.first.source, 'upload');
    expect(draft.chatHistory.last.text, 'Please make my dinner plan.');
    expect(draft.reminders, ['8 PM medicine check reminder']);
    expect(draft.reports, [
      'Weight Management Report\nPDF: https://example.com/report.pdf',
    ]);
    expect(draft.savedReminders, hasLength(1));
    expect(draft.savedReminders.single.body, '8 PM medicine check reminder');
  });

  test('ai coach message preserves source metadata', () {
    const message = AiCoachMessage.user(
      'Uploaded medical report: blood-work.pdf',
      source: 'upload',
    );
    final json = message.toJson();
    final restored = AiCoachMessage.fromJson(Map<String, dynamic>.from(json));

    expect(json['source'], 'upload');
    expect(restored.source, 'upload');
    expect(restored.isUser, isTrue);
  });

  test('coach update parser syncs only completed intake reports', () {
    final partial = CoachUpdateParser.fromMessages(const [
      AiCoachMessage.assistant(
        'Intake summary for dashboard:\n- Main concern noted\n'
        'Doctor-ready report can be generated after more details.',
      ),
    ]);

    expect(partial.intakeSummary, contains('Main concern noted'));
    expect(partial.reports, isEmpty);
    expect(partial.intakeComplete, isFalse);

    final casual = CoachUpdateParser.fromMessages(const [
      AiCoachMessage.assistant(
        'We can add a reminder later, and a report can be generated after more details.',
      ),
    ]);
    expect(casual.reminders, isEmpty);
    expect(casual.reports, isEmpty);

    final complete = CoachUpdateParser.fromMessages(const [
      AiCoachMessage.assistant(
        'Intake status: complete\n'
        'Intake summary for dashboard:\n- Main concern noted\n'
        '- Risk flags clear\n'
        'App update:\n- Reminder: 8 AM water check\n'
        '- Dashboard: Sugar pattern is stable\n'
        '- Report: Doctor-ready sexual wellness intake PDF',
      ),
    ]);

    expect(complete.intakeComplete, isTrue);
    expect(complete.reminders.single, '8 AM water check');
    expect(
      complete.dashboardNotes.single,
      'Dashboard: Sugar pattern is stable',
    );
    expect(complete.reports.single, contains('Doctor-ready'));
  });

  test('coach update parser ignores upload summaries as app commands', () {
    final update = CoachUpdateParser.fromMessages(const [
      AiCoachMessage.assistant(
        'Report says vitamin D is low. Reminder can be added later.',
        source: 'upload',
      ),
    ]);

    expect(update.hasAny, isFalse);
  });

  testWidgets('shows approved health welcome flow', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(FlickoHealthApp(prefs: prefs));

    expect(find.text('Start your health plan'), findsOneWidget);
  });

  testWidgets('startup splash closes to the next app page', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      FlickoHealthApp(
        prefs: prefs,
        startupSplashDuration: const Duration(milliseconds: 500),
      ),
    );

    expect(find.byKey(const ValueKey('flicko-startup-splash')), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('flicko-startup-splash')), findsNothing);
    expect(find.text('Start your health plan'), findsOneWidget);
  });

  testWidgets('saved login opens dashboard directly with profile button', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'flicko_health_profile_v1':
          '{"firstName":"Aarav","email":"aarav@example.com","authToken":"saved-token","selectedProblems":["Weight management"],"safetyConsentAccepted":true}',
    });
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(FlickoHealthApp(prefs: prefs));
    await tester.pumpAndSettle();

    expect(find.text('Good morning, Aarav'), findsOneWidget);
    expect(find.text('Start your health plan'), findsNothing);
    expect(find.text('Login to Flicko.'), findsNothing);
    expect(find.byTooltip('Open profile'), findsOneWidget);

    await tester.tap(find.byTooltip('Open profile'));
    await tester.pumpAndSettle();
    expect(find.text('Profile'), findsOneWidget);

    await tester.tap(find.text('Edit setup'));
    await tester.pumpAndSettle();
    expect(find.text('Build your local profile.'), findsOneWidget);

    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Good morning, Aarav'), findsOneWidget);
    expect(find.text('Login to Flicko.'), findsNothing);
  });

  testWidgets('other problem card toggles off and removes custom problems', (
    tester,
  ) async {
    var draft = const HealthProfileDraft();

    await tester.pumpWidget(
      MaterialApp(
        theme: FlickoTheme.light,
        home: StatefulBuilder(
          builder: (context, setState) {
            return ProblemSelectionScreen(
              draft: draft,
              onChanged: (nextDraft) => setState(() => draft = nextDraft),
              onNext: () {},
              onBack: () {},
            );
          },
        ),
      ),
    );

    await tester.ensureVisible(find.text('Other problem'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Other problem'));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsOneWidget);

    await tester.tap(find.text('Other problem'));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsNothing);

    await tester.tap(find.text('Other problem'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Migraine');
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pumpAndSettle();

    expect(draft.selectedProblems.contains('Migraine'), isTrue);

    await tester.ensureVisible(find.text('Other problem'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Other problem'));
    await tester.pumpAndSettle();

    expect(draft.selectedProblems.contains('Migraine'), isFalse);
  });

  testWidgets('auth screen supports login register forgot and google actions', (
    tester,
  ) async {
    AuthResult? authenticated;
    final api = FakeAuthApiClient();

    await tester.pumpWidget(
      MaterialApp(
        theme: FlickoTheme.light,
        home: AuthAccessScreen(
          apiClient: api,
          onAuthenticated: (result) => authenticated = result,
          onBack: () {},
        ),
      ),
    );

    expect(find.text('Login to Flicko.'), findsOneWidget);
    expect(find.text('Continue with Google'), findsOneWidget);

    await tester.tap(find.text('Register'));
    await tester.pumpAndSettle();
    expect(find.text('Create your account.'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Full name'), findsOneWidget);

    await tester.tap(find.text('Forgot'));
    await tester.pumpAndSettle();
    expect(find.text('Recover password.'), findsOneWidget);
    expect(find.text('Send reset OTP'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Email'),
      'reset@example.com',
    );
    await tester.tap(find.text('Send reset OTP'));
    await tester.pumpAndSettle();
    expect(find.text('Set new password'), findsOneWidget);

    await tester.ensureVisible(find.text('Back to email'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Back to email'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Back to login'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Back to login'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Email'),
      'aarav@example.com',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Password'),
      'secret123',
    );
    await tester.tap(find.text('Login and continue'));
    await tester.pumpAndSettle();
    expect(authenticated?.user.email, 'aarav@example.com');
  });

  testWidgets('login with completed saved profile skips setup screens', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'flicko_health_profile_v1':
          '{"firstName":"Aarav","lastName":"Shah","email":"old@example.com","phone":"9876543210","selectedProblems":["Weight management"],"weightKg":"56","heightCm":"170","safetyConsentAccepted":true}',
    });
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(FlickoHealthApp(prefs: prefs));
    await tester.pumpAndSettle();

    expect(find.text('Good morning, Aarav'), findsOneWidget);
    expect(find.text('Login to Flicko.'), findsNothing);
    expect(find.text('Build your local profile.'), findsNothing);
  });

  testWidgets('consent safety screen requires acknowledgement', (tester) async {
    var accepted = false;

    await tester.pumpWidget(
      MaterialApp(
        home: ConsentSafetyScreen(
          onAccepted: () => accepted = true,
          onBack: () {},
        ),
      ),
    );

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -900));
    await tester.pumpAndSettle();

    final acceptButton = find.text('Accept and open dashboard');
    expect(acceptButton, findsOneWidget);

    await tester.tap(acceptButton);
    await tester.pumpAndSettle();
    expect(accepted, isFalse);

    await tester.tap(find.textContaining('I understand Flicko'));
    await tester.pumpAndSettle();

    await tester.tap(acceptButton);
    await tester.pumpAndSettle();
    expect(accepted, isTrue);
  });

  testWidgets('profile setup saves split identity and dual metric units', (
    tester,
  ) async {
    HealthProfileDraft? savedDraft;

    await tester.pumpWidget(
      MaterialApp(
        theme: FlickoTheme.light,
        home: ProfileSetupScreen(
          draft: const HealthProfileDraft(
            selectedProblems: {'Weight management'},
          ),
          onBack: () {},
          onSaved: (draft) => savedDraft = draft,
        ),
      ),
    );

    await tester.enterText(
      find.widgetWithText(TextFormField, 'First name'),
      'Aarav',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Middle name optional'),
      'K',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Last name'),
      'Shah',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Phone number'),
      '9876543210',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Email'),
      'aarav@example.com',
    );
    await tester.ensureVisible(find.text('Next: height and weight'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next: height and weight'));
    await tester.pumpAndSettle();

    expect(find.text('Weight'), findsOneWidget);
    expect(find.text('kg'), findsWidgets);
    expect(find.text('lb'), findsOneWidget);
    expect(find.text('cm'), findsWidgets);
    expect(find.text('ft / in'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Weight (kg)'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Weight (kg)'),
      '56',
    );
    await tester.pumpAndSettle();
    expect(find.text('56 kg saved with 123 lb backup'), findsOneWidget);

    await tester.tap(find.text('lb').first);
    await tester.pumpAndSettle();
    expect(find.text('lb'), findsWidgets);
    expect(find.widgetWithText(TextFormField, 'Weight (lb)'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Weight (lb)'),
      '180',
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('ft / in'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ft / in'));
    await tester.pumpAndSettle();
    expect(find.text('ft'), findsWidgets);
    expect(find.text('in'), findsWidgets);
    expect(find.widgetWithText(TextFormField, 'Feet'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Inches'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextFormField, 'Feet'), '6');
    await tester.enterText(find.widgetWithText(TextFormField, 'Inches'), '1');
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextFormField, 'Age'), '29');
    await tester.ensureVisible(find.text('Next: medical details'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next: medical details'));
    await tester.pumpAndSettle();

    expect(find.text('Medical profile.'), findsOneWidget);
    await tester.ensureVisible(find.text('Male'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Male'));
    await tester.ensureVisible(find.text('Hindi'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hindi'));
    await tester.ensureVisible(find.text('Asia/Kolkata'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Asia/Kolkata'));
    await tester.ensureVisible(
      find.widgetWithText(TextFormField, 'Goal weight kg optional'),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Goal weight kg optional'),
      '72',
    );
    await tester.ensureVisible(
      find.widgetWithText(TextFormField, 'Current medications optional'),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Current medications optional'),
      'Metformin 500 mg',
    );
    await tester.ensureVisible(
      find.widgetWithText(TextFormField, 'Allergies optional'),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Allergies optional'),
      'Peanuts',
    );
    await tester.ensureVisible(
      find.widgetWithText(TextFormField, 'Family history optional'),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Family history optional'),
      'Father diabetes',
    );
    final saveButton = find.widgetWithText(
      FilledButton,
      'Save profile and continue',
    );
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -700),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(saveButton);
    await tester.pumpAndSettle();
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(savedDraft, isNotNull);
    expect(savedDraft!.firstName, 'Aarav');
    expect(savedDraft!.middleName, 'K');
    expect(savedDraft!.lastName, 'Shah');
    expect(savedDraft!.email, 'aarav@example.com');
    expect(savedDraft!.weightKg, isIn(['81', '82']));
    expect(savedDraft!.weightLb, '180');
    expect(savedDraft!.goalWeightKg, '72');
    expect(savedDraft!.gender, 'Male');
    expect(savedDraft!.language, 'Hindi');
    expect(savedDraft!.timezone, 'Asia/Kolkata');
    expect(savedDraft!.medications, 'Metformin 500 mg');
    expect(savedDraft!.allergies, 'Peanuts');
    expect(savedDraft!.familyHistory, 'Father diabetes');
    expect(savedDraft!.heightCm, '185');
    expect(savedDraft!.heightFeet, '6');
    expect(savedDraft!.heightInches, '1');
  });

  testWidgets('dashboard shows dismissible BMI meter from saved metrics', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: FlickoTheme.light,
        home: DashboardScreen(
          draft: const HealthProfileDraft(
            firstName: 'Aarav',
            age: '29',
            heightCm: '170',
            weightKg: '56',
            selectedProblems: {'Weight management'},
          ),
          onBack: () {},
          onEditProfile: () {},
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Your BMI meter'), findsOneWidget);
    expect(find.text('19.4'), findsOneWidget);
    expect(find.text('Healthy range'), findsOneWidget);
    expect(find.text('56 kg'), findsOneWidget);

    await tester.ensureVisible(find.text('Ignore for now'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ignore for now'));
    await tester.pumpAndSettle();

    expect(find.text('Your BMI meter'), findsNothing);
  });

  testWidgets('problem dashboard starts with AI call then unlocks cards', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ProblemDashboardScreen(
          profile: DashboardUserProfile(
            firstName: 'Aarav',
            profileContext:
                'Selected problems: Diabetes Type 2\nAge: 29\nWeight: 56 kg',
            selectedProblems: const {'Diabetes Type 2'},
            onEditProfile: () {},
          ),
        ),
      ),
    );

    expect(find.text('Good morning, Aarav'), findsOneWidget);
    expect(find.text('Diabetes care plan active'), findsOneWidget);
    expect(find.text('AI health call preparing'), findsOneWidget);
    expect(find.text('3 min'), findsOneWidget);
    expect(find.text('Call now'), findsOneWidget);
    expect(find.text('Dashboard'), findsOneWidget);
    expect(find.text('AI Coach'), findsOneWidget);
    expect(find.text('Management'), findsOneWidget);
    expect(find.text('Reports'), findsOneWidget);

    await tester.tap(find.text('Call now'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));

    expect(find.text('Flicko Health Coach'), findsOneWidget);
    expect(find.text('Live health check-in'), findsOneWidget);
    expect(find.text('Live call status'), findsOneWidget);
    expect(find.text('Mic'), findsOneWidget);
    expect(find.text('Speaker'), findsWidgets);
    expect(find.text('End call'), findsOneWidget);
    expect(find.text('Chat'), findsOneWidget);

    await tester.tap(find.text('End call'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    expect(find.text("Today's Diabetes Score"), findsNothing);
    expect(find.text('Building your real dashboard'), findsNothing);
    expect(find.text('AI health call preparing'), findsOneWidget);
    expect(
      find.textContaining('Call ended before enough setup details'),
      findsOneWidget,
    );

    await tester.tap(find.text('AI Coach').last);
    await tester.pumpAndSettle();

    expect(find.text('Flicko AI Coach'), findsOneWidget);
    expect(find.text('Aarav - Diabetes plan'), findsOneWidget);
    expect(find.byTooltip('Back to dashboard'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.byTooltip('Attach'), findsOneWidget);
    expect(find.byTooltip('Voice'), findsOneWidget);
    expect(
      find.widgetWithIcon(FilledButton, Icons.call_rounded),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.arrow_upward_rounded), findsOneWidget);
    expect(find.text('Dashboard'), findsNothing);
  });

  testWidgets('problem dashboard skips BMI dialog after intro was seen', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ProblemDashboardScreen(
          profile: DashboardUserProfile(
            firstName: 'Aarav',
            profileContext:
                'Selected problems: Weight management\nAge: 29\nWeight: 56 kg',
            selectedProblems: const {'Weight management'},
            onEditProfile: () {},
            shouldShowBmiIntro: false,
            bmiSnapshot: BmiSnapshot.fromProfileMetrics(
              weightKg: '56',
              weightLb: '',
              heightCm: '170',
              heightFeet: '',
              heightInches: '',
              age: '29',
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Call now'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byIcon(Icons.call_end_rounded));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    expect(find.text('Your BMI meter'), findsNothing);
  });

  testWidgets('management tab shows local health logs and quick add actions', (
    tester,
  ) async {
    HealthLogEntry? addedLog;

    await tester.pumpWidget(
      MaterialApp(
        home: ProblemDashboardScreen(
          profile: DashboardUserProfile(
            firstName: 'Aarav',
            profileContext:
                'Selected problems: Weight management\nAge: 29\nWeight: 56 kg',
            selectedProblems: const {'Weight management'},
            onEditProfile: () {},
            shouldShowBmiIntro: false,
            healthLogs: [
              HealthLogEntry.create(
                type: HealthLogType.weight,
                title: 'Weight log',
                value: '56',
                unit: 'kg',
                note: 'Morning weigh-in',
                problemName: 'Weight management',
              ),
            ],
            onAddHealthLog: (entry) => addedLog = entry,
          ),
        ),
      ),
    );

    await tester.tap(find.text('Call now'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byIcon(Icons.call_end_rounded));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    await tester.tap(find.text('Management'));
    await tester.pumpAndSettle();

    expect(find.text('Quick log'), findsOneWidget);
    expect(find.text('Recent local logs'), findsOneWidget);
    expect(find.text('Weight log'), findsOneWidget);
    expect(find.textContaining('56 kg'), findsOneWidget);

    await tester.tap(find.text('Meal'));
    await tester.pumpAndSettle();

    expect(addedLog, isNotNull);
    expect(addedLog!.type, HealthLogType.meal);
  });

  testWidgets('management schedule filters split now missed later and done', (
    tester,
  ) async {
    String formatTimeLabel(DateTime value) {
      final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
      final minute = value.minute.toString().padLeft(2, '0');
      final suffix = value.hour >= 12 ? 'PM' : 'AM';
      return '$hour:$minute $suffix';
    }

    final now = DateTime(2026, 1, 1, 12, 0);
    final dueReminder = FlickoSavedReminder(
      id: 'due-reminder',
      title: 'Current reminder',
      body: 'Take action now',
      hour: now.hour,
      minute: now.minute,
      problemName: 'Weight management',
      createdAt: now,
      updatedAt: now,
    );
    final missedTask = FlickoCareTask.create(
      type: FlickoCareTaskType.medicine,
      title: 'Missed tablet',
      detail: 'Evening dose',
      timeLabel: formatTimeLabel(now.subtract(const Duration(hours: 2))),
      problemName: 'Weight management',
    );
    final laterTask = FlickoCareTask.create(
      type: FlickoCareTaskType.water,
      title: 'Water target',
      detail: 'Drink 500 ml',
      timeLabel: formatTimeLabel(now.add(const Duration(hours: 2))),
      problemName: 'Weight management',
    );
    final completedAt = now;
    final completedTask = FlickoCareTask.create(
      type: FlickoCareTaskType.meal,
      title: 'Breakfast done',
      detail: 'Completed',
      timeLabel: formatTimeLabel(now.subtract(const Duration(hours: 1))),
      problemName: 'Weight management',
    ).copyWith(lastCompletedAt: completedAt, updatedAt: completedAt);

    await tester.pumpWidget(
      MaterialApp(
        home: ProblemDashboardScreen(
          profile: DashboardUserProfile(
            firstName: 'Aarav',
            profileContext:
                'Selected problems: Weight management\nAge: 29\nWeight: 56 kg',
            selectedProblems: const {'Weight management'},
            onEditProfile: () {},
            shouldShowBmiIntro: false,
            savedReminders: [dueReminder],
            careTasks: [missedTask, laterTask, completedTask],
          ),
          nowProvider: () => now,
        ),
      ),
    );

    await tester.tap(find.text('Call now'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byIcon(Icons.call_end_rounded));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    await tester.tap(find.text('Management'));
    await tester.pumpAndSettle();

    expect(find.text('3 active'), findsOneWidget);
    expect(find.text('1 completed item today'), findsOneWidget);
    expect(find.textContaining('Breakfast done'), findsOneWidget);
    expect(find.text('1 item needs attention now'), findsOneWidget);
    expect(find.text('1 missed item today'), findsOneWidget);

    await tester.tap(
      find.ancestor(of: find.text('Now'), matching: find.byType(InkWell)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Current reminder'), findsOneWidget);
    expect(find.text('Missed tablet'), findsNothing);
    expect(find.text('Water target'), findsNothing);

    await tester.tap(
      find.ancestor(of: find.text('Missed'), matching: find.byType(InkWell)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Missed tablet'), findsOneWidget);
    expect(find.text('Current reminder'), findsNothing);
    expect(find.text('Water target'), findsNothing);

    await tester.tap(
      find.ancestor(of: find.text('Later'), matching: find.byType(InkWell)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Water target'), findsOneWidget);
    expect(find.text('Missed tablet'), findsNothing);
    expect(find.text('Current reminder'), findsNothing);

    await tester.tap(
      find
          .ancestor(of: find.text('Done'), matching: find.byType(InkWell))
          .first,
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Breakfast done'), findsOneWidget);
    expect(find.text('Current reminder'), findsNothing);
    expect(find.text('Missed tablet'), findsNothing);

    await tester.tap(
      find.ancestor(of: find.text('All'), matching: find.byType(InkWell)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Current reminder'), findsOneWidget);
    expect(find.text('Missed tablet'), findsOneWidget);
    expect(find.text('Water target'), findsOneWidget);
  });

  test(
    'dashboard resolver covers every onboarding health problem explicitly',
    () {
      const expectedProblems = [
        'Weight management',
        'Diabetes Type 1',
        'Diabetes Type 2',
        'Blood pressure',
        'Heart health',
        'PCOS/PCOD',
        'Thyroid',
        'Pregnancy',
        'Preconception',
        'Postpartum',
        'Digestive health',
        'Sleep health',
        'Stress and mood',
        'Fitness',
        'Skin and hair',
        'General wellness',
        "Women's wellness",
        'Senior care',
        'Sexual health',
        'Autoimmune support',
        'Acidity and bloating',
        'Cholesterol',
        'Habit reset',
        'Other problem',
      ];

      expect(DashboardProblemResolver.supportedProblems, expectedProblems);

      for (final problem in expectedProblems) {
        final config = DashboardProblemResolver.configFor(problem);
        expect(config.problemName.trim(), isNotEmpty, reason: problem);
        expect(
          config.scoreTitle,
          isNot("Today's Health Score"),
          reason: '$problem must not fall back to the generic dashboard',
        );
        expect(config.metricTitle.trim(), isNotEmpty, reason: problem);
        expect(config.planFocus.trim(), isNotEmpty, reason: problem);
        expect(config.reportTitle.trim(), isNotEmpty, reason: problem);
      }

      expect(
        DashboardProblemResolver.primaryProblem({
          'Habit reset',
          'Diabetes Type 2',
        }),
        'Diabetes Type 2',
      );
      expect(DashboardProblemResolver.primaryProblem({'Migraine'}), 'Migraine');
      expect(
        DashboardProblemResolver.primaryProblem({'Other problem', 'Migraine'}),
        'Migraine',
      );
    },
  );

  test(
    'deterministic safety engine catches emergency and urgent red flags',
    () {
      final chestPain = FlickoSafetyEngine.evaluate(
        text: 'I have chest pain and sweating since morning',
        problemName: 'Heart health',
        source: 'chat',
      );

      expect(chestPain, isNotNull);
      expect(chestPain!.severity, FlickoSafetySeverity.emergency);
      expect(chestPain.mustStopNormalCoaching, isTrue);
      expect(chestPain.ruleId, 'chest-pain');

      final heartPain = FlickoSafetyEngine.evaluate(
        text: 'Very critical, my heart pain is strong',
        problemName: 'Heart health',
        source: 'call',
      );

      expect(heartPain, isNotNull);
      expect(heartPain!.severity, FlickoSafetySeverity.emergency);
      expect(heartPain.ruleId, 'chest-pain');

      final hinglishChestPain = FlickoSafetyEngine.evaluate(
        text: 'Mere chaise me pain he',
        problemName: 'Heart health',
        source: 'call',
      );

      expect(hinglishChestPain, isNotNull);
      expect(hinglishChestPain!.severity, FlickoSafetySeverity.emergency);
      expect(hinglishChestPain.ruleId, 'chest-pain');

      final emergencyContactRequest = FlickoSafetyEngine.evaluate(
        text: 'Please connect my emergency contact now',
        problemName: 'General wellness',
        source: 'chat',
      );

      expect(emergencyContactRequest, isNotNull);
      expect(emergencyContactRequest!.severity, FlickoSafetySeverity.emergency);
      expect(emergencyContactRequest.ruleId, 'emergency-contact-request');

      final typoEmergencyCall = FlickoSafetyEngine.evaluate(
        text: 'conect the my emenrcy contact',
        problemName: 'General wellness',
        source: 'chat',
      );

      expect(typoEmergencyCall, isNotNull);
      expect(typoEmergencyCall!.ruleId, 'emergency-contact-request');

      final highBp = FlickoSafetyEngine.evaluate(
        text: 'My BP is 180/120 and I feel dizzy',
        problemName: 'Blood pressure',
        source: 'manual',
      );

      expect(highBp, isNotNull);
      expect(highBp!.severity, FlickoSafetySeverity.emergency);
      expect(highBp.ruleId, 'bp-crisis');

      final sexualHealth = FlickoSafetyEngine.evaluate(
        text: 'I have severe testicle pain',
        problemName: 'Sexual health',
        source: 'chat',
      );

      expect(sexualHealth, isNotNull);
      expect(sexualHealth!.severity, FlickoSafetySeverity.urgent);
      expect(sexualHealth.mustStopNormalCoaching, isTrue);
    },
  );

  test(
    'profile store fallback reads writes and clears legacy storage',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = FlickoSharedPreferencesProfileStore(prefs: prefs);

      await store.writeProfileJson('{"firstName":"Aarav"}');
      expect(await store.readProfileJson(), '{"firstName":"Aarav"}');

      await store.clearProfile();
      expect(await store.readProfileJson(), isNull);
    },
  );
}

class FakeAuthApiClient extends AuthApiClient {
  const FakeAuthApiClient();

  @override
  Future<AuthResult> login({
    required String email,
    required String password,
  }) async {
    return AuthResult(
      token: 'test-token',
      user: AuthUser(
        name: 'Aarav Shah',
        email: email,
        mobile: '9876543210',
        profile: const <String, dynamic>{},
      ),
    );
  }

  @override
  Future<void> registerStart({
    required String name,
    required String email,
    required String mobile,
    required String password,
  }) async {}

  @override
  Future<AuthResult> registerVerify({
    required String email,
    required String otp,
  }) async {
    return AuthResult(
      token: 'registered-token',
      user: AuthUser(
        name: 'Aarav Shah',
        email: email,
        mobile: '9876543210',
        profile: const <String, dynamic>{},
      ),
    );
  }

  @override
  Future<void> forgotPasswordStart({required String email}) async {}

  @override
  Future<void> resetPassword({
    required String email,
    required String otp,
    required String newPassword,
  }) async {}
}
