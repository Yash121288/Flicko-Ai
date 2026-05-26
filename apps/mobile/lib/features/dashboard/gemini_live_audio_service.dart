import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:logger/logger.dart' show Level;
import 'package:record/record.dart';
import 'package:web_socket_channel/io.dart';

import 'ai_call_memory.dart';

enum GeminiLiveAudioPhase {
  idle,
  connecting,
  listening,
  speaking,
  muted,
  disconnected,
  error,
}

class GeminiLiveAudioSnapshot {
  const GeminiLiveAudioSnapshot({
    required this.phase,
    required this.message,
    this.micEnabled = true,
    this.speakerEnabled = true,
    this.connected = false,
    this.openingReady = false,
    this.error,
  });

  final GeminiLiveAudioPhase phase;
  final String message;
  final bool micEnabled;
  final bool speakerEnabled;
  final bool connected;
  final bool openingReady;
  final String? error;

  bool get isSpeaking => phase == GeminiLiveAudioPhase.speaking;

  GeminiLiveAudioSnapshot copyWith({
    GeminiLiveAudioPhase? phase,
    String? message,
    bool? micEnabled,
    bool? speakerEnabled,
    bool? connected,
    bool? openingReady,
    String? error,
  }) {
    return GeminiLiveAudioSnapshot(
      phase: phase ?? this.phase,
      message: message ?? this.message,
      micEnabled: micEnabled ?? this.micEnabled,
      speakerEnabled: speakerEnabled ?? this.speakerEnabled,
      connected: connected ?? this.connected,
      openingReady: openingReady ?? this.openingReady,
      error: error,
    );
  }
}

class GeminiLiveAudioException implements Exception {
  const GeminiLiveAudioException(this.message);

  final String message;

  @override
  String toString() => message;
}

class GeminiLiveAudioService extends ChangeNotifier {
  GeminiLiveAudioService({
    required this.apiKey,
    required this.model,
    required this.voiceName,
    required this.problemName,
    this.profileContext = '',
    this.openingScript = '',
    this.deferFirstPlayback = false,
    this.baseUri = const String.fromEnvironment(
      'FLICKO_GEMINI_LIVE_WS_URL',
      defaultValue:
          'wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1alpha.GenerativeService.BidiGenerateContent',
    ),
  });

  static const int inputSampleRate = 16000;
  static const int outputSampleRate = 24000;

  final String apiKey;
  final String model;
  final String voiceName;
  final String problemName;
  final String profileContext;
  final String openingScript;
  final bool deferFirstPlayback;
  final String baseUri;

  final AudioRecorder _recorder = AudioRecorder();
  final FlutterSoundPlayer _player = FlutterSoundPlayer(
    logLevel: Level.warning,
  );

  IOWebSocketChannel? _channel;
  StreamSubscription<dynamic>? _socketSubscription;
  StreamSubscription<Uint8List>? _micSubscription;
  Completer<void>? _setupCompleter;
  Timer? _speakingSilenceTimer;
  Future<void> _playbackQueue = Future<void>.value();
  final List<HealthCallTranscriptEntry> _transcript = [];
  final List<Uint8List> _bufferedOpeningAudio = <Uint8List>[];

  bool _running = false;
  bool _micEnabled = true;
  bool _speakerEnabled = true;
  bool _playerOpen = false;
  bool _playerStreaming = false;
  bool _microphoneStarted = false;
  bool _initialPromptSent = false;
  bool _disposed = false;
  bool _openingReleased = false;
  bool _openingReady = false;

  GeminiLiveAudioSnapshot _snapshot = const GeminiLiveAudioSnapshot(
    phase: GeminiLiveAudioPhase.idle,
    message: 'Preparing voice call',
  );

  GeminiLiveAudioSnapshot get snapshot => _snapshot;

  List<HealthCallTranscriptEntry> get transcriptSnapshot =>
      List<HealthCallTranscriptEntry>.unmodifiable(_transcript);

  Future<void> start() async {
    if (_running) {
      return;
    }

    final trimmedKey = apiKey.trim();
    final trimmedModel = model.trim();
    if (trimmedKey.isEmpty || trimmedModel.isEmpty) {
      throw const GeminiLiveAudioException(
        'Live voice is missing Gemini configuration.',
      );
    }

    _running = true;
    _initialPromptSent = false;
    _openingReleased = !deferFirstPlayback;
    _openingReady = false;
    _bufferedOpeningAudio.clear();
    _speakingSilenceTimer?.cancel();
    _emit(
      _snapshot.copyWith(
        phase: GeminiLiveAudioPhase.connecting,
        message: 'Connecting live voice',
        connected: false,
        openingReady: false,
      ),
    );

    try {
      await _openPlayer();
      await _connectSocket(apiKey: trimmedKey);
      _sendSetup(model: trimmedModel);
      await _waitForSetupComplete();
      _sendInitialGreeting();
      if (!deferFirstPlayback) {
        unawaited(_startMicrophoneFallback());
      }
    } catch (error, stackTrace) {
      debugPrint('Flicko live audio start failed: $error\n$stackTrace');
      await stop();
      _emit(
        GeminiLiveAudioSnapshot(
          phase: GeminiLiveAudioPhase.error,
          message: _friendlyError(error),
          micEnabled: _micEnabled,
          speakerEnabled: _speakerEnabled,
          connected: false,
          error: error.toString(),
        ),
      );
    }
  }

