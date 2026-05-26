import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'backend_api_defaults.dart';
import 'flicko_motion.dart';
import 'features/auth/flicko_google_sign_in.dart';
import 'features/bmi/bmi_meter_dialog.dart';
import 'features/bmi/bmi_snapshot.dart';
import 'features/dashboard/ai_call_invite_page.dart';
import 'features/dashboard/ai_call_memory.dart';
import 'features/dashboard/ai_call_models.dart';
import 'features/dashboard/ai_call_transcript_store.dart';
import 'features/dashboard/ai_call_warmup.dart';
import 'features/dashboard/ai_health_call_page.dart';
import 'features/dashboard/dashboard.dart';
import 'features/dashboard/coach_update_parser.dart';
import 'features/dashboard/dashboard_reports_view.dart';
import 'features/dashboard/dashboard_live_insights.dart';
import 'features/dashboard/flicko_dashboard_entry_coordinator.dart';
import 'features/dashboard/flicko_call_invite_coordinator.dart';
import 'features/dashboard/flicko_call_completion_coordinator.dart';
import 'features/dashboard/flicko_call_completion_effect_executor.dart';
import 'features/dashboard/flicko_call_invite_dispatch_coordinator.dart';
import 'features/dashboard/flicko_call_invite_ingress_coordinator.dart';
import 'features/dashboard/flicko_call_invite_runtime_coordinator.dart';
import 'features/dashboard/flicko_interrupted_call_recovery_coordinator.dart';
import 'features/dashboard/flicko_report_generation_coordinator.dart';
import 'features/dashboard/flicko_call_route_coordinator.dart';
import 'features/dashboard/flicko_live_call_workflow_runner.dart';
import 'features/dashboard/flicko_live_call_resume_coordinator.dart';
import 'features/dashboard/gemini_health_chat_client.dart';
import 'features/dashboard/health_profile_api_client.dart';
import 'features/dashboard/health_report_api_client.dart';
import 'features/dashboard/live_call_foreground_service.dart';
import 'features/dashboard/native_call_invite_bridge.dart';
import 'features/logs/health_log_entry.dart';
import 'features/management/flicko_care_task.dart';
import 'features/meals/meal_analysis_entry.dart';
import 'features/onboarding/consent_safety_screen.dart';
import 'features/onboarding/medical_profile_step.dart';
import 'features/reminders/flicko_notification_service.dart';
import 'features/reminders/flicko_saved_reminder.dart';
import 'features/safety/flicko_safety_engine.dart';
import 'features/storage/flicko_profile_store.dart';
import 'features/sync/flicko_app_record_sync_coordinator.dart';
import 'features/sync/flicko_backend_app_data_hydrator.dart';
import 'features/sync/flicko_pending_app_record_op.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final profileStore = FlickoSecureProfileStore(legacyPrefs: prefs);
  final initialProfileJson = await profileStore.readProfileJson();
  runApp(
    FlickoHealthApp(
      prefs: prefs,
      profileStore: profileStore,
      initialProfileJson: initialProfileJson,
    ),
  );
}

class FlickoHealthApp extends StatefulWidget {
  const FlickoHealthApp({
    super.key,
    required this.prefs,
    this.profileStore,
    this.initialProfileJson,
    this.startupSplashDuration = const Duration(milliseconds: 1300),
  });

  final SharedPreferences prefs;
  final FlickoProfileStore? profileStore;
  final String? initialProfileJson;
  final Duration startupSplashDuration;

  @override
  State<FlickoHealthApp> createState() => _FlickoHealthAppState();
}

class _FlickoHealthAppState extends State<FlickoHealthApp> {
  late final FlickoProfileStore _profileStore;
  late HealthProfileDraft _draft;
  Timer? _startupSplashTimer;
  late bool _showStartupSplash;

  @override
  void initState() {
    super.initState();
    _showStartupSplash = widget.startupSplashDuration > Duration.zero;
    _profileStore =
        widget.profileStore ??
        FlickoSharedPreferencesProfileStore(prefs: widget.prefs);
    _draft = HealthProfileDraft.fromStorage(
      widget.initialProfileJson ??
          widget.prefs.getString(FlickoSecureProfileStore.legacyProfileKey),
    );
    if (_showStartupSplash) {
      _startupSplashTimer = Timer(
        widget.startupSplashDuration,
        _closeStartupSplash,
      );
    }
  }

  Future<void> _saveDraft(HealthProfileDraft draft) async {
    setState(() => _draft = draft);
    if (draft == const HealthProfileDraft()) {
      await _profileStore.clearProfile();
      return;
    }
    await _profileStore.writeProfileJson(jsonEncode(draft.toJson()));
  }

  void _closeStartupSplash() {
    if (!mounted || !_showStartupSplash) {
      return;
    }
    setState(() => _showStartupSplash = false);
  }

  @override
  void dispose() {
    _startupSplashTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Flicko Health',
      theme: FlickoTheme.light,
      scrollBehavior: const FlickoScrollBehavior(),
      home: FlickoStartupSplashGate(
        showSplash: _showStartupSplash,
        splashDuration: widget.startupSplashDuration,
        child: HealthOnboardingFlow(draft: _draft, onDraftChanged: _saveDraft),
      ),
    );
  }
}

class FlickoStartupSplashGate extends StatelessWidget {
  const FlickoStartupSplashGate({
    super.key,
    required this.showSplash,
    required this.splashDuration,
    required this.child,
  });

  final bool showSplash;
  final Duration splashDuration;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        TickerMode(enabled: !showSplash, child: child),
        Positioned.fill(
          child: IgnorePointer(
            ignoring: !showSplash,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 360),
              reverseDuration: const Duration(milliseconds: 280),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              child: showSplash
                  ? FlickoStartupSplashScreen(
                      key: const ValueKey('flicko-startup-splash'),
                      splashDuration: splashDuration,
                    )
                  : const SizedBox.shrink(
                      key: ValueKey('flicko-startup-empty'),
                    ),
            ),
          ),
        ),
      ],
    );
  }
}

class FlickoStartupSplashScreen extends StatelessWidget {
  const FlickoStartupSplashScreen({super.key, required this.splashDuration});

  final Duration splashDuration;

  Duration get _progressDuration {
    final milliseconds = splashDuration.inMilliseconds - 180;
    return Duration(milliseconds: milliseconds < 450 ? 450 : milliseconds);
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFFAFCF8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final screenHeight = constraints.maxHeight.isFinite
              ? constraints.maxHeight
              : MediaQuery.of(context).size.height;
          final heroHeight = screenHeight < 720
              ? screenHeight * 0.58
              : screenHeight * 0.64;
          final bottomPadding = MediaQuery.of(context).padding.bottom;

          return Stack(
            children: [
              Positioned(
                left: 0,
                right: -30,
                top: 0,
                height: heroHeight,
                child: const WelcomeImageHero(),
              ),
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                height: heroHeight,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        const Color(0xFFFAFCF8).withValues(alpha: 0.92),
                        const Color(0xFFFAFCF8).withValues(alpha: 0.18),
                        const Color(0xFFFAFCF8).withValues(alpha: 0),
                        const Color(0xFFFAFCF8).withValues(alpha: 0.96),
                      ],
                      stops: const [0, 0.20, 0.55, 1],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                top: heroHeight - 190,
                bottom: 0,
                child: const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Color(0x00FAFCF8),
                        Color(0xEFFFFFF8),
                        Color(0xFFFAFCF8),
                      ],
                      stops: [0, 0.30, 0.66],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                ),
              ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(22, 10, 22, 0),
                  child: Row(
                    children: [
                      const PageCornerLogo(compact: true),
                      const Spacer(),
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.82),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: FlickoTheme.teal.withValues(alpha: 0.12),
                          ),
                        ),
                        child: const Icon(
                          Icons.monitor_heart_rounded,
                          color: FlickoTheme.tealDark,
                          size: 22,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: 22,
                right: 22,
                bottom: bottomPadding + 30,
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 18, end: 0),
                  duration: const Duration(milliseconds: 760),
                  curve: Curves.easeOutCubic,
                  builder: (context, offset, child) {
                    return Transform.translate(
                      offset: Offset(0, offset),
                      child: Opacity(
                        opacity: ((18 - offset) / 18).clamp(0.0, 1.0),
                        child: child,
                      ),
                    );
                  },
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Image.asset(
                        'assets/images/mainlogo.png',
                        width: 220,
                        height: 96,
                        fit: BoxFit.contain,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Health help that feels personal.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineLarge
                            ?.copyWith(
                              color: const Color(0xFF10231D),
                              fontSize: 27,
                              height: 1.08,
                              fontFamily: 'serif',
                              fontFamilyFallback: const ['Georgia', 'Roboto'],
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        width: 260,
                        height: 58,
                        child: CustomPaint(
                          painter: const FlickoSplashPulsePainter(),
                        ),
                      ),
                      const SizedBox(height: 14),
                      _FlickoStartupProgressBar(duration: _progressDuration),
                      const SizedBox(height: 16),
                      Container(
                        constraints: const BoxConstraints(minHeight: 44),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.82),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: FlickoTheme.teal.withValues(alpha: 0.12),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: FlickoTheme.tealDark.withValues(
                                alpha: 0.08,
                              ),
                              blurRadius: 18,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Icon(
                              Icons.lock_rounded,
                              color: FlickoTheme.tealDark,
                              size: 16,
                            ),
                            SizedBox(width: 8),
                            Text(
                              'Opening your health space',
                              style: TextStyle(
                                color: FlickoTheme.tealDark,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            SizedBox(width: 10),
                            _FlickoSplashSignalDot(delay: 0),
                            SizedBox(width: 5),
                            _FlickoSplashSignalDot(delay: 160),
                            SizedBox(width: 5),
                            _FlickoSplashSignalDot(delay: 320),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _FlickoStartupProgressBar extends StatelessWidget {
  const _FlickoStartupProgressBar({required this.duration});

  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 210,
      height: 7,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.86),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: FlickoTheme.teal.withValues(alpha: 0.10)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.18, end: 1),
          duration: duration,
          curve: Curves.easeInOutCubic,
          builder: (context, value, child) {
            return Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: value,
                heightFactor: 1,
                child: child,
              ),
            );
          },
          child: const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF21B497), FlickoTheme.teal],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FlickoSplashSignalDot extends StatelessWidget {
  const _FlickoSplashSignalDot({required this.delay});

  final int delay;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.42, end: 1),
      duration: Duration(milliseconds: 720 + delay),
      curve: Curves.easeInOut,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.scale(scale: value, child: child),
        );
      },
      child: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: FlickoTheme.teal.withValues(alpha: 0.72),
        ),
      ),
    );
  }
}

class FlickoSplashPulsePainter extends CustomPainter {
  const FlickoSplashPulsePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final baseline = size.height * 0.55;
    final lift = size.height * 0.30;
    final drop = size.height * 0.26;
    final spike = size.height * 0.42;
    final path = Path()
      ..moveTo(0, baseline)
      ..lineTo(size.width * 0.18, baseline)
      ..lineTo(size.width * 0.23, baseline - lift)
      ..lineTo(size.width * 0.29, baseline + drop)
      ..lineTo(size.width * 0.34, baseline - spike)
      ..lineTo(size.width * 0.40, baseline)
      ..lineTo(size.width * 0.58, baseline)
      ..lineTo(size.width * 0.64, baseline + drop * 0.72)
      ..lineTo(size.width * 0.70, baseline - lift * 0.72)
      ..lineTo(size.width * 0.76, baseline)
      ..lineTo(size.width, baseline);

    final paint = Paint()
      ..color = FlickoTheme.teal.withValues(alpha: 0.13)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant FlickoSplashPulsePainter oldDelegate) => false;
}

class HealthProfileDraft {
  const HealthProfileDraft({
    this.name = '',
    this.firstName = '',
    this.middleName = '',
    this.lastName = '',
    this.age = '',
    this.phone = '',
    this.email = '',
    this.heightCm = '',
    this.heightFeet = '',
    this.heightInches = '',
    this.weightKg = '',
    this.weightLb = '',
    this.goalWeightKg = '',
    this.goalWeightLb = '',
    this.gender = '',
    this.timezone = '',
    this.language = '',
    this.foodPreference = '',
    this.medications = '',
    this.allergies = '',
    this.diagnosis = '',
    this.surgeryHistory = '',
    this.familyHistory = '',
    this.pregnancyCycle = '',
    this.emergencyContactName = '',
    this.emergencyContactPhone = '',
    this.authToken = '',
    this.lastAiCallInviteAt = '',
    this.lastAiCallCompletedAt = '',
    this.aiCallInviteLog = const <String, String>{},
    this.bmiIntroSeen = false,
    this.safetyConsentAccepted = false,
    this.intakeSummary = '',
    this.intakeCompleted = false,
    this.dashboardNotes = const <String>[],
    this.reminders = const <String>[],
    this.reports = const <String>[],
    this.syncedReportKeys = const <String>[],
    this.backendDashboardSummary = const <String, Object?>{},
    this.pendingAppRecordOps = const <FlickoPendingAppRecordOp>[],
    this.callMemories = const <HealthCallMemorySummary>[],
    this.chatHistory = const <AiCoachMessage>[],
    this.healthLogs = const <HealthLogEntry>[],
    this.mealAnalyses = const <MealAnalysisEntry>[],
    this.safetyEvents = const <FlickoSafetyEvent>[],
    this.savedReminders = const <FlickoSavedReminder>[],
    this.careTasks = const <FlickoCareTask>[],
    this.selectedProblems = const <String>{},
  });

  final String name;
  final String firstName;
  final String middleName;
  final String lastName;
  final String age;
  final String phone;
  final String email;
  final String heightCm;
  final String heightFeet;
  final String heightInches;
  final String weightKg;
  final String weightLb;
  final String goalWeightKg;
  final String goalWeightLb;
  final String gender;
  final String timezone;
  final String language;
  final String foodPreference;
  final String medications;
  final String allergies;
  final String diagnosis;
  final String surgeryHistory;
  final String familyHistory;
  final String pregnancyCycle;
  final String emergencyContactName;
  final String emergencyContactPhone;
  final String authToken;
  final String lastAiCallInviteAt;
  final String lastAiCallCompletedAt;
  final Map<String, String> aiCallInviteLog;
  final bool bmiIntroSeen;
  final bool safetyConsentAccepted;
  final String intakeSummary;
  final bool intakeCompleted;
  final List<String> dashboardNotes;
  final List<String> reminders;
  final List<String> reports;
  final List<String> syncedReportKeys;
  final Map<String, Object?> backendDashboardSummary;
  final List<FlickoPendingAppRecordOp> pendingAppRecordOps;
  final List<HealthCallMemorySummary> callMemories;
  final List<AiCoachMessage> chatHistory;
  final List<HealthLogEntry> healthLogs;
  final List<MealAnalysisEntry> mealAnalyses;
  final List<FlickoSafetyEvent> safetyEvents;
  final List<FlickoSavedReminder> savedReminders;
  final List<FlickoCareTask> careTasks;
  final Set<String> selectedProblems;

  String get displayName {
    final parts = [
      firstName,
      middleName,
      lastName,
    ].map((value) => value.trim()).where((value) => value.isNotEmpty).toList();
    if (parts.isNotEmpty) {
      return parts.join(' ');
    }
    return name.trim();
  }

  String get givenName {
    if (firstName.trim().isNotEmpty) {
      return firstName.trim();
    }
    final fallback = displayName;
    return fallback.isEmpty ? '' : fallback.split(RegExp(r'\s+')).first;
  }

  bool get hasProfile =>
      displayName.trim().isNotEmpty && selectedProblems.isNotEmpty;

  bool get isAuthenticated => authToken.trim().isNotEmpty;

  bool get hasCompletedSetup => hasProfile && safetyConsentAccepted;

  bool get shouldOpenDashboard => hasCompletedSetup;

  HealthProfileDraft copyWith({
    String? name,
    String? firstName,
    String? middleName,
    String? lastName,
    String? age,
    String? phone,
    String? email,
    String? heightCm,
    String? heightFeet,
    String? heightInches,
    String? weightKg,
    String? weightLb,
    String? goalWeightKg,
    String? goalWeightLb,
    String? gender,
    String? timezone,
    String? language,
    String? foodPreference,
    String? medications,
    String? allergies,
    String? diagnosis,
    String? surgeryHistory,
    String? familyHistory,
    String? pregnancyCycle,
    String? emergencyContactName,
    String? emergencyContactPhone,
    String? authToken,
    String? lastAiCallInviteAt,
    String? lastAiCallCompletedAt,
    Map<String, String>? aiCallInviteLog,
    bool? bmiIntroSeen,
    bool? safetyConsentAccepted,
    String? intakeSummary,
    bool? intakeCompleted,
    List<String>? dashboardNotes,
    List<String>? reminders,
    List<String>? reports,
    List<String>? syncedReportKeys,
    Map<String, Object?>? backendDashboardSummary,
    List<FlickoPendingAppRecordOp>? pendingAppRecordOps,
    List<HealthCallMemorySummary>? callMemories,
    List<AiCoachMessage>? chatHistory,
    List<HealthLogEntry>? healthLogs,
    List<MealAnalysisEntry>? mealAnalyses,
    List<FlickoSafetyEvent>? safetyEvents,
    List<FlickoSavedReminder>? savedReminders,
    List<FlickoCareTask>? careTasks,
    Set<String>? selectedProblems,
  }) {
    return HealthProfileDraft(
      name: name ?? this.name,
      firstName: firstName ?? this.firstName,
      middleName: middleName ?? this.middleName,
      lastName: lastName ?? this.lastName,
      age: age ?? this.age,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      heightCm: heightCm ?? this.heightCm,
      heightFeet: heightFeet ?? this.heightFeet,
      heightInches: heightInches ?? this.heightInches,
      weightKg: weightKg ?? this.weightKg,
      weightLb: weightLb ?? this.weightLb,
      goalWeightKg: goalWeightKg ?? this.goalWeightKg,
      goalWeightLb: goalWeightLb ?? this.goalWeightLb,
      gender: gender ?? this.gender,
      timezone: timezone ?? this.timezone,
      language: language ?? this.language,
      foodPreference: foodPreference ?? this.foodPreference,
      medications: medications ?? this.medications,
      allergies: allergies ?? this.allergies,
      diagnosis: diagnosis ?? this.diagnosis,
      surgeryHistory: surgeryHistory ?? this.surgeryHistory,
      familyHistory: familyHistory ?? this.familyHistory,
      pregnancyCycle: pregnancyCycle ?? this.pregnancyCycle,
      emergencyContactName: emergencyContactName ?? this.emergencyContactName,
      emergencyContactPhone:
          emergencyContactPhone ?? this.emergencyContactPhone,
      authToken: authToken ?? this.authToken,
      lastAiCallInviteAt: lastAiCallInviteAt ?? this.lastAiCallInviteAt,
      lastAiCallCompletedAt:
          lastAiCallCompletedAt ?? this.lastAiCallCompletedAt,
      aiCallInviteLog: aiCallInviteLog ?? this.aiCallInviteLog,
      bmiIntroSeen: bmiIntroSeen ?? this.bmiIntroSeen,
      safetyConsentAccepted:
          safetyConsentAccepted ?? this.safetyConsentAccepted,
      intakeSummary: intakeSummary ?? this.intakeSummary,
      intakeCompleted: intakeCompleted ?? this.intakeCompleted,
      dashboardNotes: dashboardNotes ?? this.dashboardNotes,
      reminders: reminders ?? this.reminders,
      reports: reports ?? this.reports,
      syncedReportKeys: syncedReportKeys ?? this.syncedReportKeys,
      backendDashboardSummary:
          backendDashboardSummary ?? this.backendDashboardSummary,
      pendingAppRecordOps: pendingAppRecordOps ?? this.pendingAppRecordOps,
      callMemories: callMemories ?? this.callMemories,
      chatHistory: chatHistory ?? this.chatHistory,
      healthLogs: healthLogs ?? this.healthLogs,
      mealAnalyses: mealAnalyses ?? this.mealAnalyses,
      safetyEvents: safetyEvents ?? this.safetyEvents,
      savedReminders: savedReminders ?? this.savedReminders,
      careTasks: careTasks ?? this.careTasks,
      selectedProblems: selectedProblems ?? this.selectedProblems,
    );
  }

  Map<String, Object> toJson() {
    return {
      'name': displayName,
      'firstName': firstName,
      'middleName': middleName,
      'lastName': lastName,
      'age': age,
      'phone': phone,
      'email': email,
      'heightCm': heightCm,
      'heightFeet': heightFeet,
      'heightInches': heightInches,
      'weightKg': weightKg,
      'weightLb': weightLb,
      'goalWeightKg': goalWeightKg,
      'goalWeightLb': goalWeightLb,
      'gender': gender,
      'timezone': timezone,
      'language': language,
      'foodPreference': foodPreference,
      'medications': medications,
      'allergies': allergies,
      'diagnosis': diagnosis,
      'surgeryHistory': surgeryHistory,
      'familyHistory': familyHistory,
      'pregnancyCycle': pregnancyCycle,
      'emergencyContactName': emergencyContactName,
      'emergencyContactPhone': emergencyContactPhone,
      'authToken': authToken,
      'lastAiCallInviteAt': lastAiCallInviteAt,
      'lastAiCallCompletedAt': lastAiCallCompletedAt,
      'aiCallInviteLog': aiCallInviteLog,
      'bmiIntroSeen': bmiIntroSeen,
      'safetyConsentAccepted': safetyConsentAccepted,
      'intakeSummary': intakeSummary,
      'intakeCompleted': intakeCompleted,
      'dashboardNotes': dashboardNotes,
      'reminders': reminders,
      'reports': reports,
      'syncedReportKeys': syncedReportKeys,
      'backendDashboardSummary': backendDashboardSummary,
      'pendingAppRecordOps': pendingAppRecordOps
          .map((operation) => operation.toJson())
          .toList(),
      'callMemories': callMemories.map((memory) => memory.toJson()).toList(),
      'chatHistory': chatHistory.map((message) => message.toJson()).toList(),
      'healthLogs': healthLogs.map((entry) => entry.toJson()).toList(),
      'mealAnalyses': mealAnalyses.map((entry) => entry.toJson()).toList(),
      'safetyEvents': safetyEvents.map((entry) => entry.toJson()).toList(),
      'savedReminders': savedReminders
          .map((reminder) => reminder.toJson())
          .toList(),
      'careTasks': careTasks.map((task) => task.toJson()).toList(),
      'selectedProblems': selectedProblems.toList()..sort(),
    };
  }

  static HealthProfileDraft fromStorage(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return const HealthProfileDraft();
    }
    try {
      final data = jsonDecode(raw);
      if (data is! Map<String, dynamic>) {
        return const HealthProfileDraft();
      }
      final problems = data['selectedProblems'];
      final chatHistory = data['chatHistory'];
      final dashboardNotes = data['dashboardNotes'];
      final reminders = data['reminders'];
      final reports = data['reports'];
      final syncedReportKeys = data['syncedReportKeys'];
      final backendDashboardSummary = data['backendDashboardSummary'];
      final aiCallInviteLog = data['aiCallInviteLog'];
      final pendingAppRecordOps = data['pendingAppRecordOps'];
      final callMemories = data['callMemories'];
      final healthLogs = data['healthLogs'];
      final mealAnalyses = data['mealAnalyses'];
      final safetyEvents = data['safetyEvents'];
      final savedReminders = data['savedReminders'];
      final careTasks = data['careTasks'];
      final parsedCallMemories = callMemories is List
          ? callMemories
                .whereType<Map>()
                .map(
                  (entry) => HealthCallMemorySummary.fromJson(
                    Map<String, dynamic>.from(entry),
                  ),
                )
                .toList()
          : const <HealthCallMemorySummary>[];
      final parsedChatHistory = chatHistory is List
          ? chatHistory
                .whereType<Map>()
                .map(
                  (entry) =>
                      AiCoachMessage.fromJson(Map<String, dynamic>.from(entry)),
                )
                .where((message) => message.text.trim().isNotEmpty)
                .toList()
          : const <AiCoachMessage>[];
      final legacyName = _asString(data['name']);
      final storedFirstName = _asString(data['firstName']);
      final storedMiddleName = _asString(data['middleName']);
      final storedLastName = _asString(data['lastName']);
      final legacyParts = legacyName
          .split(RegExp(r'\s+'))
          .where((part) => part.trim().isNotEmpty)
          .toList();
      return HealthProfileDraft(
        name: legacyName,
        firstName: storedFirstName.isNotEmpty
            ? storedFirstName
            : legacyParts.isEmpty
            ? ''
            : legacyParts.first,
        middleName: storedMiddleName,
        lastName: storedLastName.isNotEmpty
            ? storedLastName
            : legacyParts.length > 1
            ? legacyParts.sublist(1).join(' ')
            : '',
        age: _asString(data['age']),
        phone: _asString(data['phone']),
        email: _asString(data['email']),
        heightCm: _asString(data['heightCm']),
        heightFeet: _asString(data['heightFeet']),
        heightInches: _asString(data['heightInches']),
        weightKg: _asString(data['weightKg']),
        weightLb: _asString(data['weightLb']),
        goalWeightKg: _asString(data['goalWeightKg']),
        goalWeightLb: _asString(data['goalWeightLb']),
        gender: _asString(data['gender']),
        timezone: _asString(data['timezone']),
        language: _asString(data['language']),
        foodPreference: _asString(data['foodPreference']),
        medications: _asString(data['medications']),
        allergies: _asString(data['allergies']),
        diagnosis: _asString(data['diagnosis']),
        surgeryHistory: _asString(data['surgeryHistory']),
        familyHistory: _asString(data['familyHistory']),
        pregnancyCycle: _asString(data['pregnancyCycle']),
        emergencyContactName: _asString(data['emergencyContactName']),
        emergencyContactPhone: _asString(data['emergencyContactPhone']),
        authToken: _asString(data['authToken']),
        lastAiCallInviteAt: _asString(data['lastAiCallInviteAt']),
        lastAiCallCompletedAt: _asString(data['lastAiCallCompletedAt']),
        aiCallInviteLog: aiCallInviteLog is Map
            ? aiCallInviteLog.map(
                (key, value) => MapEntry(key.toString(), value.toString()),
              )
            : const <String, String>{},
        bmiIntroSeen: data['bmiIntroSeen'] == true,
        safetyConsentAccepted: data['safetyConsentAccepted'] == true,
        intakeSummary: _asString(data['intakeSummary']),
        intakeCompleted: data['intakeCompleted'] == true,
        dashboardNotes: _asStringList(dashboardNotes),
        reminders: _filterUserFacingAiReminders(_asStringList(reminders)),
        reports: _filterUserFacingReports(_asStringList(reports)),
        syncedReportKeys: _asStringList(syncedReportKeys),
        backendDashboardSummary: backendDashboardSummary is Map
            ? Map<String, Object?>.from(backendDashboardSummary)
            : const <String, Object?>{},
        pendingAppRecordOps: pendingAppRecordOps is List
            ? pendingAppRecordOps
                  .whereType<Map>()
                  .map(
                    (entry) => FlickoPendingAppRecordOp.fromJson(
                      Map<String, dynamic>.from(entry),
                    ),
                  )
                  .whereType<FlickoPendingAppRecordOp>()
                  .toList()
            : const <FlickoPendingAppRecordOp>[],
        callMemories: parsedCallMemories,
        chatHistory: _sanitizeHiddenCallMessagesForDisplay(
          parsedChatHistory,
          callMemories: parsedCallMemories,
        ),
        healthLogs: healthLogs is List
            ? healthLogs
                  .whereType<Map>()
                  .map(
                    (entry) => HealthLogEntry.fromJson(
                      Map<String, dynamic>.from(entry),
                    ),
                  )
                  .toList()
            : const <HealthLogEntry>[],
        mealAnalyses: mealAnalyses is List
            ? mealAnalyses
                  .whereType<Map>()
                  .map(
                    (entry) => MealAnalysisEntry.fromJson(
                      Map<String, dynamic>.from(entry),
                    ),
                  )
                  .toList()
            : const <MealAnalysisEntry>[],
        safetyEvents: safetyEvents is List
            ? safetyEvents
                  .whereType<Map>()
                  .map(
                    (entry) => FlickoSafetyEvent.fromJson(
                      Map<String, dynamic>.from(entry),
                    ),
                  )
                  .toList()
            : const <FlickoSafetyEvent>[],
        savedReminders: savedReminders is List
            ? FlickoSavedReminder.dedupe(
                savedReminders
                    .whereType<Map>()
                    .map(
                      (entry) => FlickoSavedReminder.fromJson(
                        Map<String, dynamic>.from(entry),
                      ),
                    )
                    .whereType<FlickoSavedReminder>()
                    .where(_isUserFacingSavedReminder),
              )
            : const <FlickoSavedReminder>[],
        careTasks: careTasks is List
            ? careTasks
                  .whereType<Map>()
                  .map(
                    (entry) => FlickoCareTask.fromJson(
                      Map<String, dynamic>.from(entry),
                    ),
                  )
                  .whereType<FlickoCareTask>()
                  .toList()
            : const <FlickoCareTask>[],
        selectedProblems: problems is List
            ? problems.map(_asString).where((value) => value.isNotEmpty).toSet()
            : const <String>{},
      );
    } on FormatException {
      return const HealthProfileDraft();
    }
  }

  static String _asString(Object? value) => value?.toString() ?? '';

  static List<String> _asStringList(Object? value) {
    if (value is! List) {
      return const <String>[];
    }
    return value.map(_asString).where((entry) => entry.isNotEmpty).toList();
  }
}

List<AiCoachMessage> _sanitizeHiddenCallMessagesForDisplay(
  List<AiCoachMessage> history, {
  List<HealthCallMemorySummary> callMemories =
      const <HealthCallMemorySummary>[],
}) {
  if (history.isEmpty) {
    return const <AiCoachMessage>[];
  }
  final hiddenTranscriptTexts = <String>{
    for (final memory in callMemories)
      for (final entry in memory.transcript)
        _normalizedHiddenCallText(entry.text),
  }..remove('');
  return history
      .where((message) {
        if (message.source.trim().toLowerCase() == 'call') {
          return false;
        }
        final text = message.text.trim();
        if (text.isEmpty || _looksLikeHiddenCallTimelineMessage(text)) {
          return false;
        }
        if (hiddenTranscriptTexts.contains(_normalizedHiddenCallText(text))) {
          return false;
        }
        return true;
      })
      .toList(growable: false);
}

List<String> _filterUserFacingAiReminders(Iterable<String> values) {
  return values
      .map((value) => value.trim())
      .where(_isUserFacingReminderText)
      .toList(growable: false);
}

List<String> _filterUserFacingReports(Iterable<String> values) {
  return values
      .map((value) => value.trim())
      .where(_isUserFacingReportText)
      .toList(growable: false);
}

