import 'gemini_health_chat_client.dart';

class HealthCallTranscriptEntry {
  const HealthCallTranscriptEntry({
    required this.role,
    required this.text,
    required this.createdAt,
    this.isFinal = true,
    this.source = '',
  });

  final String role;
  final String text;
  final DateTime createdAt;
  final bool isFinal;
  final String source;

  bool get isUser => role.toLowerCase() == 'user';

  AiCoachMessage toCoachMessage() {
    return isUser
        ? AiCoachMessage.user(text, source: 'call')
        : AiCoachMessage.assistant(text, source: 'call');
  }

  Map<String, Object> toJson() {
    final data = {
      'role': isUser ? 'user' : 'assistant',
      'text': text.trim(),
      'createdAt': createdAt.toIso8601String(),
      'isFinal': isFinal,
    };
    if (source.trim().isNotEmpty) {
      data['source'] = source.trim();
    }
    return data;
  }

  factory HealthCallTranscriptEntry.fromJson(Map<String, dynamic> json) {
    return HealthCallTranscriptEntry(
      role: json['role']?.toString() == 'user' ? 'user' : 'assistant',
      text: json['text']?.toString() ?? '',
      createdAt:
          DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.now(),
      isFinal: json['isFinal'] != false,
      source: json['source']?.toString() ?? '',
    );
  }
}

class HealthCallStructuredSummary {
  const HealthCallStructuredSummary({
    required this.overview,
    this.problems = const <String>[],
    this.symptoms = const <String>[],
    this.routine = const <String>[],
    this.food = const <String>[],
    this.medicine = const <String>[],
    this.reminders = const <String>[],
    this.goals = const <String>[],
    this.redFlags = const <String>[],
  });

  final String overview;
  final List<String> problems;
  final List<String> symptoms;
  final List<String> routine;
  final List<String> food;
  final List<String> medicine;
  final List<String> reminders;
  final List<String> goals;
  final List<String> redFlags;

  String get dashboardNote {
    final redFlagText = redFlags.isEmpty
        ? ''
        : ' Red flags noted: ${redFlags.first}';
    return '${overview.trim()}$redFlagText'.trim();
  }

  String toMarkdown() {
    final sections = <String>[
      '## Call summary',
      overview.trim(),
      _section('Problems discussed', problems),
      _section('Symptoms and concerns', symptoms),
      _section('Daily routine', routine),
      _section('Food and meal pattern', food),
      _section('Medicines, allergy, diagnosis notes', medicine),
      _section('Reminder plan', reminders),
      _section('Goals and next steps', goals),
      _section('Red flags and safety', redFlags),
    ].where((line) => line.trim().isNotEmpty).join('\n\n');
    return sections.trim();
  }

  Map<String, Object> toJson() {
    return {
      'overview': overview,
      'problems': problems,
      'symptoms': symptoms,
      'routine': routine,
      'food': food,
      'medicine': medicine,
      'reminders': reminders,
      'goals': goals,
      'redFlags': redFlags,
    };
  }

  factory HealthCallStructuredSummary.fromJson(Map<String, dynamic> json) {
    return HealthCallStructuredSummary(
      overview: json['overview']?.toString() ?? '',
      problems: _stringList(json['problems']),
      symptoms: _stringList(json['symptoms']),
      routine: _stringList(json['routine']),
      food: _stringList(json['food']),
      medicine: _stringList(json['medicine']),
      reminders: _stringList(json['reminders']),
      goals: _stringList(json['goals']),
      redFlags: _stringList(json['redFlags'] ?? json['red_flags']),
    );
  }

  static String _section(String title, List<String> values) {
    if (values.isEmpty) {
      return '';
    }
    return ['## $title', ...values.map((value) => '- $value')].join('\n');
  }
}

class HealthCallMemorySummary {
  const HealthCallMemorySummary({
    required this.id,
    required this.problemName,
    required this.reason,
    required this.reasonTitle,
    required this.startedAt,
    required this.endedAt,
    required this.durationSeconds,
    required this.inviteMemoryIntent,
    required this.structured,
    this.transcript = const <HealthCallTranscriptEntry>[],
    this.backendSyncedAt = '',
    this.reportSyncedAt = '',
    this.reportTitle = '',
    this.reportPdfUrl = '',
    this.reportHtmlUrl = '',
  });

