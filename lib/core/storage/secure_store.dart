import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Encrypted persistence for sensitive values (the JWT). Backed by the iOS
/// Keychain and Android Keystore-backed EncryptedSharedPreferences — never
/// plain SharedPreferences. Tokens must NEVER be logged or written elsewhere.
class SecureStore {
  SecureStore({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(),
              iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
            );

  final FlutterSecureStorage _storage;

  static const _kToken = 'auth_token';
  static const _kUser = 'auth_user';

  Future<void> writeToken(String token) => _storage.write(key: _kToken, value: token);
  Future<String?> readToken() => _storage.read(key: _kToken);

  Future<void> writeUser(String userJson) => _storage.write(key: _kUser, value: userJson);
  Future<String?> readUser() => _storage.read(key: _kUser);

  /// Wipe all credentials (logout / token invalidation).
  Future<void> clear() async {
    await _storage.delete(key: _kToken);
    await _storage.delete(key: _kUser);
  }
}
