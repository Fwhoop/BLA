import 'package:flutter/material.dart';
import 'package:barangay_legal_aid/services/api_service.dart';

class AdminReportsScreen extends StatefulWidget {
  const AdminReportsScreen({super.key});

  @override
  _AdminReportsScreenState createState() => _AdminReportsScreenState();
}

class _AdminReportsScreenState extends State<AdminReportsScreen> {
  final ApiService _apiService = ApiService();
  Map<String, dynamic> _stats = {};
  List<Map<String, dynamic>> _requests = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadReports();
  }

  Future<void> _loadReports() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        _apiService.getRequests(),
        _apiService.getAnalytics(),
      ]);
      setState(() {
        _requests = List<Map<String, dynamic>>.from(results[0] as List);
        _stats = Map<String, dynamic>.from(results[1] as Map);
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Widget _buildStatCard(String title, int value, IconData icon, Color color) {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 48, color: color),
            SizedBox(height: 12),
            Text(
              value.toString(),
              style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: color),
            ),
            SizedBox(height: 4),
            Text(
              title,
              style: TextStyle(fontSize: 14, color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Map<String, int> _getRequestStats() {
    final pending = _requests.where((r) => r['status'] == 'pending').length;
    final approved = _requests.where((r) => r['status'] == 'approved').length;
    final rejected = _requests.where((r) => r['status'] == 'rejected').length;
    return {
      'pending': pending,
      'approved': approved,
      'rejected': rejected,
      'total': _requests.length,
    };
  }

  @override
  Widget build(BuildContext context) {
    final requestStats = _getRequestStats();
    
    return Scaffold(
      appBar: AppBar(
        title: Text('Reports & Analytics'),
        backgroundColor: Color(0xFF99272D),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: _loadReports,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadReports,
              child: SingleChildScrollView(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Request Statistics',
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF36454F)),
                    ),
                    SizedBox(height: 16),
                    GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: NeverScrollableScrollPhysics(),
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                      childAspectRatio: 1.2,
                      children: [
                        _buildStatCard(
                          'Total Requests',
                          requestStats['total'] ?? 0,
                          Icons.description,
                          Color(0xFF99272D),
                        ),
                        _buildStatCard(
                          'Pending',
                          requestStats['pending'] ?? 0,
                          Icons.pending,
                          Colors.orange,
                        ),
                        _buildStatCard(
                          'Approved',
                          requestStats['approved'] ?? 0,
                          Icons.check_circle,
                          Colors.green,
                        ),
                        _buildStatCard(
                          'Rejected',
                          requestStats['rejected'] ?? 0,
                          Icons.cancel,
                          Colors.red,
                        ),
                      ],
                    ),
                    SizedBox(height: 24),
                    Text(
                      'System Overview',
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF36454F)),
                    ),
                    SizedBox(height: 16),
                    GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: NeverScrollableScrollPhysics(),
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                      childAspectRatio: 1.2,
                      children: [
                        _buildStatCard(
                          'Total Users',
                          _stats['total_users'] ?? 0,
                          Icons.people,
                          Color(0xFF99272D),
                        ),
                        _buildStatCard(
                          'Total Cases',
                          _stats['total_cases'] ?? 0,
                          Icons.folder,
                          Color(0xFF36454F),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

