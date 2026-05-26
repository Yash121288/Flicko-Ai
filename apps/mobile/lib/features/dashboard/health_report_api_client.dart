import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../backend_api_defaults.dart';
import 'gemini_health_chat_client.dart';

class HealthReportApiException implements Exception {
  const HealthReportApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class HealthReportSyncResult {
  const HealthReportSyncResult({
    required this.title,
    required this.pdfUrl,
    required this.htmlUrl,
    this.pdfApiUrl = '',
    this.htmlApiUrl = '',
    this.intakeSummary = '',
    this.intakeCompleted = false,
    this.dashboardValues = const <String, Object?>{},
    this.dashboardNotes = const <String>[],
    this.reminders = const <String>[],
    this.savedReminders = const <Map<String, dynamic>>[],
    this.careTasks = const <Map<String, dynamic>>[],
    this.healthLogs = const <Map<String, dynamic>>[],
    this.safetyEvents = const <Map<String, dynamic>>[],
    this.analysis = const <String, Object?>{},
  });

  final String title;
  final String pdfUrl;
  final String htmlUrl;
  final String pdfApiUrl;
  final String htmlApiUrl;
  final String intakeSummary;
  final bool intakeCompleted;
  final Map<String, Object?> dashboardValues;
  final List<String> dashboardNotes;
  final List<String> reminders;
  final List<Map<String, dynamic>> savedReminders;
  final List<Map<String, dynamic>> careTasks;
  final List<Map<String, dynamic>> healthLogs;
  final List<Map<String, dynamic>> safetyEvents;
  final Map<String, Object?> analysis;

  factory HealthReportSyncResult.fromJson(Map<String, dynamic> json) {
    final dashboard = json['dashboard_values'];
    final analysis = json['analysis'];
    final pdfApiUrl = json['pdf_url']?.toString() ?? '';
    final htmlApiUrl = json['html_url']?.toString() ?? '';
    return HealthReportSyncResult(
      title: json['title']?.toString() ?? 'Flicko AI Intake Report',
      pdfUrl: json['pdf_open_url']?.toString() ?? pdfApiUrl,
      htmlUrl: json['html_open_url']?.toString() ?? htmlApiUrl,
      pdfApiUrl: pdfApiUrl,
      htmlApiUrl: htmlApiUrl,
      intakeSummary: json['intake_summary']?.toString() ?? '',
      intakeCompleted: json['intake_completed'] == true,
      dashboardValues: dashboard is Map
          ? Map<String, Object?>.from(dashboard)
          : const <String, Object?>{},
      dashboardNotes: _stringList(json['dashboard_notes']),
      reminders: _stringList(json['reminders']),
      savedReminders: _mapList(json['saved_reminders']),
      careTasks: _mapList(json['care_tasks']),
      healthLogs: _mapList(json['health_logs']),
      safetyEvents: _mapList(json['safety_events']),
      analysis: analysis is Map
          ? Map<String, Object?>.from(analysis)
          : const <String, Object?>{},
    );
  }
}

class HealthReportApiClient {
  const HealthReportApiClient({
    this.baseUrl = const String.fromEnvironment(
      'FLICKO_API_BASE_URL',
      defaultValue: '',
    ),
  });

  final String baseUrl;

  static const _fallbackBaseUrls = String.fromEnvironment(
    'FLICKO_API_BASE_URL_FALLBACKS',
    defaultValue: '',
  );

