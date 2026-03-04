import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:barangay_legal_aid/services/api_service.dart';

const _kPrimary  = Color(0xFF99272D);
const _kCharcoal = Color(0xFF36454F);
const _kBg       = Color(0xFFF0F2F5);

class AdminsScreen extends StatefulWidget {
  const AdminsScreen({super.key});

  @override
  State<AdminsScreen> createState() => _AdminsScreenState();
}

class _AdminsScreenState extends State<AdminsScreen> {
  List<Map<String, dynamic>> _admins    = [];
  List<Map<String, dynamic>> _barangays = [];
  bool   _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  Future<void> _loadData() async {
    setState(() { _isLoading = true; _error = null; });
    try {
      final api = Provider.of<ApiService>(context, listen: false);
      final results = await Future.wait([
        api.getAdmins(),
        api.getBarangays(),
      ]);
      if (!mounted) return;
      setState(() {
        _admins    = results[0];
        _barangays = results[1];
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _isLoading = false; });
    }
  }

  // ── Group admins by barangay ────────────────────────────────────────────────
  // Returns list of {barangayName, admins} sections, unassigned last.
  List<_Section> _buildSections() {
    final barangayMap = { for (final b in _barangays) b['id'] as int : b['name'] as String };

    final Map<String?, List<Map<String, dynamic>>> grouped = {};
    for (final a in _admins) {
      final bid = a['barangay_id'] as int?;
      grouped.putIfAbsent(bid == null ? null : '$bid', () => []).add(a);
    }

    final sections = <_Section>[];

    // Sort by barangay name
    final assignedKeys = grouped.keys
        .whereType<String>()
        .toList()
      ..sort((a, b) {
        final na = barangayMap[int.tryParse(a)] ?? a;
        final nb = barangayMap[int.tryParse(b)] ?? b;
        return na.compareTo(nb);
      });

    for (final key in assignedKeys) {
      final bid = int.tryParse(key);
      final name = barangayMap[bid] ?? 'Barangay #$bid';
      sections.add(_Section(name, grouped[key]!));
    }

    // Unassigned at end
    if (grouped.containsKey(null)) {
      sections.add(_Section('Unassigned', grouped[null]!));
    }

    return sections;
  }

  // ── Add admin dialog ────────────────────────────────────────────────────────
  Future<void> _showAddAdminDialog() async {
    final formKey      = GlobalKey<FormState>();
    final emailCtrl    = TextEditingController();
    final usernameCtrl = TextEditingController();
    final passwordCtrl = TextEditingController();
    final firstCtrl    = TextEditingController();
    final lastCtrl     = TextEditingController();
    int?  selectedBarangayId;
    bool  obscure = true;

    final result = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Add Admin'),
          content: SizedBox(
            width: 360,
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(child: _field(firstCtrl, 'First Name')),
                        const SizedBox(width: 10),
                        Expanded(child: _field(lastCtrl, 'Last Name')),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _field(emailCtrl, 'Email',
                        keyboardType: TextInputType.emailAddress,
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return 'Required';
                          if (!v.contains('@')) return 'Invalid email';
                          return null;
                        }),
                    const SizedBox(height: 12),
                    _field(usernameCtrl, 'Username'),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: passwordCtrl,
                      obscureText: obscure,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: Icon(obscure ? Icons.visibility_off : Icons.visibility),
                          onPressed: () => setS(() => obscure = !obscure),
                        ),
                      ),
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'Required';
                        if (v.length < 6) return 'At least 6 characters';
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int?>(
                      initialValue: selectedBarangayId,
                      decoration: const InputDecoration(
                        labelText: 'Assign to Barangay',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        const DropdownMenuItem<int?>(
                          value: null,
                          child: Text('— None —'),
                        ),
                        ..._barangays.map((b) => DropdownMenuItem<int?>(
                          value: b['id'] as int?,
                          child: Text(b['name'] ?? ''),
                        )),
                      ],
                      onChanged: (v) => setS(() => selectedBarangayId = v),
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (formKey.currentState!.validate()) Navigator.pop(ctx, true);
              },
              style: FilledButton.styleFrom(backgroundColor: _kPrimary),
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );

    if (result != true || !mounted) return;

    try {
      final api = Provider.of<ApiService>(context, listen: false);
      await api.createAdmin(
        email:      emailCtrl.text.trim(),
        username:   usernameCtrl.text.trim(),
        password:   passwordCtrl.text,
        firstName:  firstCtrl.text.trim(),
        lastName:   lastCtrl.text.trim(),
        barangayId: selectedBarangayId,
      );
      await _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Admin added successfully.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceFirst('Exception: ', '')),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _deleteAdmin(Map<String, dynamic> admin) async {
    final name = '${admin['first_name'] ?? ''} ${admin['last_name'] ?? ''}'.trim();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Admin'),
        content: Text(
          'Remove "${name.isNotEmpty ? name : admin['email']}"? This cannot be undone.',
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
      await api.deleteUser(admin['id'] as int);
      await _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Admin removed.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceFirst('Exception: ', '')),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ── build ───────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        title: const Text('Admins Management'),
        backgroundColor: _kPrimary,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _loadData,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddAdminDialog,
        backgroundColor: _kPrimary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text('Add Admin'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: _kPrimary))
          : _error != null
              ? _buildError()
              : RefreshIndicator(
                  color: _kPrimary,
                  onRefresh: _loadData,
                  child: _admins.isEmpty
                      ? _buildEmpty()
                      : _buildList(),
                ),
    );
  }

  Widget _buildList() {
    final sections = _buildSections();
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
      itemCount: sections.fold<int>(0, (sum, s) => sum + 1 + s.admins.length),
      itemBuilder: (_, idx) {
        int offset = 0;
        for (final section in sections) {
          if (idx == offset) return _SectionHeader(title: section.title, count: section.admins.length);
          offset++;
          if (idx < offset + section.admins.length) {
            return _AdminCard(
              admin: section.admins[idx - offset],
              onDelete: _deleteAdmin,
            );
          }
          offset += section.admins.length;
        }
        return const SizedBox.shrink();
      },
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.manage_accounts_rounded, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text('No admins found.',
              style: TextStyle(fontSize: 16, color: Colors.grey.shade500)),
          const SizedBox(height: 8),
          Text('Tap "Add Admin" to create one.',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade400)),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 48, color: _kPrimary),
          const SizedBox(height: 12),
          Text(_error!, style: const TextStyle(color: _kCharcoal)),
          const SizedBox(height: 16),
          OutlinedButton(onPressed: _loadData, child: const Text('Retry')),
        ],
      ),
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