  final String id;
  final String problemName;
  final String reason;
  final String reasonTitle;
  final DateTime startedAt;
  final DateTime endedAt;
  final int durationSeconds;
  final String inviteMemoryIntent;
  final HealthCallStructuredSummary structured;
  final List<HealthCallTranscriptEntry> transcript;
  final String backendSyncedAt;
  final String reportSyncedAt;
  final String reportTitle;
  final String reportPdfUrl;
  final String reportHtmlUrl;

  bool get hasTranscript =>
      transcript.any((entry) => entry.text.trim().isNotEmpty);

  String get durationLabel {
    final duration = Duration(seconds: durationSeconds);
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  String get memoryContent {
    return [
      structured.toMarkdown(),
      if (inviteMemoryIntent.trim().isNotEmpty)
        '## Call intent\n${inviteMemoryIntent.trim()}',
      if (hasTranscript)
        '## Transcript excerpt\n${transcriptExcerpt(maxEntries: 12)}',
    ].where((line) => line.trim().isNotEmpty).join('\n\n');
  }

  String get fullTranscriptText {
    return transcript
        .where((entry) => entry.text.trim().isNotEmpty)
        .map((entry) {
          final role = entry.isUser ? 'User' : 'Flicko';
          return '$role: ${_clean(entry.text)}';
        })
        .join('\n');
  }

  String transcriptExcerpt({int maxEntries = 8}) {
    return transcript
        .where((entry) => entry.text.trim().isNotEmpty)
        .take(maxEntries)
        .map((entry) {
          final role = entry.isUser ? 'User' : 'Flicko';
          return '$role: ${_clip(entry.text, 320)}';
        })
        .join('\n');
  }

  List<AiCoachMessage> toCoachTranscript() {
    return transcript
        .where((entry) => entry.text.trim().isNotEmpty)
        .map((entry) => entry.toCoachMessage())
        .toList(growable: false);
  }

  HealthCallMemorySummary copyWith({
    String? backendSyncedAt,
    String? reportSyncedAt,
    String? reportTitle,
    String? reportPdfUrl,
    String? reportHtmlUrl,
  }) {
    return HealthCallMemorySummary(
      id: id,
      problemName: problemName,
      reason: reason,
      reasonTitle: reasonTitle,
      startedAt: startedAt,
      endedAt: endedAt,
      durationSeconds: durationSeconds,
      inviteMemoryIntent: inviteMemoryIntent,
      structured: structured,
      transcript: transcript,
      backendSyncedAt: backendSyncedAt ?? this.backendSyncedAt,
      reportSyncedAt: reportSyncedAt ?? this.reportSyncedAt,
      reportTitle: reportTitle ?? this.reportTitle,
      reportPdfUrl: reportPdfUrl ?? this.reportPdfUrl,
      reportHtmlUrl: reportHtmlUrl ?? this.reportHtmlUrl,
    );
  }

  Map<String, Object> toJson() {
    return {
      'id': id,
      'problemName': problemName,
      'reason': reason,
      'reasonTitle': reasonTitle,
      'startedAt': startedAt.toIso8601String(),
      'endedAt': endedAt.toIso8601String(),
      'durationSeconds': durationSeconds,
      'inviteMemoryIntent': inviteMemoryIntent,
      'structured': structured.toJson(),
      'transcript': transcript.map((entry) => entry.toJson()).toList(),
      'backendSyncedAt': backendSyncedAt,
      'reportSyncedAt': reportSyncedAt,
      'reportTitle': reportTitle,
      'reportPdfUrl': reportPdfUrl,
      'reportHtmlUrl': reportHtmlUrl,
    };
  }

  factory HealthCallMemorySummary.fromJson(Map<String, dynamic> json) {
    final structured = json['structured'];
    final transcript = json['transcript'];
    return HealthCallMemorySummary(
      id: json['id']?.toString() ?? _stableCallId(json),
      problemName: json['problemName']?.toString() ?? 'General health',
      reason: json['reason']?.toString() ?? 'notification',
      reasonTitle:
          json['reasonTitle']?.toString() ??
          _reasonTitle(json['reason']?.toString() ?? ''),
      startedAt:
          DateTime.tryParse(json['startedAt']?.toString() ?? '') ??
          DateTime.now(),
      endedAt:
          DateTime.tryParse(json['endedAt']?.toString() ?? '') ??
          DateTime.now(),
      durationSeconds: _intValue(json['durationSeconds']),
      inviteMemoryIntent: json['inviteMemoryIntent']?.toString() ?? '',
      structured: structured is Map
          ? HealthCallStructuredSummary.fromJson(
              Map<String, dynamic>.from(structured),
            )
          : HealthCallStructuredSummary(
              overview: json['content']?.toString() ?? '',
            ),
      transcript: transcript is List
          ? transcript
                .whereType<Map>()
                .map(
                  (entry) => HealthCallTranscriptEntry.fromJson(
                    Map<String, dynamic>.from(entry),
                  ),
                )
                .where((entry) => entry.text.trim().isNotEmpty)
                .toList()
          : const <HealthCallTranscriptEntry>[],
      backendSyncedAt: json['backendSyncedAt']?.toString() ?? '',
      reportSyncedAt: json['reportSyncedAt']?.toString() ?? '',
      reportTitle: json['reportTitle']?.toString() ?? '',
      reportPdfUrl: json['reportPdfUrl']?.toString() ?? '',
      reportHtmlUrl: json['reportHtmlUrl']?.toString() ?? '',
    );
  }

  static HealthCallMemorySummary fromSession({
    required String problemName,
    required String reason,
    required String reasonTitle,
    required DateTime startedAt,
    required DateTime endedAt,
    required Duration duration,
    required String inviteMemoryIntent,
    required List<HealthCallTranscriptEntry> transcript,
  }) {
    final structured = HealthCallMemoryBuilder.buildStructuredSummary(
      problemName: problemName,
      reasonTitle: reasonTitle,
      inviteMemoryIntent: inviteMemoryIntent,
      transcript: transcript,
      duration: duration,
    );
    return HealthCallMemorySummary(
      id: _stableCallId({
        'problemName': problemName,
        'startedAt': startedAt.toIso8601String(),
        'endedAt': endedAt.toIso8601String(),
        'reason': reason,
        'reasonTitle': reasonTitle,
      }),
      problemName: problemName,
      reason: reason,
      reasonTitle: reasonTitle,
      startedAt: startedAt,
      endedAt: endedAt,
      durationSeconds: duration.inSeconds,
      inviteMemoryIntent: inviteMemoryIntent,
      structured: structured,
      transcript: transcript,
    );
  }
}

class HealthCallMemoryBuilder {
  const HealthCallMemoryBuilder._();

