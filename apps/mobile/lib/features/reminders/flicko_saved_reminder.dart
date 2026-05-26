import 'package:flutter/material.dart';

import 'flicko_reminder_schedule.dart';

class FlickoSavedReminder {
  const FlickoSavedReminder({
    required this.id,
    required this.title,
    required this.body,
    required this.hour,
    required this.minute,
    required this.problemName,
    required this.createdAt,
    required this.updatedAt,
    this.enabled = true,
  });

  final String id;
  final String title;
  final String body;
  final int hour;
  final int minute;
  final String problemName;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool enabled;

  String get payload => 'saved-reminder:$id';

  String get timeLabel {
    final hourOfPeriod = hour % 12;
    final displayHour = hourOfPeriod == 0 ? 12 : hourOfPeriod;
    final displayMinute = minute.toString().padLeft(2, '0');
    final suffix = hour >= 12 ? 'PM' : 'AM';
    return '$displayHour:$displayMinute $suffix';
  }

  TimeOfDay get timeOfDay => TimeOfDay(hour: hour, minute: minute);

  String get duplicateSlotKey {
    return [
      _normaliseKey(problemName),
      hour.toString().padLeft(2, '0'),
      minute.toString().padLeft(2, '0'),
    ].join('|');
  }

  FlickoReminderScheduleRequest toScheduleRequest() {
    return FlickoReminderScheduleRequest(
      title: title,
      body: body,
      scheduledAt: FlickoReminderScheduleRequest.nextOccurrence(timeOfDay),
      payload: payload,
    );
  }

  FlickoSavedReminder copyWith({
    String? title,
    String? body,
    int? hour,
    int? minute,
    String? problemName,
    DateTime? updatedAt,
    bool? enabled,
  }) {
    return FlickoSavedReminder(
      id: id,
      title: title ?? this.title,
      body: body ?? this.body,
      hour: hour ?? this.hour,
      minute: minute ?? this.minute,
      problemName: problemName ?? this.problemName,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      enabled: enabled ?? this.enabled,
    );
  }

  Map<String, Object> toJson() {
    return {
      'id': id,
      'title': title,
      'body': body,
      'hour': hour,
      'minute': minute,
      'problemName': problemName,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'enabled': enabled,
    };
  }

  static FlickoSavedReminder create({
    required String title,
    required String body,
    required TimeOfDay time,
    required String problemName,
  }) {
    final now = DateTime.now();
    return FlickoSavedReminder(
      id: _stableKey('${problemName.trim()}|${title.trim()}|${body.trim()}'),
      title: title.trim().isEmpty ? 'Flicko reminder' : title.trim(),
      body: body.trim().isEmpty
          ? 'Time for your Flicko health check-in.'
          : body.trim(),
      hour: time.hour,
      minute: time.minute,
      problemName: problemName.trim(),
      createdAt: now,
      updatedAt: now,
    );
  }

  static List<FlickoSavedReminder> dedupe(
    Iterable<FlickoSavedReminder> reminders,
  ) {
    final seenIds = <String>{};
    final seenSlots = <String>{};
    final result = <FlickoSavedReminder>[];
    for (final reminder in reminders) {
      if (!seenIds.add(reminder.id)) {
        continue;
      }
      if (!seenSlots.add(reminder.duplicateSlotKey)) {
        continue;
      }
      result.add(reminder);
    }
    return result.toList(growable: false);
  }

  static FlickoSavedReminder? fromJson(Map<String, dynamic> json) {
    final title = _asString(json['title']);
    final body = _asString(json['body']);
    final hour = _asInt(json['hour']);
    final minute = _asInt(json['minute']);
    if (title.isEmpty || body.isEmpty || hour < 0 || hour > 23) {
      return null;
    }
    if (minute < 0 || minute > 59) {
      return null;
    }
    final id = _asString(json['id']).isNotEmpty
        ? _asString(json['id'])
        : _stableKey('${_asString(json['problemName'])}|$title|$body');
    return FlickoSavedReminder(
      id: id,
      title: title,
      body: body,
      hour: hour,
      minute: minute,
      problemName: _asString(json['problemName']),
      createdAt: _asDate(json['createdAt']),
      updatedAt: _asDate(json['updatedAt']),
      enabled: json['enabled'] != false,
    );
  }
}

typedef FlickoSavedReminderWriter =
    Future<bool> Function(FlickoSavedReminder reminder);

typedef FlickoSavedReminderDeleter =
    Future<bool> Function(FlickoSavedReminder reminder);

String _asString(Object? value) => value?.toString().trim() ?? '';

String _normaliseKey(String value) {
  return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
}

int _asInt(Object? value) {
  if (value is int) {
    return value;
  }
  return int.tryParse(value?.toString() ?? '') ?? -1;
}

DateTime _asDate(Object? value) {
  final parsed = DateTime.tryParse(value?.toString() ?? '');
  return parsed ?? DateTime.now();
}

String _stableKey(String value) {
  var hash = 0;
  for (final unit in value.codeUnits) {
    hash = 0x1fffffff & (hash + unit);
    hash = 0x1fffffff & (hash + ((0x0007ffff & hash) << 10));
    hash ^= hash >> 6;
  }
  hash = 0x1fffffff & (hash + ((0x03ffffff & hash) << 3));
  hash ^= hash >> 11;
  hash = 0x1fffffff & (hash + ((0x00003fff & hash) << 15));
  return hash.toString();
}