// ─────────────────────────────────────────────────────────────────────────────
// Section header
// ─────────────────────────────────────────────────────────────────────────────

class _Section {
  final String title;
  final List<Map<String, dynamic>> admins;
  _Section(this.title, this.admins);
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final int count;
  const _SectionHeader({required this.title, required this.count});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
      child: Row(
        children: [
          Container(
            width: 4, height: 18,
            decoration: BoxDecoration(
              color: _kPrimary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: _kCharcoal,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: _kCharcoal.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '$count admin${count != 1 ? "s" : ""}',
              style: TextStyle(
                fontSize: 11,
                color: _kCharcoal.withValues(alpha: 0.6),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Admin card
// ─────────────────────────────────────────────────────────────────────────────

class _AdminCard extends StatelessWidget {
  final Map<String, dynamic> admin;
  final Future<void> Function(Map<String, dynamic>) onDelete;
  const _AdminCard({required this.admin, required this.onDelete});

  String _initials(String first, String last, String username) {
    if (first.isNotEmpty && last.isNotEmpty) return '${first[0]}${last[0]}'.toUpperCase();
    if (first.isNotEmpty) return first[0].toUpperCase();
    if (username.isNotEmpty) return username[0].toUpperCase();
    return '?';
  }

  @override
  Widget build(BuildContext context) {
    final first    = (admin['first_name'] ?? '') as String;
    final last     = (admin['last_name']  ?? '') as String;
    final username = (admin['username']   ?? '') as String;
    final email    = (admin['email']      ?? '—') as String;
    final fullName = '$first $last'.trim();
    final display  = fullName.isNotEmpty ? fullName : username;
    final role     = (admin['role'] ?? 'admin') as String;
    final isSuperAdmin = role == 'superadmin';

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: (isSuperAdmin ? _kPrimary : _kCharcoal).withValues(alpha: 0.12),
              child: Text(
                _initials(first, last, username),
                style: TextStyle(
                  color: isSuperAdmin ? _kPrimary : _kCharcoal,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    display,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
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
                color: isSuperAdmin
                    ? _kPrimary.withValues(alpha: 0.1)
                    : _kCharcoal.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                isSuperAdmin ? 'Superadmin' : 'Admin',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: isSuperAdmin ? _kPrimary : _kCharcoal,
                ),
              ),
            ),
            if (!isSuperAdmin) ...[
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.person_remove_outlined, color: Colors.red, size: 20),
                tooltip: 'Remove admin',
                onPressed: () => onDelete(admin),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
