import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

class LocalProtocolPackRepository {
  const LocalProtocolPackRepository({
    this.assetPath = 'assets/health_protocols/flicko_protocol_pack_v1.json',
    this.intakeSchemaAssetPath =
        'assets/health_protocols/flicko_intake_schema_v1.json',
  });

  final String assetPath;
  final String intakeSchemaAssetPath;

  static final Map<String, Future<LocalProtocolPack>> _cache =
      <String, Future<LocalProtocolPack>>{};
  static final Map<String, Future<LocalIntakeSchemaPack>> _intakeSchemaCache =
      <String, Future<LocalIntakeSchemaPack>>{};

  Future<LocalProtocolPack> load() {
    return _cache.putIfAbsent(assetPath, () async {
      final raw = await rootBundle.loadString(assetPath);
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Protocol pack root must be an object.');
      }
      return LocalProtocolPack.fromJson(decoded);
    });
  }

  Future<LocalIntakeSchemaPack> loadIntakeSchema() {
    return _intakeSchemaCache.putIfAbsent(intakeSchemaAssetPath, () async {
      final raw = await rootBundle.loadString(intakeSchemaAssetPath);
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Intake schema root must be an object.');
      }
      return LocalIntakeSchemaPack.fromJson(decoded);
    });
  }

  Future<LocalProtocolContext> contextFor({
    required String problemName,
    String profileContext = '',
    String userText = '',
  }) async {
    final loaded = await Future.wait<Object>(<Future<Object>>[
      load(),
      loadIntakeSchema(),
    ]);
    final pack = loaded[0] as LocalProtocolPack;
    final intakeSchema = loaded[1] as LocalIntakeSchemaPack;
    final condition = pack.conditionFor(problemName);
    final safety = pack.bestSafetyMatch(
      condition: condition,
      text: '$problemName\n$profileContext\n$userText',
    );
    final intakeAssessment = LocalIntakeAssessment.assess(
      schema: intakeSchema,
      condition: condition,
      profileContext: profileContext,
      userText: userText,
    );
    return LocalProtocolContext(
      pack: pack,
      condition: condition,
      safetyMatch: safety,
      intakeAssessment: intakeAssessment,
    );
  }
}

class LocalIntakeSchemaPack {
  const LocalIntakeSchemaPack({
    required this.schemaVersion,
    required this.defaultProblemKey,
    required this.generatedFrom,
    required this.conditions,
  });

  final String schemaVersion;
  final String defaultProblemKey;
  final String generatedFrom;
  final List<LocalIntakeConditionSchema> conditions;

  factory LocalIntakeSchemaPack.fromJson(Map<String, dynamic> json) {
    return LocalIntakeSchemaPack(
      schemaVersion: _string(json['schema_version'], fallback: 'unknown'),
      defaultProblemKey: _string(
        json['default_problem_key'],
        fallback: 'general',
      ),
      generatedFrom: _string(json['generated_from']),
      conditions: _mapList(
        json['conditions'],
      ).map(LocalIntakeConditionSchema.fromJson).toList(growable: false),
    );
  }

  LocalIntakeConditionSchema conditionFor(String problemName) {
    final normalizedProblem = _normalize(problemName);
    for (final condition in conditions) {
      if (condition.matches(normalizedProblem)) {
        return condition;
      }
    }
    return conditions.firstWhere(
      (condition) => condition.problemKey == defaultProblemKey,
      orElse: () => conditions.first,
    );
  }
}

class LocalIntakeConditionSchema {
  const LocalIntakeConditionSchema({
    required this.problemKey,
    required this.displayName,
    required this.matchTerms,
    required this.criticalKeys,
    required this.fields,
  });

  final String problemKey;
  final String displayName;
  final List<String> matchTerms;
  final List<String> criticalKeys;
  final List<LocalIntakeFieldSchema> fields;

  factory LocalIntakeConditionSchema.fromJson(Map<String, dynamic> json) {
    return LocalIntakeConditionSchema(
      problemKey: _string(json['problem_key'], fallback: 'general'),
      displayName: _string(json['display_name']),
      matchTerms: _stringList(json['match_terms']),
      criticalKeys: _stringList(json['critical_keys']),
      fields: _mapList(
        json['fields'],
      ).map(LocalIntakeFieldSchema.fromJson).toList(growable: false),
    );
  }

