import 'package:flutter/material.dart';
import 'package:barangay_legal_aid/services/api_service.dart';

class AdminRequestsScreen extends StatefulWidget {
  const AdminRequestsScreen({super.key});

  @override
  _AdminRequestsScreenState createState() => _AdminRequestsScreenState();
}

class _AdminRequestsScreenState extends State<AdminRequestsScreen> {
  final ApiService _apiService = ApiService();
  List<Map<String, dynamic>> _requests = [];
  bool _isLoading = true;
  String? _error;
  String _statusFilter = 'all'; // all, pending, approved, rejected

  @override
  void initState() {
    super.initState();
    _loadRequests();
  }

  Future<void> _loadRequests() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final requests = await _apiService.getRequests();
      print('Loaded ${requests.length} requests');
      print('Requests data: $requests');
      setState(() {
        _requests = requests;
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading requests: $e');
      setState(() {
        _error = e.toString().replaceAll('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  Future<void> _updateRequestStatus(int id, String status) async {
    try {
      await _apiService.updateRequest(id, {'status': status});
      _loadRequests();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Request $status successfully'),
          backgroundColor: Color(0xFF36454F),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Color(0xFF99272D),
        ),
      );
    }
  }

  Future<void> _deleteRequest(int id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete Request'),
        content: Text('Are you sure you want to delete this request?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Color(0xFF99272D)),
            child: Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _apiService.deleteRequest(id);
        _loadRequests();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Request deleted successfully'), backgroundColor: Color(0xFF36454F)),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Color(0xFF99272D)),
        );
      }
    }
  }

  List<Map<String, dynamic>> get _filteredRequests {
    if (_statusFilter == 'all') return _requests;
    return _requests.where((r) => r['status'] == _statusFilter).toList();
  }

  Color _getStatusColor(String? status) {
    switch (status) {
      case 'pending':
        return Colors.orange;
      case 'approved':
        return Colors.green;
      case 'rejected':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Document Requests'),
        backgroundColor: Color(0xFF99272D),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: _loadRequests,
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
                  selected: _statusFilter == 'all',
                  onSelected: (selected) => setState(() => _statusFilter = 'all'),
                ),
                SizedBox(width: 8),
                ChoiceChip(
                  label: Text('Pending'),
                  selected: _statusFilter == 'pending',
                  onSelected: (selected) => setState(() => _statusFilter = 'pending'),
                ),
                SizedBox(width: 8),
                ChoiceChip(
                  label: Text('Approved'),
                  selected: _statusFilter == 'approved',
                  onSelected: (selected) => setState(() => _statusFilter = 'approved'),
                ),
                SizedBox(width: 8),
                ChoiceChip(
                  label: Text('Rejected'),
                  selected: _statusFilter == 'rejected',
                  onSelected: (selected) => setState(() => _statusFilter = 'rejected'),
                ),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.error_outline, size: 64, color: Color(0xFF99272D)),
                            SizedBox(height: 16),
                            Text(_error!, style: TextStyle(color: Color(0xFF36454F))),
                            SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: _loadRequests,
                              child: Text('Retry'),
                            ),
                          ],
                        ),
                      )
                    : _filteredRequests.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.description, size: 64, color: Colors.grey),
                                SizedBox(height: 16),
                                Text(
                                  _requests.isEmpty 
                                    ? 'No requests found. Requests will appear here once users submit document requests.'
                                    : 'No requests match the selected filter.',
                                  style: TextStyle(color: Colors.grey),
                                  textAlign: TextAlign.center,
                                ),
                                if (_requests.isEmpty) ...[
                                  SizedBox(height: 16),
                                  Text(
                                    'Total requests: ${_requests.length}',
                                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                                  ),
                                ],
                              ],
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _loadRequests,
                            child: ListView.builder(
                              padding: EdgeInsets.all(16),
                              itemCount: _filteredRequests.length,
                              itemBuilder: (context, index) {
                                final request = _filteredRequests[index];
                                final status = request['status'] ?? 'pending';
                                final statusColor = _getStatusColor(status);

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
                                      'Request #${request['id']}',
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
                                          'Document: ${request['document_type'] ?? 'N/A'}',
                                          style: TextStyle(
                                            fontSize: 14,
                                            color: Color(0xFF36454F),
                                          ),
                                        ),
                                        SizedBox(height: 4),
                                        Text(
                                          'Purpose: ${request['purpose'] ?? 'N/A'}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Color(0xFF36454F).withOpacity(0.7),
                                          ),
                                        ),
                                        if (request['created_at'] != null)
                                          Text(
                                            'Date: ${request['created_at']}',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey[600],
                                            ),
                                          ),
                                      ],
                                    ),
                                    trailing: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
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
                                        if (status == 'pending') ...[
                                          SizedBox(height: 8),
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              IconButton(
                                                icon: Icon(Icons.check, color: Colors.green),
                                                onPressed: () => _updateRequestStatus(request['id'], 'approved'),
                                                tooltip: 'Approve',
                                              ),
                                              IconButton(
                                                icon: Icon(Icons.close, color: Colors.red),
                                                onPressed: () => _updateRequestStatus(request['id'], 'rejected'),
                                                tooltip: 'Reject',
                                              ),
                                              IconButton(
                                                icon: Icon(Icons.delete, color: Color(0xFF99272D)),
                                                onPressed: () => _deleteRequest(request['id']),
                                                tooltip: 'Delete',
                                              ),
                                            ],
                                          ),
                                        ],
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

