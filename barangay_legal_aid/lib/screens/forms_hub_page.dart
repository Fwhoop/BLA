import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:barangay_legal_aid/screens/user_profile_page.dart';
import 'package:barangay_legal_aid/screens/request_form.dart';
import 'package:barangay_legal_aid/screens/complaint_form_screen.dart';
import 'package:barangay_legal_aid/screens/suggestion_box_screen.dart';
import 'package:barangay_legal_aid/screens/my_requests_screen.dart';
import 'package:barangay_legal_aid/screens/my_cases_screen.dart';
import 'package:barangay_legal_aid/screens/notification_screen.dart';
import 'package:barangay_legal_aid/services/auth_service.dart';
import 'package:barangay_legal_aid/services/api_service.dart';
import 'package:barangay_legal_aid/models/user_model.dart';
import 'package:barangay_legal_aid/widgets/bla_app_bar.dart';

class FormsHubPage extends StatefulWidget {
  const FormsHubPage({super.key});

  @override
  FormsHubPageState createState() => FormsHubPageState();
}

class FormsHubPageState extends State<FormsHubPage> {
  final AuthService _authService = AuthService();
  User? _currentUser;
  int _unreadCount = 0;

  @override
  void initState() {
    super.initState();
    _loadCurrentUser();
    _loadUnreadCount();
  }

  Future<void> _loadCurrentUser() async {
    final user = await _authService.getCurrentUser();
    if (mounted)
      setState(() {
        _currentUser = user;
      });
  }

  Future<void> _loadUnreadCount() async {
    try {
      final api = Provider.of<ApiService>(context, listen: false);
      final count = await api.getUnreadNotificationCount();
      if (mounted)
        setState(() {
          _unreadCount = count;
        });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: BlaAppBar(
        title: 'Forms & Services',
        user: _currentUser == null
            ? null
            : {
                'first_name': _currentUser!.firstName,
                'last_name': _currentUser!.lastName,
                'role': _currentUser!.role.toString().split('.').last,
                'email': _currentUser!.email,
                'profile_photo_path': '',
              },
        notificationBell: NotificationBell(
          count: _unreadCount,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => NotificationScreen(
                userRole: 'user',
                currentUser: _currentUser,
              ),
            ),
          ),
        ),
      ),
      body: Container(
        color: Color(0xFFFFFFFF),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: SingleChildScrollView(
              padding: EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildWelcomeCard(),
                  SizedBox(height: 24),
                  _buildQuickActionsSection(),
                  SizedBox(height: 24),
                  _buildFormsSection(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWelcomeCard() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        padding: EdgeInsets.all(24),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: [Color(0xFF99272D), Color(0xFF36454F)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.dashboard, color: Colors.white, size: 28),
                SizedBox(width: 12),
                Text(
                  'Welcome, ${_currentUser?.firstName ?? 'User'}!',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            SizedBox(height: 12),
            Text(
              'Access all forms and services in one place. Complete your profile, submit requests, and manage your account easily.',
              style: TextStyle(
                fontSize: 16,
                color: Colors.white.withValues(alpha: 0.9),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActionsSection() {
    final actions = [
      _QuickActionItem(
        title: 'My Profile',
        subtitle: 'View & Edit',
        icon: Icons.person,
        color: const Color(0xFF99272D),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => UserProfilePage()),
        ),
      ),
      _QuickActionItem(
        title: 'My Requests',
        subtitle: 'Track & Download',
        icon: Icons.folder_open,
        color: const Color(0xFF1565C0),
        onTap: () {
          if (_currentUser != null)
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => MyRequestsScreen(currentUser: _currentUser!),
              ),
            );
        },
      ),
      _QuickActionItem(
        title: 'File a Complaint',
        subtitle: 'Submit Now',
        icon: Icons.report_problem_rounded,
        color: const Color(0xFFF44336),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ComplaintFormScreen()),
        ),
      ),
      _QuickActionItem(
        title: 'Suggestion',
        subtitle: 'Share Ideas',
        icon: Icons.lightbulb,
        color: const Color(0xFFFFC107),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const SuggestionBoxScreen()),
        ),
      ),
      _QuickActionItem(
        title: 'My Complaints',
        subtitle: 'Track Status',
        icon: Icons.assignment_outlined,
        color: const Color(0xFF6A1B9A),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const MyCasesScreen()),
        ),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Quick Actions',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Color(0xFF36454F),
          ),
        ),
        const SizedBox(height: 16),
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          childAspectRatio: 0.82,
          children: actions
              .map(
                (a) => _buildQuickActionCard(
                  title: a.title,
                  subtitle: a.subtitle,
                  icon: a.icon,
                  color: a.color,
                  onTap: a.onTap,
                ),
              )
              .toList(),
        ),
      ],
    );
  }

  Widget _buildFormsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Available Forms',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Color(0xFF36454F),
          ),
        ),
        SizedBox(height: 16),
        _buildFormCard(
          title: 'Barangay Clearance',
          description: 'Request a barangay clearance certificate',
          icon: Icons.verified_user,
          color: Color(0xFF4CAF50),
          onTap: () => _navigateToRequestForm('Barangay Clearance'),
        ),
        SizedBox(height: 12),
        _buildFormCard(
          title: 'Certificate of Residency',
          description: 'Get proof of residency from your barangay',
          icon: Icons.home,
          color: Color(0xFF2196F3),
          onTap: () => _navigateToRequestForm('Certificate of Residency'),
        ),
        SizedBox(height: 12),
        _buildFormCard(
          title: 'Certificate of Good Moral Character',
          description: 'Request a good moral character certificate',
          icon: Icons.star,
          color: Color(0xFFFF9800),
          onTap: () =>
              _navigateToRequestForm('Certificate of Good Moral Character'),
        ),
        SizedBox(height: 12),
        _buildFormCard(
          title: 'Certificate of Indigency',
          description: 'Apply for indigency certificate',
          icon: Icons.support,
          color: Color(0xFF9C27B0),
          onTap: () => _navigateToRequestForm('Certificate of Indigency'),
        ),
        SizedBox(height: 12),
        _buildFormCard(
          title: 'Certificate of No Property',
          description: 'Certify that you do not own real property',
          icon: Icons.house_outlined,
          color: Color(0xFF607D8B),
          onTap: () => _navigateToRequestForm('Certificate of No Property'),
        ),
        SizedBox(height: 12),
        _buildFormCard(
          title: 'Certificate of No Income',
          description: 'Certify that you have no regular income',
          icon: Icons.money_off,
          color: Color(0xFF795548),
          onTap: () => _navigateToRequestForm('Certificate of No Income'),
        ),
        SizedBox(height: 12),
        _buildFormCard(
          title: 'Certificate of Single Status',
          description: 'Certify that you are unmarried / single',
          icon: Icons.person_search,
          color: Color(0xFF3F51B5),
          onTap: () => _navigateToRequestForm('Certificate of Single Status'),
        ),
      ],
    );
  }

  Widget _buildQuickActionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(height: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF36454F),
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 10,
                  color: const Color(0xFF36454F).withValues(alpha: 0.65),
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFormCard({
    required String title,
    required String description,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF36454F),
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      description,
                      style: TextStyle(
                        fontSize: 14,
                        color: Color(0xFF36454F).withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios,
                color: Color(0xFF36454F).withValues(alpha: 0.5),
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _navigateToRequestForm(String documentType) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RequestForm(
          userBarangay: _currentUser?.barangay ?? '',
          preselectedDocumentType: documentType,
        ),
      ),
    );
  }
}

class _QuickActionItem {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _QuickActionItem({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });
}