bool _isUserFacingSavedReminder(FlickoSavedReminder reminder) {
  return _isUserFacingReminderText('${reminder.title}\n${reminder.body}');
}

bool _isUserFacingReminderText(String value) {
  final clean = value.trim();
  final lower = clean.toLowerCase();
  if (clean.length < 6 || clean.length > 260) {
    return false;
  }
  if (_looksLikeDeferredAiArtifact(lower)) {
    return false;
  }
  if (lower.contains('daily flicko routine call in preferred free time') ||
      lower.contains('medicine reminder based on user medicine timing') ||
      lower.contains('meal photo check after lunch')) {
    return false;
  }
  return RegExp(
        r'\b(reminder|notify|alarm|meal|photo|medicine|tablet|water|walk|sleep|steps|bp|sugar|glucose|weight|log|check|call|drink|take|upload)\b',
        caseSensitive: false,
      ).hasMatch(clean) ||
      RegExp(
        r'\b(\d{1,2})(?::\d{2})?\s*(am|pm|a\.m\.|p\.m\.)\b|\b(morning|evening|night|lunch|dinner|breakfast|bedtime)\b',
        caseSensitive: false,
      ).hasMatch(clean);
}

bool _isUserFacingReportText(String value) {
  final clean = value.trim();
  final lower = clean.toLowerCase();
  if (clean.length < 6 || _looksLikeDeferredAiArtifact(lower)) {
    return false;
  }
  return lower.contains('pdf:') ||
      lower.contains('html:') ||
      lower.contains('http://') ||
      lower.contains('https://');
}

bool _looksLikeDeferredAiArtifact(String lowerText) {
  return RegExp(
    r"\b(can be|could be|later|after more details|not ready|if you want|do not|don't|without|not enough)\b",
  ).hasMatch(lowerText);
}

bool _looksLikeHiddenCallTimelineMessage(String text) {
  final clean = text.trim().toLowerCase();
  return clean.startsWith('live ai call completed') ||
      clean.contains('use this call as context for the next chat') ||
      clean.contains('structured summary:') &&
          clean.contains('call summary') &&
          clean.contains('duration:');
}

String _normalizedHiddenCallText(String value) {
  return value.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
}

class AuthUser {
  const AuthUser({
    required this.name,
    required this.email,
    required this.mobile,
    required this.profile,
  });

  final String name;
  final String email;
  final String mobile;
  final Map<String, dynamic> profile;

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    final profile = json['profile'];
    return AuthUser(
      name: json['name']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      mobile: json['mobile']?.toString() ?? '',
      profile: profile is Map
          ? Map<String, dynamic>.from(profile)
          : <String, dynamic>{},
    );
  }
}

class AuthResult {
  const AuthResult({required this.token, required this.user});

  final String token;
  final AuthUser user;

  factory AuthResult.fromJson(Map<String, dynamic> json) {
    final userJson = json['user'];
    if (userJson is! Map<String, dynamic>) {
      throw const AuthApiException('Invalid user response from server.');
    }
    return AuthResult(
      token: json['token']?.toString() ?? '',
      user: AuthUser.fromJson(userJson),
    );
  }
}

class AuthApiException implements Exception {
  const AuthApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AuthApiClient {
  const AuthApiClient({
    this.baseUrl = const String.fromEnvironment(
      'FLICKO_API_BASE_URL',
      defaultValue: '',
    ),
  });

  final String baseUrl;

  static const _fallbackBaseUrls = String.fromEnvironment(
    'FLICKO_API_BASE_URL_FALLBACKS',
    defaultValue: '',
  );

  Future<void> registerStart({
    required String name,
    required String email,
    required String mobile,
    required String password,
  }) async {
    await _post('/auth/register/start/', {
      'name': name,
      'email': email,
      'mobile': mobile,
      'password': password,
    });
  }

  Future<AuthResult> registerVerify({
    required String email,
    required String otp,
  }) async {
    final json = await _post('/auth/register/verify/', {
      'email': email,
      'otp': otp,
    });
    return AuthResult.fromJson(json);
  }

  Future<AuthResult> login({
    required String email,
    required String password,
  }) async {
    final json = await _post('/auth/login/', {
      'email': email,
      'password': password,
    });
    return AuthResult.fromJson(json);
  }

  Future<AuthResult> googleLogin({
    required String idToken,
    required String email,
    required String name,
    required String photoUrl,
  }) async {
    final json = await _post('/auth/google/', {
      'id_token': idToken,
      'email': email,
      'name': name,
      'photo_url': photoUrl,
    });
    return AuthResult.fromJson(json);
  }

  Future<void> forgotPasswordStart({required String email}) async {
    await _post('/auth/password/forgot/start/', {'email': email});
  }

  Future<void> resetPassword({
    required String email,
    required String otp,
    required String newPassword,
  }) async {
    await _post('/auth/password/reset/', {
      'email': email,
      'otp': otp,
      'new_password': newPassword,
    });
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, String> body,
  ) async {
    final urls = _candidateBaseUrls();
    for (final candidate in urls) {
      try {
        return await _postToBaseUrl(candidate, path, body);
      } on AuthApiException {
        rethrow;
      } on TimeoutException catch (error) {
        debugPrint('Auth backend timed out at $candidate: $error');
      } on SocketException catch (error) {
        debugPrint('Auth backend socket failed at $candidate: $error');
      } on http.ClientException catch (error) {
        debugPrint('Auth backend client failed at $candidate: $error');
      } catch (error) {
        debugPrint('Auth backend failed at $candidate: $error');
      }
    }

    throw AuthApiException(
      'Could not reach Flicko backend. Tried: ${urls.join(', ')}.',
    );
  }

  List<String> _candidateBaseUrls() {
    return flickoDefaultApiBaseUrlCandidates(
      preferredBaseUrl: baseUrl,
      fallbackBaseUrlsCsv: _fallbackBaseUrls,
    );
  }

  Future<Map<String, dynamic>> _postToBaseUrl(
    String targetBaseUrl,
    String path,
    Map<String, String> body,
  ) async {
    final uri = Uri.parse('$targetBaseUrl$path');
    try {
      final response = await http
          .post(
            uri,
            headers: const {
              'Accept': 'application/json',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 15));
      final decoded = response.body.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(response.body);
      final json = decoded is Map<String, dynamic>
          ? decoded
          : <String, dynamic>{};
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return json;
      }
      final message =
          json['detail']?.toString() ??
          json['error']?.toString() ??
          'Request failed.';
      throw AuthApiException(message);
    } on AuthApiException {
      rethrow;
    } on FormatException {
      throw const AuthApiException(
        'Backend returned an invalid authentication response.',
      );
    }
  }
}

class FlickoTheme {
  static const background = Color(0xFFF4F7F5);
  static const screen = Color(0xFFFBFCF8);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceSoft = Color(0xFFEAF7EE);
  static const line = Color(0xFFDFE8E3);
  static const ink = Color(0xFF16211F);
  static const muted = Color(0xFF65736F);
  static const mutedLight = Color(0xFF8A9692);
  static const teal = Color(0xFF149447);
  static const tealDark = Color(0xFF0B372D);
  static const darkPanel = Color(0xFF12211F);
  static const mint = Color(0xFFDFF3E5);
  static const sky = Color(0xFFDFEEFE);
  static const peach = Color(0xFFFFF0DF);
  static const rose = Color(0xFFFDE7ED);

  static ThemeData get light {
    return ThemeData(
      useMaterial3: true,
      splashFactory: InkRipple.splashFactory,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          TargetPlatform.android: FlickoPageTransitionsBuilder(),
          TargetPlatform.iOS: FlickoPageTransitionsBuilder(),
          TargetPlatform.macOS: FlickoPageTransitionsBuilder(),
          TargetPlatform.linux: FlickoPageTransitionsBuilder(),
          TargetPlatform.windows: FlickoPageTransitionsBuilder(),
          TargetPlatform.fuchsia: FlickoPageTransitionsBuilder(),
        },
      ),
      scaffoldBackgroundColor: background,
      colorScheme: ColorScheme.fromSeed(
        seedColor: teal,
        brightness: Brightness.light,
        primary: teal,
        surface: surface,
      ),
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          color: ink,
          fontSize: 31,
          height: 1.1,
          fontWeight: FontWeight.w800,
          letterSpacing: 0,
        ),
        headlineMedium: TextStyle(
          color: ink,
          fontSize: 24,
          height: 1.14,
          fontWeight: FontWeight.w800,
          letterSpacing: 0,
        ),
        titleMedium: TextStyle(
          color: ink,
          fontSize: 15,
          fontWeight: FontWeight.w800,
          letterSpacing: 0,
        ),
        bodyMedium: TextStyle(
          color: muted,
          fontSize: 15,
          height: 1.48,
          letterSpacing: 0,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFFBFDFB),
        labelStyle: const TextStyle(
          color: muted,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: teal, width: 1.4),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          animationDuration: const Duration(milliseconds: 140),
          splashFactory: InkRipple.splashFactory,
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ButtonStyle(
          animationDuration: const Duration(milliseconds: 140),
          splashFactory: InkRipple.splashFactory,
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          animationDuration: const Duration(milliseconds: 140),
          splashFactory: InkRipple.splashFactory,
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          animationDuration: const Duration(milliseconds: 140),
          splashFactory: InkRipple.splashFactory,
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
      ),
    );
  }
}

class FlickoScrollBehavior extends MaterialScrollBehavior {
  const FlickoScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => const <PointerDeviceKind>{
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.stylus,
    PointerDeviceKind.invertedStylus,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.unknown,
  };

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    return const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics());
  }

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child;
  }
}

class HealthOnboardingFlow extends StatefulWidget {
  const HealthOnboardingFlow({
    super.key,
    required this.draft,
    required this.onDraftChanged,
  });

  final HealthProfileDraft draft;
  final ValueChanged<HealthProfileDraft> onDraftChanged;

  @override
  State<HealthOnboardingFlow> createState() => _HealthOnboardingFlowState();
}

