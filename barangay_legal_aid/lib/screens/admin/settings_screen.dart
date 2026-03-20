import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:barangay_legal_aid/config/env_config.dart';
import 'package:barangay_legal_aid/services/api_service.dart';
import 'package:barangay_legal_aid/utils/top_snack.dart';

class AdminSettingsScreen extends StatefulWidget {
  const AdminSettingsScreen({super.key});

  @override
  AdminSettingsScreenState createState() => AdminSettingsScreenState();
}

class AdminSettingsScreenState extends State<AdminSettingsScreen> {
  final ApiService _apiService = ApiService();

  String? _barangayName;
  int? _barangayId;

  // Logo state
  String? _logoUrl;
  String? _logoUrlSecondary;
  bool _uploadingLogo = false;
  bool _uploadingLogoSecondary = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final me = await _apiService.getCurrentUser();
      if (me != null) {
        final bid = me['barangay_id'] as int?;
        setState(() {
          _barangayId = bid;
        });
        if (bid != null) {
          final bd = await _apiService.getBarangay(bid);
          setState(() {
            _barangayName = bd['name'] as String?;
            _logoUrl = bd['logo_url'] as String?;
            _logoUrlSecondary = bd['logo_url_secondary'] as String?;
          });
        }
      } else {
        final barangays = await _apiService.getBarangays();
        if (barangays.isNotEmpty) {
          setState(() => _barangayName = barangays.first['name'] as String?);
        }
      }
    } catch (_) {
      // fail silently
    }
  }

  // ─── Logo upload (primary / secondary) ────────────────────────────────────

  Future<void> _pickAndUploadLogo({required bool secondary}) async {
    if (_barangayId == null) {
      _showError('Barangay ID not found. Please re-login.');
      return;
    }
    final picker = ImagePicker();
    final picked =
        await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked == null) return;

    final bytes = await picked.readAsBytes();
    final filename = picked.name.isNotEmpty ? picked.name : 'logo.png';

    setState(() =>
        secondary ? _uploadingLogoSecondary = true : _uploadingLogo = true);
    try {
      final result = secondary
          ? await _apiService.uploadBarangayLogoSecondary(
              _barangayId!, bytes, filename)
          : await _apiService.uploadBarangayLogo(_barangayId!, bytes, filename);

      setState(() {
        if (secondary) {
          _logoUrlSecondary = result['logo_url_secondary'] as String?;
        } else {
          _logoUrl = result['logo_url'] as String?;
        }
      });
      if (mounted) {
        showTopSnack(context,
            message: 'Logo uploaded successfully!',
            backgroundColor: const Color(0xFF36454F),
            icon: Icons.check_circle_outline);
      }
    } catch (e) {
      if (mounted) _showError(e.toString().replaceAll('Exception: ', ''));
    } finally {
      setState(() =>
          secondary ? _uploadingLogoSecondary = false : _uploadingLogo = false);
    }
  }

  void _showError(String msg) {
    showTopSnack(context,
        message: msg,
        backgroundColor: const Color(0xFF99272D),
        icon: Icons.error_outline);
  }

  // ─── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: const Color(0xFF99272D),
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildBarangayInfoCard(),
            const SizedBox(height: 16),
            _buildLogosCard(),
            const SizedBox(height: 24),
            Center(
              child: SizedBox(
                width: 220,
                child: ElevatedButton.icon(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('Settings saved'),
                          backgroundColor: Color(0xFF36454F)),
                    );
                  },
                  icon: const Icon(Icons.save),
                  label: const Text('Save Settings'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF99272D),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBarangayInfoCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Barangay Information',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF99272D))),
            const SizedBox(height: 16),
            ListTile(
              leading:
                  const Icon(Icons.location_city, color: Color(0xFF99272D)),
              title: const Text('Barangay Name'),
              subtitle: Text(_barangayName ?? 'Not set'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogosCard() {
    Widget logoPreview(String? url, String placeholder) {
      if (url != null && url.isNotEmpty) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.network(
            '$apiBaseUrl$url',
            width: 80,
            height: 80,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => _logoPlaceholder(placeholder),
          ),
        );
      }
      return _logoPlaceholder(placeholder);
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Barangay Logos',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF99272D))),
            const SizedBox(height: 4),
            const Text(
              'These logos appear on all generated documents.',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            // Left logo
            Row(
              children: [
                logoPreview(_logoUrl, 'Left\nLogo'),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Left Logo (Barangay Seal)',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      const Text(
                        'Upload your barangay\'s official seal.',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      const SizedBox(height: 8),
                      _uploadingLogo
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Color(0xFF99272D)))
                          : OutlinedButton.icon(
                              onPressed: () =>
                                  _pickAndUploadLogo(secondary: false),
                              icon: const Icon(Icons.upload, size: 16),
                              label: Text(
                                  _logoUrl == null ? 'Upload' : 'Replace'),
                              style: OutlinedButton.styleFrom(
                                  foregroundColor: const Color(0xFF99272D),
                                  side: const BorderSide(
                                      color: Color(0xFF99272D))),
                            ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 28),
            // Right logo
            Row(
              children: [
                logoPreview(_logoUrlSecondary, 'Right\nLogo'),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Right Logo (Optional)',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      const Text(
                        'We recommend uploading the Bagong Pilipinas logo here. If left empty, no right logo will appear.',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      const SizedBox(height: 8),
                      _uploadingLogoSecondary
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Color(0xFF99272D)))
                          : OutlinedButton.icon(
                              onPressed: () =>
                                  _pickAndUploadLogo(secondary: true),
                              icon: const Icon(Icons.upload, size: 16),
                              label: Text(_logoUrlSecondary == null
                                  ? 'Upload'
                                  : 'Replace'),
                              style: OutlinedButton.styleFrom(
                                  foregroundColor: const Color(0xFF99272D),
                                  side: const BorderSide(
                                      color: Color(0xFF99272D))),
                            ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _logoPlaceholder(String text) {
    return Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Center(
        child: Text(text,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 11, color: Colors.grey)),
      ),
    );
  }
}
