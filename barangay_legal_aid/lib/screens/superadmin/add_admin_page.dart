import 'dart:convert';
import 'dart:typed_data';

import 'package:barangay_legal_aid/screens/otp_verification_screen.dart';
import 'package:barangay_legal_aid/services/api_service.dart';
import 'package:barangay_legal_aid/utils/phone_utils.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

const _kPrimary  = Color(0xFF99272D);
const _kCharcoal = Color(0xFF36454F);
const _psgcBase  = 'https://psgc.gitlab.io/api';

class AddAdminPage extends StatefulWidget {
  final VoidCallback onAdminAdded;
  const AddAdminPage({super.key, required this.onAdminAdded});

  @override
  State<AddAdminPage> createState() => _AddAdminPageState();
}

class _AddAdminPageState extends State<AddAdminPage> {
  final _formKey     = GlobalKey<FormState>();
  final _imagePicker = ImagePicker();

  final _firstNameCtrl        = TextEditingController();
  final _lastNameCtrl         = TextEditingController();
  final _middleNameCtrl       = TextEditingController();
  final _emailCtrl            = TextEditingController();
  final _phoneCtrl            = TextEditingController();
  final _usernameCtrl         = TextEditingController();
  final _passwordCtrl         = TextEditingController();
  final _confirmPasswordCtrl  = TextEditingController();
  final _purokCtrl            = TextEditingController();
  final _streetCtrl           = TextEditingController();
  final _zipCtrl              = TextEditingController();

  DateTime? _selectedBirthday;
  String _selectedGender = 'prefer_not_to_say';
  bool _obscurePassword        = true;
  bool _obscureConfirmPassword = true;
  bool _isLoading              = false;

  Uint8List? _selfieBytes;
  Uint8List? _idPhotoBytes;
  Uint8List? _selfieWithIdBytes;

  // PSGC
  String? _selectedRegionCode;
  String? _selectedProvinceCode;
  String? _selectedCityCode;
  String? _selectedBarangay;
  bool _noProvinceRegion = false;

  List<Map<String, dynamic>> _regions      = [];
  List<Map<String, dynamic>> _provinces    = [];
  List<Map<String, dynamic>> _cities       = [];
  List<Map<String, dynamic>> _barangayItems = [];

  bool _regionsLoading    = false;
  bool _provincesLoading  = false;
  bool _citiesLoading     = false;
  bool _barangaysLoading  = false;