class _HealthOnboardingFlowState extends State<HealthOnboardingFlow>
    with WidgetsBindingObserver {
  static const _consentPage = 6;
  static const _lastPage = 7;
  static const _profileApiClient = HealthProfileApiClient();
  static const _reportApiClient = HealthReportApiClient();
  static const _appRecordSyncCoordinator = FlickoAppRecordSyncCoordinator();
  static const _backendAppDataHydrator = FlickoBackendAppDataHydrator();
  static const _dashboardEntryCoordinator = FlickoDashboardEntryCoordinator();
  static const _callInviteCoordinator = FlickoCallInviteCoordinator();
  static const _callCompletionCoordinator = FlickoCallCompletionCoordinator();
  static const _callCompletionEffectExecutor =
      FlickoCallCompletionEffectExecutor();
  static const _callInviteDispatchCoordinator =
      FlickoCallInviteDispatchCoordinator();
  static const _callInviteIngressCoordinator =
      FlickoCallInviteIngressCoordinator();
  static const _interruptedCallRecoveryCoordinator =
      FlickoInterruptedCallRecoveryCoordinator();
  static const _reportGenerationCoordinator =
      FlickoReportGenerationCoordinator();
  static const _callRouteCoordinator = FlickoCallRouteCoordinator();
  static const _liveCallWorkflowRunner = FlickoLiveCallWorkflowRunner();
  static const _liveCallResumeCoordinator = FlickoLiveCallResumeCoordinator();
  final FlickoCallInviteRuntimeCoordinator _callInviteRuntimeCoordinator =
      FlickoCallInviteRuntimeCoordinator();
  final AiCallTranscriptStore _callTranscriptStore = AiCallTranscriptStore();
  final NativeCallInviteBridge _nativeCallInviteBridge =
      const NativeCallInviteBridge();
  final LiveCallForegroundService _liveCallForegroundService =
      const LiveCallForegroundService();
  final Set<String> _syncingProfileKeys = <String>{};
  final Set<String> _syncingReportKeys = <String>{};
  final Set<String> _refreshingAppDataTokens = <String>{};
  final Set<String> _refreshingReportHistoryTokens = <String>{};
  final Set<String> _cleanedBackendAppDataTokens = <String>{};
  final Set<String> _scheduledReminderKeys = <String>{};
  DateTime? _backendRetryAfter;
  StreamSubscription<String>? _callInviteSubscription;
  bool _callInviteRouteOpen = false;
  bool _liveCallInProgress = false;
  bool _pageAnimating = false;
  bool _flowImagesPrecached = false;
  late final PageController _controller;
  int _page = 0;
  bool _editingProfileFromDashboard = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = PageController();
    final initialPage = _initialPageForDraft(widget.draft);
    if (initialPage != 0) {
      _page = initialPage;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _controller.jumpToPage(initialPage);
          if (initialPage == _lastPage) {
            unawaited(_prepareDashboardData(widget.draft));
          }
        }
      });
    }
    _callInviteSubscription = FlickoNotificationService
        .instance
        .callInvitePayloads
        .listen(_handleCallInvitePayload);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_initializeCallInviteNotifications());
      unawaited(_recoverInterruptedCallTranscript());
      unawaited(_resumeActiveLiveCallFromNotification());
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_flowImagesPrecached) {
      return;
    }
    _flowImagesPrecached = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(_precacheFlowImages());
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _callInviteSubscription?.cancel();
    _callInviteRuntimeCoordinator.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _precacheFlowImages() async {
    const assets = <String>[
      'assets/images/welcome_hero.png',
      'assets/images/mainlogo.png',
      'assets/images/demo_call.png',
      'assets/images/demo_meal.png',
    ];
    for (final asset in assets) {
      if (!mounted) {
        return;
      }
      try {
        await precacheImage(AssetImage(asset), context);
      } catch (error) {
        debugPrint('Flicko image precache skipped for $asset: $error');
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_drainNativeCallInvitePayloads());
      unawaited(_resumeActiveLiveCallFromNotification());
    }
  }

  Future<void> _initializeCallInviteNotifications() async {
    await FlickoNotificationService.instance.initialize();
    final initialPayload = await FlickoNotificationService.instance
        .consumeInitialCallInvitePayload();
    final nativePayload = await _nativeCallInviteBridge
        .consumeCallInvitePayload();
    if (!mounted) {
      return;
    }
    for (final payload in _callInviteIngressCoordinator.normalizedPayloads([
      initialPayload,
      nativePayload,
    ])) {
      _handleCallInvitePayload(payload);
    }
  }

  Future<void> _drainNativeCallInvitePayloads() async {
    final nativePayload = await _nativeCallInviteBridge
        .consumeCallInvitePayload();
    if (!mounted) {
      return;
    }
    for (final payload in _callInviteIngressCoordinator.normalizedPayloads([
      nativePayload,
    ])) {
      _handleCallInvitePayload(payload);
    }
  }

  Future<void> _resumeActiveLiveCallFromNotification() async {
    if (!mounted ||
        !_liveCallResumeCoordinator.shouldCheckResumeSignal(
          callInviteRouteOpen: _callInviteRouteOpen,
          liveCallInProgress: _liveCallInProgress,
        )) {
      return;
    }
    final shouldOpen = await _liveCallForegroundService
        .consumeOpenLiveCallSignal();
    if (!mounted) {
      return;
    }
    final running = shouldOpen
        ? await _liveCallForegroundService.isRunning()
        : false;
    final session = running
        ? await _callTranscriptStore.readActiveSession()
        : null;
    if (!mounted) {
      return;
    }
    final resumableSession = _liveCallResumeCoordinator.resumableSession(
      FlickoLiveCallResumeSnapshot(
        callInviteRouteOpen: _callInviteRouteOpen,
        liveCallInProgress: _liveCallInProgress,
        openSignalConsumed: shouldOpen,
        serviceRunning: running,
        session: session,
      ),
    );
    if (resumableSession == null) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _callInviteRouteOpen || _liveCallInProgress) {
        return;
      }
      unawaited(_resumeActiveLiveCallSession(resumableSession));
    });
  }

  Future<void> _recoverInterruptedCallTranscript() async {
    final session = await _callTranscriptStore.readActiveSession();
    if (!mounted || session == null || session.isCompleted) {
      return;
    }
    final recovery = _interruptedCallRecoveryCoordinator.build(
      session: session,
      fallbackProblemName: _primaryProblem(widget.draft),
      nativeTranscript: await _readNativeCallTranscript(),
      now: DateTime.now(),
    );
    if (recovery == null) {
      return;
    }

    await _callTranscriptStore.completeSession(
      sessionId: session.sessionId,
      transcript: recovery.transcript,
    );
    if (!mounted) {
      return;
    }
    _handleAiCallCompleted(recovery.summary);
  }

  Future<List<HealthCallTranscriptEntry>> _readNativeCallTranscript() async {
    try {
      return await const LiveCallForegroundService().getTranscript().timeout(
        const Duration(milliseconds: 900),
      );
    } catch (error) {
      debugPrint('Flicko native transcript recovery skipped: $error');
      return const <HealthCallTranscriptEntry>[];
    }
  }

  Future<void> _goTo(int page) async {
    if (!_controller.hasClients || _pageAnimating || page == _page) {
      return;
    }
    setState(() => _pageAnimating = true);
    try {
      await _controller.animateToPage(
        page,
        duration: FlickoMotion.pageSnapDuration,
        curve: FlickoMotion.pageSnapCurve,
      );
    } finally {
      if (mounted) {
        setState(() => _pageAnimating = false);
      } else {
        _pageAnimating = false;
      }
    }
  }

  void _next() => unawaited(_goTo((_page + 1).clamp(0, _lastPage)));

  void _previous() => unawaited(_goTo((_page - 1).clamp(0, _lastPage)));

  void _goToDashboard([HealthProfileDraft? nextDraft]) {
    final draft = nextDraft ?? widget.draft;
    _editingProfileFromDashboard = false;
    unawaited(_goTo(_lastPage));
    unawaited(
      _prepareDashboardData(draft).whenComplete(_openPendingCallInviteIfReady),
    );
  }

  FlickoDashboardEntrySnapshot _dashboardEntrySnapshot(
    HealthProfileDraft draft,
  ) {
    return FlickoDashboardEntrySnapshot(
      hasProfile: draft.hasProfile,
      shouldOpenDashboard: draft.shouldOpenDashboard,
      safetyConsentAccepted: draft.safetyConsentAccepted,
      intakeCompleted: draft.intakeCompleted,
      backendProfileIntakeCompleted: _backendSummaryBool(
        draft.backendDashboardSummary,
        'profile_intake_completed',
      ),
      lastAiCallCompletedAt: draft.lastAiCallCompletedAt,
      callMemoryCount: draft.callMemories.length,
      reportCount: draft.reports.length,
      savedReminderCount: draft.savedReminders.length,
      careTaskCount: draft.careTasks.length,
      healthLogCount: draft.healthLogs.length,
      mealAnalysisCount: draft.mealAnalyses.length,
      safetyEventCount: draft.safetyEvents.length,
      chatHistoryCount: draft.chatHistory.length,
      reminderLineCount: draft.reminders.length,
      dashboardNoteCount: draft.dashboardNotes.length,
      backendDashboardSummaryCount: draft.backendDashboardSummary.length,
    );
  }

  bool _hasCompletedAiSetupSignal(HealthProfileDraft draft) {
    return _dashboardEntryCoordinator.hasCompletedAiSetupSignal(
      _dashboardEntrySnapshot(draft),
    );
  }

  bool _hasReturningUserHistory(HealthProfileDraft draft) {
    return _dashboardEntryCoordinator.hasReturningUserHistory(
      _dashboardEntrySnapshot(draft),
    );
  }

  bool _shouldOpenDashboardEntry(HealthProfileDraft draft) {
    return _dashboardEntryCoordinator.shouldOpenDashboardEntry(
      _dashboardEntrySnapshot(draft),
    );
  }

  HealthProfileDraft _latestDraftForToken(HealthProfileDraft fallback) {
    if (!mounted) {
      return fallback;
    }
    final token = fallback.authToken.trim();
    if (token.isEmpty) {
      return fallback;
    }
    return widget.draft.authToken == token ? widget.draft : fallback;
  }

  int _initialPageForDraft(HealthProfileDraft draft) {
    switch (_dashboardEntryCoordinator.initialTarget(
      _dashboardEntrySnapshot(draft),
    )) {
      case FlickoDashboardEntryTarget.dashboard:
        return _lastPage;
      case FlickoDashboardEntryTarget.consent:
        return _consentPage;
      case FlickoDashboardEntryTarget.problemSelection:
      case FlickoDashboardEntryTarget.onboarding:
        return 0;
    }
  }

  Future<void> _handleAuthenticatedResult(AuthResult result) async {
    var authenticatedDraft = _draftFromAuth(widget.draft, result);
    widget.onDraftChanged(authenticatedDraft);
    _editingProfileFromDashboard = false;

    if (authenticatedDraft.isAuthenticated) {
      await _refreshAppDataIfAuthenticated(authenticatedDraft);
      authenticatedDraft = _latestDraftForToken(authenticatedDraft);
      await _refreshReportHistoryIfAuthenticated(authenticatedDraft);
      authenticatedDraft = _latestDraftForToken(authenticatedDraft);
      await _syncProfileIfAuthenticated(authenticatedDraft);
      authenticatedDraft = _latestDraftForToken(authenticatedDraft);
    }

    if (!mounted) {
      return;
    }
    final resolvedDraft = _latestDraftForToken(authenticatedDraft);
    switch (_dashboardEntryCoordinator.authenticatedTarget(
      _dashboardEntrySnapshot(resolvedDraft),
    )) {
      case FlickoDashboardEntryTarget.dashboard:
        _goToDashboard(resolvedDraft);
        return;
      case FlickoDashboardEntryTarget.consent:
        await _goTo(_consentPage);
        return;
      case FlickoDashboardEntryTarget.problemSelection:
        await _goTo(4);
        return;
      case FlickoDashboardEntryTarget.onboarding:
        await _goTo(0);
        return;
    }
  }

  void _openProfileFromDashboard() {
    _editingProfileFromDashboard = true;
    unawaited(_goTo(5));
  }

  void _openProblemSelectionFromDashboard() {
    _editingProfileFromDashboard = true;
    unawaited(_goTo(4));
  }

  void _logoutFromDashboard() {
    _editingProfileFromDashboard = false;
    widget.onDraftChanged(const HealthProfileDraft());
    unawaited(_goTo(3));
  }

  void _leaveProfile() {
    if (_editingProfileFromDashboard) {
      _goToDashboard();
      return;
    }
    _previous();
  }

  void _openConsentOrDashboard(HealthProfileDraft draft) {
    if (_editingProfileFromDashboard || draft.safetyConsentAccepted) {
      _goToDashboard(draft);
      return;
    }
    unawaited(_goTo(_consentPage));
  }

  void _acceptSafetyConsent() {
    final draft = widget.draft.copyWith(safetyConsentAccepted: true);
    widget.onDraftChanged(draft);
    _editingProfileFromDashboard = false;
    unawaited(_goTo(_lastPage));
    unawaited(_prepareDashboardData(draft));
    unawaited(
      _saveMemoryIfAuthenticated(
        draft,
        source: 'profile',
        category: 'safety',
        title: 'Safety consent accepted',
        content: 'User accepted Flicko AI safety and medical guidance notice.',
      ),
    );
  }

  Future<void> _prepareDashboardData(HealthProfileDraft draft) async {
    await _replayPendingAppRecordOps(draft);
    final afterReplay = widget.draft.authToken == draft.authToken
        ? widget.draft
        : draft;
    await _refreshAppDataIfAuthenticated(afterReplay);
    await _refreshReportHistoryIfAuthenticated(afterReplay);
    final latestDraft = widget.draft.authToken == draft.authToken
        ? widget.draft
        : afterReplay;
    await _syncProfileIfAuthenticated(latestDraft);
    await _syncSetupReportIfNeeded(latestDraft);
    await _ensureSavedRemindersScheduled(
      widget.draft.authToken == draft.authToken ? widget.draft : latestDraft,
    );
    await _maybeSendProactiveCallInvite(latestDraft);
    _openPendingCallInviteIfReady();
  }

  void _handleCallInvitePayload(String payload) {
    if (!mounted) {
      return;
    }
    final draft = widget.draft;
    final decision = _callInviteDispatchCoordinator.decide(
      payload: payload,
      snapshot: FlickoCallInviteDispatchSnapshot(
        callInviteRouteOpen: _callInviteRouteOpen,
        liveCallInProgress: _liveCallInProgress,
        canOpenDashboard: _shouldOpenDashboardEntry(draft),
        firstName: draft.givenName,
        problemName: _primaryProblem(draft),
      ),
    );
    switch (decision.action) {
      case FlickoCallInviteDispatchAction.ignore:
        return;
      case FlickoCallInviteDispatchAction.cancelActiveInvite:
        unawaited(
          FlickoNotificationService.instance.cancelReminderPayload(payload),
        );
        return;
      case FlickoCallInviteDispatchAction.queuePending:
        _callInviteRuntimeCoordinator.queuePendingPayload(payload);
        return;
      case FlickoCallInviteDispatchAction.retryDeclined:
        final retryPlan = decision.retryPlan;
        if (retryPlan == null) {
          return;
        }
        unawaited(
          _scheduleAiCallInvite(
            draft,
            retryPlan.spec,
            scheduledAt: retryPlan.scheduledAt,
            auditTitle: retryPlan.auditTitle,
            auditContent: retryPlan.auditContent,
          ),
        );
        return;
      case FlickoCallInviteDispatchAction.openInvite:
        final spec = decision.spec;
        if (spec == null) {
          return;
        }
        _goToDashboard(draft);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) {
            return;
          }
          unawaited(_openAiCallInviteFromRoot(spec));
        });
        return;
    }
  }

  void _openPendingCallInviteIfReady() {
    if (!mounted) {
      return;
    }
    final payload = _callInviteRuntimeCoordinator.takePendingPayloadIfReady(
      canOpenDashboard: _shouldOpenDashboardEntry(widget.draft),
      callInviteRouteOpen: _callInviteRouteOpen,
      liveCallInProgress: _liveCallInProgress,
    );
    if (payload == null) {
      return;
    }
    _handleCallInvitePayload(payload);
  }

  Future<AiCallWarmupBundle> _prepareCallWarmupBundle(
    HealthProfileDraft draft,
    AiCallInviteSpec spec, {
    String? profileContextOverride,
  }) {
    return AiCallWarmupService.instance.prepare(
      problemName: spec.problemName,
      profileContext: profileContextOverride ?? _buildProfileContext(draft),
      reason: spec.reason,
      memoryIntent: spec.memoryIntent,
      callPurpose: spec.subtitle,
      initiatedByUser: spec.initiatedByUser,
      onLoadBackendContext: () => _fetchBackendAiContext(
        problemName: spec.problemName,
        text: spec.memoryIntent,
      ),
    );
  }

  Future<void> _openAiCallInviteFromRoot(AiCallInviteSpec spec) async {
    if (!_callRouteCoordinator.canOpenRoute(
      callInviteRouteOpen: _callInviteRouteOpen,
      liveCallInProgress: _liveCallInProgress,
    )) {
      return;
    }
    _callInviteRouteOpen = true;
    try {
      final outcome = await _liveCallWorkflowRunner.runInviteFlow(
        spec: spec,
        profileContext: _buildProfileContext(widget.draft),
        showInviteSheet: _showAiCallInviteSheet,
        beforeLiveCallStart: () async {
          await _cancelPendingCallInviteForReason(widget.draft, spec.reason);
          if (mounted) {
            setState(() => _liveCallInProgress = true);
          }
        },
        prepareWarmup: (inviteSpec, profileContext) => _prepareCallWarmupBundle(
          widget.draft,
          inviteSpec,
          profileContextOverride: profileContext,
        ),
        prestartWarmLiveCall: _prestartLiveCall,
        launchCallPage: _launchLiveCallPage,
      );
      final retryPlan = outcome.retryPlan;
      if (retryPlan != null) {
        unawaited(
          _scheduleAiCallInvite(
            widget.draft,
            retryPlan.spec,
            scheduledAt: retryPlan.scheduledAt,
            auditTitle: retryPlan.auditTitle,
            auditContent: retryPlan.auditContent,
          ),
        );
        return;
      }
      final summary = outcome.summary;
      if (summary != null) {
        _handleAiCallCompleted(summary);
      }
    } finally {
      if (mounted && _liveCallInProgress) {
        setState(() => _liveCallInProgress = false);
      }
      _callInviteRouteOpen = false;
    }
  }

  Future<void> _resumeActiveLiveCallSession(
    AiCallTranscriptSessionDraft session,
  ) async {
    if (!_callRouteCoordinator.canOpenRoute(
      callInviteRouteOpen: _callInviteRouteOpen,
      liveCallInProgress: _liveCallInProgress,
    )) {
      return;
    }
    _callInviteRouteOpen = true;
    try {
      final outcome = await _liveCallWorkflowRunner.runResumeFlow(
        session: session,
        firstName: widget.draft.givenName,
        fallbackProblemName: _primaryProblem(widget.draft),
        fallbackProfileContext: _buildProfileContext(widget.draft),
        beforeLiveCallStart: () async {
          if (mounted) {
            setState(() => _liveCallInProgress = true);
          }
        },
        prepareWarmup: (spec, profileContext) => _prepareCallWarmupBundle(
          widget.draft,
          spec,
          profileContextOverride: profileContext,
        ),
        prestartWarmLiveCall: _prestartLiveCall,
        launchCallPage: (request) async {
          final initialTranscript = await _callTranscriptStore.readTranscript(
            session.sessionId,
          );
          return _launchLiveCallPage(
            request,
            initialTranscript: initialTranscript,
          );
        },
      );
      final summary = outcome.summary;
      if (summary != null) {
        _handleAiCallCompleted(summary);
      }
    } finally {
      if (mounted && _liveCallInProgress) {
        setState(() => _liveCallInProgress = false);
      }
      _callInviteRouteOpen = false;
    }
  }

  Future<AiCallInviteResponse?> _showAiCallInviteSheet(AiCallInviteSpec spec) {
    return Navigator.of(context).push<AiCallInviteResponse>(
      FlickoPageRoute(
        fullscreenDialog: true,
        builder: (context) => AiCallInvitePage(spec: spec),
      ),
    );
  }

  Future<void> _prestartLiveCall(
    AiCallWarmupBundle warmup,
    String problemName,
  ) {
    return prestartWarmLiveCall(
      foregroundService: _liveCallForegroundService,
      warmup: warmup,
      apiKey: kFlickoGeminiApiKey,
      model: kFlickoGeminiNativeAudioModel,
      voiceName: kFlickoGeminiNativeAudioVoice,
      problemName: problemName,
      baseUri: const String.fromEnvironment('FLICKO_GEMINI_LIVE_WS_URL'),
    );
  }

  Future<FlickoLiveCallPageOutcome?> _launchLiveCallPage(
    FlickoLiveCallPageRequest request, {
    List<HealthCallTranscriptEntry> initialTranscript =
        const <HealthCallTranscriptEntry>[],
  }) async {
    var callTranscript = initialTranscript;
    if (!mounted) {
      return null;
    }
    final navigator = Navigator.of(context);
    final result = await navigator.push<AiHealthCallResult>(
      FlickoPageRoute(
        builder: (context) => AiHealthCallPage(
          problemName: request.problemName,
          profileContext: request.profileContext,
          prewarmedProfileContext: request.prewarmedProfileContext,
          prewarmedOpeningScript: request.prewarmedOpeningScript,
          reason: request.spec.reason,
          subtitle: request.subtitle,
          playConnectTone: request.playConnectTone,
          emergencyContactName: widget.draft.emergencyContactName,
          emergencyContactPhone: widget.draft.emergencyContactPhone,
          userName: widget.draft.givenName,
          onSafetyEvent: _handleSafetyEventAdded,
          onLoadBackendContext: () => _fetchBackendAiContext(
            problemName: request.problemName,
            text: request.spec.memoryIntent,
          ),
          callSessionId: request.callSessionId,
          startedAt: request.startedAt,
          onCallTranscriptReady: (transcript) {
            callTranscript = transcript;
          },
        ),
      ),
    );
    if (!mounted || result == null) {
      return null;
    }
    return FlickoLiveCallPageOutcome(
      result: result,
      transcript: callTranscript,
    );
  }

  Future<void> _maybeSendProactiveCallInvite(HealthProfileDraft draft) async {
    final plan = _callInviteCoordinator.proactivePlan(
      shouldOpenDashboardEntry: _shouldOpenDashboardEntry(draft),
      hasReturningUserHistory: _hasReturningUserHistory(draft),
      callInviteRouteOpen: _callInviteRouteOpen,
      liveCallInProgress: _liveCallInProgress,
      inviteLog: draft.aiCallInviteLog,
      firstName: draft.givenName,
      problemName: _primaryProblem(draft),
      mealAnalyses: draft.mealAnalyses,
      careTasks: draft.careTasks,
    );
    if (plan == null) {
      return;
    }
    await _scheduleAiCallInvite(
      draft,
      plan.spec,
      scheduledAt: plan.scheduledAt,
      auditTitle: plan.auditTitle,
      auditContent: plan.auditContent,
      repeatsDaily: plan.repeatsDaily,
    );
  }

  Future<void> _scheduleAiCallInvite(
    HealthProfileDraft draft,
    AiCallInviteSpec spec, {
    required DateTime scheduledAt,
    required String auditTitle,
    required String auditContent,
    bool repeatsDaily = false,
  }) async {
    final now = DateTime.now();
    final plan = _callInviteCoordinator.schedulePlan(
      spec: spec,
      scheduledAt: scheduledAt,
      callInviteRouteOpen: _callInviteRouteOpen,
      liveCallInProgress: _liveCallInProgress,
      now: now,
    );
    final effectiveScheduledAt = plan.effectiveScheduledAt;
    final immediate = plan.immediate;
    final invitePayload = plan.payload;
    await _cancelPendingCallInviteForReason(
      draft,
      spec.reason,
      exceptPayload: invitePayload,
    );
    final sent = immediate
        ? await FlickoNotificationService.instance.showIncomingCallInvite(
            title: spec.title,
            body: spec.body,
            payload: invitePayload,
          )
        : await FlickoNotificationService.instance.scheduleIncomingCallInvite(
            title: spec.title,
            body: spec.body,
            scheduledAt: effectiveScheduledAt,
            payload: invitePayload,
            repeatsDaily: repeatsDaily,
          );
    if (!mounted || !sent) {
      return;
    }
    final nextDraft = draft.copyWith(
      lastAiCallInviteAt: now.toIso8601String(),
      aiCallInviteLog: _callInviteCoordinator.recordInviteLog(
        draft.aiCallInviteLog,
        reason: spec.reason,
        invitedAt: now,
        scheduledAt: effectiveScheduledAt,
        payload: invitePayload,
      ),
    );
    widget.onDraftChanged(nextDraft);
    if (immediate) {
      if (_shouldOpenDashboardEntry(nextDraft)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || _callInviteRouteOpen) {
            return;
          }
          unawaited(_openAiCallInviteFromRoot(spec));
        });
      } else {
        _callInviteRuntimeCoordinator.queuePendingPayload(invitePayload);
      }
    } else {
      _callInviteRuntimeCoordinator.armTimer(
        payload: invitePayload,
        scheduledAt: effectiveScheduledAt,
        onPayloadDue: (_) {
          if (!mounted ||
              !_shouldOpenDashboardEntry(widget.draft) ||
              _callInviteRouteOpen ||
              _liveCallInProgress) {
            return;
          }
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || _callInviteRouteOpen || _liveCallInProgress) {
              return;
            }
            _openPendingCallInviteIfReady();
          });
        },
      );
    }
    unawaited(
      _saveMemoryIfAuthenticated(
        nextDraft,
        source: 'call',
        category: 'reminder',
        title: auditTitle,
        content: auditContent,
        data: <String, Object?>{
          'call_invite_reason': spec.reason.payloadKey,
          'payload': invitePayload,
          'scheduled_at': effectiveScheduledAt.toIso8601String(),
          'immediate': immediate,
          'repeats_daily': repeatsDaily,
        },
      ),
    );
  }

  String _lastInvitePayload(
    HealthProfileDraft draft,
    AiCallInviteReason reason,
  ) {
    return _callInviteCoordinator.lastInvitePayload(
      draft.aiCallInviteLog,
      reason,
    );
  }

  Future<void> _cancelPendingCallInviteForReason(
    HealthProfileDraft draft,
    AiCallInviteReason reason, {
    String exceptPayload = '',
  }) async {
    final payload = _lastInvitePayload(draft, reason);
    if (payload.isEmpty || payload == exceptPayload) {
      return;
    }
    _callInviteRuntimeCoordinator.cancelTrackedPayload(payload);
    await FlickoNotificationService.instance.cancelReminderPayload(payload);
  }

  HealthProfileDraft _draftFromAuth(
    HealthProfileDraft current,
    AuthResult result,
  ) {
    final nameParts = result.user.name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    final profile = result.user.profile;
    final selectedProblems = _profileStringSet(profile['selected_problems']);
    final dashboardNotes = _profileStringList(profile['dashboard_notes']);
    final reminders = _profileStringList(profile['reminders']);
    final savedReminders = profile['saved_reminders'];
    final mealAnalyses = profile['meal_analyses'];
    final careTasks = profile['care_tasks'];
    final healthLogs = profile['health_logs'];
    final safetyEvents = profile['safety_events'];
    final reports = profile['reports'];
    final chatHistory = profile['chat_history'];
    return current.copyWith(
      name: result.user.name,
      firstName: current.firstName.isNotEmpty
          ? current.firstName
          : nameParts.isEmpty
          ? ''
          : nameParts.first,
      lastName: current.lastName.isNotEmpty
          ? current.lastName
          : nameParts.length > 1
          ? nameParts.sublist(1).join(' ')
          : '',
      middleName: _profileText(profile, 'middle_name', current.middleName),
      age: _profileText(profile, 'age', current.age),
      gender: _profileText(profile, 'gender', current.gender),
      email: result.user.email,
      phone: result.user.mobile.isNotEmpty
          ? result.user.mobile
          : _profileText(profile, 'mobile', current.phone),
      heightCm: _profileText(profile, 'height_cm', current.heightCm),
      heightFeet: _profileText(profile, 'height_feet', current.heightFeet),
      heightInches: _profileText(
        profile,
        'height_inches',
        current.heightInches,
      ),
      weightKg: _profileText(profile, 'weight_kg', current.weightKg),
      weightLb: _profileText(profile, 'weight_lb', current.weightLb),
      goalWeightKg: _profileText(
        profile,
        'goal_weight_kg',
        current.goalWeightKg,
      ),
      goalWeightLb: _profileText(
        profile,
        'goal_weight_lb',
        current.goalWeightLb,
      ),
      timezone: _profileText(profile, 'timezone', current.timezone),
      language: _profileText(profile, 'language', current.language),
      foodPreference: _profileText(
        profile,
        'food_preference',
        current.foodPreference,
      ),
      medications: _profileText(profile, 'medications', current.medications),
      allergies: _profileText(profile, 'allergies', current.allergies),
      diagnosis: _profileText(profile, 'diagnosis', current.diagnosis),
      surgeryHistory: _profileText(
        profile,
        'surgery_history',
        current.surgeryHistory,
      ),
      familyHistory: _profileText(
        profile,
        'family_history',
        current.familyHistory,
      ),
      pregnancyCycle: _profileText(
        profile,
        'pregnancy_cycle',
        current.pregnancyCycle,
      ),
      emergencyContactName: _profileText(
        profile,
        'emergency_contact_name',
        current.emergencyContactName,
      ),
      emergencyContactPhone: _profileText(
        profile,
        'emergency_contact_phone',
        current.emergencyContactPhone,
      ),
      authToken: result.token,
      safetyConsentAccepted:
          _profileBool(profile, 'safety_consent_accepted') ||
          current.safetyConsentAccepted,
      intakeSummary: _profileText(
        profile,
        'intake_summary',
        current.intakeSummary,
      ),
      intakeCompleted:
          _profileBool(profile, 'intake_completed') || current.intakeCompleted,
      dashboardNotes: dashboardNotes.isNotEmpty
          ? dashboardNotes
          : current.dashboardNotes,
      reminders: _filterUserFacingAiReminders(
        reminders.isNotEmpty ? reminders : current.reminders,
      ),
      reports: _profileStringList(reports).isNotEmpty
          ? _filterUserFacingReports(_profileStringList(reports))
          : _filterUserFacingReports(current.reports),
      chatHistory: chatHistory is List
          ? _sanitizeHiddenCallMessagesForDisplay(
              chatHistory
                  .whereType<Map>()
                  .map(
                    (entry) => AiCoachMessage.fromJson(
                      Map<String, dynamic>.from(entry),
                    ),
                  )
                  .where((message) => message.text.trim().isNotEmpty)
                  .toList(),
              callMemories: current.callMemories,
            )
          : current.chatHistory,
      healthLogs: healthLogs is List
          ? healthLogs
                .whereType<Map>()
                .map(
                  (entry) =>
                      HealthLogEntry.fromJson(Map<String, dynamic>.from(entry)),
                )
                .toList()
          : current.healthLogs,
      mealAnalyses: mealAnalyses is List
          ? mealAnalyses
                .whereType<Map>()
                .map(
                  (entry) => MealAnalysisEntry.fromJson(
                    Map<String, dynamic>.from(entry),
                  ),
                )
                .toList()
          : current.mealAnalyses,
      savedReminders: savedReminders is List
          ? savedReminders
                .whereType<Map>()
                .map(
                  (entry) => FlickoSavedReminder.fromJson(
                    Map<String, dynamic>.from(entry),
                  ),
                )
                .whereType<FlickoSavedReminder>()
                .toList()
          : current.savedReminders,
      careTasks: careTasks is List
          ? careTasks
                .whereType<Map>()
                .map(
                  (entry) =>
                      FlickoCareTask.fromJson(Map<String, dynamic>.from(entry)),
                )
                .whereType<FlickoCareTask>()
                .toList()
          : current.careTasks,
      safetyEvents: safetyEvents is List
          ? safetyEvents
                .whereType<Map>()
                .map(
                  (entry) => FlickoSafetyEvent.fromJson(
                    Map<String, dynamic>.from(entry),
                  ),
                )
                .toList()
          : current.safetyEvents,
      selectedProblems: selectedProblems.isNotEmpty
          ? selectedProblems
          : current.selectedProblems,
      bmiIntroSeen: false,
    );
  }

  String _profileText(
    Map<String, dynamic> profile,
    String key,
    String fallback,
  ) {
    final value = profile[key];
    if (value == null) {
      return fallback;
    }
    final text = value.toString().trim();
    return text.isEmpty ? fallback : text;
  }

  bool _profileBool(Map<String, dynamic> profile, String key) {
    final value = profile[key];
    if (value is bool) {
      return value;
    }
    return value?.toString().toLowerCase() == 'true';
  }

  List<String> _profileStringList(Object? value) {
    if (value is! List) {
      return const <String>[];
    }
    return value
        .map((entry) => entry.toString().trim())
        .where((entry) => entry.isNotEmpty)
        .toList(growable: false);
  }

  Set<String> _profileStringSet(Object? value) {
    return _profileStringList(value).toSet();
  }

  String _buildProfileContext(HealthProfileDraft draft) {
    final fullName = [
      draft.firstName.trim(),
      draft.middleName.trim(),
      draft.lastName.trim(),
    ].where((value) => value.isNotEmpty).join(' ');
    final displayName = fullName.isNotEmpty ? fullName : draft.name.trim();
    final speechName = draft.givenName.trim().isNotEmpty
        ? draft.givenName.trim()
        : _speechNameFromDisplayName(displayName);
    final lines = <String>[
      if (speechName.isNotEmpty) 'User name for speech: $speechName',
      if (speechName.isNotEmpty) 'User first name: $speechName',
      if (displayName.isNotEmpty) 'User name: $displayName',
      if (draft.email.trim().isNotEmpty) 'User email: ${draft.email.trim()}',
      if (draft.selectedProblems.isNotEmpty)
        'Selected problems: ${draft.selectedProblems.toList()..sort()}',
      if (draft.age.trim().isNotEmpty) 'Age: ${draft.age.trim()}',
      if (draft.gender.trim().isNotEmpty) 'Gender: ${draft.gender.trim()}',
      if (_weightSummary(draft).isNotEmpty) 'Weight: ${_weightSummary(draft)}',
      if (_goalWeightSummary(draft).isNotEmpty)
        'Goal weight: ${_goalWeightSummary(draft)}',
      if (_heightSummary(draft).isNotEmpty) 'Height: ${_heightSummary(draft)}',
      if (draft.foodPreference.trim().isNotEmpty)
        'Food preference: ${draft.foodPreference.trim()}',
      if (draft.language.trim().isNotEmpty)
        'Preferred language: ${draft.language.trim()}',
      if (draft.timezone.trim().isNotEmpty)
        'Timezone: ${draft.timezone.trim()}',
      if (draft.medications.trim().isNotEmpty)
        'Current medications: ${draft.medications.trim()}',
      if (draft.allergies.trim().isNotEmpty)
        'Allergies: ${draft.allergies.trim()}',
      if (draft.diagnosis.trim().isNotEmpty)
        'Recent diagnosis: ${draft.diagnosis.trim()}',
      if (draft.surgeryHistory.trim().isNotEmpty)
        'Surgery history: ${draft.surgeryHistory.trim()}',
      if (draft.familyHistory.trim().isNotEmpty)
        'Family history: ${draft.familyHistory.trim()}',
      if (draft.pregnancyCycle.trim().isNotEmpty)
        'Pregnancy or cycle notes: ${draft.pregnancyCycle.trim()}',
      if (draft.emergencyContactName.trim().isNotEmpty ||
          draft.emergencyContactPhone.trim().isNotEmpty)
        'Emergency contact: ${[draft.emergencyContactName.trim(), draft.emergencyContactPhone.trim()].where((value) => value.isNotEmpty).join(' - ')}',
      if (draft.lastAiCallCompletedAt.trim().isNotEmpty)
        'Last AI voice call completed: ${draft.lastAiCallCompletedAt.trim()}',
      if (draft.lastAiCallInviteAt.trim().isNotEmpty)
        'Last proactive call invite: ${draft.lastAiCallInviteAt.trim()}',
      if (draft.aiCallInviteLog.isNotEmpty)
        'AI call invite log: ${draft.aiCallInviteLog.entries.map((entry) => '${entry.key}=${entry.value}').join(' | ')}',
      if (draft.callMemories.isNotEmpty)
        'Saved AI call memory: ${_recentCallMemorySummary(draft.callMemories)}',
      if (_recentCallOpeningSummary(draft.callMemories).isNotEmpty)
        'Recent AI call openings to avoid: ${_recentCallOpeningSummary(draft.callMemories)}',
      if (draft.intakeSummary.trim().isNotEmpty)
        'Latest intake summary: ${draft.intakeSummary.trim()}',
      if (draft.intakeCompleted) 'Intake status: complete',
      if (draft.dashboardNotes.isNotEmpty)
        'Dashboard notes: ${draft.dashboardNotes.join(' | ')}',
      if (draft.reminders.isNotEmpty)
        'Active reminders: ${draft.reminders.join(' | ')}',
      if (draft.savedReminders.isNotEmpty)
        'Scheduled daily reminders: ${draft.savedReminders.map((reminder) => '${reminder.timeLabel} ${reminder.body}').join(' | ')}',
      if (draft.careTasks.isNotEmpty)
        'Care tasks: ${draft.careTasks.map((task) => task.compactSummary).join(' | ')}',
      if (draft.reports.isNotEmpty)
        'Saved reports: ${draft.reports.join(' | ')}',
      if (_visibleChatHistory(draft).isNotEmpty)
        'Recent chat conversation: ${_recentConversationSummary(_visibleChatHistory(draft))}',
      if (draft.healthLogs.isNotEmpty)
        'Recent local health logs: ${_recentHealthLogSummary(draft.healthLogs)}',
      if (draft.mealAnalyses.isNotEmpty)
        'Recent meal photo scores: ${_recentMealAnalysisSummary(draft.mealAnalyses)}',
      if (draft.safetyEvents.isNotEmpty)
        'Recent safety flags: ${_recentSafetyEventSummary(draft.safetyEvents)}',
    ];

    return lines.isEmpty ? 'Profile setup is incomplete.' : lines.join('\n');
  }

  String _speechNameFromDisplayName(String value) {
    final clean = value.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (clean.isEmpty) {
      return '';
    }
    return clean.split(' ').first.trim();
  }

  List<AiCoachMessage> _visibleChatHistory(HealthProfileDraft draft) {
    return _sanitizeHiddenCallMessagesForDisplay(
      draft.chatHistory,
      callMemories: draft.callMemories,
    );
  }

  String _recentConversationSummary(List<AiCoachMessage> history) {
    final messages = history
        .where((message) => message.text.trim().isNotEmpty)
        .toList();
    final recent = messages.length <= 6
        ? messages
        : messages.sublist(messages.length - 6);
    return recent
        .map((message) {
          final role = message.isUser ? 'User' : 'Flicko';
          final text = message.text.trim().replaceAll(RegExp(r'\s+'), ' ');
          final clipped = text.length > 180
              ? '${text.substring(0, 177)}...'
              : text;
          return '$role: $clipped';
        })
        .join(' | ');
  }

  String _recentCallMemorySummary(List<HealthCallMemorySummary> memories) {
    final recent = memories.length <= 4 ? memories : memories.take(4).toList();
    return recent
        .map((memory) {
          final text = memory.memoryContent.replaceAll(RegExp(r'\s+'), ' ');
          final clipped = text.length > 420
              ? '${text.substring(0, 417)}...'
              : text;
          return '${memory.endedAt.toIso8601String()} ${memory.problemName}: $clipped';
        })
        .join(' | ');
  }

  String _recentCallOpeningSummary(List<HealthCallMemorySummary> memories) {
    final recent = memories.length <= 5 ? memories : memories.take(5).toList();
    final openings = <String>[];
    for (final memory in recent) {
      String? firstAssistant;
      for (final entry in memory.transcript) {
        if (!entry.isUser && entry.text.trim().isNotEmpty) {
          firstAssistant = entry.text.trim();
          break;
        }
      }
      if (firstAssistant == null) {
        continue;
      }
      final normalized = firstAssistant.replaceAll(RegExp(r'\s+'), ' ').trim();
      final clipped = normalized.length > 150
          ? '${normalized.substring(0, 147).trim()}...'
          : normalized;
      if (clipped.isNotEmpty && !openings.contains(clipped)) {
        openings.add(clipped);
      }
    }
    return openings.join(' | ');
  }

  String _recentHealthLogSummary(List<HealthLogEntry> logs) {
    final recent = logs.length <= 10 ? logs : logs.take(10).toList();
    return recent
        .map((log) {
          final text = log.compactSummary.replaceAll(RegExp(r'\s+'), ' ');
          final clipped = text.length > 140
              ? '${text.substring(0, 137)}...'
              : text;
          return '${log.type.label}: $clipped';
        })
        .join(' | ');
  }

  String _recentMealAnalysisSummary(List<MealAnalysisEntry> entries) {
    final recent = entries.length <= 8 ? entries : entries.take(8).toList();
    return recent
        .map((entry) {
          final text = entry.compactSummary.replaceAll(RegExp(r'\s+'), ' ');
          final clipped = text.length > 150
              ? '${text.substring(0, 147)}...'
              : text;
          return '${entry.mealName}: $clipped';
        })
        .join(' | ');
  }

  String _recentSafetyEventSummary(List<FlickoSafetyEvent> events) {
    final recent = events.length <= 8 ? events : events.take(8).toList();
    return recent
        .map((event) {
          final text = event.compactSummary.replaceAll(RegExp(r'\s+'), ' ');
          final clipped = text.length > 150
              ? '${text.substring(0, 147)}...'
              : text;
          return clipped;
        })
        .join(' | ');
  }

  String _weightSummary(HealthProfileDraft draft) {
    final kg = draft.weightKg.trim();
    final lb = draft.weightLb.trim();
    if (kg.isNotEmpty && lb.isNotEmpty) {
      return '$kg kg / $lb lb';
    }
    if (kg.isNotEmpty) {
      return '$kg kg';
    }
    if (lb.isNotEmpty) {
      return '$lb lb';
    }
    return '';
  }

  String _goalWeightSummary(HealthProfileDraft draft) {
    final kg = draft.goalWeightKg.trim();
    final lb = draft.goalWeightLb.trim();
    if (kg.isNotEmpty && lb.isNotEmpty) {
      return '$kg kg / $lb lb';
    }
    if (kg.isNotEmpty) {
      return '$kg kg';
    }
    if (lb.isNotEmpty) {
      return '$lb lb';
    }
    return '';
  }

  String _heightSummary(HealthProfileDraft draft) {
    final cm = draft.heightCm.trim();
    final feet = draft.heightFeet.trim();
    final inches = draft.heightInches.trim();
    if (cm.isNotEmpty && feet.isNotEmpty) {
      return '$cm cm / $feet ft ${inches.isEmpty ? '0' : inches} in';
    }
    if (cm.isNotEmpty) {
      return '$cm cm';
    }
    if (feet.isNotEmpty || inches.isNotEmpty) {
      return '${feet.isEmpty ? '0' : feet} ft ${inches.isEmpty ? '0' : inches} in';
    }
    return '';
  }

  HealthProfileDraft _draftWithCoachUpdates(
    List<AiCoachMessage> history,
    CoachAppUpdate update,
  ) {
    return widget.draft.copyWith(
      chatHistory: history,
      intakeSummary: update.intakeSummary.isNotEmpty
          ? update.intakeSummary
          : widget.draft.intakeSummary,
      intakeCompleted: update.intakeComplete || widget.draft.intakeCompleted,
      dashboardNotes: update.dashboardNotes.isNotEmpty
          ? _mergeUnique([
              ...update.dashboardNotes,
              ...widget.draft.dashboardNotes,
            ]).take(40).toList()
          : widget.draft.dashboardNotes,
      reminders: update.reminders.isNotEmpty
          ? _filterUserFacingAiReminders(
              _mergeUnique([...update.reminders, ...widget.draft.reminders]),
            ).take(40).toList()
          : _filterUserFacingAiReminders(widget.draft.reminders),
      reports: _filterUserFacingReports(widget.draft.reports),
    );
  }

  void _handleChatHistoryChanged(List<AiCoachMessage> history) {
    final previousDraft = widget.draft;
    final visibleHistory = _sanitizeHiddenCallMessagesForDisplay(
      history,
      callMemories: previousDraft.callMemories,
    );
    final update = CoachUpdateParser.fromMessages(visibleHistory);
    final draft = _draftWithCoachUpdates(visibleHistory, update);
    widget.onDraftChanged(draft);
    unawaited(_syncProfileIfAuthenticated(draft));
    if (visibleHistory.isNotEmpty) {
      unawaited(
        _syncAppRecordIfAuthenticated(
          draft,
          recordType: 'chat-messages',
          record: {
            ...visibleHistory.last.toJson(),
            'problemName': _primaryProblem(draft),
            'createdAt': DateTime.now().toIso8601String(),
          },
        ),
      );
    }
    if (update.hasAny) {
      unawaited(
        _saveMemoryIfAuthenticated(
          draft,
          source: 'chat',
          category: update.intakeComplete ? 'intake_summary' : 'note',
          title: update.intakeComplete
              ? 'AI intake completed'
              : 'AI coach app update',
          content: update.intakeSummary.isNotEmpty
              ? update.intakeSummary
              : _recentConversationSummary(visibleHistory),
          data: <String, Object?>{
            'dashboard_notes': update.dashboardNotes,
            'reminders': update.reminders,
            'reports': update.reports,
            'intake_complete': update.intakeComplete,
          },
        ),
      );
    }
    final reportRequest = _reportGenerationCoordinator.chatAutoRequest(
      previous: _reportGenerationSnapshot(previousDraft),
      next: _reportGenerationSnapshot(draft),
      update: update,
      history: visibleHistory,
      now: DateTime.now(),
    );
    if (reportRequest != null) {
      unawaited(_syncProfileReportRequest(draft, request: reportRequest));
    }
  }

  void _handleAiCallCompleted(AiCallSessionSummary summary) {
    final current = widget.draft;
    final plan = _callCompletionCoordinator.build(
      snapshot: FlickoCallCompletionSnapshot(
        intakeSummary: current.intakeSummary,
        intakeCompleted: current.intakeCompleted,
        dashboardNotes: current.dashboardNotes,
        reminders: current.reminders,
        callMemories: current.callMemories,
        savedReminders: current.savedReminders,
        careTasks: current.careTasks,
      ),
      summary: summary,
      firstName: current.givenName,
    );
    final draft = current.copyWith(
      lastAiCallCompletedAt: plan.lastAiCallCompletedAt,
      intakeSummary: plan.intakeSummary,
      intakeCompleted: plan.intakeCompleted,
      dashboardNotes: plan.dashboardNotes,
      reminders: plan.reminders,
      reports: _filterUserFacingReports(current.reports),
      chatHistory: _visibleChatHistory(current).take(300).toList(),
      callMemories: plan.callMemories,
      savedReminders: plan.savedReminders,
      careTasks: plan.careTasks,
    );
    widget.onDraftChanged(draft);
    final autoCallReportRequest = _reportGenerationCoordinator.callAutoRequest(
      snapshot: _reportGenerationSnapshot(draft),
      summary: summary,
      now: summary.endedAt,
    );
    unawaited(
      _callCompletionEffectExecutor.execute(
        plan: plan,
        onScheduledReminderKey: _scheduledReminderKeys.add,
        scheduleReminder: (reminder) async {
          await FlickoNotificationService.instance.scheduleReminderRequest(
            reminder.toScheduleRequest(),
          );
        },
        scheduleDailyInvite: (invitePlan) {
          return _scheduleAiCallInvite(
            draft,
            invitePlan.spec,
            scheduledAt: invitePlan.scheduledAt,
            repeatsDaily: invitePlan.repeatsDaily,
            auditTitle: invitePlan.auditTitle,
            auditContent: invitePlan.auditContent,
          );
        },
        scheduleBusyRetryInvite: (retryPlan) {
          return _scheduleAiCallInvite(
            draft,
            retryPlan.spec,
            scheduledAt: retryPlan.scheduledAt,
            auditTitle: retryPlan.auditTitle,
            auditContent: retryPlan.auditContent,
          );
        },
        syncRecord: (recordSync) {
          return _syncAppRecordIfAuthenticated(
            draft,
            recordType: recordSync.recordType,
            record: recordSync.record,
          );
        },
        syncProfile: () => _syncProfileIfAuthenticated(draft),
        saveMemory: (title, content, data) {
          return _saveMemoryIfAuthenticated(
            draft,
            source: 'call',
            category: 'intake_summary',
            title: title,
            content: content,
            data: data,
          );
        },
        syncCallReport: (callMemory) async {
          if (autoCallReportRequest == null) {
            return;
          }
          await _syncCallReportRequest(
            draft,
            callMemory,
            autoCallReportRequest,
          );
        },
        syncReport: () async {},
        onError: (stage, error) {
          debugPrint('Flicko call completion effect skipped at $stage: $error');
        },
      ),
    );
  }

  void _handleHealthLogAdded(HealthLogEntry entry) {
    final current = widget.draft;
    final safetyEvent = FlickoSafetyEngine.evaluate(
      text: entry.compactSummary,
      problemName: _primaryProblem(current),
      source: 'manual',
    );
    final nextLogs = <HealthLogEntry>[
      entry,
      ...current.healthLogs.where((log) => log.id != entry.id),
    ].take(250).toList(growable: false);
    final draft = _draftWithSafetyEvent(
      current.copyWith(healthLogs: nextLogs),
      safetyEvent,
    );
    widget.onDraftChanged(draft);
    unawaited(
      _syncAppRecordIfAuthenticated(
        draft,
        recordType: 'health-logs',
        record: entry.toJson(),
      ),
    );
    unawaited(_syncProfileIfAuthenticated(draft));
    unawaited(
      _saveMemoryIfAuthenticated(
        draft,
        source: 'local_log',
        category: entry.type.name,
        title: entry.title,
        content: entry.compactSummary,
        data: entry.toJson(),
      ),
    );
    unawaited(FlickoNotificationService.instance.showLogSaved(entry));
    if (safetyEvent != null) {
      unawaited(
        _syncAppRecordIfAuthenticated(
          draft,
          recordType: 'safety-events',
          record: safetyEvent.toJson(),
        ),
      );
      unawaited(_syncSafetyEvent(draft, safetyEvent));
    }
  }

  Future<bool> _handleMealAnalysisAdded(MealAnalysisEntry entry) async {
    if (!mounted) {
      return false;
    }
    final current = widget.draft;
    final mealLog = HealthLogEntry.create(
      type: HealthLogType.meal,
      title: 'Meal photo score',
      value: entry.score.toString(),
      unit: 'score',
      note: entry.compactSummary,
      problemName: entry.problemName,
    );
    final draft = current.copyWith(
      mealAnalyses: <MealAnalysisEntry>[
        entry,
        ...current.mealAnalyses.where((item) => item.id != entry.id),
      ].take(80).toList(),
      healthLogs: <HealthLogEntry>[
        mealLog,
        ...current.healthLogs.where((log) => log.id != mealLog.id),
      ].take(250).toList(),
    );
    widget.onDraftChanged(draft);
    unawaited(
      _syncAppRecordIfAuthenticated(
        draft,
        recordType: 'meal-analyses',
        record: entry.toJson(),
      ),
    );
    unawaited(
      _syncAppRecordIfAuthenticated(
        draft,
        recordType: 'health-logs',
        record: mealLog.toJson(),
      ),
    );
    unawaited(_syncProfileIfAuthenticated(draft));
    unawaited(
      _saveMemoryIfAuthenticated(
        draft,
        source: 'meal_photo',
        category: 'meal_analysis',
        title: entry.mealName,
        content: entry.compactSummary,
        data: entry.toJson(),
      ),
    );
    unawaited(FlickoNotificationService.instance.showLogSaved(mealLog));
    return true;
  }

  Future<bool> _handleSafetyEventAdded(FlickoSafetyEvent event) async {
    if (!mounted) {
      return false;
    }
    final draft = _draftWithSafetyEvent(widget.draft, event);
    widget.onDraftChanged(draft);
    unawaited(
      _syncAppRecordIfAuthenticated(
        draft,
        recordType: 'safety-events',
        record: event.toJson(),
      ),
    );
    unawaited(_syncProfileIfAuthenticated(draft));
    unawaited(_syncSafetyEvent(draft, event));
    return true;
  }

  HealthProfileDraft _draftWithSafetyEvent(
    HealthProfileDraft draft,
    FlickoSafetyEvent? event,
  ) {
    if (event == null) {
      return draft;
    }
    return draft.copyWith(
      safetyEvents: <FlickoSafetyEvent>[
        event,
        ...draft.safetyEvents.where((entry) => entry.id != event.id),
      ].take(80).toList(growable: false),
    );
  }

  Future<void> _syncSafetyEvent(
    HealthProfileDraft draft,
    FlickoSafetyEvent event,
  ) async {
    await FlickoNotificationService.instance.showHealthReminder(
      title: event.severity == FlickoSafetySeverity.emergency
          ? 'Flicko emergency safety flag'
          : 'Flicko urgent safety flag',
      body: event.title,
      payload: 'safety:${event.id}',
    );
    await _saveMemoryIfAuthenticated(
      draft,
      source: event.source == 'chat' ? 'chat' : 'manual',
      category: 'safety',
      title: event.title,
      content: event.compactSummary,
      data: event.toJson(),
    );
  }

  void _handleReminderNotification(String reminder) {
    final body = reminder.trim().isEmpty
        ? 'Time for your Flicko health check-in.'
        : reminder.trim();
    unawaited(
      FlickoNotificationService.instance.showHealthReminder(
        title: 'Flicko health reminder',
        body: body,
        payload: 'manual-reminder:${_stableKey(body)}',
      ),
    );
  }

  Future<void> _ensureSavedRemindersScheduled(HealthProfileDraft draft) async {
    final activeReminders = FlickoSavedReminder.dedupe(
      draft.savedReminders.where(
        (entry) => entry.enabled && _isUserFacingSavedReminder(entry),
      ),
    );
    final activePayloads = activeReminders
        .map((reminder) => reminder.payload)
        .toSet();
    final pendingPayloads = await FlickoNotificationService.instance
        .pendingNotificationPayloads(prefix: 'saved-reminder:');
    for (final payload in pendingPayloads) {
      if (activePayloads.contains(payload)) {
        continue;
      }
      await FlickoNotificationService.instance.cancelReminderPayload(payload);
      _scheduledReminderKeys.removeWhere(
        (existing) => existing.startsWith('$payload|'),
      );
    }

    for (final reminder in activeReminders) {
      final key = '${reminder.payload}|${reminder.hour}:${reminder.minute}';
      if (_scheduledReminderKeys.contains(key)) {
        continue;
      }
      _scheduledReminderKeys.removeWhere(
        (existing) => existing.startsWith('${reminder.payload}|'),
      );
      final scheduled = await FlickoNotificationService.instance
          .scheduleReminderRequest(reminder.toScheduleRequest());
      if (scheduled) {
        _scheduledReminderKeys.add(key);
      }
    }
  }

  Future<bool> _handleSavedReminderUpsert(FlickoSavedReminder reminder) async {
    if (!mounted) {
      return false;
    }

    final current = widget.draft;
    final nextReminders =
        FlickoSavedReminder.dedupe([
          reminder,
          ...current.savedReminders.where((entry) => entry.id != reminder.id),
        ])..sort((a, b) {
          final hourCompare = a.hour.compareTo(b.hour);
          return hourCompare != 0 ? hourCompare : a.minute.compareTo(b.minute);
        });
    final draft = current.copyWith(savedReminders: nextReminders);
    widget.onDraftChanged(draft);

    final nextReminderIds = nextReminders.map((entry) => entry.id).toSet();
    for (final removed in current.savedReminders.where(
      (entry) => !nextReminderIds.contains(entry.id),
    )) {
      _scheduledReminderKeys.removeWhere(
        (key) => key.startsWith('${removed.payload}|'),
      );
      await FlickoNotificationService.instance.cancelReminderPayload(
        removed.payload,
      );
    }
    _scheduledReminderKeys.removeWhere(
      (key) => key.startsWith('${reminder.payload}|'),
    );
    await FlickoNotificationService.instance.cancelReminderPayload(
      reminder.payload,
    );
    final scheduled = await FlickoNotificationService.instance
        .scheduleReminderRequest(reminder.toScheduleRequest());
    if (scheduled) {
      _scheduledReminderKeys.add(
        '${reminder.payload}|${reminder.hour}:${reminder.minute}',
      );
    }
    if (!scheduled) {
      unawaited(
        FlickoNotificationService.instance.showHealthReminder(
          title: 'Reminder saved in Flicko',
          body:
              'Android blocked the background alarm. Open Flicko to see ${reminder.timeLabel} reminders.',
          payload: 'local-reminder-saved:${reminder.id}',
        ),
      );
    }

    unawaited(
      _syncAppRecordIfAuthenticated(
        draft,
        recordType: 'reminders',
        record: reminder.toJson(),
      ),
    );
    unawaited(_syncProfileIfAuthenticated(draft));
    unawaited(
      _saveMemoryIfAuthenticated(
        draft,
        source: 'local_reminder',
        category: 'reminder',
        title: reminder.title,
        content: '${reminder.timeLabel} - ${reminder.body}',
        data: reminder.toJson(),
      ),
    );
    return true;
  }

  Future<bool> _handleSavedReminderDelete(FlickoSavedReminder reminder) async {
    final current = widget.draft;
    final draft = current.copyWith(
      savedReminders: current.savedReminders
          .where((entry) => entry.id != reminder.id)
          .toList(),
    );
    widget.onDraftChanged(draft);
    unawaited(
      _deleteAppRecordIfAuthenticated(
        draft,
        recordType: 'reminders',
        externalId: reminder.id,
      ),
    );
    unawaited(_syncProfileIfAuthenticated(draft));
    await FlickoNotificationService.instance.cancelReminderPayload(
      reminder.payload,
    );
    _scheduledReminderKeys.removeWhere(
      (key) => key.startsWith('${reminder.payload}|'),
    );
    return true;
  }

  Future<bool> _handleCareTaskUpsert(FlickoCareTask task) async {
    if (!mounted) {
      return false;
    }
    final current = widget.draft;
    final nextTasks =
        <FlickoCareTask>[
          task,
          ...current.careTasks.where((entry) => entry.id != task.id),
        ]..sort((a, b) {
          if (a.isDoneToday != b.isDoneToday) {
            return a.isDoneToday ? 1 : -1;
          }
          return a.title.toLowerCase().compareTo(b.title.toLowerCase());
        });
    final draft = current.copyWith(careTasks: nextTasks.take(80).toList());
    widget.onDraftChanged(draft);
    unawaited(
      _syncAppRecordIfAuthenticated(
        draft,
        recordType: 'care-tasks',
        record: task.toJson(),
      ),
    );
    unawaited(_syncProfileIfAuthenticated(draft));
    unawaited(
      _saveMemoryIfAuthenticated(
        draft,
        source: 'care_task',
        category: task.type.name,
        title: task.title,
        content: task.compactSummary,
        data: task.toJson(),
      ),
    );
    return true;
  }

  Future<bool> _handleCareTaskDelete(FlickoCareTask task) async {
    if (!mounted) {
      return false;
    }
    final current = widget.draft;
    final draft = current.copyWith(
      careTasks: current.careTasks
          .where((entry) => entry.id != task.id)
          .toList(),
    );
    widget.onDraftChanged(draft);
    unawaited(
      _deleteAppRecordIfAuthenticated(
        draft,
        recordType: 'care-tasks',
        externalId: task.id,
      ),
    );
    unawaited(_syncProfileIfAuthenticated(draft));
    return true;
  }

  Future<DashboardReportCreationResult> _handleCreateDashboardReport() async {
    final draft = widget.draft;
    if (draft.authToken.trim().isEmpty) {
      return const DashboardReportCreationResult(
        success: false,
        message: 'Login is required before creating a backend PDF report.',
      );
    }
    final request = _reportGenerationCoordinator.manualSpecialReport(
      _reportGenerationSnapshot(draft),
      now: DateTime.now(),
    );
    if (request == null) {
      return const DashboardReportCreationResult(
        success: false,
        message:
            'Complete the first AI setup before generating special reports.',
      );
    }
    try {
      final result = await _syncProfileReportRequest(
        draft,
        request: request,
        returnResult: true,
        throwOnError: true,
      );
      if (!mounted) {
        return const DashboardReportCreationResult(
          success: false,
          message: 'Report created after screen closed.',
        );
      }
      if (result == null) {
        return const DashboardReportCreationResult(
          success: false,
          message: 'Special report request was skipped.',
        );
      }
      return const DashboardReportCreationResult(
        success: true,
        message: 'Special Flicko report created. Open it from report history.',
      );
    } catch (error) {
      return DashboardReportCreationResult(
        success: false,
        message: error is HealthReportApiException
            ? error.message
            : 'Could not create report from backend.',
      );
    }
  }

  Future<String> _handleMedicalReportExtracted({
    required String summary,
    required String fileName,
    required String mimeType,
  }) async {
    final current = widget.draft;
    final problemName = _primaryProblem(current);
    final uploadedAt = DateTime.now();
    final cleanFileName = fileName.trim().isEmpty
        ? 'uploaded medical report'
        : fileName.trim();
    final reportTitle = '$problemName Uploaded Medical Report';
    final reportNote =
        'Uploaded report file: $cleanFileName\n'
        'Uploaded at: ${uploadedAt.toIso8601String()}\n\n'
        '${summary.trim()}';

    final localDraft = current.copyWith(
      intakeSummary: current.intakeSummary.trim().isEmpty
          ? reportNote
          : '${current.intakeSummary.trim()}\n\n$reportNote',
      dashboardNotes: _mergeUnique([
        'Medical report uploaded: $cleanFileName',
        summary.trim(),
        ...current.dashboardNotes,
      ]).take(80).toList(),
      reports: _mergeReportLabels([
        '$reportTitle\nLocal upload: $cleanFileName',
      ], current.reports).take(8).toList(),
    );
    widget.onDraftChanged(localDraft);
    unawaited(_syncProfileIfAuthenticated(localDraft));

    if (localDraft.authToken.trim().isEmpty) {
      return 'I read this report and saved it locally in your Flicko profile. Login is needed to sync it to backend report history.';
    }

    try {
      final transcript = <AiCoachMessage>[
        AiCoachMessage.user(
          'Uploaded medical report: $cleanFileName',
          source: 'upload',
        ),
        AiCoachMessage.assistant(summary, source: 'upload'),
      ];
      final result = await _reportApiClient.createIntakeReport(
        token: localDraft.authToken,
        title: reportTitle,
        problemName: problemName,
        intakeSummary: reportNote,
        dashboardValues: {
          ..._dashboardValues(localDraft),
          'uploaded_report_file': cleanFileName,
          'uploaded_report_mime_type': mimeType,
        },
        reminders: _reportReminderLines(localDraft),
        transcript: transcript,
        source: 'medical_report_upload',
        sourcePayload: {
          ..._profilePayload(localDraft),
          'uploaded_report_file': cleanFileName,
          'uploaded_report_mime_type': mimeType,
          'uploaded_at': uploadedAt.toIso8601String(),
        },
        rawTranscriptText: reportNote,
        analyzeConversation: true,
      );
      _clearBackendSyncFailure();
      if (!mounted) {
        return 'Report sync completed.';
      }
      final updated = _draftWithReportData(localDraft, result);
      widget.onDraftChanged(
        updated.copyWith(
          reports: _mergeReportLabels([
            _reportLabelFromResult(result),
          ], updated.reports).take(8).toList(),
        ),
      );
      return 'Report saved to backend and added to your Flicko report history. Future AI calls and chats can use it from profile memory.';
    } catch (error) {
      _noteBackendSyncFailure('medical report upload sync', error);
      return 'I saved the report summary locally. Backend sync failed right now, so Flicko will keep it in app memory and try profile sync later.';
    }
  }

  Future<void> _syncProfileIfAuthenticated(HealthProfileDraft draft) async {
    if (draft.authToken.trim().isEmpty) {
      return;
    }
    if (_backendSyncCoolingDown()) {
      return;
    }

    final key = _profileSyncKey(draft);
    if (!_syncingProfileKeys.add(key)) {
      return;
    }

    try {
      await _profileApiClient.syncProfile(
        token: draft.authToken,
        profile: _profilePayload(draft),
      );
      final appDataResponse = await _profileApiClient.syncAppData(
        token: draft.authToken,
        data: _appDataPayload(draft),
      );
      final cleanupResponse = await _cleanupBackendAppDataIfNeeded(
        draft.authToken,
      );
      final summaryResponse = _cleanupRemovedAny(cleanupResponse)
          ? await _profileApiClient.fetchAppData(token: draft.authToken)
          : appDataResponse;
      _clearBackendSyncFailure();
      _applyBackendAppSummary(draft, summaryResponse);
    } catch (error) {
      _noteBackendSyncFailure('profile sync', error);
    } finally {
      _syncingProfileKeys.remove(key);
    }
  }

  Future<void> _refreshAppDataIfAuthenticated(HealthProfileDraft draft) async {
    final token = draft.authToken.trim();
    if (token.isEmpty ||
        _backendSyncCoolingDown() ||
        !_refreshingAppDataTokens.add(token)) {
      return;
    }

    try {
      await _cleanupBackendAppDataIfNeeded(token);
      final response = await _profileApiClient.fetchAppData(token: token);
      _clearBackendSyncFailure();
      _applyBackendAppSummary(draft, response);
    } catch (error) {
      _noteBackendSyncFailure('app data refresh', error);
    } finally {
      _refreshingAppDataTokens.remove(token);
    }
  }

  Future<void> _refreshReportHistoryIfAuthenticated(
    HealthProfileDraft draft,
  ) async {
    final token = draft.authToken.trim();
    if (token.isEmpty ||
        _backendSyncCoolingDown() ||
        !_refreshingReportHistoryTokens.add(token)) {
      return;
    }

    try {
      final reports = await _reportApiClient.fetchReportHistory(token: token);
      _clearBackendSyncFailure();
      if (!mounted || widget.draft.authToken != draft.authToken) {
        return;
      }
      final labels = reports
          .map(_reportLabelFromResult)
          .where((entry) => entry.trim().isNotEmpty)
          .toList(growable: false);
      if (labels.isEmpty) {
        return;
      }
      final nextReports = _mergeReportLabels(
        labels,
        widget.draft.reports,
      ).take(80).toList(growable: false);
      if (nextReports.join('\n---\n') == widget.draft.reports.join('\n---\n')) {
        return;
      }
      widget.onDraftChanged(widget.draft.copyWith(reports: nextReports));
    } catch (error) {
      _noteBackendSyncFailure('report history refresh', error);
    } finally {
      _refreshingReportHistoryTokens.remove(token);
    }
  }

  Future<String> _fetchBackendAiContext({
    required String problemName,
    required String text,
  }) async {
    final token = widget.draft.authToken.trim();
    if (token.isEmpty || _backendSyncCoolingDown()) {
      return '';
    }

    try {
      final response = await _profileApiClient.fetchProtocolEngineContext(
        token: token,
        condition: problemName,
        text: text,
        memoryLimit: 18,
      );
      _clearBackendSyncFailure();
      return _backendAiContextPrompt(response);
    } catch (error) {
      _noteBackendSyncFailure('backend AI context', error);
      return '';
    }
  }

  Future<Map<String, dynamic>> _cleanupBackendAppDataIfNeeded(
    String token,
  ) async {
    final cleanToken = token.trim();
    if (cleanToken.isEmpty || !_cleanedBackendAppDataTokens.add(cleanToken)) {
      return <String, dynamic>{};
    }

    try {
      return await _profileApiClient.cleanupAppData(token: cleanToken);
    } catch (error) {
      debugPrint('Flicko backend cleanup skipped: $error');
      return <String, dynamic>{};
    }
  }

  bool _cleanupRemovedAny(Map<String, dynamic> response) {
    final removed = response['removed'];
    if (removed is! Map) {
      return false;
    }
    return removed.values.any((value) {
      if (value is num) {
        return value > 0;
      }
      return int.tryParse(value?.toString() ?? '') != null &&
          int.parse(value.toString()) > 0;
    });
  }

  bool _backendSyncCoolingDown() {
    final retryAfter = _backendRetryAfter;
    return retryAfter != null && DateTime.now().isBefore(retryAfter);
  }

  void _clearBackendSyncFailure() {
    _backendRetryAfter = null;
  }

  void _noteBackendSyncFailure(String label, Object error) {
    final wasCoolingDown = _backendSyncCoolingDown();
    _backendRetryAfter = DateTime.now().add(const Duration(seconds: 25));
    if (!wasCoolingDown) {
      debugPrint('Flicko backend sync paused: $label failed. $error');
    }
  }

  String _backendAiContextPrompt(Map<String, dynamic> context) {
    final lines = <String>['Backend protocol and memory context:'];
    final primaryCondition = context['primary_condition']?.toString().trim();
    if (primaryCondition != null && primaryCondition.isNotEmpty) {
      lines.add('Primary condition: $primaryCondition');
    }

    final engine = context['protocol_engine'];
    if (engine is Map) {
      final protocolIds = _backendAiStringList(engine['protocol_ids']);
      if (protocolIds.isNotEmpty) {
        lines.add('Active protocol IDs: ${protocolIds.take(10).join(', ')}');
      }
      final versions = engine['protocol_versions'];
      if (versions is Map && versions.isNotEmpty) {
        lines.add('Protocol versions: ${_backendAiJson(versions)}');
      }
    }

    final safety = context['safety'];
    if (safety is Map) {
      final highest = safety['highest_severity']?.toString().trim() ?? '';
      if (highest.isNotEmpty) {
        lines.add('Safety highest severity: $highest');
      }
      final matches = _backendAiMapList(safety['matches'])
          .take(4)
          .map((match) {
            final pattern = match['symptom_pattern']?.toString() ?? '';
            final action = match['action']?.toString() ?? '';
            return '${match['severity']}: ${_backendAiClip(pattern, 80)} -> ${_backendAiClip(action, 140)}';
          })
          .where((line) => line.trim().isNotEmpty)
          .toList();
      if (matches.isNotEmpty) {
        lines.add(
          'Safety matches:\n${matches.map((line) => '- $line').join('\n')}',
        );
      }
    }

    final dashboardSeed = context['dashboard_seed'];
    if (dashboardSeed is Map) {
      final seedLines = <String>[
        if (dashboardSeed['score'] != null) 'score=${dashboardSeed['score']}',
        if (dashboardSeed['active_protocol_count'] != null)
          'active_protocol_count=${dashboardSeed['active_protocol_count']}',
        if (dashboardSeed['latest_memory_count'] != null)
          'latest_memory_count=${dashboardSeed['latest_memory_count']}',
      ];
      if (seedLines.isNotEmpty) {
        lines.add('Dashboard seed: ${seedLines.join(', ')}');
      }
      final notes = _backendAiStringList(dashboardSeed['dashboard_notes']);
      if (notes.isNotEmpty) {
        lines.add('Backend dashboard notes: ${notes.take(6).join(' | ')}');
      }
      final reminders = _backendAiStringList(dashboardSeed['reminders']);
      if (reminders.isNotEmpty) {
        lines.add('Backend reminders: ${reminders.take(6).join(' | ')}');
      }
    }

    final memoryLines = _backendAiMapList(context['memory_timeline'])
        .take(12)
        .map((entry) {
          final source = entry['source']?.toString() ?? '';
          final category = entry['category']?.toString() ?? '';
          final title = entry['title']?.toString() ?? '';
          final content = entry['content']?.toString() ?? '';
          return '[$source/$category] ${_backendAiClip(title, 90)}: ${_backendAiClip(content, 260)}';
        })
        .where((line) => line.replaceAll(RegExp(r'[\[\]/: ]'), '').isNotEmpty)
        .toList();
    if (memoryLines.isNotEmpty) {
      lines.add(
        'Backend memory timeline:\n${memoryLines.map((line) => '- $line').join('\n')}',
      );
    }

    final foodRules = _backendAiMapList(context['food_rules'])
        .take(8)
        .map((rule) {
          return '${rule['food_name']} ${rule['rule_type']}: ${_backendAiClip(rule['guidance']?.toString() ?? '', 170)}';
        })
        .where((line) => line.trim().isNotEmpty)
        .toList();
    if (foodRules.isNotEmpty) {
      lines.add(
        'Food rules:\n${foodRules.map((line) => '- $line').join('\n')}',
      );
    }

    final intakeQuestions = _backendAiMapList(context['intake_flows'])
        .take(4)
        .expand((flow) => _backendAiStringList(flow['questions']).take(6))
        .map((question) => _backendAiClip(question, 180))
        .toList();
    if (intakeQuestions.isNotEmpty) {
      lines.add(
        'Condition intake questions:\n${intakeQuestions.map((line) => '- $line').join('\n')}',
      );
    }

    final reminderScripts = _backendAiMapList(context['reminder_scripts'])
        .take(6)
        .map(
          (script) =>
              '${script['trigger_type']}: ${_backendAiClip(script['script']?.toString() ?? '', 180)}',
        )
        .where((line) => line.trim().isNotEmpty)
        .toList();
    if (reminderScripts.isNotEmpty) {
      lines.add(
        'Reminder scripts:\n${reminderScripts.map((line) => '- $line').join('\n')}',
      );
    }

    final metrics = _backendAiMapList(context['outcome_metrics'])
        .take(8)
        .map((metric) {
          final label = metric['label']?.toString() ?? '';
          final unit = metric['unit']?.toString() ?? '';
          final range = metric['normal_range']?.toString() ?? '';
          return '$label ${unit.isEmpty ? '' : '($unit)'} ${range.isEmpty ? '' : 'normal: $range'}'
              .trim();
        })
        .where((line) => line.isNotEmpty)
        .toList();
    if (metrics.isNotEmpty) {
      lines.add(
        'Outcome metrics:\n${metrics.map((line) => '- $line').join('\n')}',
      );
    }

    final intake = context['intake_requirements'];
    if (intake is Map) {
      final summaryParts = <String>[
        if (intake['score'] != null) 'score=${intake['score']}%',
        if (intake['is_complete'] != null)
          'intake_complete=${intake['is_complete']}',
        if (intake['report_ready'] != null)
          'report_ready=${intake['report_ready']}',
      ];
      if (summaryParts.isNotEmpty) {
        lines.add('Structured intake status: ${summaryParts.join(', ')}');
      }

      final missingLabels = _backendAiStringList(intake['missing_labels']);
      if (missingLabels.isNotEmpty) {
        lines.add(
          'Missing intake fields:\n${missingLabels.take(8).map((line) => '- $line').join('\n')}',
        );
      }

      final timelineGaps = _backendAiStringList(intake['timeline_gaps']);
      if (timelineGaps.isNotEmpty) {
        lines.add(
          'Timeline details still missing:\n${timelineGaps.take(6).map((line) => '- $line').join('\n')}',
        );
      }

      final nextQuestions = _backendAiStringList(intake['next_questions']);
      if (nextQuestions.isNotEmpty) {
        lines.add(
          'Next best intake questions:\n${nextQuestions.take(4).map((line) => '- $line').join('\n')}',
        );
      }

      final pendingTargets = _backendAiStringList(
        intake['archive_targets_pending'],
      );
      if (pendingTargets.isNotEmpty) {
        lines.add(
          'Archive to memory when captured:\n${pendingTargets.take(8).map((line) => '- $line').join('\n')}',
        );
      }
    }

    final guardrails = _backendAiStringList(context['ai_guardrails']);
    if (guardrails.isNotEmpty) {
      lines.add(
        'Backend guardrails:\n${guardrails.take(6).map((line) => '- $line').join('\n')}',
      );
    }

    return lines.length <= 1 ? '' : lines.join('\n');
  }

  void _applyBackendAppSummary(
    HealthProfileDraft sourceDraft,
    Map<String, dynamic> response,
  ) {
    if (!mounted || widget.draft.authToken != sourceDraft.authToken) {
      return;
    }
    final hydratedDraft = _draftWithPendingOperations(
      _draftWithBackendAppData(widget.draft, response),
    );
    if (_appDataFingerprint(widget.draft) ==
        _appDataFingerprint(hydratedDraft)) {
      return;
    }
    widget.onDraftChanged(hydratedDraft);
    unawaited(_ensureSavedRemindersScheduled(hydratedDraft));
  }

  HealthProfileDraft _draftWithBackendAppData(
    HealthProfileDraft current,
    Map<String, dynamic> response,
  ) {
    final snapshot = _backendAppDataHydrator.fromResponse(response);
    final summaryMap = snapshot.summary;
    final backendCallMemories = snapshot.hasCallMemories
        ? _mergeCallMemories([
            ...snapshot.callMemories,
            ...current.callMemories,
          ])
        : current.callMemories;
    final backendChatHistory = snapshot.hasChatHistory
        ? snapshot.chatHistory
        : current.chatHistory;
    return current.copyWith(
      backendDashboardSummary: summaryMap.isNotEmpty
          ? summaryMap
          : current.backendDashboardSummary,
      intakeCompleted:
          current.intakeCompleted || snapshot.profileIntakeCompleted,
      healthLogs: snapshot.hasHealthLogs
          ? snapshot.healthLogs
          : current.healthLogs,
      mealAnalyses: snapshot.hasMealAnalyses
          ? snapshot.mealAnalyses
          : current.mealAnalyses,
      savedReminders: snapshot.hasSavedReminders
          ? _savedRemindersFromBackendSnapshot(snapshot.savedReminders)
          : current.savedReminders,
      careTasks: snapshot.hasCareTasks ? snapshot.careTasks : current.careTasks,
      safetyEvents: snapshot.hasSafetyEvents
          ? snapshot.safetyEvents
          : current.safetyEvents,
      chatHistory: _sanitizeHiddenCallMessagesForDisplay(
        backendChatHistory,
        callMemories: backendCallMemories,
      ),
      callMemories: backendCallMemories,
    );
  }

  String _appDataFingerprint(HealthProfileDraft draft) {
    final visibleChatHistory = _visibleChatHistory(draft);
    return jsonEncode({
      'summary': draft.backendDashboardSummary,
      'health_logs': draft.healthLogs.map((entry) => entry.toJson()).toList(),
      'meal_analyses': draft.mealAnalyses
          .map((entry) => entry.toJson())
          .toList(),
      'saved_reminders': draft.savedReminders
          .map((entry) => entry.toJson())
          .toList(),
      'care_tasks': draft.careTasks.map((entry) => entry.toJson()).toList(),
      'safety_events': draft.safetyEvents
          .map((entry) => entry.toJson())
          .toList(),
      'chat_history': visibleChatHistory
          .map((entry) => entry.toJson())
          .toList(),
      'call_memories': draft.callMemories
          .map((entry) => entry.toJson())
          .toList(),
      'ai_call_invite_log': draft.aiCallInviteLog,
      'pending_ops': draft.pendingAppRecordOps
          .map((entry) => entry.toJson())
          .toList(),
    });
  }

  List<FlickoSavedReminder> _savedRemindersFromBackendSnapshot(
    List<FlickoSavedReminder> value,
  ) {
    return _mergeSavedReminders(
      value.where(_isUserFacingSavedReminder).toList(growable: false),
    );
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

  List<FlickoSavedReminder> _mergeSavedReminders(
    List<FlickoSavedReminder> reminders,
  ) {
    final sorted = List<FlickoSavedReminder>.from(reminders)
      ..sort((a, b) {
        final updatedCompare = b.updatedAt.compareTo(a.updatedAt);
        if (updatedCompare != 0) {
          return updatedCompare;
        }
        return b.createdAt.compareTo(a.createdAt);
      });
    final seenIds = <String>{};
    final seenSemantics = <String>{};
    final result = <FlickoSavedReminder>[];
    for (final reminder in sorted) {
      if (!_isUserFacingSavedReminder(reminder)) {
        continue;
      }
      if (!seenIds.add(reminder.id) ||
          !seenSemantics.add(reminder.duplicateSlotKey)) {
        continue;
      }
      result.add(reminder);
    }
    return result.take(80).toList(growable: false);
  }

  List<FlickoCareTask> _mergeCareTasks(List<FlickoCareTask> tasks) {
    final seen = <String>{};
    final result = <FlickoCareTask>[];
    for (final task in tasks) {
      if (!seen.add(task.id)) {
        continue;
      }
      result.add(task);
    }
    result.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return result.take(100).toList(growable: false);
  }

  List<HealthLogEntry> _mergeHealthLogs(List<HealthLogEntry> logs) {
    final seen = <String>{};
    final result = <HealthLogEntry>[];
    for (final log in logs) {
      if (!seen.add(log.id)) {
        continue;
      }
      result.add(log);
    }
    result.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return result.take(120).toList(growable: false);
  }

  List<FlickoSafetyEvent> _mergeSafetyEvents(List<FlickoSafetyEvent> events) {
    final seen = <String>{};
    final result = <FlickoSafetyEvent>[];
    for (final event in events) {
      if (!seen.add(event.id)) {
        continue;
      }
      result.add(event);
    }
    result.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return result.take(80).toList(growable: false);
  }

  HealthProfileDraft _draftWithPendingOperations(HealthProfileDraft draft) {
    var nextDraft = draft;
    for (final operation in _appRecordSyncCoordinator.coalesceQueue(
      draft.pendingAppRecordOps,
    )) {
      nextDraft = _draftWithPendingOperation(nextDraft, operation);
    }
    return nextDraft;
  }

  HealthProfileDraft _draftWithPendingOperation(
    HealthProfileDraft draft,
    FlickoPendingAppRecordOp operation,
  ) {
    switch (operation.recordType) {
      case 'health-logs':
        if (operation.isDelete) {
          return draft.copyWith(
            healthLogs: draft.healthLogs
                .where((entry) => entry.id != operation.externalId)
                .toList(),
          );
        }
        final entry = HealthLogEntry.fromJson(
          Map<String, dynamic>.from(operation.payload),
        );
        return draft.copyWith(
          healthLogs: [
            entry,
            ...draft.healthLogs.where((item) => item.id != entry.id),
          ],
        );
      case 'meal-analyses':
        if (operation.isDelete) {
          return draft.copyWith(
            mealAnalyses: draft.mealAnalyses
                .where((entry) => entry.id != operation.externalId)
                .toList(),
          );
        }
        final entry = MealAnalysisEntry.fromJson(
          Map<String, dynamic>.from(operation.payload),
        );
        return draft.copyWith(
          mealAnalyses: [
            entry,
            ...draft.mealAnalyses.where((item) => item.id != entry.id),
          ],
        );
      case 'reminders':
        if (operation.isDelete) {
          return draft.copyWith(
            savedReminders: draft.savedReminders
                .where((entry) => entry.id != operation.externalId)
                .toList(),
          );
        }
        final entry = FlickoSavedReminder.fromJson(
          Map<String, dynamic>.from(operation.payload),
        );
        if (entry == null) {
          return draft;
        }
        return draft.copyWith(
          savedReminders: FlickoSavedReminder.dedupe([
            entry,
            ...draft.savedReminders.where((item) => item.id != entry.id),
          ]),
        );
      case 'care-tasks':
        if (operation.isDelete) {
          return draft.copyWith(
            careTasks: draft.careTasks
                .where((entry) => entry.id != operation.externalId)
                .toList(),
          );
        }
        final entry = FlickoCareTask.fromJson(
          Map<String, dynamic>.from(operation.payload),
        );
        if (entry == null) {
          return draft;
        }
        return draft.copyWith(
          careTasks: [
            entry,
            ...draft.careTasks.where((item) => item.id != entry.id),
          ],
        );
      case 'safety-events':
        if (operation.isDelete) {
          return draft.copyWith(
            safetyEvents: draft.safetyEvents
                .where((entry) => entry.id != operation.externalId)
                .toList(),
          );
        }
        final entry = FlickoSafetyEvent.fromJson(
          Map<String, dynamic>.from(operation.payload),
        );
        return draft.copyWith(
          safetyEvents: [
            entry,
            ...draft.safetyEvents.where((item) => item.id != entry.id),
          ],
        );
      case 'chat-messages':
        if (operation.isDelete) {
          return draft;
        }
        final entry = AiCoachMessage.fromJson(
          Map<String, dynamic>.from(operation.payload),
        );
        final exists = draft.chatHistory.any(
          (item) =>
              item.text == entry.text &&
              item.isUser == entry.isUser &&
              item.isError == entry.isError,
        );
        return exists
            ? draft
            : draft.copyWith(chatHistory: [...draft.chatHistory, entry]);
      default:
        return draft;
    }
  }

  Future<void> _replayPendingAppRecordOps(HealthProfileDraft draft) async {
    final token = draft.authToken.trim();
    final queued = _appRecordSyncCoordinator.coalesceQueue(
      draft.pendingAppRecordOps,
    );
    if (token.isEmpty || queued.isEmpty) {
      return;
    }

    final replayResult = await _appRecordSyncCoordinator.replayQueued(
      currentQueue: queued,
      upsertRecord: (recordType, record) => _profileApiClient.upsertAppRecord(
        token: token,
        recordType: recordType,
        record: record,
      ),
      deleteRecord: (recordType, externalId) =>
          _profileApiClient.deleteAppRecord(
            token: token,
            recordType: recordType,
            externalId: externalId,
          ),
      onError: (error, operation) {
        debugPrint(
          'Flicko pending record replay kept queued '
          '${operation.recordType}/${operation.externalId}: $error',
        );
      },
    );
    if (!mounted || widget.draft.authToken != token) {
      return;
    }

    final nextQueue = _appRecordSyncCoordinator.reconcileQueueAfterReplay(
      replayedQueue: replayResult.replayedQueue,
      liveQueue: widget.draft.pendingAppRecordOps,
      remainingQueue: replayResult.remainingQueue,
    );
    widget.onDraftChanged(
      widget.draft.copyWith(pendingAppRecordOps: nextQueue),
    );
    if (replayResult.latestResponse != null) {
      _applyBackendAppSummary(widget.draft, replayResult.latestResponse!);
    }
  }

  Future<void> _syncAppRecordIfAuthenticated(
    HealthProfileDraft draft, {
    required String recordType,
    required Map<String, Object?> record,
  }) async {
    final operation = FlickoPendingAppRecordOp.upsert(
      recordType: recordType,
      payload: record,
    );
    if (draft.authToken.trim().isEmpty) {
      _queuePendingAppRecordOp(operation);
      return;
    }
    if (_backendSyncCoolingDown()) {
      _queuePendingAppRecordOp(operation);
      return;
    }
    try {
      final response = await _profileApiClient.upsertAppRecord(
        token: draft.authToken,
        recordType: recordType,
        record: record,
      );
      _clearBackendSyncFailure();
      _removePendingAppRecordOps(operation.mergeKey);
      _applyBackendAppSummary(draft, response);
    } catch (error) {
      _queuePendingAppRecordOp(operation);
      _noteBackendSyncFailure('app record sync', error);
    }
  }

  Future<void> _deleteAppRecordIfAuthenticated(
    HealthProfileDraft draft, {
    required String recordType,
    required String externalId,
  }) async {
    final operation = FlickoPendingAppRecordOp.delete(
      recordType: recordType,
      externalId: externalId,
    );
    if (draft.authToken.trim().isEmpty) {
      _queuePendingAppRecordOp(operation);
      return;
    }
    if (_backendSyncCoolingDown()) {
      _queuePendingAppRecordOp(operation);
      return;
    }
    try {
      final response = await _profileApiClient.deleteAppRecord(
        token: draft.authToken,
        recordType: recordType,
        externalId: externalId,
      );
      _clearBackendSyncFailure();
      _removePendingAppRecordOps(operation.mergeKey);
      _applyBackendAppSummary(draft, response);
    } catch (error) {
      _queuePendingAppRecordOp(operation);
      _noteBackendSyncFailure('app record delete', error);
    }
  }

  void _queuePendingAppRecordOp(FlickoPendingAppRecordOp operation) {
    if (!mounted || operation.externalId.trim().isEmpty) {
      return;
    }
    final nextQueue = _appRecordSyncCoordinator.queueOperation(
      widget.draft.pendingAppRecordOps,
      operation,
    );
    if (_queueFingerprint(widget.draft.pendingAppRecordOps) ==
        _queueFingerprint(nextQueue)) {
      return;
    }
    widget.onDraftChanged(
      widget.draft.copyWith(pendingAppRecordOps: nextQueue),
    );
  }

  void _removePendingAppRecordOps(String mergeKey) {
    if (!mounted || widget.draft.pendingAppRecordOps.isEmpty) {
      return;
    }
    final nextQueue = _appRecordSyncCoordinator.removeMergeKey(
      widget.draft.pendingAppRecordOps,
      mergeKey,
    );
    if (_queueFingerprint(nextQueue) ==
        _queueFingerprint(widget.draft.pendingAppRecordOps)) {
      return;
    }
    widget.onDraftChanged(
      widget.draft.copyWith(pendingAppRecordOps: nextQueue),
    );
  }

  String _queueFingerprint(List<FlickoPendingAppRecordOp> queue) {
    return jsonEncode(queue.map((entry) => entry.toJson()).toList());
  }

  Future<void> _saveMemoryIfAuthenticated(
    HealthProfileDraft draft, {
    required String source,
    required String category,
    required String title,
    String content = '',
    Map<String, Object?> data = const <String, Object?>{},
  }) async {
    if (draft.authToken.trim().isEmpty || _backendSyncCoolingDown()) {
      return;
    }

    try {
      await _profileApiClient.saveMemory(
        token: draft.authToken,
        problemName: _primaryProblem(draft),
        source: source,
        category: category,
        title: title,
        content: content,
        data: data,
      );
      _clearBackendSyncFailure();
    } catch (error) {
      _noteBackendSyncFailure('memory sync', error);
    }
  }

  Map<String, Object?> _profilePayload(HealthProfileDraft draft) {
    final visibleChatHistory = _visibleChatHistory(draft);
    return {
      'name': draft.displayName,
      'mobile': draft.phone.trim(),
      'middle_name': draft.middleName.trim(),
      'age': _nullableInt(draft.age),
      'gender': draft.gender.trim(),
      'height_cm': draft.heightCm.trim(),
      'height_feet': draft.heightFeet.trim(),
      'height_inches': draft.heightInches.trim(),
      'weight_kg': draft.weightKg.trim(),
      'weight_lb': draft.weightLb.trim(),
      'goal_weight_kg': draft.goalWeightKg.trim(),
      'goal_weight_lb': draft.goalWeightLb.trim(),
      'timezone': draft.timezone.trim(),
      'language': draft.language.trim(),
      'food_preference': draft.foodPreference.trim(),
      'medications': draft.medications.trim(),
      'allergies': draft.allergies.trim(),
      'diagnosis': draft.diagnosis.trim(),
      'surgery_history': draft.surgeryHistory.trim(),
      'family_history': draft.familyHistory.trim(),
      'pregnancy_cycle': draft.pregnancyCycle.trim(),
      'emergency_contact_name': draft.emergencyContactName.trim(),
      'emergency_contact_phone': draft.emergencyContactPhone.trim(),
      'selected_problems': draft.selectedProblems.toList()..sort(),
      'safety_consent_accepted': draft.safetyConsentAccepted,
      'intake_summary': draft.intakeSummary.trim(),
      'intake_completed': draft.intakeCompleted,
      'dashboard_values': _dashboardValues(draft),
      'dashboard_notes': draft.dashboardNotes.take(80).toList(),
      'reminders': _filterUserFacingAiReminders(
        draft.reminders,
      ).take(80).toList(),
      'saved_reminders': draft.savedReminders
          .where(_isUserFacingSavedReminder)
          .map((reminder) => reminder.toJson())
          .toList(),
      'care_tasks': draft.careTasks.map((task) => task.toJson()).toList(),
      'meal_analyses': draft.mealAnalyses
          .map((entry) => entry.toJson())
          .toList(),
      'health_logs': draft.healthLogs.map((entry) => entry.toJson()).toList(),
      'safety_events': draft.safetyEvents
          .map((entry) => entry.toJson())
          .toList(),
      'reports': _filterUserFacingReports(draft.reports).take(80).toList(),
      'chat_history': visibleChatHistory
          .take(160)
          .map((message) => message.toJson())
          .toList(),
      'latest_chat_summary': _recentConversationSummary(visibleChatHistory),
      'call_memories': draft.callMemories
          .take(12)
          .map((memory) => memory.toJson())
          .toList(),
      'latest_call_memory': _recentCallMemorySummary(draft.callMemories),
    };
  }

  Map<String, Object?> _appDataPayload(HealthProfileDraft draft) {
    final visibleChatHistory = _visibleChatHistory(draft);
    return {
      'health_logs': draft.healthLogs.map((entry) => entry.toJson()).toList(),
      'meal_analyses': draft.mealAnalyses
          .map((entry) => entry.toJson())
          .toList(),
      'saved_reminders': draft.savedReminders
          .where(_isUserFacingSavedReminder)
          .map((reminder) => reminder.toJson())
          .toList(),
      'care_tasks': draft.careTasks.map((task) => task.toJson()).toList(),
      'safety_events': draft.safetyEvents
          .map((entry) => entry.toJson())
          .toList(),
      'chat_history': visibleChatHistory
          .take(300)
          .map((message) => message.toJson())
          .toList(),
      'call_memories': draft.callMemories
          .take(20)
          .map((memory) => memory.toJson())
          .toList(),
    };
  }

  int? _nullableInt(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : int.tryParse(trimmed);
  }

  FlickoReportGenerationSnapshot _reportGenerationSnapshot(
    HealthProfileDraft draft,
  ) {
    return FlickoReportGenerationSnapshot(
      problemName: _primaryProblem(draft),
      intakeCompleted: draft.intakeCompleted,
      intakeSummary: draft.intakeSummary,
      syncedReportKeys: draft.syncedReportKeys,
      reportCount: draft.reports.length,
    );
  }

  Future<void> _syncSetupReportIfNeeded(HealthProfileDraft draft) async {
    final request = _reportGenerationCoordinator.setupReportIfNeeded(
      _reportGenerationSnapshot(draft),
    );
    if (request == null) {
      return;
    }
    await _syncProfileReportRequest(draft, request: request);
  }

  Future<HealthReportSyncResult?> _syncProfileReportRequest(
    HealthProfileDraft draft, {
    required FlickoReportGenerationRequest request,
    bool returnResult = false,
    bool throwOnError = false,
  }) async {
    if (draft.authToken.trim().isEmpty ||
        _backendSyncCoolingDown() ||
        !draft.intakeCompleted ||
        draft.intakeSummary.trim().isEmpty) {
      return null;
    }

    final key = request.syncKey.trim();
    if (key.isNotEmpty &&
        (draft.syncedReportKeys.contains(key) ||
            !_syncingReportKeys.add(key))) {
      return null;
    }

    try {
      final result = await _reportApiClient.createIntakeReport(
        token: draft.authToken,
        title: request.title,
        problemName: _primaryProblem(draft),
        intakeSummary: draft.intakeSummary,
        dashboardValues: _dashboardValues(draft),
        reminders: draft.reminders,
        transcript: _visibleChatHistory(draft),
        source: request.source,
        sourcePayload: {
          ..._profilePayload(draft),
          'report_kind': request.kind.name,
          'report_sync_key': key,
        },
      );
      _clearBackendSyncFailure();
      if (!mounted) {
        return result;
      }
      _saveReportResult(result, syncKey: key);
      return returnResult ? result : null;
    } catch (error) {
      _noteBackendSyncFailure('report sync', error);
      if (throwOnError) {
        rethrow;
      }
      return null;
    } finally {
      if (key.isNotEmpty) {
        _syncingReportKeys.remove(key);
      }
    }
  }

  Future<void> _syncCallReportRequest(
    HealthProfileDraft draft,
    HealthCallMemorySummary callMemory,
    FlickoReportGenerationRequest request,
  ) async {
    if (draft.authToken.trim().isEmpty ||
        _backendSyncCoolingDown() ||
        callMemory.memoryContent.isEmpty) {
      return;
    }
    final key = request.syncKey.trim();
    if (key.isNotEmpty &&
        (draft.syncedReportKeys.contains(key) ||
            !_syncingReportKeys.add(key))) {
      return;
    }

    try {
      final result = await _reportApiClient.createIntakeReport(
        token: draft.authToken,
        title: request.title,
        problemName: callMemory.problemName,
        intakeSummary: callMemory.memoryContent,
        dashboardValues: {
          ..._dashboardValues(draft),
          'call_memory': callMemory.toJson(),
        },
        reminders: _reportReminderLines(draft),
        transcript: callMemory.hasTranscript
            ? callMemory.toCoachTranscript()
            : _visibleChatHistory(draft).take(20).toList(),
        transcriptPayload: callMemory.hasTranscript
            ? callMemory.transcript.map((entry) => entry.toJson()).toList()
            : null,
        source: request.source,
        sourcePayload: {
          ...callMemory.toJson(),
          'report_kind': request.kind.name,
          'report_sync_key': key,
        },
        rawTranscriptText: callMemory.fullTranscriptText,
        analyzeConversation: true,
      );
      _clearBackendSyncFailure();
      if (!mounted) {
        return;
      }
      final updatedMemory = callMemory.copyWith(
        reportSyncedAt: DateTime.now().toIso8601String(),
        reportTitle: result.title,
        reportPdfUrl: result.pdfUrl,
        reportHtmlUrl: result.htmlUrl,
      );
      final current = _draftWithReportData(widget.draft, result);
      final nextDraft = current.copyWith(
        callMemories: _mergeCallMemories([
          updatedMemory,
          ...current.callMemories.where((entry) => entry.id != callMemory.id),
        ]),
        reports: _mergeReportLabels([
          _reportLabelFromResult(result),
        ], current.reports).take(8).toList(),
        syncedReportKeys: key.isEmpty
            ? current.syncedReportKeys
            : _mergeUnique([
                key,
                ...current.syncedReportKeys,
              ]).take(30).toList(),
      );
      widget.onDraftChanged(nextDraft);
      unawaited(_ensureSavedRemindersScheduled(nextDraft));
    } catch (error) {
      _noteBackendSyncFailure('call report sync', error);
    } finally {
      if (key.isNotEmpty) {
        _syncingReportKeys.remove(key);
      }
    }
  }

  void _saveReportResult(HealthReportSyncResult result, {String syncKey = ''}) {
    final current = _draftWithReportData(widget.draft, result);
    final reportLabel = _reportLabelFromResult(result);
    final nextDraft = current.copyWith(
      reports: _mergeReportLabels([
        reportLabel,
      ], current.reports).take(8).toList(),
      syncedReportKeys: syncKey.trim().isEmpty
          ? current.syncedReportKeys
          : _mergeUnique([
              syncKey.trim(),
              ...current.syncedReportKeys,
            ]).take(30).toList(),
    );
    widget.onDraftChanged(nextDraft);
    unawaited(_ensureSavedRemindersScheduled(nextDraft));
  }

  HealthProfileDraft _draftWithReportData(
    HealthProfileDraft current,
    HealthReportSyncResult result,
  ) {
    final incomingReminders = result.savedReminders
        .map(FlickoSavedReminder.fromJson)
        .whereType<FlickoSavedReminder>()
        .toList(growable: false);
    final incomingTasks = result.careTasks
        .map(FlickoCareTask.fromJson)
        .whereType<FlickoCareTask>()
        .toList(growable: false);
    final incomingLogs = result.healthLogs
        .map(HealthLogEntry.fromJson)
        .toList(growable: false);
    final incomingSafety = result.safetyEvents
        .map(FlickoSafetyEvent.fromJson)
        .toList(growable: false);

    return current.copyWith(
      intakeSummary: result.intakeSummary.trim().isNotEmpty
          ? result.intakeSummary.trim()
          : current.intakeSummary,
      intakeCompleted: current.intakeCompleted || result.intakeCompleted,
      backendDashboardSummary: {
        ...current.backendDashboardSummary,
        ...result.dashboardValues,
      },
      dashboardNotes: _mergeUnique([
        ...result.dashboardNotes,
        ...current.dashboardNotes,
      ]).take(80).toList(),
      reminders: _filterUserFacingAiReminders(
        _mergeUnique([...result.reminders, ...current.reminders]),
      ).take(80).toList(),
      savedReminders: _mergeSavedReminders([
        ...incomingReminders,
        ...current.savedReminders,
      ]),
      careTasks: _mergeCareTasks([...incomingTasks, ...current.careTasks]),
      healthLogs: _mergeHealthLogs([...incomingLogs, ...current.healthLogs]),
      safetyEvents: _mergeSafetyEvents([
        ...incomingSafety,
        ...current.safetyEvents,
      ]),
    );
  }

  String _reportLabelFromResult(HealthReportSyncResult result) {
    final reportLinks = <String>[
      if (result.pdfUrl.trim().isNotEmpty) 'PDF: ${result.pdfUrl.trim()}',
      if (result.htmlUrl.trim().isNotEmpty) 'HTML: ${result.htmlUrl.trim()}',
      if (result.pdfApiUrl.trim().isNotEmpty)
        'PDF API: ${result.pdfApiUrl.trim()}',
      if (result.htmlApiUrl.trim().isNotEmpty)
        'HTML API: ${result.htmlApiUrl.trim()}',
    ];
    return reportLinks.isEmpty
        ? result.title
        : '${result.title}\n${reportLinks.join('\n')}';
  }

  Future<String> _resolveFreshReportOpenUrl({
    required String title,
    required String url,
    required String apiUrl,
    required bool isPdf,
  }) async {
    final token = widget.draft.authToken.trim();
    final originalUrl = url.trim();
    if (token.isEmpty) {
      return originalUrl;
    }

    final reports = await _reportApiClient.fetchReportHistory(token: token);
    final targetId = _reportIdFromUrl(apiUrl.isNotEmpty ? apiUrl : originalUrl);
    final normalizedTitle = title.trim().toLowerCase();

    HealthReportSyncResult? match;
    if (targetId != null) {
      for (final report in reports) {
        final candidateId = _reportIdFromUrl(
          isPdf
              ? (report.pdfApiUrl.isNotEmpty ? report.pdfApiUrl : report.pdfUrl)
              : (report.htmlApiUrl.isNotEmpty
                    ? report.htmlApiUrl
                    : report.htmlUrl),
        );
        if (candidateId == targetId) {
          match = report;
          break;
        }
      }
    }
    match ??= reports.cast<HealthReportSyncResult?>().firstWhere(
      (report) =>
          report != null &&
          report.title.trim().toLowerCase() == normalizedTitle,
      orElse: () => null,
    );
    if (match == null) {
      return originalUrl;
    }
    final refreshedUrl = isPdf ? match.pdfUrl.trim() : match.htmlUrl.trim();
    return refreshedUrl.isEmpty ? originalUrl : refreshedUrl;
  }

  int? _reportIdFromUrl(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null) {
      return null;
    }
    final segments = uri.pathSegments;
    final reportIndex = segments.indexOf('intake-reports');
    if (reportIndex < 0 || reportIndex + 2 >= segments.length) {
      return null;
    }
    return int.tryParse(segments[reportIndex + 1]);
  }

  List<String> _reportReminderLines(HealthProfileDraft draft) {
    return [
      ...draft.reminders,
      ...draft.savedReminders.map(
        (reminder) => '${reminder.timeLabel} - ${reminder.body}',
      ),
      ...draft.careTasks.map((task) => task.compactSummary),
    ].where((line) => line.trim().isNotEmpty).toList(growable: false);
  }

  Map<String, Object?> _dashboardValues(HealthProfileDraft draft) {
    final primaryProblem = _primaryProblem(draft);
    final config = DashboardProblemResolver.configFor(primaryProblem);
    final insights = DashboardLiveInsights.fromData(
      problemName: config.problemName,
      fallbackScore: config.score,
      fallbackScoreStatus: config.scoreStatus,
      fallbackMetricValue: config.metricValue,
      fallbackMetricUnit: config.metricUnit,
      fallbackMetricStatus: config.metricStatus,
      fallbackPlanFocus: config.planFocus,
      fallbackPlanNote: config.planNote,
      fallbackCheckBody: config.checkBody,
      fallbackReportBody: config.reportBody,
      mealAnalyses: draft.mealAnalyses,
      healthLogs: draft.healthLogs,
      savedReminders: draft.savedReminders,
      careTasks: draft.careTasks,
      backendSummary: draft.backendDashboardSummary,
    );
    return {
      'selected_problems': draft.selectedProblems.toList()..sort(),
      'primary_problem': primaryProblem,
      ...draft.backendDashboardSummary,
      ...insights.toReportValues(),
      'weight': _weightSummary(draft),
      'goal_weight': _goalWeightSummary(draft),
      'height': _heightSummary(draft),
      'age': draft.age,
      'language': draft.language,
      'dashboard_notes': draft.dashboardNotes,
      'active_reminders': draft.reminders,
      'scheduled_reminders': draft.savedReminders
          .map((reminder) => reminder.toJson())
          .toList(),
      'care_tasks': draft.careTasks.map((task) => task.toJson()).toList(),
      'safety_event_count': draft.safetyEvents.isEmpty
          ? _backendSummaryInt(
              draft.backendDashboardSummary,
              'normalized_safety_event_count',
            )
          : draft.safetyEvents.length,
      'safety_events': draft.safetyEvents
          .take(20)
          .map((entry) => entry.toJson())
          .toList(),
      'meal_analyses': draft.mealAnalyses
          .take(20)
          .map((entry) => entry.toJson())
          .toList(),
      'recent_health_logs': draft.healthLogs
          .take(20)
          .map((entry) => entry.toJson())
          .toList(),
      'latest_log_summary': draft.healthLogs.isEmpty
          ? _backendSummaryText(
              draft.backendDashboardSummary,
              'latest_log_summary',
            )
          : _recentHealthLogSummary(draft.healthLogs),
      'latest_meal_summary': draft.mealAnalyses.isEmpty
          ? _backendSummaryText(
              draft.backendDashboardSummary,
              'latest_meal_summary',
            )
          : _recentMealAnalysisSummary(draft.mealAnalyses),
      'latest_safety_summary': draft.safetyEvents.isEmpty
          ? _backendSummaryText(
              draft.backendDashboardSummary,
              'latest_safety_summary',
            )
          : _recentSafetyEventSummary(draft.safetyEvents),
      'recent_call_memory': _recentCallMemorySummary(draft.callMemories),
      'ai_call_invite_log': draft.aiCallInviteLog,
      'call_memories': draft.callMemories
          .take(8)
          .map((memory) => memory.toJson())
          .toList(),
    };
  }

  String _backendSummaryText(Map<String, Object?> summary, String key) {
    return summary[key]?.toString().trim() ?? '';
  }

  bool _backendSummaryBool(Map<String, Object?> summary, String key) {
    final value = summary[key];
    if (value is bool) {
      return value;
    }
    return value?.toString().toLowerCase() == 'true';
  }

  int _backendSummaryInt(Map<String, Object?> summary, String key) {
    final value = summary[key];
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.round();
    }
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  List<Map<String, dynamic>> _backendAiMapList(Object? value) {
    if (value is! List) {
      return const <Map<String, dynamic>>[];
    }
    return value
        .whereType<Map>()
        .map((entry) => Map<String, dynamic>.from(entry))
        .toList(growable: false);
  }

  List<String> _backendAiStringList(Object? value) {
    if (value is! List) {
      return const <String>[];
    }
    return value
        .map((entry) => entry.toString().trim())
        .where((entry) => entry.isNotEmpty)
        .toList(growable: false);
  }

  String _backendAiJson(Object value) {
    try {
      return _backendAiClip(jsonEncode(value), 480);
    } catch (_) {
      return _backendAiClip(value.toString(), 480);
    }
  }

  String _backendAiClip(String value, int maxLength) {
    final clean = value.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (clean.length <= maxLength) {
      return clean;
    }
    return '${clean.substring(0, maxLength - 3).trim()}...';
  }

  String _primaryProblem(HealthProfileDraft draft) {
    final problems = draft.selectedProblems.toList()..sort();
    return problems.isEmpty ? 'General health' : problems.first;
  }

  String _profileSyncKey(HealthProfileDraft draft) {
    return _stableKey(
      jsonEncode({
        'profile': _profilePayload(draft),
        'app_data': _appDataPayload(draft),
      }),
    );
  }

  String _stableKey(String source) {
    var hash = 0;
    for (final codeUnit in source.codeUnits) {
      hash = (hash * 31 + codeUnit) & 0x3fffffff;
    }
    return '$hash-${source.length}';
  }

  List<String> _mergeUnique(List<String> values) {
    final seen = <String>{};
    return values
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty && seen.add(value.toLowerCase()))
        .toList(growable: false);
  }

  List<String> _mergeReportLabels(
    Iterable<String> preferred,
    Iterable<String> fallback,
  ) {
    final seenTexts = <String>{};
    final seenTitles = <String>{};
    final result = <String>[];

    void addAll(Iterable<String> values) {
      for (final value in values) {
        final clean = value.trim();
        if (clean.isEmpty) {
          continue;
        }
        final normalizedText = clean.toLowerCase();
        final titleKey = _reportTitleKey(clean);
        if (!seenTexts.add(normalizedText)) {
          continue;
        }
        if (titleKey.isNotEmpty && !seenTitles.add(titleKey)) {
          continue;
        }
        result.add(clean);
      }
    }

    addAll(preferred);
    addAll(fallback);
    return result;
  }

  String _reportTitleKey(String raw) {
    final firstLine = raw
        .split('\n')
        .map((line) => line.trim())
        .firstWhere((line) => line.isNotEmpty, orElse: () => raw.trim());
    final lower = firstLine.toLowerCase();
    if (lower.startsWith('pdf:') || lower.startsWith('html:')) {
      return '';
    }
    return lower;
  }

  Widget _buildFlowPage(int index) {
    switch (index) {
      case 0:
        return WelcomeScreen(onStart: _next);
      case 1:
        return DemoScreen(onNext: _next, onBack: _previous);
      case 2:
        return MealAnalyzerDemoScreen(onNext: _next, onBack: _previous);
      case 3:
        return AuthAccessScreen(
          onAuthenticated: _handleAuthenticatedResult,
          onBack: _previous,
        );
      case 4:
        return ProblemSelectionScreen(
          draft: widget.draft,
          onChanged: (draft) {
            widget.onDraftChanged(draft);
            unawaited(_syncProfileIfAuthenticated(draft));
          },
          onNext: _editingProfileFromDashboard
              ? () => _goToDashboard(widget.draft)
              : _next,
          onBack: _editingProfileFromDashboard
              ? () => _goToDashboard(widget.draft)
              : _previous,
          stepLabel: _editingProfileFromDashboard
              ? 'Profile edit'
              : 'Step 5 of 7',
          title: _editingProfileFromDashboard
              ? 'Edit your health problems.'
              : 'Select your problems.',
          subtitle: _editingProfileFromDashboard
              ? 'Update the problems Flicko uses for coaching, reminders, reports, and safety matching.'
              : 'Saved problems drive the AI call, dashboard, reminders, reports, and protocol matching.',
          primaryActionLabel: _editingProfileFromDashboard
              ? 'Save problems'
              : 'Continue to login',
          showFlowDots: !_editingProfileFromDashboard,
        );
      case 5:
        return ProfileSetupScreen(
          draft: widget.draft,
          onBack: _leaveProfile,
          onSaved: (draft) {
            widget.onDraftChanged(draft);
            unawaited(_syncProfileIfAuthenticated(draft));
            _openConsentOrDashboard(draft);
          },
        );
      case 6:
        return ConsentSafetyScreen(
          onAccepted: _acceptSafetyConsent,
          onBack: _previous,
        );
      case 7:
        return ProblemDashboardScreen(
          profile: DashboardUserProfile(
            firstName: widget.draft.givenName,
            fullName: widget.draft.displayName,
            phone: widget.draft.phone,
            email: widget.draft.email,
            emergencyContactName: widget.draft.emergencyContactName,
            emergencyContactPhone: widget.draft.emergencyContactPhone,
            age: widget.draft.age,
            heightCm: widget.draft.heightCm,
            heightFeet: widget.draft.heightFeet,
            heightInches: widget.draft.heightInches,
            weightKg: widget.draft.weightKg,
            weightLb: widget.draft.weightLb,
            foodPreference: widget.draft.foodPreference,
            profileContext: _buildProfileContext(widget.draft),
            shouldShowBmiIntro: !widget.draft.bmiIntroSeen,
            onBmiIntroShown: () {
              if (widget.draft.bmiIntroSeen) {
                return;
              }
              widget.onDraftChanged(widget.draft.copyWith(bmiIntroSeen: true));
            },
            chatHistory: _visibleChatHistory(widget.draft),
            onChatHistoryChanged: _handleChatHistoryChanged,
            intakeSummary: widget.draft.intakeSummary,
            intakeCompleted: widget.draft.intakeCompleted,
            hasCompletedAiSetupCall: _hasCompletedAiSetupSignal(widget.draft),
            dashboardNotes: widget.draft.dashboardNotes,
            reminders: widget.draft.reminders,
            reports: widget.draft.reports,
            backendDashboardSummary: widget.draft.backendDashboardSummary,
            healthLogs: widget.draft.healthLogs,
            mealAnalyses: widget.draft.mealAnalyses,
            safetyEvents: widget.draft.safetyEvents,
            savedReminders: widget.draft.savedReminders,
            careTasks: widget.draft.careTasks,
            onAddHealthLog: _handleHealthLogAdded,
            onSaveMealAnalysis: _handleMealAnalysisAdded,
            onSafetyEvent: _handleSafetyEventAdded,
            onSendReminderNotification: _handleReminderNotification,
            onSaveReminder: _handleSavedReminderUpsert,
            onDeleteReminder: _handleSavedReminderDelete,
            onSaveCareTask: _handleCareTaskUpsert,
            onDeleteCareTask: _handleCareTaskDelete,
            onCreateReport: _handleCreateDashboardReport,
            onMedicalReportExtracted: _handleMedicalReportExtracted,
            onCallCompleted: _handleAiCallCompleted,
            onFetchBackendAiContext: _fetchBackendAiContext,
            onResolveReportOpenUrl: _resolveFreshReportOpenUrl,
            selectedProblems: widget.draft.selectedProblems,
            onEditProfile: _openProfileFromDashboard,
            onEditProblems: _openProblemSelectionFromDashboard,
            onLogout: _logoutFromDashboard,
            onRefresh: () => _prepareDashboardData(widget.draft),
            bmiSnapshot: BmiSnapshot.fromProfileMetrics(
              weightKg: widget.draft.weightKg,
              weightLb: widget.draft.weightLb,
              heightCm: widget.draft.heightCm,
              heightFeet: widget.draft.heightFeet,
              heightInches: widget.draft.heightInches,
              age: widget.draft.age,
            ),
          ),
        );
      default:
        return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<Object?>(
      canPop:
          _page == 0 ||
          (_page == _lastPage && _shouldOpenDashboardEntry(widget.draft)),
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _page > 0) {
          if (_page == _lastPage && _shouldOpenDashboardEntry(widget.draft)) {
            return;
          }
          if (_page == 5 && _editingProfileFromDashboard) {
            _goToDashboard();
          } else {
            _previous();
          }
        }
      },
      child: AbsorbPointer(
        absorbing: _pageAnimating,
        child: PageView.builder(
          controller: _controller,
          itemCount: _lastPage + 1,
          physics: const NeverScrollableScrollPhysics(),
          onPageChanged: (value) => setState(() => _page = value),
          itemBuilder: (context, index) => _buildFlowPage(index),
          allowImplicitScrolling: true,
        ),
      ),
    );
  }
}

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key, required this.onStart});

  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        color: const Color(0xFFFAFCF8),
        child: Stack(
          children: [
            const Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: 500,
              child: WelcomeImageHero(),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: 270,
              height: 270,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFFFAFCF8).withValues(alpha: 0),
                      const Color(0xFFFAFCF8).withValues(alpha: 0.42),
                      const Color(0xFFFAFCF8).withValues(alpha: 0.94),
                      const Color(0xFFFAFCF8),
                    ],
                    stops: const [0, 0.24, 0.62, 1],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
            ),
            Positioned(
              left: 12,
              right: 12,
              bottom: 92,
              height: 260,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(34),
                    gradient: LinearGradient(
                      colors: [
                        Colors.white.withValues(alpha: 0),
                        Colors.white.withValues(alpha: 0.82),
                        Colors.white.withValues(alpha: 0.98),
                      ],
                      stops: const [0, 0.34, 1],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.white.withValues(alpha: 0.92),
                        blurRadius: 52,
                        spreadRadius: 18,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 4, 22, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const PageCornerLogo(compact: true),
                    const Spacer(flex: 7),
                    Text(
                      'Health help that feels personal.',
                      style: Theme.of(context).textTheme.headlineLarge
                          ?.copyWith(
                            fontSize: 32,
                            height: 1.08,
                            fontFamily: 'serif',
                            fontFamilyFallback: const ['Georgia', 'Roboto'],
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF10231D),
                            letterSpacing: 0,
                          ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Chat, reminders, food checks, and reports shaped around your daily routine.',
                      style: TextStyle(
                        color: Color(0xFF51625C),
                        fontSize: 15,
                        height: 1.44,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const WelcomeBullet(
                      icon: Icons.psychology_alt_rounded,
                      text: 'AI remembers your goals, routine, and problems.',
                    ),
                    const SizedBox(height: 8),
                    const WelcomeBullet(
                      icon: Icons.restaurant_menu_rounded,
                      text: 'Meal photo checks with simple food scoring.',
                    ),
                    const SizedBox(height: 8),
                    const WelcomeBullet(
                      icon: Icons.picture_as_pdf_rounded,
                      text: 'Clean PDF reports for progress and doctor visits.',
                    ),
                    const Spacer(flex: 2),
                    const FlowDots(activeIndex: 0, count: 7),
                    const SizedBox(height: 12),
                    PrimaryButton(
                      label: 'Start your health plan',
                      icon: Icons.arrow_forward_rounded,
                      onPressed: onStart,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PageCornerLogo extends StatelessWidget {
  const PageCornerLogo({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Image.asset(
        'assets/images/mainlogo.png',
        width: compact ? 88 : 96,
        height: compact ? 40 : 44,
        fit: BoxFit.contain,
      ),
    );
  }
}

class WelcomeBullet extends StatelessWidget {
  const WelcomeBullet({super.key, required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              colors: [Color(0xFF21B497), Color(0xFF0D7567)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: FlickoTheme.teal.withValues(alpha: 0.20),
                blurRadius: 14,
                offset: const Offset(0, 7),
              ),
            ],
          ),
          child: Icon(icon, size: 15, color: Colors.white),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: Color(0xFF23342F),
              fontSize: 13.5,
              height: 1.28,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}

class DemoScreen extends StatelessWidget {
  const DemoScreen({super.key, required this.onNext, required this.onBack});

  final VoidCallback onNext;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFEAF3F0), FlickoTheme.background],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppBackButton(label: 'Back', onPressed: onBack),
                const SizedBox(height: 8),
                const Expanded(child: Center(child: DemoCallImage())),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    'Live AI health call',
                    style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                      fontSize: 27,
                      height: 1.06,
                      fontFamily: 'serif',
                      fontFamilyFallback: const ['Georgia', 'Roboto'],
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF10231D),
                      letterSpacing: 0,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    'Flicko listens like a health coach, asks follow-up questions, and saves the call summary for your plan.',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Color(0xFF51625C),
                      fontSize: 13.5,
                      height: 1.34,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                PrimaryButton(
                  label: 'Next',
                  icon: Icons.arrow_forward_rounded,
                  onPressed: onNext,
                ),
                const SizedBox(height: 10),
                const FlowDots(activeIndex: 1, count: 7),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class DemoCallImage extends StatelessWidget {
  const DemoCallImage({super.key});

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 9 / 16,
      child: Image.asset(
        'assets/images/demo_call.png',
        fit: BoxFit.contain,
        alignment: Alignment.center,
      ),
    );
  }
}

class MealAnalyzerDemoScreen extends StatelessWidget {
  const MealAnalyzerDemoScreen({
    super.key,
    required this.onNext,
    required this.onBack,
  });

  final VoidCallback onNext;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFEAF3F0), FlickoTheme.background],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppBackButton(label: 'Back', onPressed: onBack),
                const SizedBox(height: 8),
                const Expanded(child: Center(child: MealAnalyzerImage())),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    'Meal photo analysis',
                    style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                      fontSize: 27,
                      height: 1.06,
                      fontFamily: 'serif',
                      fontFamilyFallback: const ['Georgia', 'Roboto'],
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF10231D),
                      letterSpacing: 0,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    'Upload a meal photo. Flicko scores the plate, finds protein, carbs, fiber, calories, and suggests a better choice.',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Color(0xFF51625C),
                      fontSize: 13.5,
                      height: 1.34,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                PrimaryButton(
                  label: 'Next',
                  icon: Icons.arrow_forward_rounded,
                  onPressed: onNext,
                ),
                const SizedBox(height: 10),
                const FlowDots(activeIndex: 2, count: 7),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class MealAnalyzerImage extends StatelessWidget {
  const MealAnalyzerImage({super.key});

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 9 / 16,
      child: Image.asset(
        'assets/images/demo_meal.png',
        fit: BoxFit.contain,
        alignment: Alignment.center,
      ),
    );
  }
}

