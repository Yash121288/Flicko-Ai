import 'coach_update_parser.dart';
import 'gemini_health_chat_client.dart';
import 'ai_call_models.dart';

enum FlickoReportGenerationKind { setup, weekly, special }

class FlickoReportGenerationSnapshot {
  const FlickoReportGenerationSnapshot({
    required this.problemName,
    required this.intakeCompleted,
    required this.intakeSummary,
    required this.syncedReportKeys,
    required this.reportCount,
  });

  final String problemName;
  final bool intakeCompleted;
  final String intakeSummary;
  final List<String> syncedReportKeys;
  final int reportCount;
}

class FlickoReportGenerationRequest {
  const FlickoReportGenerationRequest({
    required this.kind,
    required this.syncKey,
    required this.title,
    required this.source,
  });

  final FlickoReportGenerationKind kind;
  final String syncKey;
  final String title;
  final String source;
}

class FlickoReportGenerationCoordinator {
  const FlickoReportGenerationCoordinator();

  FlickoReportGenerationRequest? setupReportIfNeeded(
    FlickoReportGenerationSnapshot snapshot,
  ) {
    if (!_canGenerate(snapshot)) {
      return null;
    }
    if (_hasSetupReportKey(snapshot)) {
      return null;
    }
    return FlickoReportGenerationRequest(
      kind: FlickoReportGenerationKind.setup,
      syncKey: _setupKey(snapshot.problemName),
      title: '${snapshot.problemName} Setup Report',
      source: 'setup_auto',
    );
  }

  FlickoReportGenerationRequest? weeklyReportIfDue(
    FlickoReportGenerationSnapshot snapshot, {
    DateTime? now,
  }) {
    if (!_canGenerate(snapshot) || !_hasWeeklyBaseline(snapshot)) {
      return null;
    }
    final weeklyKey = _weeklyKey(snapshot.problemName, now ?? DateTime.now());
    if (snapshot.syncedReportKeys.contains(weeklyKey)) {
      return null;
    }
    return FlickoReportGenerationRequest(
      kind: FlickoReportGenerationKind.weekly,
      syncKey: weeklyKey,
      title: '${snapshot.problemName} Weekly Report',
      source: 'weekly_auto',
    );
  }

  FlickoReportGenerationRequest? manualSpecialReport(
    FlickoReportGenerationSnapshot snapshot, {
    DateTime? now,
  }) {
    if (!_canGenerate(snapshot)) {
      return null;
    }
    final resolvedNow = now ?? DateTime.now();
    return FlickoReportGenerationRequest(
      kind: FlickoReportGenerationKind.special,
      syncKey:
          'special-report:${_normalizedProblem(snapshot.problemName)}:${resolvedNow.microsecondsSinceEpoch}',
      title: '${snapshot.problemName} Special Report',
      source: 'special_manual',
    );
  }

  FlickoReportGenerationRequest? chatAutoRequest({
    required FlickoReportGenerationSnapshot previous,
    required FlickoReportGenerationSnapshot next,
    required CoachAppUpdate update,
    required List<AiCoachMessage> history,
    DateTime? now,
  }) {
    if (!_canGenerate(next)) {
      return null;
    }
    if ((!previous.intakeCompleted && next.intakeCompleted) ||
        update.intakeComplete) {
      final setup = setupReportIfNeeded(next);
      if (setup != null) {
        return setup;
      }
    }
    final requestText = latestExplicitSpecialReportRequest(history);
    if (requestText == null) {
      return null;
    }
    final resolvedNow = now ?? DateTime.now();
    return FlickoReportGenerationRequest(
      kind: FlickoReportGenerationKind.special,
      syncKey:
          'special-report:${_normalizedProblem(next.problemName)}:${_stableKey(requestText.toLowerCase())}:${resolvedNow.year}-${resolvedNow.month}-${resolvedNow.day}',
      title: '${next.problemName} Special Report',
      source: 'special_chat_request',
    );
  }

  FlickoReportGenerationRequest? callAutoRequest({
    required FlickoReportGenerationSnapshot snapshot,
    required AiCallSessionSummary summary,
    DateTime? now,
  }) {
    if (!_canGenerate(snapshot)) {
      return null;
    }
    if (summary.reason == AiCallInviteReason.setupIntake) {
      final setup = setupReportIfNeeded(snapshot);
      if (setup != null) {
        return setup;
      }
    }
    if (summary.reason == AiCallInviteReason.dailyRoutine ||
        summary.reason == AiCallInviteReason.notification) {
      return weeklyReportIfDue(snapshot, now: now ?? summary.endedAt);
    }
    return null;
  }

  String? latestExplicitSpecialReportRequest(List<AiCoachMessage> history) {
    for (final message in history.reversed) {
      if (!message.isUser) {
        continue;
      }
      if (message.source.trim().toLowerCase() != 'chat') {
        continue;
      }
      final text = message.text.trim();
      if (_looksLikeExplicitSpecialReportRequest(text)) {
        return text;
      }
      return null;
    }
    return null;
  }

  bool _canGenerate(FlickoReportGenerationSnapshot snapshot) {
    return snapshot.intakeCompleted && snapshot.intakeSummary.trim().isNotEmpty;
  }

  bool _hasSetupReportKey(FlickoReportGenerationSnapshot snapshot) {
    return snapshot.syncedReportKeys.contains(_setupKey(snapshot.problemName));
  }

  bool _hasWeeklyBaseline(FlickoReportGenerationSnapshot snapshot) {
    return _hasSetupReportKey(snapshot) || snapshot.reportCount > 0;
  }

  String _setupKey(String problemName) {
    return 'setup-report:${_normalizedProblem(problemName)}';
  }

  String _weeklyKey(String problemName, DateTime now) {
    final weekBucket = ((now.difference(DateTime(now.year, 1, 1)).inDays) ~/ 7)
        .toString()
        .padLeft(2, '0');
    return 'weekly-report:${_normalizedProblem(problemName)}:${now.year}-$weekBucket';
  }

  bool _looksLikeExplicitSpecialReportRequest(String text) {
    final lower = text.trim().toLowerCase();
    if (lower.isEmpty) {
      return false;
    }
    if (lower.contains('upload report') ||
        lower.contains('lab report') ||
        lower.contains('medical report upload')) {
      return false;
    }
    final mentionsReport = RegExp(
      r'\b(report|pdf|summary)\b',
      caseSensitive: false,
    ).hasMatch(lower);
    if (!mentionsReport) {
      return false;
    }
    return lower.contains('special report') ||
        lower.contains('weekly report') ||
        lower.contains('doctor-ready report') ||
        RegExp(
          r'\b(create|generate|make|prepare|need|want|give)\b',
          caseSensitive: false,
        ).hasMatch(lower);
  }

  String _normalizedProblem(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');
  }

  String _stableKey(String source) {
    var hash = 0;
    for (final codeUnit in source.codeUnits) {
      hash = (hash * 31 + codeUnit) & 0x3fffffff;
    }
    return '$hash-${source.length}';
  }
}
