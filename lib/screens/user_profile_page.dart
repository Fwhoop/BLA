import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:barangay_legal_aid/services/auth_service.dart';
import 'package:barangay_legal_aid/services/api_service.dart';
import 'package:barangay_legal_aid/models/user_model.dart';
import 'package:barangay_legal_aid/widgets/bla_app_bar.dart';

class UserProfilePage extends StatefulWidget {
  const UserProfilePage({super.key});

  @override
  State<UserProfilePage> createState() => UserProfilePageState();
}

class UserProfilePageState extends State<UserProfilePage> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _currentPasswordController = TextEditingController();
  final TextEditingController _newPasswordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();

  String? _selectedBarangay;
  bool _isLoading = false;
  bool _isEditing = false;
  bool _isChangingPassword = false;
  bool _obscureCurrentPassword = true;
  bool _obscureNewPassword = true;
  bool _obscureConfirmPassword = true;
  User? _currentUser;
  Map<String, dynamic>? _stats;
  bool _statsLoading = false;
  String? _statsError;

  final List<String> _barangays = [
    'Barangay 1',
    'Barangay 2',
    'Barangay Cabaluay',
    'Barangay Cabatangan',
    'Barangay Culianan',
    'Barangay Mercedes',
    'Barangay Pasonanca',
    'Barangay San Jose Cawa-Cawa',
    'Barangay San Jose Gusu',
    'Barangay San Roque',
    'Barangay Sta. Maria',
    'Barangay Talabaan',
    'Barangay Taluksangay',
    'System',
  ];

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _loadStats();
  }

  Future<void> _loadStats() async {
    if (!mounted) return;
    setState(() { _statsLoading = true; _statsError = null; });
    try {
      final api = Provider.of<ApiService>(context, listen: false);
      final stats = await api.getMyStats();
      if (mounted) setState(() { _stats = stats; _statsLoading = false; });
    } catch (e) {
      if (mounted) setState(() { _statsError = e.toString().replaceFirst('Exception: ', ''); _statsLoading = false; });
    }
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _loadUserData() async {
    try {
      final auth = Provider.of<AuthService>(context, listen: false);
      final user = await auth.getCurrentUser();
      final userData = await auth.getUserData();
      
      if (mounted) {
        setState(() {
          _currentUser = user;
          _firstNameController.text = userData['firstName'] ?? '';
          _lastNameController.text = userData['lastName'] ?? '';
          _emailController.text = userData['email'] ?? '';
          _phoneController.text = userData['phone'] ?? '';
          _addressController.text = userData['address'] ?? '';
          _selectedBarangay = userData['barangay'] ?? '';
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading user data: $e'),
            backgroundColor: Color(0xFF99272D),
          ),
        );
      }
    }
  }

  Future<void> _updateProfile() async {
    if (_formKey.currentState!.validate()) {
      setState(() => _isLoading = true);

      try {
        final auth = Provider.of<AuthService>(context, listen: false);
        final success = await auth.updateProfile(
          firstName: _firstNameController.text,
          lastName: _lastNameController.text,
          phone: _phoneController.text,
          address: _addressController.text,
          barangay: _selectedBarangay,
        );

        if (success) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Profile updated successfully!'),
              backgroundColor: Color(0xFF36454F),
              duration: Duration(seconds: 3),
            ),
          );
          setState(() => _isEditing = false);
          await _loadUserData();
        } else {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to update profile. Please try again.'),
              backgroundColor: Color(0xFF99272D),
            ),
          );
        }
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating profile: $e'),
            backgroundColor: Color(0xFF99272D),
          ),
        );
      } finally {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _changePassword() async {
    if (_newPasswordController.text != _confirmPasswordController.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('New passwords do not match'),
          backgroundColor: Color(0xFF99272D),
        ),
      );
      return;
    }

    if (_newPasswordController.text.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('New password must be at least 6 characters'),
          backgroundColor: Color(0xFF99272D),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final auth = Provider.of<AuthService>(context, listen: false);
      final success = await auth.changePassword(
        _currentPasswordController.text,
        _newPasswordController.text,
      );

      if (success) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Password changed successfully!'),
            backgroundColor: Color(0xFF36454F),
            duration: Duration(seconds: 3),
          ),
        );
        setState(() => _isChangingPassword = false);
        _currentPasswordController.clear();
        _newPasswordController.clear();
        _confirmPasswordController.clear();
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Current password is incorrect'),
            backgroundColor: Color(0xFF99272D),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error changing password: $e'),
          backgroundColor: Color(0xFF99272D),
        ),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_currentUser == null && !_isLoading) {
      return Scaffold(
        appBar: BlaAppBar(title: 'My Profile'),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 64, color: Color(0xFF99272D)),
              SizedBox(height: 16),
              Text(
                'Unable to load user data',
                style: TextStyle(fontSize: 18, color: Color(0xFF36454F)),
              ),
              SizedBox(height: 8),
              ElevatedButton(
                onPressed: _loadUserData,
                child: Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: BlaAppBar(
        title: 'My Profile',
        user: _currentUser == null ? {} : {
          'first_name': _currentUser!.firstName,
          'last_name': _currentUser!.lastName,
          'role': _currentUser!.role.toString().split('.').last,
          'email': _currentUser!.email,
          'profile_photo_path': '',
        },
        extraActions: [
          if (!_isEditing && !_isChangingPassword)
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () => setState(() => _isEditing = true),
              tooltip: 'Edit Profile',
            ),
        ],
      ),
      body: Container(
        color: Color(0xFFFFFFFF),
        child: _isLoading && _currentUser == null
            ? Center(child: CircularProgressIndicator())
            : Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 860),
                  child: SingleChildScrollView(
                    padding: EdgeInsets.all(20),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildProfileHeader(),
                          SizedBox(height: 24),
                          _buildProfileInfoCard(),
                          SizedBox(height: 20),
                          _buildStatsCard(),
                          SizedBox(height: 20),
                          _buildPasswordCard(),
                          SizedBox(height: 20),
                          _buildActionButtons(),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildProfileHeader() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        padding: EdgeInsets.all(24),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: [Color(0xFF99272D), Color(0xFFCC3A47)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Column(
          children: [
            CircleAvatar(
              radius: 50,
              backgroundColor: Colors.white.withValues(alpha:0.2),
              child: Icon(
                Icons.person,
                size: 50,
                color: Colors.white,
              ),
            ),
            SizedBox(height: 16),
            Text(
              _currentUser?.fullName ?? 'User',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            SizedBox(height: 8),
            Text(
              _currentUser?.roleDisplay ?? 'User',
              style: TextStyle(
                fontSize: 16,
                color: Colors.white.withValues(alpha:0.9),
              ),
            ),
            if (_currentUser?.barangay != null && _currentUser!.barangay.isNotEmpty) ...[
              SizedBox(height: 4),
              Text(
                _currentUser!.barangay,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.white.withValues(alpha:0.8),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildProfileInfoCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.person_outline, color: Color(0xFF99272D)),
                SizedBox(width: 8),
                Text(
                  'Personal Information',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF36454F),
                  ),
                ),
              ],
            ),
            SizedBox(height: 20),
            _buildNameFields(),
            SizedBox(height: 16),
            _buildEmailField(),
            SizedBox(height: 16),
            _buildPhoneField(),
            SizedBox(height: 16),
            _buildAddressField(),
            SizedBox(height: 16),
            _buildBarangayDropdown(),
          ],
        ),
      ),
    );
  }

  Widget _buildPasswordCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.lock_outline, color: Color(0xFF99272D)),
                SizedBox(width: 8),
                Text(
                  'Password Settings',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF36454F),
                  ),
                ),
              ],
            ),
            SizedBox(height: 20),
            if (_isChangingPassword) ...[
              _buildCurrentPasswordField(),
              SizedBox(height: 16),
              _buildNewPasswordField(),
              SizedBox(height: 16),
              _buildConfirmPasswordField(),
              SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        setState(() => _isChangingPassword = false);
                        _currentPasswordController.clear();
                        _newPasswordController.clear();
                        _confirmPasswordController.clear();
                      },
                      child: Text('Cancel'),
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _changePassword,
                      child: _isLoading
                          ? SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : Text('Change Password'),
                    ),
                  ),
                ],
              ),
            ] else
              ElevatedButton.icon(
                onPressed: () => setState(() => _isChangingPassword = true),
                icon: Icon(Icons.edit),
                label: Text('Change Password'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Color(0xFF36454F),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildNameFields() {
    return Row(
      children: [
        Expanded(
          child: TextFormField(
            controller: _firstNameController,
            enabled: _isEditing,
            decoration: InputDecoration(
              labelText: 'First name',
              prefixIcon: Icon(Icons.person_outline),
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Please enter your first name';
              }
              return null;
            },
          ),
        ),
        SizedBox(width: 12),
        Expanded(
          child: TextFormField(
            controller: _lastNameController,
            enabled: _isEditing,
            decoration: InputDecoration(
              labelText: 'Last name',
              prefixIcon: Icon(Icons.person_outline),
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Please enter your last name';
              }
              return null;
            },
          ),
        ),
      ],
    );
  }

  Widget _buildEmailField() {
    return TextFormField(
      controller: _emailController,
      readOnly: true, 
      decoration: InputDecoration(
        labelText: 'Email address',
        prefixIcon: Icon(Icons.email_outlined),
        helperText: 'Email cannot be changed',
      ),
    );
  }

  Widget _buildPhoneField() {
    return TextFormField(
      controller: _phoneController,
      enabled: _isEditing,
      keyboardType: TextInputType.phone,
      decoration: InputDecoration(
        labelText: 'Phone number',
        prefixIcon: Icon(Icons.phone_outlined),
      ),
      validator: (value) {
        if (_isEditing && (value == null || value.isEmpty)) {
          return 'Please enter your phone number';
        }
        if (_isEditing && value != null && value.length < 10) {
          return 'Please enter a valid phone number';
        }
        return null;
      },
    );
  }

  Widget _buildAddressField() {
    return TextFormField(
      controller: _addressController,
      enabled: _isEditing,
      maxLines: 2,
      decoration: InputDecoration(
        labelText: 'Complete address',
        prefixIcon: Icon(Icons.home_outlined),
      ),
      validator: (value) {
        if (_isEditing && (value == null || value.isEmpty)) {
          return 'Please enter your address';
        }
        return null;
      },
    );
  }

  Widget _buildBarangayDropdown() {
    String? validSelectedBarangay = _selectedBarangay;
    if (_selectedBarangay != null && !_barangays.contains(_selectedBarangay)) {
      validSelectedBarangay = null;
    }

    return DropdownButtonFormField<String>(
      initialValue: validSelectedBarangay,
      decoration: InputDecoration(
        labelText: 'Barangay',
        prefixIcon: Icon(Icons.location_on_outlined),
      ),
      items: _barangays.map((String barangay) {
        return DropdownMenuItem<String>(
          value: barangay,
          child: Text(barangay),
        );
      }).toList(),
      onChanged: _isEditing ? (String? newValue) {
        setState(() => _selectedBarangay = newValue);
      } : null,
      validator: (value) {
        if (_isEditing && value == null) {
          return 'Please select your barangay';
        }
        return null;
      },
    );
  }

  Widget _buildCurrentPasswordField() {
    return TextFormField(
      controller: _currentPasswordController,
      obscureText: _obscureCurrentPassword,
      decoration: InputDecoration(
        labelText: 'Current password',
        prefixIcon: Icon(Icons.lock_outline),
        suffixIcon: IconButton(
          icon: Icon(
            _obscureCurrentPassword ? Icons.visibility : Icons.visibility_off,
          ),
          onPressed: () {
            setState(() => _obscureCurrentPassword = !_obscureCurrentPassword);
          },
        ),
      ),
      validator: (value) {
        if (value == null || value.isEmpty) {
          return 'Please enter your current password';
        }
        return null;
      },
    );
  }

  Widget _buildNewPasswordField() {
    return TextFormField(
      controller: _newPasswordController,
      obscureText: _obscureNewPassword,
      decoration: InputDecoration(
        labelText: 'New password',
        prefixIcon: Icon(Icons.lock_outline),
        suffixIcon: IconButton(
          icon: Icon(
            _obscureNewPassword ? Icons.visibility : Icons.visibility_off,
          ),
          onPressed: () {
            setState(() => _obscureNewPassword = !_obscureNewPassword);
          },
        ),
      ),
      validator: (value) {
        if (value == null || value.isEmpty) {
          return 'Please enter a new password';
        }
        if (value.length < 6) {
          return 'Password must be at least 6 characters';
        }
        return null;
      },
    );
  }

  Widget _buildConfirmPasswordField() {
    return TextFormField(
      controller: _confirmPasswordController,
      obscureText: _obscureConfirmPassword,
      decoration: InputDecoration(
        labelText: 'Confirm new password',
        prefixIcon: Icon(Icons.lock_outline),
        suffixIcon: IconButton(
          icon: Icon(
            _obscureConfirmPassword ? Icons.visibility : Icons.visibility_off,
          ),
          onPressed: () {
            setState(() => _obscureConfirmPassword = !_obscureConfirmPassword);
          },
        ),
      ),
      validator: (value) {
        if (value == null || value.isEmpty) {
          return 'Please confirm your new password';
        }
        return null;
      },
    );
  }

  Widget _buildStatsCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.bar_chart, color: Color(0xFF99272D)),
              const SizedBox(width: 8),
              const Text('My Activity', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF36454F))),
            ]),
            const SizedBox(height: 16),
            if (_statsLoading)
              const Center(child: Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: CircularProgressIndicator(color: Color(0xFF99272D)),
              ))
            else if (_statsError != null)
              Column(children: [
                Text(_statsError!, style: const TextStyle(color: Color(0xFF99272D), fontSize: 13), textAlign: TextAlign.center),
                const SizedBox(height: 8),
                TextButton(onPressed: _loadStats, child: const Text('Retry')),
              ])
            else if (_stats != null)
              _buildStatsContent()
            else
              const Text('No activity yet.', style: TextStyle(color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsContent() {
    final s = _stats!;
    final byStatus = (s['complaints_by_status'] as Map<String, dynamic>?) ?? {};
    final reqByStatus = (s['requests_by_status'] as Map<String, dynamic>?) ?? {};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('My Complaints: ${s['complaints_filed_count'] ?? 0}', style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF36454F))),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 4, children: [
          _statsChip('Pending', byStatus['pending'] ?? 0, const Color(0xFFF59E0B)),
          _statsChip('Reviewing', byStatus['reviewing'] ?? 0, const Color(0xFF3B82F6)),
          _statsChip('Resolved', byStatus['resolved'] ?? 0, const Color(0xFF10B981)),
          _statsChip('Dismissed', byStatus['dismissed'] ?? 0, const Color(0xFF6B7280)),
        ]),
        const Divider(height: 24),
        Text('My Requests: ${s['requests_total'] ?? 0}', style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF36454F))),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 4, children: [
          _statsChip('Pending', reqByStatus['pending'] ?? 0, const Color(0xFFF59E0B)),
          _statsChip('Approved', reqByStatus['approved'] ?? 0, const Color(0xFF10B981)),
          _statsChip('Rejected', reqByStatus['rejected'] ?? 0, const Color(0xFF99272D)),
        ]),
      ],
    );
  }

  Widget _statsChip(String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text('$label: $count', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
    );
  }

  Widget _buildActionButtons() {
    if (_isEditing) {
      return Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () {
                setState(() => _isEditing = false);
                _loadUserData(); 
              },
              child: Text('Cancel'),
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: ElevatedButton(
              onPressed: _isLoading ? null : _updateProfile,
              child: _isLoading
                  ? SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : Text('Save Changes'),
            ),
          ),
        ],
      );
    }
    return SizedBox.shrink();
  }
}
