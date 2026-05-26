import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

import '../protocols/local_protocol_pack.dart';
import 'ai_call_models.dart';
import 'flicko_voice_context_engine.dart';
import 'gemini_health_chat_client.dart';
import 'live_call_foreground_service.dart';

class AiCallWarmupBundle {
  const AiCallWarmupBundle({
    required this.profileContext,
    required this.openingScript,
    required this.createdAt,
  });

  final String profileContext;
  final String openingScript;
  final DateTime createdAt;

  bool isFresh({Duration maxAge = const Duration(seconds: 90)}) {
    return DateTime.now().difference(createdAt) <= maxAge;
  }
}

class AiCallWarmupService {
  AiCallWarmupService._();

  static final AiCallWarmupService instance = AiCallWarmupService._();

  final LocalProtocolPackRepository _protocolRepository =
      const LocalProtocolPackRepository();
  final FlickoVoiceContextEngine _voiceContextEngine =
      const FlickoVoiceContextEngine();
  final GeminiHealthChatClient _chatClient = const GeminiHealthChatClient();

  final Map<String, AiCallWarmupBundle> _cache = <String, AiCallWarmupBundle>{};
  final Map<String, Future<AiCallWarmupBundle>> _inflight =
      <String, Future<AiCallWarmupBundle>>{};

  Future<AiCallWarmupBundle> prepare({
    required String problemName,
    required String profileContext,
    required AiCallInviteReason reason,
    String memoryIntent = '',
    String callPurpose = '',
    bool initiatedByUser = false,
    Future<String> Function()? onLoadBackendContext,
  }) {
    final normalizedProblem = problemName.trim().toLowerCase();
    final normalizedProfile = profileContext.trim();
    final key = [
      normalizedProblem,
      reason.payloadKey,
      memoryIntent.trim(),
      callPurpose.trim(),
      initiatedByUser ? 'user-started' : 'flicko-started',
      normalizedProfile.hashCode,
    ].join('|');

    final cached = _cache.remove(key);
    if (cached != null && cached.isFresh()) {
      return Future<AiCallWarmupBundle>.value(cached);
    }

    final running = _inflight[key];
    if (running != null) {
      return running;
    }

    final future = _buildBundle(
      problemName: problemName,
      profileContext: profileContext,
      reason: reason,
      memoryIntent: memoryIntent,
      callPurpose: callPurpose,
      initiatedByUser: initiatedByUser,
      onLoadBackendContext: onLoadBackendContext,
    );
    _inflight[key] = future;
    future
        .then((bundle) {
          _cache[key] = bundle;
          _inflight.remove(key);
        })
        .catchError((_) {
          _inflight.remove(key);
        });
    return future;
  }

