enum FlickoSafetySeverity {
  clinician,
  urgent,
  emergency;

  String get label => switch (this) {
    FlickoSafetySeverity.clinician => 'Clinician review',
    FlickoSafetySeverity.urgent => 'Urgent care',
    FlickoSafetySeverity.emergency => 'Emergency',
  };

  int get rank => switch (this) {
    FlickoSafetySeverity.clinician => 1,
    FlickoSafetySeverity.urgent => 2,
    FlickoSafetySeverity.emergency => 3,
  };
}

class FlickoSafetyEvent {
  const FlickoSafetyEvent({
    required this.id,
    required this.problemName,
    required this.source,
    required this.severity,
    required this.ruleId,
    required this.title,
    required this.matchedText,
    required this.action,
    required this.createdAt,
  });

  final String id;
  final String problemName;
  final String source;
  final FlickoSafetySeverity severity;
  final String ruleId;
  final String title;
  final String matchedText;
  final String action;
  final DateTime createdAt;

  bool get mustStopNormalCoaching =>
      severity == FlickoSafetySeverity.urgent ||
      severity == FlickoSafetySeverity.emergency;

  String get coachMessage {
    final prefix = severity == FlickoSafetySeverity.emergency
        ? 'This may be an emergency.'
        : 'This may need urgent medical care.';
    return '$prefix $action\n\nMatched safety flag: $title.';
  }

  String get compactSummary {
    return '${severity.label}: $title - $action';
  }