  @override
  void initState() {
    super.initState();
    _loadRegions();
  }

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _middleNameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    _purokCtrl.dispose();
    _streetCtrl.dispose();
    _zipCtrl.dispose();
    super.dispose();
  }

  // ── PSGC ──────────────────────────────────────────────────────────────────

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
      _selectedCityCode = code;
      _selectedBarangay = null;
      _barangayItems    = [];
      _barangaysLoading = true;
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

  // ── Photo picker ───────────────────────────────────────────────────────────

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

  // ── Submit ─────────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_passwordCtrl.text != _confirmPasswordCtrl.text) {
      _showError('Passwords do not match.');
      return;
    }
    if (_selectedBarangay == null) {
      _showError('Please select a barangay.');
      return;
    }
    if (_selfieBytes == null) {
      _showError('Please take the admin\'s selfie photo.');
      return;
    }
    if (_idPhotoBytes == null) {
      _showError('Please take a photo of the admin\'s valid ID.');
      return;
    }
    if (_selfieWithIdBytes == null) {
      _showError('Please take a selfie of the admin holding their ID.');
      return;
    }

    setState(() => _isLoading = true);

    final phone = _phoneCtrl.text.trim().isEmpty
        ? ''
        : normalizePhPhone(_phoneCtrl.text.trim());

    try {
      final api = Provider.of<ApiService>(context, listen: false);
      final result = await api.createAdminWithPhotos(
        firstName:        _firstNameCtrl.text.trim(),
        lastName:         _lastNameCtrl.text.trim(),
        middleName:       _middleNameCtrl.text.trim(),
        birthday:         _selectedBirthday,
        email:            _emailCtrl.text.trim(),
        username:         _usernameCtrl.text.trim(),
        password:         _passwordCtrl.text,
        phone:            phone,
        gender:           _selectedGender,
        purok:            _purokCtrl.text.trim().isEmpty   ? null : _purokCtrl.text.trim(),
        streetName:       _streetCtrl.text.trim().isEmpty  ? null : _streetCtrl.text.trim(),
        city:             _cities.firstWhere((c) => c['code'] == _selectedCityCode, orElse: () => {})['name'] as String?,
        province:         _noProvinceRegion ? null : _provinces.firstWhere((p) => p['code'] == _selectedProvinceCode, orElse: () => {})['name'] as String?,
        zipCode:          _zipCtrl.text.trim().isEmpty     ? null : _zipCtrl.text.trim(),
        barangayName:     _selectedBarangay,
        idPhotoBytes:     _idPhotoBytes,
        profilePhotoBytes: _selfieBytes,
        selfieWithIdBytes: _selfieWithIdBytes,
      );

      if (!mounted) return;

      final userId = result['id'] as int;
      final email  = result['email'] as String? ?? _emailCtrl.text.trim();

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => OtpVerificationScreen(
            userId: userId,
            email: email,
            emailSent: true,
            onSuccess: () {
              Navigator.pop(context); // pop OTP screen
              widget.onAdminAdded();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Admin added successfully.')),
              );
            },
          ),
        ),
      );
    } catch (e) {
      if (mounted) _showError(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      appBar: AppBar(
        title: const Text('Add Admin'),
        backgroundColor: _kPrimary,
        foregroundColor: Colors.white,
        elevation: 0,
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
                    // ── Header ───────────────────────────────────────────
                    _buildHeader(),
                    const SizedBox(height: 24),

                    // ── Section 1: Identity ──────────────────────────────
                    _sectionLabel('Identity'),
                    const SizedBox(height: 10),
                    _buildNameRow(),
                    const SizedBox(height: 12),
                    _buildMiddleNameField(),
                    const SizedBox(height: 12),
                    _buildBirthdayField(),
                    const SizedBox(height: 8),
                    _buildGenderSelector(),

                    const SizedBox(height: 20),

                    // ── Section 2: Contact ───────────────────────────────
                    _sectionLabel('Contact'),
                    const SizedBox(height: 10),
                    _buildEmailField(),
                    const SizedBox(height: 12),
                    _buildPhoneField(),

                    const SizedBox(height: 20),

                    // ── Section 3: Credentials ───────────────────────────
                    _sectionLabel('Credentials'),
                    const SizedBox(height: 10),
                    _buildTextField(ctrl: _usernameCtrl, label: 'Username', hint: 'e.g. jdelacruz', icon: Icons.alternate_email),
                    const SizedBox(height: 12),
                    _buildPasswordField(),
                    const SizedBox(height: 12),
                    _buildConfirmPasswordField(),

                    const SizedBox(height: 20),

                    // ── Section 4: Location ──────────────────────────────
                    _sectionLabel('Location'),
                    const SizedBox(height: 10),
                    _buildTextField(ctrl: _purokCtrl, label: 'Purok / Sitio', hint: 'e.g. Purok 4, Sitio Mabuhay', icon: Icons.holiday_village_outlined),
                    const SizedBox(height: 12),
                    _buildTextField(ctrl: _streetCtrl, label: 'Street Name', hint: 'e.g. Rizal St.', icon: Icons.edit_road_outlined),
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
                    _buildTextField(ctrl: _zipCtrl, label: 'ZIP Code (Optional)', hint: 'e.g. 1000', icon: Icons.markunread_mailbox_outlined, optional: true, keyboardType: TextInputType.number),

                    const SizedBox(height: 20),

                    // ── Section 5: Photo Verification ────────────────────
                    _sectionLabel('Photo Verification',
                        sub: 'Camera required — all three photos must be freshly taken'),
                    const SizedBox(height: 10),
                    _buildPhotoUploader(
                      label: 'Admin\'s Selfie',
                      hint: 'Take a clear selfie facing forward. This will be the admin\'s profile photo.',
                      icon: Icons.face_rounded,
                      bytes: _selfieBytes,
                      onPick: () => _pickPhoto(onPicked: (b) => setState(() => _selfieBytes = b)),
                      onRemove: () => setState(() => _selfieBytes = null),
                    ),
                    const SizedBox(height: 12),
                    _buildPhotoUploader(
                      label: 'Valid ID Photo',
                      hint: 'Government-issued ID: Driver\'s License, PhilHealth, SSS, UMID, Passport, Voter\'s ID, etc.',
                      icon: Icons.badge_outlined,
                      bytes: _idPhotoBytes,
                      onPick: () => _pickPhoto(onPicked: (b) => setState(() => _idPhotoBytes = b)),
                      onRemove: () => setState(() => _idPhotoBytes = null),
                    ),
                    const SizedBox(height: 12),
                    _buildPhotoUploader(
                      label: 'Selfie Holding ID',
                      hint: 'Admin holds their ID next to their face for identity verification.',
                      icon: Icons.co_present_rounded,
                      bytes: _selfieWithIdBytes,
                      onPick: () => _pickPhoto(onPicked: (b) => setState(() => _selfieWithIdBytes = b)),
                      onRemove: () => setState(() => _selfieWithIdBytes = null),
                    ),

                    const SizedBox(height: 28),

                    // ── Submit ───────────────────────────────────────────
                    FilledButton.icon(
                      onPressed: _isLoading ? null : _submit,
                      style: FilledButton.styleFrom(
                        backgroundColor: _kPrimary,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: _isLoading
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.person_add_alt_1_rounded),
                      label: Text(_isLoading ? 'Creating Admin…' : 'Create Admin Account',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
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

  // ── Widgets ────────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 20),
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
            child: const Icon(Icons.admin_panel_settings_rounded, size: 32, color: Colors.white),
          ),
          const SizedBox(width: 16),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Register Barangay Admin',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white)),
                SizedBox(height: 4),
                Text('Admin must be present for photo and OTP verification.',
                    style: TextStyle(fontSize: 12, color: Colors.white70)),
              ],
            ),
          ),
        ],
      ),
    );
  }

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
          Text(sub, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        ],
        const SizedBox(height: 4),
        Container(height: 1.5, color: _kPrimary.withValues(alpha: 0.12)),
      ],
    );
  }

  Widget _buildNameRow() {
    return Row(
      children: [
        Expanded(
          child: TextFormField(
            controller: _firstNameCtrl,
            decoration: const InputDecoration(labelText: 'First name', prefixIcon: Icon(Icons.person_outline)),
            validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: TextFormField(
            controller: _lastNameCtrl,
            decoration: const InputDecoration(labelText: 'Last name', prefixIcon: Icon(Icons.person_outline)),
            validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
          ),
        ),
      ],
    );
  }

  Widget _buildMiddleNameField() {
    return TextFormField(
      controller: _middleNameCtrl,
      decoration: const InputDecoration(
        labelText: 'Middle name',
        hintText: 'e.g. Santos',
        prefixIcon: Icon(Icons.person_outline),
        helperText: 'Middle initial will be shown automatically',
      ),
      validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
    );
  }

  Widget _buildBirthdayField() {
    final now = DateTime.now();
    final eighteenYearsAgo = DateTime(now.year - 18, now.month, now.day);
    final displayText = _selectedBirthday == null
        ? 'Select date of birth'
        : '${_selectedBirthday!.month.toString().padLeft(2, '0')}/'
          '${_selectedBirthday!.day.toString().padLeft(2, '0')}/'
          '${_selectedBirthday!.year}';

    return FormField<DateTime>(
      validator: (_) => _selectedBirthday == null ? 'Required' : null,
      builder: (state) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: eighteenYearsAgo,
                firstDate: DateTime(now.year - 100),
                lastDate: eighteenYearsAgo,
                helpText: 'Select birthday (must be 18+)',
              );
              if (picked != null) {
                setState(() => _selectedBirthday = picked);
                state.didChange(picked);
              }
            },
            child: InputDecorator(
              decoration: InputDecoration(
                labelText: 'Date of birth',
                prefixIcon: const Icon(Icons.cake_outlined),
                errorText: state.errorText,
              ),
              child: Text(
                displayText,
                style: TextStyle(color: _selectedBirthday == null ? Colors.grey.shade500 : null),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmailField() {
    return TextFormField(
      controller: _emailCtrl,
      keyboardType: TextInputType.emailAddress,
      decoration: const InputDecoration(
        labelText: 'Email address',
        hintText: 'admin@example.com',
        prefixIcon: Icon(Icons.email_outlined),
      ),
      validator: (v) {
        if (v == null || v.trim().isEmpty) return 'Required';
        final ok = RegExp(r"^[^@\s]+@[^@\s]+\.[^@\s]+$").hasMatch(v.trim());
        return ok ? null : 'Enter a valid email address';
      },
    );
  }

  Widget _buildPhoneField() {
    return TextFormField(
      controller: _phoneCtrl,
      keyboardType: TextInputType.phone,
      decoration: const InputDecoration(
        labelText: 'Phone number (Optional)',
        hintText: '+639XXXXXXXXX',
        prefixIcon: Icon(Icons.phone_outlined),
      ),
      validator: (v) {
        if (v == null || v.trim().isEmpty) return null;
        if (!isValidPhPhone(v.trim())) return 'Enter a valid PH number (09XX or +63XX)';
        return null;
      },
    );
  }

  Widget _buildTextField({
    required TextEditingController ctrl,
    required String label,
    required String hint,
    required IconData icon,
    bool optional = false,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return TextFormField(
      controller: ctrl,
      keyboardType: keyboardType,
      decoration: InputDecoration(labelText: label, hintText: hint, prefixIcon: Icon(icon)),
      validator: optional ? null : (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
    );
  }

  Widget _buildPasswordField() {
    return TextFormField(
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
        if (v.length < 6) return 'Minimum 6 characters';
        return null;
      },
    );
  }

  Widget _buildConfirmPasswordField() {
    return TextFormField(
      controller: _confirmPasswordCtrl,
      obscureText: _obscureConfirmPassword,
      decoration: InputDecoration(
        labelText: 'Confirm Password',
        prefixIcon: const Icon(Icons.lock_outline),
        suffixIcon: IconButton(
          icon: Icon(_obscureConfirmPassword ? Icons.visibility : Icons.visibility_off),
          onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
        ),
      ),
      validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
    );
  }

  Widget _buildRegionDropdown() {
    if (_regionsLoading) return _loadingRow('Loading regions…');
    if (_regions.isEmpty) return _retryRow('Could not load regions.', _loadRegions);
    return DropdownButtonFormField<String>(
      value: _selectedRegionCode,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Region', prefixIcon: Icon(Icons.map_outlined)),
      items: _regions.map((r) => DropdownMenuItem<String>(value: r['code'] as String, child: Text(r['name'] as String))).toList(),
      onChanged: (v) { if (v != null) _onRegionChanged(v); },
      validator: (v) => (v == null || v.isEmpty) ? 'Please select a region' : null,
    );
  }

  Widget _buildProvinceDropdown() {
    if (_provincesLoading) return _loadingRow('Loading provinces…');
    if (_provinces.isEmpty) return const SizedBox.shrink();
    return DropdownButtonFormField<String>(
      value: _selectedProvinceCode,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Province', prefixIcon: Icon(Icons.location_city_outlined)),
      items: _provinces.map((p) => DropdownMenuItem<String>(value: p['code'] as String, child: Text(p['name'] as String))).toList(),
      onChanged: (v) { if (v != null) _onProvinceChanged(v); },
      validator: (v) => (v == null || v.isEmpty) ? 'Please select a province' : null,
    );
  }

  Widget _buildCityDropdown() {
    if (_citiesLoading) return _loadingRow('Loading cities / municipalities…');
    if (_cities.isEmpty) return const SizedBox.shrink();
    return DropdownButtonFormField<String>(
      value: _selectedCityCode,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'City / Municipality', prefixIcon: Icon(Icons.location_on_outlined)),
      items: _cities.map((c) => DropdownMenuItem<String>(value: c['code'] as String, child: Text(c['name'] as String))).toList(),
      onChanged: (v) { if (v != null) _onCityChanged(v); },
      validator: (v) => (v == null || v.isEmpty) ? 'Please select a city or municipality' : null,
    );
  }

  Widget _buildBarangayDropdown() {
    if (_barangaysLoading) return _loadingRow('Loading barangays…');
    if (_barangayItems.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text('No barangays found for the selected city.', style: TextStyle(color: Colors.red, fontSize: 13)),
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
      validator: (v) => (v == null || v.isEmpty) ? 'Please select a barangay' : null,
    );
  }

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

  Widget _buildGenderSelector() {
    return Row(
      children: [
        Expanded(
          child: RadioListTile<String>(
            title: const Text('Male', style: TextStyle(fontSize: 14)),
            value: 'male',
            groupValue: _selectedGender,
            activeColor: _kPrimary,
            contentPadding: EdgeInsets.zero,
            onChanged: (v) => setState(() => _selectedGender = v!),
          ),
        ),
        Expanded(
          child: RadioListTile<String>(
            title: const Text('Female', style: TextStyle(fontSize: 14)),
            value: 'female',
            groupValue: _selectedGender,
            activeColor: _kPrimary,
            contentPadding: EdgeInsets.zero,
            onChanged: (v) => setState(() => _selectedGender = v!),
          ),
        ),
        Expanded(
          child: RadioListTile<String>(
            title: const Text('Prefer not\nto say', style: TextStyle(fontSize: 12)),
            value: 'prefer_not_to_say',
            groupValue: _selectedGender,
            activeColor: _kPrimary,
            contentPadding: EdgeInsets.zero,
            onChanged: (v) => setState(() => _selectedGender = v!),
          ),
        ),
      ],
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
}