  bool matches(String normalizedProblem) {
    return matchTerms.any((term) => _normalize(term) == normalizedProblem);
  }
}

class LocalIntakeFieldSchema {
  const LocalIntakeFieldSchema({
    required this.key,
    required this.label,
    required this.question,
    required this.why,
    required this.keywords,
    required this.dashboardKeys,
    required this.timeline,
    required this.priority,
    required this.memoryTarget,
    required this.reportCritical,
  });

  final String key;
  final String label;
  final String question;
  final String why;
  final List<String> keywords;
  final List<String> dashboardKeys;
  final bool timeline;
  final int priority;
  final String memoryTarget;
  final bool reportCritical;

  factory LocalIntakeFieldSchema.fromJson(Map<String, dynamic> json) {
    return LocalIntakeFieldSchema(
      key: _string(json['key']),
      label: _string(json['label']),
      question: _string(json['question']),
      why: _string(json['why']),
      keywords: _stringList(json['keywords']),
      dashboardKeys: _stringList(json['dashboard_keys']),
      timeline: json['timeline'] == true,
      priority: _int(json['priority'], fallback: 50),
      memoryTarget: _string(json['memory_target']),
      reportCritical: json['report_critical'] != false,
    );
  }

  bool matches(String combined) => keywords.any(combined.contains);
}

class LocalProtocolPack {
  const LocalProtocolPack({
    required this.packVersion,
    required this.reviewStatus,
    required this.disclaimer,
    required this.commonSafetyRules,
    required this.conditions,
  });

  final String packVersion;
  final String reviewStatus;
  final String disclaimer;
  final List<LocalSafetyRule> commonSafetyRules;
  final List<LocalConditionProtocol> conditions;

  factory LocalProtocolPack.fromJson(Map<String, dynamic> json) {
    return LocalProtocolPack(
      packVersion: _string(json['packVersion'], fallback: 'unknown'),
      reviewStatus: _string(json['reviewStatus'], fallback: 'starter'),
      disclaimer: _string(json['disclaimer']),
      commonSafetyRules: _mapList(
        json['commonSafetyRules'],
      ).map(LocalSafetyRule.fromJson).toList(growable: false),
      conditions: _mapList(
        json['conditions'],
      ).map(LocalConditionProtocol.fromJson).toList(growable: false),
    );
  }

  LocalConditionProtocol conditionFor(String problemName) {
    final normalizedProblem = _normalize(problemName);
    for (final condition in conditions) {
      if (condition.matches(normalizedProblem)) {
        return condition;
      }
    }
    return conditions.firstWhere(
      (condition) => condition.matches(_normalize('Other problem')),
      orElse: () => conditions.first,
    );
  }

  LocalSafetyMatch? bestSafetyMatch({
    required LocalConditionProtocol condition,
    required String text,
  }) {
    final normalizedText = _normalize(text);
    if (normalizedText.isEmpty) {
      return null;
    }

    LocalSafetyMatch? best;
    for (final rule in [...commonSafetyRules, ...condition.safetyRules]) {
      final score = rule.matchScore(normalizedText);
      if (score <= 0) {
        continue;
      }
      final candidate = LocalSafetyMatch(rule: rule, score: score);
      if (best == null || candidate.rank > best.rank) {
        best = candidate;
      }
    }
    return best;
  }
}

class LocalConditionProtocol {
  const LocalConditionProtocol({
    required this.condition,
    required this.aliases,
    required this.protocols,
    required this.foodRules,
    required this.safetyRules,
    required this.intakeQuestions,
    required this.reminderScripts,
    required this.reportBlocks,
    required this.dashboardMetrics,
    required this.memorySchemas,
    required this.evidenceSourceIds,
  });

  final String condition;
  final List<String> aliases;
  final List<LocalProtocol> protocols;
  final List<String> foodRules;
  final List<LocalSafetyRule> safetyRules;
  final List<String> intakeQuestions;
  final List<String> reminderScripts;
  final List<String> reportBlocks;
  final List<String> dashboardMetrics;
  final List<String> memorySchemas;
  final List<String> evidenceSourceIds;

