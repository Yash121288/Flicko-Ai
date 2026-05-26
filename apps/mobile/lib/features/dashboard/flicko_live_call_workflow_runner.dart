import 'ai_call_invite_page.dart';
import 'ai_call_memory.dart';
import 'ai_call_models.dart';
import 'ai_call_transcript_store.dart';
import 'ai_call_warmup.dart';
import 'ai_health_call_page.dart';
import 'flicko_call_invite_coordinator.dart';
import 'flicko_call_route_coordinator.dart';

class FlickoLiveCallPageRequest {
  const FlickoLiveCallPageRequest({
    required this.spec,
    required this.problemName,
    required this.profileContext,
    required this.prewarmedProfileContext,
    required this.prewarmedOpeningScript,
    required this.subtitle,
    required this.callSessionId,
    required this.startedAt,
    required this.playConnectTone,
  });

  final AiCallInviteSpec spec;
  final String problemName;
  final String profileContext;
  final String prewarmedProfileContext;
  final String prewarmedOpeningScript;
  final String subtitle;
  final String callSessionId;
  final DateTime startedAt;
  final bool playConnectTone;
}

class FlickoLiveCallPageOutcome {
  const FlickoLiveCallPageOutcome({
    required this.result,
    required this.transcript,
  });

  final AiHealthCallResult result;
  final List<HealthCallTranscriptEntry> transcript;
}

class FlickoLiveCallWorkflowOutcome {
  const FlickoLiveCallWorkflowOutcome({this.retryPlan, this.summary});

  final FlickoRetryCallInvitePlan? retryPlan;
  final AiCallSessionSummary? summary;
}

typedef FlickoShowInviteSheet =
    Future<AiCallInviteResponse?> Function(AiCallInviteSpec spec);
typedef FlickoPrepareLiveCallWarmup =
    Future<AiCallWarmupBundle> Function(
      AiCallInviteSpec spec,
      String profileContext,
    );
typedef FlickoPrestartWarmLiveCall =
    Future<void> Function(AiCallWarmupBundle warmup, String problemName);
typedef FlickoLaunchLiveCallPage =
    Future<FlickoLiveCallPageOutcome?> Function(
      FlickoLiveCallPageRequest request,
    );

class FlickoLiveCallWorkflowRunner {
  const FlickoLiveCallWorkflowRunner({
    this.inviteCoordinator = const FlickoCallInviteCoordinator(),
    this.routeCoordinator = const FlickoCallRouteCoordinator(),
  });

  final FlickoCallInviteCoordinator inviteCoordinator;
  final FlickoCallRouteCoordinator routeCoordinator;

  Future<FlickoLiveCallWorkflowOutcome> runInviteFlow({
    required AiCallInviteSpec spec,
    required String profileContext,
    required FlickoShowInviteSheet showInviteSheet,
    required Future<void> Function() beforeLiveCallStart,
    required FlickoPrepareLiveCallWarmup prepareWarmup,
    required FlickoPrestartWarmLiveCall prestartWarmLiveCall,
    required FlickoLaunchLiveCallPage launchCallPage,
  }) async {
    final response = await showInviteSheet(spec);
    final routeDecision = routeCoordinator.inviteResponseDecision(
      spec: spec,
      response: response,
    );
    if (routeDecision.action == FlickoInviteRouteAction.scheduleRetry) {
      return FlickoLiveCallWorkflowOutcome(retryPlan: routeDecision.retryPlan);
    }
    if (routeDecision.action != FlickoInviteRouteAction.accept) {
      return const FlickoLiveCallWorkflowOutcome();
    }
    await beforeLiveCallStart();
    return _runAcceptedFlow(
      spec: spec,
      problemName: spec.problemName,
      profileContext: profileContext,
      subtitle: spec.reason.title,
      playConnectTone: true,
      prepareWarmup: prepareWarmup,
      prestartWarmLiveCall: prestartWarmLiveCall,
      launchCallPage: launchCallPage,
    );
  }

  Future<FlickoLiveCallWorkflowOutcome> runResumeFlow({
    required AiCallTranscriptSessionDraft session,
    required String firstName,
    required String fallbackProblemName,
    required String fallbackProfileContext,
    required Future<void> Function() beforeLiveCallStart,
    required FlickoPrepareLiveCallWarmup prepareWarmup,
    required FlickoPrestartWarmLiveCall prestartWarmLiveCall,
    required FlickoLaunchLiveCallPage launchCallPage,
  }) async {
    final resumeContext = routeCoordinator.resumeContext(
      fallbackProblemName: fallbackProblemName,
      fallbackProfileContext: fallbackProfileContext,
      session: session,
      fallbackSubtitle: session.reason.title,
    );
    final spec = inviteCoordinator.resumeInviteSpec(
      firstName: firstName,
      problemName: resumeContext.problemName,
      reason: session.reason,
      subtitle: resumeContext.subtitle,
    );
    await beforeLiveCallStart();
    return _runAcceptedFlow(
      spec: spec,
      problemName: resumeContext.problemName,
      profileContext: resumeContext.profileContext,
      subtitle: resumeContext.subtitle,
      callSessionId: session.sessionId,
      startedAt: session.startedAt,
      playConnectTone: false,
      prepareWarmup: prepareWarmup,
      prestartWarmLiveCall: prestartWarmLiveCall,
      launchCallPage: launchCallPage,
    );
  }

  Future<FlickoLiveCallWorkflowOutcome> _runAcceptedFlow({
    required AiCallInviteSpec spec,
    required String problemName,
    required String profileContext,
    required String subtitle,
    required bool playConnectTone,
    required FlickoPrepareLiveCallWarmup prepareWarmup,
    required FlickoPrestartWarmLiveCall prestartWarmLiveCall,
    required FlickoLaunchLiveCallPage launchCallPage,
    String? callSessionId,
    DateTime? startedAt,
  }) async {
    final warmup = await prepareWarmup(spec, profileContext);
    await prestartWarmLiveCall(warmup, problemName);
    final effectiveStartedAt = startedAt ?? DateTime.now();
    final effectiveCallSessionId =
        callSessionId ??
        'call-${effectiveStartedAt.microsecondsSinceEpoch}-${spec.reason.payloadKey}';
    final pageOutcome = await launchCallPage(
      FlickoLiveCallPageRequest(
        spec: spec,
        problemName: problemName,
        profileContext: profileContext,
        prewarmedProfileContext: warmup.profileContext,
        prewarmedOpeningScript: warmup.openingScript,
        subtitle: subtitle,
        callSessionId: effectiveCallSessionId,
        startedAt: effectiveStartedAt,
        playConnectTone: playConnectTone,
      ),
    );
    if (pageOutcome == null) {
      return const FlickoLiveCallWorkflowOutcome();
    }
    final endedAt = DateTime.now();
    return FlickoLiveCallWorkflowOutcome(
      summary: routeCoordinator.buildCompletedSummary(
        problemName: problemName,
        reason: spec.reason,
        startedAt: effectiveStartedAt,
        endedAt: endedAt,
        inviteMemoryIntent: spec.memoryIntent,
        inviteSubtitle: spec.subtitle,
        transcript: pageOutcome.transcript,
      ),
    );
  }
}
