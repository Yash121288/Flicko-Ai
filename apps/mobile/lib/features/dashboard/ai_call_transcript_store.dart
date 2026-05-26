import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'ai_call_models.dart';
import 'ai_call_memory.dart';

class AiCallTranscriptSessionDraft {
  const AiCallTranscriptSessionDraft({
    required this.sessionId,
    required this.problemName,
    required this.reason,
    required this.subtitle,
    required this.profileContext,
    required this.startedAt,
    required this.updatedAt,
    this.completedAt,
    this.transcript = const <HealthCallTranscriptEntry>[],
  });

  final String sessionId;
  final String problemName;
  final AiCallInviteReason reason;
  final String subtitle;
  final String profileContext;
  final DateTime startedAt;
  final DateTime updatedAt;
  final DateTime? completedAt;
  final List<HealthCallTranscriptEntry> transcript;

  bool get isCompleted => completedAt != null;

  bool get hasTranscript =>
      transcript.any((entry) => entry.text.trim().isNotEmpty);
}

class AiCallTranscriptStore {
  AiCallTranscriptStore({FlutterSecureStorage? secureStorage})
    : secureStorage = secureStorage ?? const FlutterSecureStorage();

  static const _activeSessionKey = 'flicko_active_call_transcript_session_v1';
  static const _sessionPrefix = 'flicko_call_transcript_session_v1_';

  final FlutterSecureStorage secureStorage;

  Future<void> beginSession({
    required String sessionId,
    required String problemName,
    required AiCallInviteReason reason,
    required String subtitle,
    required String profileContext,
    required DateTime startedAt,
  }) async {
    final payload = <String, Object?>{
      'sessionId': sessionId,
      'problemName': problemName,
      'reason': reason.payloadKey,
      'subtitle': subtitle,
      'profileContext': profileContext,
      'startedAt': startedAt.toIso8601String(),
      'updatedAt': startedAt.toIso8601String(),
      'completedAt': '',
      'transcript': <Object>[],
    };
    await _writeJson(_sessionKey(sessionId), payload);
    await _writeString(_activeSessionKey, sessionId);
  }

  Future<void> appendEntry({
    required String sessionId,
    required HealthCallTranscriptEntry entry,
  }) async {
    if (entry.text.trim().isEmpty) {
      return;
    }
    final payload =
        await _readSessionPayload(sessionId) ??
        <String, Object?>{
          'sessionId': sessionId,
          'problemName': '',
          'reason': AiCallInviteReason.notification.payloadKey,
          'subtitle': '',
          'profileContext': '',
          'startedAt': DateTime.now().toIso8601String(),
          'updatedAt': DateTime.now().toIso8601String(),
          'completedAt': '',
          'transcript': <Object>[],
        };
    final rawTranscript = payload['transcript'];
    final transcript = rawTranscript is List
        ? rawTranscript.whereType<Map>().map(Map<String, dynamic>.from).toList()
        : <Map<String, dynamic>>[];
    final entryJson = entry.toJson();
    final duplicate =
        transcript.isNotEmpty &&
        _dedupeKey(transcript.last) == _dedupeKey(entryJson);
    if (!duplicate) {
      transcript.add(entryJson);
    }
    while (transcript.length > 500) {
      transcript.removeAt(0);
    }
    payload['transcript'] = transcript;
    payload['updatedAt'] = DateTime.now().toIso8601String();
    await _writeJson(_sessionKey(sessionId), payload);
  }

  Future<List<HealthCallTranscriptEntry>> readTranscript(
    String sessionId,
  ) async {
    final payload = await _readSessionPayload(sessionId);
    final rawTranscript = payload?['transcript'];
    if (rawTranscript is! List) {
      return const <HealthCallTranscriptEntry>[];
    }
    return rawTranscript
        .whereType<Map>()
        .map(
          (entry) => HealthCallTranscriptEntry.fromJson(
            Map<String, dynamic>.from(entry),
          ),
        )
        .where((entry) => entry.text.trim().isNotEmpty)
        .toList(growable: false);
  }