class HealthProblemOption {
  const HealthProblemOption({
    required this.title,
    required this.subtitle,
    required this.asset,
    required this.icon,
    required this.tint,
    required this.accent,
    this.cutout = true,
  });

  final String title;
  final String subtitle;
  final String asset;
  final IconData icon;
  final Color tint;
  final Color accent;
  final bool cutout;
}

class ProblemSelectionScreen extends StatefulWidget {
  const ProblemSelectionScreen({
    super.key,
    required this.draft,
    required this.onChanged,
    required this.onNext,
    required this.onBack,
    this.stepLabel = 'Step 5 of 7',
    this.title = 'Select your problems.',
    this.subtitle =
        'Saved problems drive the AI call, dashboard, reminders, reports, and protocol matching.',
    this.primaryActionLabel = 'Continue to login',
    this.showFlowDots = true,
  });

  final HealthProfileDraft draft;
  final ValueChanged<HealthProfileDraft> onChanged;
  final VoidCallback onNext;
  final VoidCallback onBack;
  final String stepLabel;
  final String title;
  final String subtitle;
  final String primaryActionLabel;
  final bool showFlowDots;

  @override
  State<ProblemSelectionScreen> createState() => _ProblemSelectionScreenState();
}

class _ProblemSelectionScreenState extends State<ProblemSelectionScreen> {
  static const problemOptions = <HealthProblemOption>[
    HealthProblemOption(
      title: 'Weight management',
      subtitle: 'Meal plan, calorie target, weekly progress',
      asset: 'assets/images/problems/weight_management.png',
      icon: Icons.monitor_weight_outlined,
      tint: Color(0xFFEAF8EF),
      accent: Color(0xFF159A65),
    ),
    HealthProblemOption(
      title: 'Diabetes Type 1',
      subtitle: 'Meal timing, glucose logs, warning support',
      asset: 'assets/images/problems/diabetes_type_1.png',
      icon: Icons.bloodtype_outlined,
      tint: Color(0xFFEAF5FF),
      accent: Color(0xFF1877C9),
    ),
    HealthProblemOption(
      title: 'Diabetes Type 2',
      subtitle: 'Low-glycemic food, walking, HbA1c progress',
      asset: 'assets/images/problems/diabetes_type_2.png',
      icon: Icons.insights_rounded,
      tint: Color(0xFFE8FAF1),
      accent: Color(0xFF11915D),
    ),
    HealthProblemOption(
      title: 'Blood pressure',
      subtitle: 'Sodium guidance, BP logs, exercise caution',
      asset: 'assets/images/problems/blood_pressure.jpg',
      icon: Icons.speed_rounded,
      tint: Color(0xFFFFEEF1),
      accent: Color(0xFFD94258),
      cutout: false,
    ),
    HealthProblemOption(
      title: 'Heart health',
      subtitle: 'Cholesterol-friendly food and risk warnings',
      asset: 'assets/images/problems/heart_health.jpg',
      icon: Icons.favorite_border_rounded,
      tint: Color(0xFFFFF0F4),
      accent: Color(0xFFC73357),
      cutout: false,
    ),
    HealthProblemOption(
      title: 'PCOS/PCOD',
      subtitle: 'Cycle-aware diet and insulin support',
      asset: 'assets/images/problems/pcos_pcod.png',
      icon: Icons.woman_rounded,
      tint: Color(0xFFF5ECFF),
      accent: Color(0xFF7A4FD6),
    ),
    HealthProblemOption(
      title: 'Thyroid',
      subtitle: 'Routine, medication timing note, energy tracking',
      asset: 'assets/images/problems/thyroid.png',
      icon: Icons.bolt_rounded,
      tint: Color(0xFFEAF8FF),
      accent: Color(0xFF1588A0),
    ),
    HealthProblemOption(
      title: 'Pregnancy',
      subtitle: 'Trimester nutrition and safety warnings',
      asset: 'assets/images/problems/pregnancy.jpg',
      icon: Icons.pregnant_woman_rounded,
      tint: Color(0xFFFFF1E7),
      accent: Color(0xFFD8782D),
      cutout: false,
    ),
    HealthProblemOption(
      title: 'Preconception',
      subtitle: 'Fertility-support lifestyle and cycle tracking',
      asset: 'assets/images/problems/preconception.png',
      icon: Icons.spa_outlined,
      tint: Color(0xFFF0F9EC),
      accent: Color(0xFF5B9D26),
    ),
    HealthProblemOption(
      title: 'Postpartum',
      subtitle: 'Recovery, nutrition, mood and sleep support',
      asset: 'assets/images/problems/postpartum.png',
      icon: Icons.child_friendly_rounded,
      tint: Color(0xFFFFF0F7),
      accent: Color(0xFFC84E8A),
    ),
    HealthProblemOption(
      title: 'Digestive health',
      subtitle: 'Acidity, bloating and food trigger tracking',
      asset: 'assets/images/problems/digestive_health.jpg',
      icon: Icons.restaurant_menu_rounded,
      tint: Color(0xFFF4F9E8),
      accent: Color(0xFF8BA61D),
      cutout: false,
    ),
    HealthProblemOption(
      title: 'Sleep health',
      subtitle: 'Sleep routine, caffeine timing, wind-down plan',
      asset: 'assets/images/problems/sleep_health.png',
      icon: Icons.bedtime_outlined,
      tint: Color(0xFFEFF3FF),
      accent: Color(0xFF5367C6),
    ),
    HealthProblemOption(
      title: 'Stress and mood',
      subtitle: 'Check-ins, breathing, journaling, escalation',
      asset: 'assets/images/problems/stress_mood.png',
      icon: Icons.self_improvement_rounded,
      tint: Color(0xFFEEF8F6),
      accent: Color(0xFF22897B),
    ),
    HealthProblemOption(
      title: 'Fitness',
      subtitle: 'Beginner strength and cardio schedule',
      asset: 'assets/images/problems/fitness.png',
      icon: Icons.fitness_center_rounded,
      tint: Color(0xFFEAF9FF),
      accent: Color(0xFF167DA5),
    ),
    HealthProblemOption(
      title: 'Skin and hair',
      subtitle: 'Nutrition, hydration and trigger tracking',
      asset: 'assets/images/problems/skin_hair.png',
      icon: Icons.face_retouching_natural,
      tint: Color(0xFFFFF4E7),
      accent: Color(0xFFC9842E),
    ),
    HealthProblemOption(
      title: 'General wellness',
      subtitle: 'Habits, hydration, movement and sleep',
      asset: 'assets/images/problems/general_wellness.jpg',
      icon: Icons.eco_outlined,
      tint: Color(0xFFEBFAF4),
      accent: Color(0xFF139B6E),
      cutout: false,
    ),
    HealthProblemOption(
      title: "Women's wellness",
      subtitle: 'Cycle, cramps, nutrition and energy tracking',
      asset: 'assets/images/problems/womens_wellness.png',
      icon: Icons.female_rounded,
      tint: Color(0xFFFFF0FA),
      accent: Color(0xFFAD4E9D),
    ),
    HealthProblemOption(
      title: 'Senior care',
      subtitle: 'Medication reminders, mobility, safety check-ins',
      asset: 'assets/images/problems/senior_care.png',
      icon: Icons.elderly_rounded,
      tint: Color(0xFFF0F7FF),
      accent: Color(0xFF456F9B),
    ),
    HealthProblemOption(
      title: 'Sexual health',
      subtitle: 'Private coaching with doctor referral boundaries',
      asset: 'assets/images/problems/sexual_health.png',
      icon: Icons.lock_outline_rounded,
      tint: Color(0xFFF8F1FF),
      accent: Color(0xFF7953B8),
    ),
    HealthProblemOption(
      title: 'Autoimmune support',
      subtitle: 'Flare, food, sleep and stress pattern tracking',
      asset: 'assets/images/problems/autoimmune_support.png',
      icon: Icons.shield_outlined,
      tint: Color(0xFFF1FBF8),
      accent: Color(0xFF2A8B75),
    ),
    HealthProblemOption(
      title: 'Acidity and bloating',
      subtitle: 'Trigger food, meal timing and gut routine',
      asset: 'assets/images/problems/acidity_bloating.png',
      icon: Icons.local_fire_department_outlined,
      tint: Color(0xFFFFF7E7),
      accent: Color(0xFFB88716),
    ),
    HealthProblemOption(
      title: 'Cholesterol',
      subtitle: 'Heart-friendly food, oil guidance and activity',
      asset: 'assets/images/problems/cholesterol.png',
      icon: Icons.water_drop_outlined,
      tint: Color(0xFFEFF9E8),
      accent: Color(0xFF609C2A),
    ),
    HealthProblemOption(
      title: 'Habit reset',
      subtitle: 'Cravings, late-night eating, travel recovery',
      asset: 'assets/images/problems/habit_reset.png',
      icon: Icons.restart_alt_rounded,
      tint: Color(0xFFF2F4FF),
      accent: Color(0xFF5B6EC6),
    ),
  ];

