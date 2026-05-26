class FlickoPendingAppRecordOp {
  const FlickoPendingAppRecordOp({
    required this.id,
    required this.action,
    required this.recordType,
    required this.externalId,
    required this.payload,
    required this.createdAt,
    this.attemptCount = 0,
  });

  final String id;
  final String action;
  final String recordType;
  final String externalId;
  final Map<String, Object?> payload;
  final DateTime createdAt;
  final int attemptCount;

  bool get isDelete => action == 'delete';
  bool get isUpsert => action == 'upsert';
  String get mergeKey => '$recordType|$externalId';
  String get operationKey => '$action|$mergeKey';

  FlickoPendingAppRecordOp copyWithAttempt() {
    return FlickoPendingAppRecordOp(
      id: id,
      action: action,
      recordType: recordType,
      externalId: externalId,
      payload: payload,
      createdAt: createdAt,
      attemptCount: attemptCount + 1,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'action': action,
      'recordType': recordType,
      'externalId': externalId,
      'payload': payload,
      'createdAt': createdAt.toIso8601String(),
      'attemptCount': attemptCount,
    };
  }

  static FlickoPendingAppRecordOp upsert({
    required String recordType,
    required Map<String, Object?> payload,
  }) {
    final externalId = _externalIdFromPayload(payload);
    final now = DateTime.now();
    return FlickoPendingAppRecordOp(
      id: _stableKey(
        'upsert|$recordType|$externalId|${now.microsecondsSinceEpoch}',
      ),
      action: 'upsert',
      recordType: recordType.trim(),
      externalId: externalId,
      payload: Map<String, Object?>.from(payload),
      createdAt: now,
    );
  }

  static FlickoPendingAppRecordOp delete({
    required String recordType,
    required String externalId,
  }) {
    final now = DateTime.now();
    final cleanId = externalId.trim();
    return FlickoPendingAppRecordOp(
      id: _stableKey(
        'delete|$recordType|$cleanId|${now.microsecondsSinceEpoch}',
      ),
      action: 'delete',
      recordType: recordType.trim(),
      externalId: cleanId,
      payload: const <String, Object?>{},
      createdAt: now,
    );
  }

  static FlickoPendingAppRecordOp? fromJson(Map<String, dynamic> json) {
    final action = json['action']?.toString().trim() ?? '';
    final recordType = json['recordType']?.toString().trim() ?? '';
    final externalId = json['externalId']?.toString().trim() ?? '';
    if ((action != 'upsert' && action != 'delete') ||
        recordType.isEmpty ||
        externalId.isEmpty) {
      return null;
    }
    final payload = json['payload'];
    return FlickoPendingAppRecordOp(
      id: json['id']?.toString().trim().isNotEmpty == true
          ? json['id'].toString().trim()
          : _stableKey('$action|$recordType|$externalId'),
      action: action,
      recordType: recordType,
      externalId: externalId,
      payload: payload is Map
          ? Map<String, Object?>.from(payload)
          : const <String, Object?>{},
      createdAt:
          DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.now(),
      attemptCount: _int(json['attemptCount']),
    );
  }
}

String _externalIdFromPayload(Map<String, Object?> payload) {
  final value = payload['id']?.toString().trim() ?? '';
  return value.isEmpty ? _stableKey(payload.toString()) : value;
}

int _int(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.round();
  }
  return int.tryParse(value?.toString() ?? '') ?? 0;
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
