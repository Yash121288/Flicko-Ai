import 'ai_call_memory.dart';

enum AiCallAutoEndAction {
  none,
  markClosingQuestionAsked,
  requestGoodbye,
  finishAfterGoodbye,
}

class AiCallAutoEndCoordinator {
  bool _closingQuestionAsked = false;
  bool _goodbyeRequested = false;

  bool get closingQuestionAsked => _closingQuestionAsked;
  bool get goodbyeRequested => _goodbyeRequested;

  AiCallAutoEndAction observe(HealthCallTranscriptEntry entry) {
    final text = entry.text.trim();
    if (text.isEmpty) {
      return AiCallAutoEndAction.none;
    }

    if (!entry.isUser) {
      if (_goodbyeRequested && isGoodbye(text)) {
        return AiCallAutoEndAction.finishAfterGoodbye;
      }
      if (isClosingQuestion(text)) {
        _closingQuestionAsked = true;
        return AiCallAutoEndAction.markClosingQuestionAsked;
      }
      return AiCallAutoEndAction.none;
    }

    if (!_closingQuestionAsked || _goodbyeRequested) {
      return AiCallAutoEndAction.none;
    }

    if (isNoMoreQuestions(text)) {
      _goodbyeRequested = true;
      return AiCallAutoEndAction.requestGoodbye;
    }

    _closingQuestionAsked = false;
    return AiCallAutoEndAction.none;
  }

  static bool isClosingQuestion(String text) {
    final normalized = _normalize(text);
    if (normalized.isEmpty) {
      return false;
    }
    return const [
      'aur koi question',
      'aur koi sawal',
      'aur koi problem',
      'aur koi issue',
      'koi aur question',
      'koi aur sawal',
      'koi aur problem',
      'koi aur issue',
      'aur kuch',
      'kuch aur',
      'anything else',
      'any other question',
      'any other problem',
      'any other issue',
      'any more question',
      'any more problem',
      'any more issue',
    ].any(normalized.contains);
  }

  static bool isNoMoreQuestions(String text) {
    final normalized = _normalize(text);
    if (normalized.isEmpty || _hasFollowUpConcern(normalized)) {
      return false;
    }
    if (const {
      'no',
      'nope',
      'nah',
      'nothing',
      'all good',
      'no question',
      'no questions',
      'no problem',
      'no problems',
      'no issue',
      'no issues',
      'nahi',
      'nahin',
      'nhi',
      'kuch nahi',
      'kuch nahin',
      'nahi hai',
      'nahin hai',
      'koi problem nahi',
      'koi problem nahi hai',
      'koi question nahi',
      'koi sawal nahi',
      'bas',
      'bus',
      'theek hai',
      'thik hai',
      'ok',
      'okay',
      'bye',
      'bye bye',
    }.contains(normalized)) {
      return true;
    }

    return normalized.startsWith('no ') &&
            _containsAny(normalized, const ['question', 'problem', 'issue']) ||
        normalized.contains('kuch bhi nahi') ||
        normalized.contains('nahi bas') ||
        normalized.contains('nahin bas') ||
        normalized.contains('aur kuch nahi') ||
        normalized.contains('aur koi nahi') ||
        normalized.contains('abhi kuch nahi') ||
        normalized.contains('sab theek') ||
        normalized.contains('sab thik') ||
        normalized.contains('all set') ||
        normalized.contains('that is all') ||
        normalized.contains('thats all');
  }

  static bool isGoodbye(String text) {
    final normalized = _normalize(text);
    return _containsAny(normalized, const [
      'bye',
      'goodbye',
      'chalo bye',
      'bye bye',
      'dhyan rakhna',
      'apna dhyan',
      'call yahin',
      'call end',
    ]);
  }

  static bool _hasFollowUpConcern(String normalized) {
    return _containsAny(normalized, const [
      'but',
      'actually',
      'lekin',
      'par',
      'pain',
      'dard',
      'fever',
      'sugar',
      'glucose',
      'bp',
      'pressure',
      'breath',
      'saans',
      'bleeding',
      'chakkar',
      'vomit',
      'nausea',
    ]);
  }

  static bool _containsAny(String normalized, List<String> needles) {
    return needles.any(normalized.contains);
  }

  static String _normalize(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}
