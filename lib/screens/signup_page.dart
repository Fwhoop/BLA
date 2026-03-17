import 'dart:convert';
import 'dart:typed_data';

import 'package:barangay_legal_aid/screens/otp_verification_screen.dart';
import 'package:barangay_legal_aid/screens/phone_sms_verification_screen.dart';
import 'package:barangay_legal_aid/services/auth_service.dart';
import 'package:barangay_legal_aid/services/api_service.dart';
import 'package:barangay_legal_aid/utils/phone_utils.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

const _kPrimary  = Color(0xFF99272D);
const _kCharcoal = Color(0xFF36454F);
const _psgcBase  = 'https://psgc.gitlab.io/api';

class SignupPage extends StatefulWidget {
  const SignupPage({super.key});

  @override
  State<SignupPage> createState() => SignupPageState();
}

class SignupPageState extends State<SignupPage> {
  final _formKey = GlobalKey<FormState>();
  final ImagePicker _imagePicker = ImagePicker();

  final TextEditingController _firstNameController       = TextEditingController();
  final TextEditingController _lastNameController        = TextEditingController();
  final TextEditingController _emailController           = TextEditingController();
  final TextEditingController _passwordController        = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();
  final TextEditingController _phoneController           = TextEditingController();

  // Address text fields
  final TextEditingController _houseNoController         = TextEditingController();
  final TextEditingController _purokController           = TextEditingController();
  final TextEditingController _streetController          = TextEditingController();
  final TextEditingController _zipCodeController         = TextEditingController();

  // Address dropdown selections
  String? _selectedRegionCode;
  String? _selectedProvinceCode;
  String? _selectedCityCode;
  String? _selectedBarangay;
  bool    _noProvinceRegion = false; // true for NCR / regions without provinces

  bool _isLoading            = false;
  bool _obscurePassword      = true;
  bool _obscureConfirmPassword = true;

  // Three required photos
  Uint8List? _selfieBytes;
  Uint8List? _idPhotoBytes;
  Uint8List? _selfieWithIdBytes;

  String _role               = 'user';
  String _verificationMethod = 'email';

  bool _hasEmail = false;
  bool _hasPhone = false;

  // PSGC data
  List<Map<String, dynamic>> _regions      = [];
  List<Map<String, dynamic>> _provinces    = [];
  List<Map<String, dynamic>> _cities       = [];
  List<Map<String, dynamic>> _barangayItems = [];

  bool _regionsLoading   = false;
  bool _provincesLoading = false;
  bool _citiesLoading    = false;
  bool _barangaysLoading = false;

  @override
  void initState() {
    super.initState();
    _loadRegions();
  }

