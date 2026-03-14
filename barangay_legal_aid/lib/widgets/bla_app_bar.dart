import 'package:flutter/material.dart';
import 'package:barangay_legal_aid/config/env_config.dart';
import 'package:barangay_legal_aid/services/auth_service.dart';

const _kPrimary = Color(0xFF99272D);

/// Shared AppBar for all dashboards.
/// Usage:
///   appBar: BlaAppBar(
///     title: 'Admin Dashboard',
///     user: _currentUser,           // Map from /auth/me
///     notificationBell: myBellWidget,  // optional
///   ),
class BlaAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final Map<String, dynamic>? user;
  final Widget? notificationBell;
  final List<Widget>? extraActions;

  const BlaAppBar({
    super.key,
    required this.title,
    this.user,
    this.notificationBell,
    this.extraActions,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  String _initials() {
    final f = (user?['first_name'] ?? '') as String;
    final l = (user?['last_name']  ?? '') as String;
    if (f.isNotEmpty && l.isNotEmpty) return '${f[0]}${l[0]}'.toUpperCase();
    if (f.isNotEmpty) return f[0].toUpperCase();
    return '?';
  }

  String _displayName() {
    final f = (user?['first_name'] ?? '') as String;
    final l = (user?['last_name']  ?? '') as String;
    final full = '$f $l'.trim();
    return full.isNotEmpty ? full : (user?['email'] ?? 'User');
  }

  String _role() {
    final r = (user?['role'] ?? 'user') as String;
    return r[0].toUpperCase() + r.substring(1);
  }

  String? _photoUrl() {
    final path = user?['profile_photo_path'] as String?;
    if (path == null || path.isEmpty) return null;
    return '$apiBaseUrl$path';
  }

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: _kPrimary,
      foregroundColor: Colors.white,
      elevation: 0,
      title: Text(title,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
      actions: [
        if (notificationBell != null) notificationBell!,
        ...?extraActions,
        const SizedBox(width: 4),
        _AvatarButton(
          initials: _initials(),
          photoUrl: _photoUrl(),
          displayName: _displayName(),
          role: _role(),
        ),
        const SizedBox(width: 8),
      ],
    );
  }
}

/// Avatar button that opens a bottom sheet with profile options.
class _AvatarButton extends StatelessWidget {
  final String initials;
  final String? photoUrl;
  final String displayName;
  final String role;

  const _AvatarButton({
    required this.initials,
    this.photoUrl,
    required this.displayName,
    required this.role,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _showMenu(context),
      child: CircleAvatar(
        radius: 17,
        backgroundColor: Colors.white24,
        backgroundImage: photoUrl != null ? NetworkImage(photoUrl!) : null,
        child: photoUrl == null
            ? Text(initials,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ))
            : null,
      ),
    );
  }

  void _showMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _ProfileSheet(
        initials: initials,
        photoUrl: photoUrl,
        displayName: displayName,
        role: role,
      ),
    );
  }
}

class _ProfileSheet extends StatelessWidget {
  final String initials;
  final String? photoUrl;
  final String displayName;
  final String role;

  const _ProfileSheet({
    required this.initials,
    this.photoUrl,
    required this.displayName,
    required this.role,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // Avatar + name
            CircleAvatar(
              radius: 34,
              backgroundColor: _kPrimary.withValues(alpha: 0.12),
              backgroundImage: photoUrl != null ? NetworkImage(photoUrl!) : null,
              child: photoUrl == null
                  ? Text(initials,
                      style: const TextStyle(
                        color: _kPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 22,
                      ))
                  : null,
            ),
            const SizedBox(height: 10),
            Text(displayName,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                )),
            const SizedBox(height: 2),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: _kPrimary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(role,
                  style: const TextStyle(
                    fontSize: 12,
                    color: _kPrimary,
                    fontWeight: FontWeight.w600,
                  )),
            ),
            const SizedBox(height: 20),
            const Divider(height: 1),
            const SizedBox(height: 8),

            // View Profile
            ListTile(
              leading: const Icon(Icons.person_outline_rounded, color: _kPrimary),
              title: const Text('View Profile'),
              contentPadding: EdgeInsets.zero,
              onTap: () {
                Navigator.pop(context);
                Navigator.pushNamed(context, '/profile');
              },
            ),

            // Logout
            ListTile(
              leading: const Icon(Icons.logout_rounded, color: Colors.red),
              title: const Text('Logout', style: TextStyle(color: Colors.red)),
              contentPadding: EdgeInsets.zero,
              onTap: () async {
                Navigator.pop(context);
                final nav = Navigator.of(context);
                await AuthService().logout();
                nav.pushNamedAndRemoveUntil('/login', (_) => false);
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Helper: greeting based on time of day
String blaGreeting(String firstName) {
  final hour = DateTime.now().hour;
  final tod = hour < 12 ? 'Good Morning' : hour < 17 ? 'Good Afternoon' : 'Good Evening';
  return '$tod, $firstName!';
}
