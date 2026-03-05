import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:barangay_legal_aid/models/notification_model.dart';
import 'package:barangay_legal_aid/services/api_service.dart';
import 'package:barangay_legal_aid/screens/admin/requests_screen.dart';
import 'package:barangay_legal_aid/screens/admin/cases_screen.dart';
import 'package:barangay_legal_aid/screens/admin/users_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Reusable bell icon with unread badge — drop into any AppBar actions list
// ─────────────────────────────────────────────────────────────────────────────

class NotificationBell extends StatelessWidget {
  final int count;
  final VoidCallback onTap;

  const NotificationBell({super.key, required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        IconButton(
          icon: const Icon(Icons.notifications_outlined, color: Colors.white),
          tooltip: 'Notifications',
          onPressed: onTap,
        ),
        if (count > 0)
          Positioned(
            top: 8,
            right: 8,
            child: IgnorePointer(
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: const BoxDecoration(
                  color: Color(0xFFE53935),
                  shape: BoxShape.circle,
                ),
                constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                child: Text(
                  count > 99 ? '99+' : '$count',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    height: 1,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Notification screen
// ─────────────────────────────────────────────────────────────────────────────

class NotificationScreen extends StatefulWidget {
  /// 'admin', 'superadmin', or 'user'
  final String userRole;

  const NotificationScreen({super.key, this.userRole = 'user'});

  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen> {
  List<NotificationModel> _notifications = [];
  bool _isLoading = true;
  bool _markingAll = false;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    setState(() => _isLoading = true);
    try {
      final api = Provider.of<ApiService>(context, listen: false);
      final items = await api.getNotifications();
      if (mounted) setState(() => _notifications = items);
    } catch (_) {
      // silently fail — empty list shown
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _onTileTap(NotificationModel n) async {
    // Mark read (fire-and-forget visually)
    if (!n.isRead) {
      try {
        final api = Provider.of<ApiService>(context, listen: false);
        await api.markNotificationRead(n.id);
        if (!mounted) return;
        setState(() {
          final idx = _notifications.indexWhere((x) => x.id == n.id);
          if (idx != -1) _notifications[idx] = n.copyWith(isRead: true);
        });
      } catch (_) {}
    }
    if (!mounted) return;
    _navigateToReference(n);
  }

  void _navigateToReference(NotificationModel n) {
    final isAdmin = widget.userRole == 'admin' || widget.userRole == 'superadmin';
    if (isAdmin) {
      switch (n.notifType) {
        case 'new_request':
        case 'request_update':
          Navigator.push(context,
              MaterialPageRoute(builder: (_) => const AdminRequestsScreen()));
          break;
        case 'new_case':
        case 'case_update':
          Navigator.push(context,
              MaterialPageRoute(builder: (_) => const AdminCasesScreen()));
          break;
        case 'new_user':
          Navigator.push(context,
              MaterialPageRoute(builder: (_) => const AdminUsersScreen()));
          break;
      }
    } else {
      // Users: go to forms hub (where they can see their requests and cases)
      Navigator.pushNamed(context, '/forms');
    }
  }

  Future<void> _markAllRead() async {
    if (_markingAll) return;
    setState(() => _markingAll = true);
    try {
      final api = Provider.of<ApiService>(context, listen: false);
      await api.markAllNotificationsRead();
      if (!mounted) return;
      setState(() {
        _notifications = _notifications.map((n) => n.copyWith(isRead: true)).toList();
      });
    } catch (_) {
    } finally {
      if (mounted) setState(() => _markingAll = false);
    }
  }

  int get _unreadCount => _notifications.where((n) => !n.isRead).length;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      appBar: AppBar(
        title: const Text('Notifications'),
        backgroundColor: const Color(0xFF99272D),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (_unreadCount > 0)
            _markingAll
                ? const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      ),
                    ),
                  )
                : TextButton(
                    onPressed: _markAllRead,
                    child: const Text(
                      'Mark all read',
                      style: TextStyle(color: Colors.white70),
                    ),
                  ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _notifications.isEmpty
              ? _buildEmptyState()
              : RefreshIndicator(
                  onRefresh: _loadNotifications,
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: _notifications.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 1),
                    itemBuilder: (context, i) =>
                        _NotificationTile(
                          notification: _notifications[i],
                          onTap: () => _onTileTap(_notifications[i]),
                        ),
                  ),
                ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.notifications_none,
            size: 72,
            color: Colors.grey[350],
          ),
          const SizedBox(height: 16),
          Text(
            'No notifications yet',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[500],
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'You\'ll be notified about your requests\nand case updates here.',
            style: TextStyle(fontSize: 13, color: Colors.grey[400]),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Individual notification tile
// ─────────────────────────────────────────────────────────────────────────────

class _NotificationTile extends StatelessWidget {
  final NotificationModel notification;
  final VoidCallback onTap;

  const _NotificationTile({required this.notification, required this.onTap});

  Color get _iconColor {
    switch (notification.notifType) {
      case 'request_update':
        final msg = notification.message.toLowerCase();
        if (msg.contains('approved')) return const Color(0xFF43A047);
        if (msg.contains('rejected')) return const Color(0xFFE53935);
        return const Color(0xFF1E88E5);
      case 'new_request':
        return const Color(0xFFFB8C00);
      case 'new_case':
        return const Color(0xFFFB8C00);
      case 'case_update':
        return const Color(0xFF1E88E5);
      case 'new_user':
        return const Color(0xFF8B5CF6);
      default:
        return Colors.grey;
    }
  }

  IconData get _icon {
    switch (notification.notifType) {
      case 'request_update':
        final msg = notification.message.toLowerCase();
        if (msg.contains('approved')) return Icons.check_circle;
        if (msg.contains('rejected')) return Icons.cancel;
        return Icons.assignment;
      case 'new_request':
        return Icons.assignment_add;
      case 'new_case':
        return Icons.report_problem;
      case 'case_update':
        return Icons.update;
      case 'new_user':
        return Icons.person_add_alt_1_rounded;
      default:
        return Icons.notifications;
    }
  }

  String _relativeTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} hr ago';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays} days ago';
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[dt.month - 1]} ${dt.day}';
  }

  @override
  Widget build(BuildContext context) {
    final isUnread = !notification.isRead;
    return Material(
      color: isUnread ? const Color(0xFFE3F2FD) : Colors.white,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Colored icon circle
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: _iconColor.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(_icon, color: _iconColor, size: 22),
              ),
              const SizedBox(width: 12),
              // Text content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            notification.title,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: isUnread
                                  ? FontWeight.bold
                                  : FontWeight.w500,
                              color: const Color(0xFF1A1A2E),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _relativeTime(notification.createdAt.toLocal()),
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[500],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      notification.message,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey[700],
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              // Unread dot
              if (isUnread)
                Padding(
                  padding: const EdgeInsets.only(left: 8, top: 4),
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Color(0xFF1E88E5),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
