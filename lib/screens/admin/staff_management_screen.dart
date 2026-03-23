import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:barangay_legal_aid/services/api_service.dart';

const _kPrimary = Color(0xFF99272D);
const _kCharcoal = Color(0xFF36454F);
const _kBg = Color(0xFFF0F2F5);

class StaffManagementScreen extends StatefulWidget {
  const StaffManagementScreen({super.key});

  @override
  State<StaffManagementScreen> createState() => _StaffManagementScreenState();
}

class _StaffManagementScreenState extends State<StaffManagementScreen> {
  List<Map<String, dynamic>> _staff = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadStaff());
  }

  Future<void> _loadStaff() async {
    setState(() => _isLoading = true);
    try {
      final api = Provider.of<ApiService>(context, listen: false);
      final list = await api.getStaffUsers();
      if (mounted) setState(() => _staff = list);
    } catch (e) {
      if (mounted) _showError('Failed to load staff: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _addStaff() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => _AddStaffDialog(),
    );
    if (result == true) await _loadStaff();
  }

  Future<void> _confirmRemove(Map<String, dynamic> member) async {
    final name =
        '${member['first_name'] ?? ''} ${member['last_name'] ?? ''}'.trim();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Staff'),
        content: Text(
          'Remove "${name.isNotEmpty ? name : member['username']}" from your staff? '
          'Their account will be deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    try {
      final api = Provider.of<ApiService>(context, listen: false);
      await api.deleteUser(member['id'] as int);
      await _loadStaff();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Staff member removed.')),
        );
      }
    } catch (e) {
      if (mounted) _showError('Failed to remove staff: $e');
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        title: const Text('Staff Management'),
        backgroundColor: _kPrimary,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _loadStaff,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addStaff,
        backgroundColor: _kPrimary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text('Add Staff'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: _kPrimary))
          : RefreshIndicator(
              color: _kPrimary,
              onRefresh: _loadStaff,
              child: _staff.isEmpty
                  ? _buildEmptyState()
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
                      itemCount: _staff.length,
                      itemBuilder: (_, i) =>
                          _StaffCard(member: _staff[i], onRemove: _confirmRemove),
                    ),
            ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.group_off_rounded, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(
            'No staff members yet.',
            style: TextStyle(fontSize: 16, color: Colors.grey.shade500),
          ),
          const SizedBox(height: 8),
          Text(
            'Tap "Add Staff" to assign a clerk or volunteer.',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade400),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Staff Card
// ─────────────────────────────────────────────────────────────────────────────

class _StaffCard extends StatelessWidget {
  final Map<String, dynamic> member;
  final Future<void> Function(Map<String, dynamic>) onRemove;

  const _StaffCard({required this.member, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final firstName = (member['first_name'] ?? '') as String;
    final lastName = (member['last_name'] ?? '') as String;
    final fullName = '$firstName $lastName'.trim();
    final displayName = fullName.isNotEmpty ? fullName : (member['username'] ?? '—');
    final email = (member['email'] ?? '—') as String;
    final username = (member['username'] ?? '') as String;
    final initials = _initials(firstName, lastName, username);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: _kPrimary.withValues(alpha: 0.12),
              child: Text(
                initials,
                style: const TextStyle(
                  color: _kPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayName,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: _kCharcoal,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '@$username  ·  $email',
                    style: TextStyle(
                      fontSize: 12,
                      color: _kCharcoal.withValues(alpha: 0.55),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFFE8F5E9),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                'Staff',
                style: TextStyle(
                  fontSize: 11,
                  color: Color(0xFF2E7D32),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.person_remove_outlined, color: Colors.red),
              tooltip: 'Remove staff',
              onPressed: () => onRemove(member),
            ),
          ],
        ),
      ),
    );
  }

  String _initials(String first, String last, String username) {
    if (first.isNotEmpty && last.isNotEmpty) {
      return '${first[0]}${last[0]}'.toUpperCase();
    }
    if (first.isNotEmpty) return first[0].toUpperCase();
    if (username.isNotEmpty) return username[0].toUpperCase();
    return '?';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Add Staff Dialog
// ─────────────────────────────────────────────────────────────────────────────

class _AddStaffDialog extends StatefulWidget {
  @override
  State<_AddStaffDialog> createState() => _AddStaffDialogState();
}

class _AddStaffDialogState extends State<_AddStaffDialog> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _obscure = true;
  bool _saving = false;

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _emailCtrl.dispose();
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final api = Provider.of<ApiService>(context, listen: false);
      await api.createStaffMember(
        email: _emailCtrl.text.trim(),
        username: _usernameCtrl.text.trim(),
        firstName: _firstNameCtrl.text.trim(),
        lastName: _lastNameCtrl.text.trim(),
        password: _passwordCtrl.text,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceFirst('Exception: ', '')),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add Staff Member'),
      content: SizedBox(
        width: 360,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(child: _field(_firstNameCtrl, 'First Name')),
                    const SizedBox(width: 10),
                    Expanded(child: _field(_lastNameCtrl, 'Last Name')),
                  ],
                ),
                const SizedBox(height: 12),
                _field(
                  _emailCtrl,
                  'Email',
                  keyboardType: TextInputType.emailAddress,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Required';
                    if (!v.contains('@')) return 'Invalid email';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                _field(_usernameCtrl, 'Username'),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _passwordCtrl,
                  obscureText: _obscure,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscure ? Icons.visibility_off : Icons.visibility,
                      ),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Required';
                    if (v.length < 6) return 'At least 6 characters';
                    return null;
                  },
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _submit,
          style: FilledButton.styleFrom(backgroundColor: _kPrimary),
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Add'),
        ),
      ],
    );
  }

  Widget _field(
    TextEditingController ctrl,
    String label, {
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: ctrl,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      validator: validator ??
          (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
    );
  }
}
