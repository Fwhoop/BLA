import 'dart:convert';

import 'package:barangay_legal_aid/config/env_config.dart';
import 'package:barangay_legal_aid/models/user_model.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'api_service.dart';
import 'secure_storage_service.dart';

/// Online-first auth. No local password or PII storage.
/// Tokens stored only in [SecureStorageService].
Map<String, dynamic> _decodeJson(String body) {
  if (body.isEmpty) return {};
  try {
    return json.decode(body) as Map<String, dynamic>;
  } catch (_) {
    return {};
  }
}

class AuthService {
  AuthService({
    SecureStorageService? secureStorage,
    ApiService? apiService,
  })  : _secure = secureStorage ?? SecureStorageService() {
    _api = apiService ?? ApiService(_secure);
  }

  final SecureStorageService _secure;
  late final ApiService _api;

  Future<bool> signUp({
    required String firstName,
    required String lastName,
    required String email,
    required String password,
    required String phone,
    required String address,
    required String barangay,
    required String idPhotoPath,
    dynamic idPhotoBytes,
    dynamic selfiePhotoBytes,
    dynamic selfieWithIdBytes,
    String role = 'user',
  }) async {
    await _api.register(
      firstName: firstName,
      lastName: lastName,
      email: email,
      password: password,
      phone: phone,
      address: address,
      barangay: barangay,
      idPhotoPath: idPhotoPath,
      idPhotoBytes: idPhotoBytes,
      profilePhotoBytes: selfiePhotoBytes,
      selfieWithIdBytes: selfieWithIdBytes,
      role: role,
    );
    return true;
  }

  /// Login: backend only. [identifier] may be email or phone number.
  Future<User?> login({
    required String identifier,
    required String password,
    required bool rememberMe,
  }) async {
    final loginUrl = Uri.parse('$apiBaseUrl/auth/login');
    final response = await http
        .post(
          loginUrl,
          headers: {'Content-Type': 'application/x-www-form-urlencoded'},
          body:
              'username=${Uri.encodeComponent(identifier)}&password=${Uri.encodeComponent(password)}',
        )
        .timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      final body = response.body;
      try {
        final data = _decodeJson(body);
        throw Exception(data['detail'] ?? 'Login failed: ${response.statusCode}');
      } catch (e) {
        if (e is Exception) rethrow;
        throw Exception('Login failed: ${response.statusCode} - $body');
      }
    }

    final data = _decodeJson(response.body);
    final accessToken = data['access_token'] as String?;
    if (accessToken == null || accessToken.isEmpty) {
      throw Exception('Invalid login response: no access token');
    }

    await _secure.setAccessToken(accessToken);
    final refresh = data['refresh_token'] as String?;
    if (refresh != null && refresh.isNotEmpty) {
      await _secure.setRefreshToken(refresh);
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isLoggedIn', true);
    await prefs.setBool('rememberMe', rememberMe);

    final user = await _fetchMe(accessToken);
    if (user != null) {
      await prefs.setString('currentUserEmail', user.email);
      await prefs.setString('currentUserRole', user.role.toString().split('.').last);
      await prefs.setString('currentUserId', user.id);
      await prefs.setString('firstName', user.firstName);
      await prefs.setString('lastName', user.lastName);
    }
    return user;
  }

  /// Current user from backend only. No demo or prefs fallback.
  Future<User?> getCurrentUser() async {
    final token = await _secure.getAccessToken();
    if (token == null || token.isEmpty) return null;

    final user = await _fetchMe(token);
    if (user != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('currentUserRole', user.role.toString().split('.').last);
    }
    return user;
  }

  Future<User?> _fetchMe(String accessToken) async {
    final url = Uri.parse('$apiBaseUrl/auth/me');
    final response = await http
        .get(
          url,
          headers: {
            'Authorization': 'Bearer $accessToken',
            'Content-Type': 'application/json',
          },
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) return null;
    final data = _decodeJson(response.body);
    final roleString = data['role'] ?? 'user';
    return User(
      id: (data['id'] ?? '').toString(),
      email: data['email'] ?? '',
      firstName: data['first_name'] ?? '',
      lastName: data['last_name'] ?? '',
      role: _roleFromString(roleString),
      barangay: data['barangay_id']?.toString() ?? 'System',
      createdAt: DateTime.now(),
    );
  }

  Future<bool> isLoggedIn() async {
    if (!await _secure.hasToken()) return false;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('isLoggedIn') ?? false;
  }

  Future<bool> isAdmin() async {
    final user = await getCurrentUser();
    return user?.isAdmin ?? false;
  }

  Future<bool> isSuperAdmin() async {
    final user = await getCurrentUser();
    return user?.isSuperAdmin ?? false;
  }

  Future<void> logout() async {
    await _secure.clearAll();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isLoggedIn', false);
    await prefs.remove('lastLogin');
    await prefs.remove('currentUserEmail');
    await prefs.remove('currentUserRole');
    await prefs.remove('currentUserId');
  }

  Future<Map<String, String>> getUserData() async {
    final user = await getCurrentUser();
    if (user == null) {
      return {
        'firstName': '',
        'lastName': '',
        'email': '',
        'phone': '',
        'address': '',
        'barangay': '',
        'role': 'user',
      };
    }
    final prefs = await SharedPreferences.getInstance();
    return {
      'firstName': user.firstName,
      'lastName': user.lastName,
      'email': user.email,
      'phone': prefs.getString('phone') ?? '',
      'address': prefs.getString('address') ?? '',
      'barangay': user.barangay,
      'role': user.role.toString().split('.').last,
    };
  }

  Future<bool> updateProfile({
    String? firstName,
    String? lastName,
    String? phone,
    String? address,
    String? barangay,
  }) async {
    final success = await _api.updateProfile(
      firstName: firstName,
      lastName: lastName,
      phone: phone,
      address: address,
      barangay: barangay,
    );
    if (success) {
      final prefs = await SharedPreferences.getInstance();
      if (firstName != null) await prefs.setString('firstName', firstName);
      if (lastName != null) await prefs.setString('lastName', lastName);
      if (phone != null) await prefs.setString('phone', phone);
      if (address != null) await prefs.setString('address', address);
      if (barangay != null) await prefs.setString('barangay', barangay);
    }
    return success;
  }

  /// Change password via backend (current + new). No local password check.
  Future<bool> changePassword(String currentPassword, String newPassword) async {
    return _api.changePassword(currentPassword, newPassword);
  }

  /// For API service / interceptors: read token without exposing storage.
  Future<String?> getAccessToken() => _secure.getAccessToken();

  SecureStorageService get secureStorage => _secure;

  UserRole _roleFromString(String s) {
    switch (s) {
      case 'admin':
        return UserRole.admin;
      case 'superadmin':
        return UserRole.superadmin;
      default:
        return UserRole.user;
    }
  }
}