  static const otherOption = HealthProblemOption(
    title: 'Other problem',
    subtitle: 'Type any condition or personal health goal',
    asset: 'assets/images/problems/other_problem.png',
    icon: Icons.add_rounded,
    tint: Color(0xFFF2F7F4),
    accent: Color(0xFF58776A),
  );

  late final TextEditingController _otherProblem;
  bool _showOtherInput = false;

  Set<String> get _knownProblemTitles =>
      problemOptions.map((problem) => problem.title).toSet();

  @override
  void initState() {
    super.initState();
    _otherProblem = TextEditingController();
  }

  @override
  void dispose() {
    _otherProblem.dispose();
    super.dispose();
  }

  void _toggleProblem(String problem) {
    final next = Set<String>.from(widget.draft.selectedProblems);
    if (!next.add(problem)) {
      next.remove(problem);
    }
    widget.onChanged(widget.draft.copyWith(selectedProblems: next));
  }

  void _addOtherProblem() {
    final value = _otherProblem.text.trim();
    if (value.isEmpty) {
      return;
    }
    final next = Set<String>.from(widget.draft.selectedProblems)..add(value);
    widget.onChanged(widget.draft.copyWith(selectedProblems: next));
    _otherProblem.clear();
    setState(() => _showOtherInput = false);
  }

