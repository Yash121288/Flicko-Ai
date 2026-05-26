import 'package:flutter_test/flutter_test.dart';

import 'package:flicko_health/features/dashboard/gemini_health_chat_client.dart';
import 'package:flicko_health/features/meals/gemini_meal_analysis_client.dart';

void main() {
  test('chat and meal image analysis use the same default Gemini key', () {
    const chatClient = GeminiHealthChatClient();
    const mealClient = GeminiMealAnalysisClient();

    expect(chatClient.apiKey, kFlickoGeminiApiKey);
    expect(mealClient.apiKey, kFlickoGeminiImageApiKey);
    expect(chatClient.apiKey, mealClient.apiKey);
  });
}