  Future<void> _loadRegions() async {
    if (mounted) setState(() => _regionsLoading = true);
    try {
      final resp = await http.get(Uri.parse('$_psgcBase/regions/'));
      if (resp.statusCode == 200) {
        final list = jsonDecode(resp.body) as List;
        final regions = list
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList()
          ..sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));
        if (mounted) setState(() => _regions = regions);
      }
    } catch (_) {}
    if (mounted) setState(() => _regionsLoading = false);
  }

  Future<void> _onRegionChanged(String code) async {
    setState(() {
      _selectedRegionCode   = code;
      _selectedProvinceCode = null;
      _selectedCityCode     = null;
      _selectedBarangay     = null;
      _provinces            = [];
      _cities               = [];
      _barangayItems        = [];
      _noProvinceRegion     = false;
      _provincesLoading     = true;
    });
    try {
      final resp = await http.get(Uri.parse('$_psgcBase/regions/$code/provinces/'));
      if (resp.statusCode == 200) {
        final list = jsonDecode(resp.body) as List;
        if (list.isEmpty) {
          if (mounted) setState(() { _noProvinceRegion = true; _provincesLoading = false; _citiesLoading = true; });
          final citiesResp = await http.get(Uri.parse('$_psgcBase/regions/$code/cities-municipalities/'));
          if (citiesResp.statusCode == 200) {
            final cityList = jsonDecode(citiesResp.body) as List;
            final cities = cityList
                .map((e) => Map<String, dynamic>.from(e as Map))
                .toList()
              ..sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));
            if (mounted) setState(() => _cities = cities);
          }
          if (mounted) setState(() => _citiesLoading = false);
        } else {
          final provinces = list
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList()
            ..sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));
          if (mounted) setState(() { _provinces = provinces; _provincesLoading = false; });
        }
      } else {
        if (mounted) setState(() => _provincesLoading = false);
      }
    } catch (_) {
      if (mounted) setState(() { _provincesLoading = false; _citiesLoading = false; });
    }
  }

  Future<void> _onProvinceChanged(String code) async {
    setState(() {
      _selectedProvinceCode = code;
      _selectedCityCode     = null;
      _selectedBarangay     = null;
      _cities               = [];
      _barangayItems        = [];
      _citiesLoading        = true;
    });
    try {
      final resp = await http.get(Uri.parse('$_psgcBase/provinces/$code/cities-municipalities/'));
      if (resp.statusCode == 200) {
        final list = jsonDecode(resp.body) as List;
        final cities = list
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList()
          ..sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));
        if (mounted) setState(() => _cities = cities);
      }
    } catch (_) {}
    if (mounted) setState(() => _citiesLoading = false);
  }

  Future<void> _onCityChanged(String code) async {
    setState(() {
      _selectedCityCode  = code;
      _selectedBarangay  = null;
      _barangayItems     = [];
      _barangaysLoading  = true;
    });
    try {
      final resp = await http.get(Uri.parse('$_psgcBase/cities-municipalities/$code/barangays/'));
      if (resp.statusCode == 200) {
        final list = jsonDecode(resp.body) as List;
        final barangays = list
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList()
          ..sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));
        if (mounted) setState(() => _barangayItems = barangays);
      }
    } catch (_) {}
    if (mounted) setState(() => _barangaysLoading = false);
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _phoneController.dispose();
    _houseNoController.dispose();
    _purokController.dispose();
    _streetController.dispose();
    _zipCodeController.dispose();
    super.dispose();
  }

  String _buildFullAddress() {
    final parts = <String>[];
    final houseNo = _houseNoController.text.trim();
    final purok   = _purokController.text.trim();
    final street  = _streetController.text.trim();
    final zip     = _zipCodeController.text.trim();
    if (houseNo.isNotEmpty) parts.add(houseNo);
    if (purok.isNotEmpty)   parts.add(purok);
    if (street.isNotEmpty)  parts.add(street);
    if (_selectedBarangay != null) parts.add(_selectedBarangay!);
    final cityEntry = _cities.where((c) => c['code'] == _selectedCityCode).toList();
    if (cityEntry.isNotEmpty) parts.add(cityEntry.first['name'] as String);
    if (!_noProvinceRegion) {
      final provEntry = _provinces.where((p) => p['code'] == _selectedProvinceCode).toList();
      if (provEntry.isNotEmpty) parts.add(provEntry.first['name'] as String);
    }
    final regEntry = _regions.where((r) => r['code'] == _selectedRegionCode).toList();
    if (regEntry.isNotEmpty) parts.add(regEntry.first['name'] as String);
    if (zip.isNotEmpty) parts.add(zip);
    return parts.join(', ');
  }

  Future<void> _pickPhoto({required void Function(Uint8List) onPicked}) async {
    try {
      final file = await _imagePicker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 85,
      );
      if (file != null) {
        final bytes = await file.readAsBytes();
        setState(() => onPicked(bytes));
      }
    } catch (e) {
      if (mounted) _showError('Unable to open camera: $e');
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
    if (_selectedRegionCode == null) {
      _showError('Please select your region.');
      return;
    }
    if (!_noProvinceRegion && _selectedProvinceCode == null) {
      _showError('Please select your province.');
      return;
    }
    if (_selectedCityCode == null) {
      _showError('Please select your city or municipality.');
      return;
    }
    if (_selectedBarangay == null) {
      _showError('Please select your barangay.');
      return;
    }
    if (_selfieBytes == null) {
      _showError('Please take your selfie photo.');
      return;
    }
    if (_idPhotoBytes == null) {
      _showError('Please take your valid ID photo.');
      return;
    }
    if (_selfieWithIdBytes == null) {
      _showError('Please take your selfie holding your ID.');
      return;
    }

    await _createAccount();
  }

  Future<void> _createAccount() async {
    setState(() => _isLoading = true);

    final email = _emailController.text.trim();
    // Normalize phone to E.164 (+63XXXXXXXXX) so backend lookup and Firebase both work
    final phone = _phoneController.text.trim().isEmpty
        ? ''
        : normalizePhPhone(_phoneController.text.trim());

    // Determine verification method automatically when only one contact given
    String method = _verificationMethod;
    if (email.isNotEmpty && phone.isEmpty) method = 'email';
    if (phone.isNotEmpty && email.isEmpty) method = 'phone';

    try {
      final idPhotoPath = 'id_${DateTime.now().millisecondsSinceEpoch}.jpg';

      final auth = Provider.of<AuthService>(context, listen: false);
      final api  = Provider.of<ApiService>(context, listen: false);

      // Register user — returns the full user object including `id`
      final userData = await auth.signUp(
        firstName:         _firstNameController.text.trim(),
        lastName:          _lastNameController.text.trim(),
        email:             email,
        password:          _passwordController.text,
        phone:             phone,
        address:           _buildFullAddress(),
        barangay:          _selectedBarangay!,
        idPhotoPath:       idPhotoPath,
        idPhotoBytes:      _idPhotoBytes,
        selfiePhotoBytes:  _selfieBytes,
        selfieWithIdBytes: _selfieWithIdBytes,
        role:              _role,
      );

      // Capture the DB user ID for use in verification callbacks
      final registeredUserId = userData['id'] as int?;

      if (!mounted) return;

      // ── Email OTP path ────────────────────────────────────────────────────
      if (method == 'email' && email.isNotEmpty) {
        final res = await api.sendEmailOtp(email);
        final userId   = res['user_id']   as int?;
        final emailSent = res['email_sent'] as bool? ?? true;
        if (!mounted) return;
        if (userId != null) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => OtpVerificationScreen(
                userId:    userId,
                email:     email,
                emailSent: emailSent,
              ),
            ),
          );
          return;
        } else {
          _showError('Could not send verification code. Please try again.');
          return;
        }
      }

      // ── Phone SMS path ────────────────────────────────────────────────────
      if (method == 'phone' && phone.isNotEmpty) {
        // Web: use signInWithPhoneNumber (reCAPTCHA flow)
        if (kIsWeb) {
          try {
            final confirmationResult =
                await FirebaseAuth.instance.signInWithPhoneNumber(phone);
            if (!mounted) return;
            setState(() => _isLoading = false);
            if (registeredUserId == null) {
              _showError('Registration error: could not retrieve user ID.');
              return;
            }
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => PhoneSmsVerificationScreen(
                  verificationId: '',
                  userId: registeredUserId,
                  phoneNumber: phone,
                  webConfirmationResult: confirmationResult,
                ),
              ),
            );
          } catch (e) {
            if (mounted) {
              _showError(e.toString().replaceFirst('Exception: ', ''));
              setState(() => _isLoading = false);
            }
          }
          return;
        }

        await FirebaseAuth.instance.verifyPhoneNumber(
          phoneNumber: phone,
          timeout: const Duration(seconds: 60),

          // Auto-verification (some Android devices detect SMS instantly)
          verificationCompleted: (PhoneAuthCredential cred) async {
            try {
              final userCred = await FirebaseAuth.instance.signInWithCredential(cred);
              final idToken  = await userCred.user?.getIdToken();
              if (registeredUserId != null && idToken != null) {
                await api.verifyFirebasePhone(registeredUserId, idToken);
                await FirebaseAuth.instance.signOut();
              }
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Phone auto-verified! Awaiting admin approval.'),
                  backgroundColor: _kCharcoal,
                ));
                Navigator.pushReplacementNamed(context, '/login');
              }
            } catch (e) {
              if (mounted) _showError('Auto-verification failed: $e');
            }
          },

          // Firebase could not send / validate
          verificationFailed: (FirebaseAuthException e) {
            if (mounted) {
              final msg = switch (e.code) {
                'invalid-phone-number' => 'Invalid phone number format. Use +639XXXXXXXXX.',
                'too-many-requests'    => 'Too many SMS requests. Please wait and try again.',
                'quota-exceeded'       => 'SMS quota exceeded. Please use email verification instead.',
                'app-not-authorized'   => 'This app is not authorised for Firebase Phone Auth. '
                    'Check SHA-1 fingerprint in the Firebase console.',
                _                      => e.message ?? 'Phone verification failed.',
              };
              _showError(msg);
              setState(() => _isLoading = false);
            }
          },

          // SMS sent — navigate to the code-entry screen
          codeSent: (String verificationId, int? resendToken) {
            if (!mounted) return;
            setState(() => _isLoading = false);
            if (registeredUserId == null) {
              _showError('Registration error: could not retrieve user ID. Please try again.');
              return;
            }
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => PhoneSmsVerificationScreen(
                  verificationId: verificationId,
                  userId:         registeredUserId,
                  phoneNumber:    phone,
                ),
              ),
            );
          },

          codeAutoRetrievalTimeout: (_) {},
        );
        return; // Firebase callbacks handle navigation
      }

      // ── Fallback — no OTP triggered ──────────────────────────────────────
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
                    _buildTextField(controller: _houseNoController, label: 'House No. / Unit / Building', hint: 'e.g. 12, Unit 3A', icon: Icons.home_outlined, optional: true),
                    const SizedBox(height: 12),
                    _buildTextField(controller: _purokController, label: 'Purok / Sitio', hint: 'e.g. Purok 4, Sitio Mabuhay', icon: Icons.holiday_village_outlined, optional: true),
                    const SizedBox(height: 12),
                    _buildTextField(controller: _streetController, label: 'Street Name', hint: 'e.g. Rizal St.', icon: Icons.edit_road_outlined, optional: true),
                    const SizedBox(height: 12),
                    _buildRegionDropdown(),
                    if (_selectedRegionCode != null && !_noProvinceRegion) ...[
                      const SizedBox(height: 12),
                      _buildProvinceDropdown(),
                    ],
                    if (_selectedRegionCode != null && (_noProvinceRegion || _selectedProvinceCode != null)) ...[
                      const SizedBox(height: 12),
                      _buildCityDropdown(),
                    ],
                    if (_selectedCityCode != null) ...[
                      const SizedBox(height: 12),
                      _buildBarangayDropdown(),
                    ],
                    const SizedBox(height: 12),
                    _buildTextField(controller: _zipCodeController, label: 'ZIP Code', hint: 'e.g. 1000', icon: Icons.markunread_mailbox_outlined, optional: true, keyboardType: TextInputType.number),

                    const SizedBox(height: 20),

                    // ── Section 5: Photo Verification ────────────────────
                    _sectionLabel('Photo Verification',
                        sub: 'Camera required — all three photos must be freshly taken'),
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
        if (!isValidPhPhone(v.trim())) return 'Enter a valid PH number (09XX or +63XX)';
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

  // ── Generic optional text field ────────────────────────────────────────────
  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    bool optional = false,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: optional ? '$label (Optional)' : label,
        hintText: hint,
        prefixIcon: Icon(icon),
      ),
    );
  }

  // ── Region dropdown ────────────────────────────────────────────────────────
  Widget _buildRegionDropdown() {
    if (_regionsLoading) return _loadingRow('Loading regions…');
    if (_regions.isEmpty) return _retryRow('Could not load regions.', _loadRegions);
    return DropdownButtonFormField<String>(
      value: _selectedRegionCode,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Region', prefixIcon: Icon(Icons.map_outlined)),
      items: _regions.map((r) {
        return DropdownMenuItem<String>(value: r['code'] as String, child: Text(r['name'] as String));
      }).toList(),
      onChanged: (v) { if (v != null) _onRegionChanged(v); },
      validator: (v) => (v == null || v.isEmpty) ? 'Please select your region' : null,
    );
  }

  // ── Province dropdown ──────────────────────────────────────────────────────
  Widget _buildProvinceDropdown() {
    if (_provincesLoading) return _loadingRow('Loading provinces…');
    if (_provinces.isEmpty) return const SizedBox.shrink();
    return DropdownButtonFormField<String>(
      value: _selectedProvinceCode,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Province', prefixIcon: Icon(Icons.location_city_outlined)),
      items: _provinces.map((p) {
        return DropdownMenuItem<String>(value: p['code'] as String, child: Text(p['name'] as String));
      }).toList(),
      onChanged: (v) { if (v != null) _onProvinceChanged(v); },
      validator: (v) => (v == null || v.isEmpty) ? 'Please select your province' : null,
    );
  }

  // ── City / Municipality dropdown ───────────────────────────────────────────
  Widget _buildCityDropdown() {
    if (_citiesLoading) return _loadingRow('Loading cities / municipalities…');
    if (_cities.isEmpty) return const SizedBox.shrink();
    return DropdownButtonFormField<String>(
      value: _selectedCityCode,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'City / Municipality', prefixIcon: Icon(Icons.location_on_outlined)),
      items: _cities.map((c) {
        return DropdownMenuItem<String>(value: c['code'] as String, child: Text(c['name'] as String));
      }).toList(),
      onChanged: (v) { if (v != null) _onCityChanged(v); },
      validator: (v) => (v == null || v.isEmpty) ? 'Please select your city or municipality' : null,
    );
  }

  // ── Barangay dropdown ──────────────────────────────────────────────────────
  Widget _buildBarangayDropdown() {
    if (_barangaysLoading) return _loadingRow('Loading barangays…');
    if (_barangayItems.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text('No barangays found for the selected city.',
            style: TextStyle(color: Colors.red, fontSize: 13)),
      );
    }
    return DropdownButtonFormField<String>(
      value: _selectedBarangay,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Barangay', prefixIcon: Icon(Icons.apartment_outlined)),
      items: _barangayItems.map((b) {
        final name = b['name'] as String? ?? '';
        return DropdownMenuItem<String>(value: name, child: Text(name));
      }).toList(),
      onChanged: (v) => setState(() => _selectedBarangay = v),
      validator: (v) => (v == null || v.isEmpty) ? 'Please select your barangay' : null,
    );
  }

  Widget _loadingRow(String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(children: [
        const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
        const SizedBox(width: 12),
        Text(label, style: const TextStyle(color: Colors.grey)),
      ]),
    );
  }

  Widget _retryRow(String message, VoidCallback onRetry) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Text(message, style: const TextStyle(color: Colors.red, fontSize: 13)),
        const SizedBox(width: 8),
        TextButton(onPressed: onRetry, child: const Text('Retry')),
      ]),
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
                  icon: const Icon(Icons.camera_alt, size: 16),
                  label: Text(bytes == null ? 'Open Camera' : 'Retake Photo',
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
