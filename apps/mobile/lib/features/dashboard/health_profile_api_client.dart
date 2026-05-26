import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../backend_api_defaults.dart';

class HealthProfileApiException implements Exception {
  const HealthProfileApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class HealthProfileApiClient {
  const HealthProfileApiClient({
    this.baseUrl = const String.fromEnvironment(
      'FLICKO_API_BASE_URL',
      defaultValue: '',
    ),
  });

  final String baseUrl;

  static const _fallbackBaseUrls = String.fromEnvironment(
    'FLICKO_API_BASE_URL_FALLBACKS',
    defaultValue: '',
  );

  Future<Map<String, dynamic>> syncProfile({
    required String token,
    required Map<String, Object?> profile,
  }) async {
    final trimmedToken = token.trim();
    if (trimmedToken.isEmpty) {
      throw const HealthProfileApiException('Missing login token.');
    }

    final urls = _candidateBaseUrls();
    for (final candidate in urls) {
      try {
        return await _patchProfile(candidate, profile, trimmedToken);
      } on HealthProfileApiException {
        rethrow;
      } on TimeoutException {
        continue;
      } on SocketException {
        continue;
      } on http.ClientException {
        continue;
      }
    }

    throw HealthProfileApiException(
      'Could not reach Flicko backend. Tried: ${urls.join(', ')}.',
    );
  }

  Future<void> saveMemory({
    required String token,
    required String title,
    String problemName = '',
    String source = 'chat',
    String category = 'note',
    String content = '',
    Map<String, Object?> data = const <String, Object?>{},
  }) async {
    final trimmedToken = token.trim();
    if (trimmedToken.isEmpty || title.trim().isEmpty) {
      return;
    }

    final body = <String, Object?>{
      'problem_name': problemName,
      'source': source,
      'category': category,
      'title': title,
      'content': content,
      'data': data,
    };

    final urls = _candidateBaseUrls();
    for (final candidate in urls) {
      try {
        await _postMemory(candidate, body, trimmedToken);
        return;
      } on HealthProfileApiException {
        rethrow;
      } on TimeoutException {
        continue;
      } on SocketException {
        continue;
      } on http.ClientException {
        continue;
      }
    }
  }

  Future<Map<String, dynamic>> syncAppData({
    required String token,
    required Map<String, Object?> data,
  }) async {
    final trimmedToken = token.trim();
    if (trimmedToken.isEmpty) {
      throw const HealthProfileApiException('Missing login token.');
    }

    final urls = _candidateBaseUrls();
    for (final candidate in urls) {
      try {
        return await _postAppData(candidate, data, trimmedToken);
      } on HealthProfileApiException {
        rethrow;
      } on TimeoutException {
        continue;
      } on SocketException {
        continue;
      } on http.ClientException {
        continue;
      }
    }

    throw HealthProfileApiException(
      'Could not reach Flicko backend. Tried: ${urls.join(', ')}.',
    );
  }

  Future<Map<String, dynamic>> fetchAppData({required String token}) async {
    final trimmedToken = token.trim();
    if (trimmedToken.isEmpty) {
      throw const HealthProfileApiException('Missing login token.');
    }

    final urls = _candidateBaseUrls();
    for (final candidate in urls) {
      try {
        return await _getAppData(candidate, trimmedToken);
      } on HealthProfileApiException {
        rethrow;
      } on TimeoutException {
        continue;
      } on SocketException {
        continue;
      } on http.ClientException {
        continue;
      }
    }

    throw HealthProfileApiException(
      'Could not reach Flicko backend. Tried: ${urls.join(', ')}.',
    );
  }

  Future<Map<String, dynamic>> cleanupAppData({required String token}) async {
    final trimmedToken = token.trim();
    if (trimmedToken.isEmpty) {
      throw const HealthProfileApiException('Missing login token.');
    }

    final urls = _candidateBaseUrls();
    for (final candidate in urls) {
      try {
        return await _postAppDataCleanup(candidate, trimmedToken);
      } on HealthProfileApiException {
        rethrow;
      } on TimeoutException {
        continue;
      } on SocketException {
        continue;
      } on http.ClientException {
        continue;
      }
    }

    throw HealthProfileApiException(
      'Could not reach Flicko backend. Tried: ${urls.join(', ')}.',
    );
  }

  Future<Map<String, dynamic>> fetchProtocolEngineContext({
    required String token,
    required String condition,
    required String text,
    int memoryLimit = 16,
  }) async {
    final trimmedToken = token.trim();
    if (trimmedToken.isEmpty) {
      throw const HealthProfileApiException('Missing login token.');
    }

    final urls = _candidateBaseUrls();
    for (final candidate in urls) {
      try {
        return await _getProtocolEngineContext(
          candidate,
          token: trimmedToken,
          condition: condition,
          text: text,
          memoryLimit: memoryLimit,
        );
      } on HealthProfileApiException {
        rethrow;
      } on TimeoutException {
        continue;
      } on SocketException {
        continue;
      } on http.ClientException {
        continue;
      }
    }

    throw HealthProfileApiException(
      'Could not reach Flicko backend. Tried: ${urls.join(', ')}.',
    );
  }

  Future<Map<String, dynamic>> upsertAppRecord({
    required String token,
    required String recordType,
    required Map<String, Object?> record,
  }) async {
    final trimmedToken = token.trim();
    final cleanType = recordType.trim();
    if (trimmedToken.isEmpty || cleanType.isEmpty) {
      throw const HealthProfileApiException('Missing app record sync input.');
    }

    final urls = _candidateBaseUrls();
    for (final candidate in urls) {
      try {
        return await _postAppRecord(candidate, cleanType, record, trimmedToken);
      } on HealthProfileApiException {
        rethrow;
      } on TimeoutException {
        continue;
      } on SocketException {
        continue;
      } on http.ClientException {
        continue;
      }
    }

    throw HealthProfileApiException(
      'Could not reach Flicko backend. Tried: ${urls.join(', ')}.',
    );
  }

  Future<Map<String, dynamic>> deleteAppRecord({
    required String token,
    required String recordType,
    required String externalId,
  }) async {
    final trimmedToken = token.trim();
    final cleanType = recordType.trim();
    final cleanId = externalId.trim();
    if (trimmedToken.isEmpty || cleanType.isEmpty || cleanId.isEmpty) {
      throw const HealthProfileApiException('Missing app record delete input.');
    }

    final urls = _candidateBaseUrls();
    for (final candidate in urls) {
      try {
        return await _deleteAppRecord(
          candidate,
          cleanType,
          cleanId,
          trimmedToken,
        );
      } on HealthProfileApiException {
        rethrow;
      } on TimeoutException {
        continue;
      } on SocketException {
        continue;
      } on http.ClientException {
        continue;
      }
    }

    throw HealthProfileApiException(
      'Could not reach Flicko backend. Tried: ${urls.join(', ')}.',
    );
  }

  Future<Map<String, dynamic>> _patchProfile(
    String targetBaseUrl,
    Map<String, Object?> body,
    String token,
  ) async {
    final uri = Uri.parse('$targetBaseUrl/auth/me/');
    final response = await http
        .patch(
          uri,
          headers: {
            'Accept': 'application/json',
            'Authorization': 'Token $token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 15));
    final json = _decodeObject(response.body);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final user = json['user'];
      return user is Map<String, dynamic> ? user : <String, dynamic>{};
    }

    throw HealthProfileApiException(
      _errorMessage(json, 'Profile sync failed.'),
    );
  }

  Future<Map<String, dynamic>> _postAppData(
    String targetBaseUrl,
    Map<String, Object?> body,
    String token,
  ) async {
    final uri = Uri.parse('$targetBaseUrl/auth/app-data/');
    final response = await http
        .post(
          uri,
          headers: {
            'Accept': 'application/json',
            'Authorization': 'Token $token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 15));
    final json = _decodeObject(response.body);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return json;
    }

    throw HealthProfileApiException(
      _errorMessage(json, 'App data sync failed.'),
    );
  }

  Future<Map<String, dynamic>> _getAppData(
    String targetBaseUrl,
    String token,
  ) async {
    final uri = Uri.parse('$targetBaseUrl/auth/app-data/');
    final response = await http
        .get(
          uri,
          headers: {
            'Accept': 'application/json',
            'Authorization': 'Token $token',
          },
        )
        .timeout(const Duration(seconds: 15));
    final json = _decodeObject(response.body);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return json;
    }

    throw HealthProfileApiException(
      _errorMessage(json, 'App data fetch failed.'),
    );
  }

  Future<Map<String, dynamic>> _postAppDataCleanup(
    String targetBaseUrl,
    String token,
  ) async {
    final uri = Uri.parse('$targetBaseUrl/auth/app-data/cleanup/');
    final response = await http
        .post(
          uri,
          headers: {
            'Accept': 'application/json',
            'Authorization': 'Token $token',
            'Content-Type': 'application/json',
          },
          body: '{}',
        )
        .timeout(const Duration(seconds: 15));
    final json = _decodeObject(response.body);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return json;
    }

    throw HealthProfileApiException(
      _errorMessage(json, 'App data cleanup failed.'),
    );
  }

  Future<Map<String, dynamic>> _getProtocolEngineContext(
    String targetBaseUrl, {
    required String token,
    required String condition,
    required String text,
    required int memoryLimit,
  }) async {
    final uri = Uri.parse('$targetBaseUrl/auth/protocol-engine/context/')
        .replace(
          queryParameters: {
            if (condition.trim().isNotEmpty) 'condition': condition.trim(),
            if (text.trim().isNotEmpty) 'text': text.trim(),
            'memory_limit': memoryLimit.clamp(1, 50).toString(),
          },
        );
    final response = await http
        .get(
          uri,
          headers: {
            'Accept': 'application/json',
            'Authorization': 'Token $token',
          },
        )
        .timeout(const Duration(seconds: 15));
    final json = _decodeObject(response.body);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return json;
    }

    throw HealthProfileApiException(
      _errorMessage(json, 'Protocol context fetch failed.'),
    );
  }

