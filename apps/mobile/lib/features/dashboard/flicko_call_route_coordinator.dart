import 'ai_call_invite_page.dart';
import 'ai_call_memory.dart';
import 'ai_call_models.dart';
import 'ai_call_transcript_store.dart';
import 'flicko_call_invite_coordinator.dart';

enum FlickoInviteRouteAction { ignore, accept, scheduleRetry }

class FlickoInviteRouteDecision {
  const FlickoInviteRouteDecision({required this.action, this.retryPlan});

  final FlickoInviteRouteAction action;
  final FlickoRetryCallInvitePlan? retryPlan;
}

class FlickoResumeCallContext {
  const FlickoResumeCallContext({
    required this.problemName,
    required this.profileContext,
    required this.subtitle,
  });

  final String problemName;
  final String profileContext;
  final String subtitle;
}

class FlickoCallRouteCoordinator {
  const FlickoCallRouteCoordinator({
    this.inviteCoordinator = const FlickoCallInviteCoordinator(),
  });

  final FlickoCallInviteCoordinator inviteCoordinator;

  bool canOpenRoute({
    required bool callInviteRouteOpen,
    required bool liveCallInProgress,
  }) {
    return !callInviteRouteOpen && !liveCallInProgress;
  }

  FlickoInviteRouteDecision inviteResponseDecision({
    required AiCallInviteSpec spec,
    required AiCallInviteResponse? response,
  }) {
    if (response == null) {
      return const FlickoInviteRouteDecision(
        action: FlickoInviteRouteAction.ignore,
      );
    }
    switch (response.decision) {
      case AiCallInviteDecision.accept:
        return const FlickoInviteRouteDecision(
          action: FlickoInviteRouteAction.accept,
        );
      case AiCallInviteDecision.decline:
        return FlickoInviteRouteDecision(
          action: FlickoInviteRouteAction.scheduleRetry,
          retryPlan: inviteCoordinator.declinedInviteRetryPlan(
            spec,
            retryAfter: response.retryAfter,
            note: response.note,
          ),
        );
      case AiCallInviteDecision.later:
        return FlickoInviteRouteDecision(
          action: FlickoInviteRouteAction.scheduleRetry,
          retryPlan: inviteCoordinator.postponedInviteRetryPlan(
            spec,
            retryAfter: response.retryAfter,
            note: response.note,
          ),
        );
    }
  }

  FlickoResumeCallContext resumeContext({
    required String fallbackProblemName,
    required String fallbackProfileContext,
    required AiCallTranscriptSessionDraft session,
    required String fallbackSubtitle,
  }) {
    return FlickoResumeCallContext(
      problemName: session.problemName.trim().isEmpty
          ? fallbackProblemName
          : session.problemName.trim(),
      profileContext: session.profileContext.trim().isNotEmpty
          ? session.profileContext
          : fallbackProfileContext,
      subtitle: session.subtitle.trim().isEmpty
          ? fallbackSubtitle
          : session.subtitle.trim(),
    );
  }

  AiCallSessionSummary buildCompletedSummary({
    required String problemName,
    required AiCallInviteReason reason,
    required DateTime startedAt,
    required DateTime endedAt,
    required String inviteMemoryIntent,
    String inviteSubtitle = '',
    required List<HealthCallTranscriptEntry> transcript,
  }) {
    return AiCallSessionSummary(
      problemName: problemName,
      reason: reason,
      startedAt: startedAt,
      endedAt: endedAt,
      duration: endedAt.difference(startedAt),
      inviteMemoryIntent: inviteMemoryIntent,
      inviteSubtitle: inviteSubtitle,
      memorySummary: HealthCallMemorySummary.fromSession(
        problemName: problemName,
        reason: reason.payloadKey,
        reasonTitle: reason.title,
        startedAt: startedAt,
        endedAt: endedAt,
        duration: endedAt.difference(startedAt),
        inviteMemoryIntent: inviteMemoryIntent,
        transcript: transcript,
      ),
    );
  }
}