  Future<AiCallWarmupBundle> _buildBundle({
    required String problemName,
    required String profileContext,
    required AiCallInviteReason reason,
    required String memoryIntent,
    required String callPurpose,
    required bool initiatedByUser,
    Future<String> Function()? onLoadBackendContext,
  }) async {
    var localProtocolContext = '';
    try {
      final context = await _protocolRepository
          .contextFor(
            problemName: problemName,
            profileContext: profileContext,
            userText: memoryIntent.trim().isEmpty
                ? 'voice call opening and immediate follow-up'
                : memoryIntent,
          )
          .timeout(const Duration(milliseconds: 1200));
      localProtocolContext = context.toPromptText().trim();
    } catch (_) {
      localProtocolContext = '';
    }

    var backendContext = '';
    if (onLoadBackendContext != null) {
      try {
        backendContext = await onLoadBackendContext().timeout(
          const Duration(milliseconds: 1400),
        );
      } catch (_) {
        backendContext = '';
      }
    }

    final warmProfileContext = await _voiceContextEngine.buildContext(
      problemName: problemName,
      profileContext: profileContext,
      protocolContext: localProtocolContext,
      backendContext: backendContext.trim(),
    );
    final callPurposeLabel = _callPurposeLabel(
      problemName: problemName,
      reason: reason,
      callPurpose: callPurpose,
      voiceContext: warmProfileContext,
    );
    final enrichedProfileContext = <String>[
      warmProfileContext.trim(),
      'Call initiation source: ${initiatedByUser ? 'user_started' : 'flicko_started'}',
      'Call reason label: ${reason.title}',
      'Call purpose/work name: $callPurposeLabel',
    ].where((line) => line.trim().isNotEmpty).join('\n');

    final fallbackOpening = _fallbackOpening(
      problemName: problemName,
      reason: reason,
      voiceContext: enrichedProfileContext,
      callPurpose: callPurposeLabel,
      initiatedByUser: initiatedByUser,
    );

    var openingScript = fallbackOpening;
    final recentOpeningHistory = _contextValue(
      enrichedProfileContext,
      'Recent AI call openings to avoid',
    );
    try {
      final generated = await _chatClient
          .generateCallOpening(
            firstName: _preferredSpeechName(enrichedProfileContext),
            problemName: problemName,
            voiceContext: enrichedProfileContext,
            callReasonLabel: reason.title,
            callPurpose: callPurposeLabel,
            initiatedByUser: initiatedByUser,
            openingStyleHint: _openingStyleHint(
              _contextValue(enrichedProfileContext, 'Dynamic greeting seed'),
              reason,
            ),
            recentOpeningHistory: recentOpeningHistory,
            fallbackOpening: fallbackOpening,
          )
          .timeout(const Duration(milliseconds: 2200));
      final cleanGenerated = generated.trim();
      if (cleanGenerated.isNotEmpty &&
          !_hasBannedUserStartedCliche(cleanGenerated) &&
          !_soundsRepeated(cleanGenerated, _avoidLines(recentOpeningHistory))) {
        openingScript = cleanGenerated;
      }
    } catch (_) {
      openingScript = fallbackOpening;
    }

    return AiCallWarmupBundle(
      profileContext: enrichedProfileContext,
      openingScript: openingScript,
      createdAt: DateTime.now(),
    );
  }

  String _fallbackOpening({
    required String problemName,
    required AiCallInviteReason reason,
    required String voiceContext,
    required String callPurpose,
    required bool initiatedByUser,
  }) {
    final userName = _preferredSpeechName(voiceContext);
    final safeName = userName.isEmpty ? '' : '$userName, ';
    final reminderHint = _contextValue(
      voiceContext,
      'Scheduled daily reminders',
    );
    final recentChat = _contextValue(voiceContext, 'Recent chat conversation');
    final recentOpenings = _contextValue(
      voiceContext,
      'Recent AI call openings to avoid',
    );
    final intakeComplete = voiceContext.toLowerCase().contains(
      'intake status: complete',
    );
    final recentCallMemory = _contextValue(
      voiceContext,
      'Saved AI call memory',
    );
    final openingStyle = _openingStyleHint(
      _contextValue(voiceContext, 'Dynamic greeting seed'),
      reason,
    );
    final openingSeed = _contextValue(voiceContext, 'Dynamic greeting seed');
    final avoided = _avoidLines(recentOpenings);

    if (initiatedByUser) {
      return _pickFreshOpening(
        _userStartedTemplates(
          problemName: problemName,
          reason: reason,
          userName: userName,
          style: openingStyle,
        ),
        avoided,
        seed: openingSeed,
      );
    }

    switch (reason) {
      case AiCallInviteReason.setupIntake:
        return _pickFreshOpening(
          <String>[
            '${safeName}main aapke $problemName setup ke kaam se call kar rahi hoon. ${_firstIntakeQuestion(problemName)}',
            '${_directCareLead(problemName)} ${_firstIntakeQuestion(problemName)}',
            'Chaliye aaj $problemName ko proper samajhne ke liye setup shuru karte hain. ${_firstIntakeQuestion(problemName)}',
            '$problemName ke liye focused health intake yahin se start karte hain. ${_firstIntakeQuestion(problemName)}',
          ],
          avoided,
          seed: openingSeed,
        );
      case AiCallInviteReason.dailyRoutine:
      case AiCallInviteReason.notification:
        final hasReminder = reminderHint.isNotEmpty;
        final hasContinuity =
            intakeComplete ||
            recentChat.isNotEmpty ||
            recentCallMemory.isNotEmpty;
        return _pickFreshOpening(
          _dailyRoutineTemplates(
            style: openingStyle,
            safeName: safeName,
            hasReminder: hasReminder,
            hasContinuity: hasContinuity,
            callPurpose: callPurpose,
          ),
          avoided,
          seed: openingSeed,
        );
      case AiCallInviteReason.missedMealPhoto:
        return _pickFreshOpening(
          <String>[
            '${safeName}main meal photo follow-up ke kaam se call kar rahi hoon. Meal photo miss hone ki asli wajah kya rahi?',
            '${safeName}aaj meal update wahi se pick karte hain jahan break hua tha. Meal photo miss hone ki asli wajah kya rahi?',
            '${safeName}aaj khane ke update par thoda sa catch-up karte hain. Meal photo reh gaya tha, sabse bada block kya aaya?',
            '${safeName}main aaj aapke meal follow-up ke liye phir se aayi hoon. Photo na bhejne ki sabse practical wajah kya thi?',
          ],
          avoided,
          seed: openingSeed,
        );
      case AiCallInviteReason.missedCareTask:
        return _pickFreshOpening(
          <String>[
            '${safeName}main "$callPurpose" task ke follow-up ke liye call kar rahi hoon. Isme sabse bada block kya aaya?',
            '${safeName}jo care task reh gaya tha usi par aaj seedha follow-up karte hain. Sabse badi dikkat kya aayi thi?',
            '${safeName}aaj us pending task ka real block samajhna hai. Kis wajah se task beech me reh gaya?',
            '${safeName}main pichhle task update ko yaad rakh kar call kar rahi hoon. Actual problem kya aayi thi jiski wajah se task miss hua?',
          ],
          avoided,
          seed: openingSeed,
        );
    }
  }

