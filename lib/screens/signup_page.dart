import 'dart:typed_data';

import 'package:barangay_legal_aid/screens/otp_verification_screen.dart';
import 'package:barangay_legal_aid/services/auth_service.dart';
import 'package:barangay_legal_aid/services/api_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

const _kPrimary  = Color(0xFF99272D);
const _kCharcoal = Color(0xFF36454F);

class SignupPage extends StatefulWidget {
  const SignupPage({super.key});

  @override
  State<SignupPage> createState() => SignupPageState();
}

class SignupPageState extends State<SignupPage> {
  final _formKey = GlobalKey<FormState>();
  final ImagePicker _imagePicker = ImagePicker();

  final TextEditingController _firstNameController    = TextEditingController();
  final TextEditingController _lastNameController     = TextEditingController();
  final TextEditingController _emailController        = TextEditingController();
  final TextEditingController _passwordController     = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();
  final TextEditingController _phoneController        = TextEditingController();
  final TextEditingController _addressController      = TextEditingController();

  String? _selectedBarangay;
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  // Three required photos
  Uint8List? _selfieBytes;       // → profile_photo (selfie)
  Uint8List? _idPhotoBytes;      // → id_photo      (valid ID)
  Uint8List? _selfieWithIdBytes; // → selfie_with_id (selfie holding ID)

  String _role = 'user';               // 'user' or 'admin'
  String _verificationMethod = 'email'; // only shown when both email+phone are filled

