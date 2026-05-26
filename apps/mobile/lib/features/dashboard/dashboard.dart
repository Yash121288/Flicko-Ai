import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../flicko_motion.dart';
import 'ai_call_memory.dart';
import 'ai_call_models.dart';
import 'ai_call_warmup.dart';
import 'ai_health_call_page.dart';
import '../bmi/bmi_meter_dialog.dart';
import '../bmi/bmi_snapshot.dart';
import '../logs/health_log_entry.dart';
import '../management/flicko_care_task.dart';
import '../meals/meal_analysis_entry.dart';
import '../reminders/flicko_saved_reminder.dart';
import '../safety/flicko_safety_engine.dart';
import 'ai_coach_chat_view.dart';
import 'dashboard_management_view.dart';
import 'dashboard_live_insights.dart';
import 'dashboard_profile_page.dart';
import 'dashboard_reports_view.dart';
import 'gemini_health_chat_client.dart';
import 'live_call_foreground_service.dart';
import 'meal_photo_analysis_page.dart';

class DashboardUserProfile {
  const DashboardUserProfile({
    required this.firstName,
    required this.profileContext,
    required this.selectedProblems,
    required this.onEditProfile,
    this.onEditProblems,
    this.fullName = '',
    this.phone = '',
    this.email = '',
    this.emergencyContactName = '',
    this.emergencyContactPhone = '',
    this.age = '',
    this.heightCm = '',
    this.heightFeet = '',
    this.heightInches = '',
    this.weightKg = '',
    this.weightLb = '',
    this.foodPreference = '',
    this.intakeSummary = '',
    this.intakeCompleted = false,
    this.hasCompletedAiSetupCall = false,
    this.dashboardNotes = const <String>[],
    this.reminders = const <String>[],
    this.reports = const <String>[],
    this.backendDashboardSummary = const <String, Object?>{},
    this.healthLogs = const <HealthLogEntry>[],
    this.mealAnalyses = const <MealAnalysisEntry>[],
    this.safetyEvents = const <FlickoSafetyEvent>[],
    this.savedReminders = const <FlickoSavedReminder>[],
    this.careTasks = const <FlickoCareTask>[],
    this.onAddHealthLog,
    this.onSaveMealAnalysis,
    this.onSafetyEvent,
    this.onSendReminderNotification,
    this.onSaveReminder,
    this.onDeleteReminder,
    this.onSaveCareTask,
    this.onDeleteCareTask,
    this.onCreateReport,
    this.onMedicalReportExtracted,
    this.onCallCompleted,
    this.onFetchBackendAiContext,
    this.onResolveReportOpenUrl,
    this.shouldShowBmiIntro = false,
    this.onBmiIntroShown,
    this.onLogout,
    this.onRefresh,
    this.chatHistory = const <AiCoachMessage>[],
    this.onChatHistoryChanged,
    this.autoOpenReportUploadRequestId = 0,
    this.bmiSnapshot,
  });

  final String firstName;
  final String profileContext;
  final Set<String> selectedProblems;
  final VoidCallback onEditProfile;
  final VoidCallback? onEditProblems;
  final String fullName;
  final String phone;
  final String email;
  final String emergencyContactName;
  final String emergencyContactPhone;
  final String age;
  final String heightCm;
  final String heightFeet;
  final String heightInches;
  final String weightKg;
  final String weightLb;
  final String foodPreference;
  final String intakeSummary;
  final bool intakeCompleted;
  final bool hasCompletedAiSetupCall;
  final List<String> dashboardNotes;
  final List<String> reminders;
  final List<String> reports;
  final Map<String, Object?> backendDashboardSummary;
  final List<HealthLogEntry> healthLogs;
  final List<MealAnalysisEntry> mealAnalyses;
  final List<FlickoSafetyEvent> safetyEvents;
  final List<FlickoSavedReminder> savedReminders;
  final List<FlickoCareTask> careTasks;
  final ValueChanged<HealthLogEntry>? onAddHealthLog;
  final MealAnalysisWriter? onSaveMealAnalysis;
  final FlickoSafetyEventWriter? onSafetyEvent;
  final ValueChanged<String>? onSendReminderNotification;
  final FlickoSavedReminderWriter? onSaveReminder;
  final FlickoSavedReminderDeleter? onDeleteReminder;
  final FlickoCareTaskWriter? onSaveCareTask;
  final FlickoCareTaskDeleter? onDeleteCareTask;
  final DashboardReportCreator? onCreateReport;
  final MedicalReportSaver? onMedicalReportExtracted;
  final ValueChanged<AiCallSessionSummary>? onCallCompleted;
  final Future<String> Function({
    required String problemName,
    required String text,
  })?
  onFetchBackendAiContext;
  final DashboardReportOpenUrlResolver? onResolveReportOpenUrl;
  final bool shouldShowBmiIntro;
  final VoidCallback? onBmiIntroShown;
  final VoidCallback? onLogout;
  final Future<void> Function()? onRefresh;
  final List<AiCoachMessage> chatHistory;
  final ValueChanged<List<AiCoachMessage>>? onChatHistoryChanged;
  final int autoOpenReportUploadRequestId;
  final BmiSnapshot? bmiSnapshot;

  bool get backendDashboardReady {
    final value = backendDashboardSummary['dashboard_ready'];
    if (value is bool) {
      return value;
    }
    return value?.toString().toLowerCase() == 'true';
  }

  bool get hasRealDashboardData {
    return backendDashboardReady &&
        intakeCompleted &&
        intakeSummary.trim().isNotEmpty;
  }
}

class ProblemDashboardScreen extends StatefulWidget {
  const ProblemDashboardScreen({
    super.key,
    required this.profile,
    DateTime Function()? nowProvider,
  }) : nowProvider = nowProvider ?? DateTime.now;

  final DashboardUserProfile profile;
  final DateTime Function() nowProvider;

  @override
  State<ProblemDashboardScreen> createState() => _ProblemDashboardScreenState();
}

class _ProblemDashboardScreenState extends State<ProblemDashboardScreen> {
  int _tab = 0;
  late bool _dashboardReady;
  bool _dashboardProcessing = false;
  bool _bmiShown = false;
  bool _callEndedTooEarly = false;
  int _reportUploadRequestId = 0;
  final LiveCallForegroundService _foregroundService =
      const LiveCallForegroundService();

  @override
  void initState() {
    super.initState();
    _dashboardReady = widget.profile.hasRealDashboardData;
    _dashboardProcessing =
        widget.profile.hasCompletedAiSetupCall && !_dashboardReady;
    _primeCallWarmup();
  }

  @override
  void didUpdateWidget(covariant ProblemDashboardScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profile.profileContext != widget.profile.profileContext ||
        oldWidget.profile.intakeCompleted != widget.profile.intakeCompleted ||
        oldWidget.profile.selectedProblems != widget.profile.selectedProblems) {
      _primeCallWarmup();
    }
    if (widget.profile.hasRealDashboardData && !_dashboardReady) {
      setState(() {
        _dashboardReady = true;
        _dashboardProcessing = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _showBmiOnce());
      return;
    }
    if (!_dashboardReady &&
        widget.profile.hasCompletedAiSetupCall &&
        !_dashboardProcessing) {
      setState(() => _dashboardProcessing = true);
    }
  }

  DashboardConfig get _config {
    final problem = DashboardProblemResolver.primaryProblem(
      widget.profile.selectedProblems,
    );
    return DashboardProblemResolver.configFor(problem);
  }

  void _primeCallWarmup() {
    unawaited(_prepareCallWarmup());
  }

  AiCallInviteSpec _defaultCallSpec() {
    return widget.profile.intakeCompleted ||
            widget.profile.hasCompletedAiSetupCall
        ? AiCallInviteSpec.dailyRoutine(
            firstName: widget.profile.firstName,
            problemName: _config.problemName,
            initiatedByUser: true,
          )
        : AiCallInviteSpec.setup(
            firstName: widget.profile.firstName,
            problemName: _config.problemName,
            initiatedByUser: true,
          );
  }

  Future<AiCallWarmupBundle> _prepareCallWarmup({AiCallInviteSpec? spec}) {
    final callSpec = spec ?? _defaultCallSpec();
    final future = AiCallWarmupService.instance.prepare(
      problemName: _config.problemName,
      profileContext: widget.profile.profileContext,
      reason: callSpec.reason,
      memoryIntent: callSpec.memoryIntent,
      callPurpose: callSpec.subtitle,
      initiatedByUser: callSpec.initiatedByUser,
      onLoadBackendContext: () => _fetchBackendAiContext(callSpec.memoryIntent),
    );
    return future;
  }

