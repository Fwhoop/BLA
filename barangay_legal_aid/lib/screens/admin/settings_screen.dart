import 'package:flutter/material.dart';
import 'package:barangay_legal_aid/services/api_service.dart';

class AdminSettingsScreen extends StatefulWidget {
  const AdminSettingsScreen({super.key});

  @override
  _AdminSettingsScreenState createState() => _AdminSettingsScreenState();
}

class _AdminSettingsScreenState extends State<AdminSettingsScreen> {
  final ApiService _apiService = ApiService();
  bool _notificationsEnabled = true;
  bool _autoApprove = false;
  String? _barangayName;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final barangays = await _apiService.getBarangays();
      // Get current user's barangay - this would need to be passed or retrieved
      if (barangays.isNotEmpty) {
        setState(() {
          _barangayName = barangays.first['name'];
        });
      }
    } catch (e) {
      // Handle error silently
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Settings'),
        backgroundColor: Color(0xFF99272D),
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Barangay Information',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF99272D)),
                    ),
                    SizedBox(height: 16),
                    ListTile(
                      leading: Icon(Icons.location_city, color: Color(0xFF99272D)),
                      title: Text('Barangay Name'),
                      subtitle: Text(_barangayName ?? 'Not set'),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(height: 16),
            Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Request Settings',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF99272D)),
                    ),
                    SizedBox(height: 16),
                    SwitchListTile(
                      title: Text('Auto-approve Requests'),
                      subtitle: Text('Automatically approve document requests'),
                      value: _autoApprove,
                      onChanged: (value) {
                        setState(() => _autoApprove = value);
                        // TODO: Save to backend
                      },
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(height: 16),
            Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Notifications',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF99272D)),
                    ),
                    SizedBox(height: 16),
                    SwitchListTile(
                      title: Text('Email Notifications'),
                      subtitle: Text('Receive email notifications for new requests'),
                      value: _notificationsEnabled,
                      onChanged: (value) {
                        setState(() => _notificationsEnabled = value);
                        // TODO: Save to backend
                      },
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Settings saved'), backgroundColor: Color(0xFF36454F)),
                );
              },
              icon: Icon(Icons.save),
              label: Text('Save Settings'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Color(0xFF99272D),
                padding: EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

