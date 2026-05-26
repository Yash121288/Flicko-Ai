import 'package:flutter_test/flutter_test.dart';

import 'package:flicko_health/features/dashboard/ai_call_auto_end_coordinator.dart';
import 'package:flicko_health/features/dashboard/ai_call_memory.dart';

void main() {
  HealthCallTranscriptEntry entry(String role, String text) {
    return HealthCallTranscriptEntry(
      role: role,
      text: text,
      createdAt: DateTime.utc(2026, 5, 23, 10),
    );
  }

  group('AiCallAutoEndCoordinator', () {
    test('detects the exact final closing question', () {
      final coordinator = AiCallAutoEndCoordinator();

      final action = coordinator.observe(
        entry('assistant', 'Aur koi question ya problem hai?'),
      );

      expect(action, AiCallAutoEndAction.markClosingQuestionAsked);
      expect(coordinator.closingQuestionAsked, true);
    });

    test('requests goodbye when user says no after closing question', () {
      final coordinator = AiCallAutoEndCoordinator()
        ..observe(entry('assistant', 'Aur koi question ya problem hai?'));

      final action = coordinator.observe(entry('user', 'Nahi, bas.'));

      expect(action, AiCallAutoEndAction.requestGoodbye);
      expect(coordinator.goodbyeRequested, true);
    });

    test('does not close when user has a real follow-up concern', () {
      final coordinator = AiCallAutoEndCoordinator()
        ..observe(entry('assistant', 'Aur koi question ya problem hai?'));

      final action = coordinator.observe(
        entry('user', 'Nahi, actually sugar reading high aa rahi hai.'),
      );

      expect(action, AiCallAutoEndAction.none);
      expect(coordinator.goodbyeRequested, false);
    });

    test('finishes after assistant speaks goodbye', () {
      final coordinator = AiCallAutoEndCoordinator()
        ..observe(entry('assistant', 'Aur koi question ya problem hai?'))
        ..observe(entry('user', 'No problem.'));

      final action = coordinator.observe(
        entry('assistant', 'Theek hai, chalo bye bye. Apna dhyan rakhna.'),
      );

      expect(action, AiCallAutoEndAction.finishAfterGoodbye);
    });

    test('does not treat a normal check-in question as a final close', () {
      final coordinator = AiCallAutoEndCoordinator();

      final action = coordinator.observe(
        entry(
          'assistant',
          'Aaj reminder follow hua ya koi new problem happened?',
        ),
      );

      expect(action, AiCallAutoEndAction.none);
      expect(coordinator.closingQuestionAsked, false);
    });
  });
}
