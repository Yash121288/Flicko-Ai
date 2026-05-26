import 'package:flutter_test/flutter_test.dart';

import 'package:flicko_health/features/dashboard/ai_call_models.dart';
import 'package:flicko_health/features/dashboard/ai_call_warmup.dart';

void main() {
  group('AI call opening fallback', () {
    test('user-started daily call uses fresh personal opening', () {
      final opening = buildFallbackAiCallOpening(
        problemName: 'Weight management',
        reason: AiCallInviteReason.dailyRoutine,
        voiceContext:
            'User name for speech: Kartik\nDynamic greeting seed: FRESH1',
        callPurpose: 'daily routine check-in',
        initiatedByUser: true,
      );

      expect(opening, contains('Kartik'));
      expect(opening.toLowerCase(), isNot(contains('yaad kiya')));
      expect(opening.toLowerCase(), isNot(contains('aaj mujhe')));
      expect(
        opening.toLowerCase(),
        anyOf(
          contains('help'),
          contains('update'),
          contains('plan'),
          contains('focus'),
          contains('important'),
        ),
      );
    });

    test('user-started daily call varies with greeting seed', () {
      final openings = <String>{
        for (final seed in const ['FRESH1', 'FRESH2', 'FRESH3', 'FRESH4'])
          buildFallbackAiCallOpening(
            problemName: 'Weight management',
            reason: AiCallInviteReason.dailyRoutine,
            voiceContext:
                'User name for speech: Kartik\nDynamic greeting seed: $seed',
            callPurpose: 'daily routine check-in',
            initiatedByUser: true,
          ),
      };

      expect(openings.length, greaterThan(1));
      expect(
        openings.every(
          (opening) => !opening.toLowerCase().contains('yaad kiya'),
        ),
        isTrue,
      );
    });

    test('fallback opening prefers first name for speech', () {
      final opening = buildFallbackAiCallOpening(
        problemName: 'Diabetes',
        reason: AiCallInviteReason.dailyRoutine,
        voiceContext:
            'User first name: Aarav\nUser name: Aarav Shah\nDynamic greeting seed: NAME1',
        callPurpose: 'daily routine check-in',
        initiatedByUser: true,
      );

      expect(opening, contains('Aarav'));
      expect(opening, isNot(contains('Aarav Shah')));
    });

    test('Flicko-started reminder call states the work instead', () {
      final opening = buildFallbackAiCallOpening(
        problemName: 'Diabetes',
        reason: AiCallInviteReason.dailyRoutine,
        voiceContext:
            'User name for speech: Kartik\nScheduled daily reminders: 09:00 - Medicine reminder',
        callPurpose: 'daily reminder check-in',
      );

      expect(opening.toLowerCase(), isNot(contains('yaad kiya')));
      expect(
        opening.toLowerCase(),
        anyOf(contains('reminder'), contains('check-in')),
      );
    });

    test('missed task proactive call names the task purpose', () {
      final opening = buildFallbackAiCallOpening(
        problemName: 'Thyroid',
        reason: AiCallInviteReason.missedCareTask,
        voiceContext: 'User name for speech: Kartik',
        callPurpose: 'Take thyroid medicine',
      );

      expect(opening, contains('Take thyroid medicine'));
      expect(opening.toLowerCase(), contains('follow-up'));
      expect(opening.toLowerCase(), isNot(contains('yaad kiya')));
    });
  });
}