  List<String> _dailyRoutineTemplates({
    required String style,
    required String safeName,
    required bool hasReminder,
    required bool hasContinuity,
    required String callPurpose,
  }) {
    final friendlyLead = safeName.isEmpty ? '' : safeName;
    if (hasReminder) {
      return <String>[
        '${friendlyLead}aapke reminder time par ek short check-in kar leti hoon. Aaj routine follow hua ya kahin break aaya?',
        '${friendlyLead}reminder follow-up ke liye call hai. Aaj plan, medicine, meal, ya sleep me sabse important update kya hai?',
        '$friendlyLead$callPurpose ka quick review le leti hoon. Reminder ka response kaisa raha aur koi nayi problem hui?',
        '${friendlyLead}aaj ke reminder ko yahin se close karte hain. Kya kaam complete hua ya koi practical dikkat aayi?',
      ];
    }
    switch (style) {
      case 'memory-led':
        return <String>[
          '${friendlyLead}pichhli baat yaad rakh kar aaj phir se aapka din check karne aayi hoon. Reminder, plan, ya health me sabse badi update kya rahi?',
          '${friendlyLead}jo plan humne pehle set kiya tha usi ka aaj follow-up le leti hoon. Kya theek chala aur kahaan dikkat aayi?',
        ];
      case 'friendly-led':
        return <String>[
          '${friendlyLead}main $callPurpose ke liye aayi hoon. Reminder aur routine theek chale ya kahin break hua?',
          '${friendlyLead}chaliye aaj phir se thoda sa saath me check karte hain. Aaj plan, reminder, ya health me sabse pehli dikkat kya lagi?',
        ];
      case 'progress-led':
        return <String>[
          '${friendlyLead}aaj dekhte hain plan me progress kaisi rahi. Routine, reminder, ya symptom side par sabse important update kya hai?',
          '${friendlyLead}aaj ka quick progress review le leti hoon. Kis cheez me improvement raha aur kis jagah atak gaye?',
        ];
      case 'support-led':
        return <String>[
          '${friendlyLead}main aaj aapka halka sa support check lene aayi hoon. Koi cheez plan ke mutabik nahi chali ya nayi problem hui?',
          '${friendlyLead}aaj bas calmly dekhte hain din ka flow kaisa raha. Reminder, meal, medicine, ya sleep me kahaan help chahiye?',
        ];
      case 'reminder-led':
        return <String>[
          '${friendlyLead}aaj ka care check-in lene aayi hoon. Routine aur health side par sabse pehli update kya hai?',
          '${friendlyLead}aaj din ka quick follow-up karte hain. Reminder, task, ya symptom me sabse bada change kya raha?',
        ];
      default:
        return <String>[
          if (hasReminder)
            '${friendlyLead}main aaj aapke reminder time ke around $callPurpose lene aayi hoon. Aaj plan aur health side par sab kaisa raha?'
          else if (hasContinuity)
            '${friendlyLead}pichhli baat se aaj ka follow-up yahin se continue karte hain. Aaj sabse pehle kya update dena chahenge?'
          else
            '${friendlyLead}aaj ka quick health follow-up karte hain. Reminder, routine, ya symptoms me sabse badi baat kya rahi?',
          '${friendlyLead}aaj phir se aapka short care check le leti hoon. Kya theek chala aur kya miss ho gaya?',
        ];
    }
  }

