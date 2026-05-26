import 'ai_call_memory.dart';
import 'ai_call_models.dart';
import 'ai_call_transcript_store.dart';

class FlickoInterruptedCallRecoveryPlan {
  const FlickoInterruptedCallRecoveryPlan({
    required this.transcript,
    required this.summary,
  });

  final List<HealthCallTranscriptEntry> transcript;
  final AiCallSessionSummary summary;
}

class FlickoInterruptedCallRecoveryCoordinator {
  const FlickoInterruptedCallRecoveryCoordinator();

  FlickoInterruptedCallRecoveryPlan? build({
    required AiCallTranscriptSessionDraft session,
    required String fallbackProblemName,
    required List<HealthCallTranscriptEntry> nativeTranscript,
    DateTime? now,
  }) {
    if (session.isCompleted) {
      return null;
    }
    final transcript = mergeTranscript(session.transcript, nativeTranscript);
    if (transcript.isEmpty) {
      return null;
    }

    final resolvedNow = now ?? DateTime.now();
    final problemName = session.problemName.trim().isNotEmpty
        ? session.problemName.trim()
        : fallbackProblemName;
    final startedAt = session.startedAt;
    final endedAt = session.updatedAt.isAfter(startedAt)
        ? session.updatedAt
        : resolvedNow;
    final reasonTitle = session.subtitle.trim().isNotEmpty
        ? session.subtitle.trim()
        : 'Recovered AI call';
    const memoryIntent =
        'Recovered an interrupted Gemini Live call from encrypted local transcript storage. Use it for dashboard values, reminders, report generation, and next AI call memory.';

    final memory = HealthCallMemorySummary.fromSession(
      problemName: problemName,
      reason: session.reason.payloadKey,
      reasonTitle: reasonTitle,
      startedAt: startedAt,
      endedAt: endedAt,
      duration: endedAt.difference(startedAt),
      inviteMemoryIntent: memoryIntent,
      transcript: transcript,
    );

    return FlickoInterruptedCallRecoveryPlan(
      transcript: transcript,
      summary: AiCallSessionSummary(
        problemName: problemName,
        reason: session.reason,
        startedAt: startedAt,
        endedAt: endedAt,
        duration: endedAt.difference(startedAt),
        inviteMemoryIntent: memoryIntent,
        inviteSubtitle: session.subtitle,
        memorySummary: memory,
      ),
    );
  }

  List<HealthCallTranscriptEntry> mergeTranscript(
    List<HealthCallTranscriptEntry> local,
    List<HealthCallTranscriptEntry> native,
  ) {
    final seen = <String>{};
    final merged = <HealthCallTranscriptEntry>[];
    for (final entry in [...local, ...native]) {
      final cleanText = entry.text.trim().replaceAll(RegExp(r'\s+'), ' ');
      if (cleanText.isEmpty) {
        continue;
      }
      final key =
          '${entry.role.toLowerCase()}|${entry.createdAt.toIso8601String()}|${cleanText.toLowerCase()}';
      if (!seen.add(key)) {
        continue;
      }
      merged.add(
        HealthCallTranscriptEntry(
          role: entry.isUser ? 'user' : 'assistant',
          text: cleanText,
          createdAt: entry.createdAt,
          isFinal: entry.isFinal,
          source: entry.source,
        ),
      );
    }
    merged.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return merged.take(500).toList(growable: false);
  }
}