  Future<List<HealthCallTranscriptEntry>> readActiveTranscript() async {
    final session = await readActiveSession();
    return session?.transcript ?? const <HealthCallTranscriptEntry>[];
  }

  Future<AiCallTranscriptSessionDraft?> readActiveSession() async {
    final activeSessionId = await _readString(_activeSessionKey);
    if (activeSessionId == null || activeSessionId.trim().isEmpty) {
      return null;
    }
    return readSession(activeSessionId.trim());
  }

  Future<AiCallTranscriptSessionDraft?> readSession(String sessionId) async {
    final payload = await _readSessionPayload(sessionId);
    if (payload == null) {
      return null;
    }
    final rawTranscript = payload['transcript'];
    final transcript = rawTranscript is List
        ? rawTranscript
              .whereType<Map>()
              .map(
                (entry) => HealthCallTranscriptEntry.fromJson(
                  Map<String, dynamic>.from(entry),
                ),
              )
              .where((entry) => entry.text.trim().isNotEmpty)
              .toList(growable: false)
        : const <HealthCallTranscriptEntry>[];
    return AiCallTranscriptSessionDraft(
      sessionId: payload['sessionId']?.toString() ?? sessionId,
      problemName: payload['problemName']?.toString() ?? '',
      reason: AiCallInviteReasonLabel.fromPayloadKey(
        payload['reason']?.toString() ?? '',
      ),
      subtitle: payload['subtitle']?.toString() ?? '',
      profileContext: payload['profileContext']?.toString() ?? '',
      startedAt:
          DateTime.tryParse(payload['startedAt']?.toString() ?? '') ??
          DateTime.now(),
      updatedAt:
          DateTime.tryParse(payload['updatedAt']?.toString() ?? '') ??
          DateTime.now(),
      completedAt: DateTime.tryParse(payload['completedAt']?.toString() ?? ''),
      transcript: transcript,
    );
  }

  Future<void> completeSession({
    required String sessionId,
    required List<HealthCallTranscriptEntry> transcript,
  }) async {
    final payload = await _readSessionPayload(sessionId);
    if (payload == null) {
      return;
    }
    payload['transcript'] = transcript.map((entry) => entry.toJson()).toList();
    payload['completedAt'] = DateTime.now().toIso8601String();
    payload['updatedAt'] = DateTime.now().toIso8601String();
    await _writeJson(_sessionKey(sessionId), payload);

    final activeSessionId = await _readString(_activeSessionKey);
    if (activeSessionId == sessionId) {
      await _delete(_activeSessionKey);
    }
  }

  Future<Map<String, dynamic>?> _readSessionPayload(String sessionId) async {
    final raw = await _readString(_sessionKey(sessionId));
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (error) {
      debugPrint('Flicko call transcript decode skipped: $error');
    }
    return null;
  }

  String _sessionKey(String sessionId) => '$_sessionPrefix$sessionId';

  String _dedupeKey(Map<dynamic, dynamic> value) {
    final role = value['role']?.toString() ?? '';
    final text = value['text']?.toString().trim() ?? '';
    final createdAt = value['createdAt']?.toString() ?? '';
    return '$role|$text|$createdAt';
  }

  Future<void> _writeJson(String key, Map<String, Object?> value) async {
    await _writeString(key, jsonEncode(value));
  }

  Future<void> _writeString(String key, String value) async {
    try {
      await secureStorage.write(key: key, value: value);
    } catch (error) {
      debugPrint('Flicko secure call transcript write skipped: $error');
    }
  }

  Future<String?> _readString(String key) async {
    try {
      return await secureStorage.read(key: key);
    } catch (error) {
      debugPrint('Flicko secure call transcript read skipped: $error');
      return null;
    }
  }

  Future<void> _delete(String key) async {
    try {
      await secureStorage.delete(key: key);
    } catch (error) {
      debugPrint('Flicko secure call transcript delete skipped: $error');
    }
  }
}
