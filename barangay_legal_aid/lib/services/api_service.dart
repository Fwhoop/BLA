import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_dotenv/flutter_dotenv.dart'; // ✅ add this
import 'package:http/http.dart' as http;
import 'secure_storage_service.dart';
import 'package:barangay_legal_aid/models/notification_model.dart';

class ApiService {
  ApiService([SecureStorageService? secure])
    : _secure = secure ?? SecureStorageService();

  final SecureStorageService _secure;
  static const _timeout = Duration(seconds: 15);
  static const _aiTimeout = Duration(seconds: 120);

  String get _baseUrl => dotenv.env['API_URL'] ?? 'http://127.0.0.1:8000';

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

  /// Register (signup). Photos sent as multipart; backend stores paths only.
  Future<void> register({
    required String firstName,
    required String lastName,
    required String email,
    required String password,
    required String phone,
    String address = '',
    String? houseNumber,
    String? streetName,
    String? purok,
    String? city,
    String? province,
    String? zipCode,
    required String barangay,
    String idPhotoPath = '',
    dynamic idPhotoBytes,
    String selfieWithIdPath = '',
    dynamic selfieWithIdBytes,
    String profilePhotoPath = '',
    dynamic profilePhotoBytes,
    String role = 'user',
  }) async {
    final uri = Uri.parse('$_baseUrl/auth/register');
    final request = http.MultipartRequest('POST', uri);
    request.fields['first_name'] = firstName;
    request.fields['last_name']  = lastName;
    request.fields['email']      = email;
    request.fields['password']   = password;
    request.fields['phone']      = phone;
    request.fields['barangay']   = barangay;
    request.fields['role']       = role;
    if (address.isNotEmpty)     request.fields['address']      = address;
    if (houseNumber?.isNotEmpty == true) request.fields['house_number'] = houseNumber!;
    if (streetName?.isNotEmpty  == true) request.fields['street_name']  = streetName!;
    if (purok?.isNotEmpty       == true) request.fields['purok']         = purok!;
    if (city?.isNotEmpty        == true) request.fields['city']          = city!;
    if (province?.isNotEmpty    == true) request.fields['province']      = province!;
    if (zipCode?.isNotEmpty     == true) request.fields['zip_code']      = zipCode!;

    void attach(String field, dynamic bytes, String fname) {
      List<int>? b;
      if (bytes is Uint8List) { b = bytes; }
      else if (bytes is List<int>) { b = bytes; }
      if (b != null && b.isNotEmpty) {
        request.files.add(http.MultipartFile.fromBytes(field, b, filename: fname));
      }
    }

    attach('id_photo',       idPhotoBytes,      'id_photo.jpg');
    attach('selfie_with_id', selfieWithIdBytes, 'selfie_with_id.jpg');
    attach('profile_photo',  profilePhotoBytes, 'profile_photo.jpg');

    final streamed  = await request.send().timeout(_timeout);
    final response  = await http.Response.fromStream(streamed);
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

  Future<bool> changePassword(
    String currentPassword,
    String newPassword,
  ) async {
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
    if (r.statusCode == 401)
      throw Exception('Authentication required. Please login again.');
    if (r.statusCode == 403)
      throw Exception('You do not have permission to access barangays.');
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
      'page': '$page',
      'limit': '$limit',
    };
    if (search != null && search.isNotEmpty) params['search'] = search;
    if (status != null && status != 'all') params['status'] = status;
    final uri = Uri.parse('$_baseUrl/users/').replace(queryParameters: params);
    final r = await http.get(uri, headers: headers).timeout(_timeout);
    if (r.statusCode == 200) {
      return List<Map<String, dynamic>>.from(jsonDecode(r.body));
    }
    if (r.statusCode == 401) {
      throw Exception('Authentication required. Please login again.');
    }
    if (r.statusCode == 403) {
      throw Exception('You do not have permission to access users.');
    }
    throw Exception('Failed to load users: ${r.statusCode} - ${r.body}');
  }

  Future<Map<String, dynamic>> getUserSummary() async {
    final headers = await _getHeaders();
    final r = await http
        .get(Uri.parse('$_baseUrl/users/summary'), headers: headers)
        .timeout(_timeout);
    if (r.statusCode == 200) return jsonDecode(r.body);
    throw Exception('Failed to load user summary: ${r.body}');
  }

