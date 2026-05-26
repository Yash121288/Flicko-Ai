import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class NativeCallInviteBridge {
  const NativeCallInviteBridge();

  static const MethodChannel _channel = MethodChannel(
    'flicko.health/live_call_service',
  );

  Future<String?> consumeCallInvitePayload() async {
    try {
      final payload = await _channel.invokeMethod<String?>(
        'consumeCallInvitePayload',
      );
      final clean = payload?.trim();
      return clean == null || clean.isEmpty ? null : clean;
    } on MissingPluginException catch (error) {
      debugPrint('Flicko native call invite bridge unavailable: $error');
    } on PlatformException catch (error) {
      debugPrint('Flicko native call invite bridge failed: ${error.message}');
    }
    return null;
  }

  Future<bool> showCallInvite({
    required String title,
    required String body,
    required String payload,
  }) {
    return _invokeBool('showNativeCallInvite', {
      'title': title,
      'body': body,
      'payload': payload,
    });
  }

  Future<bool> scheduleCallInvite({
    required String title,
    required String body,
    required String payload,
    required DateTime scheduledAt,
    required bool repeatsDaily,
  }) {
    return _invokeBool('scheduleNativeCallInvite', {
      'title': title,
      'body': body,
      'payload': payload,
      'scheduledAtMillis': scheduledAt.millisecondsSinceEpoch,
      'repeatsDaily': repeatsDaily,
    });
  }

  Future<bool> cancelCallInvite(String payload) {
    return _invokeBool('cancelNativeCallInvite', {'payload': payload});
  }

  Future<bool> _invokeBool(
    String method,
    Map<String, Object?> arguments,
  ) async {
    try {
      return await _channel.invokeMethod<bool>(method, arguments) ?? false;
    } on MissingPluginException catch (error) {
      debugPrint('Flicko native call invite bridge unavailable: $error');
    } on PlatformException catch (error) {
      debugPrint('Flicko native call invite bridge failed: ${error.message}');
    }
    return false;
  }
}