  List<String> _userStartedTemplates({
    required String problemName,
    required AiCallInviteReason reason,
    required String userName,
    required String style,
  }) {
    final cleanName = userName.trim();
    final nameLead = cleanName.isEmpty ? '' : '$cleanName, ';
    final friendlyLead = cleanName.isEmpty ? 'Haan,' : 'Haan $cleanName,';
    final directLead = cleanName.isEmpty ? 'Boliye,' : '$cleanName, boliye,';
    final calmLead = cleanName.isEmpty
        ? 'Main sun rahi hoon.'
        : '$cleanName, main sun rahi hoon.';
    switch (reason) {
      case AiCallInviteReason.setupIntake:
        return <String>[
          '$friendlyLead call open ho gayi. $problemName setup yahin se start karte hain. ${_firstIntakeQuestion(problemName)}',
          '$directLead $problemName ke liye sabse pehle ye bataiye: ${_firstIntakeQuestion(problemName)}',
          '$calmLead $problemName setup me aaj pehla useful step lete hain. ${_firstIntakeQuestion(problemName)}',
          '${nameLead}chaliye seedha $problemName par focus karte hain. ${_firstIntakeQuestion(problemName)}',
        ];
      case AiCallInviteReason.dailyRoutine:
      case AiCallInviteReason.notification:
        return _userStartedDailyTemplates(
          problemName: problemName,
          nameLead: nameLead,
          friendlyLead: friendlyLead,
          directLead: directLead,
          calmLead: calmLead,
          style: style,
        );
      case AiCallInviteReason.missedMealPhoto:
        return <String>[
          '$friendlyLead meal update sun leti hoon. Kya khaya tha ya photo miss hone mein kya dikkat aayi?',
          '$directLead meal photo wali baat clear karte hain. Sabse pehle kya update dena chahenge?',
          '$calmLead jo meal update reh gaya tha, use abhi simple tareeke se note karte hain. Sabse pehle kya hua?',
          '${nameLead}aaj meal follow-up yahin se continue karte hain. Photo miss hone ki real wajah kya thi?',
        ];
      case AiCallInviteReason.missedCareTask:
        return <String>[
          '$friendlyLead pending task ka update le leti hoon. Sabse pehla block kya aaya?',
          '$calmLead care task mein kis jagah help chahiye?',
          '$directLead jo task ruk gaya tha, usme actual difficulty kya aayi?',
          '${nameLead}task recovery ko simple rakhte hain. Abhi sabse realistic next step kya ho sakta hai?',
        ];
    }
  }

  List<String> _userStartedDailyTemplates({
    required String problemName,
    required String nameLead,
    required String friendlyLead,
    required String directLead,
    required String calmLead,
    required String style,
  }) {
    final templates = <String>[
      '$friendlyLead call connect ho gayi. $problemName me abhi routine, reminder, ya kisi new problem me help chahiye?',
      '$calmLead Aaj $problemName plan me sabse pehle kis cheez par baat karni hai?',
      '$directLead $problemName ke liye abhi kya help chahiye - routine, symptoms, meal, ya reminder?',
      '${nameLead}chaliye current update se start karte hain. Aaj $problemName side par kya change hua?',
      '${nameLead}main yahin hoon. Aaj plan follow hua ya kahin break aaya?',
      '${nameLead}aaj ka health update short me bata dijiye. Sabse pehle kis cheez me support chahiye?',
      '${nameLead}theek hai, $problemName par focus karte hain. Abhi sabse urgent ya important baat kya hai?',
      '${nameLead}routine ka quick check le leti hoon. Aaj reminder, meal, medicine, ya sleep me kya hua?',
      '${nameLead}aapne call kholi hai, to seedha aapki need se start karte hain. Kis point par help chahiye?',
      '${nameLead}aaj ka follow-up fresh rakhte hain. Pehli update kya dena chahenge?',
    ];
    if (style == 'progress-led') {
      return <String>[templates[3], templates[4], templates[7], ...templates];
    }
    if (style == 'support-led') {
      return <String>[templates[1], templates[5], templates[6], ...templates];
    }
    if (style == 'memory-led') {
      return <String>[templates[4], templates[3], templates[9], ...templates];
    }
    if (style == 'friendly-led') {
      return <String>[templates[0], templates[8], templates[9], ...templates];
    }
    return templates;
  }

