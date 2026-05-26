import 'package:flutter_test/flutter_test.dart';

import 'package:flicko_health/features/dashboard/ai_call_models.dart';
import 'package:flicko_health/features/dashboard/flicko_call_invite_coordinator.dart';
import 'package:flicko_health/features/management/flicko_care_task.dart';
import 'package:flicko_health/features/meals/meal_analysis_entry.dart';

void main() {
  const coordinator = FlickoCallInviteCoordinator();

  group('FlickoCallInviteCoordinator', () {
    test('schedules first setup call for new user without prior invite', () {
      final now = DateTime.utc(2026, 5, 22, 9, 0);

      final plan = coordinator.proactivePlan(
        shouldOpenDashboardEntry: true,
        hasReturningUserHistory: false,
        callInviteRouteOpen: false,
        liveCallInProgress: false,
        inviteLog: const <String, String>{},
        firstName: 'Kartik',
        problemName: 'Diabetes',
        mealAnalyses: const <MealAnalysisEntry>[],
        careTasks: const <FlickoCareTask>[],
        now: now,
      );

      expect(plan, isNotNull);
      expect(plan!.spec.reason, AiCallInviteReason.setupIntake);
      expect(plan.scheduledAt, now.add(const Duration(minutes: 3)));
      expect(plan.auditTitle, 'First Flicko setup call scheduled');
    });

    test('schedules missed task follow-up for returning user', () {
      final now = DateTime.utc(2026, 5, 22, 18, 0);
      final task = FlickoCareTask(
        id: 'task-1',
        type: FlickoCareTaskType.medicine,
        title: 'Take thyroid medicine',
        detail: 'Before dinner',
        problemName: 'Thyroid',
        timeLabel: '5:30 PM',
        createdAt: now.subtract(const Duration(days: 1)),
        updatedAt: now.subtract(const Duration(days: 1)),
      );

      final plan = coordinator.proactivePlan(
        shouldOpenDashboardEntry: true,
        hasReturningUserHistory: true,
        callInviteRouteOpen: false,
        liveCallInProgress: false,
        inviteLog: const <String, String>{},
        firstName: 'Kartik',
        problemName: 'Thyroid',
        mealAnalyses: const <MealAnalysisEntry>[],
        careTasks: [task],
        now: now,
      );

      expect(plan, isNotNull);
      expect(plan!.spec.reason, AiCallInviteReason.missedCareTask);
      expect(plan.spec.subtitle, 'Take thyroid medicine');
      expect(plan.scheduledAt, now);
    });

    test('does not schedule proactive invite while a call route is open', () {
      final plan = coordinator.proactivePlan(
        shouldOpenDashboardEntry: true,
        hasReturningUserHistory: false,
        callInviteRouteOpen: true,
        liveCallInProgress: false,
        inviteLog: const <String, String>{},
        firstName: 'Kartik',
        problemName: 'Diabetes',
        mealAnalyses: const <MealAnalysisEntry>[],
        careTasks: const <FlickoCareTask>[],
        now: DateTime.utc(2026, 5, 22, 9, 0),
      );

      expect(plan, isNull);
    });

    test(
      'delays near-immediate invite by 12 minutes when call stack is busy',
      () {
        final now = DateTime.utc(2026, 5, 22, 10, 0, 0);
        final spec = AiCallInviteSpec.dailyRoutine(
          firstName: 'Kartik',
          problemName: 'Diabetes',
        );

        final plan = coordinator.schedulePlan(
          spec: spec,
          scheduledAt: now,
          callInviteRouteOpen: false,
          liveCallInProgress: true,
          now: now,
        );

        expect(plan.immediate, false);
        expect(plan.effectiveScheduledAt, now.add(const Duration(minutes: 12)));
        expect(
          plan.payload,
          contains('${plan.effectiveScheduledAt.millisecondsSinceEpoch}'),
        );
      },
    );

    test('records and resolves latest invite timestamps by reason', () {
      final inviteLog = coordinator.recordInviteLog(
        coordinator.recordInviteLog(
          const <String, String>{},
          reason: AiCallInviteReason.missedMealPhoto,
          invitedAt: DateTime.utc(2026, 5, 22, 11, 0),
          scheduledAt: DateTime.utc(2026, 5, 22, 11, 5),
          payload: 'call-invite:missed-meal-photo:1',
        ),
        reason: AiCallInviteReason.missedCareTask,
        invitedAt: DateTime.utc(2026, 5, 22, 13, 0),
        scheduledAt: DateTime.utc(2026, 5, 22, 13, 0),
        payload: 'call-invite:missed-care-task:2',
      );

      expect(
        coordinator.lastInvitePayload(
          inviteLog,
          AiCallInviteReason.missedCareTask,
        ),
        'call-invite:missed-care-task:2',
      );
      expect(
        coordinator.latestInviteAt(inviteLog, const {
          AiCallInviteReason.missedMealPhoto,
          AiCallInviteReason.missedCareTask,
        }),
        DateTime.utc(2026, 5, 22, 13, 0).toIso8601String(),
      );
    });

    test('builds retry plans for declined and postponed invites', () {
      final now = DateTime.utc(2026, 5, 22, 14, 0);
      final spec = AiCallInviteSpec.dailyRoutine(
        firstName: 'Kartik',
        problemName: 'Diabetes',
      );

      final declined = coordinator.declinedInviteRetryPlan(
        spec,
        retryAfter: const Duration(minutes: 10),
        now: now,
      );
      final postponed = coordinator.postponedInviteRetryPlan(
        spec,
        note: 'Retry after dinner',
        now: now,
      );

      expect(declined.scheduledAt, now.add(const Duration(minutes: 10)));
      expect(declined.auditTitle, contains('declined'));
      expect(postponed.scheduledAt, now.add(const Duration(hours: 3)));
      expect(postponed.auditContent, 'Retry after dinner');
    });

    test('creates busy-call retry only for actual busy-language signals', () {
      final now = DateTime.utc(2026, 5, 22, 16, 0);

      final retryPlan = coordinator.busyCallRetryPlan(
        userText: 'abhi nahi, call later please',
        firstName: 'Kartik',
        problemName: 'Diabetes',
        now: now,
      );
      final noRetry = coordinator.busyCallRetryPlan(
        userText: 'today breakfast was oats and milk',
        firstName: 'Kartik',
        problemName: 'Diabetes',
        now: now,
      );

      expect(retryPlan, isNotNull);
      expect(retryPlan!.spec.reason, AiCallInviteReason.dailyRoutine);
      expect(retryPlan.scheduledAt, now.add(const Duration(hours: 3)));
      expect(noRetry, isNull);
    });
  });
}
