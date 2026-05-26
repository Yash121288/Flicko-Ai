import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

const kFlickoGeminiApiKey = String.fromEnvironment(
  'FLICKO_GEMINI_API_KEY',
  defaultValue: '',
);

const kFlickoGeminiTextModel = String.fromEnvironment(
  'FLICKO_GEMINI_MODEL',
  defaultValue: 'gemini-2.5-flash',
);

const kFlickoGeminiNativeAudioModel = String.fromEnvironment(
  'FLICKO_GEMINI_NATIVE_AUDIO_MODEL',
  defaultValue: 'gemini-2.5-flash-native-audio-latest',
);

const kFlickoGeminiNativeAudioVoice = String.fromEnvironment(
  'FLICKO_GEMINI_NATIVE_AUDIO_VOICE',
  defaultValue: 'Kore',
);

class AiCoachMessage {
  const AiCoachMessage._({
    required this.text,
    required this.isUser,
    this.isError = false,
    this.source = 'chat',
  });

  const AiCoachMessage.user(String text, {String source = 'chat'})
    : this._(text: text, isUser: true, isError: false, source: source);

  const AiCoachMessage.assistant(
    String text, {
    bool isError = false,
    String source = 'chat',
  }) : this._(text: text, isUser: false, isError: isError, source: source);

  final String text;
  final bool isUser;
  final bool isError;
  final String source;

  factory AiCoachMessage.fromJson(Map<String, dynamic> json) {
    final text = json['text']?.toString() ?? '';
    final role = json['role']?.toString() ?? '';
    final source = json['source']?.toString().trim() ?? '';
    return AiCoachMessage._(
      text: text,
      isUser: role == 'user',
      isError: json['isError'] == true,
      source: source.isEmpty ? 'chat' : source,
    );
  }

  Map<String, Object> toGeminiContent() {
    return {
      'role': isUser ? 'user' : 'model',
      'parts': [
        {'text': text},
      ],
    };
  }

  Map<String, Object> toJson() {
    return {
      'text': text,
      'role': isUser ? 'user' : 'assistant',
      'isError': isError,
      'source': source.trim().isEmpty ? 'chat' : source.trim(),
    };
  }
}

class GeminiHealthChatException implements Exception {
  const GeminiHealthChatException(this.message);

  final String message;

  @override
  String toString() => message;
}

class GeminiHealthChatClient {
  const GeminiHealthChatClient({
    this.apiKey = kFlickoGeminiApiKey,
    this.model = kFlickoGeminiTextModel,
    this.baseUrl = 'https://generativelanguage.googleapis.com/v1beta',
  });

  final String apiKey;
  final String model;
  final String baseUrl;