  Map<String, Object> toJson() {
    return {
      'id': id,
      'problemName': problemName,
      'source': source,
      'severity': severity.name,
      'ruleId': ruleId,
      'title': title,
      'matchedText': matchedText,
      'action': action,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory FlickoSafetyEvent.fromJson(Map<String, dynamic> json) {
    final severityName = json['severity']?.toString() ?? '';
    final severity = FlickoSafetySeverity.values.firstWhere(
      (entry) => entry.name == severityName,
      orElse: () => FlickoSafetySeverity.clinician,
    );
    return FlickoSafetyEvent(
      id: _string(json['id'], fallback: DateTime.now().toIso8601String()),
      problemName: _string(json['problemName']),
      source: _string(json['source'], fallback: 'local'),
      severity: severity,
      ruleId: _string(json['ruleId']),
      title: _string(json['title'], fallback: severity.label),
      matchedText: _string(json['matchedText']),
      action: _string(
        json['action'],
        fallback: 'Please contact a licensed clinician.',
      ),
      createdAt:
          DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.now(),
    );
  }

  static FlickoSafetyEvent create({
    required String problemName,
    required String source,
    required FlickoSafetySeverity severity,
    required String ruleId,
    required String title,
    required String matchedText,
    required String action,
  }) {
    final now = DateTime.now();
    return FlickoSafetyEvent(
      id: '${now.microsecondsSinceEpoch}-$ruleId',
      problemName: problemName.trim(),
      source: source.trim().isEmpty ? 'local' : source.trim(),
      severity: severity,
      ruleId: ruleId.trim(),
      title: title.trim(),
      matchedText: matchedText.trim(),
      action: action.trim(),
      createdAt: now,
    );
  }
}

typedef FlickoSafetyEventWriter =
    Future<bool> Function(FlickoSafetyEvent event);

class FlickoSafetyEngine {
  const FlickoSafetyEngine._();

  static FlickoSafetyEvent? evaluate({
    required String text,
    required String problemName,
    String source = 'chat',
  }) {
    final cleanText = text.trim();
    final normalized = _normalize(cleanText);
    if (normalized.isEmpty) {
      return null;
    }

    final numeric = _numericRule(
      normalized,
      cleanText,
      problemName: problemName,
      source: source,
    );
    final heuristic = _heuristicRule(
      normalized,
      cleanText,
      problemName: problemName,
      source: source,
    );
    final phraseMatch = _phraseRule(
      normalized,
      cleanText,
      problemName: problemName,
      source: source,
    );
    return _strongestEvent([numeric, heuristic, phraseMatch]);
  }

  static FlickoSafetyEvent? _strongestEvent(List<FlickoSafetyEvent?> events) {
    FlickoSafetyEvent? best;
    for (final event in events.whereType<FlickoSafetyEvent>()) {
      if (best == null || event.severity.rank > best.severity.rank) {
        best = event;
      }
    }
    return best;
  }

  static FlickoSafetyEvent? _heuristicRule(
    String normalized,
    String original, {
    required String problemName,
    required String source,
  }) {
    if (_hasChestPainPattern(normalized)) {
      return _event(
        problemName: problemName,
        source: source,
        severity: FlickoSafetySeverity.emergency,
        ruleId: 'chest-pain',
        title: 'Chest pain or heart-attack warning',
        matchedText: original,
        action:
            'Please seek emergency medical care now. Do not wait for AI coaching if chest pain, pressure, sweating, breathlessness, fainting, jaw pain, or left-arm pain is present.',
      );
    }
    if (_hasEmergencyContactCallIntent(normalized)) {
      return _event(
        problemName: problemName,
        source: source,
        severity: FlickoSafetySeverity.emergency,
        ruleId: 'emergency-contact-request',
        title: 'Emergency contact call requested',
        matchedText: original,
        action:
            'The user requested emergency contact support. Open the saved emergency contact call immediately if available, otherwise use local emergency services.',
      );
    }
    return null;
  }

  static FlickoSafetyEvent? _numericRule(
    String normalized,
    String original, {
    required String problemName,
    required String source,
  }) {
    final bp = RegExp(
      r'\b([1-2]\d{2})\s*/\s*(\d{2,3})\b',
    ).firstMatch(normalized);
    if (bp != null) {
      final systolic = int.tryParse(bp.group(1) ?? '') ?? 0;
      final diastolic = int.tryParse(bp.group(2) ?? '') ?? 0;
      if (systolic >= 180 || diastolic >= 120) {
        return _event(
          problemName: problemName,
          source: source,
          severity: FlickoSafetySeverity.emergency,
          ruleId: 'bp-crisis',
          title: 'Very high blood pressure reading',
          matchedText: bp.group(0) ?? original,
          action:
              'A reading around $systolic/$diastolic can be dangerous. Seek emergency medical help now, especially with chest pain, breathlessness, weakness, confusion, or severe headache.',
        );
      }
      if ((systolic >= 160 || diastolic >= 100) &&
          _hasAny(normalized, const [
            'severe headache',
            'chest pain',
            'breathless',
            'shortness of breath',
            'weakness',
            'confusion',
          ])) {
        return _event(
          problemName: problemName,
          source: source,
          severity: FlickoSafetySeverity.urgent,
          ruleId: 'bp-high-symptoms',
          title: 'High BP with concerning symptoms',
          matchedText: bp.group(0) ?? original,
          action:
              'Please arrange urgent medical review now because high BP with these symptoms can be unsafe.',
        );
      }
    }

    final sugarContext = _hasAny(normalized, const [
      'sugar',
      'glucose',
      'diabetes',
      'mg dl',
      'mg/dl',
    ]);
    if (sugarContext) {
      for (final match in RegExp(r'\b(\d{2,3})\b').allMatches(normalized)) {
        final value = int.tryParse(match.group(1) ?? '') ?? 0;
        if (value > 0 && value <= 54) {
          return _event(
            problemName: problemName,
            source: source,
            severity: FlickoSafetySeverity.urgent,
            ruleId: 'glucose-low',
            title: 'Very low glucose reading',
            matchedText: match.group(0) ?? '$value',
            action:
                'Low sugar around $value can become dangerous. Follow your clinician-given hypo plan and get urgent help if confused, fainting, unable to swallow, or not improving.',
          );
        }
        if (value >= 300) {
          return _event(
            problemName: problemName,
            source: source,
            severity: FlickoSafetySeverity.urgent,
            ruleId: 'glucose-high',
            title: 'Very high glucose reading',
            matchedText: match.group(0) ?? '$value',
            action:
                'High sugar around $value needs urgent medical advice, especially with vomiting, abdominal pain, deep breathing, dehydration, confusion, or ketones.',
          );
        }
      }
    }
    return null;
  }

  static FlickoSafetyEvent? _phraseRule(
    String normalized,
    String original, {
    required String problemName,
    required String source,
  }) {
    _SafetyRuleMatch? best;
    for (final rule in _rules) {
      if (!rule.appliesTo(problemName)) {
        continue;
      }
      final phrase = rule.matchPhrase(normalized);
      if (phrase == null) {
        continue;
      }
      final candidate = _SafetyRuleMatch(rule: rule, phrase: phrase);
      if (best == null || candidate.rank > best.rank) {
        best = candidate;
      }
    }
    if (best == null) {
      return null;
    }
    return _event(
      problemName: problemName,
      source: source,
      severity: best.rule.severity,
      ruleId: best.rule.ruleId,
      title: best.rule.title,
      matchedText: best.phrase.isEmpty ? original : best.phrase,
      action: best.rule.action,
    );
  }

  static FlickoSafetyEvent _event({
    required String problemName,
    required String source,
    required FlickoSafetySeverity severity,
    required String ruleId,
    required String title,
    required String matchedText,
    required String action,
  }) {
    return FlickoSafetyEvent.create(
      problemName: problemName,
      source: source,
      severity: severity,
      ruleId: ruleId,
      title: title,
      matchedText: matchedText,
      action: action,
    );
  }
}

class _SafetyRule {
  const _SafetyRule({
    required this.ruleId,
    required this.severity,
    required this.title,
    required this.phrases,
    required this.action,
    this.problemHints = const <String>[],
  });

  final String ruleId;
  final FlickoSafetySeverity severity;
  final String title;
  final List<String> phrases;
  final String action;
  final List<String> problemHints;

  bool appliesTo(String problemName) {
    if (problemHints.isEmpty) {
      return true;
    }
    final normalizedProblem = _normalize(problemName);
    return problemHints.any((hint) => normalizedProblem.contains(hint));
  }

  String? matchPhrase(String normalizedText) {
    for (final phrase in phrases) {
      final normalizedPhrase = _normalize(phrase);
      if (normalizedPhrase.isNotEmpty &&
          normalizedText.contains(normalizedPhrase)) {
        return phrase;
      }
    }
    return null;
  }
}

class _SafetyRuleMatch {
  const _SafetyRuleMatch({required this.rule, required this.phrase});

  final _SafetyRule rule;
  final String phrase;

  int get rank => rule.severity.rank * 100 + phrase.length;
}

const _rules = <_SafetyRule>[
  _SafetyRule(
    ruleId: 'chest-pain',
    severity: FlickoSafetySeverity.emergency,
    title: 'Chest pain or heart-attack warning',
    phrases: [
      'chest pain',
      'chest pressure',
      'pain in chest',
      'chest me pain',
      'chest mein pain',
      'chest mai pain',
      'mere chest me pain',
      'mere chest mein pain',
      'meri chest me pain',
      'chaise me pain',
      'mere chaise me pain',
      'mere chais me pain',
      'chais me pain',
      'seene me dard',
      'seene mein dard',
      'mere seene me dard',
      'mere seene mein dard',
      'seene me pain',
      'seene mein pain',
      'chhati me dard',
      'chaati me dard',
      'chati me dard',
      'chhati me pain',
      'chaati me pain',
      'chati me pain',
      'dil me dard',
      'heart me pain',
      'heart pain',
      'my heart pain',
      'pain in my heart',
      'critical heart pain',
      'heart attack',
      'left arm pain',
      'jaw pain with chest',
      'chest tightness',
    ],
    action:
        'Please seek emergency medical care now. Do not wait for AI coaching if chest pain, pressure, sweating, breathlessness, fainting, jaw pain, or left-arm pain is present.',
  ),
  _SafetyRule(
    ruleId: 'emergency-contact-request',
    severity: FlickoSafetySeverity.emergency,
    title: 'Emergency contact call requested',
    phrases: [
      'call my emergency contact',
      'call emergency contact',
      'connect my emergency contact',
      'connect emergency contact',
      'conect emergency contact',
      'call my emergency number',
      'call emergency number',
      'connect emergency number',
      'conect emergency number',
      'emergency contact ko call',
      'emergency number ko call',
      'mere emergency contact ko call',
      'meri emergency contact ko call',
      'mera emergency contact call',
      'call emency contact',
      'call emenrge contact',
      'call emergecy contact',
      'call emnrgecy contact',
      'critical call emergency',
      'critical emergency call',
      'connect my emergency call',
      'connect the my emergency call',
      'connect my emenrge call',
      'connect my emency call',
      'emergecy call',
      'emency call',
      'emenrgecy call',
      'emergency call connect',
    ],
    action:
        'The user requested emergency contact support. Open the saved emergency contact call immediately if available, otherwise use local emergency services.',
  ),
  _SafetyRule(
    ruleId: 'stroke-signs',
    severity: FlickoSafetySeverity.emergency,
    title: 'Stroke warning signs',
    phrases: [
      'face droop',
      'slurred speech',
      'one side weakness',
      'sudden weakness',
      'sudden numbness',
      'cannot move one side',
      'stroke symptoms',
    ],
    action:
        'Please seek emergency medical care now. Stroke warning signs are time-sensitive.',
  ),
  _SafetyRule(
    ruleId: 'breathing-danger',
    severity: FlickoSafetySeverity.emergency,
    title: 'Severe breathing trouble',
    phrases: [
      'cannot breathe',
      'cant breathe',
      "can't breathe",
      'severe breathing problem',
      'blue lips',
      'choking',
      'gasping for air',
    ],
    action:
        'Please get emergency help now if breathing is severe, worsening, or associated with blue lips, chest pain, confusion, or fainting.',
  ),
  _SafetyRule(
    ruleId: 'self-harm',
    severity: FlickoSafetySeverity.emergency,
    title: 'Self-harm or suicide risk',
    phrases: [
      'kill myself',
      'suicide',
      'end my life',
      'harm myself',
      'hurt myself',
      'dont want to live',
      "don't want to live",
    ],
    action:
        'Please contact local emergency support or a trusted person now. If you may act on these thoughts, seek emergency help immediately.',
  ),
  _SafetyRule(
    ruleId: 'severe-allergy',
    severity: FlickoSafetySeverity.emergency,
    title: 'Severe allergic reaction',
    phrases: [
      'throat swelling',
      'swollen lips',
      'tongue swelling',
      'anaphylaxis',
      'allergic reaction cannot breathe',
      'hives with breathing',
    ],
    action:
        'This can be an emergency. Use your prescribed emergency plan if you have one and seek urgent emergency care now.',
  ),
  _SafetyRule(
    ruleId: 'pregnancy-danger',
    severity: FlickoSafetySeverity.emergency,
    title: 'Pregnancy danger sign',
    phrases: [
      'heavy bleeding',
      'baby not moving',
      'severe abdominal pain',
      'pregnancy bleeding',
      'seizure pregnancy',
      'water broke early',
    ],
    action:
        'Please seek urgent obstetric or emergency care now. Pregnancy danger signs need clinician assessment.',
    problemHints: ['pregnancy', 'postpartum', 'preconception', 'women'],
  ),
  _SafetyRule(
    ruleId: 'sexual-assault',
    severity: FlickoSafetySeverity.urgent,
    title: 'Sexual assault or non-consensual contact',
    phrases: [
      'sexual assault',
      'rape',
      'forced sex',
      'non consensual',
      'without consent',
    ],
    action:
        'Please seek urgent medical and safety support. A clinician can help with injury care, STI prevention, emergency contraception where relevant, and evidence options.',
    problemHints: ['sexual'],
  ),
  _SafetyRule(
    ruleId: 'sexual-health-urgent',
    severity: FlickoSafetySeverity.urgent,
    title: 'Urgent sexual-health symptom',
    phrases: [
      'severe testicle pain',
      'genital bleeding',
      'pelvic pain fever',
      'pus discharge fever',
      'painful erection',
    ],
    action:
        'Please arrange urgent clinician care. Severe pain, bleeding, fever, or sudden genital symptoms should not wait for routine coaching.',
    problemHints: ['sexual'],
  ),
  _SafetyRule(
    ruleId: 'gut-bleeding',
    severity: FlickoSafetySeverity.urgent,
    title: 'Digestive bleeding or severe gut symptom',
    phrases: [
      'blood in stool',
      'black stool',
      'vomiting blood',
      'severe stomach pain',
      'severe dehydration',
    ],
    action:
        'Please get urgent medical assessment, especially if symptoms are severe, persistent, with fever, weakness, dehydration, or bleeding.',
  ),
];

bool _hasAny(String normalizedText, List<String> phrases) {
  return phrases.any((phrase) => normalizedText.contains(_normalize(phrase)));
}

bool _hasChestPainPattern(String normalizedText) {
  final tokens = _tokens(normalizedText);
  if (!tokens.any(_isPainToken)) {
    return false;
  }
  return tokens.any(_isChestLikeToken);
}

bool _hasEmergencyContactCallIntent(String normalizedText) {
  final tokens = _tokens(normalizedText);
  final hasEmergency = tokens.any(_isEmergencyLikeToken);
  if (!hasEmergency) {
    return false;
  }
  final hasCallAction = tokens.any(_isCallActionToken);
  if (!hasCallAction) {
    return false;
  }
  return tokens.any(_isEmergencyCallTargetToken);
}

List<String> _tokens(String normalizedText) {
  return normalizedText
      .split(' ')
      .map((token) => token.trim())
      .where((token) => token.isNotEmpty)
      .toList(growable: false);
}

bool _isPainToken(String token) {
  return token == 'pain' ||
      token == 'dard' ||
      token == 'ache' ||
      token == 'pressure' ||
      token == 'tightness';
}

bool _isChestLikeToken(String token) {
  const known = <String>{
    'chest',
    'chaise',
    'chais',
    'chase',
    'cheste',
    'seene',
    'sine',
    'seenay',
    'seeney',
    'chhati',
    'chhathi',
    'chaati',
    'chati',
    'dil',
    'heart',
  };
  if (known.contains(token)) {
    return true;
  }
  return token.length >= 4 && _editDistanceWithin(token, 'chest', 2);
}

bool _isEmergencyLikeToken(String token) {
  const known = <String>{
    'emergency',
    'emergecy',
    'emency',
    'emenrcy',
    'emnrgecy',
    'emenrgecy',
    'emrgecy',
    'emergncy',
  };
  if (known.contains(token)) {
    return true;
  }
  if (token.length < 5 || token.length > 12) {
    return false;
  }
  return _editDistanceWithin(token, 'emergency', 3);
}

bool _isCallActionToken(String token) {
  const known = <String>{
    'call',
    'dial',
    'connect',
    'conect',
    'phone',
    'ring',
    'karo',
    'kar',
    'lagao',
    'lgao',
    'milao',
  };
  return known.contains(token);
}

bool _isEmergencyCallTargetToken(String token) {
  const known = <String>{
    'contact',
    'contect',
    'contac',
    'number',
    'numbar',
    'call',
    'phone',
  };
  return known.contains(token) || _isEmergencyLikeToken(token);
}

bool _editDistanceWithin(String left, String right, int maxDistance) {
  if ((left.length - right.length).abs() > maxDistance) {
    return false;
  }
  var previous = List<int>.generate(right.length + 1, (index) => index);
  for (var i = 0; i < left.length; i++) {
    final current = List<int>.filled(right.length + 1, 0);
    current[0] = i + 1;
    var rowBest = current[0];
    for (var j = 0; j < right.length; j++) {
      final cost = left.codeUnitAt(i) == right.codeUnitAt(j) ? 0 : 1;
      final value = [
        previous[j + 1] + 1,
        current[j] + 1,
        previous[j] + cost,
      ].reduce((a, b) => a < b ? a : b);
      current[j + 1] = value;
      if (value < rowBest) {
        rowBest = value;
      }
    }
    if (rowBest > maxDistance) {
      return false;
    }
    previous = current;
  }
  return previous.last <= maxDistance;
}

String _normalize(String value) {
  return value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9/]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

String _string(Object? value, {String fallback = ''}) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? fallback : text;
}
