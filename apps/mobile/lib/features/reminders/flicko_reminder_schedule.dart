import 'package:flutter/material.dart';

class FlickoReminderScheduleRequest {
  const FlickoReminderScheduleRequest({
    required this.title,
    required this.body,
    required this.scheduledAt,
    required this.payload,
    this.repeatsDaily = true,
  });

  final String title;
  final String body;
  final DateTime scheduledAt;
  final String payload;
  final bool repeatsDaily;

  String get timeLabel {
    final hourOfPeriod = scheduledAt.hour % 12;
    final hour = hourOfPeriod == 0 ? 12 : hourOfPeriod;
    final minute = scheduledAt.minute.toString().padLeft(2, '0');
    final suffix = scheduledAt.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $suffix';
  }

  static DateTime nextOccurrence(TimeOfDay time, {DateTime? now}) {
    final base = now ?? DateTime.now();
    var target = DateTime(
      base.year,
      base.month,
      base.day,
      time.hour,
      time.minute,
    );
    if (!target.isAfter(base)) {
      target = target.add(const Duration(days: 1));
    }
    return target;
  }

  static TimeOfDay suggestedTimeFor(String reminder) {
    final explicit = _explicitTime(reminder);
    if (explicit != null) {
      return explicit;
    }

    final text = reminder.toLowerCase();
    if (text.contains('breakfast') || text.contains('morning')) {
      return const TimeOfDay(hour: 8, minute: 0);
    }
    if (text.contains('lunch')) {
      return const TimeOfDay(hour: 13, minute: 0);
    }
    if (text.contains('dinner')) {
      return const TimeOfDay(hour: 20, minute: 0);
    }
    if (text.contains('sleep') || text.contains('wind-down')) {
      return const TimeOfDay(hour: 22, minute: 0);
    }
    if (text.contains('water') || text.contains('hydration')) {
      return const TimeOfDay(hour: 7, minute: 30);
    }
    if (text.contains('medicine') ||
        text.contains('medication') ||
        text.contains('tablet')) {
      return const TimeOfDay(hour: 20, minute: 0);
    }
    if (text.contains('walk') ||
        text.contains('steps') ||
        text.contains('workout') ||
        text.contains('activity')) {
      return const TimeOfDay(hour: 18, minute: 30);
    }
    if (text.contains('photo') || text.contains('meal')) {
      return const TimeOfDay(hour: 13, minute: 30);
    }
    return const TimeOfDay(hour: 9, minute: 0);
  }

  static TimeOfDay? _explicitTime(String reminder) {
    final match = RegExp(
      r'\b(\d{1,2})(?::(\d{2}))?\s*(am|pm)\b',
      caseSensitive: false,
    ).firstMatch(reminder);
    if (match == null) {
      return null;
    }

    final rawHour = int.tryParse(match.group(1) ?? '');
    if (rawHour == null || rawHour < 1 || rawHour > 12) {
      return null;
    }
    final rawMinute = int.tryParse(match.group(2) ?? '0') ?? 0;
    if (rawMinute < 0 || rawMinute > 59) {
      return null;
    }

    final suffix = (match.group(3) ?? '').toLowerCase();
    var hour = rawHour % 12;
    if (suffix == 'pm') {
      hour += 12;
    }
    return TimeOfDay(hour: hour, minute: rawMinute);
  }
}

typedef FlickoReminderScheduler =
    Future<bool> Function(FlickoReminderScheduleRequest request);