  Future<List<Map<String, dynamic>>> getAdmins() async {
    final users = await getUsers();
    return users
        .where((u) => u['role'] == 'admin' || u['role'] == 'superadmin')
        .toList();
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

  Future<Map<String, dynamic>> updateUser(
    int id,
    Map<String, dynamic> data,
  ) async {
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
      if (r.statusCode == 200)
        return List<Map<String, dynamic>>.from(jsonDecode(r.body));
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
      if (r.statusCode == 200)
        return List<Map<String, dynamic>>.from(jsonDecode(r.body));
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
      throw Exception(
        d['detail'] ?? 'Failed to create request: ${r.statusCode}',
      );
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
    if (r.statusCode == 200)
      return List<Map<String, dynamic>>.from(jsonDecode(r.body));
    if (r.statusCode == 401)
      throw Exception('Authentication failed. Please login again.');
    if (r.statusCode == 403)
      throw Exception('You do not have permission to access requests.');
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

  Future<Map<String, dynamic>> updateRequest(
    int id,
    Map<String, dynamic> data,
  ) async {
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
    if (r.statusCode == 200)
      return List<Map<String, dynamic>>.from(jsonDecode(r.body));
    if (r.statusCode == 401)
      throw Exception('Authentication required. Please login again.');
    if (r.statusCode == 403)
      throw Exception('You do not have permission to access cases.');
    throw Exception('Failed to load cases: ${r.statusCode} - ${r.body}');
  }

  Future<Map<String, dynamic>> createCase({
    required String title,
    required String description,
    String? category,
    String? urgency,
  }) async {
    final headers = await _getHeaders();
    final body = <String, dynamic>{
      'title': title,
      'description': description,
      if (category != null) 'category': category,
      if (urgency != null) 'urgency': urgency,
    };
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

  Future<void> addRespondent(int caseId, Map<String, dynamic> data) async {
    final headers = await _getHeaders();
    final r = await http
        .post(
          Uri.parse('$_baseUrl/cases/$caseId/respondents'),
          headers: headers,
          body: jsonEncode(data),
        )
        .timeout(_timeout);
    if (r.statusCode != 200 && r.statusCode != 201) {
      throw Exception('Failed to add respondent: ${r.body}');
    }
  }

  Future<List<Map<String, dynamic>>> searchUsers(String query) async {
    final headers = await _getHeaders();
    final uri = Uri.parse('$_baseUrl/users/').replace(
      queryParameters: {'search': query, 'limit': '20'},
    );
    final r = await http.get(uri, headers: headers).timeout(_timeout);
    if (r.statusCode == 200) {
      return List<Map<String, dynamic>>.from(jsonDecode(r.body));
    }
    return [];
  }

  Future<Map<String, dynamic>> updateCase(
    int id,
    Map<String, dynamic> data,
  ) async {
    final headers = await _getHeaders();
    final r = await http
        .put(
          Uri.parse('$_baseUrl/cases/$id'),
          headers: headers,
          body: jsonEncode(data),
        )
        .timeout(_timeout);
    if (r.statusCode == 200) return jsonDecode(r.body);
    try {
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      throw Exception(d['detail'] ?? 'Failed to update case: ${r.statusCode}');
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('Failed to update case: ${r.statusCode}');
    }
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
        .get(
          Uri.parse('$_baseUrl/notifications/unread-count'),
          headers: headers,
        )
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

  Future<List<Map<String, dynamic>>> getChats() async {
    final headers = await _getHeaders();
    final r = await http
        .get(Uri.parse('$_baseUrl/chats/'), headers: headers)
        .timeout(_timeout);
    if (r.statusCode == 200)
      return List<Map<String, dynamic>>.from(jsonDecode(r.body));
    if (r.statusCode == 401)
      throw Exception('Authentication required. Please login again.');
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

  /// Forgot password – send OTP via email or initiate phone reset.
  /// [method] is `'email'` or `'phone'`. Returns `{'user_id': int, 'message': String}`.
  Future<Map<String, dynamic>> forgotPassword(String identifier, String method) async {
    final r = await http
        .post(
          Uri.parse('$_baseUrl/auth/forgot-password'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'identifier': identifier, 'method': method}),
        )
        .timeout(_timeout);
    if (r.statusCode == 200) return jsonDecode(r.body) as Map<String, dynamic>;
    try {
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      throw Exception(d['detail'] ?? 'Failed to send OTP');
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('Failed to send OTP: ${r.body}');
    }
  }

  /// Reset password via email OTP – verify OTP and set a new password.
  Future<void> resetPassword(int userId, String otp, String newPassword) async {
    final r = await http
        .post(
          Uri.parse('$_baseUrl/auth/reset-password'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'user_id': userId,
            'otp': otp,
            'new_password': newPassword,
          }),
        )
        .timeout(_timeout);
    if (r.statusCode == 200) return;
    try {
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      throw Exception(d['detail'] ?? 'Password reset failed');
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('Password reset failed: ${r.body}');
    }
  }

  /// Reset password via Firebase phone OTP.
  Future<void> resetPasswordPhone(int userId, String firebaseIdToken, String newPassword) async {
    final r = await http
        .post(
          Uri.parse('$_baseUrl/auth/reset-password-phone'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'user_id': userId,
            'firebase_id_token': firebaseIdToken,
            'new_password': newPassword,
          }),
        )
        .timeout(_timeout);
    if (r.statusCode == 200) return;
    try {
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      throw Exception(d['detail'] ?? 'Password reset failed');
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('Password reset failed: ${r.body}');
    }
  }

  // ── Mediation ────────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getMediations(int caseId) async {
    final headers = await _getHeaders();
    final r = await http
        .get(Uri.parse('$_baseUrl/cases/$caseId/mediations'), headers: headers)
        .timeout(_timeout);
    if (r.statusCode == 200) return List<Map<String, dynamic>>.from(jsonDecode(r.body));
    throw Exception('Failed to load mediations: ${r.body}');
  }

  Future<Map<String, dynamic>> createMediation(int caseId, Map<String, dynamic> data) async {
    final headers = await _getHeaders();
    final r = await http
        .post(Uri.parse('$_baseUrl/cases/$caseId/mediations'),
            headers: headers, body: jsonEncode(data))
        .timeout(_timeout);
    if (r.statusCode == 200 || r.statusCode == 201) return jsonDecode(r.body);
    try {
      final d = jsonDecode(r.body);
      throw Exception(d['detail'] ?? 'Failed to create mediation');
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('Failed to create mediation: ${r.body}');
    }
  }

  Future<Map<String, dynamic>> updateMediation(int mediationId, Map<String, dynamic> data) async {
    final headers = await _getHeaders();
    final r = await http
        .put(Uri.parse('$_baseUrl/mediations/$mediationId'),
            headers: headers, body: jsonEncode(data))
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

  /// Upload a fulfilled document file for a document request (admin only).
  Future<Map<String, dynamic>> uploadRequestDocument(
    int requestId,
    List<int> bytes,
    String filename,
  ) async {
    final token = await _getToken();
    final uri = Uri.parse('$_baseUrl/requests/$requestId/upload-document');
    final req = http.MultipartRequest('POST', uri);
    if (token != null && token.isNotEmpty) {
      req.headers['Authorization'] = 'Bearer $token';
    }
    req.files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
    final streamed = await req.send().timeout(_timeout);
    final response = await http.Response.fromStream(streamed);
    if (response.statusCode == 200 || response.statusCode == 201) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    try {
      final d = jsonDecode(response.body) as Map<String, dynamic>;
      throw Exception(d['detail'] ?? 'Upload failed: ${response.statusCode}');
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('Upload failed: ${response.statusCode}');
    }
  }

  /// Upload a resolution photo for a mediation record (admin only).
  Future<Map<String, dynamic>> uploadResolutionPhoto(
    int mediationId,
    List<int> bytes,
    String filename,
  ) async {
    final token = await _getToken();
    final uri = Uri.parse('$_baseUrl/mediations/$mediationId/upload-resolution-photo');
    final req = http.MultipartRequest('POST', uri);
    if (token != null && token.isNotEmpty) {
      req.headers['Authorization'] = 'Bearer $token';
    }
    req.files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
    final streamed = await req.send().timeout(_timeout);
    final response = await http.Response.fromStream(streamed);
    if (response.statusCode == 200 || response.statusCode == 201) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    try {
      final d = jsonDecode(response.body) as Map<String, dynamic>;
      throw Exception(d['detail'] ?? 'Upload failed: ${response.statusCode}');
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('Upload failed: ${response.statusCode}');
    }
  }

  // ── OTP ──────────────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> sendEmailOTP(String email) async {
    final r = await http
        .post(Uri.parse('$_baseUrl/auth/send-email-otp'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'email': email}))
        .timeout(_timeout);
    if (r.statusCode == 200) return jsonDecode(r.body) as Map<String, dynamic>;
    try {
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      throw Exception(d['detail'] ?? 'Failed to send OTP');
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('Failed to send OTP: ${r.body}');
    }
  }

