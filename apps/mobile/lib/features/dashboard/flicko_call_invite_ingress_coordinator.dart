class FlickoCallInviteIngressCoordinator {
  const FlickoCallInviteIngressCoordinator();

  List<String> normalizedPayloads(Iterable<String?> rawPayloads) {
    final seen = <String>{};
    final normalized = <String>[];
    for (final rawPayload in rawPayloads) {
      final payload = rawPayload?.trim() ?? '';
      if (payload.isEmpty || !seen.add(payload)) {
        continue;
      }
      normalized.add(payload);
    }
    return normalized;
  }
}
