import 'package:flutter/material.dart';
import 'package:barangay_legal_aid/services/api_service.dart';

class AdminCasesScreen extends StatefulWidget {
  const AdminCasesScreen({super.key});

  @override
  _AdminCasesScreenState createState() => _AdminCasesScreenState();
}

class _AdminCasesScreenState extends State<AdminCasesScreen> {
  final ApiService _apiService = ApiService();
  List<Map<String, dynamic>> _cases = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadCases();
  }

  Future<void> _loadCases() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final cases = await _apiService.getCases();
      setState(() {
        _cases = cases;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _showAddCaseDialog() async {
    final titleController = TextEditingController();
    final descriptionController = TextEditingController();
    
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Add Case'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                decoration: InputDecoration(labelText: 'Case Title'),
                autofocus: true,
              ),
              SizedBox(height: 16),
              TextField(
                controller: descriptionController,
                decoration: InputDecoration(labelText: 'Description'),
                maxLines: 3,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Add'),
          ),
        ],
      ),
    );

    if (result == true && titleController.text.isNotEmpty) {
      try {
        await _apiService.createCase(
          title: titleController.text,
          description: descriptionController.text,
        );
        _loadCases();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Case added successfully'), backgroundColor: Color(0xFF36454F)),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Color(0xFF99272D)),
        );
      }
    }
  }

  Future<void> _deleteCase(Map<String, dynamic> caseData) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete Case'),
        content: Text('Are you sure you want to delete this case?'),
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
        await _apiService.deleteCase(caseData['id']);
        _loadCases();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Case deleted successfully'), backgroundColor: Color(0xFF36454F)),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Color(0xFF99272D)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Cases Management'),
        backgroundColor: Color(0xFF99272D),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: _loadCases,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
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
                        onPressed: _loadCases,
                        child: Text('Retry'),
                      ),
                    ],
                  ),
                )
              : _cases.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.folder, size: 64, color: Colors.grey),
                          SizedBox(height: 16),
                          Text('No cases found', style: TextStyle(color: Colors.grey)),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _loadCases,
                      child: ListView.builder(
                        padding: EdgeInsets.all(16),
                        itemCount: _cases.length,
                        itemBuilder: (context, index) {
                          final caseData = _cases[index];
                          return Card(
                            margin: EdgeInsets.only(bottom: 12),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: Color(0xFF99272D),
                                child: Icon(Icons.folder, color: Colors.white),
                              ),
                              title: Text(
                                caseData['title'] ?? 'Untitled Case',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                              subtitle: Text(
                                caseData['description'] ?? 'No description',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: IconButton(
                                icon: Icon(Icons.delete, color: Color(0xFF99272D)),
                                onPressed: () => _deleteCase(caseData),
                              ),
                              isThreeLine: true,
                            ),
                          );
                        },
                      ),
                    ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddCaseDialog,
        backgroundColor: Color(0xFF99272D),
        child: Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}