  Future<HealthReportSyncResult> createIntakeReport({
    required String token,
    required String title,
    required String problemName,
    required String intakeSummary,
    required Map<String, Object?> dashboardValues,
    required List<String> reminders,
    required List<AiCoachMessage> transcript,
    List<Map<String, Object?>>? transcriptPayload,
    Map<String, Object?> sourcePayload = const <String, Object?>{},
    String source = '',
    String rawTranscriptText = '',
    bool analyzeConversation = true,
  }) async {
    final trimmedToken = token.trim();
    if (trimmedToken.isEmpty) {
      throw const HealthReportApiException('Missing login token.');
    }

    final body = <String, Object?>{
      'title': title,
      'problem_name': problemName,
      'intake_summary': intakeSummary,
      'dashboard_values': dashboardValues,
      'reminders': reminders,
      'transcript':
          transcriptPayload ??
          transcript.map((message) => message.toJson()).toList(),
      'source': source,
      'source_payload': sourcePayload,
      'raw_transcript_text': rawTranscriptText,
      'analyze_conversation': analyzeConversation,
    };

    final urls = _candidateBaseUrls();
    for (final candidate in urls) {
      try {
        return await _postToBaseUrl(candidate, body, trimmedToken);
      } on HealthReportApiException {
        rethrow;
      } on TimeoutException {
        continue;
      } on SocketException {
        continue;
      } on http.ClientException {
        continue;
      } on FormatException {
        throw const HealthReportApiException(
          'Backend returned an invalid report response.',
        );
      }
    }

    throw HealthReportApiException(
      'Could not reach Flicko backend. Tried: ${urls.join(', ')}.',
    );
  }

  Future<List<HealthReportSyncResult>> fetchReportHistory({
    required String token,
  }) async {
    final trimmedToken = token.trim();
    if (trimmedToken.isEmpty) {
      throw const HealthReportApiException('Missing login token.');
    }

    final urls = _candidateBaseUrls();
    for (final candidate in urls) {
      try {
        return await _getFromBaseUrl(candidate, trimmedToken);
      } on HealthReportApiException {
        rethrow;
      } on TimeoutException {
        continue;
      } on SocketException {
        continue;
      } on http.ClientException {
        continue;
      } on FormatException {
        throw const HealthReportApiException(
          'Backend returned an invalid report history response.',
        );
      }
    }

    throw HealthReportApiException(
      'Could not reach Flicko backend. Tried: ${urls.join(', ')}.',
    );
  }

  Future<HealthReportSyncResult> _postToBaseUrl(
    String targetBaseUrl,
    Map<String, Object?> body,
    String token,
  ) async {
    final uri = Uri.parse('$targetBaseUrl/auth/intake-reports/');
    final response = await http
        .post(
          uri,
          headers: {
            'Accept': 'application/json',
            'Authorization': 'Token $token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 20));

    final decoded = response.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(response.body);
    final json = decoded is Map<String, dynamic>
        ? decoded
        : <String, dynamic>{};

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return HealthReportSyncResult.fromJson(json);
    }

    final message =
        json['detail']?.toString() ??
        json['error']?.toString() ??
        'Report sync failed with HTTP ${response.statusCode}.';
    throw HealthReportApiException(message);
  }

  Future<List<HealthReportSyncResult>> _getFromBaseUrl(
    String targetBaseUrl,
    String token,
  ) async {
    final uri = Uri.parse('$targetBaseUrl/auth/intake-reports/');
    final response = await http
        .get(
          uri,
          headers: {
            'Accept': 'application/json',
            'Authorization': 'Token $token',
          },
        )
        .timeout(const Duration(seconds: 20));

    final decoded = response.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(response.body);
    final json = decoded is Map<String, dynamic>
        ? decoded
        : <String, dynamic>{};

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final reports = json['reports'];
      if (reports is! List) {
        return const <HealthReportSyncResult>[];
      }
      return reports
          .whereType<Map>()
          .map(
            (entry) => HealthReportSyncResult.fromJson(
              Map<String, dynamic>.from(entry),
            ),
          )
          .toList(growable: false);
    }

    final message =
        json['detail']?.toString() ??
        json['error']?.toString() ??
        'Report history fetch failed with HTTP ${response.statusCode}.';
    throw HealthReportApiException(message);
  }

  List<String> _candidateBaseUrls() {
    return flickoDefaultApiBaseUrlCandidates(
      preferredBaseUrl: baseUrl,
      fallbackBaseUrlsCsv: _fallbackBaseUrls,
    );
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

List<Map<String, dynamic>> _mapList(Object? value) {
  if (value is! List) {
    return const <Map<String, dynamic>>[];
  }
  return value
      .whereType<Map>()
      .map((entry) => Map<String, dynamic>.from(entry))
      .toList(growable: false);
}
