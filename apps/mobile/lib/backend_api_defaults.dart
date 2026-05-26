const String flickoHostedApiBaseUrl =
    'https://flickoai-d4i2i.ondigitalocean.app/api';

const bool flickoAllowLocalBackendFallbacks = bool.fromEnvironment(
  'FLICKO_ALLOW_LOCAL_BACKEND_FALLBACKS',
  defaultValue: false,
);

const List<String> _flickoLocalDevApiBaseUrls = <String>[
  'http://10.0.2.2:8000/api',
  'http://127.0.0.1:8000/api',
  'http://localhost:8000/api',
];

List<String> flickoDefaultApiBaseUrlCandidates({
  String preferredBaseUrl = '',
  String fallbackBaseUrlsCsv = '',
}) {
  final urls = <String>[
    preferredBaseUrl,
    ...fallbackBaseUrlsCsv.split(','),
    flickoHostedApiBaseUrl,
    if (flickoAllowLocalBackendFallbacks) ..._flickoLocalDevApiBaseUrls,
  ];

  final seen = <String>{};
  return urls
      .map(normalizeFlickoApiBaseUrl)
      .where((url) => url.isNotEmpty && seen.add(url))
      .toList(growable: false);
}

String normalizeFlickoApiBaseUrl(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return '';
  }
  final withoutTrailingSlash = trimmed.endsWith('/')
      ? trimmed.substring(0, trimmed.length - 1)
      : trimmed;
  if (!flickoAllowLocalBackendFallbacks &&
      _flickoLocalDevApiBaseUrls.contains(withoutTrailingSlash)) {
    return flickoHostedApiBaseUrl;
  }
  return withoutTrailingSlash;
}
