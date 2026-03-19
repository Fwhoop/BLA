import 'package:flutter/material.dart';
import 'package:barangay_legal_aid/config/env_config.dart';
import 'package:barangay_legal_aid/services/auth_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  final PreferredSizeWidget? bottom;

  const BlaAppBar({
    super.key,
    required this.title,
    this.user,
    this.notificationBell,
    this.extraActions,
    this.bottom,
  });

  @override
  Size get preferredSize => Size.fromHeight(
        kToolbarHeight + (bottom?.preferredSize.height ?? 0),
      );

  String _initials() {
    final f = (user?['first_name'] ?? '') as String;
    final l = (user?['last_name']  ?? '') as String;
    if (f.isNotEmpty && l.isNotEmpty) return '${f[0]}${l[0]}'.toUpperCase();
    if (f.isNotEmpty) return f[0].toUpperCase();
    return '?';
  }

  String _displayName() {
    final f  = (user?['first_name']  ?? '') as String;
    final l  = (user?['last_name']   ?? '') as String;
    final mn = (user?['middle_name'] ?? '') as String;
    final mi = mn.isNotEmpty ? '${mn[0].toUpperCase()}. ' : '';
    final full = '$f $mi$l'.trim();
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
      bottom: bottom,
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
    showDialog(
      context: context,
      barrierColor: Colors.black38,
      builder: (_) => _ProfileDialog(
        initials: initials,
        photoUrl: photoUrl,
        displayName: displayName,
        role: role,
      ),
    );
  }
}

class _ProfileDialog extends StatelessWidget {
  final String initials;
  final String? photoUrl;
  final String displayName;
  final String role;

  const _ProfileDialog({
    required this.initials,
    this.photoUrl,
    required this.displayName,
    required this.role,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      // Anchor to top-right, just below the AppBar
      alignment: Alignment.topRight,
      child: Padding(
        padding: const EdgeInsets.only(top: 56, right: 12),
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: 280,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header strip with avatar + close button
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(20, 20, 12, 16),
                  decoration: BoxDecoration(
                    color: _kPrimary.withValues(alpha: 0.06),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                        radius: 28,
                        backgroundColor: _kPrimary.withValues(alpha: 0.14),
                        backgroundImage: photoUrl != null ? NetworkImage(photoUrl!) : null,
                        child: photoUrl == null
                            ? Text(initials,
                                style: const TextStyle(
                                  color: _kPrimary,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 20,
                                ))
                            : null,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 2),
                            Text(
                              displayName,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: Color(0xFF36454F),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 5),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: _kPrimary.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                role,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: _kPrimary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Close button
                      InkWell(
                        onTap: () => Navigator.pop(context),
                        borderRadius: BorderRadius.circular(20),
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Icon(Icons.close, size: 18, color: Colors.grey.shade500),
                        ),
                      ),
                    ],
                  ),
                ),

                const Divider(height: 1, thickness: 1, color: Color(0xFFEEEEEE)),

                // View Profile
                _MenuItem(
                  icon: Icons.person_outline_rounded,
                  label: 'View Profile',
                  iconColor: _kPrimary,
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.pushNamed(context, '/profile');
                  },
                ),

                const Divider(height: 1, indent: 16, endIndent: 16, color: Color(0xFFF0F0F0)),

                // Logout
                _MenuItem(
                  icon: Icons.logout_rounded,
                  label: 'Logout',
                  iconColor: Colors.red,
                  labelColor: Colors.red,
                  onTap: () async {
                    Navigator.pop(context);
                    final nav = Navigator.of(context);
                    await AuthService().logout();
                    nav.pushNamedAndRemoveUntil('/login', (_) => false);
                  },
                ),

                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color iconColor;
  final Color labelColor;
  final VoidCallback onTap;

  const _MenuItem({
    required this.icon,
    required this.label,
    required this.iconColor,
    this.labelColor = const Color(0xFF36454F),
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, color: iconColor, size: 20),
            const SizedBox(width: 14),
            Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: labelColor)),
            const Spacer(),
            Icon(Icons.chevron_right, size: 16, color: Colors.grey.shade400),
          ],
        ),
      ),
    );
  }
}

/// Helper: greeting with role — e.g. "Good Morning, Admin Juan"
String blaGreeting(String firstName, {String role = ''}) {
  final hour = DateTime.now().hour;
  final tod = hour < 12 ? 'Good Morning' : hour < 17 ? 'Good Afternoon' : 'Good Evening';
  final roleLabel = role.isNotEmpty
      ? '${role[0].toUpperCase()}${role.substring(1)} '
      : '';
  return '$tod, $roleLabel$firstName';
}

/// Load lightweight user map from SharedPreferences (no HTTP call).
/// Stored at login: firstName, lastName, currentUserRole, currentUserEmail.
Future<Map<String, dynamic>> loadUserFromPrefs() async {
  final prefs = await SharedPreferences.getInstance();
  return {
    'first_name':  prefs.getString('firstName')  ?? '',
    'last_name':   prefs.getString('lastName')   ?? '',
    'middle_name': prefs.getString('middleName') ?? '',
    'role':        prefs.getString('currentUserRole')  ?? 'user',
    'email':       prefs.getString('currentUserEmail') ?? '',
    'profile_photo_path': prefs.getString('profilePhotoPath') ?? '',
  };
}
