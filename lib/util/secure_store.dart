/// Keychain-backed storage for the API bearer token. Everything else the app
/// remembers (server URL, profile, model prefs) is not a secret and stays in
/// SharedPreferences; the token alone grants full access to the daemon, so it
/// lives in the iOS Keychain.
library;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SecureStore {
  static const _kToken = 'api_token';

  // afterFirstUnlock: readable once the device has been unlocked since boot —
  // required so a background wake (push) can still build an authed client.
  final FlutterSecureStorage _storage;

  SecureStore([FlutterSecureStorage? storage])
    : _storage =
          storage ??
          const FlutterSecureStorage(
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.first_unlock,
            ),
          );

  Future<String?> readToken() => _storage.read(key: _kToken);

  Future<void> writeToken(String token) =>
      _storage.write(key: _kToken, value: token);

  Future<void> deleteToken() => _storage.delete(key: _kToken);

  /// One-time migration: a token that predates Keychain storage moves out of
  /// SharedPreferences (where any file-system reader could see it) and the
  /// plain-text copy is removed.
  Future<void> migrate(SharedPreferences prefs) async {
    final legacy = prefs.getString(_kToken);
    if (legacy == null || legacy.isEmpty) return;
    final existing = await readToken();
    if (existing == null || existing.isEmpty) {
      await writeToken(legacy);
    }
    await prefs.remove(_kToken);
  }
}
