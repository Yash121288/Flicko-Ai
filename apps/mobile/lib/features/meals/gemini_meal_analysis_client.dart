import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'meal_analysis_entry.dart';

const kFlickoGeminiImageApiKey = String.fromEnvironment(
  'FLICKO_GEMINI_IMAGE_API_KEY',
  defaultValue: '',
);

const kFlickoGeminiImageModel = String.fromEnvironment(
  'FLICKO_GEMINI_IMAGE_MODEL',
  defaultValue: 'gemini-2.5-flash',
);

class GeminiMealAnalysisException implements Exception {
  const GeminiMealAnalysisException(this.message);

  final String message;

  @override
  String toString() => message;
}

class GeminiMealAnalysisClient {
  const GeminiMealAnalysisClient({
    this.apiKey = kFlickoGeminiImageApiKey,
    this.model = kFlickoGeminiImageModel,
    this.baseUrl = 'https://generativelanguage.googleapis.com/v1beta',
  });

  final String apiKey;
  final String model;
  final String baseUrl;

  Future<MealAnalysisEntry> analyzeMeal({
    required Uint8List imageBytes,
    required String mimeType,
    required String problemName,
    required String profileContext,
    required String imagePath,
  }) async {
    final trimmedKey = apiKey.trim();
    if (trimmedKey.isEmpty) {
      throw const GeminiMealAnalysisException(
        'Gemini API key is missing in the app configuration.',
      );
    }
    if (imageBytes.isEmpty) {
      throw const GeminiMealAnalysisException('Meal image is empty.');
    }

    final uri = Uri.parse('$baseUrl/models/$model:generateContent');
    final payload = <String, Object?>{
      'contents': [
        {
          'role': 'user',
          'parts': [
            {'text': _prompt(problemName, profileContext)},
            {
              'inlineData': {
                'mimeType': mimeType.trim().isEmpty
                    ? 'image/jpeg'
                    : mimeType.trim(),
                'data': base64Encode(imageBytes),
              },
            },
          ],
        },
      ],
      'generationConfig': {
        'temperature': 0.15,
        'topP': 0.8,
        'maxOutputTokens': 1200,
        'responseMimeType': 'application/json',
      },
    };

    try {
      final response = await http
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'x-goog-api-key': trimmedKey,
            },
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 35));

      final json = _decodeResponseBody(response.body);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw GeminiMealAnalysisException(
          _errorMessage(response.statusCode, json),
        );
      }

      final text = _extractReply(json);
      if (text.trim().isEmpty) {
        return _fallbackAnalysis(
          problemName: problemName,
          imagePath: imagePath,
          reason: 'Gemini returned no structured food data.',
        );
      }

      final parsed = _parseJsonReply(text);
      return MealAnalysisEntry.create(
        problemName: problemName,
        mealName: _string(parsed['mealName'], fallback: 'Meal photo check'),
        score: _int(parsed['score'], fallback: 50),
        decision: _string(parsed['decision'], fallback: 'Review'),
        calorieRange: _string(parsed['calorieRange']),
        carbLoad: _string(parsed['carbLoad']),
        proteinQuality: _string(parsed['proteinQuality']),
        fiberQuality: _string(parsed['fiberQuality']),
        nutrientScores: MealNutrientScore.listFromJson(
          parsed['nutrientScores'],
        ),
        detectedFoods: _stringList(parsed['detectedFoods']),
        riskFlags: _stringList(parsed['riskFlags']),
        recommendations: _stringList(parsed['recommendations']),
        imagePath: imagePath,
      );
    } on GeminiMealAnalysisException {
      rethrow;
    } on FormatException {
      return _fallbackAnalysis(
        problemName: problemName,
        imagePath: imagePath,
        reason: 'Gemini returned invalid structured food data.',
      );
    } catch (_) {
      throw const GeminiMealAnalysisException(
        'Could not analyze the meal photo. Check internet and API key status.',
      );
    }
  }

  Map<String, dynamic> _decodeResponseBody(String body) {
    final trimmed = body.trim();
    if (trimmed.isEmpty) {
      return <String, dynamic>{};
    }
    try {
      final decoded = jsonDecode(trimmed);
      return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
    } on FormatException {
      return <String, dynamic>{};
    }
  }

  MealAnalysisEntry _fallbackAnalysis({
    required String problemName,
    required String imagePath,
    required String reason,
  }) {
    return MealAnalysisEntry.create(
      problemName: problemName,
      mealName: 'Meal photo estimate',
      score: 60,
      decision: 'Review',
      calorieRange: 'Estimate needs manual review',
      carbLoad: 'Estimate: check refined carbs and portion size',
      proteinQuality: 'Estimate: add lean protein if meal is mostly carbs',
      fiberQuality:
          'Estimate: add vegetables or salad if plate looks low fiber',
      nutrientScores: const <MealNutrientScore>[],
      detectedFoods: const ['Photo captured'],
      riskFlags: [reason],
      recommendations: const [
        'Retake the photo with the full plate visible in good light.',
        'Add meal details in chat for a more accurate condition-specific score.',
        'Use this temporary score only as a review signal, not a medical decision.',
      ],
      imagePath: imagePath,
    );
  }

  String _prompt(String problemName, String profileContext) {
    return '''
You are Flicko AI meal photo analyzer.

Analyze the food image for a user whose primary health focus is: $problemName
Known profile:
$profileContext

Return ONLY valid JSON with this exact shape:
{
  "mealName": "short meal name",
  "score": 0-100,
  "decision": "Eat / Eat small portion / Reduce / Avoid / Review",
  "calorieRange": "estimated range",
  "carbLoad": "Low / Medium / High with short reason",
  "proteinQuality": "Low / Medium / High with short reason",
  "fiberQuality": "Low / Medium / High with short reason",
  "nutrientScores": [
    {"name": "Protein", "score": 8, "level": "High", "note": "visible evidence"},
    {"name": "Fiber", "score": 6, "level": "Medium", "note": "visible evidence"},
    {"name": "Portion", "score": 7, "level": "Good", "note": "visible evidence"},
    {"name": "Cholesterol", "score": 8, "level": "Low risk", "note": "visible evidence"},
    {"name": "Vitamins", "score": 6, "level": "Medium", "note": "visible evidence"}
  ],
  "detectedFoods": ["food 1", "food 2"],
  "riskFlags": ["condition-specific risk, if any"],
  "recommendations": ["actionable correction 1", "actionable correction 2", "actionable correction 3"]
}

Rules:
- Be conservative. If unsure, say estimated.
- nutrientScores are 0-10 health-aligned scores for the visible meal, where 10 is best for the user's health focus. For cholesterol/saturated fat, 10 means low-risk/heart-friendly and 0 means high-risk.
- Include nutrientScores only when the photo gives usable evidence. Omit any nutrient that is not visible or inferable from the meal image. Do not output placeholder or unknown nutrient rows.
- Do not diagnose disease.
- For diabetes, prioritize sugar load, refined carbs, fiber, portion, and post-meal walk.
- For blood pressure/heart/cholesterol, prioritize salt, fried food, saturated fat, fiber, and portion.
- For weight management, prioritize protein, calorie density, portion, fiber, and liquid calories.
- For digestive health, prioritize spice, oil, portion size, late meal risk, and trigger foods.
''';
  }

  String _extractReply(Map<String, dynamic> json) {
    final candidates = json['candidates'];
    if (candidates is! List || candidates.isEmpty) {
      return '';
    }
    final first = candidates.first;
    if (first is! Map<String, dynamic>) {
      return '';
    }
    final content = first['content'];
    if (content is! Map<String, dynamic>) {
      return '';
    }
    final parts = content['parts'];
    if (parts is! List) {
      return '';
    }
    return parts
        .whereType<Map<String, dynamic>>()
        .map((part) => part['text']?.toString().trim() ?? '')
        .where((text) => text.isNotEmpty)
        .join('\n')
        .trim();
  }

  Map<String, dynamic> _parseJsonReply(String text) {
    final cleaned = text
        .replaceAll(RegExp(r'^```json\s*', multiLine: true), '')
        .replaceAll(RegExp(r'^```\s*', multiLine: true), '')
        .replaceAll(RegExp(r'\s*```$', multiLine: true), '')
        .trim();
    final decoded = jsonDecode(_extractJsonObject(cleaned));
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Meal analysis is not a JSON object.');
    }
    return decoded;
  }

  String _extractJsonObject(String text) {
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start == -1 || end <= start) {
      throw const FormatException('Meal analysis JSON object missing.');
    }
    return text.substring(start, end + 1);
  }

  String _errorMessage(int statusCode, Map<String, dynamic> json) {
    final error = json['error'];
    final rawMessage = error is Map<String, dynamic>
        ? error['message']?.toString() ?? ''
        : '';
    final lower = rawMessage.toLowerCase();
    if (lower.contains('api key') || lower.contains('permission')) {
      return 'Gemini API key is invalid, blocked, or not enabled for image analysis.';
    }
    if (statusCode == 429 || lower.contains('quota')) {
      return 'Gemini image-analysis quota is exhausted right now.';
    }
    return rawMessage.isNotEmpty
        ? rawMessage
        : 'Meal analysis failed with status $statusCode.';
  }
}

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