  String _callPurposeLabel({
    required String problemName,
    required AiCallInviteReason reason,
    required String callPurpose,
    required String voiceContext,
  }) {
    final cleanPurpose = _compactPurpose(callPurpose);
    switch (reason) {
      case AiCallInviteReason.setupIntake:
        return '$problemName health setup';
      case AiCallInviteReason.dailyRoutine:
        final reminderHint = _contextValue(
          voiceContext,
          'Scheduled daily reminders',
        );
        if (reminderHint.trim().isNotEmpty) {
          return 'daily reminder check-in';
        }
        return 'daily routine check-in';
      case AiCallInviteReason.missedMealPhoto:
        return 'meal photo follow-up';
      case AiCallInviteReason.missedCareTask:
        return cleanPurpose.isEmpty ? 'pending care task' : cleanPurpose;
      case AiCallInviteReason.notification:
        return cleanPurpose.isEmpty ? 'health reminder call' : cleanPurpose;
    }
  }

  String _compactPurpose(String value) {
    final clean = value
        .replaceAll(RegExp(r'[\r\n\t]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (clean.length <= 56) {
      return clean;
    }
    return clean.substring(0, 56).trimRight();
  }

  String _openingStyleHint(String seed, AiCallInviteReason reason) {
    final List<String> styles;
    switch (reason) {
      case AiCallInviteReason.setupIntake:
        styles = const <String>[
          'direct-care-led',
          'focused-intake-led',
          'condition-led',
        ];
      case AiCallInviteReason.dailyRoutine:
      case AiCallInviteReason.notification:
        styles = const <String>[
          'friendly-led',
          'memory-led',
          'reminder-led',
          'progress-led',
          'support-led',
        ];
      case AiCallInviteReason.missedMealPhoto:
      case AiCallInviteReason.missedCareTask:
        styles = const <String>['memory-led', 'support-led', 'friendly-led'];
    }
    final source = seed.trim().isEmpty
        ? DateTime.now().microsecondsSinceEpoch.toString()
        : seed.trim();
    var hash = 0;
    for (final unit in source.codeUnits) {
      hash = (hash * 31 + unit) & 0x3fffffff;
    }
    return styles[hash % styles.length];
  }

  List<String> _avoidLines(String value) {
    return value
        .split('|')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
  }

  String _pickFreshOpening(
    List<String> candidates,
    List<String> avoided, {
    String seed = '',
  }) {
    final orderedCandidates = _rotateCandidates(candidates, seed);
    for (final candidate in orderedCandidates) {
      if (!_soundsRepeated(candidate, avoided)) {
        return candidate;
      }
    }
    return orderedCandidates.first;
  }

  List<String> _rotateCandidates(List<String> candidates, String seed) {
    if (candidates.length < 2 || seed.trim().isEmpty) {
      return candidates;
    }
    var hash = 0;
    for (final unit in seed.codeUnits) {
      hash = (hash * 37 + unit) & 0x3fffffff;
    }
    final start = hash % candidates.length;
    return <String>[...candidates.skip(start), ...candidates.take(start)];
  }

  bool _soundsRepeated(String candidate, List<String> avoided) {
    if (_hasBannedUserStartedCliche(candidate)) {
      return true;
    }
    final normalizedCandidate = _normalizeOpening(candidate);
    for (final line in avoided) {
      final normalizedAvoided = _normalizeOpening(line);
      if (normalizedAvoided.isEmpty) {
        continue;
      }
      if (normalizedCandidate == normalizedAvoided) {
        return true;
      }
      if (normalizedCandidate.startsWith(normalizedAvoided) ||
          normalizedAvoided.startsWith(normalizedCandidate)) {
        return true;
      }
    }
    return false;
  }

  bool _hasBannedUserStartedCliche(String value) {
    final clean = value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\u0900-\u097F ]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return clean.contains('aaj mujhe yaad kiya') ||
        clean.contains('mujhe yaad kiya') ||
        clean.contains('आज मुझे याद किया') ||
        clean.contains('मुझे याद किया');
  }

