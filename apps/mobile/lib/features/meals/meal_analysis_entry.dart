class MealNutrientScore {
  const MealNutrientScore({
    required this.name,
    required this.score,
    required this.level,
    required this.note,
  });

  final String name;
  final int score;
  final String level;
  final String note;

  Map<String, Object> toJson() {
    return {'name': name, 'score': score, 'level': level, 'note': note};
  }

  factory MealNutrientScore.fromJson(
    Map<String, dynamic> json, {
    String fallbackName = '',
  }) {
    return MealNutrientScore(
      name: _string(
        json['name'] ?? json['label'] ?? json['nutrient'],
        fallback: fallbackName,
      ),
      score:
          _scoreOutOf10(json['score'] ?? json['outOf10'] ?? json['value']) ?? 0,
      level: _string(json['level'] ?? json['status'] ?? json['quality']),
      note: _string(json['note'] ?? json['reason'] ?? json['evidence']),
    );
  }

  static List<MealNutrientScore> listFromJson(Object? value) {
    return _nutrientScoreList(value);
  }

  bool get isUsable => name.trim().isNotEmpty && score >= 0 && score <= 10;
}

class MealAnalysisEntry {
  const MealAnalysisEntry({
    required this.id,
    required this.problemName,
    required this.mealName,
    required this.score,
    required this.decision,
    required this.calorieRange,
    required this.carbLoad,
    required this.proteinQuality,
    required this.fiberQuality,
    required this.detectedFoods,
    required this.riskFlags,
    required this.recommendations,
    required this.createdAt,
    this.nutrientScores = const <MealNutrientScore>[],
    this.imagePath = '',
  });

  final String id;
  final String problemName;
  final String mealName;
  final int score;
  final String decision;
  final String calorieRange;
  final String carbLoad;
  final String proteinQuality;
  final String fiberQuality;
  final List<String> detectedFoods;
  final List<String> riskFlags;
  final List<String> recommendations;
  final DateTime createdAt;
  final List<MealNutrientScore> nutrientScores;
  final String imagePath;

  String get compactSummary {
    final foods = detectedFoods.take(4).join(', ');
    final advice = recommendations.take(2).join(' ');
    final nutrients = nutrientScores
        .take(2)
        .map((item) => '${item.name} ${item.score}/10')
        .join(', ');
    return [
      '$score/100',
      decision,
      if (foods.isNotEmpty) foods,
      if (nutrients.isNotEmpty) nutrients,
      if (calorieRange.isNotEmpty) calorieRange,
      if (advice.isNotEmpty) advice,
    ].where((part) => part.trim().isNotEmpty).join(' - ');
  }

  Map<String, Object> toJson() {
    return {
      'id': id,
      'problemName': problemName,
      'mealName': mealName,
      'score': score,
      'decision': decision,
      'calorieRange': calorieRange,
      'carbLoad': carbLoad,
      'proteinQuality': proteinQuality,
      'fiberQuality': fiberQuality,
      'detectedFoods': detectedFoods,
      'riskFlags': riskFlags,
      'recommendations': recommendations,
      'createdAt': createdAt.toIso8601String(),
      'nutrientScores': nutrientScores.map((entry) => entry.toJson()).toList(),
      'imagePath': imagePath,
    };
  }

  factory MealAnalysisEntry.fromJson(Map<String, dynamic> json) {
    return MealAnalysisEntry(
      id: _string(json['id'], fallback: DateTime.now().toIso8601String()),
      problemName: _string(json['problemName']),
      mealName: _string(json['mealName'], fallback: 'Meal photo check'),
      score: _int(json['score'], fallback: 0).clamp(0, 100),
      decision: _string(json['decision'], fallback: 'Review'),
      calorieRange: _string(json['calorieRange']),
      carbLoad: _string(json['carbLoad']),
      proteinQuality: _string(json['proteinQuality']),
      fiberQuality: _string(json['fiberQuality']),
      detectedFoods: _stringList(json['detectedFoods']),
      riskFlags: _stringList(json['riskFlags']),
      recommendations: _stringList(json['recommendations']),
      createdAt:
          DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.now(),
      nutrientScores: _nutrientScoreList(json['nutrientScores']),
      imagePath: _string(json['imagePath']),
    );
  }