  static HealthCallStructuredSummary buildStructuredSummary({
    required String problemName,
    required String reasonTitle,
    required String inviteMemoryIntent,
    required List<HealthCallTranscriptEntry> transcript,
    required Duration duration,
  }) {
    final userLines = transcript
        .where((entry) => entry.isUser && entry.text.trim().isNotEmpty)
        .map((entry) => _clean(entry.text))
        .toList();
    final allLines = transcript
        .where((entry) => entry.text.trim().isNotEmpty)
        .map((entry) => _clean(entry.text))
        .toList();
    final source = userLines.isEmpty ? allLines : userLines;
    final minutes = duration.inMinutes;
    final overview = source.isEmpty
        ? '$reasonTitle completed for $problemName. Flicko should use this call to continue intake, routine tracking, reminders, dashboard values, and report planning.'
        : '$reasonTitle completed for $problemName in ${minutes <= 0 ? 1 : minutes} min. Main user notes: ${_clip(source.take(3).join(' | '), 520)}';

    return HealthCallStructuredSummary(
      overview: overview,
      problems: _matches(source, const [
        'problem',
        'issue',
        'pareshaan',
        'taklif',
        'concern',
        'health',
      ], fallback: problemName),
      symptoms: _matches(source, const [
        'pain',
        'dard',
        'symptom',
        'sugar',
        'bp',
        'pressure',
        'sleep',
        'stress',
        'mood',
        'tired',
        'weak',
        'bleeding',
        'fever',
      ]),
      routine: _matches(source, const [
        'morning',
        'night',
        'wake',
        'sleep',
        'routine',
        'free',
        'time',
        'dincharya',
        'walk',
        'steps',
      ]),
      food: _matches(source, const [
        'breakfast',
        'lunch',
        'dinner',
        'meal',
        'food',
        'khana',
        'water',
        'snack',
        'craving',
        'photo',
      ]),
      medicine: _matches(source, const [
        'medicine',
        'medication',
        'tablet',
        'dose',
        'insulin',
        'metformin',
        'allergy',
        'diagnosis',
        'doctor',
        'surgery',
      ]),
      reminders: _matches(allLines, const [
        'reminder',
        'remind',
        'call',
        'notify',
        'alarm',
        'schedule',
        'miss',
        'missed',
        'free time',
        'free',
        'time',
        'baje',
        'baad',
        'kal',
        'subah',
        'shaam',
        'raat',
        'yaad',
        'yaad dil',
        'busy',
        'abhi nahi',
      ], fallback: inviteMemoryIntent),
      goals: _matches(source, const [
        'goal',
        'target',
        'weight',
        'fitness',
        'plan',
        'improve',
        'control',
        'reduce',
      ]),
      redFlags: _matches(source, const [
        'chest pain',
        'breath',
        'faint',
        'severe',
        'bleeding',
        'emergency',
        'suicide',
        'unconscious',
      ]),
    );
  }

