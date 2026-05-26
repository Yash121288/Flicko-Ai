enum HealthLogType {
  weight,
  glucose,
  bloodPressure,
  meal,
  water,
  steps,
  sleep,
  mood,
  medicine,
  symptom,
  activity,
}

class HealthLogEntry {
  const HealthLogEntry({
    required this.id,
    required this.type,
    required this.title,
    required this.value,
    required this.unit,
    required this.note,
    required this.problemName,
    required this.createdAt,
  });

  final String id;
  final HealthLogType type;
  final String title;
  final String value;
  final String unit;
  final String note;
  final String problemName;
  final DateTime createdAt;

  factory HealthLogEntry.create({
    required HealthLogType type,
    required String title,
    required String value,
    String unit = '',
    String note = '',
    String problemName = '',
  }) {
    final now = DateTime.now();
    return HealthLogEntry(
      id: '${now.microsecondsSinceEpoch}-${type.name}',
      type: type,
      title: title.trim().isEmpty ? type.defaultTitle : title.trim(),
      value: value.trim(),
      unit: unit.trim(),
      note: note.trim(),
      problemName: problemName.trim(),
      createdAt: now,
    );
  }

  factory HealthLogEntry.fromJson(Map<String, dynamic> json) {
    final typeName = json['type']?.toString() ?? '';
    return HealthLogEntry(
      id: _string(json['id'], fallback: DateTime.now().toIso8601String()),
      type: HealthLogType.values.firstWhere(
        (type) => type.name == typeName,
        orElse: () => HealthLogType.symptom,
      ),
      title: _string(json['title']),
      value: _string(json['value']),
      unit: _string(json['unit']),
      note: _string(json['note']),
      problemName: _string(json['problemName']),
      createdAt:
          DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.now(),
    );
  }

  Map<String, Object> toJson() {
    return {
      'id': id,
      'type': type.name,
      'title': title,
      'value': value,
      'unit': unit,
      'note': note,
      'problemName': problemName,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  String get valueText {
    final parts = [
      value,
      unit,
    ].map((part) => part.trim()).where((part) => part.isNotEmpty).toList();
    return parts.isEmpty ? note : parts.join(' ');
  }

  String get compactSummary {
    final pieces = <String>[
      title,
      if (valueText.trim().isNotEmpty) valueText,
      if (note.trim().isNotEmpty) note,
    ];
    return pieces.join(': ');
  }
}

extension HealthLogTypeLabel on HealthLogType {
  String get label => switch (this) {
    HealthLogType.weight => 'Weight',
    HealthLogType.glucose => 'Glucose',
    HealthLogType.bloodPressure => 'Blood pressure',
    HealthLogType.meal => 'Meal',
    HealthLogType.water => 'Water',
    HealthLogType.steps => 'Steps',
    HealthLogType.sleep => 'Sleep',
    HealthLogType.mood => 'Mood',
    HealthLogType.medicine => 'Medicine',
    HealthLogType.symptom => 'Symptom',
    HealthLogType.activity => 'Activity',
  };

  String get defaultTitle => switch (this) {
    HealthLogType.weight => 'Weight log',
    HealthLogType.glucose => 'Blood sugar log',
    HealthLogType.bloodPressure => 'BP reading',
    HealthLogType.meal => 'Meal log',
    HealthLogType.water => 'Water intake',
    HealthLogType.steps => 'Step count',
    HealthLogType.sleep => 'Sleep log',
    HealthLogType.mood => 'Mood check',
    HealthLogType.medicine => 'Medicine check',
    HealthLogType.symptom => 'Symptom log',
    HealthLogType.activity => 'Activity log',
  };

  String get defaultUnit => switch (this) {
    HealthLogType.weight => 'kg',
    HealthLogType.glucose => 'mg/dL',
    HealthLogType.bloodPressure => '',
    HealthLogType.meal => 'score',
    HealthLogType.water => 'L',
    HealthLogType.steps => 'steps',
    HealthLogType.sleep => 'hrs',
    HealthLogType.mood => '/10',
    HealthLogType.medicine => '',
    HealthLogType.symptom => '/10',
    HealthLogType.activity => 'min',
  };
}

String _string(Object? value, {String fallback = ''}) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? fallback : text;
}