  void _toggleOtherProblem(List<String> customProblems) {
    if (_showOtherInput || customProblems.isNotEmpty) {
      final next = Set<String>.from(widget.draft.selectedProblems)
        ..removeWhere((problem) => !_knownProblemTitles.contains(problem));
      _otherProblem.clear();
      widget.onChanged(widget.draft.copyWith(selectedProblems: next));
      setState(() => _showOtherInput = false);
      return;
    }

    setState(() => _showOtherInput = true);
  }

  @override
  Widget build(BuildContext context) {
    final selected = widget.draft.selectedProblems;
    final customProblems =
        selected
            .where((problem) => !_knownProblemTitles.contains(problem))
            .toList()
          ..sort();

    return AppPage(
      onBack: widget.onBack,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionLabel(widget.stepLabel),
          const SizedBox(height: 8),
          Text(widget.title, style: Theme.of(context).textTheme.headlineLarge),
          const SizedBox(height: 10),
          Text(widget.subtitle, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 14),
          Row(
            children: const [
              ProgramCountBadge(text: '23 programs'),
              SizedBox(width: 8),
              ProgramCountBadge(text: 'Multi-select'),
              SizedBox(width: 8),
              ProgramCountBadge(text: 'Custom problem'),
            ],
          ),
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth > 560 ? 3 : 2;
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: problemOptions.length + 1,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: columns == 3 ? 0.82 : 0.72,
                ),
                itemBuilder: (context, index) {
                  if (index == problemOptions.length) {
                    return ProblemProgramCard(
                      option: otherOption,
                      selected: _showOtherInput || customProblems.isNotEmpty,
                      onTap: () => _toggleOtherProblem(customProblems),
                    );
                  }
                  final option = problemOptions[index];
                  return ProblemProgramCard(
                    option: option,
                    selected: selected.contains(option.title),
                    onTap: () => _toggleProblem(option.title),
                  );
                },
              );
            },
          ),
          if (_showOtherInput) ...[
            const SizedBox(height: 14),
            OtherProblemInput(
              controller: _otherProblem,
              onAdd: _addOtherProblem,
            ),
          ],
          if (customProblems.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              'Your added problems',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final problem in customProblems)
                  SelectedProblemPill(
                    label: problem,
                    onRemove: () => _toggleProblem(problem),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 18),
          const SafetyNotice(
            text:
                'This app coaches and tracks health habits. Emergency symptoms require medical care, not AI coaching.',
          ),
          const SizedBox(height: 18),
          PrimaryButton(
            label: selected.isEmpty
                ? 'Select at least one'
                : widget.primaryActionLabel,
            onPressed: selected.isEmpty ? null : widget.onNext,
          ),
          const SizedBox(height: 10),
          SecondaryButton(
            label: 'Use starter goals',
            onPressed: () {
              widget.onChanged(
                widget.draft.copyWith(
                  selectedProblems: {
                    'Weight management',
                    'Diabetes Type 2',
                    'Sleep health',
                  },
                ),
              );
            },
          ),
          if (widget.showFlowDots) ...[
            const SizedBox(height: 18),
            const FlowDots(activeIndex: 4, count: 7),
          ],
        ],
      ),
    );
  }
}

