import 'package:flutter_test/flutter_test.dart';

import 'package:flicko_health/features/meals/gemini_meal_analysis_client.dart';
import 'package:flicko_health/features/meals/meal_analysis_entry.dart';

void main() {
  test('meal image analysis uses image-specific Gemini config without embedded key', () {
    const client = GeminiMealAnalysisClient();

    expect(client.apiKey, kFlickoGeminiImageApiKey);
    expect(client.model, kFlickoGeminiImageModel);
    expect(client.apiKey.trim(), isEmpty);
    expect(client.model, 'gemini-2.5-flash');
  });

  test('meal analysis stores only usable nutrient scores out of ten', () {
    final entry = MealAnalysisEntry.fromJson({
      'id': 'meal-1',
      'problemName': 'Weight management',
      'mealName': 'Dal rice and salad',
      'score': 78,
      'decision': 'Eat small portion',
      'nutrientScores': [
        {
          'name': 'Protein',
          'score': 8,
          'level': 'High',
          'note': 'Dal and curd visible',
        },
        {
          'name': 'Fiber',
          'score': '6/10',
          'level': 'Medium',
          'note': 'Small salad portion visible',
        },
        {'name': 'Vitamin', 'level': 'Unknown'},
      ],
      'createdAt': '2026-01-01T10:00:00.000',
    });

    expect(entry.nutrientScores, hasLength(2));
    expect(entry.nutrientScores.first.name, 'Protein');
    expect(entry.nutrientScores.first.score, 8);
    expect(entry.nutrientScores[1].name, 'Fiber');
    expect(entry.nutrientScores[1].score, 6);
    expect(entry.compactSummary, contains('Protein 8/10'));
    expect(entry.toJson()['nutrientScores'], isA<List<Object?>>());
  });
}
