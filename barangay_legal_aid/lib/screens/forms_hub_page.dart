import 'package:flutter/material.dart';
import 'package:barangay_legal_aid/screens/user_profile_page.dart';
import 'package:barangay_legal_aid/screens/request_form.dart';
import 'package:barangay_legal_aid/screens/complaint_form_screen.dart';
import 'package:barangay_legal_aid/screens/suggestion_box_screen.dart';
import 'package:barangay_legal_aid/screens/my_requests_screen.dart';
import 'package:barangay_legal_aid/screens/my_cases_screen.dart';
import 'package:barangay_legal_aid/services/auth_service.dart';
import 'package:barangay_legal_aid/models/user_model.dart';

class FormsHubPage extends StatefulWidget {
  const FormsHubPage({super.key});

  @override
  FormsHubPageState createState() => FormsHubPageState();
}

class FormsHubPageState extends State<FormsHubPage> {
  final AuthService _authService = AuthService();
  User? _currentUser;

  @override
  void initState() {
    super.initState();
    _loadCurrentUser();
  }

  Future<void> _loadCurrentUser() async {
    final user = await _authService.getCurrentUser();
    setState(() {
      _currentUser = user;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Forms & Services'),
        backgroundColor: Color(0xFF99272D),
        foregroundColor: Colors.white,
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
                color: Colors.white.withValues(alpha:0.9),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActionsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Quick Actions',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Color(0xFF36454F),
          ),
        ),
        SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _buildQuickActionCard(
                title: 'My Profile',
                subtitle: 'View & Edit',
                icon: Icons.person,
                color: Color(0xFF99272D),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => UserProfilePage()),
                ),
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: _buildQuickActionCard(
                title: 'My Requests',
                subtitle: 'Track & Download',
                icon: Icons.folder_open_outlined,
                color: Color(0xFF1565C0),
                onTap: () {
                  if (_currentUser != null) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => MyRequestsScreen(currentUser: _currentUser!),
                      ),
                    );
                  }
                },
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: _buildQuickActionCard(
                title: 'File a Complaint',
                subtitle: 'Submit Now',
                icon: Icons.report_problem_rounded,
                color: Color(0xFFF44336),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ComplaintFormScreen()),
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildQuickActionCard(
                title: 'Suggestion',
                subtitle: 'Share Ideas',
                icon: Icons.lightbulb,
                color: Color(0xFFFFC107),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SuggestionBoxScreen()),
                ),
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: _buildQuickActionCard(
                title: 'My Complaints',
                subtitle: 'Track Status',
                icon: Icons.fact_check_outlined,
                color: Color(0xFF6366F1),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const MyCasesScreen()),
                ),
              ),
            ),
            SizedBox(width: 12),
            Expanded(child: SizedBox()),
          ],
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
          onTap: () => _navigateToRequestForm('Certificate of Good Moral Character'),
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
          title: 'Certificate of Live Birth',
          description: 'Barangay certification for birth registration',
          icon: Icons.child_care,
          color: Color(0xFF00BCD4),
          onTap: () => _navigateToRequestForm('Certificate of Live Birth'),
        ),
        SizedBox(height: 12),
        _buildFormCard(
          title: 'Certificate of Death',
          description: 'Barangay certification for death registration',
          icon: Icons.person_off_outlined,
          color: Color(0xFF9E9E9E),
          onTap: () => _navigateToRequestForm('Certificate of Death'),
        ),
        SizedBox(height: 12),
        _buildFormCard(
          title: 'Certificate of Marriage',
          description: 'Barangay certification supporting marriage documents',
          icon: Icons.favorite_outline,
          color: Color(0xFFE91E63),
          onTap: () => _navigateToRequestForm('Certificate of Marriage'),
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
        child: Container(
          padding: EdgeInsets.all(16),
          child: Column(
            children: [
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withValues(alpha:0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              SizedBox(height: 12),
              Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF36454F),
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12,
                  color: Color(0xFF36454F).withValues(alpha:0.7),
                ),
                textAlign: TextAlign.center,
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
                  color: color.withValues(alpha:0.1),
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
                        color: Color(0xFF36454F).withValues(alpha:0.7),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios, color: Color(0xFF36454F).withValues(alpha:0.5), size: 16),
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