  Future<void> verifyEmailOTP(String email, String otp) async {
    final r = await http
        .post(Uri.parse('$_baseUrl/auth/verify-email-otp'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'email': email, 'otp': otp}))
        .timeout(_timeout);
    if (r.statusCode == 200) return;
    try {
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      throw Exception(d['detail'] ?? 'Invalid OTP');
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('Verification failed: ${r.body}');
    }
  }

  /// Lowercase alias — sends email OTP after registration, returns `{'user_id': int}`.
  Future<Map<String, dynamic>> sendEmailOtp(String email) => sendEmailOTP(email);

  /// Verify email OTP by user_id + code (post-registration flow).
  Future<void> verifyEmailOtp(int userId, String otp) async {
    final r = await http
        .post(Uri.parse('$_baseUrl/auth/verify-email-otp'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'user_id': userId, 'otp': otp}))
        .timeout(_timeout);
    if (r.statusCode == 200) return;
    try {
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      throw Exception(d['detail'] ?? 'Invalid OTP');
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('Verification failed: ${r.body}');
    }
  }

  /// Verify Firebase phone ID token after phone OTP flow.
  Future<void> verifyFirebasePhone(int userId, String firebaseIdToken) async {
    final r = await http
        .post(Uri.parse('$_baseUrl/auth/verify-firebase-phone'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'user_id': userId, 'firebase_id_token': firebaseIdToken}))
        .timeout(_timeout);
    if (r.statusCode == 200) return;
    try {
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      throw Exception(d['detail'] ?? 'Phone verification failed');
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('Phone verification failed: ${r.body}');
    }
  }

  // ── Admin Approval ───────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getPendingAdmins() async {
    final headers = await _getHeaders();
    final r = await http
        .get(Uri.parse('$_baseUrl/users/pending-admins'), headers: headers)
        .timeout(_timeout);
    if (r.statusCode == 200) return List<Map<String, dynamic>>.from(jsonDecode(r.body));
    throw Exception('Failed to load pending admins: ${r.body}');
  }

  Future<void> approveAdmin(int userId) async {
    final headers = await _getHeaders();
    final r = await http
        .post(Uri.parse('$_baseUrl/users/$userId/approve-admin'), headers: headers)
        .timeout(_timeout);
    if (r.statusCode == 200) return;
    try {
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      throw Exception(d['detail'] ?? 'Failed to approve admin');
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('Failed to approve admin: ${r.body}');
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
    if (r.statusCode == 200) return;
    try {
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      throw Exception(d['detail'] ?? 'Failed to reject admin');
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('Failed to reject admin: ${r.body}');
    }
  }

  Future<List<Map<String, dynamic>>> getAuditLogs({
    String? actionType,
    int? targetUserId,
    int limit = 50,
  }) async {
    final headers = await _getHeaders();
    final params = <String, String>{'limit': '$limit'};
    if (actionType != null) params['action_type'] = actionType;
    if (targetUserId != null) params['target_user_id'] = '$targetUserId';
    final uri = Uri.parse('$_baseUrl/audit-logs').replace(queryParameters: params);
    final r = await http.get(uri, headers: headers).timeout(_timeout);
    if (r.statusCode == 200) return List<Map<String, dynamic>>.from(jsonDecode(r.body));
    throw Exception('Failed to load audit logs: ${r.body}');
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
        'message':
            data['message'] as String? ?? "Sorry, I couldn't process that.",
        'ui_action': data['ui_action'] as String?,
      };
    }
    throw Exception('Chat failed: ${r.statusCode}');
  }
}
