import 'dart:convert';
import 'dart:io';

import 'package:barangay_legal_aid/models/user_model.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  final Map<String, Map<String, dynamic>> _demoUsers = {
    'user@legalaid.com': {
      'password': 'password123',
      'firstName': 'Juan',
      'lastName': 'Dela Cruz',
      'role': UserRole.user,
      'barangay': 'Barangay 1',
      'phone': '09123456789',
      'address': '123 Main Street'
    },
    'admin@legalaid.com': {
      'password': 'admin123',
      'firstName': 'Maria',
      'lastName': 'Santos',
      'role': UserRole.admin,
      'barangay': 'Barangay 1',
      'phone': '09123456788',
      'address': '456 Admin Avenue'
    },
    'superadmin@legalaid.com': {
      'password': 'super123',
      'firstName': 'Pedro',
      'lastName': 'Reyes',
      'role': UserRole.superadmin,
      'barangay': 'System',
      'phone': '09123456777',
      'address': '789 System Road'
    },
    'test@legalaid.com': {
      'password': 'test123',
      'firstName': 'Test',
      'lastName': 'User',
      'role': UserRole.user,
      'barangay': 'Barangay 2',
      'phone': '09123456766',
      'address': '321 Test Street'
    },
  };

  Future<bool> signUp({
    required String firstName,
    required String lastName,
    required String email,
    required String password,
    required String phone,
    required String address,
    required String barangay,
    required String idPhotoPath,
  }) async {
    await Future.delayed(Duration(seconds: 2));

    final prefs = await SharedPreferences.getInstance();
    
    if (_demoUsers.containsKey(email) || await _isEmailRegistered(prefs, email)) {
      throw Exception('Email already registered');
    }

    await prefs.setString('firstName', firstName);
    await prefs.setString('lastName', lastName);
    await prefs.setString('email', email);
    await prefs.setString('phone', phone);
    await prefs.setString('address', address);
    await prefs.setString('barangay', barangay);
    await prefs.setString('password', password);
    await prefs.setString('role', UserRole.user.toString().split('.').last);
    await prefs.setBool('isLoggedIn', true);
    await prefs.setString('lastLogin', DateTime.now().toString());
    await _storeIdPhoto(prefs, idPhotoPath);
    await prefs.setBool('idPhotoApproved', false);

    return true;
  }

  Future<void> _storeIdPhoto(SharedPreferences prefs, String idPhotoPath) async {
    final file = File(idPhotoPath);
    if (!await file.exists()) {
      throw Exception('ID photo file not found. Please try again.');
    }
    final bytes = await file.readAsBytes();
    final base64Photo = base64Encode(bytes);
    await prefs.setString('idPhotoBase64', base64Photo);
    await prefs.setString('idPhotoFilename', p.basename(idPhotoPath));
  }

  Future<bool> _isEmailRegistered(SharedPreferences prefs, String email) async {
    final storedEmail = prefs.getString('email');
    return storedEmail == email || _demoUsers.containsKey(email);
  }

  Future<User?> login({
    required String email,
    required String password,
    required bool rememberMe,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    
    try {
      // backend login
      final loginUrl = Uri.parse('http://127.0.0.1:8000/auth/login');
      final loginResponse = await http.post(
        loginUrl,
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: 'username=${Uri.encodeComponent(email)}&password=${Uri.encodeComponent(password)}',
      );

      if (loginResponse.statusCode == 200) {
        final tokenData = jsonDecode(loginResponse.body);
        final accessToken = tokenData['access_token'] as String;
        
        await prefs.setString('access_token', accessToken);
        
        // Get user info
        try {
          final userUrl = Uri.parse('http://127.0.0.1:8000/auth/me');
          final userResponse = await http.get(
            userUrl,
            headers: {
              'Authorization': 'Bearer $accessToken',
              'Content-Type': 'application/json',
            },
          );

          if (userResponse.statusCode == 200) {
            final userData = jsonDecode(userResponse.body);
            final user = User(
              id: userData['id'].toString(),
              email: userData['email'] ?? email,
              firstName: userData['first_name'] ?? '',
              lastName: userData['last_name'] ?? '',
              role: _getRoleFromString(userData['role'] ?? 'user'),
              barangay: userData['barangay_id']?.toString() ?? 'Barangay 1',
              createdAt: DateTime.now(),
            );
            
            await _setLoginState(prefs, user, rememberMe);
            return user;
          }
        } catch (e) {
          print('Error fetching user info: $e');
        }
        
        
        final user = User(
          id: email.hashCode.toString(),
          email: email,
          firstName: email.split('@')[0],
          lastName: '',
          role: UserRole.user,
          barangay: 'Barangay 1',
          createdAt: DateTime.now(),
        );
        
        await _setLoginState(prefs, user, rememberMe);
        return user;
      } else {
        final errorBody = loginResponse.body;
        print('Backend login failed: ${loginResponse.statusCode} - $errorBody');
        if (loginResponse.statusCode == 401) {
          throw Exception('Invalid email or password. Please check your credentials or create an account in the backend.');
        }
        return _tryDemoLogin(email, password, rememberMe, prefs);
      }
    } catch (e) {
      print('Backend login error: $e');
      if (e.toString().contains('Failed host lookup') || 
          e.toString().contains('Connection refused') ||
          e.toString().contains('Network is unreachable')) {
        print('Backend unavailable, using demo login');
        return _tryDemoLogin(email, password, rememberMe, prefs);
      }
      rethrow;
    }
  }

  Future<User?> _tryDemoLogin(String email, String password, bool rememberMe, SharedPreferences prefs) async {
    if (_demoUsers.containsKey(email) && _demoUsers[email]!['password'] == password) {
      final userData = _demoUsers[email]!;
      final user = User(
        id: email.hashCode.toString(),
        email: email,
        firstName: userData['firstName'] as String,
        lastName: userData['lastName'] as String,
        role: userData['role'] as UserRole,
        barangay: userData['barangay'] as String,
        createdAt: DateTime.now(),
      );
      
      await prefs.remove('access_token');
      await _setLoginState(prefs, user, rememberMe);
      print(' Demo login - backend features will not be available');
      return user;
    }

    final storedEmail = prefs.getString('email');
    final storedPassword = prefs.getString('password');
    
    if (storedEmail == email && storedPassword == password) {
      final user = User(
        id: storedEmail!.hashCode.toString(),
        email: storedEmail,
        firstName: prefs.getString('firstName') ?? 'User',
        lastName: prefs.getString('lastName') ?? '',
        role: _getRoleFromString(prefs.getString('role') ?? 'user'),
        barangay: prefs.getString('barangay') ?? 'Barangay 1',
        createdAt: DateTime.now(),
      );
      
      await prefs.remove('access_token');
      await _setLoginState(prefs, user, rememberMe);
      print(' Stored user login - backend features will not be available');
      return user;
    }

    return null;
  }

  Future<void> _setLoginState(SharedPreferences prefs, User user, bool rememberMe) async {
    await prefs.setBool('isLoggedIn', true);
    await prefs.setBool('rememberMe', rememberMe);
    await prefs.setString('lastLogin', DateTime.now().toString());
    await prefs.setString('currentUserEmail', user.email);
    await prefs.setString('currentUserRole', user.role.toString().split('.').last);
    await prefs.setString('currentUserId', user.id);
  }

  Future<User?> getCurrentUser() async {
    final prefs = await SharedPreferences.getInstance();
    final isLoggedIn = prefs.getBool('isLoggedIn') ?? false;
    
    if (!isLoggedIn) return null;

    final email = prefs.getString('currentUserEmail') ?? prefs.getString('email');
    if (email == null) return null;

    if (_demoUsers.containsKey(email)) {
      final userData = _demoUsers[email]!;
      return User(
        id: email.hashCode.toString(),
        email: email,
        firstName: userData['firstName'] as String,
        lastName: userData['lastName'] as String,
        role: userData['role'] as UserRole,
        barangay: userData['barangay'] as String,
        createdAt: DateTime.now(),
      );
    }

    return User(
      id: email.hashCode.toString(),
      email: email,
      firstName: prefs.getString('firstName') ?? 'User',
      lastName: prefs.getString('lastName') ?? '',
      role: _getRoleFromString(prefs.getString('currentUserRole') ?? prefs.getString('role') ?? 'user'),
      barangay: prefs.getString('barangay') ?? 'Barangay 1',
      createdAt: DateTime.now(),
    );
  }

  Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    final isLoggedIn = prefs.getBool('isLoggedIn') ?? false;
    final rememberMe = prefs.getBool('rememberMe') ?? false;
    
    if (rememberMe && isLoggedIn) {
      return true;
    }
    
    final lastLogin = prefs.getString('lastLogin');
    if (lastLogin != null) {
      final lastLoginDate = DateTime.parse(lastLogin);
      final difference = DateTime.now().difference(lastLoginDate);
      
      if (difference.inDays < 7) {
        return isLoggedIn;
      }
    }
    
    await prefs.setBool('isLoggedIn', false);
    return false;
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
    final prefs = await SharedPreferences.getInstance();
    final rememberMe = prefs.getBool('rememberMe') ?? false;
    
    if (!rememberMe) {
      await prefs.setBool('isLoggedIn', false);
      await prefs.remove('lastLogin');
      await prefs.remove('currentUserEmail');
      await prefs.remove('currentUserRole');
      await prefs.remove('currentUserId');
    }
    await prefs.remove('access_token');
  }

  Future<Map<String, String>> getUserData() async {
    final prefs = await SharedPreferences.getInstance();
    final user = await getCurrentUser();
    
    if (user != null) {
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

  Future<bool> hasUserRegistered() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('email') != null;
  }

  Future<void> clearAllData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }

  Future<bool> updateProfile({
    String? firstName,
    String? lastName,
    String? phone,
    String? address,
    String? barangay,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    
    try {
      if (firstName != null) await prefs.setString('firstName', firstName);
      if (lastName != null) await prefs.setString('lastName', lastName);
      if (phone != null) await prefs.setString('phone', phone);
      if (address != null) await prefs.setString('address', address);
      if (barangay != null) await prefs.setString('barangay', barangay);
      
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> changePassword(String currentPassword, String newPassword) async {
    final prefs = await SharedPreferences.getInstance();
    final storedPassword = prefs.getString('password');
    
    if (storedPassword == currentPassword) {
      await prefs.setString('password', newPassword);
      return true;
    }
    
    return false;
  }

  UserRole _getRoleFromString(String roleString) {
    switch (roleString) {
      case 'admin':
        return UserRole.admin;
      case 'superadmin':
        return UserRole.superadmin;
      default:
        return UserRole.user;
    }
  }

  List<User> getDemoUsers() {
    return _demoUsers.entries.map((entry) {
      final email = entry.key;
      final userData = entry.value;
      return User(
        id: email.hashCode.toString(),
        email: email,
        firstName: userData['firstName'] as String,
        lastName: userData['lastName'] as String,
        role: userData['role'] as UserRole,
        barangay: userData['barangay'] as String,
        createdAt: DateTime.now(),
      );
    }).toList();
  }

  List<User> getUsersByBarangay(String barangay) {
    return getDemoUsers().where((user) => user.barangay == barangay).toList();
  }

  List<User> getAdmins() {
    return getDemoUsers().where((user) => user.isAdmin).toList();
  }

  Future<bool> createAdmin({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
    required String barangay,
  }) async {
    await Future.delayed(Duration(seconds: 1));
    
    return true;
  }
}