class ProgramCountBadge extends StatelessWidget {
  const ProgramCountBadge({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Flexible(
      child: Container(
        constraints: const BoxConstraints(minHeight: 30),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.74),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white.withValues(alpha: 0.90)),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0F2A25).withValues(alpha: 0.06),
              blurRadius: 14,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: FlickoTheme.tealDark,
            fontSize: 11.5,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class ProblemProgramCard extends StatelessWidget {
  const ProblemProgramCard({
    super.key,
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final HealthProblemOption option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final problemImage = Image.asset(
      option.asset,
      fit: option.cutout ? BoxFit.contain : BoxFit.cover,
      errorBuilder: (context, error, stackTrace) {
        return DecoratedBox(decoration: BoxDecoration(color: option.tint));
      },
    );

    return Semantics(
      button: true,
      selected: selected,
      label: option.title,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: selected ? 0.98 : 0.86),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected
                  ? option.accent.withValues(alpha: 0.88)
                  : Colors.white.withValues(alpha: 0.92),
              width: selected ? 1.6 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: selected
                    ? option.accent.withValues(alpha: 0.18)
                    : const Color(0xFF18352E).withValues(alpha: 0.08),
                blurRadius: selected ? 22 : 16,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 7,
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(17),
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              option.tint.withValues(alpha: 0.96),
                              Colors.white.withValues(alpha: 0.74),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                      ),
                      if (option.cutout)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(10, 12, 10, 8),
                          child: problemImage,
                        )
                      else
                        problemImage,
                      if (!option.cutout)
                        DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.black.withValues(alpha: 0),
                                Colors.black.withValues(alpha: 0.10),
                              ],
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                            ),
                          ),
                        ),
                      Positioned(
                        left: 10,
                        top: 10,
                        child: Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.84),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: option.accent.withValues(alpha: 0.16),
                                blurRadius: 12,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: Icon(
                            option.icon,
                            color: option.accent,
                            size: 19,
                          ),
                        ),
                      ),
                      if (selected)
                        Positioned(
                          right: 10,
                          top: 10,
                          child: Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: option.accent,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.check_rounded,
                              color: Colors.white,
                              size: 18,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Expanded(
                flex: 6,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(11, 9, 11, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        option.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: selected ? option.accent : FlickoTheme.ink,
                          fontSize: 13.4,
                          height: 1.08,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Expanded(
                        child: Text(
                          option.subtitle,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: FlickoTheme.muted,
                            fontSize: 11.2,
                            height: 1.24,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class OtherProblemInput extends StatelessWidget {
  const OtherProblemInput({
    super.key,
    required this.controller,
    required this.onAdd,
  });

  final TextEditingController controller;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.white.withValues(alpha: 0.96),
            FlickoTheme.mint.withValues(alpha: 0.72),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.94)),
        boxShadow: [
          BoxShadow(
            color: FlickoTheme.teal.withValues(alpha: 0.10),
            blurRadius: 24,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 360;
          final input = TextField(
            controller: controller,
            textInputAction: TextInputAction.done,
            textCapitalization: TextCapitalization.words,
            onSubmitted: (_) => onAdd(),
            decoration: InputDecoration(
              labelText: 'Custom problem',
              hintText: 'Migraine, back pain, anemia...',
              prefixIcon: const Icon(
                Icons.edit_note_rounded,
                color: FlickoTheme.teal,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 16,
              ),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.90),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide(
                  color: FlickoTheme.teal.withValues(alpha: 0.14),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide(
                  color: FlickoTheme.teal.withValues(alpha: 0.14),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: const BorderSide(
                  color: FlickoTheme.teal,
                  width: 1.4,
                ),
              ),
            ),
          );

          final addButton = SizedBox(
            width: compact ? double.infinity : 104,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(54),
                backgroundColor: FlickoTheme.teal,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                textStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
              onPressed: onAdd,
              icon: const Icon(Icons.add_rounded, size: 20),
              label: const Text('Add'),
            ),
          );

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.90),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: FlickoTheme.teal.withValues(alpha: 0.12),
                          blurRadius: 14,
                          offset: const Offset(0, 7),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.add_circle_outline_rounded,
                      color: FlickoTheme.teal,
                      size: 21,
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Add a custom health problem',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 3),
                        const Text(
                          'Flicko will save it with your selected programs and personalize the AI plan around it.',
                          style: TextStyle(
                            color: FlickoTheme.muted,
                            fontSize: 12.5,
                            height: 1.35,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 13),
              if (compact) ...[
                input,
                const SizedBox(height: 10),
                addButton,
              ] else
                Row(
                  children: [
                    Expanded(child: input),
                    const SizedBox(width: 10),
                    addButton,
                  ],
                ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: const [
                  OtherProblemHint(text: 'Migraine'),
                  OtherProblemHint(text: 'Back pain'),
                  OtherProblemHint(text: 'Anemia'),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class OtherProblemHint extends StatelessWidget {
  const OtherProblemHint({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: FlickoTheme.teal.withValues(alpha: 0.10)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: FlickoTheme.tealDark,
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class SelectedProblemPill extends StatelessWidget {
  const SelectedProblemPill({
    super.key,
    required this.label,
    required this.onRemove,
  });

  final String label;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 36),
      padding: const EdgeInsets.fromLTRB(11, 7, 7, 7),
      decoration: BoxDecoration(
        color: FlickoTheme.mint,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: FlickoTheme.teal.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: FlickoTheme.tealDark,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 5),
          InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: onRemove,
            child: const Icon(
              Icons.close_rounded,
              color: FlickoTheme.tealDark,
              size: 17,
            ),
          ),
        ],
      ),
    );
  }
}

enum AuthMode { login, register, forgot }

enum AuthStep { form, registerOtp, resetPassword }

class AuthAccessScreen extends StatefulWidget {
  const AuthAccessScreen({
    super.key,
    required this.onAuthenticated,
    required this.onBack,
    this.apiClient = const AuthApiClient(),
  });

  final FutureOr<void> Function(AuthResult result) onAuthenticated;
  final VoidCallback onBack;
  final AuthApiClient apiClient;

  @override
  State<AuthAccessScreen> createState() => _AuthAccessScreenState();
}

class _AuthAccessScreenState extends State<AuthAccessScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _otp = TextEditingController();
  final _newPassword = TextEditingController();
  AuthMode _mode = AuthMode.login;
  AuthStep _step = AuthStep.form;
  bool _loading = false;
  String? _statusMessage;
  String? _errorMessage;
  final FlickoGoogleSignInService _googleSignIn = FlickoGoogleSignInService();

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _password.dispose();
    _otp.dispose();
    _newPassword.dispose();
    super.dispose();
  }

  String get _title {
    return switch (_mode) {
      AuthMode.login => 'Login to Flicko.',
      AuthMode.register => 'Create your account.',
      AuthMode.forgot => 'Recover password.',
    };
  }

  String get _body {
    return switch (_mode) {
      AuthMode.login =>
        'Secure your health setup before building your local profile.',
      AuthMode.register =>
        'Register now, then complete the profile used by AI coaching.',
      AuthMode.forgot =>
        'Enter your email and we will prepare the reset flow for Django.',
    };
  }

  void _setMode(AuthMode mode) {
    setState(() {
      _mode = mode;
      _step = AuthStep.form;
      _statusMessage = null;
      _errorMessage = null;
      _otp.clear();
      _newPassword.clear();
    });
  }

  Future<void> _runAuth(Future<void> Function() action) async {
    setState(() {
      _loading = true;
      _errorMessage = null;
      _statusMessage = null;
    });
    try {
      await action();
    } on AuthApiException catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = error.message);
    } on FlickoGoogleSignInException catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = error.message);
    } on Object catch (error) {
      if (!mounted) return;
      setState(
        () => _errorMessage = 'Authentication failed. ${error.toString()}',
      );
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_mode == AuthMode.login) {
      await _runAuth(() async {
        final result = await widget.apiClient.login(
          email: _email.text.trim(),
          password: _password.text,
        );
        if (!mounted) {
          return;
        }
        setState(() => _statusMessage = 'Syncing your Flicko account...');
        await widget.onAuthenticated(result);
      });
      return;
    }

    if (_mode == AuthMode.register) {
      await _runAuth(() async {
        await widget.apiClient.registerStart(
          name: _name.text.trim(),
          email: _email.text.trim(),
          mobile: _phone.text.trim(),
          password: _password.text,
        );
        if (!mounted) return;
        setState(() {
          _step = AuthStep.registerOtp;
          _statusMessage = 'OTP sent to ${_email.text.trim()}.';
        });
      });
      return;
    }

    await _runAuth(() async {
      await widget.apiClient.forgotPasswordStart(email: _email.text.trim());
      if (!mounted) return;
      setState(() {
        _step = AuthStep.resetPassword;
        _statusMessage = 'OTP sent if this email exists.';
      });
    });
  }

  Future<void> _verifyRegistrationOtp() async {
    if (_otp.text.trim().length < 4) {
      setState(() => _errorMessage = 'Enter the OTP from email.');
      return;
    }
    await _runAuth(() async {
      final result = await widget.apiClient.registerVerify(
        email: _email.text.trim(),
        otp: _otp.text.trim(),
      );
      if (!mounted) {
        return;
      }
      setState(() => _statusMessage = 'Syncing your Flicko account...');
      await widget.onAuthenticated(result);
    });
  }

  Future<void> _resetPassword() async {
    if (_otp.text.trim().length < 4 || _newPassword.text.trim().length < 6) {
      setState(() => _errorMessage = 'Enter OTP and a 6+ character password.');
      return;
    }
    await _runAuth(() async {
      await widget.apiClient.resetPassword(
        email: _email.text.trim(),
        otp: _otp.text.trim(),
        newPassword: _newPassword.text,
      );
      if (!mounted) return;
      setState(() {
        _mode = AuthMode.login;
        _step = AuthStep.form;
        _password.clear();
        _otp.clear();
        _newPassword.clear();
        _statusMessage = 'Password reset complete. Login with new password.';
      });
    });
  }

  Future<void> _continueWithGoogle() async {
    if (_loading) {
      return;
    }
    await _runAuth(() async {
      final google = await _googleSignIn.signIn();
      final result = await widget.apiClient.googleLogin(
        idToken: google.idToken,
        email: google.email,
        name: google.displayName,
        photoUrl: google.photoUrl,
      );
      if (!mounted) {
        return;
      }
      setState(() => _statusMessage = 'Syncing your Flicko account...');
      await widget.onAuthenticated(result);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AppPage(
      onBack: widget.onBack,
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionLabel('Step 4 of 7'),
            const SizedBox(height: 8),
            Text(_title, style: Theme.of(context).textTheme.headlineLarge),
            const SizedBox(height: 10),
            Text(_body, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 18),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFFFFFF), Color(0xFFE8F8F1)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(26),
                border: Border.all(color: Colors.white.withValues(alpha: 0.92)),
                boxShadow: [
                  BoxShadow(
                    color: FlickoTheme.teal.withValues(alpha: 0.11),
                    blurRadius: 30,
                    offset: const Offset(0, 18),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          color: FlickoTheme.teal,
                          borderRadius: BorderRadius.circular(17),
                          boxShadow: [
                            BoxShadow(
                              color: FlickoTheme.teal.withValues(alpha: 0.22),
                              blurRadius: 16,
                              offset: const Offset(0, 9),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.health_and_safety_outlined,
                          color: Colors.white,
                          size: 23,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Secure health access',
                              style: TextStyle(
                                color: FlickoTheme.ink,
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            SizedBox(height: 3),
                            Text(
                              'Login, register, Google, or password recovery.',
                              style: TextStyle(
                                color: FlickoTheme.muted,
                                fontSize: 12.5,
                                height: 1.3,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (_step == AuthStep.form) ...[
                    AuthModeSelector(mode: _mode, onChanged: _setMode),
                    const SizedBox(height: 16),
                    if (_mode == AuthMode.register) ...[
                      AppTextField(
                        label: 'Full name',
                        controller: _name,
                        icon: Icons.person_add_alt_rounded,
                        textCapitalization: TextCapitalization.words,
                        validator: _required('Full name'),
                      ),
                      const SizedBox(height: 10),
                    ],
                    AppTextField(
                      label: 'Email',
                      controller: _email,
                      icon: Icons.alternate_email_rounded,
                      keyboardType: TextInputType.emailAddress,
                      validator: _emailValidator(),
                    ),
                    if (_mode == AuthMode.register) ...[
                      const SizedBox(height: 10),
                      AppTextField(
                        label: 'Mobile number',
                        controller: _phone,
                        icon: Icons.call_outlined,
                        keyboardType: TextInputType.phone,
                        validator: _required('Mobile number'),
                      ),
                    ],
                    if (_mode != AuthMode.forgot) ...[
                      const SizedBox(height: 10),
                      AppTextField(
                        label: 'Password',
                        controller: _password,
                        icon: Icons.lock_outline_rounded,
                        obscureText: true,
                        validator: _passwordValidator(),
                      ),
                    ],
                  ] else if (_step == AuthStep.registerOtp) ...[
                    AuthOtpHeader(
                      title: 'Verify your email',
                      body:
                          'Enter the OTP sent to ${_email.text.trim()} to finish registration.',
                    ),
                    const SizedBox(height: 12),
                    AppTextField(
                      label: 'Email OTP',
                      controller: _otp,
                      icon: Icons.pin_outlined,
                      keyboardType: TextInputType.number,
                    ),
                  ] else ...[
                    AuthOtpHeader(
                      title: 'Set new password',
                      body:
                          'Enter the OTP sent to ${_email.text.trim()} and create a new password.',
                    ),
                    const SizedBox(height: 12),
                    AppTextField(
                      label: 'Email OTP',
                      controller: _otp,
                      icon: Icons.pin_outlined,
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 10),
                    AppTextField(
                      label: 'New password',
                      controller: _newPassword,
                      icon: Icons.lock_reset_rounded,
                      obscureText: true,
                    ),
                  ],
                  if (_statusMessage != null) ...[
                    const SizedBox(height: 12),
                    AuthInfoBanner(
                      icon: Icons.mark_email_read_outlined,
                      text: _statusMessage!,
                    ),
                  ],
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 12),
                    AuthErrorBanner(text: _errorMessage!),
                  ],
                  const SizedBox(height: 16),
                  if (_step == AuthStep.form)
                    PrimaryButton(
                      label: _loading
                          ? 'Please wait...'
                          : switch (_mode) {
                              AuthMode.login => 'Login and continue',
                              AuthMode.register => 'Register and continue',
                              AuthMode.forgot => 'Send reset OTP',
                            },
                      icon: _mode == AuthMode.forgot
                          ? Icons.send_rounded
                          : Icons.arrow_forward_rounded,
                      onPressed: _loading ? null : _submit,
                    )
                  else if (_step == AuthStep.registerOtp)
                    PrimaryButton(
                      label: _loading ? 'Verifying...' : 'Verify OTP',
                      icon: Icons.verified_rounded,
                      onPressed: _loading ? null : _verifyRegistrationOtp,
                    )
                  else
                    PrimaryButton(
                      label: _loading ? 'Saving...' : 'Save new password',
                      icon: Icons.lock_reset_rounded,
                      onPressed: _loading ? null : _resetPassword,
                    ),
                  if (_step != AuthStep.form) ...[
                    const SizedBox(height: 10),
                    SecondaryButton(
                      label: 'Back to email',
                      onPressed: _loading
                          ? null
                          : () => setState(() => _step = AuthStep.form),
                    ),
                  ],
                  if (_step == AuthStep.form && _mode != AuthMode.forgot) ...[
                    const SizedBox(height: 12),
                    const AuthDivider(),
                    const SizedBox(height: 12),
                    GoogleSignInButton(onPressed: _continueWithGoogle),
                  ],
                  const SizedBox(height: 12),
                  if (_step == AuthStep.form)
                    AuthFooterActions(
                      mode: _mode,
                      onLogin: () => _setMode(AuthMode.login),
                      onRegister: () => _setMode(AuthMode.register),
                      onForgot: () => _setMode(AuthMode.forgot),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            const SafetyNotice(
              text:
                  'Auth connects to Django for email login, OTP recovery, Google login, profile sync, and reports.',
            ),
            const SizedBox(height: 18),
            const FlowDots(activeIndex: 3, count: 7),
          ],
        ),
      ),
    );
  }

  FormFieldValidator<String> _required(String label) {
    return (value) =>
        value == null || value.trim().isEmpty ? '$label is required' : null;
  }

  FormFieldValidator<String> _emailValidator() {
    return (value) {
      final trimmed = value?.trim() ?? '';
      if (trimmed.isEmpty) {
        return 'Email is required';
      }
      final valid = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(trimmed);
      return valid ? null : 'Enter a valid email';
    };
  }

  FormFieldValidator<String> _passwordValidator() {
    return (value) {
      final trimmed = value?.trim() ?? '';
      if (trimmed.isEmpty) {
        return 'Password is required';
      }
      if (trimmed.length < 6) {
        return 'Use at least 6 characters';
      }
      return null;
    };
  }
}

class AuthHeroPanel extends StatelessWidget {
  const AuthHeroPanel({super.key, required this.mode});

  final AuthMode mode;

  String get _headline {
    return switch (mode) {
      AuthMode.login => 'Secure access for your AI health plan',
      AuthMode.register => 'Start with a protected Flicko account',
      AuthMode.forgot => 'Recover access without losing setup',
    };
  }

  String get _subtext {
    return switch (mode) {
      AuthMode.login =>
        'Your profile, reminders, chat memory, and reports stay connected.',
      AuthMode.register =>
        'Create access once, then complete your health profile.',
      AuthMode.forgot => 'Reset password and continue your guided setup.',
    };
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0D2E29), Color(0xFF0F6F62)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: FlickoTheme.tealDark.withValues(alpha: 0.22),
            blurRadius: 32,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.18),
                  ),
                ),
                child: const Icon(
                  Icons.favorite_rounded,
                  color: Color(0xFF8EF1C2),
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Flicko AI',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      _headline,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        height: 1.08,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _subtext,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.76),
              fontSize: 13.5,
              height: 1.38,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 14),
          const Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              AuthHeroBadge(icon: Icons.lock_outline_rounded, text: 'Private'),
              AuthHeroBadge(
                icon: Icons.health_and_safety_outlined,
                text: 'Health data',
              ),
              AuthHeroBadge(
                icon: Icons.cloud_sync_outlined,
                text: 'Django ready',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class AuthHeroBadge extends StatelessWidget {
  const AuthHeroBadge({super.key, required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: const Color(0xFFBFF7E1), size: 14),
          const SizedBox(width: 5),
          Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class AuthPanelHeader extends StatelessWidget {
  const AuthPanelHeader({
    super.key,
    required this.mode,
    required this.title,
    required this.body,
  });

  final AuthMode mode;
  final String title;
  final String body;

  IconData get _icon {
    return switch (mode) {
      AuthMode.login => Icons.login_rounded,
      AuthMode.register => Icons.person_add_alt_rounded,
      AuthMode.forgot => Icons.lock_reset_rounded,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: FlickoTheme.mint,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.9)),
          ),
          child: Icon(_icon, color: FlickoTheme.tealDark, size: 20),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: FlickoTheme.ink,
                  fontSize: 20,
                  height: 1.08,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                body,
                style: const TextStyle(
                  color: FlickoTheme.muted,
                  fontSize: 13,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class AuthModeSelector extends StatelessWidget {
  const AuthModeSelector({
    super.key,
    required this.mode,
    required this.onChanged,
  });

  final AuthMode mode;
  final ValueChanged<AuthMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: FlickoTheme.surfaceSoft,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: FlickoTheme.line),
      ),
      child: Row(
        children: [
          AuthModeTab(
            label: 'Login',
            selected: mode == AuthMode.login,
            onTap: () => onChanged(AuthMode.login),
          ),
          AuthModeTab(
            label: 'Register',
            selected: mode == AuthMode.register,
            onTap: () => onChanged(AuthMode.register),
          ),
          AuthModeTab(
            label: 'Forgot',
            selected: mode == AuthMode.forgot,
            onTap: () => onChanged(AuthMode.forgot),
          ),
        ],
      ),
    );
  }
}

class AuthModeTab extends StatelessWidget {
  const AuthModeTab({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 170),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: FlickoTheme.teal.withValues(alpha: 0.10),
                      blurRadius: 14,
                      offset: const Offset(0, 7),
                    ),
                  ]
                : null,
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: selected ? FlickoTheme.tealDark : FlickoTheme.muted,
              fontSize: 12.5,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
    );
  }
}

class GoogleSignInButton extends StatelessWidget {
  const GoogleSignInButton({super.key, required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          foregroundColor: FlickoTheme.tealDark,
          backgroundColor: FlickoTheme.surfaceSoft.withValues(alpha: 0.88),
          side: BorderSide(color: FlickoTheme.teal.withValues(alpha: 0.18)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
        ),
        onPressed: onPressed,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: FlickoTheme.line),
              ),
              child: const Center(
                child: Text(
                  'G',
                  style: TextStyle(
                    color: Color(0xFF4285F4),
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            const Text('Continue with Google'),
          ],
        ),
      ),
    );
  }
}

class AuthTrustStrip extends StatelessWidget {
  const AuthTrustStrip({super.key});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: const [
        AuthTrustBadge(
          icon: Icons.verified_user_outlined,
          text: 'Secure access',
        ),
        AuthTrustBadge(
          icon: Icons.history_edu_outlined,
          text: 'Profile memory',
        ),
        AuthTrustBadge(icon: Icons.picture_as_pdf_outlined, text: 'Reports'),
      ],
    );
  }
}

class AuthTrustBadge extends StatelessWidget {
  const AuthTrustBadge({super.key, required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: FlickoTheme.surfaceSoft,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: FlickoTheme.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: FlickoTheme.tealDark, size: 14),
          const SizedBox(width: 5),
          Text(
            text,
            style: const TextStyle(
              color: FlickoTheme.tealDark,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class AuthDivider extends StatelessWidget {
  const AuthDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: const [
        Expanded(child: Divider(color: FlickoTheme.line)),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 10),
          child: Text(
            'or',
            style: TextStyle(
              color: FlickoTheme.muted,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        Expanded(child: Divider(color: FlickoTheme.line)),
      ],
    );
  }
}

class AuthFooterActions extends StatelessWidget {
  const AuthFooterActions({
    super.key,
    required this.mode,
    required this.onLogin,
    required this.onRegister,
    required this.onForgot,
  });

  final AuthMode mode;
  final VoidCallback onLogin;
  final VoidCallback onRegister;
  final VoidCallback onForgot;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 9,
      runSpacing: 8,
      children: [
        if (mode != AuthMode.login)
          AuthFooterButton(
            label: 'Back to login',
            icon: Icons.login_rounded,
            onPressed: onLogin,
          ),
        if (mode == AuthMode.login)
          AuthFooterButton(
            label: 'Create account',
            icon: Icons.person_add_alt_rounded,
            onPressed: onRegister,
          ),
        if (mode != AuthMode.forgot)
          AuthFooterButton(
            label: 'Forgot password?',
            icon: Icons.lock_reset_rounded,
            onPressed: onForgot,
          ),
      ],
    );
  }
}

class AuthFooterButton extends StatelessWidget {
  const AuthFooterButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        foregroundColor: FlickoTheme.tealDark,
        backgroundColor: FlickoTheme.mint.withValues(alpha: 0.82),
        side: BorderSide(color: FlickoTheme.teal.withValues(alpha: 0.13)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        textStyle: const TextStyle(fontSize: 12.3, fontWeight: FontWeight.w900),
      ),
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      label: Text(label),
    );
  }
}

class AuthOtpHeader extends StatelessWidget {
  const AuthOtpHeader({super.key, required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: FlickoTheme.teal.withValues(alpha: 0.12)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: FlickoTheme.mint,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.mark_email_read_outlined,
              color: FlickoTheme.tealDark,
              size: 18,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: FlickoTheme.ink,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  body,
                  style: const TextStyle(
                    color: FlickoTheme.muted,
                    fontSize: 12.2,
                    height: 1.34,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class AuthInfoBanner extends StatelessWidget {
  const AuthInfoBanner({super.key, required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: FlickoTheme.mint.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: FlickoTheme.teal.withValues(alpha: 0.12)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: FlickoTheme.tealDark, size: 19),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: FlickoTheme.tealDark,
                fontSize: 12.5,
                height: 1.35,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class AuthErrorBanner extends StatelessWidget {
  const AuthErrorBanner({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: FlickoTheme.rose.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFD94258).withValues(alpha: 0.16),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: Color(0xFFD94258),
            size: 19,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Color(0xFF8A2432),
                fontSize: 12.5,
                height: 1.35,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({
    super.key,
    required this.draft,
    required this.onBack,
    required this.onSaved,
  });

  final HealthProfileDraft draft;
  final VoidCallback onBack;
  final ValueChanged<HealthProfileDraft> onSaved;

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _firstName;
  late final TextEditingController _middleName;
  late final TextEditingController _lastName;
  late final TextEditingController _age;
  late final TextEditingController _phone;
  late final TextEditingController _email;
  late final TextEditingController _food;
  late final TextEditingController _gender;
  late final TextEditingController _goalWeightKg;
  late final TextEditingController _goalWeightLb;
  late final TextEditingController _timezone;
  late final TextEditingController _language;
  late final TextEditingController _medications;
  late final TextEditingController _allergies;
  late final TextEditingController _diagnosis;
  late final TextEditingController _surgeryHistory;
  late final TextEditingController _familyHistory;
  late final TextEditingController _pregnancyCycle;
  late final TextEditingController _emergencyContactName;
  late final TextEditingController _emergencyContactPhone;
  int _profileStep = 0;
  late int _heightCmValue;
  late int _heightFeetValue;
  late int _heightInchesValue;
  late int _weightKgValue;
  late int _weightLbValue;
  String _weightUnit = 'kg';
  String _heightUnit = 'cm';

  @override
  void initState() {
    super.initState();
    _firstName = TextEditingController(text: widget.draft.firstName);
    _middleName = TextEditingController(text: widget.draft.middleName);
    _lastName = TextEditingController(text: widget.draft.lastName);
    _age = TextEditingController(text: widget.draft.age);
    _phone = TextEditingController(text: widget.draft.phone);
    _email = TextEditingController(text: widget.draft.email);
    _food = TextEditingController(text: widget.draft.foodPreference);
    _gender = TextEditingController(text: widget.draft.gender);
    _goalWeightKg = TextEditingController(text: widget.draft.goalWeightKg);
    _goalWeightLb = TextEditingController(text: widget.draft.goalWeightLb);
    _timezone = TextEditingController(text: widget.draft.timezone);
    _language = TextEditingController(text: widget.draft.language);
    _medications = TextEditingController(text: widget.draft.medications);
    _allergies = TextEditingController(text: widget.draft.allergies);
    _diagnosis = TextEditingController(text: widget.draft.diagnosis);
    _surgeryHistory = TextEditingController(text: widget.draft.surgeryHistory);
    _familyHistory = TextEditingController(text: widget.draft.familyHistory);
    _pregnancyCycle = TextEditingController(text: widget.draft.pregnancyCycle);
    _emergencyContactName = TextEditingController(
      text: widget.draft.emergencyContactName,
    );
    _emergencyContactPhone = TextEditingController(
      text: widget.draft.emergencyContactPhone,
    );

    if (_firstName.text.trim().isEmpty && widget.draft.name.trim().isNotEmpty) {
      final parts = widget.draft.name
          .trim()
          .split(RegExp(r'\s+'))
          .where((part) => part.isNotEmpty)
          .toList();
      _firstName.text = parts.isEmpty ? '' : parts.first;
      _lastName.text = parts.length > 1 ? parts.sublist(1).join(' ') : '';
    }

    _weightKgValue = _parseInt(widget.draft.weightKg, 70).clamp(30, 220);
    _weightLbValue = _parseInt(
      widget.draft.weightLb,
      (_weightKgValue * 2.20462).round(),
    ).clamp(66, 485);

    final storedFeet = _parseInt(widget.draft.heightFeet, 0);
    final storedInches = _parseInt(widget.draft.heightInches, 0);
    if (widget.draft.heightCm.trim().isEmpty && storedFeet > 0) {
      _heightCmValue = ((storedFeet * 12 + storedInches) * 2.54).round().clamp(
        120,
        230,
      );
    } else {
      _heightCmValue = _parseInt(widget.draft.heightCm, 170).clamp(120, 230);
    }
    _syncFeetInchesFromCm();
  }

  @override
  void dispose() {
    _firstName.dispose();
    _middleName.dispose();
    _lastName.dispose();
    _age.dispose();
    _phone.dispose();
    _email.dispose();
    _food.dispose();
    _gender.dispose();
    _goalWeightKg.dispose();
    _goalWeightLb.dispose();
    _timezone.dispose();
    _language.dispose();
    _medications.dispose();
    _allergies.dispose();
    _diagnosis.dispose();
    _surgeryHistory.dispose();
    _familyHistory.dispose();
    _pregnancyCycle.dispose();
    _emergencyContactName.dispose();
    _emergencyContactPhone.dispose();
    super.dispose();
  }

  int _parseInt(String value, int fallback) {
    return int.tryParse(value.trim()) ?? fallback;
  }

  String _fullName() {
    return [
      _firstName.text,
      _middleName.text,
      _lastName.text,
    ].map((value) => value.trim()).where((value) => value.isNotEmpty).join(' ');
  }

  void _goToMetrics() {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    setState(() => _profileStep = 1);
  }

  void _goToMedical() {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    setState(() => _profileStep = 2);
  }

  void _backFromProfileStep() {
    if (_profileStep == 0) {
      widget.onBack();
      return;
    }
    setState(() => _profileStep -= 1);
  }

  void _setWeightKg(int value) {
    setState(() {
      _weightKgValue = value.clamp(30, 220);
      _weightLbValue = (value * 2.20462).round().clamp(66, 485);
    });
  }

  void _setWeightLb(int value) {
    setState(() {
      _weightLbValue = value.clamp(66, 485);
      _weightKgValue = (value / 2.20462).round().clamp(30, 220);
    });
  }

  void _setHeightCm(int value) {
    setState(() {
      _heightCmValue = value.clamp(120, 230);
      _syncFeetInchesFromCm();
    });
  }

  void _setHeightFeet(int value) {
    setState(() {
      _heightFeetValue = value.clamp(3, 8);
      _syncCmFromFeetInches();
    });
  }

  void _setHeightInches(int value) {
    setState(() {
      _heightInchesValue = value.clamp(0, 11);
      _syncCmFromFeetInches();
    });
  }

  void _syncFeetInchesFromCm() {
    final totalInches = (_heightCmValue / 2.54).round();
    _heightFeetValue = (totalInches ~/ 12).clamp(3, 8);
    _heightInchesValue = (totalInches % 12).clamp(0, 11);
  }

  void _syncCmFromFeetInches() {
    _heightCmValue = ((_heightFeetValue * 12 + _heightInchesValue) * 2.54)
        .round()
        .clamp(120, 230);
  }

  void _save() {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    widget.onSaved(
      widget.draft.copyWith(
        name: _fullName(),
        firstName: _firstName.text.trim(),
        middleName: _middleName.text.trim(),
        lastName: _lastName.text.trim(),
        age: _age.text.trim(),
        phone: _phone.text.trim(),
        email: _email.text.trim(),
        heightCm: _heightCmValue.toString(),
        heightFeet: _heightFeetValue.toString(),
        heightInches: _heightInchesValue.toString(),
        weightKg: _weightKgValue.toString(),
        weightLb: _weightLbValue.toString(),
        goalWeightKg: _goalWeightKg.text.trim(),
        goalWeightLb: _goalWeightLb.text.trim(),
        gender: _gender.text.trim(),
        timezone: _timezone.text.trim(),
        language: _language.text.trim(),
        foodPreference: _food.text.trim(),
        medications: _medications.text.trim(),
        allergies: _allergies.text.trim(),
        diagnosis: _diagnosis.text.trim(),
        surgeryHistory: _surgeryHistory.text.trim(),
        familyHistory: _familyHistory.text.trim(),
        pregnancyCycle: _pregnancyCycle.text.trim(),
        emergencyContactName: _emergencyContactName.text.trim(),
        emergencyContactPhone: _emergencyContactPhone.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppPage(
      key: ValueKey('profile-setup-page-step-$_profileStep'),
      onBack: _backFromProfileStep,
      backLabel: switch (_profileStep) {
        0 => 'Back',
        1 => 'Back to details',
        _ => 'Back to metrics',
      },
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionLabel('Step 6 of 7'),
            const SizedBox(height: 8),
            Text(switch (_profileStep) {
              0 => 'Build your local profile.',
              1 => 'Body metrics.',
              _ => 'Medical profile.',
            }, style: Theme.of(context).textTheme.headlineLarge),
            const SizedBox(height: 10),
            Text(switch (_profileStep) {
              0 =>
                'Add your name and contact details first. No login in this phase.',
              1 =>
                'Set height and weight with synced unit pickers before saving.',
              _ =>
                'Add medicines, allergies, diagnosis, family history, pregnancy or cycle notes, and emergency contact when available.',
            }, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 18),
            ProfileStepIndicator(activeStep: _profileStep),
            const SizedBox(height: 14),
            AnimatedSwitcher(
              duration: FlickoMotion.inlineDuration,
              switchInCurve: FlickoMotion.routeCurve,
              switchOutCurve: FlickoMotion.routeReverseCurve,
              layoutBuilder: (currentChild, previousChildren) => Stack(
                alignment: Alignment.topCenter,
                children: <Widget>[
                  ...previousChildren,
                  ...?(currentChild == null ? null : <Widget>[currentChild]),
                ],
              ),
              transitionBuilder: (child, animation) {
                final curved = CurvedAnimation(
                  parent: animation,
                  curve: FlickoMotion.routeCurve,
                  reverseCurve: FlickoMotion.routeReverseCurve,
                );
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0.028, 0),
                      end: Offset.zero,
                    ).animate(curved),
                    child: child,
                  ),
                );
              },
              child: switch (_profileStep) {
                0 => _IdentityProfileStep(
                  key: const ValueKey('identity-profile-step'),
                  firstName: _firstName,
                  middleName: _middleName,
                  lastName: _lastName,
                  phone: _phone,
                  email: _email,
                  requiredValidator: _required,
                  emailValidator: _emailValidator,
                ),
                1 => _MetricsProfileStep(
                  key: const ValueKey('metrics-profile-step'),
                  age: _age,
                  food: _food,
                  heightCm: _heightCmValue,
                  heightFeet: _heightFeetValue,
                  heightInches: _heightInchesValue,
                  weightKg: _weightKgValue,
                  weightLb: _weightLbValue,
                  weightUnit: _weightUnit,
                  heightUnit: _heightUnit,
                  onWeightUnitChanged: (unit) =>
                      setState(() => _weightUnit = unit),
                  onHeightUnitChanged: (unit) =>
                      setState(() => _heightUnit = unit),
                  onHeightCmChanged: _setHeightCm,
                  onHeightFeetChanged: _setHeightFeet,
                  onHeightInchesChanged: _setHeightInches,
                  onWeightKgChanged: _setWeightKg,
                  onWeightLbChanged: _setWeightLb,
                  requiredValidator: _required,
                ),
                _ => MedicalProfileStep(
                  key: const ValueKey('medical-profile-step'),
                  gender: _gender,
                  goalWeightKg: _goalWeightKg,
                  goalWeightLb: _goalWeightLb,
                  timezone: _timezone,
                  language: _language,
                  medications: _medications,
                  allergies: _allergies,
                  diagnosis: _diagnosis,
                  surgeryHistory: _surgeryHistory,
                  familyHistory: _familyHistory,
                  pregnancyCycle: _pregnancyCycle,
                  emergencyContactName: _emergencyContactName,
                  emergencyContactPhone: _emergencyContactPhone,
                ),
              },
            ),
            const SizedBox(height: 14),
            const SafetyNotice(
              text:
                  'Profile facts will guide reminders, reports, food scores, and the 20-minute AI intake later.',
            ),
            const SizedBox(height: 18),
            PrimaryButton(
              label: switch (_profileStep) {
                0 => 'Next: height and weight',
                1 => 'Next: medical details',
                _ => 'Save profile and continue',
              },
              onPressed: switch (_profileStep) {
                0 => _goToMetrics,
                1 => _goToMedical,
                _ => _save,
              },
            ),
            const SizedBox(height: 18),
            const FlowDots(activeIndex: 5, count: 7),
          ],
        ),
      ),
    );
  }

  FormFieldValidator<String> _required(String label) {
    return (value) =>
        value == null || value.trim().isEmpty ? '$label is required' : null;
  }

  FormFieldValidator<String> _emailValidator() {
    return (value) {
      final trimmed = value?.trim() ?? '';
      if (trimmed.isEmpty) {
        return 'Email is required';
      }
      final valid = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(trimmed);
      return valid ? null : 'Enter a valid email';
    };
  }
}

class ProfileStepIndicator extends StatelessWidget {
  const ProfileStepIndicator({super.key, required this.activeStep});

  final int activeStep;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: ProfileStagePill(
            number: '1',
            title: 'Profile',
            active: activeStep == 0,
            complete: activeStep > 0,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: ProfileStagePill(
            number: '2',
            title: 'Metrics',
            active: activeStep == 1,
            complete: activeStep > 1,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: ProfileStagePill(
            number: '3',
            title: 'Medical',
            active: activeStep == 2,
            complete: false,
          ),
        ),
      ],
    );
  }
}

class ProfileStagePill extends StatelessWidget {
  const ProfileStagePill({
    super.key,
    required this.number,
    required this.title,
    required this.active,
    required this.complete,
  });

  final String number;
  final String title;
  final bool active;
  final bool complete;

