import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  static const String baseUrl = 'http://127.0.0.1:8000';
  
  Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('access_token');
  }

  Future<bool> checkBackendHealth() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/docs'),
        headers: {'Content-Type': 'application/json'},
      );
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  Future<Map<String, String>> _getHeaders({bool includeAuth = true}) async {
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };
    if (includeAuth) {
      final token = await _getToken();
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }
    }
    return headers;
  }

  // Barangays API
  Future<List<Map<String, dynamic>>> getBarangays() async {
    try {
      final headers = await _getHeaders();
      final response = await http.get(
        Uri.parse('$baseUrl/barangays/'),
        headers: headers,
      );
      
      if (response.statusCode == 200) {
        return List<Map<String, dynamic>>.from(jsonDecode(response.body));
      } else if (response.statusCode == 401) {
        throw Exception('Authentication required. Please login again.');
      } else if (response.statusCode == 403) {
        throw Exception('You do not have permission to access barangays.');
      } else {
        throw Exception('Failed to load barangays: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      if (e.toString().contains('Failed host lookup') || 
          e.toString().contains('Connection refused') ||
          e.toString().contains('Network is unreachable')) {
        throw Exception('Cannot connect to backend server. Please ensure the backend is running on http://127.0.0.1:8000');
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> createBarangay(String name) async {
    try {
      final headers = await _getHeaders();
      final response = await http.post(
        Uri.parse('$baseUrl/barangays/'),
        headers: headers,
        body: jsonEncode({'name': name}),
      );
      
      if (response.statusCode == 200 || response.statusCode == 201) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Failed to create barangay: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error creating barangay: $e');
    }
  }

  Future<Map<String, dynamic>> updateBarangay(int id, String name) async {
    try {
      final headers = await _getHeaders();
      final response = await http.put(
        Uri.parse('$baseUrl/barangays/$id'),
        headers: headers,
        body: jsonEncode({'name': name}),
      );
      
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Failed to update barangay: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error updating barangay: $e');
    }
  }

  Future<void> deleteBarangay(int id) async {
    try {
      final headers = await _getHeaders();
      final response = await http.delete(
        Uri.parse('$baseUrl/barangays/$id'),
        headers: headers,
      );
      
      if (response.statusCode != 200 && response.statusCode != 204) {
        throw Exception('Failed to delete barangay: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error deleting barangay: $e');
    }
  }

  Future<List<Map<String, dynamic>>> getUsers() async {
    try {
      final headers = await _getHeaders(includeAuth: false); 
      final response = await http.get(
        Uri.parse('$baseUrl/users/'),
        headers: headers,
      );
      
      if (response.statusCode == 200) {
        return List<Map<String, dynamic>>.from(jsonDecode(response.body));
      } else {
        throw Exception('Failed to load users: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      if (e.toString().contains('Failed host lookup') || 
          e.toString().contains('Connection refused')) {
        throw Exception('Cannot connect to backend server. Please ensure the backend is running.');
      }
      throw Exception('Error fetching users: $e');
    }
  }

  Future<List<Map<String, dynamic>>> getAdmins() async {
    try {
      final users = await getUsers();
      return users.where((user) => 
        user['role'] == 'admin' || user['role'] == 'superadmin'
      ).toList();
    } catch (e) {
      throw Exception('Error fetching admins: $e');
    }
  }

  Future<Map<String, dynamic>> createAdmin({
    required String email,
    required String username,
    required String password,
    required String firstName,
    required String lastName,
    required int? barangayId,
  }) async {
    try {
      final headers = await _getHeaders();
      final response = await http.post(
        Uri.parse('$baseUrl/users/'),
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
      );
      
      if (response.statusCode == 200 || response.statusCode == 201) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Failed to create admin: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error creating admin: $e');
    }
  }

  Future<Map<String, dynamic>> updateUser(int id, Map<String, dynamic> data) async {
    try {
      final headers = await _getHeaders();
      final response = await http.put(
        Uri.parse('$baseUrl/users/$id'),
        headers: headers,
        body: jsonEncode(data),
      );
      
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Failed to update user: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error updating user: $e');
    }
  }

  Future<void> deleteUser(int id) async {
    try {
      final headers = await _getHeaders();
      final response = await http.delete(
        Uri.parse('$baseUrl/users/$id'),
        headers: headers,
      );
      
      if (response.statusCode != 200 && response.statusCode != 204) {
        throw Exception('Failed to delete user: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error deleting user: $e');
    }
  }

  Future<Map<String, dynamic>> getAnalytics() async {
    try {
      final headers = await _getHeaders();
      final response = await http.get(
        Uri.parse('$baseUrl/analytics/'),
        headers: headers,
      );
      
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        return {
          'total_users': 0,
          'total_requests': 0,
          'total_cases': 0,
          'total_barangays': 0,
        };
      }
    } catch (e) {
      return {
        'total_users': 0,
        'total_requests': 0,
        'total_cases': 0,
        'total_barangays': 0,
      };
    }
  }

  Future<List<Map<String, dynamic>>> getLogs() async {
    try {
      final headers = await _getHeaders();
      final response = await http.get(
        Uri.parse('$baseUrl/logs/'),
        headers: headers,
      );
      
      if (response.statusCode == 200) {
        return List<Map<String, dynamic>>.from(jsonDecode(response.body));
      } else {
        return [];
      }
    } catch (e) {
      return [];
    }
  }

  Future<Map<String, dynamic>> createBackup() async {
    try {
      final headers = await _getHeaders();
      final response = await http.post(
        Uri.parse('$baseUrl/backup/'),
        headers: headers,
      );
      
      if (response.statusCode == 200 || response.statusCode == 201) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Failed to create backup: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error creating backup: $e');
    }
  }

  Future<List<Map<String, dynamic>>> getBackups() async {
    try {
      final headers = await _getHeaders();
      final response = await http.get(
        Uri.parse('$baseUrl/backup/'),
        headers: headers,
      );
      
      if (response.statusCode == 200) {
        return List<Map<String, dynamic>>.from(jsonDecode(response.body));
      } else {
        return [];
      }
    } catch (e) {
      return [];
    }
  }

  // Requests API
  Future<List<Map<String, dynamic>>> getRequests() async {
    try {
      final token = await _getToken();
      if (token == null || token.isEmpty) {
        throw Exception('No authentication token found. Please login again.');
      }
      
      final headers = await _getHeaders();
      print('Fetching requests from $baseUrl/requests/');
      print('Token present: ${token.isNotEmpty}');
      print('Headers: ${headers.keys.toList()}');
      final response = await http.get(
        Uri.parse('$baseUrl/requests/'),
        headers: headers,
      );
      
      print('Response status: ${response.statusCode}');
      print('Response body: ${response.body}');
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        print('Parsed requests: $data');
        return List<Map<String, dynamic>>.from(data);
      } else if (response.statusCode == 401) {
        throw Exception('Authentication failed. Token may be expired. Please login again.');
      } else if (response.statusCode == 403) {
        throw Exception('You do not have permission to access requests. Make sure your account has admin role and barangay_id set.');
      } else if (response.statusCode == 404) {
        try {
          final errorData = jsonDecode(response.body);
          final detail = errorData['detail'] ?? 'Endpoint not found';
          throw Exception('404 Error: $detail. Make sure you are logged in and the backend is running correctly.');
        } catch (_) {
          throw Exception('404 Error: Endpoint not found. This may indicate an authentication issue. Please login again.');
        }
      } else {
        throw Exception('Failed to load requests: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      print('Error in getRequests: $e');
      if (e.toString().contains('Failed host lookup') || 
          e.toString().contains('Connection refused')) {
        throw Exception('Cannot connect to backend server. Please ensure the backend is running on http://127.0.0.1:8000');
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> updateRequest(int id, Map<String, dynamic> data) async {
    try {
      final headers = await _getHeaders();
      final response = await http.put(
        Uri.parse('$baseUrl/requests/$id'),
        headers: headers,
        body: jsonEncode(data),
      );
      
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Failed to update request: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error updating request: $e');
    }
  }

  Future<void> deleteRequest(int id) async {
    try {
      final headers = await _getHeaders();
      final response = await http.delete(
        Uri.parse('$baseUrl/requests/$id'),
        headers: headers,
      );
      
      if (response.statusCode != 200 && response.statusCode != 204) {
        throw Exception('Failed to delete request: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error deleting request: $e');
    }
  }

  // Cases API
  Future<List<Map<String, dynamic>>> getCases() async {
    try {
      final headers = await _getHeaders(includeAuth: false); 
      final response = await http.get(
        Uri.parse('$baseUrl/cases/'),
        headers: headers,
      );
      
      if (response.statusCode == 200) {
        return List<Map<String, dynamic>>.from(jsonDecode(response.body));
      } else {
        throw Exception('Failed to load cases: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      if (e.toString().contains('Failed host lookup') || 
          e.toString().contains('Connection refused')) {
        throw Exception('Cannot connect to backend server. Please ensure the backend is running.');
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> createCase({
    required String title,
    required String description,
  }) async {
    try {
      final headers = await _getHeaders();
      final response = await http.post(
        Uri.parse('$baseUrl/cases/'),
        headers: headers,
        body: jsonEncode({
          'title': title,
          'description': description,
        }),
      );
      
      if (response.statusCode == 200 || response.statusCode == 201) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Failed to create case: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error creating case: $e');
    }
  }

  Future<Map<String, dynamic>> updateCase(int id, Map<String, dynamic> data) async {
    try {
      final headers = await _getHeaders();
      final response = await http.put(
        Uri.parse('$baseUrl/cases/$id'),
        headers: headers,
        body: jsonEncode(data),
      );
      
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Failed to update case: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error updating case: $e');
    }
  }

  Future<void> deleteCase(int id) async {
    try {
      final headers = await _getHeaders();
      final response = await http.delete(
        Uri.parse('$baseUrl/cases/$id'),
        headers: headers,
      );
      
      if (response.statusCode != 200 && response.statusCode != 204) {
        throw Exception('Failed to delete case: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error deleting case: $e');
    }
  }

  // Chats API
  Future<List<Map<String, dynamic>>> getChats() async {
    try {
      final headers = await _getHeaders();
      final response = await http.get(
        Uri.parse('$baseUrl/chats/'),
        headers: headers,
      );
      
      if (response.statusCode == 200) {
        return List<Map<String, dynamic>>.from(jsonDecode(response.body));
      } else if (response.statusCode == 401) {
        throw Exception('Authentication required. Please login again.');
      } else {
        throw Exception('Failed to load chats: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      if (e.toString().contains('Failed host lookup') || 
          e.toString().contains('Connection refused')) {
        throw Exception('Cannot connect to backend server. Please ensure the backend is running.');
      }
      rethrow;
    }
  }

  // Get regular users (non-admin)
  Future<List<Map<String, dynamic>>> getRegularUsers() async {
    try {
      final users = await getUsers();
      return users.where((user) => 
        user['role'] == 'user'
      ).toList();
    } catch (e) {
      throw Exception('Error fetching users: $e');
    }
  }
}