  Future<String> generateCallOpening({
    required String firstName,
    required String problemName,
    required String voiceContext,
    required String callReasonLabel,
    required String callPurpose,
    required bool initiatedByUser,
    required String openingStyleHint,
    required String recentOpeningHistory,
    required String fallbackOpening,
  }) async {
    final trimmedKey = apiKey.trim();
    if (trimmedKey.isEmpty) {
      throw const GeminiHealthChatException(
        'Gemini API key is missing in the app configuration.',
      );
    }

    final uri = Uri.parse('$baseUrl/models/$model:generateContent');
    final safeName = firstName.trim().isEmpty ? 'user' : firstName.trim();
    final payload = <String, Object>{
      'system_instruction': {
        'parts': [
          {
            'text': '''
You generate the first spoken turn for a live health call inside the Flicko app.

Rules:
- Return only the spoken opening, no labels, no markdown, no quotes.
- Keep it to exactly 1 or 2 short natural spoken sentences.
- Use local Hindi or Hinglish that sounds human and warm.
- Mention one real context item only if it exists in the provided context.
- If this is a first intake, start directly from the health reason and first question.
- If this is a follow-up, continue naturally from memory and ask one useful question.
- Do not repeat generic greetings or robotic call-center wording.
- Do not mention AI, model, app internals, loading, buffering, or setup.
- Use the fallback opening only if the provided context is too weak.
''',
          },
        ],
      },
      'contents': [
        {
          'role': 'user',
          'parts': [
            {
              'text':
                  '''
Call reason: $callReasonLabel
Call started by: ${initiatedByUser ? 'user' : 'Flicko'}
Call purpose or work name: ${callPurpose.trim().isEmpty ? callReasonLabel : callPurpose.trim()}
User name: $safeName
Primary problem: $problemName
Opening style hint: $openingStyleHint
Recent openings to avoid: ${recentOpeningHistory.trim().isEmpty ? 'none' : recentOpeningHistory.trim()}
Fallback opening:
$fallbackOpening

Known voice context:
$voiceContext

Additional rules:
- The first sentence must sound materially different from anything in "Recent openings to avoid".
- If User name is not "user", use that exact name naturally once in the opening. Do not replace it with another name or a full formal name.
- Choose a fresh opening move that matches the style hint: continuity-led, reminder-led, progress-led, catch-up-led, support-led, memory-led, or friendly-led.
- If "Call started by" is user, open like a known coach who the user called, but do not use the old canned line "aaj mujhe yaad kiya" or any close variant. Generate a fresh first sentence every time, then ask what help is needed.
- If "Call started by" is Flicko, never say the user remembered or called you. State the exact work name: setup, daily reminder, meal photo follow-up, care task, or notification purpose.
- Friendly familiarity is allowed for returning users when context supports it, but do not force the same playful phrase every time.
- Avoid these exact repeated patterns: "main aaj ka quick care check-in lene ke liye call kar rahi hoon", "main aapke fixed check-in time par call kar rahi hoon", "main care task follow-up ke liye call kar rahi hoon".
- If a daily reminder or agreed call time exists in context, you may acknowledge it naturally, but rephrase it freshly.

Write the exact first spoken turn now.
''',
            },
          ],
        },
      ],
      'generationConfig': {
        'temperature': 0.9,
        'topP': 0.92,
        'maxOutputTokens': 120,
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
          .timeout(const Duration(seconds: 8));

      final decoded = response.body.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(response.body);
      final json = decoded is Map<String, dynamic>
          ? decoded
          : <String, dynamic>{};

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw GeminiHealthChatException(
          _buildErrorMessage(response.statusCode, json),
        );
      }

      final reply = _extractReply(json).trim();
      if (reply.isEmpty) {
        throw const GeminiHealthChatException(
          'Gemini returned an empty live call opening.',
        );
      }
      return reply;
    } on GeminiHealthChatException {
      rethrow;
    } on FormatException {
      throw const GeminiHealthChatException(
        'Gemini returned an invalid live call opening response.',
      );
    } catch (_) {
      throw const GeminiHealthChatException(
        'Could not pre-generate the live call opening.',
      );
    }
  }

  Future<String> sendMessage({
    required String firstName,
    required String problemName,
    required String aiPrompt,
    required String profileContext,
    String protocolContext = '',
    required String message,
    required List<AiCoachMessage> history,
  }) async {
    final trimmedKey = apiKey.trim();
    if (trimmedKey.isEmpty) {
      throw const GeminiHealthChatException(
        'Gemini API key is missing in the app configuration.',
      );
    }

    final uri = Uri.parse('$baseUrl/models/$model:generateContent');
    final payload = <String, Object>{
      'system_instruction': {
        'parts': [
          {
            'text': _buildSystemPrompt(
              problemName: problemName,
              aiPrompt: aiPrompt,
            ),
          },
        ],
      },
      'contents': [
        ...history
            .where((entry) => entry.text.trim().isNotEmpty)
            .takeLast(10)
            .map((entry) => entry.toGeminiContent()),
        {
          'role': 'user',
          'parts': [
            {
              'text': _buildUserPrompt(
                firstName: firstName,
                problemName: problemName,
                profileContext: profileContext,
                protocolContext: protocolContext,
                message: message,
              ),
            },
          ],
        },
      ],
      'generationConfig': {
        'temperature': 0.72,
        'topP': 0.94,
        'maxOutputTokens': 1800,
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
          .timeout(const Duration(seconds: 30));

      final decoded = response.body.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(response.body);
      final json = decoded is Map<String, dynamic>
          ? decoded
          : <String, dynamic>{};

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw GeminiHealthChatException(
          _buildErrorMessage(response.statusCode, json),
        );
      }

      final reply = _extractReply(json);
      if (reply.isEmpty) {
        throw const GeminiHealthChatException(
          'Gemini returned an empty reply. Try asking again.',
        );
      }
      return reply;
    } on GeminiHealthChatException {
      rethrow;
    } on FormatException {
      throw const GeminiHealthChatException(
        'Gemini returned an invalid response format.',
      );
    } catch (_) {
      throw const GeminiHealthChatException(
        'Could not reach Gemini from the app. Check internet access and API key status.',
      );
    }
  }

