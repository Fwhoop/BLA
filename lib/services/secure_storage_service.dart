import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Secure storage for tokens only. No passwords or PII.
class SecureStorageService {
  static const _keyAccessToken = 'access_token';
  static const _keyRefreshToken = 'refresh_token';

  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  Future<String?> getAccessToken() => _storage.read(key: _keyAccessToken);
  Future<void> setAccessToken(String value) =>
      _storage.write(key: _keyAccessToken, value: value);
  Future<void> deleteAccessToken() => _storage.delete(key: _keyAccessToken);

  Future<String?> getRefreshToken() => _storage.read(key: _keyRefreshToken);
  Future<void> setRefreshToken(String? value) {
    if (value == null || value.isEmpty) return _storage.delete(key: _keyRefreshToken);
    return _storage.write(key: _keyRefreshToken, value: value);
  }

  Future<void> clearAll() async {
    await _storage.delete(key: _keyAccessToken);
    await _storage.delete(key: _keyRefreshToken);
  }

  Future<bool> hasToken() async {
    final t = await getAccessToken();
    return t != null && t.isNotEmpty;
  }
}
