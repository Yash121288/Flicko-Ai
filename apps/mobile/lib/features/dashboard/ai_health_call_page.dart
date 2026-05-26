import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:logger/logger.dart' show Level;
import 'package:permission_handler/permission_handler.dart';

import '../protocols/local_protocol_pack.dart';
import '../safety/flicko_safety_alert_sheet.dart';
import '../safety/flicko_safety_engine.dart';
import 'ai_call_auto_end_coordinator.dart';
import 'ai_call_models.dart';
import 'ai_call_transcript_store.dart';
import 'ai_call_memory.dart';
import 'flicko_voice_context_engine.dart';
import 'gemini_live_audio_service.dart';
import 'gemini_health_chat_client.dart';
import 'live_call_foreground_service.dart';

enum AiHealthCallResult { ended, openChat, openChatUploadReport }

class AiHealthCallPage extends StatefulWidget {
  const AiHealthCallPage({
    super.key,
    required this.problemName,
    required this.profileContext,
    this.reason = AiCallInviteReason.notification,
    this.coachName = 'Flicko Health Coach',
    this.subtitle = 'Live health check-in',
    this.coachImageAsset = 'assets/images/dashboard/live_coach.png',
    this.apiKey = kFlickoGeminiApiKey,
    this.nativeAudioModel = kFlickoGeminiNativeAudioModel,
    this.nativeAudioVoice = kFlickoGeminiNativeAudioVoice,
    this.callSessionId,
    this.startedAt,
    this.playConnectTone = true,
    this.prewarmedProfileContext,
    this.prewarmedOpeningScript,
    this.emergencyContactName = '',
    this.emergencyContactPhone = '',
    this.userName = '',
    this.onLoadBackendContext,
    this.onCallTranscriptReady,
    this.onSafetyEvent,
  });

  final String problemName;
  final String profileContext;
  final AiCallInviteReason reason;
  final String coachName;
  final String subtitle;
  final String coachImageAsset;
  final String apiKey;
  final String nativeAudioModel;
  final String nativeAudioVoice;
  final String? callSessionId;
  final DateTime? startedAt;
  final bool playConnectTone;
  final String? prewarmedProfileContext;
  final String? prewarmedOpeningScript;
  final String emergencyContactName;
  final String emergencyContactPhone;
  final String userName;
  final Future<String> Function()? onLoadBackendContext;
  final ValueChanged<List<HealthCallTranscriptEntry>>? onCallTranscriptReady;
  final FlickoSafetyEventWriter? onSafetyEvent;

  @override
  State<AiHealthCallPage> createState() => _AiHealthCallPageState();
}

