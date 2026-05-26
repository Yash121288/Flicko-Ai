import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract class FlickoProfileStore {
  Future<String?> readProfileJson();

  Future<void> writeProfileJson(String json);

  Future<void> clearProfile();
}

class FlickoSharedPreferencesProfileStore implements FlickoProfileStore {
  const FlickoSharedPreferencesProfileStore({
    required this.prefs,
    this.legacyKey = FlickoSecureProfileStore.legacyProfileKey,
  });

  final SharedPreferences prefs;
  final String legacyKey;

  @override
  Future<String?> readProfileJson() async {
    return prefs.getString(legacyKey);
  }

  @override
  Future<void> writeProfileJson(String json) async {
    await prefs.setString(legacyKey, json);
  }

  @override
  Future<void> clearProfile() async {
    await prefs.remove(legacyKey);
  }
}

class FlickoSecureProfileStore implements FlickoProfileStore {
  FlickoSecureProfileStore({
    required this.legacyPrefs,
    FlutterSecureStorage? secureStorage,
    this.legacyKey = legacyProfileKey,
  }) : secureStorage = secureStorage ?? const FlutterSecureStorage();

  static const legacyProfileKey = 'flicko_health_profile_v1';
  static const secureProfileKey = 'flicko_health_profile_secure_v1';
  static const migrationFlagKey = 'flicko_health_profile_secure_migrated_v1';

  final SharedPreferences legacyPrefs;
  final FlutterSecureStorage secureStorage;
  final String legacyKey;

  @override
  Future<String?> readProfileJson() async {
    final secureJson = await _readSecure();
    if (_hasValue(secureJson)) {
      return secureJson;
    }

    final legacyJson = legacyPrefs.getString(legacyKey);
    if (!_hasValue(legacyJson)) {
      return null;
    }

    final migrated = await _writeSecure(legacyJson!);
    if (migrated) {
      await legacyPrefs.remove(legacyKey);
      await legacyPrefs.setBool(migrationFlagKey, true);
    }
    return legacyJson;
  }

  @override
  Future<void> writeProfileJson(String json) async {
    final secureSaved = await _writeSecure(json);
    if (secureSaved) {
      await legacyPrefs.remove(legacyKey);
      await legacyPrefs.setBool(migrationFlagKey, true);
      return;
    }

    // Last-resort fallback keeps the app usable on unsupported/plugin-failing
    // environments, but production Android/iOS should use the secure branch.
    await legacyPrefs.setString(legacyKey, json);
  }

  @override
  Future<void> clearProfile() async {
    try {
      await secureStorage.delete(key: secureProfileKey);
    } catch (error) {
      debugPrint('Flicko secure profile delete skipped: $error');
    }
    await legacyPrefs.remove(legacyKey);
  }

  Future<String?> _readSecure() async {
    try {
      return await secureStorage.read(key: secureProfileKey);
    } catch (error) {
      debugPrint('Flicko secure profile read skipped: $error');
      return null;
    }
  }

  Future<bool> _writeSecure(String json) async {
    try {
      await secureStorage.write(key: secureProfileKey, value: json);
      return true;
    } catch (error) {
      debugPrint('Flicko secure profile write skipped: $error');
      return false;
    }
  }

  bool _hasValue(String? value) => value != null && value.trim().isNotEmpty;
}
