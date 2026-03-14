import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:barangay_legal_aid/services/api_service.dart';
import 'package:barangay_legal_aid/config/env_config.dart';

const _kPrimary  = Color(0xFF99272D);
const _kCharcoal = Color(0xFF36454F);
const _kBg       = Color(0xFFF0F2F5);
const _kGreen    = Color(0xFF10B981);
const _kAmber    = Color(0xFFF59E0B);
const _kRed      = Color(0xFFEF4444);

class AdminUsersScreen extends StatefulWidget {
  const AdminUsersScreen({super.key});

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen>
    with SingleTickerProviderStateMixin {
  // Data
  List<Map<String, dynamic>> _users = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  int  _currentPage = 1;
  bool _hasMore = true;
  static const int _pageSize = 20;

  // Search + filter
  final _searchCtrl = TextEditingController();
  String _filterStatus = 'all'; // all, pending, approved, rejected, inactive
  Timer? _debounce;

  // Tabs
  late final TabController _tabCtrl;

  // Summary counts
  int _pendingCount = 0;
  int _activeCount  = 0;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _tabCtrl.addListener(() {
      if (!_tabCtrl.indexIsChanging) {
        // Sync filter with active tab
        final newFilter = _tabCtrl.index == 0 ? 'pending' : 'approved';
        if (_filterStatus != newFilter) {
          setState(() => _filterStatus = newFilter);
          _reload();
        }
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _filterStatus = 'pending';
      _loadUsers(reset: true);
    });
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _searchCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String val) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _reload);
  }

  void _reload() => _loadUsers(reset: true);

  Future<void> _loadUsers({bool reset = false}) async {
    if (reset) {
      setState(() { _currentPage = 1; _hasMore = true; _users = []; _isLoading = true; });
    } else {
      if (!_hasMore || _isLoadingMore) return;
      setState(() => _isLoadingMore = true);
    }

    try {
      final api = Provider.of<ApiService>(context, listen: false);
      final page = reset ? 1 : _currentPage;
      final results = await api.getUsers(
        search: _searchCtrl.text.trim().isEmpty ? null : _searchCtrl.text.trim(),
        status: _filterStatus == 'all' ? null : _filterStatus,
        page: page,
        limit: _pageSize,
      );

      // Also refresh summary counts when resetting
      if (reset) {
        try {
          final summary = await api.getUserSummary();
          _pendingCount = (summary['pending'] as int?) ?? 0;
          _activeCount  = (summary['approved'] as int?) ?? 0;
        } catch (_) {}
      }

      if (mounted) {
        setState(() {
          if (reset) {
            _users = results;
          } else {
            _users.addAll(results);
          }
          _currentPage = page + 1;
          _hasMore = results.length == _pageSize;
          _isLoading = false;
          _isLoadingMore = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() { _isLoading = false; _isLoadingMore = false; });
        _showError('Failed to load users: $e');
      }
    }
  }

  Future<void> _approveUser(Map<String, dynamic> user) async {
    try {
      final api = Provider.of<ApiService>(context, listen: false);
      await api.updateUser(user['id'] as int, {'is_active': true});
      _reload();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${_name(user)} has been approved.'),
          backgroundColor: _kGreen,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ));
      }
    } catch (e) {
      if (mounted) _showError('Failed to approve: $e');
    }
  }

  Future<void> _rejectUser(Map<String, dynamic> user) async {
    final confirm = await _confirm(
      'Reject Registration',
      'Reject ${_name(user)}? Their account will be marked as rejected.',
      destructive: true,
    );
    if (confirm != true || !mounted) return;
    try {
      final api = Provider.of<ApiService>(context, listen: false);
      await api.updateUser(user['id'] as int, {'verification_status': 'rejected'});
      _reload();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Registration rejected.'),
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      if (mounted) _showError('Failed to reject: $e');
    }
  }

  Future<void> _deactivateUser(Map<String, dynamic> user) async {
    final confirm = await _confirm(
      'Deactivate Account',
      'Deactivate ${_name(user)}? They will not be able to log in until reactivated.',
    );
    if (confirm != true || !mounted) return;
    try {
      final api = Provider.of<ApiService>(context, listen: false);
      await api.updateUser(user['id'] as int, {'is_active': false});
      _reload();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('User deactivated.'),
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      if (mounted) _showError('Failed to deactivate: $e');
    }
  }

  Future<void> _deleteUser(Map<String, dynamic> user) async {
    final confirm = await _confirm(
      'Delete Account',
      'Permanently delete ${_name(user)}? This cannot be undone.',
      destructive: true,
    );
    if (confirm != true || !mounted) return;
    try {
      final api = Provider.of<ApiService>(context, listen: false);
      await api.deleteUser(user['id'] as int);
      _reload();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('User deleted.'),
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      if (mounted) _showError('Failed to delete: $e');
    }
  }

  Future<bool?> _confirm(String title, String body, {bool destructive = false}) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: destructive ? _kRed : _kGreen,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: Text(destructive ? 'Confirm' : 'Confirm'),
          ),
        ],
      ),
    );
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: _kRed,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  String _name(Map<String, dynamic> u) {
    final n = '${u['first_name'] ?? ''} ${u['last_name'] ?? ''}'.trim();
    return n.isNotEmpty ? n : (u['email'] ?? 'User');
  }

  void _openDetail(Map<String, dynamic> user) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _UserDetailSheet(
        user: user,
        onApprove: () { Navigator.pop(context); _approveUser(user); },
        onReject:  () { Navigator.pop(context); _rejectUser(user); },
        onDeactivate: () { Navigator.pop(context); _deactivateUser(user); },
        onDelete:  () { Navigator.pop(context); _deleteUser(user); },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        title: const Text('Users Management'),
        backgroundColor: _kPrimary,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
            onPressed: _reload,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(108),
          child: Column(
            children: [
              TabBar(
                controller: _tabCtrl,
                indicatorColor: Colors.white,
                indicatorWeight: 3,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white60,
                labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                tabs: [
                  Tab(child: _tabLabel('Pending', _pendingCount, _kAmber)),
                  Tab(child: _tabLabel('Active', _activeCount, _kGreen)),
                ],
              ),
              // Search + filter row
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 36,
                        child: TextField(
                          controller: _searchCtrl,
                          onChanged: _onSearchChanged,
                          style: const TextStyle(fontSize: 13, color: Colors.white),
                          decoration: InputDecoration(
                            hintText: 'Search by name, email, phone…',
                            hintStyle: const TextStyle(color: Colors.white54, fontSize: 13),
                            prefixIcon: const Icon(Icons.search, color: Colors.white54, size: 18),
                            suffixIcon: _searchCtrl.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear, color: Colors.white54, size: 16),
                                    onPressed: () { _searchCtrl.clear(); _reload(); },
                                  )
                                : null,
                            filled: true,
                            fillColor: Colors.white.withValues(alpha: 0.15),
                            contentPadding: EdgeInsets.zero,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    PopupMenuButton<String>(
                      initialValue: _filterStatus,
                      onSelected: (v) {
                        setState(() => _filterStatus = v);
                        _reload();
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'all',      child: Text('All users')),
                        PopupMenuItem(value: 'pending',  child: Text('Pending')),
                        PopupMenuItem(value: 'approved', child: Text('Approved')),
                        PopupMenuItem(value: 'rejected', child: Text('Rejected')),
                        PopupMenuItem(value: 'inactive', child: Text('Inactive')),
                      ],
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.filter_list, color: Colors.white, size: 16),
                            const SizedBox(width: 4),
                            Text(
                              _filterLabel(_filterStatus),
                              style: const TextStyle(color: Colors.white, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: _kPrimary))
          : TabBarView(
              controller: _tabCtrl,
              children: [
                _buildList(emptyMsg: 'No pending approvals', emptyIcon: Icons.how_to_reg_outlined, isPending: true),
                _buildList(emptyMsg: 'No active users', emptyIcon: Icons.people_outline_rounded, isPending: false),
              ],
            ),
    );
  }

  String _filterLabel(String s) {
    switch (s) {
      case 'pending':  return 'Pending';
      case 'approved': return 'Approved';
      case 'rejected': return 'Rejected';
      case 'inactive': return 'Inactive';
      default:         return 'All';
    }
  }

  Widget _tabLabel(String label, int count, Color badgeColor) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label),
        if (count > 0) ...[
          const SizedBox(width: 6),
          _TabBadge(count: count, color: badgeColor),
        ],
      ],
    );
  }

  Widget _buildList({
    required String emptyMsg,
    required IconData emptyIcon,
    required bool isPending,
  }) {
    if (_users.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80, height: 80,
              decoration: BoxDecoration(color: Colors.grey.shade100, shape: BoxShape.circle),
              child: Icon(emptyIcon, size: 40, color: Colors.grey.shade400),
            ),
            const SizedBox(height: 16),
            Text(emptyMsg,
                style: TextStyle(
                  color: _kCharcoal.withValues(alpha: 0.8),
                  fontSize: 16, fontWeight: FontWeight.w600,
                )),
            const SizedBox(height: 4),
            Text(_searchCtrl.text.isNotEmpty ? 'Try a different search term.' : '',
                style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: _kPrimary,
      onRefresh: () => _loadUsers(reset: true),
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        itemCount: _users.length + (_hasMore ? 1 : 0),
        itemBuilder: (_, i) {
          if (i == _users.length) {
            return _LoadMoreButton(
              isLoading: _isLoadingMore,
              onTap: () => _loadUsers(),
            );
          }
          final u = _users[i];
          return _UserCard(
            user: u,
            isPending: isPending,
            onTap: () => _openDetail(u),
            onApprove: () => _approveUser(u),
            onReject:  () => _rejectUser(u),
            onDeactivate: () => _deactivateUser(u),
            onDelete:  () => _deleteUser(u),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tab badge
// ─────────────────────────────────────────────────────────────────────────────

class _TabBadge extends StatelessWidget {
  final int count;
  final Color color;
  const _TabBadge({required this.count, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(10)),
      child: Text('$count',
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Load more button
// ─────────────────────────────────────────────────────────────────────────────

class _LoadMoreButton extends StatelessWidget {
  final bool isLoading;
  final VoidCallback onTap;
  const _LoadMoreButton({required this.isLoading, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: isLoading
            ? const CircularProgressIndicator(color: _kPrimary)
            : OutlinedButton.icon(
                onPressed: onTap,
                icon: const Icon(Icons.expand_more),
                label: const Text('Load more'),
              ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// User Card (compact summary)
// ─────────────────────────────────────────────────────────────────────────────

class _UserCard extends StatelessWidget {
  final Map<String, dynamic> user;
  final bool isPending;
  final VoidCallback onTap;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  final VoidCallback onDeactivate;
  final VoidCallback onDelete;

  const _UserCard({
    required this.user,
    required this.isPending,
    required this.onTap,
    required this.onApprove,
    required this.onReject,
    required this.onDeactivate,
    required this.onDelete,
  });

  String _initials() {
    final f = (user['first_name'] ?? '') as String;
    final l = (user['last_name']  ?? '') as String;
    if (f.isNotEmpty && l.isNotEmpty) return '${f[0]}${l[0]}'.toUpperCase();
    if (f.isNotEmpty) return f[0].toUpperCase();
    return '?';
  }

  String _formatDate(dynamic raw) {
    if (raw == null) return '';
    try {
      final dt = DateTime.parse(raw.toString()).toLocal();
      const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
      return 'Joined ${months[dt.month - 1]} ${dt.day}, ${dt.year}';
    } catch (_) { return ''; }
  }

  Color _statusColor() {
    final vs = user['verification_status'] as String? ?? '';
    if (vs == 'rejected') return _kRed;
    if (vs == 'approved' && user['is_active'] == true) return _kGreen;
    if (user['is_active'] == false && vs != 'pending') return Colors.grey;
    return _kAmber;
  }

  String _statusLabel() {
    final vs = user['verification_status'] as String? ?? '';
    if (vs == 'rejected') return 'Rejected';
    if (vs == 'approved' && user['is_active'] == true) return 'Active';
    if (user['is_active'] == false && vs != 'pending') return 'Inactive';
    return 'Pending';
  }

  @override
  Widget build(BuildContext context) {
    final first   = (user['first_name'] ?? '') as String;
    final last    = (user['last_name']  ?? '') as String;
    final email   = (user['email']      ?? '—') as String;
    final phone   = (user['phone']      ?? '') as String;
    final created = _formatDate(user['created_at']);
    final fullName = '$first $last'.trim();
    final display  = fullName.isNotEmpty ? fullName : email;
    final accent   = _statusColor();

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      color: Colors.white,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 4,
              decoration: BoxDecoration(
                color: accent,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      // Avatar
                      Container(
                        width: 46, height: 46,
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(_initials(),
                              style: TextStyle(color: accent, fontWeight: FontWeight.bold, fontSize: 16)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(display,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 14, color: _kCharcoal)),
                            const SizedBox(height: 2),
                            Text(email,
                                style: TextStyle(fontSize: 12, color: _kCharcoal.withValues(alpha: 0.5))),
                            if (phone.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(phone,
                                  style: TextStyle(fontSize: 12, color: _kCharcoal.withValues(alpha: 0.5))),
                            ],
                          ],
                        ),
                      ),
                      // Status badge
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: accent.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: accent.withValues(alpha: 0.3)),
                            ),
                            child: Text(_statusLabel(),
                                style: TextStyle(
                                    fontSize: 10, fontWeight: FontWeight.w700, color: accent)),
                          ),
                          if (created.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(created,
                                style: TextStyle(fontSize: 10, color: _kCharcoal.withValues(alpha: 0.4))),
                          ],
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // Action buttons
                  if (isPending)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        const Text('Tap to view details',
                            style: TextStyle(fontSize: 11, color: Colors.grey)),
                        const Spacer(),
                        OutlinedButton.icon(
                          onPressed: onReject,
                          icon: const Icon(Icons.close_rounded, size: 14, color: _kRed),
                          label: const Text('Reject', style: TextStyle(color: _kRed, fontSize: 12)),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: _kRed),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.icon(
                          onPressed: onApprove,
                          icon: const Icon(Icons.check_rounded, size: 14),
                          label: const Text('Approve', style: TextStyle(fontSize: 12)),
                          style: FilledButton.styleFrom(
                            backgroundColor: _kGreen,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                      ],
                    )
                  else
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        const Text('Tap for details',
                            style: TextStyle(fontSize: 11, color: Colors.grey)),
                        const Spacer(),
                        OutlinedButton.icon(
                          onPressed: onDeactivate,
                          icon: const Icon(Icons.block_rounded, size: 14, color: _kAmber),
                          label: const Text('Deactivate', style: TextStyle(color: _kAmber, fontSize: 12)),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: _kAmber),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.delete_outline_rounded, color: _kRed, size: 18),
                          onPressed: onDelete,
                          tooltip: 'Delete',
                          visualDensity: VisualDensity.compact,
                          style: IconButton.styleFrom(
                            backgroundColor: _kRed.withValues(alpha: 0.08),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// User Detail Bottom Sheet
// ─────────────────────────────────────────────────────────────────────────────

class _UserDetailSheet extends StatelessWidget {
  final Map<String, dynamic> user;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  final VoidCallback onDeactivate;
  final VoidCallback onDelete;

  const _UserDetailSheet({
    required this.user,
    required this.onApprove,
    required this.onReject,
    required this.onDeactivate,
    required this.onDelete,
  });

  bool get _isPending {
    final vs = user['verification_status'] as String? ?? 'pending';
    return vs == 'pending' || user['is_active'] == false;
  }

  String _fullName() {
    final n = '${user['first_name'] ?? ''} ${user['last_name'] ?? ''}'.trim();
    return n.isNotEmpty ? n : (user['email'] ?? 'User');
  }

  String _initials() {
    final f = (user['first_name'] ?? '') as String;
    final l = (user['last_name']  ?? '') as String;
    if (f.isNotEmpty && l.isNotEmpty) return '${f[0]}${l[0]}'.toUpperCase();
    return f.isNotEmpty ? f[0].toUpperCase() : '?';
  }

  String _buildAddress() {
    final parts = <String>[
      if ((user['house_number'] ?? '').toString().isNotEmpty) user['house_number'].toString(),
      if ((user['street_name']  ?? '').toString().isNotEmpty) user['street_name'].toString(),
      if ((user['purok']        ?? '').toString().isNotEmpty) 'Purok ${user['purok']}',
      if ((user['address']      ?? '').toString().isNotEmpty) user['address'].toString(),
      if ((user['city']         ?? '').toString().isNotEmpty) user['city'].toString(),
      if ((user['province']     ?? '').toString().isNotEmpty) user['province'].toString(),
      if ((user['zip_code']     ?? '').toString().isNotEmpty) user['zip_code'].toString(),
    ];
    return parts.join(', ');
  }

  void _viewPhoto(BuildContext context, String url, String title) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: Stack(
          children: [
            Container(
              constraints: const BoxConstraints(maxWidth: 600, maxHeight: 600),
              decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(16)),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Row(
                        children: [
                          Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          const Spacer(),
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.white),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: InteractiveViewer(
                        child: Image.network(
                          url, fit: BoxFit.contain,
                          loadingBuilder: (_, child, p) => p == null ? child
                              : const Center(child: CircularProgressIndicator(color: Colors.white)),
                          errorBuilder: (_, __, ___) => const Center(
                            child: Icon(Icons.broken_image_outlined, color: Colors.white54, size: 48),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final idPhotoUrl  = (user['id_photo_url']         ?? '') as String;
    final selfieUrl   = (user['selfie_with_id_path']  ?? '') as String;
    final profileUrl  = (user['profile_photo_path']   ?? '') as String;
    final email       = (user['email']                ?? '—') as String;
    final phone       = (user['phone']                ?? '') as String;
    final username    = (user['username']             ?? '') as String;
    final verStatus   = (user['verification_status']  ?? 'pending') as String;
    final address     = _buildAddress();

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      builder: (_, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // Handle
            Container(
              margin: const EdgeInsets.symmetric(vertical: 8),
              width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
            ),
            Expanded(
              child: ListView(
                controller: scrollCtrl,
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                children: [
                  // Header
                  Row(
                    children: [
                      Container(
                        width: 60, height: 60,
                        decoration: BoxDecoration(color: _kPrimary.withValues(alpha: 0.1), shape: BoxShape.circle),
                        child: Center(child: Text(_initials(),
                            style: const TextStyle(color: _kPrimary, fontWeight: FontWeight.bold, fontSize: 20))),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_fullName(),
                                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _kCharcoal)),
                            if (username.isNotEmpty)
                              Text('@$username', style: const TextStyle(fontSize: 13, color: Colors.grey)),
                          ],
                        ),
                      ),
                      _VerBadge(status: verStatus),
                    ],
                  ),

                  const SizedBox(height: 20),
                  const Divider(),
                  const SizedBox(height: 12),

                  // Contact info
                  _sheetSection('Contact', [
                    _sheetRow(Icons.email_outlined, email),
                    if (phone.isNotEmpty) _sheetRow(Icons.phone_outlined, phone),
                  ]),

                  // Address
                  if (address.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _sheetSection('Address', [_sheetRow(Icons.location_on_outlined, address)]),
                  ],

                  // Photos
                  const SizedBox(height: 16),
                  _sheetSectionLabel('Verification Photos'),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      if (profileUrl.isNotEmpty)
                        Expanded(child: _PhotoTile(
                          url: '$apiBaseUrl$profileUrl', label: 'Profile',
                          onTap: () => _viewPhoto(context, '$apiBaseUrl$profileUrl', 'Profile Photo'),
                        )),
                      if (profileUrl.isNotEmpty && idPhotoUrl.isNotEmpty) const SizedBox(width: 8),
                      if (idPhotoUrl.isNotEmpty)
                        Expanded(child: _PhotoTile(
                          url: '$apiBaseUrl$idPhotoUrl', label: 'Gov\'t ID',
                          onTap: () => _viewPhoto(context, '$apiBaseUrl$idPhotoUrl', 'Government ID'),
                        )),
                      if (idPhotoUrl.isNotEmpty && selfieUrl.isNotEmpty) const SizedBox(width: 8),
                      if (selfieUrl.isNotEmpty)
                        Expanded(child: _PhotoTile(
                          url: '$apiBaseUrl$selfieUrl', label: 'Selfie+ID',
                          onTap: () => _viewPhoto(context, '$apiBaseUrl$selfieUrl', 'Selfie with ID'),
                        )),
                    ],
                  ),
                  if (idPhotoUrl.isEmpty && selfieUrl.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF3C7),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.info_outline_rounded, size: 14, color: _kAmber),
                          SizedBox(width: 8),
                          Text('No verification photos uploaded', style: TextStyle(fontSize: 12, color: _kAmber)),
                        ],
                      ),
                    ),

                  const SizedBox(height: 28),

                  // Actions
                  if (_isPending) ...[
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: onReject,
                            icon: const Icon(Icons.close_rounded, color: _kRed, size: 16),
                            label: const Text('Reject', style: TextStyle(color: _kRed)),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: _kRed),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: onApprove,
                            icon: const Icon(Icons.check_rounded, size: 16),
                            label: const Text('Approve'),
                            style: FilledButton.styleFrom(
                              backgroundColor: _kGreen,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ] else ...[
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: onDeactivate,
                            icon: const Icon(Icons.block_rounded, color: _kAmber, size: 16),
                            label: const Text('Deactivate', style: TextStyle(color: _kAmber)),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: _kAmber),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        OutlinedButton.icon(
                          onPressed: onDelete,
                          icon: const Icon(Icons.delete_outline_rounded, color: _kRed, size: 16),
                          label: const Text('Delete', style: TextStyle(color: _kRed)),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: _kRed),
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sheetSection(String title, List<Widget> rows) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sheetSectionLabel(title),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: _kBg, borderRadius: BorderRadius.circular(10)),
          child: Column(children: rows),
        ),
      ],
    );
  }

  Widget _sheetSectionLabel(String label) {
    return Text(label,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
            color: Colors.grey, letterSpacing: 0.5));
  }

  Widget _sheetRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: _kCharcoal.withValues(alpha: 0.45)),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13, color: _kCharcoal))),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Verification status badge
// ─────────────────────────────────────────────────────────────────────────────

class _VerBadge extends StatelessWidget {
  final String status;
  const _VerBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    Color color;
    switch (status) {
      case 'approved': color = _kGreen;  break;
      case 'rejected': color = _kRed;    break;
      default:         color = _kAmber;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(status[0].toUpperCase() + status.substring(1),
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Photo tile
// ─────────────────────────────────────────────────────────────────────────────

class _PhotoTile extends StatelessWidget {
  final String url;
  final String label;
  final VoidCallback onTap;
  const _PhotoTile({required this.url, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
              child: Image.network(
                url, height: 90, width: double.infinity, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  height: 90, color: Colors.grey.shade100,
                  child: const Icon(Icons.image_not_supported_outlined, color: Colors.grey),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }
}