  Future<void> _openProfilePage() async {
    await Navigator.of(context).push<void>(
      FlickoPageRoute(
        builder: (profilePageContext) => DashboardProfilePage(
          data: DashboardProfileData(
            firstName: widget.profile.firstName,
            fullName: widget.profile.fullName,
            phone: widget.profile.phone,
            email: widget.profile.email,
            emergencyContactName: widget.profile.emergencyContactName,
            emergencyContactPhone: widget.profile.emergencyContactPhone,
            age: widget.profile.age,
            heightCm: widget.profile.heightCm,
            heightFeet: widget.profile.heightFeet,
            heightInches: widget.profile.heightInches,
            weightKg: widget.profile.weightKg,
            weightLb: widget.profile.weightLb,
            foodPreference: widget.profile.foodPreference,
            selectedProblems: widget.profile.selectedProblems.toList()..sort(),
            primaryProblem: _config.problemName,
            activePlanLabel: '${_config.problemName} care plan active',
            profileContext: widget.profile.profileContext,
            bmiSnapshot: widget.profile.bmiSnapshot,
          ),
          onEditProfile: () {
            Navigator.of(profilePageContext).pop();
            widget.profile.onEditProfile();
          },
          onEditProblems: () {
            Navigator.of(profilePageContext).pop();
            (widget.profile.onEditProblems ?? widget.profile.onEditProfile)
                .call();
          },
          onLogout: () {
            Navigator.of(profilePageContext).pop();
            widget.profile.onLogout?.call();
          },
        ),
      ),
    );
  }

  void _waitForBackendDashboard({int tab = 0}) {
    setState(() {
      _dashboardProcessing = true;
      _callEndedTooEarly = false;
      _tab = tab;
    });
  }

  Future<void> _openCallPage() async {
    if (_callEndedTooEarly) {
      setState(() => _callEndedTooEarly = false);
    }
    final inviteSpec =
        widget.profile.intakeCompleted || widget.profile.hasCompletedAiSetupCall
        ? AiCallInviteSpec.dailyRoutine(
            firstName: widget.profile.firstName,
            problemName: _config.problemName,
            initiatedByUser: true,
          )
        : AiCallInviteSpec.setup(
            firstName: widget.profile.firstName,
            problemName: _config.problemName,
            initiatedByUser: true,
          );
    final warmup = await _prepareCallWarmup(spec: inviteSpec);
    if (!mounted) {
      return;
    }
    await prestartWarmLiveCall(
      foregroundService: _foregroundService,
      warmup: warmup,
      apiKey: kFlickoGeminiApiKey,
      model: kFlickoGeminiNativeAudioModel,
      voiceName: kFlickoGeminiNativeAudioVoice,
      problemName: _config.problemName,
      baseUri: const String.fromEnvironment('FLICKO_GEMINI_LIVE_WS_URL'),
    );
    if (!mounted) {
      return;
    }
    final startedAt = DateTime.now();
    var callTranscript = const <HealthCallTranscriptEntry>[];
    final result = await Navigator.of(context).push<AiHealthCallResult>(
      FlickoPageRoute(
        builder: (context) => AiHealthCallPage(
          problemName: _config.problemName,
          profileContext: widget.profile.profileContext,
          prewarmedProfileContext: warmup.profileContext,
          prewarmedOpeningScript: warmup.openingScript,
          reason: inviteSpec.reason,
          emergencyContactName: widget.profile.emergencyContactName,
          emergencyContactPhone: widget.profile.emergencyContactPhone,
          userName: widget.profile.firstName,
          onSafetyEvent: widget.profile.onSafetyEvent,
          onLoadBackendContext: () =>
              _fetchBackendAiContext(inviteSpec.memoryIntent),
          onCallTranscriptReady: (transcript) {
            callTranscript = transcript;
          },
        ),
      ),
    );
    if (!mounted || result == null) {
      return;
    }
    final endedAt = DateTime.now();
    final duration = endedAt.difference(startedAt);
    if (!_callHasEnoughSetupSignal(duration, callTranscript)) {
      setState(() {
        _callEndedTooEarly = true;
        if (result == AiHealthCallResult.openChatUploadReport) {
          _tab = 1;
          _reportUploadRequestId++;
        }
      });
      return;
    }
    widget.profile.onCallCompleted?.call(
      AiCallSessionSummary(
        problemName: _config.problemName,
        reason: inviteSpec.reason,
        startedAt: startedAt,
        endedAt: endedAt,
        duration: duration,
        inviteMemoryIntent: inviteSpec.memoryIntent,
        memorySummary: HealthCallMemorySummary.fromSession(
          problemName: _config.problemName,
          reason: inviteSpec.reason.payloadKey,
          reasonTitle: inviteSpec.reason.title,
          startedAt: startedAt,
          endedAt: endedAt,
          duration: duration,
          inviteMemoryIntent: inviteSpec.memoryIntent,
          transcript: callTranscript,
        ),
      ),
    );
    switch (result) {
      case AiHealthCallResult.ended:
        _waitForBackendDashboard();
      case AiHealthCallResult.openChat:
        _waitForBackendDashboard(tab: 1);
      case AiHealthCallResult.openChatUploadReport:
        setState(() {
          _dashboardProcessing = true;
          _callEndedTooEarly = false;
          _tab = 1;
          _reportUploadRequestId++;
        });
    }
  }

  bool _callHasEnoughSetupSignal(
    Duration duration,
    List<HealthCallTranscriptEntry> transcript,
  ) {
    final userLineCount = transcript
        .where((entry) => entry.isUser && entry.text.trim().length >= 8)
        .length;
    return userLineCount >= 2 || duration.inSeconds >= 120;
  }

  Future<void> _openMealAnalysisPage() async {
    await Navigator.of(context).push<void>(
      FlickoPageRoute(
        builder: (context) => MealPhotoAnalysisPage(
          firstName: widget.profile.firstName,
          problemName: _config.problemName,
          profileContext: widget.profile.profileContext,
          history: widget.profile.mealAnalyses,
          onSaveAnalysis:
              widget.profile.onSaveMealAnalysis ?? (_) async => false,
        ),
      ),
    );
  }

  Future<void> _refreshDashboard() async {
    final refresher = widget.profile.onRefresh;
    if (refresher == null) {
      return;
    }
    await refresher();
  }

  Future<String> _fetchBackendAiContext(String text) async {
    final loader = widget.profile.onFetchBackendAiContext;
    if (loader == null) {
      return '';
    }
    return loader(problemName: _config.problemName, text: text);
  }

  DashboardLiveInsights _liveInsightsFor(DashboardConfig config) {
    return DashboardLiveInsights.fromData(
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
      mealAnalyses: widget.profile.mealAnalyses,
      healthLogs: widget.profile.healthLogs,
      savedReminders: widget.profile.savedReminders,
      careTasks: widget.profile.careTasks,
      backendSummary: widget.profile.backendDashboardSummary,
      now: widget.nowProvider(),
    );
  }

