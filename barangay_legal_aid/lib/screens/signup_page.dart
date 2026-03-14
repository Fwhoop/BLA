import 'dart:io';
import 'dart:typed_data';

import 'package:barangay_legal_aid/services/auth_service.dart';
import 'package:barangay_legal_aid/services/api_service.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

class SignupPage extends StatefulWidget {
  const SignupPage({super.key});

  @override
  State<SignupPage> createState() => SignupPageState();
}

class SignupPageState extends State<SignupPage> {
  final _formKey = GlobalKey<FormState>();
  final ImagePicker _imagePicker = ImagePicker();

  // Personal info
  final _firstNameCtrl    = TextEditingController();
  final _lastNameCtrl     = TextEditingController();
  final _emailCtrl        = TextEditingController();
  final _passwordCtrl     = TextEditingController();
  final _confirmPassCtrl  = TextEditingController();
  final _phoneCtrl        = TextEditingController();

  // Philippine address
  final _houseNumberCtrl  = TextEditingController();
  final _streetNameCtrl   = TextEditingController();
  final _purokCtrl        = TextEditingController();
  final _cityCtrl         = TextEditingController();
  final _provinceCtrl     = TextEditingController();
  final _zipCodeCtrl      = TextEditingController();

  String? _selectedBarangay;
  bool _isLoading            = false;
  bool _obscurePassword      = true;
  bool _obscureConfirmPass   = true;

  // Photos
  File?      _profilePhotoFile;
  Uint8List? _profilePhotoBytes;
  File?      _idPhotoFile;
  Uint8List? _idPhotoBytes;
  File?      _selfieWithIdFile;
  Uint8List? _selfieWithIdBytes;

  List<Map<String, dynamic>> _barangayItems = [];
  bool _barangaysLoading = true;

  @override
  void initState() {
    super.initState();
    _loadBarangays();
  }