class _AiHealthCallPageState extends State<AiHealthCallPage>
    with SingleTickerProviderStateMixin {
  static const String _connectToneAsset =
      'assets/audio/dragon-studio-phone-ringing-382734.mp3';
  static const Duration _connectToneMinimum = Duration(milliseconds: 1800);
  static const Duration _connectToneMaximum = Duration(milliseconds: 4500);

  late final AnimationController _controller;
  Timer? _timer;
  Timer? _autoEndCallTimer;
  Timer? _connectToneReleaseTimer;
  Timer? _connectToneForceTimer;
  Duration _elapsed = Duration.zero;
  bool _micOn = true;
  bool _speakerOn = true;
  bool _micPermissionGranted = true;
  bool _requestingMicPermission = false;
  final LiveCallForegroundService _foregroundService =
      const LiveCallForegroundService();
  final AiCallTranscriptStore _transcriptStore = AiCallTranscriptStore();
  final AiCallAutoEndCoordinator _autoEndCoordinator =
      AiCallAutoEndCoordinator();
  final LocalProtocolPackRepository _protocolRepository =
      const LocalProtocolPackRepository();
  final FlickoVoiceContextEngine _voiceContextEngine =
      const FlickoVoiceContextEngine();
  final FlutterSoundPlayer _connectTonePlayer = FlutterSoundPlayer(
    logLevel: Level.warning,
  );
  GeminiLiveAudioService? _voiceService;
  StreamSubscription<GeminiLiveAudioSnapshot>? _nativeSnapshotSubscription;
  StreamSubscription<HealthCallTranscriptEntry>? _nativeTranscriptSubscription;
  final List<HealthCallTranscriptEntry> _callTranscript =
      <HealthCallTranscriptEntry>[];
  final Set<String> _handledSafetyTranscriptKeys = <String>{};
  late final String _callSessionId;
  late final DateTime _startedAt;
  bool _usingNativeTransport = false;
  bool _nativeFallbackAttempted = false;
  bool _endingCall = false;
  String? _resolvedProfileContext;
  bool _callLiveStarted = false;
  bool _connectTonePlayerOpen = false;
  bool _deferredOpeningReleased = false;
  bool _safetySheetOpen = false;
  DateTime? _connectToneStartedAt;
  GeminiLiveAudioSnapshot _voiceSnapshot = const GeminiLiveAudioSnapshot(
    phase: GeminiLiveAudioPhase.idle,
    message: 'Preparing voice call',
  );

  bool get _nativeAudioReady =>
      widget.apiKey.trim().isNotEmpty &&
      widget.nativeAudioModel.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _startedAt = widget.startedAt ?? DateTime.now();
    _callSessionId =
        widget.callSessionId ??
        'call-${_startedAt.microsecondsSinceEpoch}-${widget.problemName.hashCode.abs()}';
    final prewarmedContext = widget.prewarmedProfileContext?.trim() ?? '';
    if (prewarmedContext.isNotEmpty) {
      _resolvedProfileContext = prewarmedContext;
    }
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();
    if (widget.playConnectTone) {
      unawaited(_startConnectTone());
    } else {
      _deferredOpeningReleased = true;
      _callLiveStarted = true;
      _elapsed = DateTime.now().difference(_startedAt);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_beginTranscriptPersistence());
      if (mounted) {
        unawaited(_startLiveVoice());
      }
    });
  }

  Future<void> _beginTranscriptPersistence() async {
    await _transcriptStore.beginSession(
      sessionId: _callSessionId,
      problemName: widget.problemName,
      reason: widget.reason,
      subtitle: widget.subtitle,
      profileContext: widget.profileContext,
      startedAt: _startedAt,
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _autoEndCallTimer?.cancel();
    _connectToneReleaseTimer?.cancel();
    _connectToneForceTimer?.cancel();
    unawaited(_stopConnectTone());
    unawaited(_disposeConnectTonePlayer());
    unawaited(_nativeSnapshotSubscription?.cancel());
    unawaited(_nativeTranscriptSubscription?.cancel());
    _disposeVoiceService();
    unawaited(_foregroundService.stop());
    _controller.dispose();
    super.dispose();
  }

  String get _formattedTime {
    final minutes = _elapsed.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = _elapsed.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Future<void> _startConnectTone() async {
    try {
      if (!_connectTonePlayerOpen) {
        await _connectTonePlayer.openPlayer();
        _connectTonePlayer.setLogLevel(Level.warning);
        _connectTonePlayerOpen = true;
      }
      final byteData = await rootBundle.load(_connectToneAsset);
      final bytes = byteData.buffer.asUint8List();
      if (bytes.isEmpty) {
        return;
      }
      _connectToneStartedAt = DateTime.now();
      _deferredOpeningReleased = false;
      await _connectTonePlayer.startPlayer(
        fromDataBuffer: bytes,
        codec: Codec.mp3,
      );
      _connectToneForceTimer?.cancel();
      _connectToneForceTimer = Timer(_connectToneMaximum, () {
        if (mounted) {
          unawaited(_releaseDeferredOpening(force: true));
        }
      });
    } catch (_) {
      _connectToneStartedAt = DateTime.now();
      _connectToneForceTimer?.cancel();
      _connectToneForceTimer = Timer(_connectToneMaximum, () {
        if (mounted) {
          unawaited(_releaseDeferredOpening(force: true));
        }
      });
    }
  }

  Future<void> _stopConnectTone() async {
    _connectToneReleaseTimer?.cancel();
    _connectToneForceTimer?.cancel();
    try {
      if (_connectTonePlayerOpen) {
        await _connectTonePlayer.stopPlayer();
      }
    } catch (_) {
      // Best effort. The tone may already be finished.
    }
  }

  Future<void> _disposeConnectTonePlayer() async {
    try {
      if (_connectTonePlayerOpen) {
        await _connectTonePlayer.closePlayer();
      }
    } catch (_) {
      // Best effort during teardown.
    } finally {
      _connectTonePlayerOpen = false;
    }
  }

  Future<void> _releaseDeferredOpening({bool force = false}) async {
    if (_deferredOpeningReleased) {
      if (force) {
        await _stopConnectTone();
        if (_voiceSnapshot.connected &&
            _voiceSnapshot.phase != GeminiLiveAudioPhase.connecting) {
          _markCallLive();
        }
      }
      return;
    }
    final startedAt = _connectToneStartedAt;
    if (!force && startedAt != null) {
      final elapsed = DateTime.now().difference(startedAt);
      if (elapsed < _connectToneMinimum) {
        _connectToneReleaseTimer?.cancel();
        _connectToneReleaseTimer = Timer(_connectToneMinimum - elapsed, () {
          if (mounted) {
            unawaited(_releaseDeferredOpening(force: true));
          }
        });
        return;
      }
    }
    _deferredOpeningReleased = true;
    _connectToneReleaseTimer?.cancel();
    _connectToneForceTimer?.cancel();
    if (_usingNativeTransport) {
      await _foregroundService.releaseDeferredPlayback();
    } else {
      await _voiceService?.releaseDeferredPlayback();
    }
    await _stopConnectTone();
    if (_voiceSnapshot.connected &&
        _voiceSnapshot.phase != GeminiLiveAudioPhase.connecting) {
      _markCallLive();
    }
  }

  void _markCallLive() {
    if (_callLiveStarted) {
      return;
    }
    _callLiveStarted = true;
    _elapsed = DateTime.now().difference(_startedAt);
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) {
        return;
      }
      setState(() => _elapsed = DateTime.now().difference(_startedAt));
    });
    if (mounted) {
      setState(() {});
    }
  }

  void _handleOpeningState(GeminiLiveAudioSnapshot snapshot) {
    if (snapshot.openingReady) {
      unawaited(_releaseDeferredOpening());
      return;
    }
    if (!_deferredOpeningReleased &&
        (snapshot.phase == GeminiLiveAudioPhase.speaking ||
            (snapshot.connected &&
                snapshot.phase == GeminiLiveAudioPhase.listening))) {
      unawaited(_releaseDeferredOpening(force: true));
      return;
    }
    if (_deferredOpeningReleased &&
        snapshot.connected &&
        snapshot.phase != GeminiLiveAudioPhase.connecting) {
      _markCallLive();
    }
  }

  Future<bool> _ensureMicrophonePermission({
    required bool requestIfNeeded,
  }) async {
    if (_requestingMicPermission) {
      return _micPermissionGranted;
    }
    _requestingMicPermission = true;
    try {
      var status = await Permission.microphone.status;
      if (!status.isGranted && requestIfNeeded) {
        status = await Permission.microphone.request();
      }

      if (!mounted) {
        return false;
      }

      setState(() {
        _micPermissionGranted = status.isGranted;
        _micOn = status.isGranted && _micOn;
      });

      if (!status.isGranted && mounted) {
        _showInfo(
          status.isPermanentlyDenied
              ? 'Microphone permission is blocked. Enable it from app settings.'
              : 'Microphone permission is needed for live voice.',
        );
      }
      return status.isGranted;
    } catch (_) {
      if (!mounted) {
        return false;
      }
      setState(() {
        _micPermissionGranted = false;
        _micOn = false;
        _voiceSnapshot = _voiceSnapshot.copyWith(
          phase: GeminiLiveAudioPhase.error,
          message: 'Microphone permission plugin is unavailable here',
          connected: false,
        );
      });
      return false;
    } finally {
      _requestingMicPermission = false;
    }
  }

  Future<void> _startLiveVoice() async {
    final allowed = await _ensureMicrophonePermission(requestIfNeeded: true);
    if (!mounted || !allowed || !_nativeAudioReady) {
      if (!allowed || !_nativeAudioReady) {
        await _stopConnectTone();
      }
      return;
    }
    final profileContext = await _voiceProfileContext();
    final scriptedOpening = widget.prewarmedOpeningScript?.trim() ?? '';
    if (!mounted || _endingCall) {
      return;
    }

    final alreadyRunning = await _foregroundService.isRunning();
    if (alreadyRunning && mounted) {
      _attachNativeTransport('Resuming live voice');
      return;
    }

    final nativeStarted = await _foregroundService.start(
      title: 'Call in progress',
      subtitle: '',
      apiKey: widget.apiKey,
      model: widget.nativeAudioModel,
      voiceName: widget.nativeAudioVoice,
      problemName: widget.problemName,
      profileContext: profileContext,
      openingScript: scriptedOpening,
      deferFirstPlayback: true,
      baseUri: const String.fromEnvironment('FLICKO_GEMINI_LIVE_WS_URL'),
    );
    if (nativeStarted && mounted) {
      _attachNativeTransport('Connecting native live voice');
      return;
    }

    await _startDartLiveFallback(
      'Native live voice service unavailable',
      profileContext: profileContext,
      openingScript: scriptedOpening,
    );
  }

  Future<String> _voiceProfileContext() async {
    final cached = _resolvedProfileContext;
    if (cached != null) {
      return cached;
    }
    var localProtocolContext = '';
    try {
      final context = await _protocolRepository.contextFor(
        problemName: widget.problemName,
        profileContext: widget.profileContext,
        userText: 'voice intake setup and medical report checklist',
      );
      localProtocolContext = context.toPromptText().trim();
    } catch (_) {
      localProtocolContext = '';
    }
    final backendLoader = widget.onLoadBackendContext;
    if (backendLoader == null) {
      _resolvedProfileContext = await _voiceContextEngine.buildContext(
        problemName: widget.problemName,
        profileContext: widget.profileContext,
        protocolContext: localProtocolContext,
      );
      return _resolvedProfileContext!;
    }
    try {
      final backendContext = (await backendLoader()).trim();
      _resolvedProfileContext = await _voiceContextEngine.buildContext(
        problemName: widget.problemName,
        profileContext: widget.profileContext,
        protocolContext: localProtocolContext,
        backendContext: backendContext,
      );
    } catch (_) {
      _resolvedProfileContext = await _voiceContextEngine.buildContext(
        problemName: widget.problemName,
        profileContext: widget.profileContext,
        protocolContext: localProtocolContext,
      );
    }
    return _resolvedProfileContext!;
  }

  Future<void> _startDartLiveFallback(
    String reason, {
    String? profileContext,
    String openingScript = '',
  }) async {
    if (!mounted || _nativeFallbackAttempted || _endingCall) {
      return;
    }
    _nativeFallbackAttempted = true;
    unawaited(_nativeSnapshotSubscription?.cancel());
    _nativeSnapshotSubscription = null;
    unawaited(_nativeTranscriptSubscription?.cancel());
    _nativeTranscriptSubscription = null;
    _usingNativeTransport = false;
    unawaited(_foregroundService.stop());
    _disposeVoiceService();
    setState(() {
      _voiceSnapshot = GeminiLiveAudioSnapshot(
        phase: GeminiLiveAudioPhase.connecting,
        message: 'Reconnecting live voice',
        connected: false,
        micEnabled: _micOn,
        speakerEnabled: _speakerOn,
        error: reason,
      );
    });

    final service = GeminiLiveAudioService(
      apiKey: widget.apiKey,
      model: widget.nativeAudioModel,
      voiceName: widget.nativeAudioVoice,
      problemName: widget.problemName,
      profileContext: profileContext ?? await _voiceProfileContext(),
      openingScript: openingScript,
      deferFirstPlayback: true,
    );
    service.addListener(_handleVoiceChanged);
    _voiceService = service;
    await service.start();
  }

  void _attachNativeTransport(String message) {
    _nativeSnapshotSubscription?.cancel();
    _nativeSnapshotSubscription = _foregroundService.watchSnapshots().listen(
      _handleNativeVoiceSnapshot,
      onError: _handleNativeVoiceError,
    );
    _nativeTranscriptSubscription?.cancel();
    _nativeTranscriptSubscription = _foregroundService.watchTranscript().listen(
      _handleNativeTranscript,
      onError: (error) =>
          debugPrint('Flicko native live transcript stream failed: $error'),
    );
    setState(() {
      _usingNativeTransport = true;
      _voiceSnapshot = GeminiLiveAudioSnapshot(
        phase: GeminiLiveAudioPhase.connecting,
        message: message,
        connected: false,
      );
    });
  }

  Future<void> _endLiveCall(AiHealthCallResult result) async {
    if (_endingCall) {
      return;
    }
    _endingCall = true;
    _timer?.cancel();
    _autoEndCallTimer?.cancel();
    await _stopConnectTone();
    final wasUsingNativeTransport = _usingNativeTransport;
    if (mounted) {
      setState(() {
        _voiceSnapshot = _voiceSnapshot.copyWith(
          phase: GeminiLiveAudioPhase.disconnected,
          message: 'Saving final transcript',
          connected: false,
        );
      });
    }
    final immediateTranscript = _mergeTranscript(
      _callTranscript,
      _voiceService?.transcriptSnapshot ?? const <HealthCallTranscriptEntry>[],
    );
    final nativeTranscript = wasUsingNativeTransport
        ? await _flushNativeTranscript()
        : const <HealthCallTranscriptEntry>[];
    final transcript = _mergeTranscript(immediateTranscript, nativeTranscript);
    widget.onCallTranscriptReady?.call(transcript);
    unawaited(_nativeSnapshotSubscription?.cancel());
    _nativeSnapshotSubscription = null;
    unawaited(_nativeTranscriptSubscription?.cancel());
    _nativeTranscriptSubscription = null;
    _disposeVoiceService();
    _usingNativeTransport = false;
    if (!wasUsingNativeTransport) {
      unawaited(_foregroundService.stop());
    }
    if (mounted) {
      Navigator.of(context).pop(result);
    }
    unawaited(_finishCallCleanup(transcript));
  }

  Future<void> _finishCallCleanup(
    List<HealthCallTranscriptEntry> immediateTranscript,
  ) async {
    final persistedTranscript = await _readPersistedTranscript();
    final transcript = _mergeTranscript(
      immediateTranscript,
      persistedTranscript,
    );
    await _completeTranscriptSession(transcript);
    widget.onCallTranscriptReady?.call(transcript);
  }

  Future<List<HealthCallTranscriptEntry>> _readPersistedTranscript() async {
    try {
      return await _transcriptStore
          .readTranscript(_callSessionId)
          .timeout(const Duration(milliseconds: 700));
    } catch (_) {
      return const <HealthCallTranscriptEntry>[];
    }
  }

  Future<List<HealthCallTranscriptEntry>> _readNativeTranscript() async {
    try {
      return await _foregroundService.getTranscript().timeout(
        const Duration(milliseconds: 700),
      );
    } catch (_) {
      return const <HealthCallTranscriptEntry>[];
    }
  }

  Future<List<HealthCallTranscriptEntry>> _flushNativeTranscript() async {
    try {
      return await _foregroundService.endCallAndFlushTranscript().timeout(
        const Duration(milliseconds: 1500),
      );
    } catch (_) {
      return _readNativeTranscript();
    }
  }

  Future<void> _completeTranscriptSession(
    List<HealthCallTranscriptEntry> transcript,
  ) async {
    try {
      await _transcriptStore
          .completeSession(sessionId: _callSessionId, transcript: transcript)
          .timeout(const Duration(milliseconds: 900));
    } catch (_) {
      // Closing the call UI must not be blocked by secure-storage issues.
    }
  }

  void _disposeVoiceService() {
    final service = _voiceService;
    if (service == null) {
      return;
    }
    service.removeListener(_handleVoiceChanged);
    _voiceService = null;
    service.dispose();
  }

  void _handleVoiceChanged() {
    final service = _voiceService;
    if (!mounted || service == null) {
      return;
    }
    final next = service.snapshot;
    _ingestFallbackTranscript(service.transcriptSnapshot);
    setState(() {
      _voiceSnapshot = next;
      _micOn = next.micEnabled;
      _speakerOn = next.speakerEnabled;
    });
    _handleOpeningState(next);
  }

  void _handleNativeVoiceSnapshot(GeminiLiveAudioSnapshot next) {
    if (!mounted || !_usingNativeTransport) {
      return;
    }
    setState(() {
      _voiceSnapshot = next;
      _micOn = next.micEnabled;
      _speakerOn = next.speakerEnabled;
    });
    _handleOpeningState(next);
    if (_shouldFallbackFromNative(next)) {
      unawaited(
        _startDartLiveFallback(
          next.error ?? next.message,
          openingScript: widget.prewarmedOpeningScript?.trim() ?? '',
        ),
      );
    }
  }

  void _handleNativeTranscript(HealthCallTranscriptEntry entry) {
    if (!mounted || entry.text.trim().isEmpty) {
      return;
    }
    _appendTranscript(entry);
  }

  void _ingestFallbackTranscript(List<HealthCallTranscriptEntry> entries) {
    for (final entry in entries) {
      _appendTranscript(entry);
    }
  }

  void _handleNativeVoiceError(Object error) {
    if (!mounted || !_usingNativeTransport) {
      return;
    }
    setState(() {
      _voiceSnapshot = GeminiLiveAudioSnapshot(
        phase: GeminiLiveAudioPhase.error,
        message: 'Native live voice status unavailable',
        connected: false,
        micEnabled: _micOn,
        speakerEnabled: _speakerOn,
        error: error.toString(),
      );
    });
    unawaited(
      _startDartLiveFallback(
        error.toString(),
        openingScript: widget.prewarmedOpeningScript?.trim() ?? '',
      ),
    );
  }

  bool _shouldFallbackFromNative(GeminiLiveAudioSnapshot snapshot) {
    if (_nativeFallbackAttempted || _endingCall) {
      return false;
    }
    if (snapshot.connected) {
      return false;
    }
    return snapshot.phase == GeminiLiveAudioPhase.error ||
        snapshot.phase == GeminiLiveAudioPhase.disconnected;
  }

  Future<void> _toggleMic() async {
    if (!_micPermissionGranted) {
      await _ensureMicrophonePermission(requestIfNeeded: true);
      return;
    }
    final next = !_micOn;
    final previous = _micOn;
    setState(() => _micOn = next);
    var success = true;
    if (_usingNativeTransport) {
      success = await _foregroundService.setMicEnabled(next);
    } else {
      await _voiceService?.setMicEnabled(next);
    }
    if (!mounted || success) {
      return;
    }
    setState(() => _micOn = previous);
    _showInfo('Microphone control did not update.');
  }

  Future<void> _toggleSpeaker() async {
    final next = !_speakerOn;
    final previous = _speakerOn;
    setState(() => _speakerOn = next);
    var success = true;
    if (_usingNativeTransport) {
      success = await _foregroundService.setSpeakerEnabled(next);
    } else {
      await _voiceService?.setSpeakerEnabled(next);
    }
    if (!mounted || success) {
      return;
    }
    setState(() => _speakerOn = previous);
    _showInfo('Speaker control did not update.');
  }

  void _showInfo(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  void _appendTranscript(HealthCallTranscriptEntry entry) {
    final cleanText = entry.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (cleanText.isEmpty) {
      return;
    }
    if (_callTranscript.isNotEmpty) {
      final last = _callTranscript.last;
      if (last.role == entry.role && last.text.trim() == cleanText) {
        return;
      }
    }
    _callTranscript.add(
      HealthCallTranscriptEntry(
        role: entry.role,
        text: cleanText,
        createdAt: entry.createdAt,
        isFinal: entry.isFinal,
        source: entry.source,
      ),
    );
    if (_callTranscript.length > 500) {
      _callTranscript.removeRange(0, _callTranscript.length - 500);
    }
    unawaited(
      _transcriptStore.appendEntry(
        sessionId: _callSessionId,
        entry: _callTranscript.last,
      ),
    );
    _handleAutoEndTranscript(_callTranscript.last);
    _handleSafetyTranscript(_callTranscript.last);
  }

  void _handleSafetyTranscript(HealthCallTranscriptEntry entry) {
    if (!entry.isUser) {
      return;
    }
    final text = entry.text.trim();
    if (text.isEmpty) {
      return;
    }
    final key = text.toLowerCase();
    if (!_handledSafetyTranscriptKeys.add(key)) {
      return;
    }
    final safetyEvent = FlickoSafetyEngine.evaluate(
      text: text,
      problemName: widget.problemName,
      source: 'call',
    );
    if (safetyEvent == null) {
      return;
    }
    unawaited(_surfaceSafetyEvent(safetyEvent));
  }

  Future<void> _surfaceSafetyEvent(FlickoSafetyEvent event) async {
    _sendSafetyVoiceInstruction(event);
    await widget.onSafetyEvent?.call(event);
    if (!mounted || _safetySheetOpen) {
      return;
    }
    _safetySheetOpen = true;
    try {
      await showFlickoSafetyAlertSheet(
        context: context,
        event: event,
        emergencyContactName: widget.emergencyContactName,
        emergencyContactPhone: widget.emergencyContactPhone,
        userName: widget.userName,
        autoOpenEmergencyContact:
            event.severity == FlickoSafetySeverity.emergency,
      );
    } finally {
      _safetySheetOpen = false;
    }
  }

  void _sendSafetyVoiceInstruction(FlickoSafetyEvent event) {
    final instruction =
        'The user reported this safety red flag: ${event.title}. '
        'Stop normal coaching. Say in the user language: '
        '"Emergency symptoms lag rahe hain. Main aapke emergency contact ka call abhi open kar rahi hoon." '
        'Then tell the user to say this to the contact: '
        '"${buildFlickoEmergencyHandoffMessage(userName: widget.userName, event: event)}" '
        'Do not continue routine intake until they are safe. Action: ${event.action}';
    if (_usingNativeTransport) {
      unawaited(_foregroundService.sendTextTurn(instruction));
    } else {
      _voiceService?.sendTextTurn(instruction);
    }
  }

  void _handleAutoEndTranscript(HealthCallTranscriptEntry entry) {
    final action = _autoEndCoordinator.observe(entry);
    switch (action) {
      case AiCallAutoEndAction.requestGoodbye:
        _requestGoodbyeAndScheduleCallEnd();
        break;
      case AiCallAutoEndAction.finishAfterGoodbye:
        _scheduleAutoEndCall(const Duration(milliseconds: 1400));
        break;
      case AiCallAutoEndAction.none:
      case AiCallAutoEndAction.markClosingQuestionAsked:
        break;
    }
  }

  void _requestGoodbyeAndScheduleCallEnd() {
    if (_endingCall) {
      return;
    }
    const instruction =
        'The user said they have no more questions or problems. '
        'Say exactly: "Theek hai, chalo bye bye. Apna dhyan rakhna." '
        'Do not ask another question after this.';
    if (_usingNativeTransport) {
      unawaited(_foregroundService.sendTextTurn(instruction));
    } else {
      _voiceService?.sendTextTurn(instruction);
    }
    _scheduleAutoEndCall(const Duration(seconds: 5));
  }

  void _scheduleAutoEndCall(Duration delay) {
    if (_endingCall) {
      return;
    }
    _autoEndCallTimer?.cancel();
    _autoEndCallTimer = Timer(delay, () {
      if (!mounted || _endingCall) {
        return;
      }
      unawaited(_endLiveCall(AiHealthCallResult.ended));
    });
  }

  List<HealthCallTranscriptEntry> _mergeTranscript(
    List<HealthCallTranscriptEntry> first,
    List<HealthCallTranscriptEntry> second,
  ) {
    final seen = <String>{};
    final merged = <HealthCallTranscriptEntry>[];
    for (final entry in [...first, ...second]) {
      final text = entry.text.trim().replaceAll(RegExp(r'\s+'), ' ');
      if (text.isEmpty) {
        continue;
      }
      final key =
          '${entry.role}|$text|${entry.createdAt.millisecondsSinceEpoch ~/ 1000}';
      if (!seen.add(key)) {
        continue;
      }
      merged.add(
        HealthCallTranscriptEntry(
          role: entry.role,
          text: text,
          createdAt: entry.createdAt,
          isFinal: entry.isFinal,
          source: entry.source,
        ),
      );
    }
    merged.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return merged;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFCFDFB),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.1),
            radius: 1.05,
            colors: [Color(0xFFF4FBF5), Color(0xFFFDFEFC), Color(0xFFF8FAF8)],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
            child: Column(
              children: [
                _CallTopBar(
                  nativeAudioReady: _nativeAudioReady,
                  onBack: () =>
                      unawaited(_endLiveCall(AiHealthCallResult.ended)),
                  onUpload: () => unawaited(
                    _endLiveCall(AiHealthCallResult.openChatUploadReport),
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(top: 14),
                    child: Column(
                      children: [
                        const SizedBox(height: 8),
                        RepaintBoundary(
                          child: _CoachHero(imageAsset: widget.coachImageAsset),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          widget.coachName,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Color(0xFF0C3027),
                            fontSize: 25,
                            height: 1.1,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 7),
                        Text(
                          widget.subtitle,
                          style: const TextStyle(
                            color: Color(0xFF6D7A74),
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _callLiveStarted ? _formattedTime : 'Connecting...',
                          style: const TextStyle(
                            color: Color(0xFF4BA861),
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 14),
                        RepaintBoundary(
                          child: SizedBox(
                            width: double.infinity,
                            height: 48,
                            child:
                                _callLiveStarted &&
                                    _voiceSnapshot.connected &&
                                    _speakerOn
                                ? AnimatedBuilder(
                                    animation: _controller,
                                    builder: (context, _) {
                                      return CustomPaint(
                                        painter: _WaveformPainter(
                                          _controller.value,
                                          enabled: true,
                                        ),
                                      );
                                    },
                                  )
                                : CustomPaint(
                                    painter: _WaveformPainter(
                                      0,
                                      enabled: false,
                                    ),
                                  ),
                          ),
                        ),
                        if (!_micPermissionGranted ||
                            _voiceSnapshot.phase == GeminiLiveAudioPhase.error)
                          Padding(
                            padding: const EdgeInsets.only(top: 18),
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFF4EE),
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: const Color(0xFFFFD9C5),
                                ),
                              ),
                              child: Text(
                                !_micPermissionGranted
                                    ? 'Microphone permission is blocked.'
                                    : _voiceSnapshot.error?.trim().isNotEmpty ==
                                          true
                                    ? _voiceSnapshot.error!.trim()
                                    : _voiceSnapshot.message,
                                style: const TextStyle(
                                  color: Color(0xFF8F3E0D),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(12, 16, 12, 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(34),
                    border: Border.all(color: const Color(0xFFE6EEE7)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.07),
                        blurRadius: 26,
                        offset: const Offset(0, 14),
                      ),
                    ],
                  ),
                  child: SafeArea(
                    top: false,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _CallControlButton(
                          icon: _micOn
                              ? Icons.mic_rounded
                              : Icons.mic_off_rounded,
                          label: 'Mic',
                          active: _micPermissionGranted && _micOn,
                          onTap: _toggleMic,
                        ),
                        _CallControlButton(
                          icon: _speakerOn
                              ? Icons.volume_up_rounded
                              : Icons.volume_mute_rounded,
                          label: 'Speaker',
                          active: _speakerOn,
                          onTap: () => unawaited(_toggleSpeaker()),
                        ),
                        _EndCallButton(
                          onTap: () =>
                              unawaited(_endLiveCall(AiHealthCallResult.ended)),
                        ),
                        _CallControlButton(
                          icon: Icons.chat_bubble_outline_rounded,
                          label: 'Chat',
                          onTap: () => unawaited(
                            _endLiveCall(AiHealthCallResult.openChat),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CallTopBar extends StatelessWidget {
  const _CallTopBar({
    required this.nativeAudioReady,
    required this.onBack,
    required this.onUpload,
  });

  final bool nativeAudioReady;
  final VoidCallback onBack;
  final VoidCallback onUpload;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        GestureDetector(
          onTap: onBack,
          child: Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(
              color: Color(0xFFF0F6EE),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.arrow_back_ios_new_rounded,
              color: Color(0xFF205B41),
              size: 18,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Image.asset(
          'assets/images/mainlogo.png',
          width: 48,
          height: 48,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) {
            return const Icon(
              Icons.favorite_rounded,
              color: Color(0xFF149447),
              size: 44,
            );
          },
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Flicko AI',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Color(0xFF10362D),
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                nativeAudioReady
                    ? 'Your AI Health Assistant'
                    : 'Voice setup pending',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF7A8782),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        const _TopIconBubble(icon: Icons.shield_outlined),
        const SizedBox(width: 10),
        _TopIconBubble(icon: Icons.attach_file_rounded, onTap: onUpload),
      ],
    );
  }
}

class _TopIconBubble extends StatelessWidget {
  const _TopIconBubble({required this.icon, this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 52,
        height: 52,
        decoration: const BoxDecoration(
          color: Color(0xFFF0F6EE),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Color(0xFF205B41), size: 24),
      ),
    );
  }
}

class _CoachHero extends StatelessWidget {
  const _CoachHero({required this.imageAsset});

  final String imageAsset;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 330,
      height: 350,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 294,
            height: 294,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const RadialGradient(
                colors: [
                  Color(0xFFF3FFF5),
                  Color(0xFFDDEFD7),
                  Color(0x00DDEFD7),
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF9ED59D).withValues(alpha: 0.22),
                  blurRadius: 32,
                  spreadRadius: 6,
                ),
              ],
            ),
          ),
          const Positioned.fill(
            child: CustomPaint(painter: _OrbitWavePainter()),
          ),
          Container(
            width: 286,
            height: 286,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.92),
                width: 3,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFB2D7B0).withValues(alpha: 0.24),
                  blurRadius: 34,
                  spreadRadius: 4,
                ),
              ],
            ),
            child: ClipOval(
              child: Image.asset(
                imageAsset,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    color: const Color(0xFFE4F4E7),
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.support_agent_rounded,
                      color: Color(0xFF149447),
                      size: 72,
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CallControlButton extends StatelessWidget {
  const _CallControlButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: active ? const Color(0xFFE9F8EE) : Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFFE8ECE9)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.035),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Icon(
              icon,
              color: active ? const Color(0xFF149447) : const Color(0xFF222C28),
              size: 28,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF28332F),
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _EndCallButton extends StatelessWidget {
  const _EndCallButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 74,
            height: 74,
            decoration: BoxDecoration(
              color: const Color(0xFFF14135),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFF14135).withValues(alpha: 0.25),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: const Icon(
              Icons.call_end_rounded,
              color: Colors.white,
              size: 34,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'End call',
            style: TextStyle(
              color: Color(0xFF28332F),
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  _WaveformPainter(this.progress, {required this.enabled});

  final double progress;
  final bool enabled;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..color = enabled ? const Color(0xFF76D589) : const Color(0xFFC9D1CC);

    final centerY = size.height / 2;
    final step = size.width / 34;
    for (var i = 0; i < 34; i++) {
      final x = step * i + (step / 2);
      final phase = (progress * math.pi * 2) + (i * 0.42);
      final base = enabled ? 18.0 : 4.0;
      final strength = (math.sin(phase).abs() * base) + (i.isEven ? 5 : 2);
      canvas.drawLine(
        Offset(x, centerY - strength / 2),
        Offset(x, centerY + strength / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.enabled != enabled;
  }
}

class _OrbitWavePainter extends CustomPainter {
  const _OrbitWavePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = const Color(0xFFE4F5E4).withValues(alpha: 0.6);

    for (var i = 0; i < 3; i++) {
      final radius = 112.0 + (i * 26);
      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _OrbitWavePainter oldDelegate) => false;
}
