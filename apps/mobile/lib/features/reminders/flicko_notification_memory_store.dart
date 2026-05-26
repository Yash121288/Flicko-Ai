import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class FlickoNotificationMemoryEntry {
  const FlickoNotificationMemoryEntry({
    required this.id,
    required this.eventType,
    required this.title,
    required this.body,
    required this.payload,
    required this.createdAt,
  });

  final String id;
  final String eventType;
  final String title;
  final String body;
  final String payload;
  final DateTime createdAt;

  String get promptLine {
    final time = _timeLabel(createdAt);
    final cleanTitle = title.trim().isEmpty ? 'Flicko notification' : title;
    final cleanBody = body.trim();
    final detail = cleanBody.isEmpty ? cleanTitle : '$cleanTitle - $cleanBody';
    return '$time [$eventType] $detail';
  }

  Map<String, Object> toJson() {
    return {
      'id': id,
      'eventType': eventType,
      'title': title,
      'body': body,
      'payload': payload,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  static FlickoNotificationMemoryEntry? fromJson(Map<String, dynamic> json) {
    final payload = json['payload']?.toString().trim() ?? '';
    final title = json['title']?.toString().trim() ?? '';
    final body = json['body']?.toString().trim() ?? '';
    final eventType = json['eventType']?.toString().trim() ?? '';
    final createdAt = DateTime.tryParse(json['createdAt']?.toString() ?? '');
    if (eventType.isEmpty || createdAt == null) {
      return null;
    }
    return FlickoNotificationMemoryEntry(
      id: json['id']?.toString().trim().isNotEmpty == true
          ? json['id'].toString().trim()
          : _stableKey('$eventType|$payload|${createdAt.toIso8601String()}'),
      eventType: eventType,
      title: title,
      body: body,
      payload: payload,
      createdAt: createdAt,
    );
  }

  static String _timeLabel(DateTime value) {
    final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
    final minute = value.minute.toString().padLeft(2, '0');
    final suffix = value.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $suffix';
  }
}

class FlickoNotificationMemoryStore {
  FlickoNotificationMemoryStore({FlutterSecureStorage? secureStorage})
    : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  static const _key = 'flicko_notification_memory_v1';
  static const _maxEntries = 80;

  final FlutterSecureStorage _secureStorage;

  Future<void> record({
    required String eventType,
    required String title,
    required String body,
    required String payload,
    DateTime? createdAt,
  }) async {
    final cleanEvent = eventType.trim();
    if (cleanEvent.isEmpty) {
      return;
    }
    final now = createdAt ?? DateTime.now();
    final entry = FlickoNotificationMemoryEntry(
      id: _stableKey('$cleanEvent|$payload|${now.toIso8601String()}'),
      eventType: cleanEvent,
      title: title.trim(),
      body: body.trim(),
      payload: payload.trim(),
      createdAt: now,
    );
    final entries = await readEntries();
    final dedupeKey = _dedupeKey(entry);
    final next = <FlickoNotificationMemoryEntry>[
      entry,
      ...entries.where((item) => _dedupeKey(item) != dedupeKey),
    ].take(_maxEntries).toList(growable: false);
    await _write(next);
  }

  Future<List<FlickoNotificationMemoryEntry>> readEntries() async {
    final raw = await _readRaw();
    if (raw == null || raw.trim().isEmpty) {
      return const <FlickoNotificationMemoryEntry>[];
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return const <FlickoNotificationMemoryEntry>[];
      }
      final entries = decoded
          .whereType<Map>()
          .map(
            (entry) => FlickoNotificationMemoryEntry.fromJson(
              Map<String, dynamic>.from(entry),
            ),
          )
          .whereType<FlickoNotificationMemoryEntry>()
          .toList();
      entries.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return entries.take(_maxEntries).toList(growable: false);
    } catch (error) {
      debugPrint('Flicko notification memory decode skipped: $error');
      return const <FlickoNotificationMemoryEntry>[];
    }
  }

  Future<String> summaryForPrompt({int limit = 10}) async {
    final entries = await readEntries();
    if (entries.isEmpty) {
      return 'Notification memory: no saved notification history yet.';
    }
    final recent = entries.take(limit).map((entry) => '- ${entry.promptLine}');
    final pendingCallInvites = entries
        .where(
          (entry) =>
              entry.eventType == 'call_invite_scheduled' ||
              entry.eventType == 'call_invite_shown',
        )
        .take(3)
        .map((entry) => entry.promptLine)
        .toList();
    final missedOrDeclined = entries
        .where(
          (entry) =>
              entry.eventType == 'call_invite_declined' ||
              entry.eventType == 'notification_tapped_late',
        )
        .take(3)
        .map((entry) => entry.promptLine)
        .toList();
    return [
      'Notification memory:',
      ...recent,
      if (pendingCallInvites.isNotEmpty)
        'Recent call invite state: ${pendingCallInvites.join(' | ')}',
      if (missedOrDeclined.isNotEmpty)
        'Missed or declined notification state: ${missedOrDeclined.join(' | ')}',
    ].join('\n');
  }

  Future<void> _write(List<FlickoNotificationMemoryEntry> entries) async {
    final payload = jsonEncode(entries.map((entry) => entry.toJson()).toList());
    try {
      await _secureStorage.write(key: _key, value: payload);
    } catch (error) {
      debugPrint('Flicko notification memory write skipped: $error');
    }
  }

  Future<String?> _readRaw() async {
    try {
      return await _secureStorage.read(key: _key);
    } catch (error) {
      debugPrint('Flicko notification memory read skipped: $error');
      return null;
    }
  }

  String _dedupeKey(FlickoNotificationMemoryEntry entry) {
    return '${entry.eventType}|${entry.payload}|${entry.title}|${entry.body}';
  }
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