  @override
  Widget build(BuildContext context) {
    final color = active || complete ? FlickoTheme.teal : FlickoTheme.muted;
    return Container(
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: active
            ? Colors.white.withValues(alpha: 0.94)
            : Colors.white.withValues(alpha: 0.58),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: active
              ? FlickoTheme.teal.withValues(alpha: 0.28)
              : Colors.white.withValues(alpha: 0.82),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: active || complete ? FlickoTheme.teal : FlickoTheme.line,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: complete
                  ? const Icon(
                      Icons.check_rounded,
                      color: Colors.white,
                      size: 16,
                    )
                  : Text(
                      number,
                      style: TextStyle(
                        color: active ? Colors.white : FlickoTheme.muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              title,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 12.5,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _IdentityProfileStep extends StatelessWidget {
  const _IdentityProfileStep({
    super.key,
    required this.firstName,
    required this.middleName,
    required this.lastName,
    required this.phone,
    required this.email,
    required this.requiredValidator,
    required this.emailValidator,
  });

  final TextEditingController firstName;
  final TextEditingController middleName;
  final TextEditingController lastName;
  final TextEditingController phone;
  final TextEditingController email;
  final FormFieldValidator<String> Function(String label) requiredValidator;
  final FormFieldValidator<String> Function() emailValidator;

  @override
  Widget build(BuildContext context) {
    return HealthCard(
      highlighted: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ProfilePanelHeader(
            icon: Icons.person_outline_rounded,
            title: 'Local identity',
            body:
                'Saved on this phone now. Django sync can use the same fields later.',
          ),
          const SizedBox(height: 14),
          AppTextField(
            label: 'First name',
            controller: firstName,
            icon: Icons.person_outline_rounded,
            textCapitalization: TextCapitalization.words,
            validator: requiredValidator('First name'),
          ),
          const SizedBox(height: 10),
          AppTextField(
            label: 'Middle name optional',
            controller: middleName,
            icon: Icons.badge_outlined,
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: 10),
          AppTextField(
            label: 'Last name',
            controller: lastName,
            icon: Icons.person_rounded,
            textCapitalization: TextCapitalization.words,
            validator: requiredValidator('Last name'),
          ),
          const SizedBox(height: 10),
          AppTextField(
            label: 'Phone number',
            controller: phone,
            icon: Icons.call_outlined,
            keyboardType: TextInputType.phone,
            validator: requiredValidator('Phone number'),
          ),
          const SizedBox(height: 10),
          AppTextField(
            label: 'Email',
            controller: email,
            icon: Icons.alternate_email_rounded,
            keyboardType: TextInputType.emailAddress,
            validator: emailValidator(),
          ),
        ],
      ),
    );
  }
}

class _MetricsProfileStep extends StatelessWidget {
  const _MetricsProfileStep({
    super.key,
    required this.age,
    required this.food,
    required this.heightCm,
    required this.heightFeet,
    required this.heightInches,
    required this.weightKg,
    required this.weightLb,
    required this.weightUnit,
    required this.heightUnit,
    required this.onWeightUnitChanged,
    required this.onHeightUnitChanged,
    required this.onHeightCmChanged,
    required this.onHeightFeetChanged,
    required this.onHeightInchesChanged,
    required this.onWeightKgChanged,
    required this.onWeightLbChanged,
    required this.requiredValidator,
  });

  final TextEditingController age;
  final TextEditingController food;
  final int heightCm;
  final int heightFeet;
  final int heightInches;
  final int weightKg;
  final int weightLb;
  final String weightUnit;
  final String heightUnit;
  final ValueChanged<String> onWeightUnitChanged;
  final ValueChanged<String> onHeightUnitChanged;
  final ValueChanged<int> onHeightCmChanged;
  final ValueChanged<int> onHeightFeetChanged;
  final ValueChanged<int> onHeightInchesChanged;
  final ValueChanged<int> onWeightKgChanged;
  final ValueChanged<int> onWeightLbChanged;
  final FormFieldValidator<String> Function(String label) requiredValidator;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        MetricWheelCard(
          icon: Icons.monitor_weight_outlined,
          title: 'Weight',
          body: 'Enter exact weight. Unit conversion saves automatically.',
          unitSelector: MetricUnitToggle(
            value: weightUnit,
            options: const [
              MetricUnitOption(value: 'kg', label: 'kg'),
              MetricUnitOption(value: 'lb', label: 'lb'),
            ],
            onChanged: onWeightUnitChanged,
          ),
          child: MetricMeasurementControl(
            summary: '$weightKg kg saved with $weightLb lb backup',
            manualInput: MetricManualField(
              key: ValueKey('manual-weight-$weightUnit'),
              label: 'Weight (${weightUnit == 'kg' ? 'kg' : 'lb'})',
              value: weightUnit == 'kg' ? weightKg : weightLb,
              suffix: weightUnit,
              min: weightUnit == 'kg' ? 30 : 66,
              max: weightUnit == 'kg' ? 220 : 485,
              icon: Icons.edit_rounded,
              onChanged: weightUnit == 'kg'
                  ? onWeightKgChanged
                  : onWeightLbChanged,
            ),
          ),
        ),
        const SizedBox(height: 12),
        MetricWheelCard(
          icon: Icons.height_rounded,
          title: 'Height',
          body: 'Enter exact height. Both formats save together.',
          unitSelector: MetricUnitToggle(
            value: heightUnit,
            options: const [
              MetricUnitOption(value: 'cm', label: 'cm'),
              MetricUnitOption(value: 'ftin', label: 'ft / in'),
            ],
            onChanged: onHeightUnitChanged,
          ),
          child: heightUnit == 'cm'
              ? MetricMeasurementControl(
                  summary:
                      '$heightCm cm saved with $heightFeet ft $heightInches in',
                  manualInput: MetricManualField(
                    key: const ValueKey('manual-height-cm'),
                    label: 'Height (cm)',
                    value: heightCm,
                    suffix: 'cm',
                    min: 120,
                    max: 230,
                    icon: Icons.straighten_rounded,
                    onChanged: onHeightCmChanged,
                  ),
                )
              : MetricMeasurementControl(
                  summary:
                      '$heightFeet ft $heightInches in saved with $heightCm cm',
                  manualInput: Row(
                    children: [
                      Expanded(
                        child: MetricManualField(
                          key: const ValueKey('manual-height-ft'),
                          label: 'Feet',
                          value: heightFeet,
                          suffix: 'ft',
                          min: 3,
                          max: 8,
                          icon: Icons.straighten_rounded,
                          onChanged: onHeightFeetChanged,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: MetricManualField(
                          key: const ValueKey('manual-height-in'),
                          label: 'Inches',
                          value: heightInches,
                          suffix: 'in',
                          min: 0,
                          max: 11,
                          icon: Icons.height_rounded,
                          onChanged: onHeightInchesChanged,
                        ),
                      ),
                    ],
                  ),
                ),
        ),
        const SizedBox(height: 12),
        HealthCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const ProfilePanelHeader(
                icon: Icons.restaurant_menu_rounded,
                title: 'Health context',
                body:
                    'These fields help the AI build safer meal and habit plans.',
              ),
              const SizedBox(height: 14),
              AppTextField(
                label: 'Age',
                controller: age,
                icon: Icons.cake_outlined,
                keyboardType: TextInputType.number,
                validator: requiredValidator('Age'),
              ),
              const SizedBox(height: 10),
              AppTextField(
                label: 'Food preference',
                controller: food,
                icon: Icons.restaurant_outlined,
                hintText: 'Indian vegetarian, low sugar',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class ProfilePanelHeader extends StatelessWidget {
  const ProfilePanelHeader({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: FlickoTheme.mint.withValues(alpha: 0.88),
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: Colors.white.withValues(alpha: 0.82)),
          ),
          child: Center(
            child: Icon(icon, color: FlickoTheme.tealDark, size: 18),
          ),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 3),
              Text(
                body,
                style: const TextStyle(
                  color: FlickoTheme.muted,
                  fontSize: 12.5,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class MetricMeasurementControl extends StatelessWidget {
  const MetricMeasurementControl({
    super.key,
    required this.summary,
    required this.manualInput,
    this.footer,
  });

  final String summary;
  final Widget manualInput;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFFFFFF), Color(0xFFF0F8F4)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: FlickoTheme.teal.withValues(alpha: 0.12),
              ),
              boxShadow: [
                BoxShadow(
                  color: FlickoTheme.teal.withValues(alpha: 0.08),
                  blurRadius: 18,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: const [
                    ProfileFieldIcon(icon: Icons.edit_note_rounded),
                    SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        'Manual input',
                        style: TextStyle(
                          color: FlickoTheme.ink,
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                manualInput,
                const SizedBox(height: 10),
                MetricSummaryStrip(text: summary),
                if (footer != null) ...[const SizedBox(height: 10), footer!],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class MetricSummaryStrip extends StatelessWidget {
  const MetricSummaryStrip({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: FlickoTheme.tealDark.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.check_circle_rounded,
            color: FlickoTheme.tealDark,
            size: 16,
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: FlickoTheme.tealDark,
                fontSize: 12,
                height: 1.25,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class MetricManualField extends StatefulWidget {
  const MetricManualField({
    super.key,
    required this.label,
    required this.value,
    required this.suffix,
    required this.min,
    required this.max,
    required this.icon,
    required this.onChanged,
  });

  final String label;
  final int value;
  final String suffix;
  final int min;
  final int max;
  final IconData icon;
  final ValueChanged<int> onChanged;

  @override
  State<MetricManualField> createState() => _MetricManualFieldState();
}

class _MetricManualFieldState extends State<MetricManualField> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value.toString());
    _focusNode = FocusNode();
  }

  @override
  void didUpdateWidget(covariant MetricManualField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value == widget.value || _focusNode.hasFocus) {
      return;
    }
    _setText(widget.value.toString());
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _setText(String value) {
    _controller.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }

  void _apply(String raw, {required bool clamp}) {
    final parsed = int.tryParse(raw.trim());
    if (parsed == null) {
      return;
    }

    if (!clamp && (parsed < widget.min || parsed > widget.max)) {
      return;
    }

    final next = parsed.clamp(widget.min, widget.max).toInt();
    widget.onChanged(next);
  }

  void _commit() {
    final parsed = int.tryParse(_controller.text.trim());
    final next = (parsed ?? widget.value).clamp(widget.min, widget.max).toInt();
    _setText(next.toString());
    widget.onChanged(next);
    _focusNode.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: _controller,
      focusNode: _focusNode,
      keyboardType: TextInputType.number,
      textInputAction: TextInputAction.done,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      onChanged: (value) => _apply(value, clamp: false),
      onEditingComplete: _commit,
      onFieldSubmitted: (_) => _commit(),
      decoration: InputDecoration(
        labelText: widget.label,
        suffixText: widget.suffix,
        prefixIcon: Align(
          widthFactor: 1,
          heightFactor: 1,
          child: Padding(
            padding: const EdgeInsetsDirectional.only(start: 10, end: 8),
            child: ProfileFieldIcon(icon: widget.icon),
          ),
        ),
        prefixIconConstraints: const BoxConstraints(
          minWidth: 47,
          minHeight: 48,
        ),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.96),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 15,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(
            color: FlickoTheme.teal.withValues(alpha: 0.12),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(
            color: FlickoTheme.teal.withValues(alpha: 0.12),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: FlickoTheme.teal, width: 1.4),
        ),
      ),
      style: const TextStyle(
        color: FlickoTheme.ink,
        fontSize: 16,
        fontWeight: FontWeight.w900,
      ),
    );
  }
}

class MetricWheelCard extends StatelessWidget {
  const MetricWheelCard({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    required this.child,
    this.unitSelector,
  });

  final IconData icon;
  final String title;
  final String body;
  final Widget child;
  final Widget? unitSelector;

  @override
  Widget build(BuildContext context) {
    return HealthCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ProfilePanelHeader(icon: icon, title: title, body: body),
          const SizedBox(height: 12),
          if (unitSelector != null) ...[
            unitSelector!,
            const SizedBox(height: 12),
          ],
          Center(child: child),
        ],
      ),
    );
  }
}

class MetricUnitOption {
  const MetricUnitOption({required this.value, required this.label});

  final String value;
  final String label;
}

class MetricUnitToggle extends StatelessWidget {
  const MetricUnitToggle({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String value;
  final List<MetricUnitOption> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: FlickoTheme.surfaceSoft,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: FlickoTheme.line),
      ),
      child: Row(
        children: [
          for (final option in options)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(option.value),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 170),
                  curve: Curves.easeOutCubic,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: value == option.value
                        ? Colors.white
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: value == option.value
                        ? [
                            BoxShadow(
                              color: FlickoTheme.teal.withValues(alpha: 0.12),
                              blurRadius: 12,
                              offset: const Offset(0, 6),
                            ),
                          ]
                        : null,
                  ),
                  child: Text(
                    option.label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: value == option.value
                          ? FlickoTheme.tealDark
                          : FlickoTheme.muted,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class MetricWheelField extends StatefulWidget {
  const MetricWheelField({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  State<MetricWheelField> createState() => _MetricWheelFieldState();
}

class _MetricWheelFieldState extends State<MetricWheelField> {
  late final FixedExtentScrollController _controller;
  bool _syncingFromExternalValue = false;

  int get _selectedIndex =>
      (widget.value - widget.min).clamp(0, widget.max - widget.min);

  @override
  void initState() {
    super.initState();
    _controller = FixedExtentScrollController(initialItem: _selectedIndex);
  }

  @override
  void didUpdateWidget(covariant MetricWheelField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value == widget.value) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_controller.hasClients) {
        return;
      }
      if (_controller.selectedItem == _selectedIndex) {
        return;
      }
      _syncingFromExternalValue = true;
      _controller
          .animateToItem(
            _selectedIndex,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
          )
          .whenComplete(() {
            if (mounted) {
              _syncingFromExternalValue = false;
            }
          });
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final itemCount = widget.max - widget.min + 1;
    return Container(
      width: 128,
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: FlickoTheme.teal.withValues(alpha: 0.12)),
        boxShadow: [
          BoxShadow(
            color: FlickoTheme.teal.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: FlickoTheme.mint,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              widget.label,
              style: const TextStyle(
                color: FlickoTheme.tealDark,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 62,
            child: CupertinoPicker.builder(
              scrollController: _controller,
              itemExtent: 50,
              diameterRatio: 1.05,
              squeeze: 1.0,
              useMagnifier: true,
              magnification: 1.02,
              selectionOverlay: DecoratedBox(
                decoration: BoxDecoration(
                  color: FlickoTheme.mint.withValues(alpha: 0.66),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: FlickoTheme.teal.withValues(alpha: 0.14),
                  ),
                ),
              ),
              onSelectedItemChanged: (index) {
                if (_syncingFromExternalValue) {
                  return;
                }
                widget.onChanged(widget.min + index);
              },
              childCount: itemCount,
              itemBuilder: (context, index) {
                final value = widget.min + index;
                return Center(
                  child: Text(
                    value.toString(),
                    style: TextStyle(
                      color: value == widget.value
                          ? FlickoTheme.tealDark
                          : FlickoTheme.muted,
                      fontSize: value == widget.value ? 25 : 18,
                      fontWeight: value == widget.value
                          ? FontWeight.w900
                          : FontWeight.w700,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    super.key,
    required this.draft,
    required this.onBack,
    required this.onEditProfile,
  });

  final HealthProfileDraft draft;
  final VoidCallback onBack;
  final VoidCallback onEditProfile;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _tab = 0;
  bool _bmiDialogShown = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _showBmiDialogOnce());
  }

  @override
  void didUpdateWidget(covariant DashboardScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.draft != widget.draft) {
      _bmiDialogShown = false;
      WidgetsBinding.instance.addPostFrameCallback((_) => _showBmiDialogOnce());
    }
  }

  void _showBmiDialogOnce() {
    if (!mounted || _bmiDialogShown) {
      return;
    }
    final snapshot = BmiSnapshot.fromProfileMetrics(
      weightKg: widget.draft.weightKg,
      weightLb: widget.draft.weightLb,
      heightCm: widget.draft.heightCm,
      heightFeet: widget.draft.heightFeet,
      heightInches: widget.draft.heightInches,
      age: widget.draft.age,
    );
    if (snapshot == null) {
      return;
    }
    _bmiDialogShown = true;
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (context) => BmiMeterDialog(snapshot: snapshot),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      DashboardHome(draft: widget.draft, onEditProfile: widget.onEditProfile),
      ChatPreview(onBack: _backFromDashboardTab),
      MealsPreview(onBack: _backFromDashboardTab),
      ReportsPreview(onBack: _backFromDashboardTab),
    ];
    return Scaffold(
      body: pages[_tab],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        backgroundColor: Colors.white.withValues(alpha: 0.94),
        indicatorColor: FlickoTheme.mint,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        onDestinationSelected: (value) => setState(() => _tab = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            selectedIcon: Icon(Icons.chat_bubble),
            label: 'Chat',
          ),
          NavigationDestination(
            icon: Icon(Icons.grid_view_outlined),
            selectedIcon: Icon(Icons.grid_view),
            label: 'Meals',
          ),
          NavigationDestination(
            icon: Icon(Icons.article_outlined),
            selectedIcon: Icon(Icons.article),
            label: 'Reports',
          ),
        ],
      ),
    );
  }

  void _backFromDashboardTab() {
    if (_tab == 0) {
      widget.onBack();
      return;
    }
    setState(() => _tab = 0);
  }
}

class DashboardHome extends StatelessWidget {
  const DashboardHome({
    super.key,
    required this.draft,
    required this.onEditProfile,
  });

  final HealthProfileDraft draft;
  final VoidCallback onEditProfile;

  @override
  Widget build(BuildContext context) {
    final firstName = draft.givenName.isEmpty ? 'there' : draft.givenName;
    final activePlan = draft.selectedProblems.isEmpty
        ? 'General health plan'
        : '${draft.selectedProblems.take(2).join(' + ')} plan';
    return AppPage(
      bottomPadding: 18,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Tuesday, May 19',
                      style: TextStyle(
                        color: FlickoTheme.muted,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Good morning, $firstName.',
                      style: Theme.of(context).textTheme.headlineLarge,
                    ),
                  ],
                ),
              ),
              IconButton.filledTonal(
                onPressed: onEditProfile,
                icon: const Icon(Icons.tune_rounded),
                tooltip: 'Edit setup',
              ),
            ],
          ),
          const SizedBox(height: 16),
          HealthScoreCard(activePlan: activePlan),
          const SizedBox(height: 12),
          Row(
            children: const [
              Expanded(
                child: MiniActionCard(
                  title: 'AI call',
                  meta: 'Ready',
                  body: 'Start the 20-minute intake and save structured notes.',
                  highlighted: true,
                ),
              ),
              SizedBox(width: 10),
              Expanded(
                child: MiniActionCard(
                  title: 'PDF report',
                  meta: 'Draft',
                  body: 'Weekly summary and dinner plan will generate here.',
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          HealthCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Today',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    Text(
                      '3 tasks',
                      style: TextStyle(color: FlickoTheme.muted, fontSize: 12),
                    ),
                  ],
                ),
                SizedBox(height: 6),
                TaskRow(
                  icon: Icons.add_a_photo_outlined,
                  title: 'Upload lunch photo',
                  body: 'AI scores portion, carb load, and sugar risk.',
                  time: '1 PM',
                ),
                TaskRow(
                  icon: Icons.directions_walk_rounded,
                  title: 'Walk after meal',
                  body: '20 minutes, low intensity.',
                  time: '2 PM',
                ),
                TaskRow(
                  icon: Icons.nightlight_round,
                  title: 'Sleep wind-down',
                  body: 'Start routine before 10:30 PM.',
                  time: '10 PM',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ChatPreview extends StatelessWidget {
  const ChatPreview({super.key, required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return AppPage(
      onBack: onBack,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionLabel('24/7 AI chat'),
          const SizedBox(height: 8),
          Text(
            'Ask freely. Memory comes next.',
            style: Theme.of(context).textTheme.headlineLarge,
          ),
          const SizedBox(height: 16),
          const ChatBubble(
            text:
                'Can I eat dosa tonight if I am trying to reduce sugar spikes?',
            mine: true,
          ),
          const ChatBubble(
            text:
                'Yes, but pair it with protein, reduce chutney sugar, avoid sweet drinks, and walk 10-15 minutes after dinner. I can also turn this into a simple dinner plan for tonight.',
            mine: false,
          ),
          const Spacer(),
          const SafetyNotice(
            text:
                'Gemini chat is active in the app. Deeper protocol memory can be layered in next.',
          ),
        ],
      ),
    );
  }
}

class MealsPreview extends StatelessWidget {
  const MealsPreview({super.key, required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return AppPage(
      onBack: onBack,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionLabel('Meal photo score'),
          const SizedBox(height: 8),
          Text(
            'Scan lunch. Get a practical decision.',
            style: Theme.of(context).textTheme.headlineLarge,
          ),
          const SizedBox(height: 16),
          HealthCard(
            child: Column(
              children: [
                Container(
                  height: 210,
                  decoration: BoxDecoration(
                    color: FlickoTheme.surfaceSoft,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: FlickoTheme.line),
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.add_a_photo_outlined,
                      size: 48,
                      color: FlickoTheme.teal,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Future output: meal guess, confidence, calorie range, carb load, protein quality, and eat/reduce/avoid decision.',
                  style: TextStyle(color: FlickoTheme.muted, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ReportsPreview extends StatelessWidget {
  const ReportsPreview({super.key, required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return AppPage(
      onBack: onBack,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionLabel('Reports'),
          const SizedBox(height: 8),
          Text(
            'Doctor-ready summaries and plans.',
            style: Theme.of(context).textTheme.headlineLarge,
          ),
          const SizedBox(height: 16),
          const FeatureTile(
            color: FlickoTheme.sky,
            iconColor: Color(0xFF2563EB),
            icon: Icons.picture_as_pdf_outlined,
            title: 'Weekly progress PDF',
            body: 'Weight, meals, adherence, calls, and next plan.',
          ),
          const SizedBox(height: 10),
          const FeatureTile(
            color: FlickoTheme.mint,
            iconColor: FlickoTheme.tealDark,
            icon: Icons.medical_information_outlined,
            title: 'Doctor-ready report',
            body: 'Symptoms, medications, logs, and risk flags in one summary.',
          ),
          const SizedBox(height: 10),
          const FeatureTile(
            color: FlickoTheme.peach,
            iconColor: Color(0xFFC77718),
            icon: Icons.dinner_dining_outlined,
            title: 'Dinner plan',
            body: 'Condition-aware options from profile and food history.',
          ),
        ],
      ),
    );
  }
}

class AppPage extends StatefulWidget {
  const AppPage({
    super.key,
    required this.child,
    this.topPadding = 22,
    this.horizontalPadding = 24,
    this.bottomPadding = 28,
    this.onBack,
    this.backLabel = 'Back',
  });

  final Widget child;
  final double topPadding;
  final double horizontalPadding;
  final double bottomPadding;
  final VoidCallback? onBack;
  final String backLabel;

  @override
  State<AppPage> createState() => _AppPageState();
}

class _AppPageState extends State<AppPage> {
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFEAF3F0), FlickoTheme.background],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Scrollbar(
            controller: _scrollController,
            thumbVisibility: true,
            radius: const Radius.circular(999),
            thickness: 4,
            child: SingleChildScrollView(
              controller: _scrollController,
              primary: false,
              padding: EdgeInsets.fromLTRB(
                widget.horizontalPadding,
                widget.topPadding,
                widget.horizontalPadding,
                widget.bottomPadding,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (widget.onBack != null) ...[
                    AppBackButton(
                      label: widget.backLabel,
                      onPressed: widget.onBack!,
                    ),
                    const SizedBox(height: 14),
                  ],
                  widget.child,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AppBackButton extends StatelessWidget {
  const AppBackButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onPressed,
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.fromLTRB(10, 6, 14, 6),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.76),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: FlickoTheme.line),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: const BoxDecoration(
                  color: FlickoTheme.surfaceSoft,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.arrow_back_rounded,
                  color: FlickoTheme.tealDark,
                  size: 18,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  color: FlickoTheme.ink,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class WelcomeImageHero extends StatelessWidget {
  const WelcomeImageHero({super.key});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/welcome_hero.png',
      width: double.infinity,
      height: double.infinity,
      fit: BoxFit.cover,
      alignment: Alignment.topCenter,
      errorBuilder: (context, error, stackTrace) {
        return Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [FlickoTheme.mint, FlickoTheme.sky],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          alignment: Alignment.center,
          child: const Icon(
            Icons.monitor_heart_outlined,
            color: FlickoTheme.tealDark,
            size: 48,
          ),
        );
      },
    );
  }
}

class LiveCallCard extends StatelessWidget {
  const LiveCallCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: FlickoTheme.darkPanel,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Expanded(child: SectionLabel('AI care call', light: true)),
              Text(
                '01:42',
                style: TextStyle(
                  color: Colors.white70,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 30),
          const Text(
            'Flicko Coach is ready',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Voice intake collects symptoms, routine, meals, sleep, risk signals, and goals.',
            style: TextStyle(color: Colors.white70, height: 1.45),
          ),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: const [
              WaveBar(height: 14),
              WaveBar(height: 26),
              WaveBar(height: 18),
              WaveBar(height: 32),
              WaveBar(height: 21),
              WaveBar(height: 15),
              WaveBar(height: 28),
            ],
          ),
        ],
      ),
    );
  }
}

class WaveBar extends StatelessWidget {
  const WaveBar({super.key, required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 5,
      height: height,
      margin: const EdgeInsets.only(right: 5),
      decoration: BoxDecoration(
        color: const Color(0xFF7FE0D0),
        borderRadius: BorderRadius.circular(999),
      ),
    );
  }
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.label, {super.key, this.light = false});

  final String label;
  final bool light;

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: TextStyle(
        color: light ? const Color(0xFF7FE0D0) : FlickoTheme.tealDark,
        fontSize: 12,
        fontWeight: FontWeight.w900,
        letterSpacing: 1.4,
      ),
    );
  }
}

class HealthCard extends StatelessWidget {
  const HealthCard({super.key, required this.child, this.highlighted = false});

  final Widget child;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: highlighted ? const Color(0xFFF0FAF5) : FlickoTheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: highlighted ? const Color(0xFFD7EADF) : FlickoTheme.line,
        ),
      ),
      child: child,
    );
  }
}

class FeatureTile extends StatelessWidget {
  const FeatureTile({
    super.key,
    required this.color,
    required this.iconColor,
    required this.icon,
    required this.title,
    required this.body,
  });

  final Color color;
  final Color iconColor;
  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return HealthCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: const TextStyle(
                    color: FlickoTheme.muted,
                    height: 1.38,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ProblemChip extends StatelessWidget {
  const ProblemChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 36),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? FlickoTheme.mint : FlickoTheme.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected
                ? FlickoTheme.teal.withValues(alpha: 0.42)
                : FlickoTheme.line,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected) ...[
              const Icon(
                Icons.check_rounded,
                size: 15,
                color: FlickoTheme.tealDark,
              ),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                color: selected ? FlickoTheme.tealDark : FlickoTheme.ink,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SafetyNotice extends StatelessWidget {
  const SafetyNotice({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return HealthCard(
      highlighted: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.verified_user_outlined,
            color: FlickoTheme.tealDark,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: FlickoTheme.tealDark,
                fontSize: 12.5,
                height: 1.36,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    required this.label,
    required this.controller,
    this.hintText,
    this.icon,
    this.keyboardType,
    this.obscureText = false,
    this.textCapitalization = TextCapitalization.none,
    this.validator,
  });

  final String label;
  final TextEditingController controller;
  final String? hintText;
  final IconData? icon;
  final TextInputType? keyboardType;
  final bool obscureText;
  final TextCapitalization textCapitalization;
  final FormFieldValidator<String>? validator;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      textCapitalization: textCapitalization,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        hintText: hintText,
        prefixIcon: icon == null
            ? null
            : Align(
                widthFactor: 1,
                heightFactor: 1,
                child: Padding(
                  padding: const EdgeInsetsDirectional.only(start: 11, end: 9),
                  child: ProfileFieldIcon(icon: icon!),
                ),
              ),
        prefixIconConstraints: icon == null
            ? null
            : const BoxConstraints(minWidth: 48, minHeight: 48),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.92),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(
            color: FlickoTheme.teal.withValues(alpha: 0.12),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(
            color: FlickoTheme.teal.withValues(alpha: 0.12),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: FlickoTheme.teal, width: 1.4),
        ),
      ),
    );
  }
}

class ProfileFieldIcon extends StatelessWidget {
  const ProfileFieldIcon({super.key, required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFE5F7F0), Color(0xFFF6FFFB)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: Colors.white.withValues(alpha: 0.92)),
        boxShadow: [
          BoxShadow(
            color: FlickoTheme.teal.withValues(alpha: 0.10),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Icon(icon, color: FlickoTheme.tealDark, size: 16),
    );
  }
}

class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;

    return SizedBox(
      width: double.infinity,
      height: 52,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: enabled ? FlickoTheme.teal : FlickoTheme.line,
          boxShadow: enabled
              ? [
                  BoxShadow(
                    color: FlickoTheme.teal.withValues(alpha: 0.20),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ]
              : null,
        ),
        child: FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Colors.transparent,
            disabledBackgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            textStyle: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
          onPressed: onPressed,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
              if (icon != null) ...[
                const SizedBox(width: 8),
                Icon(icon, size: 18),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class SecondaryButton extends StatelessWidget {
  const SecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: FlickoTheme.mint.withValues(alpha: 0.80),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: FlickoTheme.teal.withValues(alpha: 0.12),
              ),
              boxShadow: [
                BoxShadow(
                  color: FlickoTheme.teal.withValues(alpha: 0.08),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: FlickoTheme.ink,
                side: BorderSide.none,
                backgroundColor: Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                textStyle: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
              onPressed: onPressed,
              child: Text(label, overflow: TextOverflow.ellipsis),
            ),
          ),
        ),
      ),
    );
  }
}

class FlowDots extends StatelessWidget {
  const FlowDots({super.key, required this.activeIndex, required this.count});

  final int activeIndex;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var index = 0; index < count; index++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: index == activeIndex ? 20 : 6,
            height: 6,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            decoration: BoxDecoration(
              color: index == activeIndex
                  ? FlickoTheme.teal
                  : const Color(0xFFCBD8D2),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
      ],
    );
  }
}

class HealthScoreCard extends StatelessWidget {
  const HealthScoreCard({super.key, required this.activePlan});

  final String activePlan;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: FlickoTheme.darkPanel,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 112,
            height: 112,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: 0.74,
                  strokeWidth: 10,
                  backgroundColor: Colors.white.withValues(alpha: 0.12),
                  valueColor: const AlwaysStoppedAnimation(Color(0xFF7FE0D0)),
                  strokeCap: StrokeCap.round,
                ),
                const Text(
                  '74',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  activePlan,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 19,
                    height: 1.15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Today focuses on protein at lunch, post-meal movement, and sleep consistency.',
                  style: TextStyle(
                    color: Colors.white70,
                    height: 1.38,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class MiniActionCard extends StatelessWidget {
  const MiniActionCard({
    super.key,
    required this.title,
    required this.meta,
    required this.body,
    this.highlighted = false,
  });

  final String title;
  final String meta;
  final String body;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return HealthCard(
      highlighted: highlighted,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Text(
                meta,
                style: TextStyle(
                  color: highlighted ? FlickoTheme.tealDark : FlickoTheme.muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: const TextStyle(
              color: FlickoTheme.muted,
              fontSize: 13,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class TaskRow extends StatelessWidget {
  const TaskRow({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    required this.time,
  });

  final IconData icon;
  final String title;
  final String body;
  final String time;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: FlickoTheme.line)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: FlickoTheme.surfaceSoft,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: FlickoTheme.tealDark, size: 19),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 3),
                Text(
                  body,
                  style: const TextStyle(
                    color: FlickoTheme.muted,
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            time,
            style: const TextStyle(
              color: FlickoTheme.mutedLight,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class ChatBubble extends StatelessWidget {
  const ChatBubble({super.key, required this.text, required this.mine});

  final String text;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 340),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: mine ? FlickoTheme.teal : FlickoTheme.surface,
          borderRadius: BorderRadius.circular(8),
          border: mine ? null : Border.all(color: FlickoTheme.line),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: mine ? Colors.white : FlickoTheme.ink,
            height: 1.42,
            fontWeight: mine ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
