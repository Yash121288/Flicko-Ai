import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'ai_call_memory.dart';
import 'gemini_live_audio_service.dart';

class LiveCallForegroundService {
  const LiveCallForegroundService();

  static const MethodChannel _channel = MethodChannel(
    'flicko.health/live_call_service',
  );
  static const EventChannel _events = EventChannel(
    'flicko.health/live_call_events',
  );
  static final Stream<dynamic> _sharedEvents = _events
      .receiveBroadcastStream()
      .asBroadcastStream();

  Stream<GeminiLiveAudioSnapshot> watchSnapshots() {
    return _sharedEvents
        .where((event) => event is Map && event['type'] != 'transcript')
        .map(_snapshotFromNativeEvent);
  }

  Stream<HealthCallTranscriptEntry> watchTranscript() {
    return _sharedEvents
        .where((event) => event is Map && event['type'] == 'transcript')
        .map(_transcriptFromNativeEvent);
  }

  Future<bool> start({
    required String title,
    required String subtitle,
    String apiKey = '',
    String model = '',
    String voiceName = '',
    String problemName = '',
    String profileContext = '',
    String openingScript = '',
    bool deferFirstPlayback = false,
    String baseUri = '',
  }) async {
    try {
      return await _channel.invokeMethod<bool>('start', {
            'title': title,
            'subtitle': subtitle,
            'apiKey': apiKey,
            'model': model,
            'voiceName': voiceName,
            'problemName': problemName,
            'profileContext': profileContext,
            'openingScript': openingScript,
            'deferFirstPlayback': deferFirstPlayback,
            'baseUri': baseUri,
          }) ??
          false;
    } on MissingPluginException catch (error) {
      debugPrint('Flicko call foreground service unavailable: $error');
    } on PlatformException catch (error) {
      debugPrint('Flicko call foreground service failed: ${error.message}');
    }
    return false;
  }

  Future<bool> stop() async {
    try {
      return await _channel.invokeMethod<bool>('stop') ?? false;
    } on MissingPluginException catch (error) {
      debugPrint('Flicko call foreground service unavailable: $error');
    } on PlatformException catch (error) {
      debugPrint(
        'Flicko call foreground service stop failed: ${error.message}',
      );
    }
    return false;
  }

  Future<List<HealthCallTranscriptEntry>> endCallAndFlushTranscript() async {
    try {
      final value = await _channel.invokeMethod<Object?>(
        'endCallAndFlushTranscript',
      );
      return _transcriptEntriesFromNativeValue(value);
    } on MissingPluginException catch (error) {
      debugPrint('Flicko call foreground service unavailable: $error');
    } on PlatformException catch (error) {
      debugPrint(
        'Flicko call foreground service final transcript failed: ${error.message}',
      );
    }
    return const <HealthCallTranscriptEntry>[];
  }

  Future<bool> setMicEnabled(bool enabled) async {
    try {
      return await _channel.invokeMethod<bool>('setMicEnabled', {
            'enabled': enabled,
          }) ??
          false;
    } on MissingPluginException catch (error) {
      debugPrint('Flicko call foreground service unavailable: $error');
    } on PlatformException catch (error) {
      debugPrint(
        'Flicko call foreground service mic toggle failed: ${error.message}',
      );
    }
    return false;
  }

  Future<bool> setSpeakerEnabled(bool enabled) async {
    try {
      return await _channel.invokeMethod<bool>('setSpeakerEnabled', {
            'enabled': enabled,
          }) ??
          false;
    } on MissingPluginException catch (error) {
      debugPrint('Flicko call foreground service unavailable: $error');
    } on PlatformException catch (error) {
      debugPrint(
        'Flicko call foreground service speaker toggle failed: ${error.message}',
      );
    }
    return false;
  }

  Future<bool> sendTextTurn(String text) async {
    final cleanText = text.trim();
    if (cleanText.isEmpty) {
      return false;
    }
    try {
      return await _channel.invokeMethod<bool>('sendTextTurn', {
            'text': cleanText,
          }) ??
          false;
    } on MissingPluginException catch (error) {
      debugPrint('Flicko call foreground service unavailable: $error');
    } on PlatformException catch (error) {
      debugPrint(
        'Flicko call foreground service text turn failed: ${error.message}',
      );
    }
    return false;
  }

