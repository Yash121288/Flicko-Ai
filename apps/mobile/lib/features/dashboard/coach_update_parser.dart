import 'gemini_health_chat_client.dart';

class CoachAppUpdate {
  const CoachAppUpdate({
    this.intakeSummary = '',
    this.dashboardNotes = const <String>[],
    this.reminders = const <String>[],
    this.reports = const <String>[],
    this.intakeComplete = false,
  });

  final String intakeSummary;
  final List<String> dashboardNotes;
  final List<String> reminders;
  final List<String> reports;
  final bool intakeComplete;

  bool get hasAny =>
      intakeSummary.trim().isNotEmpty ||
      dashboardNotes.isNotEmpty ||
      reminders.isNotEmpty ||
      reports.isNotEmpty ||
      intakeComplete;
}

class CoachUpdateParser {
  const CoachUpdateParser._();

  static CoachAppUpdate fromMessages(List<AiCoachMessage> messages) {
    final assistantMessages = messages
        .where(
          (message) =>
              !message.isUser &&
              !message.isError &&
              message.source.trim().toLowerCase() == 'chat',
        )
        .map((message) => message.text.trim())
        .where((text) => text.isNotEmpty)
        .toList();

    var intakeSummary = '';
    final dashboardNotes = <String>[];
    final reminders = <String>[];
    final reports = <String>[];
    var intakeComplete = false;

    for (final text in assistantMessages) {
      final lower = text.toLowerCase();
      if (_isIntakeComplete(lower)) {
        intakeComplete = true;
      }
      if (lower.contains('intake summary for dashboard')) {
        intakeSummary = _boundedSectionAfter(
          text,
          'Intake summary for dashboard',
        );
      }
      final appUpdate = _boundedSectionAfter(text, 'App update');
      if (appUpdate.isNotEmpty) {
        dashboardNotes.addAll(
          _bulletLines(appUpdate).where(
            (line) =>
                !_looksLikeReminderLine(line) && !_looksLikeReportLine(line),
          ),
        );
        reminders.addAll(_reminderLines(appUpdate));
        if (intakeComplete) {
          reports.addAll(_reportLines(appUpdate));
        }
      }
      if (appUpdate.isEmpty &&
          intakeComplete &&
          lower.contains('doctor-ready report')) {
        reports.addAll(_reportLines(text));
      }
    }

    return CoachAppUpdate(
      intakeSummary: intakeSummary.trim(),
      dashboardNotes: _uniqueClean(dashboardNotes).take(8).toList(),
      reminders: _uniqueClean(reminders).take(8).toList(),
      reports: _uniqueClean(reports).take(8).toList(),
      intakeComplete: intakeComplete,
    );
  }

  static bool _isIntakeComplete(String lowerText) {
    return lowerText.contains('intake status: complete') ||
        lowerText.contains('intake complete: yes') ||
        lowerText.contains('intake completed: yes') ||
        lowerText.contains('intake is complete');
  }

  static String _boundedSectionAfter(String text, String heading) {
    final lower = text.toLowerCase();
    final index = lower.indexOf(heading.toLowerCase());
    if (index < 0) {
      return '';
    }
    final body = text
        .substring(index + heading.length)
        .trimLeft()
        .replaceFirst(RegExp(r'^[:\-\s]+'), '');
    final stop = RegExp(
      r'\n\s*(?:#{1,3}\s*)?(?:app update|intake summary for dashboard|doctor-ready report|report|safety rules?|next question)\s*[:\-]?',
      caseSensitive: false,
    ).firstMatch(body);
    return (stop == null ? body : body.substring(0, stop.start)).trim();
  }

  static List<String> _bulletLines(String text) {
    return text
        .split('\n')
        .map((line) => line.trim().replaceFirst(RegExp(r'^[-*\d.)\s]+'), ''))
        .where((line) => line.length >= 4)
        .toList();
  }

  static List<String> _reminderLines(String text) {
    return _bulletLines(text)
        .where(_looksLikeReminderLine)
        .map(_cleanReminderLine)
        .where((line) => line.isNotEmpty)
        .where(_isActionableReminderLine)
        .toList();
  }

  static List<String> _reportLines(String text) {
    return _bulletLines(text)
        .where(_looksLikeReportLine)
        .where((line) => !_looksLikeDeferredReportLine(line))
        .map(
          (line) =>
              line.length > 90 ? '${line.substring(0, 87).trim()}...' : line,
        )
        .toList();
  }

  static String _cleanReminderLine(String line) {
    return line
        .trim()
        .replaceFirst(
          RegExp(
            r'^(?:reminder|set reminder|create reminder)\s*[:\-]\s*',
            caseSensitive: false,
          ),
          '',
        )
        .trim();
  }

  static bool _looksLikeReminderLine(String line) {
    return line.toLowerCase().contains('reminder');
  }

  static bool _isActionableReminderLine(String line) {
    final lower = line.toLowerCase();
    if (line.length < 8 || line.length > 180) {
      return false;
    }
    if (RegExp(
      r"\b(no|not|don't|do not|without|if you want|can be|could be|later|after more details)\b",
    ).hasMatch(lower)) {
      return false;
    }
    final hasAction = RegExp(
      r'\b(meal|photo|medicine|tablet|water|walk|sleep|steps|bp|sugar|glucose|weight|log|check|call|drink|take|upload)\b',
      caseSensitive: false,
    ).hasMatch(line);
    final hasTime = RegExp(
      r'\b(\d{1,2})(?::\d{2})?\s*(am|pm|a\.m\.|p\.m\.)\b|\b(morning|evening|night|lunch|dinner|breakfast|bedtime)\b',
      caseSensitive: false,
    ).hasMatch(line);
    return hasAction || hasTime;
  }

  static bool _looksLikeReportLine(String line) {
    final lower = line.toLowerCase();
    return lower.startsWith('doctor-ready report') ||
        lower.startsWith('report:') ||
        lower.startsWith('report -');
  }

  static bool _looksLikeDeferredReportLine(String line) {
    final lower = line.toLowerCase();
    return lower.contains('can be generated') ||
        lower.contains('after more') ||
        lower.contains('not ready') ||
        lower.contains('later');
  }

  static List<String> _uniqueClean(List<String> values) {
    final seen = <String>{};
    final result = <String>[];
    for (final value in values) {
      final cleaned = value.trim();
      if (cleaned.isEmpty || !seen.add(cleaned.toLowerCase())) {
        continue;
      }
      result.add(cleaned);
    }
    return result;
  }
}