  // Tracks whether the fields have content (for smart verification selector)
  bool _hasEmail = false;
  bool _hasPhone = false;

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
      if (mounted) setState(() { _barangayItems = items; _barangaysLoading = false; });
    } catch (_) {
      if (mounted) setState(() => _barangaysLoading = false);
    }
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto({required void Function(Uint8List) onPicked}) async {
    try {
      final file = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 85,
      );
      if (file != null) {
        final bytes = await file.readAsBytes();
        setState(() => onPicked(bytes));
      }
    } catch (e) {
      if (mounted) _showError('Unable to pick photo: $e');
    }
  }

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) return;

    final email = _emailController.text.trim();
    final phone = _phoneController.text.trim();

    // Cross-field: at least one contact required
    if (email.isEmpty && phone.isEmpty) {
      _showError('Please provide at least an email address or phone number.');
      return;
    }

    if (_passwordController.text != _confirmPasswordController.text) {
      _showError('Passwords do not match.');
      return;
    }
    if (_selectedBarangay == null) {
      _showError('Please select your barangay.');
      return;
    }
    if (_selfieBytes == null) {
      _showError('Please upload your selfie photo.');
      return;
    }
    if (_idPhotoBytes == null) {
      _showError('Please upload your valid ID photo.');
      return;
    }
    if (_selfieWithIdBytes == null) {
      _showError('Please upload your selfie holding your ID.');
      return;
    }

    await _createAccount();
  }

  Future<void> _createAccount() async {
    setState(() => _isLoading = true);

    final email = _emailController.text.trim();
    final phone = _phoneController.text.trim();

    // Determine verification method automatically when only one contact given
    String method = _verificationMethod;
    if (email.isNotEmpty && phone.isEmpty) method = 'email';
    if (phone.isNotEmpty && email.isEmpty) method = 'phone';

    try {
      final idPhotoPath = 'id_${DateTime.now().millisecondsSinceEpoch}.jpg';

      final auth = Provider.of<AuthService>(context, listen: false);
      final api  = Provider.of<ApiService>(context, listen: false);

      await auth.signUp(
        firstName:         _firstNameController.text.trim(),
        lastName:          _lastNameController.text.trim(),
        email:             email,
        password:          _passwordController.text,
        phone:             phone,
        address:           _addressController.text.trim(),
        barangay:          _selectedBarangay!,
        idPhotoPath:       idPhotoPath,
        idPhotoBytes:      _idPhotoBytes,
        selfiePhotoBytes:  _selfieBytes,
        selfieWithIdBytes: _selfieWithIdBytes,
        role:              _role,
      );

      if (!mounted) return;

      if (method == 'email' && email.isNotEmpty) {
        final res = await api.sendEmailOtp(email);
        final userId = res['user_id'] as int?;
        if (!mounted) return;
        if (userId != null) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => OtpVerificationScreen(userId: userId, email: email),
            ),
          );
          return;
        }
      } else if (method == 'phone' && phone.isNotEmpty) {
        if (kIsWeb) {
          _showError('Phone SMS verification is not supported on the web. Please use Email OTP.');
          setState(() => _isLoading = false);
          return;
        }
        await FirebaseAuth.instance.verifyPhoneNumber(
          phoneNumber: phone,
          verificationCompleted: (PhoneAuthCredential cred) async {
            final userCred = await FirebaseAuth.instance.signInWithCredential(cred);
            final idToken  = await userCred.user!.getIdToken();
            final res = await api.sendEmailOtp(email).catchError((_) => <String, dynamic>{});
            final uid = res['user_id'] as int?;
            if (uid != null && idToken != null) {
              await api.verifyFirebasePhone(uid, idToken);
            }
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('Phone verified! Awaiting admin approval.'),
                backgroundColor: _kCharcoal,
              ));
              Navigator.pushReplacementNamed(context, '/login');
            }
          },
          verificationFailed: (FirebaseAuthException e) {
            if (mounted) _showError(e.message ?? 'Phone verification failed.');
          },
          codeSent: (String verificationId, int? _) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('SMS code sent! Application submitted — await admin approval.'),
                backgroundColor: _kCharcoal,
                duration: Duration(seconds: 5),
              ));
              Navigator.pushReplacementNamed(context, '/login');
            }
          },
          codeAutoRetrievalTimeout: (_) {},
        );
        return;
      }

      // Fallback — no OTP triggered
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Application submitted! An admin will review your photos for approval.'),
        backgroundColor: _kCharcoal,
        duration: Duration(seconds: 3),
      ));
      await Future.delayed(const Duration(seconds: 2));
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/login');
    } catch (e) {
      if (mounted) {
        _showError(e is Exception
            ? e.toString().replaceFirst('Exception: ', '')
            : 'Signup failed. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: _kPrimary),
    );
  }

  // ── Build ───────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      appBar: AppBar(
        title: const Text('Create Account'),
        backgroundColor: _kPrimary,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pushReplacementNamed(context, '/login'),
          tooltip: 'Back to Login',
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildHeader(),
                    const SizedBox(height: 24),

                    // ── Section 1: Identity ──────────────────────────────
                    _sectionLabel('Identity'),
                    const SizedBox(height: 10),
                    _buildNameFields(),

                    const SizedBox(height: 20),

                    // ── Section 2: Contact ───────────────────────────────
                    _sectionLabel('Contact', sub: 'At least one is required'),
                    const SizedBox(height: 10),
                    _buildEmailField(),
                    const SizedBox(height: 12),
                    _buildPhoneField(),

                    const SizedBox(height: 20),

                    // ── Section 3: Password ──────────────────────────────
                    _sectionLabel('Password'),
                    const SizedBox(height: 10),
                    _buildPasswordField(),
                    const SizedBox(height: 12),
                    _buildConfirmPasswordField(),

                    const SizedBox(height: 20),

                    // ── Section 4: Location ──────────────────────────────
                    _sectionLabel('Location'),
                    const SizedBox(height: 10),
                    _buildAddressField(),
                    const SizedBox(height: 12),
                    _buildBarangayDropdown(),

                    const SizedBox(height: 20),

                    // ── Section 5: Photo Verification ────────────────────
                    _sectionLabel('Photo Verification',
                        sub: 'All three photos are required for identity verification'),
                    const SizedBox(height: 10),
                    _buildPhotoUploader(
                      label: 'Your Selfie',
                      hint: 'Take a clear selfie facing forward. This will be your profile photo.',
                      icon: Icons.face_rounded,
                      bytes: _selfieBytes,
                      onPick: () => _pickPhoto(onPicked: (b) => _selfieBytes = b),
                      onRemove: () => setState(() => _selfieBytes = null),
                    ),
                    const SizedBox(height: 12),
                    _buildPhotoUploader(
                      label: 'Valid ID Photo',
                      hint: 'Government-issued ID: Driver\'s License, PhilHealth, SSS, UMID, Passport, Voter\'s ID, etc.',
                      icon: Icons.badge_outlined,
                      bytes: _idPhotoBytes,
                      onPick: () => _pickPhoto(onPicked: (b) => _idPhotoBytes = b),
                      onRemove: () => setState(() => _idPhotoBytes = null),
                    ),
                    const SizedBox(height: 12),
                    _buildPhotoUploader(
                      label: 'Selfie Holding Your ID',
                      hint: 'Hold your ID next to your face. Admin will use this to verify your identity.',
                      icon: Icons.co_present_rounded,
                      bytes: _selfieWithIdBytes,
                      onPick: () => _pickPhoto(onPicked: (b) => _selfieWithIdBytes = b),
                      onRemove: () => setState(() => _selfieWithIdBytes = null),
                    ),

                    const SizedBox(height: 20),

                    // ── Section 6: Account Type ──────────────────────────
                    _sectionLabel('Account Type'),
                    const SizedBox(height: 4),
                    _buildRoleSelector(),

                    // ── Section 7: Verification Method (smart) ───────────
                    if (_hasEmail && _hasPhone) ...[
                      const SizedBox(height: 8),
                      _sectionLabel('Verification Method',
                          sub: 'You provided both email and phone — choose one to verify now'),
                      const SizedBox(height: 4),
                      _buildVerificationMethodSelector(),
                    ],

                    const SizedBox(height: 24),

                    // ── Section 8: Submit ────────────────────────────────
                    _buildSignupButton(),
                    const SizedBox(height: 16),
                    _buildLoginLink(),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Section label ──────────────────────────────────────────────────────────
  Widget _sectionLabel(String title, {String? sub}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: _kPrimary,
              letterSpacing: 0.6,
            )),
        if (sub != null) ...[
          const SizedBox(height: 2),
          Text(sub,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        ],
        const SizedBox(height: 4),
        Container(height: 1.5, color: _kPrimary.withValues(alpha: 0.12)),
      ],
    );
  }

  // ── Header card ────────────────────────────────────────────────────────────
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [_kPrimary, Color(0xFF6B1A1E)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.gavel, size: 36, color: Colors.white),
          ),
          const SizedBox(width: 16),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Barangay Legal Aid',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                SizedBox(height: 4),
                Text('Create your account',
                    style: TextStyle(fontSize: 13, color: Colors.white70)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Name row ───────────────────────────────────────────────────────────────
  Widget _buildNameFields() {
    return Row(
      children: [
        Expanded(
          child: TextFormField(
            controller: _firstNameController,
            decoration: const InputDecoration(
              labelText: 'First name',
              prefixIcon: Icon(Icons.person_outline),
            ),
            validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: TextFormField(
            controller: _lastNameController,
            decoration: const InputDecoration(
              labelText: 'Last name',
              prefixIcon: Icon(Icons.person_outline),
            ),
            validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
          ),
        ),
      ],
    );
  }

  // ── Email ──────────────────────────────────────────────────────────────────
  Widget _buildEmailField() {
    return TextFormField(
      controller: _emailController,
      keyboardType: TextInputType.emailAddress,
      onChanged: (v) => setState(() => _hasEmail = v.trim().isNotEmpty),
      decoration: const InputDecoration(
        labelText: 'Email address',
        hintText: 'you@example.com',
        prefixIcon: Icon(Icons.email_outlined),
        helperText: 'Optional if phone is provided',
      ),
      validator: (v) {
        if (v == null || v.trim().isEmpty) return null; // optional
        final ok = RegExp(r"^[^@\s]+@[^@\s]+\.[^@\s]+$").hasMatch(v.trim());
        return ok ? null : 'Enter a valid email address';
      },
    );
  }

  // ── Phone ──────────────────────────────────────────────────────────────────
  Widget _buildPhoneField() {
    return TextFormField(
      controller: _phoneController,
      keyboardType: TextInputType.phone,
      onChanged: (v) => setState(() => _hasPhone = v.trim().isNotEmpty),
      decoration: const InputDecoration(
        labelText: 'Phone number',
        hintText: '+639XXXXXXXXX',
        prefixIcon: Icon(Icons.phone_outlined),
        helperText: 'Optional if email is provided. Use +63 format.',
      ),
      validator: (v) {
        if (v == null || v.trim().isEmpty) return null; // optional
        if (v.trim().length < 10) return 'Enter a valid phone number';
        return null;
      },
    );
  }

  // ── Password ───────────────────────────────────────────────────────────────
  Widget _buildPasswordField() {
    return TextFormField(
      controller: _passwordController,
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
        if (v == null || v.isEmpty) return 'Please enter a password';
        if (v.length < 6) return 'Minimum 6 characters';
        return null;
      },
    );
  }

  Widget _buildConfirmPasswordField() {
    return TextFormField(
      controller: _confirmPasswordController,
      obscureText: _obscureConfirmPassword,
      decoration: InputDecoration(
        labelText: 'Confirm Password',
        prefixIcon: const Icon(Icons.lock_outline),
        suffixIcon: IconButton(
          icon: Icon(_obscureConfirmPassword ? Icons.visibility : Icons.visibility_off),
          onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
        ),
      ),
      validator: (v) => (v == null || v.isEmpty) ? 'Please confirm your password' : null,
    );
  }

  // ── Address ────────────────────────────────────────────────────────────────
  Widget _buildAddressField() {
    return TextFormField(
      controller: _addressController,
      decoration: const InputDecoration(
        labelText: 'Complete address',
        prefixIcon: Icon(Icons.home_outlined),
      ),
      validator: (v) => (v == null || v.isEmpty) ? 'Please enter your address' : null,
    );
  }

  // ── Barangay ───────────────────────────────────────────────────────────────
  Widget _buildBarangayDropdown() {
    if (_barangaysLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Row(children: [
          SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
          SizedBox(width: 12),
          Text('Loading barangays…', style: TextStyle(color: Colors.grey)),
        ]),
      );
    }
    if (_barangayItems.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text('No barangays available. Please contact your administrator.',
            style: TextStyle(color: Colors.red, fontSize: 13)),
      );
    }
    return DropdownButtonFormField<String>(
      value: _selectedBarangay,
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

  // ── Reusable photo uploader ────────────────────────────────────────────────
  Widget _buildPhotoUploader({
    required String label,
    required String hint,
    required IconData icon,
    required Uint8List? bytes,
    required VoidCallback onPick,
    required VoidCallback onRemove,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: bytes == null ? _kPrimary.withValues(alpha: 0.4) : Colors.green.shade400,
          width: bytes == null ? 1.0 : 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: bytes != null ? Colors.green.shade600 : _kPrimary),
              const SizedBox(width: 8),
              Text(label,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: bytes != null ? Colors.green.shade700 : _kCharcoal,
                  )),
              if (bytes != null) ...[
                const SizedBox(width: 6),
                Icon(Icons.check_circle_rounded, size: 16, color: Colors.green.shade500),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Text(hint, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          const SizedBox(height: 10),
          if (bytes != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.memory(bytes, height: 140, width: double.infinity, fit: BoxFit.cover),
            ),
            const SizedBox(height: 8),
          ],
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _isLoading ? null : onPick,
                  icon: Icon(bytes == null ? Icons.upload_file : Icons.swap_horiz_rounded, size: 16),
                  label: Text(bytes == null ? 'Upload Photo' : 'Replace Photo',
                      style: const TextStyle(fontSize: 13)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    foregroundColor: _kPrimary,
                    side: const BorderSide(color: _kPrimary),
                  ),
                ),
              ),
              if (bytes != null) ...[
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _isLoading ? null : onRemove,
                  icon: const Icon(Icons.delete_outline, color: _kPrimary),
                  tooltip: 'Remove photo',
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  // ── Role selector ──────────────────────────────────────────────────────────
  Widget _buildRoleSelector() {
    return Row(
      children: [
        Expanded(
          child: RadioListTile<String>(
            title: const Text('Resident', style: TextStyle(fontSize: 14)),
            value: 'user',
            groupValue: _role,
            activeColor: _kPrimary,
            contentPadding: EdgeInsets.zero,
            onChanged: (v) => setState(() => _role = v!),
          ),
        ),
        Expanded(
          child: RadioListTile<String>(
            title: const Text('Barangay Admin', style: TextStyle(fontSize: 14)),
            value: 'admin',
            groupValue: _role,
            activeColor: _kPrimary,
            contentPadding: EdgeInsets.zero,
            onChanged: (v) => setState(() => _role = v!),
          ),
        ),
      ],
    );
  }

  // ── Verification method (only shown when both email+phone are filled) ───────
  Widget _buildVerificationMethodSelector() {
    return Row(
      children: [
        Expanded(
          child: RadioListTile<String>(
            title: const Text('Email OTP', style: TextStyle(fontSize: 14)),
            value: 'email',
            groupValue: _verificationMethod,
            activeColor: _kPrimary,
            contentPadding: EdgeInsets.zero,
            onChanged: (v) => setState(() => _verificationMethod = v!),
          ),
        ),
        Expanded(
          child: RadioListTile<String>(
            title: const Text('Phone SMS', style: TextStyle(fontSize: 14)),
            value: 'phone',
            groupValue: _verificationMethod,
            activeColor: _kPrimary,
            contentPadding: EdgeInsets.zero,
            onChanged: (v) => setState(() => _verificationMethod = v!),
          ),
        ),
      ],
    );
  }

  // ── Submit button ──────────────────────────────────────────────────────────
  Widget _buildSignupButton() {
    return ElevatedButton(
      onPressed: _isLoading ? null : _submitForm,
      style: ElevatedButton.styleFrom(
        backgroundColor: _kPrimary,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: _isLoading
          ? const SizedBox(
              height: 20, width: 20,
              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
            )
          : const Text('Create Account', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
    );
  }

  // ── Login link ─────────────────────────────────────────────────────────────
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