  void _showBmiOnce() {
    if (!mounted ||
        _bmiShown ||
        !_dashboardReady ||
        !widget.profile.shouldShowBmiIntro) {
      return;
    }
    final snapshot = widget.profile.bmiSnapshot;
    if (snapshot == null) {
      return;
    }
    _bmiShown = true;
    widget.profile.onBmiIntroShown?.call();
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (context) => BmiMeterDialog(snapshot: snapshot),
    );
  }

  @override
  Widget build(BuildContext context) {
    final config = _config;
    final insights = _liveInsightsFor(config);
    final body = switch (_tab) {
      0 =>
        _dashboardReady
            ? DashboardReadyView(
                profile: widget.profile,
                config: config,
                insights: insights,
                onOpenProfile: _openProfilePage,
                onOpenMealAnalysis: _openMealAnalysisPage,
                onOpenAiCoach: () => setState(() => _tab = 1),
                onOpenManagement: () => setState(() => _tab = 2),
                onOpenReports: () => setState(() => _tab = 3),
              )
            : DashboardCallSetupView(
                profile: widget.profile,
                config: config,
                processing: _dashboardProcessing,
                showEarlyCallWarning: _callEndedTooEarly,
                onCallNow: _openCallPage,
                onOpenProfile: _openProfilePage,
                onOpenNotifications: () => setState(() => _tab = 2),
                onRefresh: _refreshDashboard,
              ),
      1 => AiCoachChatView(
        firstName: widget.profile.firstName,
        problemName: config.problemName,
        aiPrompt: config.aiPrompt,
        aiAssetPath: config.aiAssetPath,
        profileContext: widget.profile.profileContext,
        initialMessages: widget.profile.chatHistory,
        onMessagesChanged: widget.profile.onChatHistoryChanged,
        onSafetyEvent: widget.profile.onSafetyEvent,
        emergencyContactName: widget.profile.emergencyContactName,
        emergencyContactPhone: widget.profile.emergencyContactPhone,
        onCallNow: _openCallPage,
        onBack: () => setState(() => _tab = 0),
        onLoadBackendContext: (userText) => _fetchBackendAiContext(userText),
        onMedicalReportExtracted: widget.profile.onMedicalReportExtracted,
        autoOpenReportUploadRequestId:
            widget.profile.autoOpenReportUploadRequestId +
            _reportUploadRequestId,
      ),
      2 => DashboardManagementView(
        problemName: config.problemName,
        subtitle: '${config.problemName} routines, reminders, and logs.',
        healthLogs: widget.profile.healthLogs,
        onAddLog: widget.profile.onAddHealthLog ?? (_) {},
        onSendReminderNotification:
            widget.profile.onSendReminderNotification ?? (_) {},
        savedReminders: widget.profile.savedReminders,
        careTasks: widget.profile.careTasks,
        onSaveReminder: widget.profile.onSaveReminder ?? (_) async => false,
        onDeleteReminder: widget.profile.onDeleteReminder ?? (_) async => false,
        onSaveCareTask: widget.profile.onSaveCareTask ?? (_) async => false,
        onDeleteCareTask: widget.profile.onDeleteCareTask ?? (_) async => false,
        intakeSummary: widget.profile.intakeSummary,
        reminders: widget.profile.reminders,
        dashboardNotes: widget.profile.dashboardNotes,
        defaultMetricTitle: config.metricTitle,
        defaultMetricIcon: config.metricIcon,
        defaultMetricStatus: config.metricStatus,
        nowProvider: widget.nowProvider,
      ),
      _ => DashboardReportsView(
        firstName: widget.profile.firstName,
        problemName: config.problemName,
        reports: widget.profile.reports,
        fallbackTitle: config.reportTitle,
        fallbackBody: config.reportBody,
        dashboardNotes: widget.profile.dashboardNotes,
        reminders: widget.profile.reminders,
        healthLogCount: widget.profile.healthLogs.length,
        mealAnalysisCount: insights.mealCount,
        averageMealScore: insights.averageMealScore,
        highRiskMealCount: insights.highRiskMealCount,
        careTaskCount: widget.profile.careTasks.length,
        onCreateReport: widget.profile.onCreateReport,
        onResolveOpenUrl: widget.profile.onResolveReportOpenUrl,
      ),
    };

    final refreshableBody = _tab == 1
        ? body
        : RefreshIndicator(
            color: const Color(0xFF149447),
            backgroundColor: Colors.white,
            displacement: 46,
            strokeWidth: 2.8,
            notificationPredicate: (notification) {
              return notification.metrics.axis == Axis.vertical;
            },
            onRefresh: _refreshDashboard,
            child: body,
          );

    return Scaffold(
      backgroundColor: const Color(0xFFFBFCF8),
      body: refreshableBody,
      bottomNavigationBar: _tab == 1
          ? null
          : DashboardBottomNav(
              selectedIndex: _tab,
              onChanged: (value) => setState(() => _tab = value),
            ),
    );
  }
}

class DashboardCallSetupView extends StatelessWidget {
  const DashboardCallSetupView({
    super.key,
    required this.profile,
    required this.config,
    required this.processing,
    required this.showEarlyCallWarning,
    required this.onCallNow,
    required this.onOpenProfile,
    required this.onOpenNotifications,
    required this.onRefresh,
  });