  static MealAnalysisEntry create({
    required String problemName,
    required String mealName,
    required int score,
    required String decision,
    required String calorieRange,
    required String carbLoad,
    required String proteinQuality,
    required String fiberQuality,
    required List<String> detectedFoods,
    required List<String> riskFlags,
    required List<String> recommendations,
    List<MealNutrientScore> nutrientScores = const <MealNutrientScore>[],
    String imagePath = '',
  }) {
    final now = DateTime.now();
    return MealAnalysisEntry(
      id: '${now.microsecondsSinceEpoch}-meal-analysis',
      problemName: problemName.trim(),
      mealName: mealName.trim().isEmpty ? 'Meal photo check' : mealName.trim(),
      score: score.clamp(0, 100),
      decision: decision.trim().isEmpty ? 'Review' : decision.trim(),
      calorieRange: calorieRange.trim(),
      carbLoad: carbLoad.trim(),
      proteinQuality: proteinQuality.trim(),
      fiberQuality: fiberQuality.trim(),
      detectedFoods: detectedFoods
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false),
      riskFlags: riskFlags
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false),
      recommendations: recommendations
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false),
      createdAt: now,
      nutrientScores: _dedupeNutrientScores(nutrientScores),
      imagePath: imagePath.trim(),
    );
  }
}

typedef MealAnalysisWriter = Future<bool> Function(MealAnalysisEntry entry);

String _string(Object? value, {String fallback = ''}) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? fallback : text;
}

int _int(Object? value, {required int fallback}) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.round();
  }
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}

List<String> _stringList(Object? value) {
  if (value is! List) {
    return const <String>[];
  }
  return value
      .map((entry) => entry?.toString().trim() ?? '')
      .where((entry) => entry.isNotEmpty)
      .toList(growable: false);
}

List<MealNutrientScore> _nutrientScoreList(Object? value) {
  if (value is List) {
    return _dedupeNutrientScores(
      value
          .whereType<Map>()
          .map((entry) {
            final json = Map<String, dynamic>.from(entry);
            final score = _scoreOutOf10(
              json['score'] ?? json['outOf10'] ?? json['value'],
            );
            if (score == null) {
              return null;
            }
            return MealNutrientScore.fromJson(json);
          })
          .whereType<MealNutrientScore>()
          .toList(growable: false),
    );
  }
  if (value is Map) {
    final scores = <MealNutrientScore>[];
    for (final item in value.entries) {
      final name = item.key.toString();
      final raw = item.value;
      if (raw is Map) {
        final json = Map<String, dynamic>.from(raw);
        final score = _scoreOutOf10(
          json['score'] ?? json['outOf10'] ?? json['value'],
        );
        if (score == null) {
          continue;
        }
        scores.add(MealNutrientScore.fromJson(json, fallbackName: name));
        continue;
      }
      final score = _scoreOutOf10(raw);
      if (score != null) {
        scores.add(
          MealNutrientScore(name: name, score: score, level: '', note: ''),
        );
      }
    }
    return _dedupeNutrientScores(scores);
  }
  return const <MealNutrientScore>[];
}

List<MealNutrientScore> _dedupeNutrientScores(List<MealNutrientScore> scores) {
  final seen = <String>{};
  final cleaned = <MealNutrientScore>[];
  for (final score in scores) {
    final key = score.name.trim().toLowerCase();
    if (!score.isUsable || key.isEmpty || seen.contains(key)) {
      continue;
    }
    seen.add(key);
    cleaned.add(
      MealNutrientScore(
        name: score.name.trim(),
        score: score.score.clamp(0, 10),
        level: score.level.trim(),
        note: score.note.trim(),
      ),
    );
  }
  return cleaned.toList(growable: false);
}

int? _scoreOutOf10(Object? value) {
  if (value is int) {
    return value.clamp(0, 10);
  }
  if (value is num) {
    return value.round().clamp(0, 10);
  }
  final text = value?.toString().trim() ?? '';
  if (text.isEmpty) {
    return null;
  }
  final ratio = RegExp(r'(\d+(?:\.\d+)?)\s*/\s*10').firstMatch(text);
  final raw =
      ratio?.group(1) ??
      RegExp(r'\b(\d+(?:\.\d+)?)\b').firstMatch(text)?.group(1);
  final parsed = raw == null ? null : double.tryParse(raw);
  return parsed?.round().clamp(0, 10);
}
