import 'package:flutter/material.dart';
import 'package:barangay_legal_aid/services/api_service.dart';
import 'package:barangay_legal_aid/widgets/bla_app_bar.dart';

class BarangaysScreen extends StatefulWidget {
  const BarangaysScreen({super.key});

  @override
  BarangaysScreenState createState() => BarangaysScreenState();
}

class BarangaysScreenState extends State<BarangaysScreen> {
  final ApiService _apiService = ApiService();
  Map<String, dynamic> _userMap = {};
  List<Map<String, dynamic>> _barangays = [];
  List<Map<String, dynamic>> _admins = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadData();
    loadUserFromPrefs().then((m) { if (mounted) setState(() => _userMap = m); });
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final results = await Future.wait([
        _apiService.getBarangays(),
        _apiService.getAdmins(),
      ]);
      setState(() {
        _barangays = results[0];
        _admins = results[1].where((u) => u['role'] == 'admin').toList();
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Map<String, dynamic>? _adminForBarangay(int barangayId) {
    try {
      return _admins.firstWhere((a) => a['barangay_id'] == barangayId);
    } catch (_) {
      return null;
    }
  }

  void _showAdminInfo(BuildContext context, Map<String, dynamic> barangay) {
    final admin = _adminForBarangay(barangay['id'] as int);
    final name = admin == null
        ? 'No admin assigned'
        : '${admin['first_name'] ?? ''} ${admin['last_name'] ?? ''}'.trim();
    final email = admin?['email'] as String? ?? '';
    final phone = admin?['phone'] as String? ?? '';

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(barangay['name'] ?? 'Barangay'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Admin', style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            if (admin == null)
              const Text('No admin assigned yet.', style: TextStyle(color: Colors.grey))
            else ...[
              Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              if (email.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(email, style: const TextStyle(fontSize: 13, color: Color(0xFF36454F))),
              ],
              if (phone.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(phone, style: const TextStyle(fontSize: 13, color: Color(0xFF36454F))),
              ],
            ],
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: BlaAppBar(
        title: 'Barangays Management',
        user: _userMap,
        extraActions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline, size: 64, color: Color(0xFF99272D)),
                      const SizedBox(height: 16),
                      Text(_error!, style: const TextStyle(color: Color(0xFF36454F))),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadData,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : _barangays.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.location_city, size: 64, color: Colors.grey),
                          const SizedBox(height: 16),
                          const Text(
                            'No barangays yet.',
                            style: TextStyle(color: Colors.grey, fontSize: 16),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Barangays are created automatically\nwhen you add an admin.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _loadData,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _barangays.length,
                        itemBuilder: (context, index) {
                          final barangay = _barangays[index];
                          final admin = _adminForBarangay(barangay['id'] as int);
                          final adminName = admin == null
                              ? 'No admin assigned'
                              : '${admin['first_name'] ?? ''} ${admin['last_name'] ?? ''}'.trim();
                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            child: ListTile(
                              leading: const CircleAvatar(
                                backgroundColor: Color(0xFF99272D),
                                child: Icon(Icons.location_city, color: Colors.white),
                              ),
                              title: Text(
                                barangay['name'] ?? 'Unknown',
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              subtitle: Text(adminName,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: admin == null ? Colors.grey : const Color(0xFF36454F),
                                  )),
                              trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                              onTap: () => _showAdminInfo(context, barangay),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}
