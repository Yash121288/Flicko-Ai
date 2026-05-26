import '../reminders/flicko_notification_service.dart';
import 'ai_call_models.dart';
import 'flicko_call_invite_coordinator.dart';

enum FlickoCallInviteDispatchAction {
  ignore,
  cancelActiveInvite,
  queuePending,
  retryDeclined,
  openInvite,
}

class FlickoCallInviteDispatchSnapshot {
  const FlickoCallInviteDispatchSnapshot({
    required this.callInviteRouteOpen,
    required this.liveCallInProgress,
    required this.canOpenDashboard,
    required this.firstName,
    required this.problemName,
  });

  final bool callInviteRouteOpen;
  final bool liveCallInProgress;
  final bool canOpenDashboard;
  final String firstName;
  final String problemName;
}

class FlickoCallInviteDispatchDecision {
  const FlickoCallInviteDispatchDecision({
    required this.action,
    this.spec,
    this.retryPlan,
    this.normalizedPayload = '',
  });

  final FlickoCallInviteDispatchAction action;
  final AiCallInviteSpec? spec;
  final FlickoRetryCallInvitePlan? retryPlan;
  final String normalizedPayload;
}

class FlickoCallInviteDispatchCoordinator {
  const FlickoCallInviteDispatchCoordinator({
    this.inviteCoordinator = const FlickoCallInviteCoordinator(),
  });

  final FlickoCallInviteCoordinator inviteCoordinator;

  FlickoCallInviteDispatchDecision decide({
    required String payload,
    required FlickoCallInviteDispatchSnapshot snapshot,
  }) {
    final cleanPayload = payload.trim();
    final isInvite = cleanPayload.startsWith(flickoCallInvitePayloadPrefix);
    final isDeclined = cleanPayload.startsWith(flickoCallDeclinedPayloadPrefix);
    if (!isInvite && !isDeclined) {
      return const FlickoCallInviteDispatchDecision(
        action: FlickoCallInviteDispatchAction.ignore,
      );
    }
    if (snapshot.callInviteRouteOpen || snapshot.liveCallInProgress) {
      return FlickoCallInviteDispatchDecision(
        action: isInvite
            ? FlickoCallInviteDispatchAction.cancelActiveInvite
            : FlickoCallInviteDispatchAction.ignore,
        normalizedPayload: cleanPayload,
      );
    }
    if (!snapshot.canOpenDashboard) {
      return FlickoCallInviteDispatchDecision(
        action: FlickoCallInviteDispatchAction.queuePending,
        normalizedPayload: cleanPayload,
      );
    }
    final specPayload = isDeclined
        ? '$flickoCallInvitePayloadPrefix${cleanPayload.substring(flickoCallDeclinedPayloadPrefix.length)}'
        : cleanPayload;
    final spec = AiCallInviteSpec.fromNotification(
      firstName: snapshot.firstName,
      problemName: snapshot.problemName,
      payload: specPayload,
    );
    if (isDeclined) {
      return FlickoCallInviteDispatchDecision(
        action: FlickoCallInviteDispatchAction.retryDeclined,
        spec: spec,
        retryPlan: inviteCoordinator.declinedNotificationRetryPlan(spec),
        normalizedPayload: specPayload,
      );
    }
    return FlickoCallInviteDispatchDecision(
      action: FlickoCallInviteDispatchAction.openInvite,
      spec: spec,
      normalizedPayload: specPayload,
    );
  }
}
