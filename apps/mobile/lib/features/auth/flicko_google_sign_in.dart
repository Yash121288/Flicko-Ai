import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';

class FlickoGoogleAccount {
  const FlickoGoogleAccount({
    required this.idToken,
    required this.email,
    required this.displayName,
    required this.photoUrl,
  });

  final String idToken;
  final String email;
  final String displayName;
  final String photoUrl;
}

class FlickoGoogleSignInException implements Exception {
  const FlickoGoogleSignInException(this.message);

  final String message;

  @override
  String toString() => message;
}

class FlickoGoogleSignInService {
  FlickoGoogleSignInService({GoogleSignIn? signIn})
    : _signIn = signIn ?? GoogleSignIn.instance;

  static const _defaultGoogleClientId =
      '782174705998-7l0035suockngjdvbhbue651sv6cemll.apps.googleusercontent.com';
  static const _clientId = String.fromEnvironment(
    'FLICKO_GOOGLE_CLIENT_ID',
    defaultValue: _defaultGoogleClientId,
  );
  static const _serverClientId = String.fromEnvironment(
    'FLICKO_GOOGLE_SERVER_CLIENT_ID',
    defaultValue: _defaultGoogleClientId,
  );

  static Future<void>? _initializeFuture;

  final GoogleSignIn _signIn;

  Future<FlickoGoogleAccount> signIn() async {
    await _initialize();

    if (!_signIn.supportsAuthenticate()) {
      throw const FlickoGoogleSignInException(
        'Google login is not supported by this platform UI.',
      );
    }

    final account = await _signIn.authenticate(
      scopeHint: const <String>['email', 'profile'],
    );
    final idToken = account.authentication.idToken?.trim() ?? '';
    if (idToken.isEmpty) {
      throw const FlickoGoogleSignInException(
        'Google did not return an ID token for the configured Flicko OAuth client.',
      );
    }

    return FlickoGoogleAccount(
      idToken: idToken,
      email: account.email,
      displayName: account.displayName ?? '',
      photoUrl: account.photoUrl ?? '',
    );
  }

  Future<void> signOut() async {
    await _initialize();
    await _signIn.signOut();
  }

  Future<void> _initialize() {
    final clientId = _emptyToNull(_clientId);
    final serverClientId = _emptyToNull(_serverClientId);
    return _initializeFuture ??= _signIn.initialize(
      clientId: clientId,
      serverClientId: kIsWeb ? null : serverClientId,
    );
  }

  static String? _emptyToNull(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