  final DashboardUserProfile profile;
  final DashboardConfig config;
  final bool processing;
  final bool showEarlyCallWarning;
  final VoidCallback onCallNow;
  final VoidCallback onOpenProfile;
  final VoidCallback onOpenNotifications;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return DashboardScaffoldBody(
      profile: profile,
      activePlanLabel: '${config.problemName} care plan active',
      onOpenProfile: onOpenProfile,
      onOpenNotifications: onOpenNotifications,
      child: Expanded(
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          padding: const EdgeInsets.only(bottom: 18),
          child: Center(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(22, 24, 22, 22),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFF7FFF9), Color(0xFFEAF7EE)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: const Color(0xFFD9E9DF)),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF168878).withValues(alpha: 0.13),
                    blurRadius: 30,
                    offset: const Offset(0, 18),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 82,
                    height: 82,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: const Color(
                            0xFF168878,
                          ).withValues(alpha: 0.16),
                          blurRadius: 22,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Icon(
                      processing
                          ? Icons.dashboard_customize_rounded
                          : Icons.phone_in_talk_rounded,
                      color: const Color(0xFF168878),
                      size: 38,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    processing
                        ? 'Building your real dashboard'
                        : 'AI health call preparing',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFF0B372D),
                      fontSize: 23,
                      height: 1.05,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 9),
                  Text(
                    processing
                        ? 'Flicko is saving the call memory, syncing Django, and waiting for backend-ready ${config.problemName.toLowerCase()} dashboard values.'
                        : 'Within 3 minutes, Flicko AI can call and build your ${config.problemName.toLowerCase()} dashboard.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFF51625C),
                      fontSize: 13.2,
                      height: 1.45,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 18),
                  processing
                      ? const DashboardProcessingPill()
                      : const DashboardCountdownPill(),
                  if (showEarlyCallWarning) ...[
                    const SizedBox(height: 14),
                    const DashboardCallWarningCard(),
                  ],
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF149447),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                      onPressed: processing
                          ? () => unawaited(onRefresh())
                          : onCallNow,
                      icon: Icon(
                        processing ? Icons.sync_rounded : Icons.call_rounded,
                      ),
                      label: Text(
                        processing ? 'Refresh status' : 'Call now',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    processing
                        ? 'No dummy cards are shown here. Real dashboard opens only after backend confirms setup data is ready.'
                        : 'If you cut the call early, setup will not count and Flicko will keep the 3-minute call active.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFF7A8782),
                      fontSize: 11.3,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class DashboardReadyView extends StatelessWidget {
  const DashboardReadyView({
    super.key,
    required this.profile,
    required this.config,
    required this.insights,
    required this.onOpenProfile,
    required this.onOpenMealAnalysis,
    required this.onOpenAiCoach,
    required this.onOpenManagement,
    required this.onOpenReports,
  });

  final DashboardUserProfile profile;
  final DashboardConfig config;
  final DashboardLiveInsights insights;
  final VoidCallback onOpenProfile;
  final VoidCallback onOpenMealAnalysis;
  final VoidCallback onOpenAiCoach;
  final VoidCallback onOpenManagement;
  final VoidCallback onOpenReports;

  @override
  Widget build(BuildContext context) {
    return DashboardScaffoldBody(
      profile: profile,
      activePlanLabel: '${config.problemName} care plan active',
      onOpenProfile: onOpenProfile,
      onOpenNotifications: onOpenManagement,
      child: Expanded(
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          padding: const EdgeInsets.only(bottom: 18),
          child: Column(
            children: [
              DashboardScoreCard(config: config, insights: insights),
              if (insights.hasSafetyWarning) ...[
                const SizedBox(height: 12),
                DashboardSafetyWarningCard(insights: insights),
              ],
              const SizedBox(height: 15),
              DashboardCardGrid(
                config: config,
                insights: insights,
                onPhotoCheck: onOpenMealAnalysis,
                onPlan: onOpenManagement,
                onAiCoach: onOpenAiCoach,
                onReminder: onOpenManagement,
                onReport: onOpenReports,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class DashboardSafetyWarningCard extends StatelessWidget {
  const DashboardSafetyWarningCard({super.key, required this.insights});

  final DashboardLiveInsights insights;

  @override
  Widget build(BuildContext context) {
    final urgent =
        insights.safetySeverity.toLowerCase() == 'urgent' ||
        insights.safetySeverity.toLowerCase() == 'emergency';
    final color = urgent ? const Color(0xFFC83E32) : const Color(0xFF9A6B00);
    final background = urgent
        ? const Color(0xFFFFF1EF)
        : const Color(0xFFFFF8E7);
    final border = urgent ? const Color(0xFFF1B8B1) : const Color(0xFFF0D899);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            urgent
                ? Icons.warning_amber_rounded
                : Icons.health_and_safety_outlined,
            color: color,
            size: 21,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  insights.safetyTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontSize: 13.5,
                    height: 1.2,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (insights.safetyAction.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    insights.safetyAction,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: color.withValues(alpha: 0.86),
                      fontSize: 12.2,
                      height: 1.3,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class DashboardCallWarningCard extends StatelessWidget {
  const DashboardCallWarningCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E7),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFF0D899)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, color: Color(0xFF9A6B00), size: 20),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Call ended before enough setup details were captured. Flicko will keep the 3-minute setup call active.',
              style: TextStyle(
                color: Color(0xFF725311),
                fontSize: 12.2,
                height: 1.32,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class DashboardScaffoldBody extends StatelessWidget {
  const DashboardScaffoldBody({
    super.key,
    required this.profile,
    required this.activePlanLabel,
    required this.onOpenProfile,
    required this.onOpenNotifications,
    required this.child,
  });

  final DashboardUserProfile profile;
  final String activePlanLabel;
  final VoidCallback onOpenProfile;
  final VoidCallback onOpenNotifications;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final firstName = profile.firstName.trim().isEmpty
        ? 'Guest'
        : profile.firstName.trim();
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DashboardHeader(
              firstName: firstName,
              onOpenProfile: onOpenProfile,
              onOpenNotifications: onOpenNotifications,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: const BoxDecoration(
                    color: Color(0xFF149447),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.shield_rounded,
                    color: Colors.white,
                    size: 15,
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    activePlanLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF51625C),
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 19),
            child,
          ],
        ),
      ),
    );
  }
}

class DashboardHeader extends StatelessWidget {
  const DashboardHeader({
    super.key,
    required this.firstName,
    required this.onOpenProfile,
    required this.onOpenNotifications,
  });

  final String firstName;
  final VoidCallback onOpenProfile;
  final VoidCallback onOpenNotifications;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Image.asset(
          'assets/images/mainlogo.png',
          width: 52,
          height: 52,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) {
            return const Icon(
              Icons.favorite_rounded,
              color: Color(0xFF149447),
              size: 45,
            );
          },
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            'Good morning, $firstName',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF0B372D),
              fontSize: 18.5,
              height: 1.08,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Stack(
          clipBehavior: Clip.none,
          children: [
            DashboardRoundButton(
              icon: Icons.notifications_none_rounded,
              onPressed: onOpenNotifications,
            ),
            Positioned(
              right: 5,
              top: 4,
              child: Container(
                width: 6.5,
                height: 6.5,
                decoration: const BoxDecoration(
                  color: Color(0xFFFF5A24),
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(width: 8),
        Tooltip(
          message: 'Open profile',
          child: GestureDetector(
            onTap: onOpenProfile,
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: const Color(0xFFE8EFEA),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2.2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 11,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: const Icon(
                Icons.person_rounded,
                color: Color(0xFF0B372D),
                size: 21,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class DashboardRoundButton extends StatelessWidget {
  const DashboardRoundButton({
    super.key,
    required this.icon,
    required this.onPressed,
  });

  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 36,
      height: 36,
      child: IconButton(
        style: IconButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF0B372D),
          shadowColor: Colors.black.withValues(alpha: 0.10),
          elevation: 8,
        ),
        onPressed: onPressed,
        icon: Icon(icon, size: 20),
      ),
    );
  }
}

class DashboardScoreCard extends StatelessWidget {
  const DashboardScoreCard({
    super.key,
    required this.config,
    required this.insights,
  });

  final DashboardConfig config;
  final DashboardLiveInsights insights;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final ringSize = constraints.maxWidth < 360 ? 112.0 : 128.0;
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(20, 20, 16, 19),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFFFFFFF), Color(0xFFECFFF4), Color(0xFFDDF3E7)],
              stops: [0.0, 0.55, 1.0],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: const Color(0xFFD1E7D8)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF149447).withValues(alpha: 0.13),
                blurRadius: 30,
                offset: const Offset(0, 16),
              ),
              BoxShadow(
                color: Colors.white.withValues(alpha: 0.95),
                blurRadius: 10,
                offset: const Offset(-3, -3),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            config.scoreTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF10231D),
                              fontSize: 15.2,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(
                          Icons.info_outline_rounded,
                          color: Color(0xFF7B8A85),
                          size: 17,
                        ),
                      ],
                    ),
                    const SizedBox(height: 19),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          insights.score.toString(),
                          style: const TextStyle(
                            color: Color(0xFF149447),
                            fontSize: 50,
                            height: 0.9,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(width: 5),
                        const Padding(
                          padding: EdgeInsets.only(bottom: 5),
                          child: Text(
                            '/ 100',
                            style: TextStyle(
                              color: Color(0xFF25352F),
                              fontSize: 21,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 13),
                    Text(
                      insights.scoreStatus,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF149447),
                        fontSize: 14.8,
                        height: 1.2,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: ringSize,
                height: ringSize,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CustomPaint(
                      size: Size(ringSize - 10, ringSize - 10),
                      painter: DashboardProgressRingPainter(
                        progress: insights.score / 100,
                      ),
                    ),
                    Container(
                      width: ringSize * 0.43,
                      height: ringSize * 0.43,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 14,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Icon(
                        config.scoreIcon,
                        color: const Color(0xFF0C7D3B),
                        size: ringSize * 0.22,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class DashboardCardGrid extends StatelessWidget {
  const DashboardCardGrid({
    super.key,
    required this.config,
    required this.insights,
    required this.onPhotoCheck,
    required this.onPlan,
    required this.onAiCoach,
    required this.onReminder,
    required this.onReport,
  });

  final DashboardConfig config;
  final DashboardLiveInsights insights;
  final VoidCallback onPhotoCheck;
  final VoidCallback onPlan;
  final VoidCallback onAiCoach;
  final VoidCallback onReminder;
  final VoidCallback onReport;

  @override
  Widget build(BuildContext context) {
    final cards = [
      DashboardMetricCard(config: config, insights: insights),
      DashboardPlanCard(config: config, insights: insights, onTap: onPlan),
      DashboardAiCoachCard(config: config, onTap: onAiCoach),
      DashboardReminderCard(config: config, onTap: onReminder),
      DashboardPhotoCheckCard(
        config: config,
        insights: insights,
        onTap: onPhotoCheck,
      ),
      DashboardReportCard(config: config, insights: insights, onTap: onReport),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final gap = 13.0;
        final columns = constraints.maxWidth < 330 ? 1 : 2;
        final width = columns == 1
            ? constraints.maxWidth
            : (constraints.maxWidth - gap) / 2;
        return Wrap(
          spacing: gap,
          runSpacing: 13,
          children: [
            for (final card in cards) SizedBox(width: width, child: card),
          ],
        );
      },
    );
  }
}

class DashboardMetricCard extends StatelessWidget {
  const DashboardMetricCard({
    super.key,
    required this.config,
    required this.insights,
  });

  final DashboardConfig config;
  final DashboardLiveInsights insights;

  @override
  Widget build(BuildContext context) {
    return DashboardMiniCard(
      height: 260,
      icon: config.metricIcon,
      title: config.metricTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 9),
          RichText(
            text: TextSpan(
              text: insights.metricValue,
              style: const TextStyle(
                color: Color(0xFF0B372D),
                fontSize: 25,
                fontWeight: FontWeight.w900,
              ),
              children: [
                TextSpan(
                  text: insights.metricUnit.trim().isEmpty
                      ? ''
                      : ' ${insights.metricUnit}',
                  style: const TextStyle(
                    color: Color(0xFF25352F),
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 7),
          Text(
            insights.metricStatus,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF149447),
              fontSize: 13,
              height: 1.25,
              fontWeight: FontWeight.w900,
            ),
          ),
          const Spacer(),
          if (config.metricAssetPath == null)
            SizedBox(
              width: double.infinity,
              height: 86,
              child: CustomPaint(painter: DashboardLineChartPainter()),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final imageWidth = math.min(112.0, constraints.maxWidth * 0.74);
                return Align(
                  alignment: Alignment.bottomRight,
                  child: DashboardAssetImage(
                    assetPath: config.metricAssetPath!,
                    width: imageWidth,
                    height: imageWidth * 0.75,
                    borderRadius: 24,
                    fit: BoxFit.cover,
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

class DashboardPlanCard extends StatelessWidget {
  const DashboardPlanCard({
    super.key,
    required this.config,
    required this.insights,
    required this.onTap,
  });

  final DashboardConfig config;
  final DashboardLiveInsights insights;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return DashboardMiniCard(
      height: 260,
      icon: config.planIcon,
      title: config.planTitle,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final imageSize = math.min(110.0, constraints.maxWidth * 0.58);
          final textWidth = constraints.maxWidth * 0.58;
          return Stack(
            children: [
              Positioned(
                right: -imageSize * 0.20,
                top: constraints.maxHeight * 0.22,
                child: DashboardAssetImage(
                  assetPath: config.planAssetPath,
                  width: imageSize,
                  height: imageSize,
                  shape: BoxShape.circle,
                  fit: BoxFit.cover,
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 20),
                  Text(
                    config.planSubtitle,
                    style: const TextStyle(
                      color: Color(0xFF51625C),
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 7),
                  SizedBox(
                    width: textWidth,
                    child: Text(
                      insights.planFocus,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF10231D),
                        fontSize: 14.5,
                        height: 1.18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(height: 9),
                  SizedBox(
                    width: textWidth,
                    child: Text(
                      insights.planNote,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF51625C),
                        fontSize: 12,
                        height: 1.25,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const Spacer(),
                  DashboardSmallButton(label: config.planCta, onTap: onTap),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class DashboardAiCoachCard extends StatelessWidget {
  const DashboardAiCoachCard({
    super.key,
    required this.config,
    required this.onTap,
  });

  final DashboardConfig config;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return DashboardMiniCard(
      height: 192,
      title: config.aiTitle,
      leading: DashboardAvatarAsset(assetPath: config.aiAssetPath),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 7),
          Text(
            config.aiPrompt,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF25352F),
              fontSize: 14.2,
              height: 1.28,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
          DashboardSoftButton(
            icon: Icons.chat_bubble_outline_rounded,
            label: 'Start AI chat',
            onTap: onTap,
          ),
        ],
      ),
    );
  }
}

class DashboardReminderCard extends StatelessWidget {
  const DashboardReminderCard({
    super.key,
    required this.config,
    required this.onTap,
  });

  final DashboardConfig config;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: onTap,
      child: DashboardMiniCard(
        height: 192,
        icon: config.reminderIcon,
        title: config.reminderTitle,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 20),
                  Text(
                    config.reminderMain,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF10231D),
                      fontSize: 16.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Icon(
                        Icons.schedule_rounded,
                        color: Color(0xFF51625C),
                        size: 18,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        config.reminderTime,
                        style: const TextStyle(
                          color: Color(0xFF25352F),
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Stack(
              clipBehavior: Clip.none,
              children: [
                DashboardAssetImage(
                  assetPath: config.reminderAssetPath,
                  width: 58,
                  height: 58,
                  borderRadius: 20,
                  fit: BoxFit.cover,
                ),
                Positioned(
                  right: -3,
                  bottom: -3,
                  child: Container(
                    width: 25,
                    height: 25,
                    decoration: const BoxDecoration(
                      color: Color(0xFFDDF2E3),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check_rounded,
                      color: Color(0xFF149447),
                      size: 17,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class DashboardPhotoCheckCard extends StatelessWidget {
  const DashboardPhotoCheckCard({
    super.key,
    required this.config,
    required this.insights,
    required this.onTap,
  });

  final DashboardConfig config;
  final DashboardLiveInsights insights;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(23),
        child: DashboardMiniCard(
          height: 212,
          icon: config.checkIcon,
          title: config.checkTitle,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final imageSize = math.min(105.0, constraints.maxWidth * 0.56);
              return Stack(
                children: [
                  Positioned(
                    right: -imageSize * 0.22,
                    bottom: -imageSize * 0.14,
                    child: DashboardAssetImage(
                      assetPath: config.checkAssetPath,
                      width: imageSize,
                      height: imageSize,
                      shape: BoxShape.circle,
                      fit: BoxFit.cover,
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 12),
                      SizedBox(
                        width: constraints.maxWidth * 0.58,
                        child: Text(
                          insights.checkBody,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF25352F),
                            fontSize: 13.5,
                            height: 1.33,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const Spacer(),
                      DashboardSmallButton(label: config.checkCta, soft: true),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class DashboardReportCard extends StatelessWidget {
  const DashboardReportCard({
    super.key,
    required this.config,
    required this.insights,
    required this.onTap,
  });

  final DashboardConfig config;
  final DashboardLiveInsights insights;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return DashboardMiniCard(
      height: 212,
      icon: Icons.article_outlined,
      title: config.reportTitle,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final reportWidth = math.min(76.0, constraints.maxWidth * 0.42);
          return Stack(
            children: [
              Positioned(
                right: -3,
                bottom: 0,
                child: DashboardAssetImage(
                  assetPath: config.reportAssetPath,
                  width: reportWidth,
                  height: reportWidth * 1.29,
                  borderRadius: 13,
                  fit: BoxFit.cover,
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 12),
                  SizedBox(
                    width: constraints.maxWidth * 0.58,
                    child: Text(
                      insights.reportBody,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF25352F),
                        fontSize: 13.5,
                        height: 1.33,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const Spacer(),
                  DashboardSmallButton(
                    label: 'View report',
                    soft: true,
                    onTap: onTap,
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class DashboardMiniCard extends StatelessWidget {
  const DashboardMiniCard({
    super.key,
    required this.title,
    required this.child,
    required this.height,
    this.icon,
    this.leading,
  });

  final String title;
  final Widget child;
  final double height;
  final IconData? icon;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      padding: const EdgeInsets.fromLTRB(15, 15, 15, 15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(23),
        border: Border.all(color: const Color(0xFFE3EAE6)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              leading ??
                  DashboardIconBubble(
                    icon: icon ?? Icons.favorite_border_rounded,
                  ),
              const SizedBox(width: 11),
              Expanded(
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF10231D),
                    fontSize: 15,
                    height: 1.05,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class DashboardSimpleTab extends StatelessWidget {
  const DashboardSimpleTab({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.cards,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final List<Widget> cards;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                DashboardIconBubble(icon: icon),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: Color(0xFF0B372D),
                          fontSize: 24,
                          height: 1.05,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: Color(0xFF65736F),
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Expanded(
              child: ListView.separated(
                itemCount: cards.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, index) => cards[index],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class DashboardTextCard extends StatelessWidget {
  const DashboardTextCard({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    required this.cta,
  });

  final IconData icon;
  final String title;
  final String body;
  final String cta;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(23),
        border: Border.all(color: const Color(0xFFE3EAE6)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DashboardIconBubble(icon: icon),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF10231D),
                    fontSize: 16.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  body,
                  style: const TextStyle(
                    color: Color(0xFF51625C),
                    fontSize: 13,
                    height: 1.38,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 13),
                DashboardSmallButton(label: cta, soft: true),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class DashboardBottomNav extends StatelessWidget {
  const DashboardBottomNav({
    super.key,
    required this.selectedIndex,
    required this.onChanged,
  });

  final int selectedIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final items = const [
      (Icons.dashboard_customize_rounded, 'Dashboard'),
      (Icons.auto_awesome_rounded, 'AI Coach'),
      (Icons.health_and_safety_rounded, 'Management'),
      (Icons.query_stats_rounded, 'Reports'),
    ];
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 7, 16, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(25)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            for (var i = 0; i < items.length; i++)
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onChanged(i),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOutCubic,
                        width: selectedIndex == i ? 39 : 35,
                        height: selectedIndex == i ? 36 : 33,
                        decoration: BoxDecoration(
                          gradient: selectedIndex == i
                              ? const LinearGradient(
                                  colors: [
                                    Color(0xFF19B456),
                                    Color(0xFF0D7D3C),
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                )
                              : null,
                          color: selectedIndex == i
                              ? null
                              : const Color(0xFFF1F6F3),
                          borderRadius: BorderRadius.circular(13),
                          boxShadow: selectedIndex == i
                              ? [
                                  BoxShadow(
                                    color: const Color(
                                      0xFF149447,
                                    ).withValues(alpha: 0.20),
                                    blurRadius: 12,
                                    offset: const Offset(0, 6),
                                  ),
                                ]
                              : null,
                        ),
                        child: Icon(
                          items[i].$1,
                          size: selectedIndex == i ? 21 : 20,
                          color: selectedIndex == i
                              ? Colors.white
                              : const Color(0xFF59645F),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        items[i].$2,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: selectedIndex == i
                              ? const Color(0xFF149447)
                              : const Color(0xFF4D5654),
                          fontSize: 10,
                          fontWeight: selectedIndex == i
                              ? FontWeight.w900
                              : FontWeight.w700,
                        ),
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

class DashboardCountdownPill extends StatelessWidget {
  const DashboardCountdownPill({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFD8E9DE)),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.timer_outlined, color: Color(0xFF149447), size: 21),
          SizedBox(width: 8),
          Text(
            '3 min',
            style: TextStyle(
              color: Color(0xFF0B372D),
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class DashboardProcessingPill extends StatelessWidget {
  const DashboardProcessingPill({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFD8E9DE)),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2.4,
              color: Color(0xFF149447),
            ),
          ),
          SizedBox(width: 9),
          Text(
            'Syncing setup',
            style: TextStyle(
              color: Color(0xFF0B372D),
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class DashboardIconBubble extends StatelessWidget {
  const DashboardIconBubble({super.key, required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 49,
      height: 49,
      decoration: const BoxDecoration(
        color: Color(0xFFDFF3E5),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: Color(0xFF149447), size: 25),
    );
  }
}

class DashboardAvatarPlaceholder extends StatelessWidget {
  const DashboardAvatarPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 58,
      height: 58,
      decoration: const BoxDecoration(
        color: Color(0xFFDFF3E5),
        shape: BoxShape.circle,
      ),
      child: const Icon(
        Icons.medical_information_outlined,
        color: Color(0xFF149447),
        size: 31,
      ),
    );
  }
}

class DashboardAvatarAsset extends StatelessWidget {
  const DashboardAvatarAsset({super.key, required this.assetPath});

  final String assetPath;

  @override
  Widget build(BuildContext context) {
    return DashboardAssetImage(
      assetPath: assetPath,
      width: 58,
      height: 58,
      shape: BoxShape.circle,
      fit: BoxFit.cover,
    );
  }
}

class DashboardAssetImage extends StatelessWidget {
  const DashboardAssetImage({
    super.key,
    required this.assetPath,
    required this.width,
    required this.height,
    this.shape = BoxShape.rectangle,
    this.borderRadius = 18,
    this.fit = BoxFit.contain,
  });

  final String assetPath;
  final double width;
  final double height;
  final BoxShape shape;
  final double borderRadius;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final radius = shape == BoxShape.rectangle
        ? BorderRadius.circular(borderRadius)
        : null;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        shape: shape,
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Image.asset(
        assetPath,
        fit: fit,
        errorBuilder: (context, error, stackTrace) {
          return Container(
            decoration: BoxDecoration(
              color: const Color(0xFFEAF7EE),
              shape: shape,
              borderRadius: radius,
            ),
            child: const Icon(Icons.image_outlined, color: Color(0xFF149447)),
          );
        },
      ),
    );
  }
}

class DashboardImagePlaceholder extends StatelessWidget {
  const DashboardImagePlaceholder({
    super.key,
    required this.icon,
    required this.size,
  });

  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFFEAF7EE),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Icon(icon, color: const Color(0xFF149447), size: size * 0.36),
    );
  }
}

class DashboardPdfPlaceholder extends StatelessWidget {
  const DashboardPdfPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 76,
      height: 98,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(13),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 15,
            offset: const Offset(0, 9),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          Text(
            'PDF',
            style: TextStyle(
              color: Color(0xFFE63737),
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
          SizedBox(height: 9),
          Icon(Icons.insert_chart_outlined_rounded, color: Color(0xFF149447)),
          SizedBox(height: 5),
          _PdfLine(width: 38),
          SizedBox(height: 4),
          _PdfLine(width: 28),
        ],
      ),
    );
  }
}

class _PdfLine extends StatelessWidget {
  const _PdfLine({required this.width});

  final double width;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: 4,
      decoration: BoxDecoration(
        color: const Color(0xFFE2E9E5),
        borderRadius: BorderRadius.circular(99),
      ),
    );
  }
}

class DashboardSmallButton extends StatelessWidget {
  const DashboardSmallButton({
    super.key,
    required this.label,
    this.soft = false,
    this.onTap,
  });

  final String label;
  final bool soft;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(12);
    return Material(
      color: soft ? const Color(0xFFDFF3E5) : const Color(0xFF149447),
      borderRadius: radius,
      child: InkWell(
        borderRadius: radius,
        onTap: onTap,
        child: Container(
          height: 41,
          padding: const EdgeInsets.symmetric(horizontal: 17),
          alignment: Alignment.center,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: soft ? const Color(0xFF0B5B2D) : Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
    );
  }
}

class DashboardSoftButton extends StatelessWidget {
  const DashboardSoftButton({
    super.key,
    required this.icon,
    required this.label,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(12);
    return Material(
      color: const Color(0xFFDFF3E5),
      borderRadius: radius,
      child: InkWell(
        borderRadius: radius,
        onTap: onTap,
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 13),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: const Color(0xFF149447), size: 18),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF0B5B2D),
                    fontSize: 12.2,
                    fontWeight: FontWeight.w900,
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

class DashboardProgressRingPainter extends CustomPainter {
  const DashboardProgressRingPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final stroke = size.width * 0.085;
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFFD9F0DF);
    final active = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFF149447);
    canvas.drawArc(
      rect.deflate(stroke),
      -math.pi / 2,
      math.pi * 2,
      false,
      base,
    );
    canvas.drawArc(
      rect.deflate(stroke),
      -math.pi / 2,
      math.pi * 2 * progress.clamp(0, 1),
      false,
      active,
    );
  }

  @override
  bool shouldRepaint(covariant DashboardProgressRingPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

class DashboardLineChartPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = const Color(0xFFE3EAE6)
      ..strokeWidth = 1;
    for (final y in [0.18, 0.50, 0.82]) {
      canvas.drawLine(
        Offset(0, size.height * y),
        Offset(size.width, size.height * y),
        gridPaint,
      );
    }

    final points = [
      const Offset(0.00, 0.64),
      const Offset(0.13, 0.48),
      const Offset(0.25, 0.60),
      const Offset(0.37, 0.44),
      const Offset(0.50, 0.35),
      const Offset(0.63, 0.55),
      const Offset(0.76, 0.34),
      const Offset(0.88, 0.48),
      const Offset(1.00, 0.52),
    ].map((p) => Offset(p.dx * size.width, p.dy * size.height)).toList();
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    final fillPath = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      fillPath,
      Paint()..color = const Color(0xFF149447).withValues(alpha: 0.08),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFF149447)
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke,
    );
    for (final point in points) {
      canvas.drawCircle(point, 3.5, Paint()..color = const Color(0xFF149447));
    }
    canvas.drawCircle(points.last, 7, Paint()..color = const Color(0xFFDFF3E5));
    canvas.drawCircle(
      points.last,
      3.2,
      Paint()..color = const Color(0xFF149447),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class DashboardAssetPaths {
  const DashboardAssetPaths._();

  static const mealPlan = 'assets/images/dashboard/meal_plan.png';
  static const aiCoach = 'assets/images/dashboard/ai_coach.png';
  static const weightScale = 'assets/images/dashboard/weight_scale.png';
  static const medicine = 'assets/images/dashboard/medicine.png';
  static const weeklyReport = 'assets/images/dashboard/weekly_report.png';
}

class DashboardConfig {
  const DashboardConfig({
    required this.problemName,
    required this.scoreTitle,
    required this.score,
    required this.scoreStatus,
    required this.scoreIcon,
    required this.metricIcon,
    required this.metricTitle,
    required this.metricValue,
    required this.metricUnit,
    required this.metricStatus,
    required this.planIcon,
    required this.planTitle,
    required this.planSubtitle,
    required this.planFocus,
    required this.planNote,
    required this.planCta,
    required this.aiTitle,
    required this.aiPrompt,
    required this.reminderIcon,
    required this.reminderTitle,
    required this.reminderMain,
    required this.reminderTime,
    required this.reminderBody,
    required this.checkIcon,
    required this.checkTitle,
    required this.checkBody,
    required this.checkCta,
    required this.reportTitle,
    required this.reportBody,
    this.metricAssetPath,
    this.planAssetPath = DashboardAssetPaths.mealPlan,
    this.aiAssetPath = DashboardAssetPaths.aiCoach,
    this.reminderAssetPath = DashboardAssetPaths.medicine,
    this.checkAssetPath = DashboardAssetPaths.mealPlan,
    this.reportAssetPath = DashboardAssetPaths.weeklyReport,
  });

  final String problemName;
  final String scoreTitle;
  final int score;
  final String scoreStatus;
  final IconData scoreIcon;
  final IconData metricIcon;
  final String metricTitle;
  final String metricValue;
  final String metricUnit;
  final String metricStatus;
  final IconData planIcon;
  final String planTitle;
  final String planSubtitle;
  final String planFocus;
  final String planNote;
  final String planCta;
  final String aiTitle;
  final String aiPrompt;
  final IconData reminderIcon;
  final String reminderTitle;
  final String reminderMain;
  final String reminderTime;
  final String reminderBody;
  final IconData checkIcon;
  final String checkTitle;
  final String checkBody;
  final String checkCta;
  final String reportTitle;
  final String reportBody;
  final String? metricAssetPath;
  final String planAssetPath;
  final String aiAssetPath;
  final String reminderAssetPath;
  final String checkAssetPath;
  final String reportAssetPath;
}

class DashboardProblemResolver {
  const DashboardProblemResolver._();

  static const supportedProblems = [
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

  static const _priority = [
    'Heart health',
    'Blood pressure',
    'Diabetes Type 1',
    'Pregnancy',
    'Diabetes Type 2',
    'Thyroid',
    'PCOS/PCOD',
    'Cholesterol',
    'Weight management',
    'Preconception',
    'Postpartum',
    'Autoimmune support',
    'Senior care',
    'Sexual health',
    'Digestive health',
    'Acidity and bloating',
    'Sleep health',
    'Stress and mood',
    'Fitness',
    'Skin and hair',
    "Women's wellness",
    'Habit reset',
    'General wellness',
  ];

  static String primaryProblem(Set<String> selectedProblems) {
    if (selectedProblems.isEmpty) {
      return 'General wellness';
    }
    for (final problem in _priority) {
      if (selectedProblems.contains(problem)) {
        return problem;
      }
    }
    final customProblems =
        selectedProblems
            .where((problem) => !supportedProblems.contains(problem))
            .toList()
          ..sort();
    if (customProblems.isNotEmpty) {
      return customProblems.first;
    }
    if (selectedProblems.contains('Other problem')) {
      return 'Other problem';
    }
    return selectedProblems.first;
  }

  static DashboardConfig configFor(String problem) {
    switch (problem) {
      case 'Diabetes Type 1':
      case 'Diabetes Type 2':
        return _diabetes(
          problem == 'Diabetes Type 1' ? 'Type 1 diabetes' : 'Diabetes',
          type1: problem == 'Diabetes Type 1',
        );
      case 'Weight management':
        return _weight();
      case 'Blood pressure':
        return _bp();
      case 'Heart health':
        return _heart();
      case 'PCOS/PCOD':
        return _simple(
          problemName: 'PCOS',
          scoreTitle: "Today's PCOS Balance Score",
          metricIcon: Icons.calendar_month_rounded,
          metricTitle: 'Cycle & cravings',
          metricValue: '7',
          metricUnit: 'day',
          metricStatus: 'Protein and low-GI meals needed',
          planFocus: 'Low-GI dinner',
          reminderMain: 'Evening walk',
          checkTitle: 'Meal insulin check',
          reportTitle: 'PCOS Report',
        );
      case 'Thyroid':
        return _simple(
          problemName: 'Thyroid',
          scoreTitle: "Today's Thyroid Routine Score",
          metricIcon: Icons.bolt_rounded,
          metricTitle: 'Energy',
          metricValue: '6',
          metricUnit: '/10',
          metricStatus: 'Track fatigue and medicine timing',
          planFocus: 'Protein breakfast',
          reminderMain: 'Thyroid medicine',
          checkTitle: 'Symptom Log',
          reportTitle: 'Thyroid Report',
        );
      case 'Pregnancy':
        return _simple(
          problemName: 'Pregnancy',
          scoreTitle: "Today's Pregnancy Wellness Score",
          metricIcon: Icons.water_drop_outlined,
          metricTitle: 'Hydration',
          metricValue: '5',
          metricUnit: 'cups',
          metricStatus: 'Add fluids and iron-rich meal',
          planFocus: 'Safe meal',
          reminderMain: 'Prenatal vitamin',
          checkTitle: 'Nutrition Check',
          reportTitle: 'Pregnancy Report',
        );
      case 'Preconception':
        return _simple(
          problemName: 'Preconception',
          scoreTitle: "Today's Fertility Prep Score",
          metricIcon: Icons.event_available_rounded,
          metricTitle: 'Cycle Window',
          metricValue: 'Day 12',
          metricUnit: '',
          metricStatus: 'Folic acid and sleep routine active',
          planFocus: 'Fertility meal',
          reminderMain: 'Folic acid',
          checkTitle: 'Cycle Log',
          reportTitle: 'Preconception Report',
        );
      case 'Postpartum':
        return _simple(
          problemName: 'Postpartum',
          scoreTitle: "Today's Recovery Score",
          metricIcon: Icons.child_friendly_rounded,
          metricTitle: 'Recovery',
          metricValue: '68',
          metricUnit: '/100',
          metricStatus: 'Watch sleep, mood, and hydration',
          planFocus: 'Recovery meal',
          reminderMain: 'Hydration',
          checkTitle: 'Mood & Sleep Log',
          reportTitle: 'Postpartum Report',
        );
      case 'Digestive health':
      case 'Acidity and bloating':
        return _simple(
          problemName: problem,
          scoreTitle: "Today's Gut Relief Score",
          metricIcon: Icons.spa_outlined,
          metricTitle: 'Gut comfort',
          metricValue: '72',
          metricUnit: '/100',
          metricStatus: 'Avoid late spicy meals',
          planFocus: 'Low-trigger lunch',
          reminderMain: 'Meal timing',
          checkTitle: 'Trigger Check',
          reportTitle: 'Gut Report',
        );
      case 'Sleep health':
        return _simple(
          problemName: 'Sleep',
          scoreTitle: "Today's Sleep Readiness Score",
          metricIcon: Icons.nightlight_round,
          metricTitle: 'Sleep',
          metricValue: '6.5',
          metricUnit: 'hr',
          metricStatus: 'Caffeine cutoff needed',
          planFocus: 'Wind-down plan',
          reminderMain: 'Sleep routine',
          checkTitle: 'Sleep Log',
          reportTitle: 'Sleep Report',
        );
      case 'Stress and mood':
        return _simple(
          problemName: 'Stress and mood',
          scoreTitle: "Today's Calm Score",
          metricIcon: Icons.mood_outlined,
          metricTitle: 'Mood',
          metricValue: '7',
          metricUnit: '/10',
          metricStatus: 'Good, add breathing break',
          planFocus: 'Grounding plan',
          reminderMain: 'Breathing',
          checkTitle: 'Mood Log',
          reportTitle: 'Mood Report',
        );
      case 'Fitness':
        return _simple(
          problemName: 'Fitness',
          scoreTitle: "Today's Fitness Score",
          metricIcon: Icons.directions_run_rounded,
          metricTitle: 'Steps',
          metricValue: '6.2k',
          metricUnit: '',
          metricStatus: 'Strength session pending',
          planFocus: 'Strength + walk',
          reminderMain: 'Workout',
          checkTitle: 'Exercise Log',
          reportTitle: 'Fitness Report',
        );
      case 'Skin and hair':
        return _simple(
          problemName: 'Skin and hair',
          scoreTitle: "Today's Skin/Hair Score",
          metricIcon: Icons.face_retouching_natural,
          metricTitle: 'Hydration',
          metricValue: '4',
          metricUnit: 'cups',
          metricStatus: 'Improve sleep and hydration',
          planFocus: 'Skin nutrition',
          reminderMain: 'Routine',
          checkTitle: 'Photo Progress',
          reportTitle: 'Skin/Hair Report',
        );
      case 'General wellness':
        return _simple(
          problemName: 'Wellness',
          scoreTitle: "Today's Wellness Score",
          metricIcon: Icons.eco_outlined,
          metricTitle: 'Habit Score',
          metricValue: '79',
          metricUnit: '/100',
          metricStatus: 'Hydration, movement, and sleep are active',
          planFocus: 'Balanced routine',
          reminderMain: 'Daily check-in',
          checkTitle: 'Wellness Log',
          reportTitle: 'Wellness Report',
        );
      case "Women's wellness":
        return _simple(
          problemName: "Women's wellness",
          scoreTitle: "Today's Cycle Wellness Score",
          metricIcon: Icons.female_rounded,
          metricTitle: 'Cycle',
          metricValue: 'Day 21',
          metricUnit: '',
          metricStatus: 'Energy and cramps tracking ready',
          planFocus: 'Cycle-aware meal',
          reminderMain: 'Cycle log',
          checkTitle: 'Symptom Log',
          reportTitle: "Women's Wellness Report",
        );
      case 'Senior care':
        return _simple(
          problemName: 'Senior care',
          scoreTitle: "Today's Care Score",
          metricIcon: Icons.medication_outlined,
          metricTitle: 'Adherence',
          metricValue: '86',
          metricUnit: '%',
          metricStatus: 'Medicine reminder active',
          planFocus: 'Easy meal',
          reminderMain: 'Medicine',
          checkTitle: 'Care Check',
          reportTitle: 'Senior Care Report',
        );
      case 'Sexual health':
        return _simple(
          problemName: 'Sexual health',
          scoreTitle: "Today's Private Health Score",
          metricIcon: Icons.lock_outline_rounded,
          metricTitle: 'Privacy Check',
          metricValue: 'Ready',
          metricUnit: '',
          metricStatus: 'Private coaching and referral boundary active',
          planFocus: 'Private care plan',
          reminderMain: 'Private check-in',
          checkTitle: 'Symptom Log',
          reportTitle: 'Private Health Report',
        );
      case 'Autoimmune support':
        return _simple(
          problemName: 'Autoimmune support',
          scoreTitle: "Today's Flare Control Score",
          metricIcon: Icons.shield_outlined,
          metricTitle: 'Flare Level',
          metricValue: '3',
          metricUnit: '/10',
          metricStatus: 'Pacing, sleep, and trigger watch active',
          planFocus: 'Anti-inflammatory meal',
          reminderMain: 'Rest window',
          checkTitle: 'Flare Log',
          reportTitle: 'Autoimmune Report',
        );
      case 'Cholesterol':
        return _simple(
          problemName: 'Cholesterol',
          scoreTitle: "Today's Cholesterol Score",
          metricIcon: Icons.favorite_border_rounded,
          metricTitle: 'Fat score',
          metricValue: '74',
          metricUnit: '/100',
          metricStatus: 'Add fiber and reduce fried food',
          planFocus: 'Heart-friendly meal',
          reminderMain: 'Evening walk',
          checkTitle: 'Food Fat Check',
          reportTitle: 'Cholesterol Report',
        );
      case 'Habit reset':
        return _simple(
          problemName: 'Habit reset',
          scoreTitle: "Today's Habit Reset Score",
          metricIcon: Icons.restart_alt_rounded,
          metricTitle: 'Streak',
          metricValue: '4',
          metricUnit: 'days',
          metricStatus: 'Craving check and recovery plan ready',
          planFocus: 'Replacement habit',
          reminderMain: 'Evening reset',
          checkTitle: 'Craving Log',
          reportTitle: 'Habit Reset Report',
        );
      case 'Other problem':
        return _simple(
          problemName: 'Custom health',
          scoreTitle: "Today's Custom Health Score",
          metricIcon: Icons.add_rounded,
          metricTitle: 'AI Setup',
          metricValue: '76',
          metricUnit: '/100',
          metricStatus: 'AI will build the plan from your typed problem',
          planFocus: 'Custom plan',
          reminderMain: 'Custom check-in',
          checkTitle: 'Custom Log',
          reportTitle: 'Custom Report',
        );
      default:
        return _simple(
          problemName: problem,
          scoreTitle: "Today's Health Score",
          metricIcon: Icons.monitor_heart_outlined,
          metricTitle: 'Status',
          metricValue: '76',
          metricUnit: '/100',
          metricStatus: 'AI will personalize after call',
          planFocus: 'Next action',
          reminderMain: 'Check-in',
          checkTitle: 'Daily Log',
          reportTitle: '$problem Report',
        );
    }
  }

  static DashboardConfig _diabetes(String name, {required bool type1}) {
    return DashboardConfig(
      problemName: name,
      scoreTitle: "Today's Diabetes Score",
      score: 82,
      scoreStatus: 'Stable, needs meal consistency',
      scoreIcon: Icons.water_drop_outlined,
      metricIcon: Icons.water_drop_outlined,
      metricTitle: 'Blood Sugar',
      metricValue: '118',
      metricUnit: 'mg/dL',
      metricStatus: 'Normal after breakfast',
      planIcon: Icons.restaurant_menu_rounded,
      planTitle: 'Meal Plan',
      planSubtitle: 'Next meal:',
      planFocus: type1 ? 'Carb-counted meal' : 'High-protein lunch',
      planNote: type1
          ? 'Check carb load and glucose timing'
          : 'Avoid high sugar drinks',
      planCta: 'View plan',
      aiTitle: 'AI Coach',
      aiPrompt: type1
          ? 'Ask before meals, lows, exercise, or travel'
          : 'Ask Flicko before your next meal',
      reminderIcon: Icons.medication_rounded,
      reminderTitle: 'Medicine Reminder',
      reminderMain: type1 ? 'Insulin / glucose check' : 'Metformin',
      reminderTime: type1 ? 'Before meals' : '8:00 PM',
      reminderBody: type1
          ? 'Insulin timing, glucose checks, and hypo safety.'
          : 'Medication timing and glucose checks.',
      checkIcon: Icons.photo_camera_outlined,
      checkTitle: 'Photo Meal Check',
      checkBody: 'Upload meal photo\nAI will score eat / avoid',
      checkCta: 'Check now',
      reportTitle: 'Weekly Report',
      reportBody: type1
          ? 'Glucose PDF\nHypo/hyper notes ready'
          : 'Doctor-ready PDF\n3 insights ready',
    );
  }

  static DashboardConfig _weight() {
    return const DashboardConfig(
      problemName: 'Weight management',
      scoreTitle: "Today's Weight Score",
      score: 78,
      scoreStatus: 'Good, improve protein consistency',
      scoreIcon: Icons.monitor_weight_outlined,
      metricIcon: Icons.monitor_weight_outlined,
      metricTitle: 'Weight Trend',
      metricValue: '-0.6',
      metricUnit: 'kg',
      metricStatus: 'Down this week',
      planIcon: Icons.restaurant_menu_rounded,
      planTitle: 'Meal Plan',
      planSubtitle: 'Next meal:',
      planFocus: 'High-protein lunch',
      planNote: 'Stay inside calorie target',
      planCta: 'View plan',
      aiTitle: 'AI Coach',
      aiPrompt: 'Ask before cravings or dinner',
      reminderIcon: Icons.directions_walk_rounded,
      reminderTitle: 'Activity Reminder',
      reminderMain: '20 min walk',
      reminderTime: '7:00 PM',
      reminderBody: 'Walking and hydration reminders.',
      checkIcon: Icons.photo_camera_outlined,
      checkTitle: 'Photo Meal Check',
      checkBody: 'Upload meal photo\nAI will score calories',
      checkCta: 'Check now',
      reportTitle: 'Weekly Report',
      reportBody: 'Weight PDF\nBMI insights ready',
      metricAssetPath: DashboardAssetPaths.weightScale,
    );
  }

  static DashboardConfig _bp() {
    return const DashboardConfig(
      problemName: 'Blood pressure',
      scoreTitle: "Today's BP Control Score",
      score: 80,
      scoreStatus: 'Stable, reduce sodium today',
      scoreIcon: Icons.favorite_border_rounded,
      metricIcon: Icons.speed_rounded,
      metricTitle: 'Blood Pressure',
      metricValue: '122/78',
      metricUnit: '',
      metricStatus: 'Normal morning reading',
      planIcon: Icons.restaurant_menu_rounded,
      planTitle: 'Meal Plan',
      planSubtitle: 'Next meal:',
      planFocus: 'Low-sodium lunch',
      planNote: 'Avoid packaged snacks',
      planCta: 'View plan',
      aiTitle: 'AI Coach',
      aiPrompt: 'Ask about salt, stress, or readings',
      reminderIcon: Icons.monitor_heart_outlined,
      reminderTitle: 'BP Reminder',
      reminderMain: 'BP reading',
      reminderTime: '9:00 PM',
      reminderBody: 'Measure blood pressure tonight.',
      checkIcon: Icons.edit_note_rounded,
      checkTitle: 'Reading Log',
      checkBody: 'Add BP reading\nAI checks trend',
      checkCta: 'Add log',
      reportTitle: 'Weekly Report',
      reportBody: 'BP PDF\nRisk notes ready',
    );
  }

  static DashboardConfig _heart() {
    return const DashboardConfig(
      problemName: 'Heart health',
      scoreTitle: "Today's Heart Score",
      score: 81,
      scoreStatus: 'Good, add heart-safe walk',
      scoreIcon: Icons.favorite_border_rounded,
      metricIcon: Icons.favorite_border_rounded,
      metricTitle: 'Heart Status',
      metricValue: '72',
      metricUnit: 'bpm',
      metricStatus: 'Resting HR is steady',
      planIcon: Icons.restaurant_menu_rounded,
      planTitle: 'Meal Plan',
      planSubtitle: 'Next meal:',
      planFocus: 'Heart-friendly lunch',
      planNote: 'Low oil, high fiber',
      planCta: 'View plan',
      aiTitle: 'AI Coach',
      aiPrompt: 'Ask before workout or oily meal',
      reminderIcon: Icons.medication_outlined,
      reminderTitle: 'Medicine Reminder',
      reminderMain: 'Heart meds',
      reminderTime: '8:00 PM',
      reminderBody: 'Medicine and movement routine.',
      checkIcon: Icons.document_scanner_outlined,
      checkTitle: 'Food Fat Check',
      checkBody: 'Scan food label\nAI flags fat/sodium',
      checkCta: 'Scan now',
      reportTitle: 'Weekly Report',
      reportBody: 'Heart PDF\n3 insights ready',
    );
  }

  static DashboardConfig _simple({
    required String problemName,
    required String scoreTitle,
    required IconData metricIcon,
    required String metricTitle,
    required String metricValue,
    required String metricUnit,
    required String metricStatus,
    required String planFocus,
    required String reminderMain,
    required String checkTitle,
    required String reportTitle,
  }) {
    return DashboardConfig(
      problemName: problemName,
      scoreTitle: scoreTitle,
      score: 76,
      scoreStatus: 'AI plan ready after daily check',
      scoreIcon: metricIcon,
      metricIcon: metricIcon,
      metricTitle: metricTitle,
      metricValue: metricValue,
      metricUnit: metricUnit,
      metricStatus: metricStatus,
      planIcon: Icons.restaurant_menu_rounded,
      planTitle: 'Care Plan',
      planSubtitle: 'Next step:',
      planFocus: planFocus,
      planNote: 'Built around your profile',
      planCta: 'View plan',
      aiTitle: 'AI Coach',
      aiPrompt: 'Ask Flicko before your next choice',
      reminderIcon: Icons.notifications_active_outlined,
      reminderTitle: 'Reminder',
      reminderMain: reminderMain,
      reminderTime: '8:00 PM',
      reminderBody: 'Condition-specific check-in reminder.',
      checkIcon: Icons.edit_note_rounded,
      checkTitle: checkTitle,
      checkBody: 'Add daily log\nAI checks pattern',
      checkCta: 'Check now',
      reportTitle: reportTitle,
      reportBody: 'Doctor-ready PDF\n3 insights ready',
    );
  }
}
