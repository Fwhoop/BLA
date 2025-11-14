import 'package:flutter/material.dart';
import 'package:barangay_legal_aid/services/auth_service.dart';
import 'package:barangay_legal_aid/screens/admin/users_screen.dart';
import 'package:barangay_legal_aid/screens/admin/cases_screen.dart';
import 'package:barangay_legal_aid/screens/admin/chats_screen.dart';
import 'package:barangay_legal_aid/screens/admin/reports_screen.dart';
import 'package:barangay_legal_aid/screens/admin/settings_screen.dart';
import 'package:barangay_legal_aid/screens/admin/requests_screen.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  _AdminDashboardState createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Admin Dashboard'),
        backgroundColor: Color(0xFF99272D),
        foregroundColor: Colors.white,
        actions: [
          TextButton(
            onPressed: () async {
              await AuthService().logout();
              Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
            },
            child: Text(
              'LOGOUT',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
      body: Container(
        color: Color(0xFFFFFFFF),
        padding: EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 1600),
            child: GridView.builder(
          gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 280,
            crossAxisSpacing: 14,
            mainAxisSpacing: 14,
            childAspectRatio: 1.1,
          ),
          itemCount: 6,
          itemBuilder: (context, index) {
            final items = [
              {
                'title': 'Requests',
                'icon': '📝',
                'desc': 'View document requests',
                'color': Color(0xFF99272D),
                'route': AdminRequestsScreen(),
              },
              {
                'title': 'Users',
                'icon': '👥',
                'desc': 'Manage users',
                'color': Color(0xFF36454F),
                'route': AdminUsersScreen(),
              },
              {
                'title': 'Cases',
                'icon': '📋',
                'desc': 'Track legal cases',
                'color': Color(0xFF99272D),
                'route': AdminCasesScreen(),
              },
              {
                'title': 'Chats',
                'icon': '💬',
                'desc': 'Monitor conversations',
                'color': Color(0xFF36454F),
                'route': AdminChatsScreen(),
              },
              {
                'title': 'Reports',
                'icon': '📊',
                'desc': 'View analytics',
                'color': Color(0xFF99272D),
                'route': AdminReportsScreen(),
              },
              {
                'title': 'Settings',
                'icon': '⚙️',
                'desc': 'Barangay settings',
                'color': Color(0xFF36454F),
                'route': AdminSettingsScreen(),
              },
            ];
            final item = items[index];
            return _buildDashboardCard(
              title: item['title'] as String,
              icon: item['icon'] as String,
              description: item['desc'] as String,
              color: item['color'] as Color,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => item['route'] as Widget),
                );
              },
            );
          },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDashboardCard({
    required String title,
    required String icon,
    required String description,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: EdgeInsets.all(6),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                icon,
                style: TextStyle(fontSize: 30),
              ),
              SizedBox(height: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 4),
              Text(
                description,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