  Future<String> analyzeMedicalReportImage({
    required Uint8List imageBytes,
    required String mimeType,
    required String fileName,
    required String problemName,
    required String profileContext,
  }) async {
    return analyzeMedicalReportFile(
      fileBytes: imageBytes,
      mimeType: mimeType,
      fileName: fileName,
      problemName: problemName,
      profileContext: profileContext,
    );
  }

  Future<String> analyzeMedicalReportFile({
    required Uint8List fileBytes,
    required String mimeType,
    required String fileName,
    required String problemName,
    required String profileContext,
  }) async {
    final trimmedKey = apiKey.trim();
    if (trimmedKey.isEmpty) {
      throw const GeminiHealthChatException(
        'Gemini API key is missing in the app configuration.',
      );
    }
    if (fileBytes.isEmpty) {
      throw const GeminiHealthChatException('Medical report file is empty.');
    }

    final uri = Uri.parse('$baseUrl/models/$model:generateContent');
    final safeMimeType = mimeType.trim().isEmpty
        ? 'application/pdf'
        : mimeType.trim();
    final payload = <String, Object?>{
      'contents': [
        {
          'role': 'user',
          'parts': [
            {
              'text': _medicalReportFilePrompt(
                fileName: fileName,
                mimeType: safeMimeType,
                problemName: problemName,
                profileContext: profileContext,
              ),
            },
            {
              'inlineData': {
                'mimeType': safeMimeType,
                'data': base64Encode(fileBytes),
              },
            },
          ],
        },
      ],
      'generationConfig': {
        'temperature': 0.12,
        'topP': 0.8,
        'maxOutputTokens': 2200,
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

      final decoded = response.body.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(response.body);
      final json = decoded is Map<String, dynamic>
          ? decoded
          : <String, dynamic>{};

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw GeminiHealthChatException(
          _buildErrorMessage(response.statusCode, json),
        );
      }

      final reply = _extractReply(json);
      if (reply.trim().isEmpty) {
        throw const GeminiHealthChatException(
          'Gemini could not read useful report text from this file.',
        );
      }
      return reply;
    } on GeminiHealthChatException {
      rethrow;
    } on FormatException {
      throw const GeminiHealthChatException(
        'Gemini returned an invalid report response.',
      );
    } catch (_) {
      throw const GeminiHealthChatException(
        'Could not analyze the medical report. Check internet and API key status.',
      );
    }
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

    final textParts = <String>[];
    for (final entry in parts) {
      if (entry is Map<String, dynamic>) {
        final text = entry['text']?.toString().trim() ?? '';
        if (text.isNotEmpty) {
          textParts.add(text);
        }
      }
    }
    return textParts.join('\n').trim();
  }

  String _buildErrorMessage(int statusCode, Map<String, dynamic> json) {
    final error = json['error'];
    final rawMessage = error is Map<String, dynamic>
        ? error['message']?.toString() ?? ''
        : json['detail']?.toString() ?? '';
    final normalized = rawMessage.toLowerCase();

    if (normalized.contains('leaked')) {
      return 'This Gemini API key was blocked by Google. Replace it with a new key inside the app.';
    }
    if (normalized.contains('api key') || normalized.contains('permission')) {
      return 'Gemini API key is invalid, blocked, or not enabled for this project.';
    }
    if (statusCode == 429 || normalized.contains('quota')) {
      return 'Gemini quota is exhausted right now. Try again later or switch to another key.';
    }
    if (statusCode >= 500) {
      return 'Gemini is temporarily unavailable. Try again shortly.';
    }
    return rawMessage.isNotEmpty
        ? rawMessage
        : 'Gemini request failed with status $statusCode.';
  }