  Future<void> stop({bool emitDisconnected = true}) async {
    _sendAudioStreamEnd();
    _running = false;
    _speakingSilenceTimer?.cancel();
    _speakingSilenceTimer = null;

    await _micSubscription?.cancel();
    _micSubscription = null;

    try {
      await _recorder.stop();
    } catch (_) {
      // Recorder may already be stopped by the platform.
    }

    await _socketSubscription?.cancel();
    _socketSubscription = null;

    try {
      await _channel?.sink.close();
    } catch (_) {
      // Socket may already be closed.
    }
    _channel = null;
    _setupCompleter = null;
    _microphoneStarted = false;
    _initialPromptSent = false;
    _openingReleased = false;
    _openingReady = false;
    _bufferedOpeningAudio.clear();

    try {
      if (_playerStreaming) {
        await _player.stopPlayer();
      }
    } catch (_) {
      // Player shutdown must be best-effort during call teardown.
    }
    _playerStreaming = false;

    try {
      if (_playerOpen) {
        await _player.closePlayer();
      }
    } catch (_) {
      // Player may already be closed by native audio focus loss.
    }
    _playerOpen = false;

    if (emitDisconnected &&
        !_disposed &&
        !_snapshot.phase.name.contains('error')) {
      _emit(
        _snapshot.copyWith(
          phase: GeminiLiveAudioPhase.disconnected,
          message: 'Call ended',
          connected: false,
        ),
      );
    }
  }

  Future<void> setMicEnabled(bool enabled) async {
    if (_micEnabled == enabled) {
      return;
    }
    _micEnabled = enabled;
    try {
      if (enabled) {
        await _recorder.resume();
      } else {
        await _recorder.pause();
      }
    } catch (error) {
      debugPrint('Flicko live audio mic toggle failed: $error');
    }
    _emit(
      _snapshot.copyWith(
        phase: enabled
            ? GeminiLiveAudioPhase.listening
            : GeminiLiveAudioPhase.muted,
        message: enabled ? 'Listening' : 'Microphone muted',
        micEnabled: enabled,
      ),
    );
  }

  Future<void> setSpeakerEnabled(bool enabled) async {
    if (_speakerEnabled == enabled) {
      return;
    }
    _speakerEnabled = enabled;
    try {
      await _player.setVolume(enabled ? 1.0 : 0.0);
    } catch (error) {
      debugPrint('Flicko live audio speaker toggle failed: $error');
    }
    _emit(
      _snapshot.copyWith(
        message: enabled ? 'Speaker enabled' : 'Speaker muted',
        speakerEnabled: enabled,
      ),
    );
  }

  Future<void> _openPlayer() async {
    await _player.openPlayer();
    _player.setLogLevel(Level.warning);
    _playerOpen = true;
    await _player.startPlayerFromStream(
      codec: Codec.pcm16,
      interleaved: true,
      numChannels: 1,
      sampleRate: outputSampleRate,
      bufferSize: 4096,
    );
    _playerStreaming = true;
  }

  Future<void> _connectSocket({required String apiKey}) async {
    final uri = Uri.parse(baseUri).replace(
      queryParameters: <String, String>{
        ...Uri.parse(baseUri).queryParameters,
        'key': apiKey,
      },
    );

    final channel = IOWebSocketChannel.connect(
      uri,
      pingInterval: const Duration(seconds: 20),
      connectTimeout: const Duration(seconds: 20),
    );
    _channel = channel;
    _setupCompleter = Completer<void>();
    _socketSubscription = channel.stream.listen(
      _handleSocketMessage,
      onError: _handleSocketError,
      onDone: _handleSocketDone,
      cancelOnError: false,
    );
    await channel.ready.timeout(const Duration(seconds: 20));
  }

  Future<void> _waitForSetupComplete() async {
    final completer = _setupCompleter;
    if (completer == null) {
      throw const GeminiLiveAudioException(
        'Live voice setup was not initialized.',
      );
    }
    await completer.future.timeout(
      const Duration(seconds: 20),
      onTimeout: () {
        throw const GeminiLiveAudioException(
          'Gemini Live did not confirm voice setup in time.',
        );
      },
    );
  }

  void _sendSetup({required String model}) {
    final normalizedModel = model.startsWith('models/')
        ? model
        : 'models/$model';
    _sendJson({
      'setup': {
        'model': normalizedModel,
        'generationConfig': {
          'responseModalities': ['AUDIO'],
          'temperature': 0.92,
          'enableAffectiveDialog': true,
          'speechConfig': {
            'voiceConfig': {
              'prebuiltVoiceConfig': {'voiceName': voiceName.trim()},
            },
          },
        },
        'systemInstruction': {
          'parts': [
            {'text': _systemPrompt},
          ],
        },
        'inputAudioTranscription': <String, Object?>{},
        'outputAudioTranscription': <String, Object?>{},
      },
    });
  }

  Future<void> _startMicrophone() async {
    if (_microphoneStarted) {
      return;
    }
    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      throw const GeminiLiveAudioException(
        'Microphone permission is required for live voice.',
      );
    }

