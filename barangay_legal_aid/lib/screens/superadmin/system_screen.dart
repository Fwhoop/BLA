import 'package:flutter/material.dart';

class SystemScreen extends StatefulWidget {
  const SystemScreen({super.key});

  @override
  _SystemScreenState createState() => _SystemScreenState();
}

class _SystemScreenState extends State<SystemScreen> {

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('System Configuration'),
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
                      'System Settings',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF99272D)),
                    ),
                    SizedBox(height: 16),
                    SwitchListTile(
                      title: Text('Maintenance Mode'),
                      subtitle: Text('Enable maintenance mode'),
                      value: false,
                      onChanged: (value) {
                        // TODO: Implement maintenance mode toggle
                      },
                    ),
                    Divider(),
                    SwitchListTile(
                      title: Text('Email Notifications'),
                      subtitle: Text('Send email notifications'),
                      value: true,
                      onChanged: (value) {
                        // TODO: Implement email notifications toggle
                      },
                    ),
                    Divider(),
                    SwitchListTile(
                      title: Text('Auto Backup'),
                      subtitle: Text('Enable automatic backups'),
                      value: true,
                      onChanged: (value) {
                        // TODO: Implement auto backup toggle
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
                      'Database',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF99272D)),
                    ),
                    SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: () {
                        // TODO: Implement database optimization
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Database optimization feature coming soon')),
                        );
                      },
                      icon: Icon(Icons.tune),
                      label: Text('Optimize Database'),
                      style: ElevatedButton.styleFrom(backgroundColor: Color(0xFF36454F)),
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
                      'API Configuration',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF99272D)),
                    ),
                    SizedBox(height: 16),
                    Text('API Base URL: http://127.0.0.1:8000'),
                    SizedBox(height: 8),
                    ElevatedButton.icon(
                      onPressed: () {
                        // TODO: Implement API test
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('API test feature coming soon')),
                        );
                      },
                      icon: Icon(Icons.network_check),
                      label: Text('Test API Connection'),
                      style: ElevatedButton.styleFrom(backgroundColor: Color(0xFF36454F)),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

