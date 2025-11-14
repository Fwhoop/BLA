import 'package:flutter/material.dart';
import 'package:barangay_legal_aid/services/api_service.dart';

class AdminsScreen extends StatefulWidget {
  const AdminsScreen({super.key});

  @override
  _AdminsScreenState createState() => _AdminsScreenState();
}

class _AdminsScreenState extends State<AdminsScreen> {
  final ApiService _apiService = ApiService();
  List<Map<String, dynamic>> _admins = [];
  List<Map<String, dynamic>> _barangays = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final [admins, barangays] = await Future.wait([
        _apiService.getAdmins(),
        _apiService.getBarangays(),
      ]);
      setState(() {
        _admins = admins;
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

  Future<void> _showAddAdminDialog() async {
    final formKey = GlobalKey<FormState>();
    final emailController = TextEditingController();
    final usernameController = TextEditingController();
    final passwordController = TextEditingController();
    final firstNameController = TextEditingController();
    final lastNameController = TextEditingController();
    int? selectedBarangayId;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Add Admin'),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: emailController,
                    decoration: InputDecoration(labelText: 'Email'),
                    keyboardType: TextInputType.emailAddress,
                    validator: (v) => v?.isEmpty ?? true ? 'Required' : null,
                  ),
                  TextFormField(
                    controller: usernameController,
                    decoration: InputDecoration(labelText: 'Username'),
                    validator: (v) => v?.isEmpty ?? true ? 'Required' : null,
                  ),
                  TextFormField(
                    controller: passwordController,
                    decoration: InputDecoration(labelText: 'Password'),
                    obscureText: true,
                    validator: (v) => v?.isEmpty ?? true ? 'Required' : null,
                  ),
                  TextFormField(
                    controller: firstNameController,
                    decoration: InputDecoration(labelText: 'First Name'),
                    validator: (v) => v?.isEmpty ?? true ? 'Required' : null,
                  ),
                  TextFormField(
                    controller: lastNameController,
                    decoration: InputDecoration(labelText: 'Last Name'),
                    validator: (v) => v?.isEmpty ?? true ? 'Required' : null,
                  ),
                  DropdownButtonFormField<int?>(
                    value: selectedBarangayId,
                    decoration: InputDecoration(labelText: 'Barangay (Optional)'),
                    items: [
                      DropdownMenuItem<int?>(value: null, child: Text('None')),
                      ..._barangays.map((b) => DropdownMenuItem<int?>(
                        value: b['id'],
                        child: Text(b['name'] ?? ''),
                      )),
                    ],
                    onChanged: (v) => setDialogState(() => selectedBarangayId = v),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  Navigator.pop(context, true);
                }
              },
              child: Text('Add'),
            ),
          ],
        ),
      ),
    ).then((result) async {
      if (result == true) {
        try {
          await _apiService.createAdmin(
            email: emailController.text,
            username: usernameController.text,
            password: passwordController.text,
            firstName: firstNameController.text,
            lastName: lastNameController.text,
            barangayId: selectedBarangayId,
          );
          _loadData();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Admin added successfully'), backgroundColor: Color(0xFF36454F)),
          );
        } catch (e) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: Color(0xFF99272D)),
          );
        }
      }
    });
  }

  Future<void> _deleteAdmin(Map<String, dynamic> admin) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete Admin'),
        content: Text('Are you sure you want to delete ${admin['email']}?'),
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
        await _apiService.deleteUser(admin['id']);
        _loadData();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Admin deleted successfully'), backgroundColor: Color(0xFF36454F)),
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
        title: Text('Admins Management'),
        backgroundColor: Color(0xFF99272D),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: _loadData,
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
                        onPressed: _loadData,
                        child: Text('Retry'),
                      ),
                    ],
                  ),
                )
              : _admins.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.admin_panel_settings, size: 64, color: Colors.grey),
                          SizedBox(height: 16),
                          Text('No admins found', style: TextStyle(color: Colors.grey)),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _loadData,
                      child: ListView.builder(
                        padding: EdgeInsets.all(16),
                        itemCount: _admins.length,
                        itemBuilder: (context, index) {
                          final admin = _admins[index];
                          return Card(
                            margin: EdgeInsets.only(bottom: 12),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: Color(0xFF36454F),
                                child: Icon(Icons.admin_panel_settings, color: Colors.white),
                              ),
                              title: Text(
                                admin['email'] ?? 'Unknown',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Username: ${admin['username'] ?? 'N/A'}'),
                                  Text('Name: ${admin['first_name'] ?? ''} ${admin['last_name'] ?? ''}'),
                                  Text('Role: ${admin['role'] ?? 'N/A'}'),
                                ],
                              ),
                              trailing: IconButton(
                                icon: Icon(Icons.delete, color: Color(0xFF99272D)),
                                onPressed: () => _deleteAdmin(admin),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddAdminDialog,
        backgroundColor: Color(0xFF99272D),
        child: Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}