    final supportsPcm = await _recorder.isEncoderSupported(
      AudioEncoder.pcm16bits,
    );
    if (!supportsPcm) {
      throw const GeminiLiveAudioException(
        'This device cannot stream the required PCM microphone audio.',
      );
    }

    final stream = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: inputSampleRate,
        numChannels: 1,
        autoGain: true,
        echoCancel: true,
        noiseSuppress: true,
        streamBufferSize: 3200,
      ),
    );
    _micSubscription = stream.listen(
      _sendAudioChunk,
      onError: (Object error, StackTrace stackTrace) {
        debugPrint('Flicko microphone stream failed: $error\n$stackTrace');
        _emit(
          _snapshot.copyWith(
            phase: GeminiLiveAudioPhase.error,
            message: 'Microphone stream stopped',
            error: error.toString(),
          ),
        );
      },
      cancelOnError: false,
    );
    _microphoneStarted = true;
  }

  Future<void> _startMicrophoneFallback() async {
    await Future<void>.delayed(const Duration(seconds: 8));
    if (!_running || _microphoneStarted) {
      return;
    }
    try {
      await _startMicrophone();
    } catch (error, stackTrace) {
      debugPrint('Flicko delayed microphone start failed: $error\n$stackTrace');
      _emit(
        _snapshot.copyWith(
          phase: GeminiLiveAudioPhase.error,
          message: _friendlyError(error),
          error: error.toString(),
        ),
      );
    }
  }

  void _sendAudioChunk(Uint8List chunk) {
    if (!_running || !_micEnabled || chunk.isEmpty) {
      return;
    }
    _sendJson({
      'realtimeInput': {
        'audio': {
          'mimeType': 'audio/pcm;rate=$inputSampleRate',
          'data': base64Encode(chunk),
        },
      },
    });
  }

  void _sendAudioStreamEnd() {
    if (!_running) {
      return;
    }
    _sendJson({
      'realtimeInput': {'audioStreamEnd': true},
    });
  }

  void _sendInitialGreeting() {
    if (_initialPromptSent) {
      return;
    }
    _initialPromptSent = true;
    final text = openingScript.trim().isNotEmpty
        ? '''
Speak the following exact opening naturally in a warm human Hindi or Hinglish health-coach voice.
Do not add a new greeting before it.
After speaking it once, stop and wait for the user response.

${openingScript.trim()}
'''
        : _initialGreetingPrompt;
    _sendJson({
      'clientContent': {
        'turns': [
          {
            'role': 'user',
            'parts': [
              {'text': text},
            ],
          },
        ],
        'turnComplete': true,
      },
    });
  }

  void sendTextTurn(String text) {
    final cleanText = text.trim();
    if (!_running || cleanText.isEmpty) {
      return;
    }
    _sendJson({
      'clientContent': {
        'turns': [
          {
            'role': 'user',
            'parts': [
              {'text': cleanText},
            ],
          },
        ],
        'turnComplete': true,
      },
    });
  }

  bool get _hasCompletedIntakeContext {
    final context = profileContext.toLowerCase();
    return const [
      'intake status: complete',
      'latest intake summary:',
      'saved ai call memory:',
      'last ai voice call completed:',
      'saved reports:',
    ].any((marker) => context.contains(marker));
  }

  String _firstPromptListItem(String label) {
    final lines = profileContext.split('\n');
    final normalizedLabel = label.trim().toLowerCase();
    for (var index = 0; index < lines.length; index++) {
      final current = lines[index].trim().toLowerCase();
      if (current != '$normalizedLabel:') {
        continue;
      }
      for (var cursor = index + 1; cursor < lines.length; cursor++) {
        final candidate = lines[cursor].trim();
        if (candidate.isEmpty) {
          continue;
        }
        if (!candidate.startsWith('- ')) {
          break;
        }
        final value = candidate.substring(2).trim();
        if (value.isNotEmpty) {
          return value;
        }
      }
    }
    return '';
  }

  String _defaultFirstIntakeQuestion() {
    final normalizedProblem = problemName.toLowerCase();
    if (normalizedProblem.contains('diabetes')) {
      return 'Sabse pehle mujhe bataiye, aapka sugar issue kis type ka hai aur aaj kal fasting ya random reading kitni aa rahi hai?';
    }
    if (normalizedProblem.contains('blood pressure') ||
        normalizedProblem.contains('heart')) {
      return 'Sabse pehle bataiye, blood pressure ya heart problem kab se hai aur recent BP reading ya symptom kya chal raha hai?';
    }
    if (normalizedProblem.contains('weight')) {
      return 'Sabse pehle bataiye, weight concern me abhi sabse badi dikkat kya hai aur pichhle do hafton me weight badha, ghata, ya same raha?';
    }
    if (normalizedProblem.contains('thyroid')) {
      return 'Sabse pehle bataiye, thyroid issue kab se hai aur abhi kaunsi medicine kis time le rahe hain?';
    }
    if (normalizedProblem.contains('pcos') ||
        normalizedProblem.contains('pcod') ||
        normalizedProblem.contains('hormone')) {
      return 'Sabse pehle bataiye, cycle ya hormone issue me abhi sabse zyada problem kya chal rahi hai aur ye kab se hai?';
    }
    if (normalizedProblem.contains('pregnan')) {
      return 'Sabse pehle bataiye, pregnancy ka kaunsa month ya week chal raha hai aur abhi koi symptom ya concern kya hai?';
    }
    if (normalizedProblem.contains('sleep')) {
      return 'Sabse pehle bataiye, neend ki dikkat kya hai aur sone me problem, beech me uthna, ya subah thakan me se kya zyada ho raha hai?';
    }
    if (normalizedProblem.contains('stress') ||
        normalizedProblem.contains('mood')) {
      return 'Sabse pehle bataiye, stress ya mood me abhi sabse badi dikkat kya hai aur ye pichhle kitne dino se chal rahi hai?';
    }
    if (normalizedProblem.contains('sexual')) {
      return 'Sabse pehle bataiye, sexual health concern me abhi exact problem kya hai aur ye kab se chal rahi hai?';
    }
    return 'Sabse pehle bataiye, $problemName ko lekar abhi sabse badi dikkat kya hai aur ye kab se chal rahi hai?';
  }

  String get _suggestedFirstIntakeQuestion {
    final directQuestion = _firstPromptListItem('Next best intake questions');
    if (directQuestion.isNotEmpty) {
      return directQuestion;
    }
    final localQuestion = _firstPromptListItem(
      'Local next best intake questions',
    );
    if (localQuestion.isNotEmpty) {
      return localQuestion;
    }
    return _defaultFirstIntakeQuestion();
  }

  String get _initialGreetingPrompt {
    final speechName = _preferredSpeechName();
    final userName = speechName.isEmpty ? 'user' : speechName;
    final timeHint = _contextValue('Time-of-day opening hint').isEmpty
        ? _localTimeHint()
        : _contextValue('Time-of-day opening hint');
    final seed = _contextValue('Dynamic greeting seed').isEmpty
        ? DateTime.now().microsecondsSinceEpoch.toString()
        : _contextValue('Dynamic greeting seed');
    final mode = _hasCompletedIntakeContext
        ? 'returning follow-up call'
        : 'first intake call';
    final suggestedQuestion = _suggestedFirstIntakeQuestion;
    final scheduledReminderHint = _contextValue('Scheduled daily reminders');
    final recentOpenings = _contextValue('Recent AI call openings to avoid');
    final openingStyle = _openingStyleHint(seed);
    final callSource = _contextValue('Call initiation source').isEmpty
        ? 'unknown'
        : _contextValue('Call initiation source');
    final callPurpose = _contextValue('Call purpose/work name').isEmpty
        ? 'health call'
        : _contextValue('Call purpose/work name');

    return '''
Generate the first spoken turn for this $mode.

Context to use:
- User name: $userName
- Time hint: $timeHint
- Care focus: $problemName
- Call initiation source: $callSource
- Call purpose/work name: $callPurpose
- Variation seed: $seed
- Opening style hint: $openingStyle
- Scheduled reminder hint: ${scheduledReminderHint.isEmpty ? 'none' : scheduledReminderHint}
- Recent openings to avoid: ${recentOpenings.isEmpty ? 'none' : recentOpenings}
- Known user context is already available in the system prompt.

Hard rules:
- Do not say "Hello Flick", "Hello Flicko", or repeat a fixed canned greeting.
- Do not copy a previous opening from Known user context or transcript memory.
- Do not use the same sentence structure as the previous call.
- Follow the opening style hint so the first line feels different from recent calls.
- The first sentence must sound materially different from anything listed in Recent openings to avoid.
- Mention the exact speech name naturally if it is available and not "user"; do not switch to a wrong name or full formal name unless only that is available.
- Mention one real context item if available: last call, missed reminder, care task, report, recent chat, recent glucose/meal/log, or notification memory.
- Keep it human, warm, local Hindi/Hinglish as appropriate, and under 14 seconds of speech.
- Ask exactly one useful next question.
- If call initiation source is user_started, the user opened the call. Be warm and familiar, but do not use the old canned line "aaj mujhe yaad kiya" or any close variant. Generate a fresh first sentence every time, then ask what help they need.
- If call initiation source is flicko_started, Flicko started the call. Do not say the user remembered or called you. State the call purpose/work name naturally before the question.
- If this is a returning call, use one short natural continuity or greeting line, then ask whether the current reminder, task, or plan went properly and whether any new problem happened.
- Friendly familiarity is allowed for returning users when context supports it, for example light continuity like remembering the user or their plan, but never reuse one playful phrase every call.
- If scheduled reminder hint is present, naturally acknowledge that you are calling at the agreed reminder time and that you want a quick full-day review or summary. Vary the wording every call. Do not use one canned sentence repeatedly.
- Avoid these exact repeated patterns: "main aaj ka quick care check-in lene ke liye call kar rahi hoon", "main aapke fixed check-in time par call kar rahi hoon", "main care task follow-up ke liye call kar rahi hoon".
- If this is a returning call, ask reminder timing details only if the user says the reminder failed, felt inconvenient, was missed, or they want it changed.
- If Known user context already contains a confirmed reminder time or an answered detail, do not ask for that same detail again unless the earlier answer is incomplete, conflicting, or the user wants a change.
- If the user gives a reminder or call time, repeat the exact time with AM/PM. Never round it or guess morning/evening. If the user says an ambiguous hour like "9 baje", ask one short clarification question before confirming it.
- After the user gives one clear detail, do not ask the same thing again in different words.
- If this is the first intake, do not open with social small talk like "kaise ho", "kya haalchal hai", "kya chal raha hai", or any generic wellness greeting.
- If this is the first intake, the first sentence must directly state the reason for the call or care focus.
- If this is the first intake, the second sentence must be the actual intake question. Do not waste the first turn on pleasantries.

Suggested first intake question:
- $suggestedQuestion

If this is a returning call, continue from memory, ask first whether the current reminder or plan worked properly, then ask what changed today only if needed.
If this is the first intake, lead the intake confidently and ask the most relevant first condition-specific question. Stay close to the suggested first intake question unless safety context requires a more urgent opening.
''';
  }

  String _contextValue(String label) {
    final prefix = '$label:';
    for (final line in profileContext.split('\n')) {
      final clean = line.trim();
      if (clean.toLowerCase().startsWith(prefix.toLowerCase())) {
        return clean.substring(prefix.length).trim();
      }
    }
    return '';
  }

  String _preferredSpeechName() {
    for (final label in const <String>[
      'User name for speech',
      'User first name',
      'First name',
      'User name',
      'Name',
    ]) {
      final value = _contextValue(label);
      final speechName = _speechNameFrom(value);
      if (speechName.isNotEmpty) {
        return speechName;
      }
    }
    return '';
  }

  String _speechNameFrom(String value) {
    final clean = value.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (clean.isEmpty) {
      return '';
    }
    return clean.split(' ').first.trim();
  }

  String _localTimeHint() {
    final hour = DateTime.now().hour;
    if (hour < 5) {
      return 'late night';
    }
    if (hour < 12) {
      return 'morning';
    }
    if (hour < 17) {
      return 'afternoon';
    }
    if (hour < 21) {
      return 'evening';
    }
    return 'night';
  }

  void _sendJson(Map<String, Object?> payload) {
    final channel = _channel;
    if (!_running || channel == null) {
      return;
    }
    channel.sink.add(jsonEncode(payload));
  }

  void _handleSocketMessage(dynamic message) {
    if (!_running) {
      return;
    }

    final text = message is List<int>
        ? utf8.decode(message)
        : message?.toString() ?? '';
    if (text.trim().isEmpty) {
      return;
    }

    try {
      final decoded = jsonDecode(text);
      if (decoded is! Map<String, dynamic>) {
        return;
      }
      _handleLiveResponse(decoded);
    } on FormatException {
      debugPrint('Flicko live audio received non-JSON payload.');
    }
  }

  void _handleLiveResponse(Map<String, dynamic> json) {
    if (json.containsKey('setupComplete')) {
      final completer = _setupCompleter;
      if (completer != null && !completer.isCompleted) {
        completer.complete();
      }
      _emit(
        _snapshot.copyWith(
          phase: GeminiLiveAudioPhase.listening,
          message: 'Listening',
          connected: true,
          micEnabled: _micEnabled,
          speakerEnabled: _speakerEnabled,
          openingReady: _openingReady,
        ),
      );
    }

    final serverContent = json['serverContent'];
    if (serverContent is Map<String, dynamic>) {
      _handleServerContent(serverContent);
    }

    final error = json['error'];
    if (error is Map<String, dynamic>) {
      final message = error['message']?.toString();
      if (message != null && message.isNotEmpty) {
        final completer = _setupCompleter;
        if (completer != null && !completer.isCompleted) {
          completer.completeError(GeminiLiveAudioException(message));
        }
        _emit(
          _snapshot.copyWith(
            phase: GeminiLiveAudioPhase.error,
            message: _friendlyError(message),
            connected: false,
            error: message,
          ),
        );
      }
    }
  }

  void _handleServerContent(Map<String, dynamic> serverContent) {
    _handleTranscription(serverContent);

    final modelTurn = serverContent['modelTurn'];
    var heardAudio = false;
    if (modelTurn is Map<String, dynamic>) {
      final parts = modelTurn['parts'];
      if (parts is List) {
        for (final part in parts) {
          if (part is! Map<String, dynamic>) {
            continue;
          }
          final inlineData = part['inlineData'];
          if (inlineData is Map<String, dynamic>) {
            final data = inlineData['data']?.toString();
            if (data != null && data.isNotEmpty) {
              heardAudio = true;
              _queuePlayback(data);
            }
          }
        }
      }
    }

    if (heardAudio) {
      if (_openingReady && !_openingReleased) {
        _emit(
          _snapshot.copyWith(
            phase: GeminiLiveAudioPhase.connecting,
            message: 'Opening voice ready',
            connected: true,
            openingReady: true,
          ),
        );
      } else {
        _scheduleSpeakingSilenceWatchdog();
        if (_microphoneStarted && _micEnabled) {
          unawaited(_recorder.pause());
        }
        _emit(
          _snapshot.copyWith(
            phase: GeminiLiveAudioPhase.speaking,
            message: _speakerEnabled ? 'AI is speaking' : 'AI speaking muted',
            connected: true,
            openingReady: false,
          ),
        );
      }
    }

    if (serverContent['turnComplete'] == true ||
        serverContent['generationComplete'] == true) {
      _markModelTurnComplete();
    }
  }

  void _scheduleSpeakingSilenceWatchdog() {
    _speakingSilenceTimer?.cancel();
    _speakingSilenceTimer = Timer(const Duration(milliseconds: 1800), () {
      if (!_running || _snapshot.phase != GeminiLiveAudioPhase.speaking) {
        return;
      }
      _markModelTurnComplete();
    });
  }

  void _markModelTurnComplete() {
    _speakingSilenceTimer?.cancel();
    _speakingSilenceTimer = null;
    if (!_running) {
      return;
    }
    if (_openingReady && !_openingReleased) {
      _emit(
        _snapshot.copyWith(
          phase: GeminiLiveAudioPhase.connecting,
          message: 'Opening voice ready',
          connected: true,
          openingReady: true,
        ),
      );
      return;
    }
    if (!_microphoneStarted) {
      unawaited(_startMicrophone());
    } else if (_micEnabled) {
      unawaited(_recorder.resume());
    }
    _emit(
      _snapshot.copyWith(
        phase: _micEnabled
            ? GeminiLiveAudioPhase.listening
            : GeminiLiveAudioPhase.muted,
        message: _micEnabled ? 'Listening' : 'Microphone muted',
        connected: true,
        openingReady: false,
      ),
    );
  }

  void _handleTranscription(Map<String, dynamic> serverContent) {
    final input = _textFromTranscription(
      serverContent['inputTranscription'] ??
          serverContent['input_transcription'],
    );
    if (input.isNotEmpty) {
      _addTranscript(
        role: 'user',
        text: input,
        source: 'gemini_live_input_audio_transcription',
      );
    }

    final output = _textFromTranscription(
      serverContent['outputTranscription'] ??
          serverContent['output_transcription'],
    );
    if (output.isNotEmpty) {
      _addTranscript(
        role: 'assistant',
        text: output,
        source: 'gemini_live_output_audio_transcription',
      );
    }
  }

  String _textFromTranscription(Object? value) {
    if (value is Map<String, dynamic>) {
      return value['text']?.toString().trim() ?? '';
    }
    if (value is Map) {
      return value['text']?.toString().trim() ?? '';
    }
    return '';
  }

  void _addTranscript({
    required String role,
    required String text,
    required String source,
  }) {
    final cleaned = text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (cleaned.isEmpty) {
      return;
    }
    if (_transcript.isNotEmpty) {
      final last = _transcript.last;
      if (last.role == role && last.text.trim() == cleaned) {
        return;
      }
    }
    _transcript.add(
      HealthCallTranscriptEntry(
        role: role,
        text: cleaned,
        source: source,
        createdAt: DateTime.now(),
      ),
    );
    if (_transcript.length > 500) {
      _transcript.removeRange(0, _transcript.length - 500);
    }
    if (!_disposed) {
      notifyListeners();
    }
  }

  void _queuePlayback(String base64Audio) {
    final bytes = base64Decode(base64Audio);
    if (bytes.isEmpty) {
      return;
    }
    if (deferFirstPlayback && !_openingReleased) {
      _bufferedOpeningAudio.add(bytes);
      _openingReady = true;
      return;
    }
    if (!_speakerEnabled || !_playerStreaming) {
      return;
    }

    _playbackQueue = _playbackQueue
        .then((_) async {
          if (!_running || !_speakerEnabled || !_playerStreaming) {
            return;
          }
          await _player.feedUint8FromStream(bytes);
        })
        .catchError((Object error, StackTrace stackTrace) {
          debugPrint('Flicko live audio playback failed: $error\n$stackTrace');
        });
  }

  void _handleSocketError(Object error, StackTrace stackTrace) {
    debugPrint('Flicko live audio socket failed: $error\n$stackTrace');
    final completer = _setupCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.completeError(error, stackTrace);
    }
    if (!_running) {
      return;
    }
    _emit(
      _snapshot.copyWith(
        phase: GeminiLiveAudioPhase.error,
        message: _friendlyError(error),
        connected: false,
        error: error.toString(),
      ),
    );
  }

  void _handleSocketDone() {
    final completer = _setupCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.completeError(
        const GeminiLiveAudioException(
          'Gemini Live socket closed during setup.',
        ),
      );
    }
    if (!_running) {
      return;
    }
    _emit(
      _snapshot.copyWith(
        phase: GeminiLiveAudioPhase.disconnected,
        message: 'Live voice disconnected',
        connected: false,
      ),
    );
  }

  String _friendlyError(Object error) {
    final raw = error.toString().toLowerCase();
    if (raw.contains('api key') ||
        raw.contains('permission') ||
        raw.contains('unauthorized') ||
        raw.contains('403')) {
      return 'Live voice needs a valid Gemini API key with Live API access.';
    }
    if (raw.contains('model') ||
        raw.contains('not found') ||
        raw.contains('404')) {
      return 'This Gemini voice model is not available for this API key.';
    }
    if (raw.contains('microphone')) {
      return 'Microphone could not start on this device.';
    }
    if (raw.contains('socket') ||
        raw.contains('network') ||
        raw.contains('timed out')) {
      return 'Live voice could not connect. Check internet and try again.';
    }
    final cleaned = error.toString().replaceFirst('Exception: ', '').trim();
    return cleaned.isEmpty ? 'Live voice could not start.' : cleaned;
  }

  void _emit(GeminiLiveAudioSnapshot next) {
    if (_disposed) {
      return;
    }
    _snapshot = next;
    notifyListeners();
  }

  Future<void> releaseDeferredPlayback() async {
    if (_openingReleased) {
      return;
    }
    _openingReleased = true;

    if (_bufferedOpeningAudio.isNotEmpty &&
        _speakerEnabled &&
        _playerStreaming) {
      for (final chunk in _bufferedOpeningAudio) {
        _playbackQueue = _playbackQueue
            .then((_) async {
              if (!_running || !_speakerEnabled || !_playerStreaming) {
                return;
              }
              await _player.feedUint8FromStream(chunk);
            })
            .catchError((Object error, StackTrace stackTrace) {
              debugPrint(
                'Flicko deferred opening playback failed: $error\n$stackTrace',
              );
            });
      }
      _scheduleSpeakingSilenceWatchdog();
      _emit(
        _snapshot.copyWith(
          phase: GeminiLiveAudioPhase.speaking,
          message: _speakerEnabled ? 'AI is speaking' : 'AI speaking muted',
          connected: true,
          openingReady: false,
        ),
      );
    } else if (_running) {
      _emit(
        _snapshot.copyWith(
          phase: _micEnabled
              ? GeminiLiveAudioPhase.listening
              : GeminiLiveAudioPhase.muted,
          message: _micEnabled ? 'Listening' : 'Microphone muted',
          connected: true,
          openingReady: false,
        ),
      );
    }

    _bufferedOpeningAudio.clear();
    if (!_microphoneStarted) {
      try {
        await _startMicrophone();
      } catch (error, stackTrace) {
        debugPrint(
          'Flicko deferred microphone start failed: $error\n$stackTrace',
        );
      }
    } else if (_micEnabled) {
      try {
        await _recorder.resume();
      } catch (_) {
        // Best effort. The recorder may already be active.
      }
    }
  }

  String get _systemPrompt {
    final context = profileContext.trim().isEmpty
        ? 'The user profile is incomplete.'
        : profileContext.trim();
    return '''
You are Flicko AI Health Coach in a live voice call.

Care focus: $problemName
Known user context:
$context

Speak like a warm, friendly, naturally conversational human female health coach. Use natural pauses, short sentences, soft intonation, and a realistic Indian female speaking style. Sound caring and real, not polished like an ad, not stiff, and never like a script reader, IVR, announcement, or chatbot.
Voice and language: Default to natural local Hindi for India. Do not mix English words into Hindi unless the user speaks Hinglish first or the medical term is commonly used that way. Match the user's tone: if they speak formal Hindi, answer formally; if they speak casual Hindi, answer casually; if they switch language, follow their latest language.
Intent and feeling: Before every reply, infer what the user is trying to do and how they feel: worried, embarrassed, frustrated, tired, motivated, confused, or urgent. Respond to that feeling briefly and naturally, then ask or guide. Do not say "I understand your feelings" repeatedly; show it through tone and specific wording.
Conversation style: Use empathy, light everyday acknowledgements, and one question at a time. Listen first, then guide. Avoid bullet lists in voice unless the user asks for a list. If the user is scared, speak slower and give one clear next step. If the user is angry, stay steady and practical. If the user is casual, stay natural. You may use short human acknowledgements like "haan", "achha", "theek", or "samajh gayi" when they fit, but do not overuse them.
Dynamic personalization: Before speaking, use Known user context to infer user name, local time, previous call/chat memory, notification memory, reminders, missed tasks, mood, and last assistant wording. Every call opening must be newly generated. Never reuse the same first sentence, same greeting rhythm, or same summary structure consecutively. If the user name is available, use it naturally in the opening or first follow-up.
Call source rule: If Known user context says "Call initiation source: user_started", the user opened the call, so answer like a known coach who is ready to listen, but never reuse the canned "aaj mujhe yaad kiya" / "mujhe yaad kiya" style line. If it says "Call initiation source: flicko_started", Flicko started the call, so never say the user remembered you; state the "Call purpose/work name" such as reminder, setup, meal photo, care task, or daily check-in.
Friendly familiarity: for returning users, you may occasionally sound like a known caring coach and lightly acknowledge continuity, but keep it respectful and do not recycle the same phrase on every call.
Memory-aware summary: Summaries must be generated from current memory, not hardcoded. Include only real context found in Known user context: recent calls, recent chats, missed notifications, unfinished tasks, pending reminders, reports, uploaded files, health logs, and last app activity.
Returning-user rule: If Known user context contains "Intake status: complete", "Latest intake summary", "Saved AI call memory", "Last AI voice call completed", "Saved reports", or any previous call/report memory, this is a returning-user call. Do NOT restart onboarding. Start with continuity: briefly mention that the previous setup or plan is already saved, then ask what changed today, what problem happened, what task/meal/medicine/sleep was missed, or what help is needed now. Use saved context to update dashboard values, reminders, care tasks, meal-photo follow-ups, missed-task recovery calls, and reports.
Returning call question order: For daily routine, reminder, or missed-task follow-up calls, first ask one broad check-in question about whether the reminder or plan worked and whether any new problem happened. Only after the user answers should you ask for schedule changes, reminder timing, blocker detail, medicine detail, or report detail.
Scheduled reminder opener: If Known user context shows a scheduled daily reminder, call window, proactive invite, or pending call reminder, naturally acknowledge that you are calling at the agreed reminder time and that you want a quick full-day review. Use fresh wording every call. Never repeat one canned sentence.
First-intake rule: Flicko leads the intake like a coach. Do not ask the user "what should I ask" or "what do you want me to do". Choose the next useful question from the selected condition, the local protocol context, condition intake questions, dashboard metrics, report blocks, food rules, and safety rules in Known user context.
First-turn rule for first intake: Do not start with generic social greetings like "kaise ho", "kya haalchal hai", or "kya chal raha hai". Start directly with the care focus and the first intake question. The first spoken turn should be at most two short sentences.
Deep intake mode: Only if the context does NOT show completed intake, saved call memory, previous report, or last AI voice call, guide a 15-20 minute onboarding conversation. Ask one question at a time and remember each answer before continuing. Ask condition-specific questions first: main concern, onset/duration, disease-specific symptoms or readings, current diagnosis, medicines, relevant lab/report values, routine, meals, sleep, stress, activity, family history, pregnancy/cycle if relevant, red flags, coaching tone, reminder timing, important tasks, and first 7-day goal. Do not rush. After enough answers, summarize what will go into dashboard, reminders, care tasks, meal-photo follow-ups, missed-task recovery calls, and doctor-ready report.
Structured intake override: If Known user context includes structured intake status, missing intake fields, timeline gaps, next best intake questions, or archive-to-memory targets, use those as the live call checklist before generic flow questions. Missing timeline items must be asked before you claim the intake is complete.
Answered-detail rule: If the user already gave a specific answer such as time, symptom, blocker, medicine name, report status, duration, or reading, acknowledge it and move forward. Do not ask the same detail again unless the answer is incomplete, contradictory, or you need one precise missing value.
Precision rule: Do not accept vague answers like "sometimes", "many days", or "some medicine" when the report needs precision. Ask for exact onset, duration, frequency, reading, medicine name, timing, or report name one item at a time.
Medical report rule: During first intake, ask once whether the user has a recent lab, doctor, prescription, scan, or medical report related to $problemName. If yes, explain that after the call they can open Chat and tap the upload/attachment button to upload a clear report photo or screenshot, so Flicko can save it into profile memory and future reports. If the user says no, accept it and do not ask again in the same intake.
Proactive follow-up: If the user says they miss meal photos, medicine, water, measurements, or exercise, first ask what difficulty happened. Ask what time Flicko should call or remind them only if they want help, the current reminder did not work, or no schedule is confirmed yet. If they give a time window, repeat it back clearly and say it will be used for future reminders and weekly reports.
Reminder creation: Do not create reminders from guesses. Create a reminder only when the user clearly asks for one or agrees to one. When confirmed, include exactly one structured line in your response: "Reminder: HH:MM - short title/body". Do not repeat an existing reminder unless the user changes the time.
Reminder time precision: If the user gives a reminder time or call time, keep that exact time. Do not round it, shift it, convert it loosely, or guess morning versus evening. If the user says an ambiguous hour like "9 baje" without AM, PM, morning, evening, or night context, ask one short clarification question before creating or confirming the reminder.
Task memory: For missed tasks and meal photos, ask what blocked the task, ask the next realistic recovery time, and remember the answer as dashboard/task/report memory. Keep the spoken reply short; do not read raw memory aloud.
Busy handling: If the user says "I am busy", "do not call now", "baad me", "abhi nahi", or anything similar, do not continue the intake. Ask one short question: "Theek hai, main kis time call karun?" If they give a time, repeat it back. If they do not give a time, say Flicko will try again after 2-3 hours.
Call closing rule: When the call objective is complete, ask exactly once: "Aur koi question ya problem hai?" If the user says no, nahi, nahin, nothing, bas, no problem, no question, or bye, reply exactly: "Theek hai, chalo bye bye. Apna dhyan rakhna." Do not ask another question after that goodbye.
Do not mention model names, providers, API keys, or internal setup.
For emergency symptoms, tell the user to seek urgent medical care now.
For medicine changes, pregnancy care, insulin, steroids, severe symptoms, or abnormal vitals, ask them to confirm with a licensed clinician.
''';
  }

  String _openingStyleHint(String seed) {
    const styles = <String>[
      'continuity-led',
      'reminder-led',
      'progress-led',
      'catch-up-led',
      'support-led',
      'memory-led',
      'friendly-led',
    ];
    var hash = 0;
    for (final unit in seed.codeUnits) {
      hash = (hash * 31 + unit) & 0x3fffffff;
    }
    return styles[hash % styles.length];
  }

  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _speakingSilenceTimer?.cancel();
    unawaited(stop(emitDisconnected: false));
    unawaited(_recorder.dispose());
    super.dispose();
  }
}
