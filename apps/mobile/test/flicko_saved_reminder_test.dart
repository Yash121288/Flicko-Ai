import 'package:flicko_health/features/reminders/flicko_saved_reminder.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('dedupe keeps one reminder per problem and clock time', () {
    final first = FlickoSavedReminder.create(
      title: 'Medicine reminder',
      body: 'Take tablet',
      time: const TimeOfDay(hour: 20, minute: 0),
      problemName: 'Diabetes',
    );
    final duplicateTime = FlickoSavedReminder.create(
      title: 'Daily routine check',
      body: 'Call and review meal, water, and medicine',
      time: const TimeOfDay(hour: 20, minute: 0),
      problemName: 'Diabetes',
    );
    final differentTime = FlickoSavedReminder.create(
      title: 'Morning medicine',
      body: 'Take breakfast tablet',
      time: const TimeOfDay(hour: 9, minute: 0),
      problemName: 'Diabetes',
    );

    final deduped = FlickoSavedReminder.dedupe([
      first,
      duplicateTime,
      differentTime,
    ]);

    expect(deduped, [first, differentTime]);
  });
}
