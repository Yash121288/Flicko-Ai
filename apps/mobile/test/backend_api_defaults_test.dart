import 'package:flutter_test/flutter_test.dart';
import 'package:flicko_health/backend_api_defaults.dart';

void main() {
  test(
    'production candidates prefer hosted backend and exclude local fallbacks',
    () {
      final urls = flickoDefaultApiBaseUrlCandidates();

      expect(urls, equals(const <String>[flickoHostedApiBaseUrl]));
    },
  );

  test('localhost-like values normalize back to hosted backend by default', () {
    expect(
      normalizeFlickoApiBaseUrl('http://localhost:8000/api/'),
      flickoHostedApiBaseUrl,
    );
    expect(
      normalizeFlickoApiBaseUrl('http://127.0.0.1:8000/api'),
      flickoHostedApiBaseUrl,
    );
    expect(
      normalizeFlickoApiBaseUrl('http://10.0.2.2:8000/api'),
      flickoHostedApiBaseUrl,
    );
  });

  test('explicit production url survives normalization', () {
    expect(
      normalizeFlickoApiBaseUrl(
        'https://flickoai-d4i2i.ondigitalocean.app/api/',
      ),
      flickoHostedApiBaseUrl,
    );
  });
}
