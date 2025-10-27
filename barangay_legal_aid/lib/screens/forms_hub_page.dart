import 'package:flutter/material.dart';
import 'package:barangay_legal_aid/screens/user_profile_page.dart';
import 'package:barangay_legal_aid/screens/request_form.dart';
import 'package:barangay_legal_aid/services/auth_service.dart';
import 'package:barangay_legal_aid/models/user_model.dart';

class FormsHubPage extends StatefulWidget {
  @override
  _FormsHubPageState createState() => _FormsHubPageState();
}

class _FormsHubPageState extends State<FormsHubPage> {
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
              SizedBox(height: 24),
              _buildServicesSection(),
            ],
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
                color: Colors.white.withOpacity(0.9),
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
                title: 'Document Request',
                subtitle: 'Submit Request',
                icon: Icons.description,
                color: Color(0xFF36454F),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => RequestForm(userBarangay: _currentUser?.barangay ?? ''),
                  ),
                ),
              ),
            ),
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
      ],
    );
  }

  Widget _buildServicesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Other Services',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Color(0xFF36454F),
          ),
        ),
        SizedBox(height: 16),
        _buildServiceCard(
          title: 'Legal Consultation',
          description: 'Schedule a legal consultation appointment',
          icon: Icons.gavel,
          color: Color(0xFF99272D),
          onTap: () => _showComingSoon('Legal Consultation'),
        ),
        SizedBox(height: 12),
        _buildServiceCard(
          title: 'Complaint Form',
          description: 'Submit complaints or concerns',
          icon: Icons.report_problem,
          color: Color(0xFFF44336),
          onTap: () => _showComingSoon('Complaint Form'),
        ),
        SizedBox(height: 12),
        _buildServiceCard(
          title: 'Suggestion Box',
          description: 'Share your suggestions for improvement',
          icon: Icons.lightbulb,
          color: Color(0xFFFFC107),
          onTap: () => _showComingSoon('Suggestion Box'),
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
                  color: color.withOpacity(0.1),
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
                  color: Color(0xFF36454F).withOpacity(0.7),
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
                  color: color.withOpacity(0.1),
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
                        color: Color(0xFF36454F).withOpacity(0.7),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios, color: Color(0xFF36454F).withOpacity(0.5), size: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildServiceCard({
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
                  color: color.withOpacity(0.1),
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
                        color: Color(0xFF36454F).withOpacity(0.7),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios, color: Color(0xFF36454F).withOpacity(0.5), size: 16),
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
        builder: (_) => RequestForm(userBarangay: _currentUser?.barangay ?? ''),
      ),
    );
  }

  void _showComingSoon(String service) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$service - Coming Soon!'),
        backgroundColor: Color(0xFF36454F),
        duration: Duration(seconds: 2),
      ),
    );
  }
}