  Future<bool> releaseDeferredPlayback() async {
    try {
      return await _channel.invokeMethod<bool>('releaseDeferredPlayback') ??
          false;
    } on MissingPluginException catch (error) {
      debugPrint('Flicko call foreground service unavailable: $error');
    } on PlatformException catch (error) {
      debugPrint(
        'Flicko call foreground service deferred playback failed: ${error.message}',
      );
    }
    return false;
  }

  Future<List<HealthCallTranscriptEntry>> getTranscript() async {
    try {
      final value = await _channel.invokeMethod<Object?>('getTranscript');
      return _transcriptEntriesFromNativeValue(value);
    } on MissingPluginException catch (error) {
      debugPrint('Flicko call foreground service unavailable: $error');
    } on PlatformException catch (error) {
      debugPrint(
        'Flicko call foreground service transcript failed: ${error.message}',
      );
    }
    return const <HealthCallTranscriptEntry>[];
  }

  Future<bool> isRunning() async {
    try {
      return await _channel.invokeMethod<bool>('isRunning') ?? false;
    } on MissingPluginException catch (error) {
      debugPrint('Flicko call foreground service unavailable: $error');
    } on PlatformException catch (error) {
      debugPrint(
        'Flicko call foreground service running-state failed: ${error.message}',
      );
    }
    return false;
  }

  Future<bool> consumeOpenLiveCallSignal() async {
    try {
      return await _channel.invokeMethod<bool>('consumeOpenLiveCallSignal') ??
          false;
    } on MissingPluginException catch (error) {
      debugPrint('Flicko call foreground service unavailable: $error');
    } on PlatformException catch (error) {
      debugPrint(
        'Flicko call foreground service open-signal failed: ${error.message}',
      );
    }
    return false;
  }

  List<HealthCallTranscriptEntry> _transcriptEntriesFromNativeValue(
    Object? value,
  ) {
    if (value is! List) {
      return const <HealthCallTranscriptEntry>[];
    }
    return value
        .whereType<Map>()
        .map((entry) => _transcriptFromNativeEvent(entry))
        .where((entry) => entry.text.trim().isNotEmpty)
        .toList(growable: false);
  }

  GeminiLiveAudioSnapshot _snapshotFromNativeEvent(dynamic event) {
    if (event is! Map) {
      return const GeminiLiveAudioSnapshot(
        phase: GeminiLiveAudioPhase.error,
        message: 'Unknown native call state',
        connected: false,
        error: 'Invalid native call event',
      );
    }
    final phase = _phaseFromNative(event['phase']?.toString());
    final isSpeaking = event['isSpeaking'] == true;
    return GeminiLiveAudioSnapshot(
      phase: isSpeaking ? GeminiLiveAudioPhase.speaking : phase,
      message: event['message']?.toString() ?? 'Native live voice active',
      micEnabled: event['micEnabled'] != false,
      speakerEnabled: event['speakerEnabled'] != false,
      connected: event['connected'] == true,
      openingReady: event['openingReady'] == true,
      error: event['error']?.toString(),
    );
  }

  GeminiLiveAudioPhase _phaseFromNative(String? phase) {
    switch (phase) {
      case 'connecting':
        return GeminiLiveAudioPhase.connecting;
      case 'listening':
        return GeminiLiveAudioPhase.listening;
      case 'speaking':
        return GeminiLiveAudioPhase.speaking;
      case 'muted':
        return GeminiLiveAudioPhase.muted;
      case 'disconnected':
        return GeminiLiveAudioPhase.disconnected;
      case 'error':
        return GeminiLiveAudioPhase.error;
      default:
        return GeminiLiveAudioPhase.idle;
    }
  }

  HealthCallTranscriptEntry _transcriptFromNativeEvent(dynamic event) {
    if (event is! Map) {
      return HealthCallTranscriptEntry(
        role: 'assistant',
        text: '',
        createdAt: DateTime.now(),
      );
    }
    final createdAtMs = event['createdAt'];
    return HealthCallTranscriptEntry(
      role: event['role']?.toString() == 'user' ? 'user' : 'assistant',
      text: event['text']?.toString() ?? '',
      source: event['source']?.toString() ?? 'gemini_live_native',
      createdAt: createdAtMs is int
          ? DateTime.fromMillisecondsSinceEpoch(createdAtMs)
          : DateTime.now(),
      isFinal: event['isFinal'] != false,
    );
  }
}
