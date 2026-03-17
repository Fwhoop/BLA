import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:barangay_legal_aid/config/env_config.dart';
import 'package:barangay_legal_aid/models/notification_model.dart';
import 'package:http/http.dart' as http;

import 'secure_storage_service.dart';

class ApiService {
  ApiService([SecureStorageService? secure])
      : _secure = secure ?? SecureStorageService();

  final SecureStorageService _secure;
  static const _timeout = Duration(seconds: 15);
  // AI model inference takes ~40–60 s; use a longer timeout only for chat
  static const _aiTimeout = Duration(seconds: 120);

  String get _baseUrl => apiBaseUrl;

  Future<String?> _getToken() => _secure.getAccessToken();

  Future<Map<String, String>> _getHeaders({bool includeAuth = true}) async {
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (includeAuth) {
      final token = await _getToken();
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }
    }
    return headers;
  }

  Future<bool> checkBackendHealth() async {
    try {
      final r = await http
          .get(
            Uri.parse('$_baseUrl/docs'),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(_timeout);
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Register (signup). All three photos sent as multipart fields.
  /// Returns the created user data map (includes `id`).
  Future<Map<String, dynamic>> register({
    required String firstName,
    required String lastName,
    required String email,
    required String password,
    required String phone,
    required String address,
    required String barangay,
    required String idPhotoPath,
    dynamic idPhotoBytes,
    dynamic profilePhotoBytes,
    dynamic selfieWithIdBytes,
    String role = 'user',
  }) async {
    final uri = Uri.parse('$_baseUrl/auth/register');
    final request = http.MultipartRequest('POST', uri);
    request.fields['first_name'] = firstName;
    request.fields['last_name'] = lastName;
    request.fields['email'] = email;
    request.fields['password'] = password;
    request.fields['phone'] = phone;
    request.fields['address'] = address;
    request.fields['barangay'] = barangay;
    request.fields['role'] = role;

    // Attach government ID photo
    List<int>? idBytes;
    if (idPhotoBytes is Uint8List) {
      idBytes = idPhotoBytes;
    } else if (idPhotoBytes is List<int>) {
      idBytes = idPhotoBytes;
    }
    if (idBytes != null && idBytes.isNotEmpty) {
      request.files.add(http.MultipartFile.fromBytes('id_photo', idBytes, filename: 'id_photo.jpg'));
    } else if (idPhotoPath.isNotEmpty && !idPhotoPath.startsWith('web_')) {
      final file = File(idPhotoPath);
      if (await file.exists()) {
        request.files.add(await http.MultipartFile.fromPath(
          'id_photo', idPhotoPath,
          filename: idPhotoPath.split(RegExp(r'[/\\]')).last,
        ));
      }
    }

    // Attach selfie → stored as profile_photo (shown on profile after approval)
    if (profilePhotoBytes != null) {
      final bytes = profilePhotoBytes is Uint8List
          ? profilePhotoBytes
          : profilePhotoBytes is List<int> ? Uint8List.fromList(profilePhotoBytes) : null;
      if (bytes != null && bytes.isNotEmpty) {
        request.files.add(http.MultipartFile.fromBytes('profile_photo', bytes, filename: 'profile_photo.jpg'));
      }
    }

    // Attach selfie-holding-ID photo
    if (selfieWithIdBytes != null) {
      final bytes = selfieWithIdBytes is Uint8List
          ? selfieWithIdBytes
          : selfieWithIdBytes is List<int> ? Uint8List.fromList(selfieWithIdBytes) : null;
      if (bytes != null && bytes.isNotEmpty) {
        request.files.add(http.MultipartFile.fromBytes('selfie_with_id', bytes, filename: 'selfie_with_id.jpg'));
      }
    }

    final streamed = await request.send().timeout(_timeout);
    final response = await http.Response.fromStream(streamed);
    if (response.statusCode != 200 && response.statusCode != 201) {
      final body = response.body;
      try {
        final d = json.decode(body) as Map<String, dynamic>;
        throw Exception(d['detail'] ?? 'Registration failed: ${response.statusCode}');
      } catch (e) {
        if (e is Exception) rethrow;
        throw Exception('Registration failed: ${response.statusCode} - $body');
      }
    }
    return json.decode(response.body) as Map<String, dynamic>;
  }

  Future<bool> updateProfile({
    String? firstName,
    String? lastName,
    String? phone,
    String? address,
    String? barangay,
  }) async {
    final body = <String, dynamic>{};
    if (firstName != null) body['first_name'] = firstName;
    if (lastName != null) body['last_name'] = lastName;
    if (phone != null) body['phone'] = phone;
    if (address != null) body['address'] = address;
    if (barangay != null) body['barangay'] = barangay;
    if (body.isEmpty) return true;

    final r = await http
        .put(
          Uri.parse('$_baseUrl/auth/me'),
          headers: await _getHeaders(),
          body: jsonEncode(body),
        )
        .timeout(_timeout);
    return r.statusCode == 200;
  }

  Future<bool> changePassword(String currentPassword, String newPassword) async {
    final r = await http
        .post(
          Uri.parse('$_baseUrl/auth/change-password'),
          headers: await _getHeaders(),
          body: jsonEncode({
            'current_password': currentPassword,
            'new_password': newPassword,
          }),
        )
        .timeout(_timeout);
    if (r.statusCode != 200) {
      try {
        final d = json.decode(r.body) as Map<String, dynamic>;
        throw Exception(d['detail'] ?? 'Change password failed');
      } catch (e) {
        if (e is Exception) rethrow;
        throw Exception('Change password failed: ${r.body}');
      }
    }
    return true;
  }

  Future<List<Map<String, dynamic>>> getBarangays() async {
    // Public endpoint — no auth needed (called from signup screen before login)
    final r = await http
        .get(Uri.parse('$_baseUrl/barangays/'))
        .timeout(_timeout);
    if (r.statusCode == 200) {
      return List<Map<String, dynamic>>.from(jsonDecode(r.body));
    }
    if (r.statusCode == 401) throw Exception('Authentication required. Please login again.');
    if (r.statusCode == 403) throw Exception('You do not have permission to access barangays.');
    throw Exception('Failed to load barangays: ${r.statusCode} - ${r.body}');
  }

  Future<Map<String, dynamic>> createBarangay(String name) async {
    final headers = await _getHeaders();
    final r = await http
        .post(
          Uri.parse('$_baseUrl/barangays/'),
          headers: headers,
          body: jsonEncode({'name': name}),
        )
        .timeout(_timeout);
    if (r.statusCode == 200 || r.statusCode == 201) return jsonDecode(r.body);
    throw Exception('Failed to create barangay: ${r.body}');
  }

  Future<Map<String, dynamic>> updateBarangay(int id, String name) async {
    final headers = await _getHeaders();
    final r = await http
        .put(
          Uri.parse('$_baseUrl/barangays/$id'),
          headers: headers,
          body: jsonEncode({'name': name}),
        )
        .timeout(_timeout);
    if (r.statusCode == 200) return jsonDecode(r.body);
    throw Exception('Failed to update barangay: ${r.body}');
  }

  Future<void> deleteBarangay(int id) async {
    final headers = await _getHeaders();
    final r = await http
        .delete(Uri.parse('$_baseUrl/barangays/$id'), headers: headers)
        .timeout(_timeout);
    if (r.statusCode != 200 && r.statusCode != 204) {
      throw Exception('Failed to delete barangay: ${r.body}');
    }
  }

  Future<List<Map<String, dynamic>>> getUsers({
    String? search,
    String? status,
    int page = 1,
    int limit = 50,
  }) async {
    final headers = await _getHeaders();
    final params = <String, String>{
      'page': page.toString(),
      'limit': limit.toString(),
      if (search != null && search.isNotEmpty) 'search': search,
      if (status != null) 'status': status,
    };
    final uri = Uri.parse('$_baseUrl/users/').replace(queryParameters: params);
    final r = await http.get(uri, headers: headers).timeout(_timeout);
    if (r.statusCode == 200) return List<Map<String, dynamic>>.from(jsonDecode(r.body));
    if (r.statusCode == 401) throw Exception('Authentication required. Please login again.');
    if (r.statusCode == 403) throw Exception('You do not have permission to access users.');
    throw Exception('Failed to load users: ${r.statusCode} - ${r.body}');
  }

  Future<Map<String, dynamic>> getUserSummary() async {
    final headers = await _getHeaders();
    final r = await http
        .get(Uri.parse('$_baseUrl/users/summary'), headers: headers)
        .timeout(_timeout);
    if (r.statusCode == 200) return Map<String, dynamic>.from(jsonDecode(r.body));
    throw Exception('Failed to load user summary: ${r.statusCode}');
  }

  Future<List<Map<String, dynamic>>> searchUsers(String query) async {
    if (query.trim().length < 2) return [];
    final headers = await _getHeaders();
    final uri = Uri.parse('$_baseUrl/users/search')
        .replace(queryParameters: {'q': query.trim(), 'limit': '10'});
    final r = await http.get(uri, headers: headers).timeout(_timeout);
    if (r.statusCode == 200) return List<Map<String, dynamic>>.from(jsonDecode(r.body));
    return [];
  }

  Future<List<Map<String, dynamic>>> getAdmins() async {
    final users = await getUsers();
    return users.where((u) => u['role'] == 'admin' || u['role'] == 'superadmin').toList();
  }

  /// Create admin. Password sent over HTTPS only; backend must hash and never log.
  Future<Map<String, dynamic>> createAdmin({
    required String email,
    required String username,
    required String password,
    required String firstName,
    required String lastName,
    required int? barangayId,
  }) async {
    final headers = await _getHeaders();
    final r = await http
        .post(
          Uri.parse('$_baseUrl/users/'),
          headers: headers,
          body: jsonEncode({
            'email': email,
            'username': username,
            'password': password,
            'first_name': firstName,
            'last_name': lastName,
            'role': 'admin',
            'barangay_id': barangayId,
          }),
        )
        .timeout(_timeout);
    if (r.statusCode == 200 || r.statusCode == 201) return jsonDecode(r.body);
    throw Exception('Failed to create admin: ${r.body}');
  }

  Future<Map<String, dynamic>> updateUser(int id, Map<String, dynamic> data) async {
    final headers = await _getHeaders();
    final r = await http
        .put(
          Uri.parse('$_baseUrl/users/$id'),
          headers: headers,
          body: jsonEncode(data),
        )
        .timeout(_timeout);
    if (r.statusCode == 200) return jsonDecode(r.body);
    throw Exception('Failed to update user: ${r.body}');
  }

  Future<void> deleteUser(int id) async {
    final headers = await _getHeaders();
    final r = await http
        .delete(Uri.parse('$_baseUrl/users/$id'), headers: headers)
        .timeout(_timeout);
    if (r.statusCode != 200 && r.statusCode != 204) {
      throw Exception('Failed to delete user: ${r.body}');
    }
  }

  Future<Map<String, dynamic>> getAnalytics() async {
    try {
      final headers = await _getHeaders();
      final r = await http
          .get(Uri.parse('$_baseUrl/analytics/'), headers: headers)
          .timeout(_timeout);
      if (r.statusCode == 200) return jsonDecode(r.body);
    } catch (_) {}
    return {
      'total_users': 0,
      'total_requests': 0,
      'total_cases': 0,
      'total_barangays': 0,
    };
  }

  Future<List<Map<String, dynamic>>> getLogs() async {
    try {
      final headers = await _getHeaders();
      final r = await http
          .get(Uri.parse('$_baseUrl/logs/'), headers: headers)
          .timeout(_timeout);
      if (r.statusCode == 200) return List<Map<String, dynamic>>.from(jsonDecode(r.body));
    } catch (_) {}
    return [];
  }

  Future<Map<String, dynamic>> createBackup() async {
    final headers = await _getHeaders();
    final r = await http
        .post(Uri.parse('$_baseUrl/backup/'), headers: headers)
        .timeout(_timeout);
    if (r.statusCode == 200 || r.statusCode == 201) return jsonDecode(r.body);
    throw Exception('Failed to create backup: ${r.body}');
  }

  Future<List<Map<String, dynamic>>> getBackups() async {
    try {
      final headers = await _getHeaders();
      final r = await http
          .get(Uri.parse('$_baseUrl/backup/'), headers: headers)
          .timeout(_timeout);
      if (r.statusCode == 200) return List<Map<String, dynamic>>.from(jsonDecode(r.body));
    } catch (_) {}
    return [];
  }

  Future<Map<String, dynamic>> getFaqData() async {
    try {
      final r = await http
          .get(
            Uri.parse('$_baseUrl/chats/faq'),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(_timeout);
      if (r.statusCode == 200) return jsonDecode(r.body);
    } catch (_) {}
    return {};
  }

  Future<Map<String, dynamic>> createRequest({
    required int barangayId,
    required String documentType,
    required String purpose,
  }) async {
    final headers = await _getHeaders();
    final r = await http
        .post(
          Uri.parse('$_baseUrl/requests/'),
          headers: headers,
          body: jsonEncode({
            'barangay_id': barangayId,
            'document_type': documentType,
            'purpose': purpose,
          }),
        )
        .timeout(_timeout);
    if (r.statusCode == 200 || r.statusCode == 201) return jsonDecode(r.body);
    try {
      final d = jsonDecode(r.body);
      throw Exception(d['detail'] ?? 'Failed to create request: ${r.statusCode}');
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('Failed to create request: ${r.statusCode} - ${r.body}');
    }
  }

  Future<List<Map<String, dynamic>>> getRequests() async {
    final token = await _getToken();
    if (token == null || token.isEmpty) {
      throw Exception('No authentication token. Please login again.');
    }
    final headers = await _getHeaders();
    final r = await http
        .get(Uri.parse('$_baseUrl/requests/'), headers: headers)
        .timeout(_timeout);
    if (r.statusCode == 200) return List<Map<String, dynamic>>.from(jsonDecode(r.body));
    if (r.statusCode == 401) throw Exception('Authentication failed. Please login again.');
    if (r.statusCode == 403) throw Exception('You do not have permission to access requests.');
    if (r.statusCode == 404) {
      try {
        final d = jsonDecode(r.body);
        throw Exception(d['detail'] ?? 'Endpoint not found.');
      } catch (e) {
        if (e is Exception) rethrow;
      }
    }
    throw Exception('Failed to load requests: ${r.statusCode} - ${r.body}');
  }

  Future<Map<String, dynamic>> updateRequest(int id, Map<String, dynamic> data) async {
    final headers = await _getHeaders();
    final r = await http
        .put(
          Uri.parse('$_baseUrl/requests/$id'),
          headers: headers,
          body: jsonEncode(data),
        )
        .timeout(_timeout);
    if (r.statusCode == 200) return jsonDecode(r.body);
    throw Exception('Failed to update request: ${r.body}');
  }

  Future<void> deleteRequest(int id) async {
    final headers = await _getHeaders();
    final r = await http
        .delete(Uri.parse('$_baseUrl/requests/$id'), headers: headers)
        .timeout(_timeout);
    if (r.statusCode != 200 && r.statusCode != 204) {
      throw Exception('Failed to delete request: ${r.body}');
    }
  }

  Future<List<Map<String, dynamic>>> getCases() async {
    final headers = await _getHeaders();
    final r = await http
        .get(Uri.parse('$_baseUrl/cases/'), headers: headers)
        .timeout(_timeout);
    if (r.statusCode == 200) return List<Map<String, dynamic>>.from(jsonDecode(r.body));
    if (r.statusCode == 401) throw Exception('Authentication required. Please login again.');
    if (r.statusCode == 403) throw Exception('You do not have permission to access cases.');
    throw Exception('Failed to load cases: ${r.statusCode} - ${r.body}');
  }

  Future<Map<String, dynamic>> createCase({
    required String title,
    required String description,
    int? targetBarangayId,
  }) async {
    final headers = await _getHeaders();
    final body = <String, dynamic>{'title': title, 'description': description};
    if (targetBarangayId != null) body['target_barangay_id'] = targetBarangayId;
    final r = await http
        .post(
          Uri.parse('$_baseUrl/cases/'),
          headers: headers,
          body: jsonEncode(body),
        )
        .timeout(_timeout);
    if (r.statusCode == 200 || r.statusCode == 201) return jsonDecode(r.body);
    throw Exception('Failed to create case: ${r.body}');
  }

  Future<void> uploadSuggestionAttachment(int caseId, List<int> bytes, String filename) async {
    final token = await _getToken();
    final uri = Uri.parse('$_baseUrl/cases/$caseId/upload-attachment');
    final request = http.MultipartRequest('POST', uri);
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    request.files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
    final streamed = await request.send().timeout(_timeout);
    final body = await streamed.stream.bytesToString();
    if (streamed.statusCode == 200 || streamed.statusCode == 201) return;
    throw Exception('Failed to upload attachment: $body');
  }

  Future<Map<String, dynamic>> updateCase(int id, Map<String, dynamic> data) async {
    final headers = await _getHeaders();
    final r = await http
        .put(
          Uri.parse('$_baseUrl/cases/$id'),
          headers: headers,
          body: jsonEncode(data),
        )
        .timeout(_timeout);
    if (r.statusCode == 200) return jsonDecode(r.body);
    throw Exception('Failed to update case: ${r.body}');
  }

  Future<void> deleteCase(int id) async {
    final headers = await _getHeaders();
    final r = await http
        .delete(Uri.parse('$_baseUrl/cases/$id'), headers: headers)
        .timeout(_timeout);
    if (r.statusCode != 200 && r.statusCode != 204) {
      throw Exception('Failed to delete case: ${r.body}');
    }
  }

  Future<List<Map<String, dynamic>>> getMediations(int caseId) async {
    final headers = await _getHeaders();
    final r = await http
        .get(Uri.parse('$_baseUrl/cases/$caseId/mediations'), headers: headers)
        .timeout(_timeout);
    if (r.statusCode == 200) return List<Map<String, dynamic>>.from(jsonDecode(r.body));
    throw Exception('Failed to load mediations: ${r.statusCode}');
  }

  Future<Map<String, dynamic>> createMediation(int caseId, Map<String, dynamic> data) async {
    final headers = await _getHeaders();
    final r = await http
        .post(
          Uri.parse('$_baseUrl/cases/$caseId/mediations'),
          headers: headers,
          body: jsonEncode(data),
        )
        .timeout(_timeout);
    if (r.statusCode == 200 || r.statusCode == 201) return jsonDecode(r.body);
    throw Exception('Failed to create mediation: ${r.body}');
  }

  Future<Map<String, dynamic>> updateMediation(int mediationId, Map<String, dynamic> data) async {
    final headers = await _getHeaders();
    final r = await http
        .put(
          Uri.parse('$_baseUrl/mediations/$mediationId'),
          headers: headers,
          body: jsonEncode(data),
        )
        .timeout(_timeout);
    if (r.statusCode == 200) return jsonDecode(r.body);
    throw Exception('Failed to update mediation: ${r.body}');
  }

  Future<void> deleteMediation(int mediationId) async {
    final headers = await _getHeaders();
    final r = await http
        .delete(Uri.parse('$_baseUrl/mediations/$mediationId'), headers: headers)
        .timeout(_timeout);
    if (r.statusCode != 200 && r.statusCode != 204) {
      throw Exception('Failed to delete mediation: ${r.body}');
    }
  }

  Future<Map<String, dynamic>> uploadResolutionPhoto(
      int mediationId, List<int> bytes, String filename) async {
    final token = await _getToken();
    final uri = Uri.parse('$_baseUrl/mediations/$mediationId/upload-resolution-photo');
    final request = http.MultipartRequest('POST', uri);
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    request.files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
    final streamed = await request.send().timeout(_timeout);
    final body = await streamed.stream.bytesToString();
    if (streamed.statusCode == 200 || streamed.statusCode == 201) return jsonDecode(body);
    throw Exception('Failed to upload resolution photo: $body');
  }

  Future<Map<String, dynamic>> uploadRequestDocument(
      int requestId, List<int> bytes, String filename) async {
    final token = await _getToken();
    final uri = Uri.parse('$_baseUrl/requests/$requestId/upload-document');
    final request = http.MultipartRequest('POST', uri);
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    request.files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
    final streamed = await request.send().timeout(_timeout);
    final body = await streamed.stream.bytesToString();
    if (streamed.statusCode == 200 || streamed.statusCode == 201) return jsonDecode(body);
    throw Exception('Failed to upload document: $body');
  }

  Future<void> addRespondent(int caseId, Map<String, dynamic> data) async {
    final headers = await _getHeaders();
    final r = await http
        .post(
          Uri.parse('$_baseUrl/cases/$caseId/respondents'),
          headers: headers,
          body: jsonEncode(data),
        )
        .timeout(_timeout);
    if (r.statusCode == 200 || r.statusCode == 201) return;
    throw Exception('Failed to add respondent: ${r.body}');
  }

  Future<List<Map<String, dynamic>>> getRespondents(int caseId) async {
    final headers = await _getHeaders();
    final r = await http
        .get(Uri.parse('$_baseUrl/cases/$caseId/respondents'), headers: headers)
        .timeout(_timeout);
    if (r.statusCode == 200) return List<Map<String, dynamic>>.from(jsonDecode(r.body));
    throw Exception('Failed to load respondents: ${r.statusCode}');
  }

  Future<List<NotificationModel>> getNotifications() async {
    final headers = await _getHeaders();
    final r = await http
        .get(Uri.parse('$_baseUrl/notifications/'), headers: headers)
        .timeout(_timeout);
    if (r.statusCode == 200) {
      return (jsonDecode(r.body) as List)
          .map((e) => NotificationModel.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    if (r.statusCode == 401) throw Exception('Authentication required.');
    throw Exception('Failed to load notifications: ${r.statusCode}');
  }

  Future<int> getUnreadNotificationCount() async {
    final headers = await _getHeaders();
    final r = await http
        .get(Uri.parse('$_baseUrl/notifications/unread-count'), headers: headers)
        .timeout(_timeout);
    if (r.statusCode == 200) {
      final data = jsonDecode(r.body) as Map<String, dynamic>;
      return data['count'] as int? ?? 0;
    }
    return 0;
  }

  Future<void> markNotificationRead(int id) async {
    final headers = await _getHeaders();
    await http
        .put(Uri.parse('$_baseUrl/notifications/$id/read'), headers: headers)
        .timeout(_timeout);
  }

  Future<void> markAllNotificationsRead() async {
    final headers = await _getHeaders();
    await http
        .put(Uri.parse('$_baseUrl/notifications/read-all'), headers: headers)
        .timeout(_timeout);
  }

  Future<Map<String, dynamic>> getUserStats(int userId) async {
    final headers = await _getHeaders();
    final r = await http
        .get(Uri.parse('$_baseUrl/users/$userId/stats'), headers: headers)
        .timeout(_timeout);
    if (r.statusCode == 200) return jsonDecode(r.body) as Map<String, dynamic>;
    if (r.statusCode == 403) throw Exception('Not authorized to view this user\'s stats.');
    if (r.statusCode == 404) throw Exception('User not found.');
    throw Exception('Failed to load user stats: ${r.statusCode}');
  }

  Future<Map<String, dynamic>> getMyStats() async {
    final headers = await _getHeaders();
    final r = await http
        .get(Uri.parse('$_baseUrl/users/me/stats'), headers: headers)
        .timeout(_timeout);
    if (r.statusCode == 200) return jsonDecode(r.body) as Map<String, dynamic>;
    throw Exception('Failed to load your stats: ${r.statusCode}');
  }

  Future<List<Map<String, dynamic>>> getChats() async {
    final headers = await _getHeaders();
    final r = await http
        .get(Uri.parse('$_baseUrl/chats/'), headers: headers)
        .timeout(_timeout);
    if (r.statusCode == 200) return List<Map<String, dynamic>>.from(jsonDecode(r.body));
    if (r.statusCode == 401) throw Exception('Authentication required. Please login again.');
    throw Exception('Failed to load chats: ${r.statusCode} - ${r.body}');
  }

  Future<List<Map<String, dynamic>>> getRegularUsers() async {
    final users = await getUsers();
    return users.where((u) => u['role'] == 'user').toList();
  }

  Future<List<Map<String, dynamic>>> getStaffUsers() async {
    final users = await getUsers();
    return users.where((u) => u['role'] == 'staff').toList();
  }

  Future<Map<String, dynamic>> createStaffMember({
    required String email,
    required String username,
    required String firstName,
    required String lastName,
    required String password,
  }) async {
    final headers = await _getHeaders();
    final r = await http
        .post(
          Uri.parse('$_baseUrl/users/staff-member'),
          headers: headers,
          body: jsonEncode({
            'email': email,
            'username': username,
            'first_name': firstName,
            'last_name': lastName,
            'password': password,
          }),
        )
        .timeout(_timeout);
    if (r.statusCode == 200 || r.statusCode == 201) {
      return Map<String, dynamic>.from(jsonDecode(r.body));
    }
    final body = jsonDecode(r.body);
    throw Exception(body['detail'] ?? 'Failed to create staff member');
  }

  // ── OTP / Verification ────────────────────────────────────────────────────

  Future<Map<String, dynamic>> sendEmailOtp(String email) async {
    final r = await http
        .post(
          Uri.parse('$_baseUrl/auth/send-email-otp'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'email': email}),
        )
        .timeout(_timeout);
    if (r.statusCode == 200) return jsonDecode(r.body);
    final d = jsonDecode(r.body);
    throw Exception(d['detail'] ?? 'Failed to send OTP');
  }

  Future<void> verifyEmailOtp(int userId, String otp) async {
    final r = await http
        .post(
          Uri.parse('$_baseUrl/auth/verify-email-otp'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'user_id': userId, 'otp': otp}),
        )
        .timeout(_timeout);
    if (r.statusCode != 200) {
      final d = jsonDecode(r.body);
      throw Exception(d['detail'] ?? 'OTP verification failed');
    }
  }

  Future<void> verifyFirebasePhone(int userId, String firebaseIdToken) async {
    final r = await http
        .post(
          Uri.parse('$_baseUrl/auth/verify-firebase-phone'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'user_id': userId, 'firebase_id_token': firebaseIdToken}),
        )
        .timeout(_timeout);
    if (r.statusCode != 200) {
      final d = jsonDecode(r.body);
      throw Exception(d['detail'] ?? 'Phone verification failed');
    }
  }

  Future<Map<String, dynamic>> forgotPassword(String identifier, String method) async {
    final r = await http
        .post(
          Uri.parse('$_baseUrl/auth/forgot-password'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'identifier': identifier, 'method': method}),
        )
        .timeout(_timeout);
    if (r.statusCode == 200) return jsonDecode(r.body);
    final d = jsonDecode(r.body);
    throw Exception(d['detail'] ?? 'Request failed');
  }

  Future<void> resetPassword(int userId, String otp, String newPassword) async {
    final r = await http
        .post(
          Uri.parse('$_baseUrl/auth/reset-password'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'user_id': userId, 'otp': otp, 'new_password': newPassword}),
        )
        .timeout(_timeout);
    if (r.statusCode != 200) {
      final d = jsonDecode(r.body);
      throw Exception(d['detail'] ?? 'Password reset failed');
    }
  }

  Future<void> resetPasswordPhone(int userId, String firebaseIdToken, String newPassword) async {
    final r = await http
        .post(
          Uri.parse('$_baseUrl/auth/reset-password-phone'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'user_id': userId, 'firebase_id_token': firebaseIdToken, 'new_password': newPassword}),
        )
        .timeout(_timeout);
    if (r.statusCode != 200) {
      final d = jsonDecode(r.body);
      throw Exception(d['detail'] ?? 'Password reset failed');
    }
  }

  // ── Admin Approval ────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getPendingAdmins() async {
    final headers = await _getHeaders();
    final r = await http
        .get(Uri.parse('$_baseUrl/users/pending-admins'), headers: headers)
        .timeout(_timeout);
    if (r.statusCode == 200) return List<Map<String, dynamic>>.from(jsonDecode(r.body));
    throw Exception('Failed to load pending admins: ${r.statusCode}');
  }

  Future<void> approveAdmin(int userId) async {
    final headers = await _getHeaders();
    final r = await http
        .post(Uri.parse('$_baseUrl/users/$userId/approve-admin'), headers: headers)
        .timeout(_timeout);
    if (r.statusCode != 200) {
      final d = jsonDecode(r.body);
      throw Exception(d['detail'] ?? 'Approval failed');
    }
  }

  Future<void> rejectAdmin(int userId, {String? reason}) async {
    final headers = await _getHeaders();
    final r = await http
        .post(
          Uri.parse('$_baseUrl/users/$userId/reject-admin'),
          headers: headers,
          body: jsonEncode({'reason': reason}),
        )
        .timeout(_timeout);
    if (r.statusCode != 200) {
      final d = jsonDecode(r.body);
      throw Exception(d['detail'] ?? 'Rejection failed');
    }
  }

  /// Send message to AI chatbot with conversation history for context.
  /// Returns { 'message': String, 'ui_action': String? }.
  Future<Map<String, dynamic>> sendChatMessage(
    String message,
    String senderId, {
    List<Map<String, String>> history = const [],
  }) async {
    final headers = await _getHeaders();
    final r = await http
        .post(
          Uri.parse('$_baseUrl/chats/ai'),
          headers: headers,
          body: jsonEncode({
            'sender_id': int.tryParse(senderId) ?? 0,
            'receiver_id': 1,
            'message': message,
            'history': history,
          }),
        )
        .timeout(_aiTimeout); // model inference takes ~40–60 s
    if (r.statusCode == 200 || r.statusCode == 201) {
      final data = jsonDecode(r.body) as Map<String, dynamic>;
      return {
        'message': data['message'] as String? ?? "Sorry, I couldn't process that.",
        'ui_action': data['ui_action'] as String?,
      };
    }
    throw Exception('Chat failed: ${r.statusCode}');
  }
}