  static List<String> _matches(
    List<String> lines,
    List<String> keywords, {
    String fallback = '',
  }) {
    final seen = <String>{};
    final result = <String>[];
    for (final line in lines) {
      final lower = line.toLowerCase();
      if (!keywords.any(lower.contains)) {
        continue;
      }
      final clipped = _clip(line, 180);
      if (seen.add(clipped.toLowerCase())) {
        result.add(clipped);
      }
      if (result.length >= 5) {
        break;
      }
    }
    if (result.isEmpty && fallback.trim().isNotEmpty) {
      result.add(_clip(fallback, 180));
    }
    return result;
  }
}

List<String> _stringList(Object? value) {
  if (value is! List) {
    return const <String>[];
  }
  return value
      .map((entry) => entry.toString().trim())
      .where((entry) => entry.isNotEmpty)
      .toList(growable: false);
}

String _clean(String value) {
  return value.trim().replaceAll(RegExp(r'\s+'), ' ');
}

String _clip(String value, int maxLength) {
  final clean = _clean(value);
  if (clean.length <= maxLength) {
    return clean;
  }
  return '${clean.substring(0, maxLength - 3).trim()}...';
}

int _intValue(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.round();
  }
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

String _stableCallId(Map<dynamic, dynamic> source) {
  final raw = source.entries
      .map((entry) => '${entry.key}:${entry.value}')
      .join('|')
      .codeUnits;
  var hash = 0;
  for (final unit in raw) {
    hash = 0x1fffffff & (hash + unit);
    hash = 0x1fffffff & (hash + ((0x0007ffff & hash) << 10));
    hash ^= hash >> 6;
  }
  hash = 0x1fffffff & (hash + ((0x03ffffff & hash) << 3));
  hash ^= hash >> 11;
  hash = 0x1fffffff & (hash + ((0x00003fff & hash) << 15));
  return 'call-$hash';
}

String _reasonTitle(String reason) {
  return switch (reason.trim()) {
    'setup-intake' => 'Health setup call',
    'daily-routine' => 'Daily routine call',
    'missed-meal-photo' => 'Meal photo follow-up',
    'missed-care-task' => 'Care task follow-up',
    _ => 'Flicko health call',
  };
}