  Future<void> _loadBarangays() async {
    try {
      final api = Provider.of<ApiService>(context, listen: false);
      final items = await api.getBarangays();
      if (mounted) {
        setState(() { _barangayItems = items; _barangaysLoading = false; });
      }
    } catch (_) {
      if (mounted) setState(() => _barangaysLoading = false);
    }
  }

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmPassCtrl.dispose();
    _phoneCtrl.dispose();
    _houseNumberCtrl.dispose();
    _streetNameCtrl.dispose();
    _purokCtrl.dispose();
    _cityCtrl.dispose();
    _provinceCtrl.dispose();
    _zipCodeCtrl.dispose();
    super.dispose();
  }

  // ── Photo picker ────────────────────────────────────────────────────────────

  Future<void> _pickPhoto({
    required String label,
    required void Function(File? file, Uint8List? bytes) onPicked,
  }) async {
    try {
      ImageSource? source;
      if (kIsWeb) {
        source = ImageSource.gallery;
      } else {
        source = await showDialog<ImageSource>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text('Select $label'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.camera_alt, color: Color(0xFF99272D)),
                  title: const Text('Take Photo'),
                  onTap: () => Navigator.pop(ctx, ImageSource.camera),
                ),
                ListTile(
                  leading: const Icon(Icons.photo_library, color: Color(0xFF99272D)),
                  title: const Text('Choose from Gallery'),
                  onTap: () => Navigator.pop(ctx, ImageSource.gallery),
                ),
              ],
            ),
          ),
        );
      }
      if (source == null) return;

      final picked = await _imagePicker.pickImage(
        source: source, maxWidth: 1600, maxHeight: 1600, imageQuality: 85,
      );
      if (picked == null) return;

      if (kIsWeb) {
        final bytes = await picked.readAsBytes();
        onPicked(null, bytes);
      } else {
        onPicked(File(picked.path), null);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('$label selected'),
          backgroundColor: const Color(0xFF36454F),
          duration: const Duration(seconds: 2),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Could not pick photo: $e'),
          backgroundColor: const Color(0xFF99272D),
        ));
      }
    }
  }

  // ── Submit ───────────────────────────────────────────────────────────────────

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) return;

    if (_passwordCtrl.text != _confirmPassCtrl.text) {
      _showError('Passwords do not match');
      return;
    }
    if (_selectedBarangay == null) {
      _showError('Please select your barangay');
      return;
    }
    if (_idPhotoFile == null && _idPhotoBytes == null) {
      _showError('Please upload a photo of your valid government ID');
      return;
    }
    if (_selfieWithIdFile == null && _selfieWithIdBytes == null) {
      _showError('Please upload a selfie holding your ID');
      return;
    }

    setState(() => _isLoading = true);
    try {
      final auth = Provider.of<AuthService>(context, listen: false);
      await auth.signUp(
        firstName: _firstNameCtrl.text.trim(),
        lastName:  _lastNameCtrl.text.trim(),
        email:     _emailCtrl.text.trim(),
        password:  _passwordCtrl.text,
        phone:     _phoneCtrl.text.trim(),
        barangay:  _selectedBarangay!,
        houseNumber: _houseNumberCtrl.text.trim().isEmpty ? null : _houseNumberCtrl.text.trim(),
        streetName:  _streetNameCtrl.text.trim().isEmpty  ? null : _streetNameCtrl.text.trim(),
        purok:       _purokCtrl.text.trim().isEmpty        ? null : _purokCtrl.text.trim(),
        city:        _cityCtrl.text.trim().isEmpty         ? null : _cityCtrl.text.trim(),
        province:    _provinceCtrl.text.trim().isEmpty     ? null : _provinceCtrl.text.trim(),
        zipCode:     _zipCodeCtrl.text.trim().isEmpty      ? null : _zipCodeCtrl.text.trim(),
        // ID photo
        idPhotoPath:  kIsWeb ? 'web_id.jpg'      : (_idPhotoFile?.path ?? ''),
        idPhotoBytes: _idPhotoBytes,
        // Selfie with ID
        selfieWithIdPath:  kIsWeb ? 'web_selfie.jpg'  : (_selfieWithIdFile?.path ?? ''),
        selfieWithIdBytes: _selfieWithIdBytes,
        // Profile photo (optional)
        profilePhotoPath:  kIsWeb ? 'web_profile.jpg' : (_profilePhotoFile?.path ?? ''),
        profilePhotoBytes: _profilePhotoBytes,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Account created! A barangay admin will review and approve your registration.'),
        backgroundColor: Color(0xFF36454F),
        duration: Duration(seconds: 4),
      ));
      await Future.delayed(const Duration(seconds: 2));
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/login');
    } catch (e) {
      if (mounted) {
        _showError(e is Exception
            ? e.toString().replaceFirst('Exception: ', '')
            : 'Registration failed. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: const Color(0xFF99272D),
    ));
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Account'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pushReplacementNamed(context, '/login'),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildHeader(),
                    const SizedBox(height: 28),

                    _sectionLabel('Personal Information', Icons.person_outline),
                    const SizedBox(height: 12),
                    _buildNameRow(),
                    const SizedBox(height: 14),
                    _buildEmailField(),
                    const SizedBox(height: 14),
                    _buildPasswordRow(),
                    const SizedBox(height: 14),
                    _buildPhoneField(),

                    const SizedBox(height: 28),
                    _sectionLabel('Philippine Address', Icons.home_outlined),
                    const SizedBox(height: 12),
                    _buildAddressFields(),

                    const SizedBox(height: 28),
                    _sectionLabel('Barangay', Icons.location_on_outlined),
                    const SizedBox(height: 12),
                    _buildBarangayDropdown(),

                    const SizedBox(height: 28),
                    _sectionLabel('Photo Verification', Icons.verified_user_outlined),
                    const SizedBox(height: 4),
                    const Text(
                      'Required for identity verification. All photos are reviewed only by authorized barangay staff.',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 14),
                    _buildPhotoCard(
                      label: 'Profile Photo',
                      sublabel: 'Optional — shown on your account',
                      icon: Icons.account_circle_outlined,
                      required: false,
                      file: _profilePhotoFile,
                      bytes: _profilePhotoBytes,
                      onTap: () => _pickPhoto(
                        label: 'Profile Photo',
                        onPicked: (f, b) => setState(() { _profilePhotoFile = f; _profilePhotoBytes = b; }),
                      ),
                      onClear: () => setState(() { _profilePhotoFile = null; _profilePhotoBytes = null; }),
                    ),
                    const SizedBox(height: 12),
                    _buildPhotoCard(
                      label: 'Government ID',
                      sublabel: 'Required — front of any valid government-issued ID',
                      icon: Icons.badge_outlined,
                      required: true,
                      file: _idPhotoFile,
                      bytes: _idPhotoBytes,
                      onTap: () => _pickPhoto(
                        label: 'Government ID',
                        onPicked: (f, b) => setState(() { _idPhotoFile = f; _idPhotoBytes = b; }),
                      ),
                      onClear: () => setState(() { _idPhotoFile = null; _idPhotoBytes = null; }),
                    ),
                    const SizedBox(height: 12),
                    _buildPhotoCard(
                      label: 'Selfie Holding ID',
                      sublabel: 'Required — a clear selfie with your ID visible',
                      icon: Icons.camera_front_outlined,
                      required: true,
                      file: _selfieWithIdFile,
                      bytes: _selfieWithIdBytes,
                      onTap: () => _pickPhoto(
                        label: 'Selfie with ID',
                        onPicked: (f, b) => setState(() { _selfieWithIdFile = f; _selfieWithIdBytes = b; }),
                      ),
                      onClear: () => setState(() { _selfieWithIdFile = null; _selfieWithIdBytes = null; }),
                    ),

                    const SizedBox(height: 32),
                    _buildSubmitButton(),
                    const SizedBox(height: 16),
                    _buildLoginLink(),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Section helpers ──────────────────────────────────────────────────────────

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          colors: [Color(0xFF99272D), Color(0xFF36454F)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.gavel, size: 52, color: Colors.white),
          ),
          const SizedBox(height: 14),
          const Text('Barangay Legal Aid',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 6),
          const Text('Create your resident account',
              style: TextStyle(fontSize: 14, color: Colors.white70)),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 18, color: const Color(0xFF99272D)),
        const SizedBox(width: 8),
        Text(text,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Color(0xFF36454F),
            )),
      ],
    );
  }

  Widget _buildNameRow() {
    return Row(
      children: [
        Expanded(child: _textField(_firstNameCtrl, 'First name', Icons.person_outline, required: true)),
        const SizedBox(width: 12),
        Expanded(child: _textField(_lastNameCtrl, 'Last name', Icons.person_outline, required: true)),
      ],
    );
  }

  Widget _buildEmailField() {
    return TextFormField(
      controller: _emailCtrl,
      keyboardType: TextInputType.emailAddress,
      decoration: const InputDecoration(
        labelText: 'Email address',
        hintText: 'you@example.com',
        prefixIcon: Icon(Icons.email_outlined),
      ),
      validator: (v) {
        if (v == null || v.isEmpty) return 'Required';
        if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v)) {
          return 'Enter a valid email';
        }
        return null;
      },
    );
  }

  Widget _buildPasswordRow() {
    return Row(
      children: [
        Expanded(
          child: TextFormField(
            controller: _passwordCtrl,
            obscureText: _obscurePassword,
            decoration: InputDecoration(
              labelText: 'Password',
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                icon: Icon(_obscurePassword ? Icons.visibility : Icons.visibility_off),
                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
              ),
            ),
            validator: (v) {
              if (v == null || v.isEmpty) return 'Required';
              if (v.length < 6) return 'Min 6 characters';
              return null;
            },
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: TextFormField(
            controller: _confirmPassCtrl,
            obscureText: _obscureConfirmPass,
            decoration: InputDecoration(
              labelText: 'Confirm password',
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                icon: Icon(_obscureConfirmPass ? Icons.visibility : Icons.visibility_off),
                onPressed: () => setState(() => _obscureConfirmPass = !_obscureConfirmPass),
              ),
            ),
            validator: (v) {
              if (v == null || v.isEmpty) return 'Required';
              return null;
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPhoneField() {
    return TextFormField(
      controller: _phoneCtrl,
      keyboardType: TextInputType.phone,
      decoration: const InputDecoration(
        labelText: 'Mobile number',
        hintText: '09XXXXXXXXX',
        prefixIcon: Icon(Icons.phone_outlined),
      ),
      validator: (v) {
        if (v == null || v.isEmpty) return 'Required';
        if (v.length < 10) return 'Enter a valid phone number';
        return null;
      },
    );
  }

  Widget _buildAddressFields() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              flex: 2,
              child: _textField(_houseNumberCtrl, 'House / Unit No.', Icons.house_outlined),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 3,
              child: _textField(_streetNameCtrl, 'Street name', Icons.edit_road_outlined),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _textField(_purokCtrl, 'Purok / Zone (optional)', Icons.map_outlined)),
            const SizedBox(width: 12),
            Expanded(child: _textField(_cityCtrl, 'City / Municipality', Icons.location_city_outlined)),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _textField(_provinceCtrl, 'Province', Icons.terrain_outlined)),
            const SizedBox(width: 12),
            Expanded(child: _textField(_zipCodeCtrl, 'ZIP code (optional)', Icons.markunread_mailbox_outlined)),
          ],
        ),
      ],
    );
  }

  Widget _textField(
    TextEditingController ctrl,
    String label,
    IconData icon, {
    bool required = false,
  }) {
    return TextFormField(
      controller: ctrl,
      decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon)),
      validator: required
          ? (v) => (v == null || v.isEmpty) ? 'Required' : null
          : null,
    );
  }

  Widget _buildBarangayDropdown() {
    if (_barangaysLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: 12),
            Text('Loading barangays…', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }
    if (_barangayItems.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text(
          'No barangays available. Please contact your administrator.',
          style: TextStyle(color: Colors.red, fontSize: 13),
        ),
      );
    }
    return DropdownButtonFormField<String>(
      initialValue: _selectedBarangay,
      decoration: const InputDecoration(
        labelText: 'Select barangay',
        prefixIcon: Icon(Icons.location_on_outlined),
      ),
      items: _barangayItems.map((b) {
        final name = b['name'] as String? ?? '';
        return DropdownMenuItem<String>(value: name, child: Text(name));
      }).toList(),
      onChanged: (v) => setState(() => _selectedBarangay = v),
      validator: (v) => (v == null || v.isEmpty) ? 'Please select your barangay' : null,
    );
  }

  Widget _buildPhotoCard({
    required String label,
    required String sublabel,
    required IconData icon,
    required bool required,
    required File? file,
    required Uint8List? bytes,
    required VoidCallback onTap,
    required VoidCallback onClear,
  }) {
    final hasPhoto = file != null || bytes != null;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: (required && !hasPhoto) ? const Color(0xFF99272D) : Colors.grey.shade300,
        ),
        color: Colors.white,
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: const Color(0xFF99272D)),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(label,
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                        if (required) ...[
                          const SizedBox(width: 4),
                          const Text('*', style: TextStyle(color: Color(0xFF99272D))),
                        ],
                      ],
                    ),
                    Text(sublabel,
                        style: const TextStyle(fontSize: 11, color: Colors.grey)),
                  ],
                ),
              ),
              if (hasPhoto)
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Color(0xFF99272D), size: 20),
                  onPressed: _isLoading ? null : onClear,
                  tooltip: 'Remove',
                ),
            ],
          ),
          if (hasPhoto) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: kIsWeb && bytes != null
                  ? Image.memory(bytes, height: 140, width: double.infinity, fit: BoxFit.cover)
                  : file != null
                      ? Image.file(file, height: 140, width: double.infinity, fit: BoxFit.cover)
                      : const SizedBox.shrink(),
            ),
          ],
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _isLoading ? null : onTap,
              icon: Icon(hasPhoto ? Icons.refresh : Icons.upload_file, size: 18),
              label: Text(hasPhoto ? 'Replace' : 'Upload Photo'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubmitButton() {
    return ElevatedButton(
      onPressed: _isLoading ? null : _submitForm,
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: _isLoading
          ? const SizedBox(
              height: 20, width: 20,
              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
            )
          : const Text('Create Account', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildLoginLink() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text('Already have an account?'),
        TextButton(
          onPressed: () => Navigator.pushReplacementNamed(context, '/login'),
          child: const Text('Sign In', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}
