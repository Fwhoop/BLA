import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:barangay_legal_aid/services/auth_service.dart';
import 'package:barangay_legal_aid/services/api_service.dart';
import 'package:barangay_legal_aid/models/user_model.dart';
import 'package:barangay_legal_aid/widgets/bla_app_bar.dart';

const _kPrimary  = Color(0xFF99272D);
const _kCharcoal = Color(0xFF36454F);
const _kBg       = Color(0xFFF5F6FA);

class UserProfilePage extends StatefulWidget {
  const UserProfilePage({super.key});

  @override
  State<UserProfilePage> createState() => UserProfilePageState();
}

class UserProfilePageState extends State<UserProfilePage> {
  final _formKey = GlobalKey<FormState>();

  final _firstNameCtrl    = TextEditingController();
  final _lastNameCtrl     = TextEditingController();
  final _emailCtrl        = TextEditingController();
  final _phoneCtrl        = TextEditingController();
  final _addressCtrl      = TextEditingController();
  final _curPassCtrl      = TextEditingController();
  final _newPassCtrl      = TextEditingController();
  final _confirmPassCtrl  = TextEditingController();

  String? _selectedBarangay;
  bool _isLoading         = false;
  bool _isEditing         = false;
  bool _isChangingPw      = false;
  bool _obscureCur        = true;
  bool _obscureNew        = true;
  bool _obscureConfirm    = true;
  User? _currentUser;
  Map<String, dynamic>? _stats;
  bool _statsLoading = false;
  bool _showFullMiddleName = false;

