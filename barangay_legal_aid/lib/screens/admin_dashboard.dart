import 'package:flutter/material.dart';
import 'package:barangay_legal_aid/services/auth_service.dart';
import 'package:barangay_legal_aid/screens/ui/feature_placeholder.dart';

class AdminDashboard extends StatefulWidget {
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
                'route': _RequestsListPage(),
              },
              {
                'title': 'Users',
                'icon': '👥',
                'desc': 'Manage users',
                'color': Color(0xFF36454F),
                'route': FeaturePlaceholder(
                  title: 'Users',
                  description: 'Manage users',
                ),
              },
              {
                'title': 'Cases',
                'icon': '📋',
                'desc': 'Track legal cases',
                'color': Color(0xFF99272D),
                'route': FeaturePlaceholder(
                  title: 'Cases',
                  description: 'Track and manage cases',
                ),
              },
              {
                'title': 'Chats',
                'icon': '💬',
                'desc': 'Monitor conversations',
                'color': Color(0xFF36454F),
                'route': FeaturePlaceholder(
                  title: 'Chats',
                  description: 'Monitor conversations',
                ),
              },
              {
                'title': 'Reports',
                'icon': '📊',
                'desc': 'View analytics',
                'color': Color(0xFF99272D),
                'route': FeaturePlaceholder(
                  title: 'Reports',
                  description: 'View analytics and reports',
                ),
              },
              {
                'title': 'Settings',
                'icon': '⚙️',
                'desc': 'Barangay settings',
                'color': Color(0xFF36454F),
                'route': FeaturePlaceholder(
                  title: 'Settings',
                  description: 'Barangay settings',
                ),
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

class _RequestsListPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // Demo requests data
    final requests = [
      {
        'id': 1,
        'requester': 'Juan Dela Cruz',
        'documentType': 'Barangay Clearance',
        'purpose': 'For employment',
        'status': 'pending',
        'date': DateTime.now().subtract(Duration(days: 2)),
      },
      {
        'id': 2,
        'requester': 'Maria Santos',
        'documentType': 'Certificate of Residency',
        'purpose': 'For school enrollment',
        'status': 'approved',
        'date': DateTime.now().subtract(Duration(days: 5)),
      },
      {
        'id': 3,
        'requester': 'Carlos Ramirez',
        'documentType': 'Certificate of Good Moral Character',
        'purpose': 'For travel',
        'status': 'pending',
        'date': DateTime.now().subtract(Duration(days: 1)),
      },
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text('Document Requests'),
        backgroundColor: Color(0xFF99272D),
      ),
      body: Container(
        color: Color(0xFFFFFFFF),
        child: ListView.builder(
          padding: EdgeInsets.all(16),
          itemCount: requests.length,
          itemBuilder: (context, index) {
            final request = requests[index];
            final status = request['status'] as String;
            final statusColor = status == 'pending'
                ? Colors.orange
                : status == 'approved'
                    ? Colors.green
                    : Colors.red;

            return Card(
              elevation: 2,
              margin: EdgeInsets.only(bottom: 12),
              child: ListTile(
                contentPadding: EdgeInsets.all(16),
                leading: CircleAvatar(
                  backgroundColor: Color(0xFF99272D).withOpacity(0.1),
                  child: Icon(
                    Icons.description,
                    color: Color(0xFF99272D),
                  ),
                ),
                title: Text(
                  request['requester'] as String,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(height: 4),
                    Text(
                      request['documentType'] as String,
                      style: TextStyle(
                        fontSize: 14,
                        color: Color(0xFF36454F),
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      request['purpose'] as String,
                      style: TextStyle(
                        fontSize: 12,
                        color: Color(0xFF36454F).withOpacity(0.7),
                      ),
                    ),
                  ],
                ),
                trailing: Container(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: statusColor, width: 1),
                  ),
                  child: Text(
                    status.toUpperCase(),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: statusColor,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}