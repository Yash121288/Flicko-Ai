import 'package:flutter/material.dart';

import 'ai_call_memory.dart';

class AiCallScheduleParser {
  const AiCallScheduleParser._();

  static TimeOfDay? preferredDailyCallTime(HealthCallMemorySummary memory) {
    final transcript = memory.transcript
        .where((entry) => entry.text.trim().isNotEmpty)
        .toList(growable: false);

    for (final entry in transcript) {
      if (!_looksLikeConfirmedCallWindow(entry.text)) {
        continue;
      }
      final explicit = _parseExplicitTime(entry.text);
      if (explicit != null) {
        return explicit;
      }
      final inferred = _parseContextualTime(
        entry.text,
        entry.text,
        allowAmbiguousInference: false,
      );
      if (inferred != null) {
        return inferred;
      }
    }

    for (var index = 0; index < transcript.length; index += 1) {
      final entry = transcript[index];
      if (!entry.isUser) {
        continue;
      }
      final previousCoach = _previousAssistantText(transcript, index);
      final context = '$previousCoach ${entry.text}';
      final explicit = _parseExplicitTime(entry.text);
      if (explicit != null) {
        return explicit;
      }
      if (_looksLikeCallTimeContext(context)) {
        final inferred = _parseContextualTime(
          entry.text,
          context,
          allowAmbiguousInference: false,
        );
        if (inferred != null) {
          return inferred;
        }
      }
    }

    for (final reminder in memory.structured.reminders) {
      final explicit = _parseExplicitTime(reminder);
      if (explicit != null) {
        return explicit;
      }
      if (_looksLikeCallTimeContext(reminder)) {
        final inferred = _parseContextualTime(
          reminder,
          reminder,
          allowAmbiguousInference: false,
        );
        if (inferred != null) {
          return inferred;
        }
      }
    }

    return null;
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
    while (!target.isAfter(base)) {
      target = target.add(const Duration(days: 1));
    }
    return target;
  }

  static String _previousAssistantText(
    List<HealthCallTranscriptEntry> transcript,
    int userIndex,
  ) {
    for (var index = userIndex - 1; index >= 0; index -= 1) {
      final entry = transcript[index];
      if (!entry.isUser) {
        return entry.text;
      }
    }
    return '';
  }

  static TimeOfDay? _parseExplicitTime(String text) {
    final lower = text.toLowerCase();
    final amPm = RegExp(
      r'\b(\d{1,2})(?::(\d{2}))?\s*(am|pm|a\.m\.|p\.m\.)\b',
      caseSensitive: false,
    ).firstMatch(lower);
    if (amPm != null) {
      final hour = int.tryParse(amPm.group(1) ?? '');
      final minute = int.tryParse(amPm.group(2) ?? '0') ?? 0;
      final suffix = (amPm.group(3) ?? '').replaceAll('.', '').toLowerCase();
      if (hour == null || hour < 1 || hour > 12 || minute < 0 || minute > 59) {
        return null;
      }
      var normalizedHour = hour % 12;
      if (suffix == 'pm') {
        normalizedHour += 12;
      }
      return TimeOfDay(hour: normalizedHour, minute: minute);
    }

    final twentyFour = RegExp(
      r'\b([01]?\d|2[0-3]):([0-5]\d)\b',
    ).firstMatch(lower);
    if (twentyFour != null && !_hasMeridiemWord(lower)) {
      final hour = int.tryParse(twentyFour.group(1) ?? '');
      final minute = int.tryParse(twentyFour.group(2) ?? '0') ?? 0;
      if (hour != null && hour >= 13) {
        return TimeOfDay(hour: hour, minute: minute);
      }
    }

    return null;
  }

  static TimeOfDay? _parseContextualTime(
    String text,
    String context, {
    required bool allowAmbiguousInference,
  }) {
    final lower = text.toLowerCase();
    final match = RegExp(
      r'(?:^|[^\d])(\d{1,2})(?::(\d{2}))?\s*(?:baje|बजे|o\s*clock)?(?:[^\d]|$)',
      caseSensitive: false,
    ).firstMatch(lower);
    if (match == null) {
      return null;
    }
    final rawHour = int.tryParse(match.group(1) ?? '');
    final minute = int.tryParse(match.group(2) ?? '0') ?? 0;
    if (rawHour == null ||
        rawHour < 1 ||
        rawHour > 23 ||
        minute < 0 ||
        minute > 59) {
      return null;
    }
    if (rawHour > 12) {
      return TimeOfDay(hour: rawHour, minute: minute);
    }
    if (!_hasMeridiemContext('$context $text') && !allowAmbiguousInference) {
      return null;
    }
    return TimeOfDay(
      hour: _inferHour(rawHour, '$context $text'),
      minute: minute,
    );
  }

  static int _inferHour(int hour, String context) {
    final lower = context.toLowerCase();
    if (RegExp(r'\b(am|a\.m\.|morning|subah|सुबह)\b').hasMatch(lower)) {
      return hour % 12;
    }
    if (RegExp(
      r'\b(pm|p\.m\.|evening|shaam|sham|raat|rat|night|dinner|रात|शाम)\b',
    ).hasMatch(lower)) {
      return hour == 12 ? 12 : hour + 12;
    }
    if (RegExp(r'\b(afternoon|dopahar|lunch|दोपहर)\b').hasMatch(lower)) {
      return hour == 12 ? 12 : hour + 12;
    }
    return hour == 12 ? 12 : hour + 12;
  }

  static bool _looksLikeConfirmedCallWindow(String text) {
    final lower = text.toLowerCase();
    final hasReminderCue = RegExp(
      r'\b(reminder|call|schedule|daily|window|free-time|free time|check-in|checkin|routine)\b',
      caseSensitive: false,
    ).hasMatch(lower);
    final hasConfirmationCue = RegExp(
      r'\b(theek hai|thik hai|done|confirmed|confirm|save|saved|noted|set|karungi|karunga|rakh diya|rakh dungi)\b',
      caseSensitive: false,
    ).hasMatch(lower);
    return hasReminderCue && hasConfirmationCue;
  }

  static bool _looksLikeCallTimeContext(String text) {
    final lower = text.toLowerCase();
    return RegExp(
      r'\b(call|free|available|time|routine|reminder|schedule|kis time|kab|baje|फ्री|कॉल|समय|बजे)\b',
      caseSensitive: false,
    ).hasMatch(lower);
  }

  static bool _hasMeridiemContext(String text) {
    final lower = text.toLowerCase();
    return RegExp(
      r'\b(am|pm|a\.m\.|p\.m\.|morning|subah|à¤¸à¥à¤¬à¤¹|evening|shaam|sham|raat|rat|night|dinner|à¤°à¤¾à¤¤|à¤¶à¤¾à¤®|afternoon|dopahar|lunch|à¤¦à¥‹à¤ªà¤¹à¤°)\b',
      caseSensitive: false,
    ).hasMatch(lower);
  }

  static bool _hasMeridiemWord(String text) {
    return RegExp(
      r'\b(am|pm|a\.m\.|p\.m\.)\b',
      caseSensitive: false,
    ).hasMatch(text);
  }
}
