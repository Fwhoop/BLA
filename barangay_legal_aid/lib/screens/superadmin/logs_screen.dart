import 'package:flutter/material.dart';
import 'package:barangay_legal_aid/services/api_service.dart';

class LogsScreen extends StatefulWidget {
  const LogsScreen({super.key});

  @override
  _LogsScreenState createState() => _LogsScreenState();
}

class _LogsScreenState extends State<LogsScreen> {
  final ApiService _apiService = ApiService();
  List<Map<String, dynamic>> _logs = [];
  bool _isLoading = true;
  String _filter = 'all'; // all, error, info, warning

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  Future<void> _loadLogs() async {
    setState(() => _isLoading = true);
    try {
      final logs = await _apiService.getLogs();
      setState(() {
        _logs = logs;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  List<Map<String, dynamic>> get _filteredLogs {
    if (_filter == 'all') return _logs;
    return _logs.where((log) => log['level']?.toLowerCase() == _filter).toList();
  }

  Color _getLogColor(String? level) {
    switch (level?.toLowerCase()) {
      case 'error':
        return Color(0xFF99272D);
      case 'warning':
        return Colors.orange;
      case 'info':
        return Color(0xFF36454F);
      default:
        return Colors.grey;
    }
  }

  IconData _getLogIcon(String? level) {
    switch (level?.toLowerCase()) {
      case 'error':
        return Icons.error;
      case 'warning':
        return Icons.warning;
      case 'info':
        return Icons.info;
      default:
        return Icons.description;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('System Logs'),
        backgroundColor: Color(0xFF99272D),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: _loadLogs,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Colors.grey[200],
            child: Row(
              children: [
                Text('Filter: ', style: TextStyle(fontWeight: FontWeight.bold)),
                SizedBox(width: 8),
                ChoiceChip(
                  label: Text('All'),
                  selected: _filter == 'all',
                  onSelected: (selected) => setState(() => _filter = 'all'),
                ),
                SizedBox(width: 8),
                ChoiceChip(
                  label: Text('Error'),
                  selected: _filter == 'error',
                  onSelected: (selected) => setState(() => _filter = 'error'),
                ),
                SizedBox(width: 8),
                ChoiceChip(
                  label: Text('Warning'),
                  selected: _filter == 'warning',
                  onSelected: (selected) => setState(() => _filter = 'warning'),
                ),
                SizedBox(width: 8),
                ChoiceChip(
                  label: Text('Info'),
                  selected: _filter == 'info',
                  onSelected: (selected) => setState(() => _filter = 'info'),
                ),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? Center(child: CircularProgressIndicator())
                : _filteredLogs.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.description, size: 64, color: Colors.grey),
                            SizedBox(height: 16),
                            Text('No logs found', style: TextStyle(color: Colors.grey)),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadLogs,
                        child: ListView.builder(
                          padding: EdgeInsets.all(16),
                          itemCount: _filteredLogs.length,
                          itemBuilder: (context, index) {
                            final log = _filteredLogs[index];
                            final level = log['level'] ?? 'info';
                            final color = _getLogColor(level);
                            return Card(
                              margin: EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                leading: Icon(_getLogIcon(level), color: color),
                                title: Text(
                                  log['message'] ?? 'No message',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Level: ${level.toUpperCase()}'),
                                    if (log['timestamp'] != null)
                                      Text('Time: ${log['timestamp']}'),
                                    if (log['module'] != null)
                                      Text('Module: ${log['module']}'),
                                  ],
                                ),
                                isThreeLine: true,
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

