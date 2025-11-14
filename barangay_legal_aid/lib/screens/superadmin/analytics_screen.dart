import 'package:flutter/material.dart';
import 'package:barangay_legal_aid/services/api_service.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  _AnalyticsScreenState createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  final ApiService _apiService = ApiService();
  Map<String, dynamic> _analytics = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAnalytics();
  }

  Future<void> _loadAnalytics() async {
    setState(() => _isLoading = true);
    try {
      final analytics = await _apiService.getAnalytics();
      setState(() {
        _analytics = analytics;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Analytics'),
        backgroundColor: Color(0xFF99272D),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: _loadAnalytics,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadAnalytics,
              child: SingleChildScrollView(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
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
                          _analytics['total_users'] ?? 0,
                          Icons.people,
                          Color(0xFF99272D),
                        ),
                        _buildStatCard(
                          'Total Requests',
                          _analytics['total_requests'] ?? 0,
                          Icons.description,
                          Color(0xFF36454F),
                        ),
                        _buildStatCard(
                          'Total Cases',
                          _analytics['total_cases'] ?? 0,
                          Icons.folder,
                          Color(0xFF99272D),
                        ),
                        _buildStatCard(
                          'Total Barangays',
                          _analytics['total_barangays'] ?? 0,
                          Icons.location_city,
                          Color(0xFF36454F),
                        ),
                      ],
                    ),
                    SizedBox(height: 24),
                    Card(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Additional Statistics',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF36454F)),
                            ),
                            SizedBox(height: 16),
                            Text('More detailed analytics will be available here.'),
                          ],
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

