import '../reminders/flicko_notification_memory_store.dart';

class FlickoVoiceContextEngine {
  const FlickoVoiceContextEngine({FlickoNotificationMemoryStore? memoryStore})
    : _memoryStore = memoryStore;

  final FlickoNotificationMemoryStore? _memoryStore;

  Future<String> buildContext({
    required String problemName,
    required String profileContext,
    String protocolContext = '',
    String backendContext = '',
  }) async {
    final now = DateTime.now();
    final notificationMemory =
        await (_memoryStore ?? FlickoNotificationMemoryStore())
            .summaryForPrompt();
    final name = _preferredSpeechName(profileContext);
    final lastAssistant = _lastAssistantLine(profileContext);
    final sessionSeed = _variationSeed(now, profileContext, notificationMemory);

    final sections = <String>[
      'Live voice context engine:',
      'Current local time: ${now.toIso8601String()}',
      'Time-of-day opening hint: ${_timeOfDay(now)}',
      'Primary care focus: $problemName',
      if (name.isNotEmpty) 'User name for speech: $name',
      'Dynamic greeting seed: $sessionSeed',
      if (lastAssistant.isNotEmpty)
        'Last assistant wording to avoid repeating exactly: $lastAssistant',
      'Personalization rule: mention the user name naturally when available, but do not force it into every sentence.',
      'Friendly familiarity rule: for returning users, sound like a known caring coach. You may occasionally use light friendly continuity such as remembering the user or their plan, but never reuse the same phrase on every call.',
      'Anti-repeat rule: never reuse the same first sentence, same greeting structure, or same summary wording from previous calls.',
      'Summary rule: generate a fresh summary from current memory, notification state, recent chat/call history, reminders, and tasks.',
      'Reminder rule: do not invent reminders. When the user clearly approves a reminder or call time, repeat back that exact time and include one exact structured line: Reminder: HH:MM - short title/body. Do not round or guess morning/evening. If the time is ambiguous like 9 baje, ask one short clarification question first.',
      'Task recovery rule: for missed task or meal photo calls, ask what blocked the task, ask the next realistic recovery time, then update the plan in one short confirmation.',
      'Memory rule: use chat uploads, saved reports, previous call summaries, missed notifications, and local logs as hidden context. Do not dump raw memory into the spoken response.',
      profileContext.trim(),
      protocolContext.trim(),
      backendContext.trim(),
      notificationMemory.trim(),
    ].where((value) => value.trim().isNotEmpty).toList();

    return sections.join('\n\n');
  }

  String _extractLine(String context, String label) {
    final prefix = '$label:';
    for (final line in context.split('\n')) {
      final clean = line.trim();
      if (clean.toLowerCase().startsWith(prefix.toLowerCase())) {
        return clean.substring(prefix.length).trim();
      }
    }
    return '';
  }

  String _preferredSpeechName(String context) {
    for (final label in const <String>[
      'User name for speech',
      'User first name',
      'First name',
      'User name',
      'Name',
    ]) {
      final value = _extractLine(context, label);
      final speechName = _speechNameFrom(value);
      if (speechName.isNotEmpty) {
        return speechName;
      }
    }
    return '';
  }

  String _speechNameFrom(String value) {
    final clean = value.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (clean.isEmpty) {
      return '';
    }
    return clean.split(' ').first.trim();
  }

  String _lastAssistantLine(String context) {
    final markers = <String>['Flicko:', 'Assistant:', 'AI:'];
    final lines = context.split('\n').reversed;
    for (final line in lines) {
      final clean = line.trim();
      for (final marker in markers) {
        if (clean.startsWith(marker)) {
          return _clip(clean.substring(marker.length).trim(), 180);
        }
      }
    }
    return '';
  }

  String _timeOfDay(DateTime now) {
    if (now.hour < 5) {
      return 'late night';
    }
    if (now.hour < 12) {
      return 'morning';
    }
    if (now.hour < 17) {
      return 'afternoon';
    }
    if (now.hour < 21) {
      return 'evening';
    }
    return 'night';
  }

  String _variationSeed(
    DateTime now,
    String profileContext,
    String notificationMemory,
  ) {
    final source =
        '${now.microsecondsSinceEpoch}|${profileContext.hashCode}|${notificationMemory.hashCode}';
    const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    var hash = 0;
    for (final unit in source.codeUnits) {
      hash = 0x1fffffff & (hash + unit);
      hash = 0x1fffffff & (hash + ((0x0007ffff & hash) << 10));
      hash ^= hash >> 6;
    }
    final chars = <String>[];
    var value = hash.abs();
    for (var i = 0; i < 6; i++) {
      chars.add(alphabet[value % alphabet.length]);
      value = value ~/ alphabet.length;
    }
    return chars.join();
  }

  String _clip(String value, int maxLength) {
    final clean = value.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (clean.length <= maxLength) {
      return clean;
    }
    return '${clean.substring(0, maxLength - 3).trim()}...';
  }
}