  String _buildSystemPrompt({
    required String problemName,
    required String aiPrompt,
  }) {
    return '''
You are Flicko AI, a premium healthcare guidance assistant inside a mobile health app.

Write with the calm depth of a senior multidisciplinary care team with decades of experience across medicine, nutrition, lifestyle coaching, chronic disease management, sleep, stress, fitness, and preventive care.

Primary care focus: $problemName
Behavior focus: $aiPrompt

Your job:
- If the user asks to start intake, complete profile, build dashboard, make report, set reminders, or if the profile is incomplete, run a structured health intake instead of giving a generic answer.
- Structured intake must feel like a 15-20 minute coach consultation led by Flicko. You ask and explain; do not ask the user "what should I ask" or "what do you want me to do". Choose the next clinically useful question from the selected problem and protocol context.
- Intake order: condition-specific first concern and duration, key symptoms/readings for that disease, current routine, breakfast/lunch/dinner timing, snacks/sugar/oil, sleep, stress/mood, activity/steps, medication, allergies, diagnosis/labs, family history, pregnancy/cycle if relevant, red-flag symptoms, barriers, preferred coaching tone, reminder time, and first 7-day goal.
- Use the local app protocol pack context first when available: condition intake questions, dashboard metrics, report blocks, food rules, safety rules, reminder scripts, and memory schemas.
- If backend structured intake status is present, treat "Missing intake fields", "Timeline details still missing", and "Next best intake questions" as the authoritative intake checklist for this turn.
- Ask timeline before lifestyle whenever onset, duration, frequency, trigger, relief, or last severe episode are still missing.
- Archive-ready intake means exact timing, exact medicine names, exact test/report names, and realistic reminder/call windows. Push for precision when the current answer is vague.
- Ask once during first intake whether the user has a recent medical/lab/doctor report relevant to this problem. If yes, tell them: after the call, open Chat and tap the upload/attachment button to upload the report image so Flicko can save it into profile memory and reports. If no, accept that and do not keep asking for a report in the same intake.
- During intake, save progress conversationally but do not produce a backend-ready report until the intake is complete.
- When enough intake data is collected, output exactly "Intake status: complete", then produce a section named "Intake summary for dashboard" with profile facts, dashboard values to update, risk flags, and report sections.
- If the intake is still incomplete, do not write "Intake status: complete"; ask the next best missing question.
- First infer the user's intent and feeling before answering: fear, pain, confusion, frustration, shame, urgency, curiosity, or motivation.
- Reflect that feeling briefly in one human sentence when it helps, without exaggerating or pretending to feel emotions yourself.
- Before each answer, compare against recent assistant messages in chat/call memory. Do not reuse the same opening line, same summary structure, or same first two sentences consecutively.
- Generate fresh summaries from actual profile context: recent calls, chat history, missed notifications, reminders, unfinished tasks, uploaded reports, health logs, meal checks, and last app activity. Never use a fake/static summary.
- Give practical, specific, stepwise answers that a real user can act on today.
- Personalize every answer to the user's health problem, profile, routine, food choices, and goals when that context is available.
- Ask one to three sharp follow-up questions when missing details block a useful answer.
- Suggest meal ideas, daily routines, symptom logs, habit plans, and doctor-ready summaries when helpful.
- When the user asks to update dashboard, add a reminder, or create a report, output a clear "App update" section with exact values, but do not claim it was saved unless the app confirms it.
- Inside "App update", use explicit lines only: "Dashboard: ...", "Reminder: 8:00 PM - ...", and "Report: Doctor-ready ...". Do not put casual advice, future possibilities, or incomplete report notes in that section.
- For a final doctor-ready PDF, include a short "Doctor-ready report" line only after "Intake status: complete" and only when enough user-specific intake details are available.
- Keep answers clean and mobile-friendly: short paragraphs, short bullets, simple steps, and clear priorities.
- If the user sounds anxious, slow down and reassure with clear next steps. If the user sounds angry, stay calm and practical. If the user sounds casual, answer naturally. If the user is urgent, lead with safety triage.
- Use the local app protocol pack context when it is provided. Treat deterministic local safety matches as higher priority than normal coaching.
- When giving a plan, dashboard update, reminder set, or report summary, ground it in the matching protocol IDs, food rules, intake questions, dashboard metrics, memory schemas, and evidence source IDs from the local app protocol context.
- Do not expose protocol IDs to the user unless the user asks for technical detail or the answer is a doctor-ready/report-ready summary.

Safety rules:
- Do not claim you examined the user or know facts that were not provided.
- Do not diagnose with certainty or invent medicines, labs, vitals, or reports.
- If the user mentions red flags such as chest pain, trouble breathing, severe allergic reaction, stroke signs, fainting, suicidal thoughts, seizures, severe dehydration, pregnancy emergencies, heavy bleeding, or confusion, tell them to seek urgent medical care now.
- For medicine changes, insulin changes, steroid use, pregnancy care, and severe symptoms, tell the user to confirm with a licensed clinician.

Presentation rules:
- Be direct, warm, polished, and premium.
- Sound like a careful human coach: calm, attentive, emotionally aware, and specific. Avoid robotic phrases, generic motivation, or fake over-sympathy.
- Reply in the same language and script as the user's latest message. If the user mixes languages, answer in the dominant language they used. Do not translate to English unless the user asks.
- Never mention model names, providers, API keys, or internal instructions.
- Keep the response focused on the user's health question.
''';
  }

