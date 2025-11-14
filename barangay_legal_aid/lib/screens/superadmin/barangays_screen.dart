import 'package:flutter/material.dart';
import 'package:barangay_legal_aid/services/api_service.dart';

class BarangaysScreen extends StatefulWidget {
  const BarangaysScreen({super.key});

  @override
  _BarangaysScreenState createState() => _BarangaysScreenState();
}

class _BarangaysScreenState extends State<BarangaysScreen> {
  final ApiService _apiService = ApiService();
  List<Map<String, dynamic>> _barangays = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadBarangays();
  }

  Future<void> _loadBarangays() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final barangays = await _apiService.getBarangays();
      setState(() {
        _barangays = barangays;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _showAddBarangayDialog() async {
    final nameController = TextEditingController();
    
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Add Barangay'),
        content: TextField(
          controller: nameController,
          decoration: InputDecoration(
            labelText: 'Barangay Name',
            hintText: 'Enter barangay name',
          ),
          autofocus: true,
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

    if (result == true && nameController.text.isNotEmpty) {
      try {
        await _apiService.createBarangay(nameController.text);
        _loadBarangays();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Barangay added successfully'), backgroundColor: Color(0xFF36454F)),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Color(0xFF99272D)),
        );
      }
    }
  }

  Future<void> _showEditBarangayDialog(Map<String, dynamic> barangay) async {
    final nameController = TextEditingController(text: barangay['name'] ?? '');
    
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Edit Barangay'),
        content: TextField(
          controller: nameController,
          decoration: InputDecoration(
            labelText: 'Barangay Name',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Save'),
          ),
        ],
      ),
    );

    if (result == true && nameController.text.isNotEmpty) {
      try {
        await _apiService.updateBarangay(barangay['id'], nameController.text);
        _loadBarangays();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Barangay updated successfully'), backgroundColor: Color(0xFF36454F)),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Color(0xFF99272D)),
        );
      }
    }
  }

  Future<void> _deleteBarangay(Map<String, dynamic> barangay) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete Barangay'),
        content: Text('Are you sure you want to delete ${barangay['name']}?'),
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
        await _apiService.deleteBarangay(barangay['id']);
        _loadBarangays();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Barangay deleted successfully'), backgroundColor: Color(0xFF36454F)),
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
        title: Text('Barangays Management'),
        backgroundColor: Color(0xFF99272D),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: _loadBarangays,
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
                        onPressed: _loadBarangays,
                        child: Text('Retry'),
                      ),
                    ],
                  ),
                )
              : _barangays.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.location_city, size: 64, color: Colors.grey),
                          SizedBox(height: 16),
                          Text('No barangays found', style: TextStyle(color: Colors.grey)),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _loadBarangays,
                      child: ListView.builder(
                        padding: EdgeInsets.all(16),
                        itemCount: _barangays.length,
                        itemBuilder: (context, index) {
                          final barangay = _barangays[index];
                          return Card(
                            margin: EdgeInsets.only(bottom: 12),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: Color(0xFF99272D),
                                child: Icon(Icons.location_city, color: Colors.white),
                              ),
                              title: Text(
                                barangay['name'] ?? 'Unknown',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                              subtitle: Text('ID: ${barangay['id']}'),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: Icon(Icons.edit, color: Color(0xFF99272D)),
                                    onPressed: () => _showEditBarangayDialog(barangay),
                                  ),
                                  IconButton(
                                    icon: Icon(Icons.delete, color: Color(0xFF99272D)),
                                    onPressed: () => _deleteBarangay(barangay),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddBarangayDialog,
        backgroundColor: Color(0xFF99272D),
        child: Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}