  String _normalizeOpening(String value) {
    final firstSentence = value
        .split(RegExp(r'[.!?]'))
        .first
        .replaceAll(RegExp(r'[^a-zA-Z0-9\u0900-\u097F ]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .toLowerCase();
    if (firstSentence.isEmpty) {
      return '';
    }
    final words = firstSentence.split(' ');
    return words.take(words.length < 9 ? words.length : 9).join(' ');
  }

  String _directCareLead(String problemName) {
    final normalized = problemName.trim();
    if (normalized.isEmpty) {
      return 'Main aapki health setup call shuru kar rahi hoon.';
    }
    return 'Main $normalized ko samajhne ke liye aapki health setup call shuru kar rahi hoon.';
  }

  String _firstIntakeQuestion(String problemName) {
    final normalizedProblem = problemName.toLowerCase();
    if (normalizedProblem.contains('diabetes')) {
      return 'Sabse pehle bataiye aaj kal fasting ya khane ke baad sugar reading kitni aa rahi hai?';
    }
    if (normalizedProblem.contains('blood pressure') ||
        normalizedProblem.contains('heart')) {
      return 'Sabse pehle bataiye recent BP reading ya heart symptom abhi kya chal raha hai?';
    }
    if (normalizedProblem.contains('weight')) {
      return 'Sabse pehle bataiye abhi weight concern me sabse badi dikkat kya hai?';
    }
    if (normalizedProblem.contains('thyroid')) {
      return 'Sabse pehle bataiye thyroid ki medicine kis time le rahe hain aur abhi sabse bada symptom kya hai?';
    }
    if (normalizedProblem.contains('sleep')) {
      return 'Sabse pehle bataiye neend me sone ki dikkat zyada hai ya beech me uthna?';
    }
    if (normalizedProblem.contains('stress') ||
        normalizedProblem.contains('mood')) {
      return 'Sabse pehle bataiye stress ya mood me abhi sabse badi dikkat kya chal rahi hai?';
    }
    return 'Sabse pehle bataiye abhi sabse badi health dikkat kya hai aur ye kab se chal rahi hai?';
  }

  String _contextValue(String context, String label) {
    final prefix = '$label:';
    for (final rawLine in context.split('\n')) {
      final line = rawLine.trim();
      if (line.toLowerCase().startsWith(prefix.toLowerCase())) {
        return line.substring(prefix.length).trim();
      }
    }
    return '';
  }

  String _preferredSpeechName(String context) {
    for (final label in const <String>[
      'User name for speech',
      'User first name',
      'First name',
      'User name',
      'Name',
    ]) {
      final value = _contextValue(context, label);
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
}

@visibleForTesting
String buildFallbackAiCallOpening({
  required String problemName,
  required AiCallInviteReason reason,
  required String voiceContext,
  String callPurpose = '',
  bool initiatedByUser = false,
}) {
  return AiCallWarmupService.instance._fallbackOpening(
    problemName: problemName,
    reason: reason,
    voiceContext: voiceContext,
    callPurpose: callPurpose.isEmpty ? reason.title : callPurpose,
    initiatedByUser: initiatedByUser,
  );
}

Future<bool> prestartWarmLiveCall({
  required LiveCallForegroundService foregroundService,
  required AiCallWarmupBundle warmup,
  required String apiKey,
  required String model,
  required String voiceName,
  required String problemName,
  String title = 'Call in progress',
  String subtitle = '',
  String baseUri = '',
}) async {
  try {
    final microphoneStatus = await Permission.microphone.status;
    if (!microphoneStatus.isGranted) {
      debugPrint(
        'Flicko live call prestart skipped: microphone permission is not granted yet.',
      );
      return false;
    }
  } catch (error) {
    debugPrint('Flicko live call prestart skipped: $error');
    return false;
  }

  try {
    return await foregroundService.start(
      title: title,
      subtitle: subtitle,
      apiKey: apiKey,
      model: model,
      voiceName: voiceName,
      problemName: problemName,
      profileContext: warmup.profileContext,
      openingScript: warmup.openingScript,
      deferFirstPlayback: true,
      baseUri: baseUri,
    );
  } catch (error) {
    debugPrint('Flicko live call prestart failed: $error');
    return false;
  }
}
