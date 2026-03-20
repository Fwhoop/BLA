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
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadBarangays();
    loadUserFromPrefs().then((m) { if (mounted) setState(() => _userMap = m); });
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: BlaAppBar(
        title: 'Barangays Management',
        user: _userMap,
        extraActions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadBarangays,
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
                        onPressed: _loadBarangays,
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
                      onRefresh: _loadBarangays,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _barangays.length,
                        itemBuilder: (context, index) {
                          final barangay = _barangays[index];
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
                              subtitle: Text('ID: ${barangay['id']}'),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}
