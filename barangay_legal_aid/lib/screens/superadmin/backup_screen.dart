import 'package:flutter/material.dart';
import 'package:barangay_legal_aid/services/api_service.dart';

class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});

  @override
  _BackupScreenState createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  final ApiService _apiService = ApiService();
  List<Map<String, dynamic>> _backups = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadBackups();
  }

  Future<void> _loadBackups() async {
    setState(() => _isLoading = true);
    try {
      final backups = await _apiService.getBackups();
      setState(() {
        _backups = backups;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _createBackup() async {
    setState(() => _isLoading = true);
    try {
      await _apiService.createBackup();
      _loadBackups();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Backup created successfully'), backgroundColor: Color(0xFF36454F)),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error creating backup: $e'), backgroundColor: Color(0xFF99272D)),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Backup Management'),
        backgroundColor: Color(0xFF99272D),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: _loadBackups,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading && _backups.isEmpty
          ? Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: EdgeInsets.all(16),
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : _createBackup,
                    icon: Icon(Icons.backup),
                    label: Text('Create Backup'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Color(0xFF99272D),
                      padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    ),
                  ),
                ),
                Expanded(
                  child: _backups.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.backup, size: 64, color: Colors.grey),
                              SizedBox(height: 16),
                              Text('No backups found', style: TextStyle(color: Colors.grey)),
                            ],
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _loadBackups,
                          child: ListView.builder(
                            padding: EdgeInsets.all(16),
                            itemCount: _backups.length,
                            itemBuilder: (context, index) {
                              final backup = _backups[index];
                              return Card(
                                margin: EdgeInsets.only(bottom: 12),
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: Color(0xFF36454F),
                                    child: Icon(Icons.backup, color: Colors.white),
                                  ),
                                  title: Text(
                                    backup['name'] ?? 'Backup ${index + 1}',
                                    style: TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                  subtitle: Text(
                                    backup['created_at'] ?? 'Unknown date',
                                  ),
                                  trailing: IconButton(
                                    icon: Icon(Icons.download, color: Color(0xFF99272D)),
                                    onPressed: () {
                                      // TODO: Implement backup download
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('Download feature coming soon')),
                                      );
                                    },
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                ),
              ],
            ),
    );
  }
}