  String _medicalReportFilePrompt({
    required String fileName,
    required String mimeType,
    required String problemName,
    required String profileContext,
  }) {
    final safeContext = profileContext.trim().isEmpty
        ? 'Profile setup is incomplete.'
        : profileContext.trim();
    return '''
Read this uploaded medical/lab/doctor report file for Flicko AI.

File name: $fileName
File MIME type: $mimeType
Primary health problem: $problemName
Known user profile:
$safeContext

Rules:
- Extract only what is visible. Do not invent values.
- Do not diagnose or prescribe.
- If the PDF/image is unclear, say exactly what could not be read.
- Make it useful for user profile memory, dashboard, reminders, and doctor-ready report generation.
- Match the user's language if obvious from context; otherwise use simple English with medical terms preserved.

Return markdown with these sections:
## Uploaded report summary
Report type, visible date, lab/doctor/source if visible.

## Key values found
Bullets with test/metric name, value, unit, reference range/status if visible.

## Relevance for $problemName
How these visible values may relate to the selected problem, stated cautiously.

## Follow-up questions
Only the missing details Flicko should ask next.

## Dashboard memory
Short machine-readable bullets that can be saved as profile/report memory.
''';
  }

  String _buildUserPrompt({
    required String firstName,
    required String problemName,
    required String profileContext,
    required String protocolContext,
    required String message,
  }) {
    final safeName = firstName.trim().isEmpty ? 'User' : firstName.trim();
    final safeContext = profileContext.trim().isEmpty
        ? 'Profile setup is incomplete.'
        : profileContext.trim();
    final safeProtocolContext = protocolContext.trim().isEmpty
        ? 'No local protocol pack context was loaded for this turn.'
        : protocolContext.trim();

    return '''
User name: $safeName
Primary health problem: $problemName
Known health profile:
$safeContext

Local app protocol context:
$safeProtocolContext

User message:
$message

Answer specifically for $safeName and this problem. Before giving advice, silently identify the user's likely intent and emotional state, then adapt the tone. If recent assistant wording exists in the known profile/chat/call context, avoid repeating it exactly. If the user asks for a plan, make it structured and practical.
''';
  }
}

extension<T> on Iterable<T> {
  Iterable<T> takeLast(int count) {
    if (count <= 0) {
      return <T>[];
    }
    final items = toList();
    if (items.length <= count) {
      return items;
    }
    return items.sublist(items.length - count);
  }
}