  Future<Map<String, dynamic>> _postAppRecord(
    String targetBaseUrl,
    String recordType,
    Map<String, Object?> body,
    String token,
  ) async {
    final uri = Uri.parse('$targetBaseUrl/auth/app-data/$recordType/');
    final response = await http
        .post(
          uri,
          headers: {
            'Accept': 'application/json',
            'Authorization': 'Token $token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 15));
    final json = _decodeObject(response.body);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return json;
    }

    throw HealthProfileApiException(
      _errorMessage(json, 'App record sync failed.'),
    );
  }

  Future<Map<String, dynamic>> _deleteAppRecord(
    String targetBaseUrl,
    String recordType,
    String externalId,
    String token,
  ) async {
    final encodedId = Uri.encodeComponent(externalId);
    final uri = Uri.parse(
      '$targetBaseUrl/auth/app-data/$recordType/$encodedId/',
    );
    final response = await http
        .delete(
          uri,
          headers: {
            'Accept': 'application/json',
            'Authorization': 'Token $token',
          },
        )
        .timeout(const Duration(seconds: 15));
    final json = _decodeObject(response.body);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return json;
    }

    throw HealthProfileApiException(
      _errorMessage(json, 'App record delete failed.'),
    );
  }

  Future<void> _postMemory(
    String targetBaseUrl,
    Map<String, Object?> body,
    String token,
  ) async {
    final uri = Uri.parse('$targetBaseUrl/auth/memory/');
    final response = await http
        .post(
          uri,
          headers: {
            'Accept': 'application/json',
            'Authorization': 'Token $token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 15));

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return;
    }

    final json = _decodeObject(response.body);
    throw HealthProfileApiException(_errorMessage(json, 'Memory sync failed.'));
  }

  Map<String, dynamic> _decodeObject(String body) {
    if (body.trim().isEmpty) {
      return <String, dynamic>{};
    }
    try {
      final decoded = jsonDecode(body);
      return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
    } on FormatException {
      throw const HealthProfileApiException(
        'Backend returned an invalid profile response.',
      );
    }
  }

  List<String> _candidateBaseUrls() {
    return flickoDefaultApiBaseUrlCandidates(
      preferredBaseUrl: baseUrl,
      fallbackBaseUrlsCsv: _fallbackBaseUrls,
    );
  }

  String _errorMessage(Map<String, dynamic> json, String fallback) {
    final direct = json['detail']?.toString().trim();
    if (direct != null && direct.isNotEmpty) {
      return direct;
    }
    final error = json['error']?.toString().trim();
    if (error != null && error.isNotEmpty) {
      return error;
    }
    final fields = <String>[];
    for (final entry in json.entries) {
      final field = entry.key.trim();
      if (field.isEmpty || field == 'non_field_errors') {
        continue;
      }
      final message = _validationMessage(entry.value);
      if (message.isNotEmpty) {
        fields.add('$field: $message');
      }
    }
    if (fields.isNotEmpty) {
      return '$fallback ${fields.take(4).join('; ')}';
    }
    final nonField = _validationMessage(json['non_field_errors']);
    if (nonField.isNotEmpty) {
      return '$fallback $nonField';
    }
    return fallback;
  }

  String _validationMessage(Object? value) {
    if (value == null) {
      return '';
    }
    if (value is List) {
      return value
          .map(_validationMessage)
          .where((message) => message.isNotEmpty)
          .join(', ');
    }
    if (value is Map) {
      return value.entries
          .map((entry) {
            final child = _validationMessage(entry.value);
            return child.isEmpty ? '' : '${entry.key}: $child';
          })
          .where((message) => message.isNotEmpty)
          .join(', ');
    }
    return value.toString().trim();
  }
}