  factory LocalConditionProtocol.fromJson(Map<String, dynamic> json) {
    return LocalConditionProtocol(
      condition: _string(json['condition']),
      aliases: _stringList(json['aliases']),
      protocols: _mapList(
        json['protocols'],
      ).map(LocalProtocol.fromJson).toList(growable: false),
      foodRules: _stringList(json['foodRules']),
      safetyRules: _mapList(
        json['safetyRules'],
      ).map(LocalSafetyRule.fromJson).toList(growable: false),
      intakeQuestions: _stringList(json['intakeQuestions']),
      reminderScripts: _stringList(json['reminderScripts']),
      reportBlocks: _stringList(json['reportBlocks']),
      dashboardMetrics: _stringList(json['dashboardMetrics']),
      memorySchemas: _stringList(json['memorySchemas']),
      evidenceSourceIds: _stringList(json['evidenceSourceIds']),
    );
  }

  bool matches(String normalizedProblem) {
    if (_normalize(condition) == normalizedProblem) {
      return true;
    }
    return aliases.any((alias) => _normalize(alias) == normalizedProblem);
  }
}

class LocalProtocol {
  const LocalProtocol({
    required this.protocolId,
    required this.version,
    required this.title,
    required this.summary,
    required this.rules,
  });

  final String protocolId;
  final int version;
  final String title;
  final String summary;
  final List<String> rules;

  factory LocalProtocol.fromJson(Map<String, dynamic> json) {
    return LocalProtocol(
      protocolId: _string(json['protocolId']),
      version: _int(json['version'], fallback: 1),
      title: _string(json['title']),
      summary: _string(json['summary']),
      rules: _stringList(json['rules']),
    );
  }
}

class LocalSafetyRule {
  const LocalSafetyRule({
    required this.ruleId,
    required this.severity,
    required this.symptomPattern,
    required this.response,
  });

  final String ruleId;
  final String severity;
  final String symptomPattern;
  final String response;

  factory LocalSafetyRule.fromJson(Map<String, dynamic> json) {
    return LocalSafetyRule(
      ruleId: _string(json['ruleId']),
      severity: _string(json['severity'], fallback: 'clinician'),
      symptomPattern: _string(json['symptomPattern']),
      response: _string(json['response']),
    );
  }

  int matchScore(String normalizedText) {
    final terms = _normalize(
      symptomPattern,
    ).split(' ').where((term) => term.length >= 3).toSet();
    if (terms.isEmpty) {
      return 0;
    }

    var hits = 0;
    for (final term in terms) {
      if (normalizedText.contains(term)) {
        hits++;
      }
    }

    if (hits >= 2) {
      return hits;
    }
    final exactPattern = _normalize(symptomPattern);
    if (exactPattern.isNotEmpty && normalizedText.contains(exactPattern)) {
      return hits + 2;
    }
    return 0;
  }
}

class LocalSafetyMatch {
  const LocalSafetyMatch({required this.rule, required this.score});

  final LocalSafetyRule rule;
  final int score;

  int get rank => switch (rule.severity.toLowerCase()) {
    'emergency' => 300 + score,
    'urgent' => 200 + score,
    'clinician' => 100 + score,
    _ => score,
  };
}

class LocalProtocolContext {
  const LocalProtocolContext({
    required this.pack,
    required this.condition,
    this.safetyMatch,
    required this.intakeAssessment,
  });

  final LocalProtocolPack pack;
  final LocalConditionProtocol condition;
  final LocalSafetyMatch? safetyMatch;
  final LocalIntakeAssessment intakeAssessment;