  static const List<String> _barangays = [
    'Barangay 1', 'Barangay 2', 'Barangay Cabaluay', 'Barangay Cabatangan',
    'Barangay Culianan', 'Barangay Mercedes', 'Barangay Pasonanca',
    'Barangay San Jose Cawa-Cawa', 'Barangay San Jose Gusu',
    'Barangay San Roque', 'Barangay Sta. Maria', 'Barangay Talabaan',
    'Barangay Taluksangay', 'System',
  ];

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _loadStats();
  }

  @override
  void dispose() {
    _firstNameCtrl.dispose(); _lastNameCtrl.dispose(); _emailCtrl.dispose();
    _phoneCtrl.dispose(); _addressCtrl.dispose(); _curPassCtrl.dispose();
    _newPassCtrl.dispose(); _confirmPassCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadUserData() async {
    try {
      final auth = Provider.of<AuthService>(context, listen: false);
      final user = await auth.getCurrentUser();
      final data = await auth.getUserData();
      if (mounted) {
        setState(() {
          _currentUser          = user;
          _firstNameCtrl.text   = data['firstName'] ?? '';
          _lastNameCtrl.text    = data['lastName']  ?? '';
          _emailCtrl.text       = data['email']     ?? '';
          _phoneCtrl.text       = data['phone']     ?? '';
          _addressCtrl.text     = data['address']   ?? '';
          _selectedBarangay     = data['barangay']  ?? '';
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading user data: $e'), backgroundColor: _kPrimary),
        );
      }
    }
  }

  Future<void> _loadStats() async {
    if (!mounted) return;
    setState(() => _statsLoading = true);
    try {
      final api = Provider.of<ApiService>(context, listen: false);
      final stats = await api.getMyStats();
      if (mounted) setState(() { _stats = stats; _statsLoading = false; });
    } catch (_) {
      if (mounted) setState(() => _statsLoading = false);
    }
  }

  Future<void> _updateProfile() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      final auth = Provider.of<AuthService>(context, listen: false);
      final ok = await auth.updateProfile(
        firstName: _firstNameCtrl.text,
        lastName:  _lastNameCtrl.text,
        phone:     _phoneCtrl.text,
        address:   _addressCtrl.text,
        barangay:  _selectedBarangay,
      );
      if (!mounted) return;
      if (ok) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Profile updated successfully!'),
          backgroundColor: Color(0xFF36454F),
        ));
        setState(() => _isEditing = false);
        await _loadUserData();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Failed to update profile.'), backgroundColor: _kPrimary,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: _kPrimary),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _changePassword() async {
    if (_newPassCtrl.text != _confirmPassCtrl.text) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('New passwords do not match'), backgroundColor: _kPrimary,
      ));
      return;
    }
    if (_newPassCtrl.text.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Password must be at least 6 characters'), backgroundColor: _kPrimary,
      ));
      return;
    }
    setState(() => _isLoading = true);
    try {
      final auth = Provider.of<AuthService>(context, listen: false);
      final ok = await auth.changePassword(_curPassCtrl.text, _newPassCtrl.text);
      if (!mounted) return;
      if (ok) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Password changed successfully!'),
          backgroundColor: Color(0xFF36454F),
        ));
        setState(() => _isChangingPw = false);
        _curPassCtrl.clear(); _newPassCtrl.clear(); _confirmPassCtrl.clear();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Current password is incorrect'), backgroundColor: _kPrimary,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: _kPrimary),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: BlaAppBar(
        title: 'My Profile',
        user: _currentUser == null ? {} : {
          'first_name':  _currentUser!.firstName,
          'last_name':   _currentUser!.lastName,
          'middle_name': _currentUser!.middleName ?? '',
          'role':        _currentUser!.role.toString().split('.').last,
          'email':       _currentUser!.email,
          'profile_photo_path': '',
        },
        extraActions: [
          if (!_isEditing && !_isChangingPw)
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Edit Profile',
              onPressed: () {
                _formKey.currentState?.reset(); // clear any previous validation state
                setState(() => _isEditing = true);
              },
            ),
        ],
      ),
      body: _currentUser == null
          ? const Center(child: CircularProgressIndicator(color: _kPrimary))
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 860),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildHero(),
                        const SizedBox(height: 20),
                        _buildActivityRow(),
                        const SizedBox(height: 16),
                        _buildInfoCard(),
                        const SizedBox(height: 16),
                        _buildPasswordCard(),
                        if (_isEditing) ...[
                          const SizedBox(height: 16),
                          _buildEditActions(),
                        ],
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  // ── Name display with middle-name toggle ───────────────────────────────────

  Widget _buildNameDisplay() {
    final user = _currentUser;
    if (user == null) return const SizedBox.shrink();

    final mi = user.middleInitial;
    if (mi == null) {
      return Text(
        user.fullName,
        style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '${user.firstName} ',
              style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
            ),
            GestureDetector(
              onTap: () => setState(() => _showFullMiddleName = !_showFullMiddleName),
              child: Text(
                _showFullMiddleName ? '${user.middleName} ' : '$mi ',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  decoration: TextDecoration.underline,
                  decorationColor: Colors.white54,
                ),
              ),
            ),
            Flexible(
              child: Text(
                user.lastName,
                style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        GestureDetector(
          onTap: () => setState(() => _showFullMiddleName = !_showFullMiddleName),
          child: Text(
            _showFullMiddleName ? 'show initial' : 'see full name',
            style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.65)),
          ),
        ),
      ],
    );
  }

  // ── Hero ──────────────────────────────────────────────────────────────────

  Widget _buildHero() {
    final initials = () {
      final f = _currentUser?.firstName ?? '';
      final l = _currentUser?.lastName  ?? '';
      if (f.isNotEmpty && l.isNotEmpty) return '${f[0]}${l[0]}'.toUpperCase();
      if (f.isNotEmpty) return f[0].toUpperCase();
      return '?';
    }();
    final role = _currentUser?.roleDisplay ?? 'User';
    final brgy = _currentUser?.barangay ?? '';

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          colors: [Color(0xFF99272D), Color(0xFF6B1A1E)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [BoxShadow(color: _kPrimary.withValues(alpha: 0.3), blurRadius: 16, offset: const Offset(0, 6))],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          CircleAvatar(
            radius: 38,
            backgroundColor: Colors.white.withValues(alpha: 0.2),
            child: Text(initials, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 26)),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildNameDisplay(),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(role, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                    ),
                    if (brgy.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          '· $brgy',
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 12),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ],
                ),
                if (_emailCtrl.text.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(_emailCtrl.text, style: TextStyle(color: Colors.white.withValues(alpha: 0.65), fontSize: 12)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Activity row ──────────────────────────────────────────────────────────

  Widget _buildActivityRow() {
    final isAdmin = _currentUser?.isAdmin ?? false;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: _buildComplaintsFiledCard()),
        const SizedBox(width: 12),
        if (!isAdmin) ...[
          Expanded(child: _buildComplaintsAgainstCard()),
          const SizedBox(width: 12),
        ],
        Expanded(child: _buildRequestsCard()),
      ],
    );
  }

  Widget _buildComplaintsFiledCard() {
    if (_statsLoading) return _statCardShimmer();
    final s = _stats;
    final count   = s?['complaints_filed_count'] ?? 0;
    final pending  = (s?['complaints_by_status']?['pending']   ?? 0) as int;
    final reviewing = (s?['complaints_by_status']?['reviewing'] ?? 0) as int;
    final resolved  = (s?['complaints_by_status']?['resolved']  ?? 0) as int;
    final dismissed = (s?['complaints_by_status']?['dismissed'] ?? 0) as int;

    return _StatCard(
      icon: Icons.report_outlined,
      iconColor: _kPrimary,
      label: 'Complaints Filed',
      count: count,
      children: [
        _StatRow('Pending',   pending,   const Color(0xFFF59E0B)),
        _StatRow('Reviewing', reviewing, const Color(0xFF3B82F6)),
        _StatRow('Resolved',  resolved,  const Color(0xFF10B981)),
        _StatRow('Dismissed', dismissed, const Color(0xFF6B7280)),
      ],
    );
  }

  Widget _buildComplaintsAgainstCard() {
    if (_statsLoading) return _statCardShimmer();
    final s = _stats;
    final count = s?['complaints_filed_against_count'] ?? 0;
    final cats  = (s?['complaints_against_by_category'] as List<dynamic>?) ?? [];

    return _StatCard(
      icon: Icons.gavel_outlined,
      iconColor: const Color(0xFF8E24AA),
      label: 'Complaints Against Me',
      count: count,
      children: cats.isEmpty
          ? [const _EmptyStatHint('No complaints on record')]
          : cats.take(4).map<Widget>((c) {
              final cat   = c['category'] as String? ?? 'Other';
              final cnt   = c['count'] as int? ?? 0;
              return _StatRow(cat, cnt, const Color(0xFF8E24AA));
            }).toList(),
    );
  }

  Widget _buildRequestsCard() {
    if (_statsLoading) return _statCardShimmer();
    final s = _stats;
    final total    = s?['requests_total'] ?? 0;
    final pending  = (s?['requests_by_status']?['pending']  ?? 0) as int;
    final approved = (s?['requests_by_status']?['approved'] ?? 0) as int;
    final rejected = (s?['requests_by_status']?['rejected'] ?? 0) as int;

    return _StatCard(
      icon: Icons.description_outlined,
      iconColor: const Color(0xFF0277BD),
      label: 'Document Requests',
      count: total,
      children: [
        _StatRow('Pending',  pending,  const Color(0xFFF59E0B)),
        _StatRow('Approved', approved, const Color(0xFF10B981)),
        _StatRow('Rejected', rejected, const Color(0xFF99272D)),
      ],
    );
  }

  Widget _statCardShimmer() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFEEEEEE)),
      ),
      child: const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: _kPrimary)),
        ),
      ),
    );
  }

  // ── Personal info card ────────────────────────────────────────────────────

  Widget _buildInfoCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFEEEEEE)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.person_outline_rounded, color: _kPrimary, size: 20),
              const SizedBox(width: 8),
              const Text('Personal Information',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: _kCharcoal)),
              const Spacer(),
              if (_isEditing)
                TextButton(
                  onPressed: () {
                    _formKey.currentState?.reset();
                    setState(() => _isEditing = false);
                    _loadUserData();
                  },
                  child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
                ),
            ],
          ),
          const SizedBox(height: 18),
          // Name row
          Row(
            children: [
              Expanded(child: _field(_firstNameCtrl, 'First Name', Icons.person_outline)),
              const SizedBox(width: 12),
              Expanded(child: _field(_lastNameCtrl, 'Last Name', Icons.person_outline)),
            ],
          ),
          const SizedBox(height: 14),
          // Email (read-only)
          TextFormField(
            controller: _emailCtrl,
            readOnly: true,
            style: const TextStyle(fontSize: 14, color: Colors.grey),
            decoration: _inputDec('Email', Icons.email_outlined, helper: 'Email cannot be changed'),
          ),
          const SizedBox(height: 14),
          _field(_phoneCtrl, 'Phone Number', Icons.phone_outlined,
              type: TextInputType.phone,
              validator: (v) {
                // Only validate format if something was actually typed
                if (_isEditing && v != null && v.isNotEmpty && v.length < 10) {
                  return 'Enter a valid phone number';
                }
                return null;
              }),
          const SizedBox(height: 14),
          TextFormField(
            controller: _addressCtrl,
            enabled: _isEditing,
            maxLines: 2,
            decoration: _inputDec('Complete Address', Icons.home_outlined),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            initialValue: _barangays.contains(_selectedBarangay) ? _selectedBarangay : null,
            decoration: _inputDec('Barangay', Icons.location_on_outlined),
            items: _barangays.map((b) => DropdownMenuItem(value: b, child: Text(b))).toList(),
            onChanged: _isEditing ? (v) => setState(() => _selectedBarangay = v) : null,
          ),
          if (_isEditing) ...[
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _updateProfile,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kPrimary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: _isLoading
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Save Changes', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _field(TextEditingController ctrl, String label, IconData icon, {
    TextInputType? type,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: ctrl,
      enabled: _isEditing,
      keyboardType: type,
      decoration: _inputDec(label, icon),
      validator: validator, // no blanket "Required" — fields are optional
    );
  }

  InputDecoration _inputDec(String label, IconData icon, {String? helper}) {
    return InputDecoration(
      labelText: label,
      helperText: helper,
      prefixIcon: Icon(icon, size: 18),
      filled: true,
      fillColor: _isEditing ? Colors.white : const Color(0xFFF8F9FA),
      isDense: true,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFDDE3EE)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _kPrimary, width: 2),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFF0F0F0)),
      ),
    );
  }

  // ── Password card ─────────────────────────────────────────────────────────

  Widget _buildPasswordCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFEEEEEE)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.lock_outline_rounded, color: _kPrimary, size: 20),
              const SizedBox(width: 8),
              const Text('Password Settings',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: _kCharcoal)),
              const Spacer(),
              if (!_isChangingPw)
                TextButton.icon(
                  onPressed: () => setState(() => _isChangingPw = true),
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label: const Text('Change'),
                  style: TextButton.styleFrom(foregroundColor: _kPrimary),
                ),
              if (_isChangingPw)
                TextButton(
                  onPressed: () {
                    setState(() => _isChangingPw = false);
                    _curPassCtrl.clear(); _newPassCtrl.clear(); _confirmPassCtrl.clear();
                  },
                  child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
                ),
            ],
          ),
          if (_isChangingPw) ...[
            const SizedBox(height: 16),
            _pwField(_curPassCtrl, 'Current Password', _obscureCur, () => setState(() => _obscureCur = !_obscureCur)),
            const SizedBox(height: 12),
            _pwField(_newPassCtrl, 'New Password', _obscureNew, () => setState(() => _obscureNew = !_obscureNew)),
            const SizedBox(height: 12),
            _pwField(_confirmPassCtrl, 'Confirm New Password', _obscureConfirm, () => setState(() => _obscureConfirm = !_obscureConfirm)),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _changePassword,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kCharcoal,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: _isLoading
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Update Password', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ] else ...[
            const SizedBox(height: 8),
            Text('Keep your account secure with a strong password.',
                style: TextStyle(fontSize: 12, color: _kCharcoal.withValues(alpha: 0.55))),
          ],
        ],
      ),
    );
  }

  Widget _pwField(TextEditingController ctrl, String label, bool obscure, VoidCallback toggle) {
    return TextFormField(
      controller: ctrl,
      obscureText: obscure,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: const Icon(Icons.lock_outline, size: 18),
        suffixIcon: IconButton(
          icon: Icon(obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 18),
          onPressed: toggle,
        ),
        filled: true,
        fillColor: Colors.white,
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFDDE3EE))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _kPrimary, width: 2)),
      ),
    );
  }

  Widget _buildEditActions() => const SizedBox.shrink();
}

// ── Reusable stat card ────────────────────────────────────────────────────────

class _StatCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final int count;
  final List<Widget> children;

  const _StatCard({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.count,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFEEEEEE)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: iconColor, size: 16),
              ),
              const Spacer(),
              Text(
                '$count',
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: iconColor),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _kCharcoal)),
          const SizedBox(height: 10),
          const Divider(height: 1, color: Color(0xFFF0F0F0)),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  final String label;
  final int count;
  final Color color;

  const _StatRow(this.label, this.count, this.color);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 11, color: _kCharcoal), overflow: TextOverflow.ellipsis)),
          Text('$count', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }
}

class _EmptyStatHint extends StatelessWidget {
  final String text;
  const _EmptyStatHint(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text(text, style: const TextStyle(fontSize: 11, color: Colors.grey)),
    );
  }
}
