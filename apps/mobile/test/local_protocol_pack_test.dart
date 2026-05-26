import 'package:flutter_test/flutter_test.dart';
import 'package:flicko_health/features/protocols/local_protocol_pack.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'local protocol context loads shared intake schema asset and exposes structured gaps',
    () async {
      const repository = LocalProtocolPackRepository();
      final context = await repository.contextFor(
        problemName: 'Sexual health',
        profileContext: 'Medicine: fluconazole tablet after food.',
        userText:
            'My main problem is itching and discharge since 4 days after unprotected sex.',
      );

      final prompt = context.toPromptText();
      expect(context.intakeAssessment.problemKey, 'sexual');
      expect(prompt, contains('Local structured intake status:'));
      expect(prompt, contains('Local missing intake fields'));
      expect(prompt, contains('Local next best intake questions'));
      expect(prompt, contains('Testing or doctor-referral history'));
      expect(
        context.intakeAssessment.answeredKeys,
        containsAll(<String>[
          'private_symptom',
          'exposure_risk',
          'current_medicines',
          'medicine_timing',
        ]),
      );
    },
  );

  test(
    'local intake assessment captures transcript slots for 3 representative conditions',
    () async {
      const repository = LocalProtocolPackRepository();

      Future<void> expectCaptured({
        required String problemName,
        required String profileContext,
        required String userText,
        required String expectedProblemKey,
        required List<String> expectedKeys,
      }) async {
        final context = await repository.contextFor(
          problemName: problemName,
          profileContext: profileContext,
          userText: userText,
        );

        expect(context.intakeAssessment.problemKey, expectedProblemKey);
        expect(
          context.intakeAssessment.answeredKeys,
          containsAll(expectedKeys),
        );
      }

      await expectCaptured(
        problemName: 'Diabetes Type 2',
        profileContext: 'Medicine: metformin tablet after food.',
        userText:
            'My main problem is diabetes. Fasting sugar 168 and post-meal sugar 240 since 2 weeks.',
        expectedProblemKey: 'diabetes',
        expectedKeys: <String>[
          'main_concern',
          'symptom_timeline',
          'glucose_readings',
          'current_medicines',
          'medicine_timing',
        ],
      );

      await expectCaptured(
        problemName: 'Pregnancy',
        profileContext: 'Diagnosis: pregnancy.',
        userText:
            'My main problem is pregnancy. I am 24 weeks pregnant and have swelling with severe pain since yesterday.',
        expectedProblemKey: 'pregnancy',
        expectedKeys: <String>[
          'main_concern',
          'symptom_timeline',
          'gestation_stage',
          'bleeding_movement_pain',
        ],
      );

      await expectCaptured(
        problemName: 'Sexual health',
        profileContext: 'Medicine: doxycycline tablet after food.',
        userText:
            'My main problem is itching and discharge since 4 days after unprotected sex.',
        expectedProblemKey: 'sexual',
        expectedKeys: <String>[
          'main_concern',
          'symptom_timeline',
          'private_symptom',
          'exposure_risk',
          'current_medicines',
          'medicine_timing',
        ],
      );
    },
  );
}