  String toPromptText() {
    final buffer = StringBuffer()
      ..writeln('Local protocol pack version: ${pack.packVersion}')
      ..writeln('Pack review status: ${pack.reviewStatus}')
      ..writeln('Safety disclaimer: ${pack.disclaimer}')
      ..writeln('Matched condition: ${condition.condition}');

    if (safetyMatch != null) {
      final rule = safetyMatch!.rule;
      buffer
        ..writeln('Matched deterministic safety rule:')
        ..writeln('- ${rule.ruleId} [${rule.severity}]: ${rule.response}');
    }

    buffer.writeln('Condition protocols:');
    for (final protocol in condition.protocols.take(3)) {
      buffer
        ..writeln(
          '- ${protocol.protocolId} v${protocol.version}: '
          '${protocol.title}. ${protocol.summary}',
        )
        ..writeln('  Rules: ${protocol.rules.take(4).join(' | ')}');
    }

    _writeList(buffer, 'Food rules', condition.foodRules);
    _writeList(buffer, 'Intake questions', condition.intakeQuestions);
    _writeList(buffer, 'Reminder scripts', condition.reminderScripts);
    _writeList(buffer, 'Report blocks', condition.reportBlocks);
    _writeList(buffer, 'Dashboard metrics', condition.dashboardMetrics);
    _writeList(buffer, 'Memory schemas', condition.memorySchemas);
    _writeList(buffer, 'Evidence source IDs', condition.evidenceSourceIds);
    buffer
      ..writeln('Local structured intake status:')
      ..writeln(
        '- score=${intakeAssessment.score}% '
        'intake_complete=${intakeAssessment.isComplete} '
        'report_ready=${intakeAssessment.reportReady}',
      );
    _writeList(
      buffer,
      'Local missing intake fields',
      intakeAssessment.missingLabels,
    );
    _writeList(
      buffer,
      'Local timeline details still missing',
      intakeAssessment.timelineGaps,
    );
    _writeList(
      buffer,
      'Local next best intake questions',
      intakeAssessment.nextQuestions,
    );
    _writeList(
      buffer,
      'Local archive to memory targets',
      intakeAssessment.archiveTargetsPending,
    );
    return buffer.toString().trim();
  }

  static void _writeList(
    StringBuffer buffer,
    String title,
    List<String> values,
  ) {
    if (values.isEmpty) {
      return;
    }
    buffer.writeln('$title:');
    for (final value in values.take(8)) {
      buffer.writeln('- $value');
    }
  }
}

class LocalIntakeAssessment {
  const LocalIntakeAssessment({
    required this.problemKey,
    required this.score,
    required this.isComplete,
    required this.reportReady,
    required this.answeredKeys,
    required this.missingLabels,
    required this.timelineGaps,
    required this.nextQuestions,
    required this.archiveTargetsPending,
  });

  final String problemKey;
  final int score;
  final bool isComplete;
  final bool reportReady;
  final List<String> answeredKeys;
  final List<String> missingLabels;
  final List<String> timelineGaps;
  final List<String> nextQuestions;
  final List<String> archiveTargetsPending;

  static LocalIntakeAssessment assess({
    required LocalIntakeSchemaPack schema,
    required LocalConditionProtocol condition,
    required String profileContext,
    required String userText,
  }) {
    final conditionSchema = schema.conditionFor(condition.condition);
    final combined = _normalize(
      '${condition.condition}\n$profileContext\n$userText',
    );
    final fields = conditionSchema.fields;

    final missing = <LocalIntakeFieldSchema>[];
    final timelineGaps = <String>[];
    final pendingTargets = <String>[];
    final answeredKeys = <String>[];
    for (final field in fields) {
      final isAnswered = field.matches(combined);
      if (isAnswered) {
        answeredKeys.add(field.key);
        continue;
      }
      missing.add(field);
      if (field.timeline) {
        timelineGaps.add(field.label);
      }
      if (field.memoryTarget.trim().isNotEmpty) {
        pendingTargets.add(field.memoryTarget.trim());
      }
    }

    missing.sort((a, b) => b.priority.compareTo(a.priority));
    final criticalMissing = missing.where((field) => field.reportCritical);
    final score = fields.isEmpty
        ? 0
        : ((answeredKeys.length * 100) / fields.length).round();
    return LocalIntakeAssessment(
      problemKey: conditionSchema.problemKey,
      score: score,
      isComplete: criticalMissing.isEmpty && timelineGaps.length <= 1,
      reportReady: criticalMissing.isEmpty,
      answeredKeys: answeredKeys,
      missingLabels: missing.map((field) => field.label).take(8).toList(),
      timelineGaps: timelineGaps.take(6).toList(),
      nextQuestions: missing.map((field) => field.question).take(4).toList(),
      archiveTargetsPending: _uniqueStrings(pendingTargets).take(8).toList(),
    );
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

List<Map<String, dynamic>> _mapList(Object? value) {
  if (value is! List) {
    return const <Map<String, dynamic>>[];
  }
  return value.whereType<Map<String, dynamic>>().toList(growable: false);
}

String _normalize(String value) {
  return value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

Iterable<String> _uniqueStrings(Iterable<String> values) sync* {
  final seen = <String>{};
  for (final value in values) {
    final cleaned = value.trim();
    if (cleaned.isEmpty) {
      continue;
    }
    final key = cleaned.toLowerCase();
    if (seen.add(key)) {
      yield cleaned;
    }
  }
}
