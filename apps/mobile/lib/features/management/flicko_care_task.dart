enum FlickoCareTaskType {
  medicine,
  meal,
  measurement,
  activity,
  water,
  sleep,
  symptom,
  appointment,
  custom,
}

class FlickoCareTask {
  const FlickoCareTask({
    required this.id,
    required this.type,
    required this.title,
    required this.detail,
    required this.problemName,
    required this.createdAt,
    required this.updatedAt,
    this.timeLabel = '',
    this.enabled = true,
    this.lastCompletedAt,
  });

  final String id;
  final FlickoCareTaskType type;
  final String title;
  final String detail;
  final String timeLabel;
  final String problemName;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastCompletedAt;
  final bool enabled;

  bool isDoneOn(DateTime date) {
    final completed = lastCompletedAt;
    if (completed == null) {
      return false;
    }
    return completed.year == date.year &&
        completed.month == date.month &&
        completed.day == date.day;
  }

  bool get isDoneToday {
    return isDoneOn(DateTime.now());
  }

  String get compactSummary {
    final parts = [
      type.label,
      if (timeLabel.trim().isNotEmpty) timeLabel.trim(),
      title.trim(),
      if (detail.trim().isNotEmpty) detail.trim(),
      isDoneToday ? 'Done today' : 'Pending',
    ];
    return parts.where((value) => value.isNotEmpty).join(' - ');
  }

  FlickoCareTask copyWith({
    FlickoCareTaskType? type,
    String? title,
    String? detail,
    String? timeLabel,
    String? problemName,
    DateTime? updatedAt,
    DateTime? lastCompletedAt,
    bool clearCompleted = false,
    bool? enabled,
  }) {
    return FlickoCareTask(
      id: id,
      type: type ?? this.type,
      title: title ?? this.title,
      detail: detail ?? this.detail,
      timeLabel: timeLabel ?? this.timeLabel,
      problemName: problemName ?? this.problemName,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastCompletedAt: clearCompleted
          ? null
          : lastCompletedAt ?? this.lastCompletedAt,
      enabled: enabled ?? this.enabled,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'type': type.name,
      'title': title,
      'detail': detail,
      'timeLabel': timeLabel,
      'problemName': problemName,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'lastCompletedAt': lastCompletedAt?.toIso8601String(),
      'enabled': enabled,
    };
  }

  static FlickoCareTask create({
    required FlickoCareTaskType type,
    required String title,
    required String detail,
    required String timeLabel,
    required String problemName,
    DateTime? now,
  }) {
    final effectiveNow = now ?? DateTime.now();
    final cleanTitle = title.trim().isEmpty ? type.defaultTitle : title.trim();
    return FlickoCareTask(
      id: _stableKey(
        '${problemName.trim()}|${type.name}|$cleanTitle|${timeLabel.trim()}',
      ),
      type: type,
      title: cleanTitle,
      detail: detail.trim(),
      timeLabel: timeLabel.trim(),
      problemName: problemName.trim(),
      createdAt: effectiveNow,
      updatedAt: effectiveNow,
    );
  }

  static FlickoCareTask? fromJson(Map<String, dynamic> json) {
    final title = _asString(json['title']);
    if (title.isEmpty) {
      return null;
    }
    final typeName = _asString(json['type']);
    final type = FlickoCareTaskType.values.firstWhere(
      (entry) => entry.name == typeName,
      orElse: () => FlickoCareTaskType.custom,
    );
    final id = _asString(json['id']).isNotEmpty
        ? _asString(json['id'])
        : _stableKey('${_asString(json['problemName'])}|${type.name}|$title');
    return FlickoCareTask(
      id: id,
      type: type,
      title: title,
      detail: _asString(json['detail']),
      timeLabel: _asString(json['timeLabel']),
      problemName: _asString(json['problemName']),
      createdAt: _asDate(json['createdAt']),
      updatedAt: _asDate(json['updatedAt']),
      lastCompletedAt: _nullableDate(json['lastCompletedAt']),
      enabled: json['enabled'] != false,
    );
  }
}

extension FlickoCareTaskTypeLabel on FlickoCareTaskType {
  String get label => switch (this) {
    FlickoCareTaskType.medicine => 'Medicine',
    FlickoCareTaskType.meal => 'Meal',
    FlickoCareTaskType.measurement => 'Measurement',
    FlickoCareTaskType.activity => 'Activity',
    FlickoCareTaskType.water => 'Water',
    FlickoCareTaskType.sleep => 'Sleep',
    FlickoCareTaskType.symptom => 'Symptom',
    FlickoCareTaskType.appointment => 'Appointment',
    FlickoCareTaskType.custom => 'Custom',
  };

  String get defaultTitle => switch (this) {
    FlickoCareTaskType.medicine => 'Take medicine',
    FlickoCareTaskType.meal => 'Meal check',
    FlickoCareTaskType.measurement => 'Health reading',
    FlickoCareTaskType.activity => 'Activity goal',
    FlickoCareTaskType.water => 'Water target',
    FlickoCareTaskType.sleep => 'Sleep routine',
    FlickoCareTaskType.symptom => 'Symptom check',
    FlickoCareTaskType.appointment => 'Doctor visit',
    FlickoCareTaskType.custom => 'Care task',
  };
}

typedef FlickoCareTaskWriter = Future<bool> Function(FlickoCareTask task);
typedef FlickoCareTaskDeleter = Future<bool> Function(FlickoCareTask task);

String _asString(Object? value) => value?.toString().trim() ?? '';

DateTime _asDate(Object? value) {
  return DateTime.tryParse(value?.toString() ?? '') ?? DateTime.now();
}

DateTime? _nullableDate(Object? value) {
  final raw = value?.toString();
  if (raw == null || raw.trim().isEmpty) {
    return null;
  }
  return DateTime.tryParse(raw);
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
