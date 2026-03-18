// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:convert';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:typed_data';

import 'package:barangay_legal_aid/services/api_service.dart';

class SuggestionBoxScreen extends StatefulWidget {
  const SuggestionBoxScreen({super.key});

  @override
  State<SuggestionBoxScreen> createState() => _SuggestionBoxScreenState();
}

class _SuggestionBoxScreenState extends State<SuggestionBoxScreen> {
  final _formKey = GlobalKey<FormState>();
  final _subjectController = TextEditingController();
  final _detailsController = TextEditingController();

  String? _selectedCategory;
  String _selectedImpact = 'Medium';
  bool _isAnonymous = false;
  bool _isLoading = false;
  bool _submitted = false;

  // Photo attachment
  Uint8List? _photoBytes;
  String? _photoFilename;

  // Cross-barangay suggestion
  bool _isCrossBarangay = false;
  int? _targetBarangayId;
  List<Map<String, dynamic>> _barangays = [];

  static const Color _accent   = Color(0xFFF59E0B);
  static const Color _charcoal = Color(0xFF36454F);
  static const Color _primary  = Color(0xFF99272D);

  static const _photoStorageKey     = 'suggestion_draft_photo_data';
  static const _photoNameStorageKey = 'suggestion_draft_photo_name';

  static const List<Map<String, dynamic>> _categories = [
    {'label': 'Infrastructure',    'icon': Icons.construction,        'color': Color(0xFF0277BD)},
    {'label': 'Public Services',   'icon': Icons.manage_accounts,     'color': Color(0xFF00897B)},

    {'label': 'Programs / Events', 'icon': Icons.event,               'color': Color(0xFF7B1FA2)},
    {'label': 'Safety & Security', 'icon': Icons.shield,              'color': Color(0xFFD32F2F)},
    {'label': 'Technology',        'icon': Icons.devices,             'color': Color(0xFF1565C0)},
    {'label': 'Environment',       'icon': Icons.park,                'color': Color(0xFF2E7D32)},
    {'label': 'Other',             'icon': Icons.lightbulb_outline,   'color': Color(0xFFF59E0B)},
  ];

  static const List<Map<String, dynamic>> _impacts = [
    {'label': 'Low',    'color': Color(0xFF43A047), 'icon': Icons.sentiment_satisfied_alt},
    {'label': 'Medium', 'color': Color(0xFFF59E0B), 'icon': Icons.sentiment_neutral},
    {'label': 'High',   'color': Color(0xFFE53935), 'icon': Icons.sentiment_very_dissatisfied},
  ];

  @override
  void initState() {
    super.initState();
    _loadPhotoFromStorage();
    _loadBarangays();
    WidgetsBinding.instance.addPostFrameCallback((_) => _showWelcomeDialog());
  }

  Future<void> _loadBarangays() async {
    try {
      final api = Provider.of<ApiService>(context, listen: false);
      final list = await api.getBarangays();
      if (mounted) setState(() => _barangays = list);
    } catch (_) {}
  }

  // ── localStorage photo persistence ───────────────────────────────────────
  void _loadPhotoFromStorage() {
    try {
      final data = html.window.localStorage[_photoStorageKey];
      final name = html.window.localStorage[_photoNameStorageKey];
      if (data != null && data.isNotEmpty && name != null) {
        final bytes = base64Decode(data);
        setState(() { _photoBytes = bytes; _photoFilename = name; });
      }
    } catch (_) {}
  }

  void _savePhotoToStorage(List<int> bytes, String name) {
    try {
      html.window.localStorage[_photoStorageKey]     = base64Encode(bytes);
      html.window.localStorage[_photoNameStorageKey] = name;
    } catch (_) {}
  }

  void _clearPhotoFromStorage() {
    html.window.localStorage.remove(_photoStorageKey);
    html.window.localStorage.remove(_photoNameStorageKey);
  }

  // ── Photo picker ──────────────────────────────────────────────────────────
  void _pickPhoto() {
    final input = html.FileUploadInputElement()..accept = 'image/*';
    input.click();
    input.onChange.listen((_) {
      final file = input.files?.first;
      if (file == null) return;
      final reader = html.FileReader();
      reader.readAsArrayBuffer(file);
      reader.onLoad.listen((_) {
        final bytes = Uint8List.fromList(reader.result as List<int>);
        _savePhotoToStorage(bytes, file.name);
        if (mounted) setState(() { _photoBytes = bytes; _photoFilename = file.name; });
      });
    });
  }

  void _removePhoto() {
    _clearPhotoFromStorage();
    setState(() { _photoBytes = null; _photoFilename = null; });
  }

  @override
  void dispose() {
    _subjectController.dispose();
    _detailsController.dispose();
    super.dispose();
  }

  Future<void> _showWelcomeDialog() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Gradient banner
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [_accent, _accent.withValues(alpha: 0.75)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.lightbulb_rounded, color: Colors.white, size: 28),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Share Your Ideas',
                            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Your suggestions help us improve barangay services and better serve the community.',
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 13, height: 1.4),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // Close button
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _accent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('Got It', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _selectCategory(String label) {
    setState(() {
      _selectedCategory = label;
      if (_subjectController.text.isEmpty ||
          _categories.any((c) => c['label'] == _subjectController.text)) {
        _subjectController.text = label;
      }
    });
  }

  Future<void> _submit() async {
    if (_selectedCategory == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Please select a category for your suggestion.'),
        backgroundColor: _primary,
      ));
      return;
    }
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      final api = Provider.of<ApiService>(context, listen: false);
      final title = '[Suggestion][$_selectedCategory] ${_subjectController.text.trim()}';
      final description =
          'Impact: $_selectedImpact\nAnonymous: ${_isAnonymous ? "Yes" : "No"}\n\n${_detailsController.text.trim()}';
      final newCase = await api.createCase(
        title: title,
        description: description,
        targetBarangayId: _isCrossBarangay ? _targetBarangayId : null,
      );

      // Upload attachment if selected
      if (_photoBytes != null && _photoFilename != null) {
        final caseId = newCase['id'] as int?;
        if (caseId != null) {
          await api.uploadSuggestionAttachment(caseId, _photoBytes!, _photoFilename!);
        }
      }

      _clearPhotoFromStorage();
      if (!mounted) return;
      setState(() => _submitted = true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Failed to submit: $e'),
        backgroundColor: _primary,
      ));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        title: const Text('Suggestion Box'),
        backgroundColor: _accent,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _submitted ? _buildSuccessView() : _buildForm(),
    );
  }

  // ── Success screen ──────────────────────────────────────────────────────────
  Widget _buildSuccessView() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: _accent.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.lightbulb_rounded, color: _accent, size: 72),
              ),
              const SizedBox(height: 28),
              const Text(
                'Suggestion Received!',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: _charcoal),
              ),
              const SizedBox(height: 12),
              Text(
                'Thank you for sharing your idea. Your suggestion will be reviewed by the barangay office.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, color: _charcoal.withValues(alpha: 0.7), height: 1.5),
              ),
              const SizedBox(height: 8),
              Text(
                'Your voice helps us serve the community better.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: _charcoal.withValues(alpha: 0.55)),
              ),
              const SizedBox(height: 36),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Back to Services'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _accent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => setState(() {
                  _submitted = false;
                  _selectedCategory = null;
                  _subjectController.clear();
                  _detailsController.clear();
                  _selectedImpact = 'Medium';
                  _isAnonymous = false;
                  _photoBytes = null;
                  _photoFilename = null;
                  _isCrossBarangay = false;
                  _targetBarangayId = null;
                }),
                child: const Text('Submit Another Suggestion', style: TextStyle(color: _accent)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Form ────────────────────────────────────────────────────────────────────
  Widget _buildForm() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionLabel('1  Select Category', required: true),
                  const SizedBox(height: 12),
                  _buildCategoryGrid(),
                  const SizedBox(height: 28),
                  _sectionLabel('2  Subject', required: true),
                  const SizedBox(height: 10),
                  _buildSubjectField(),
                  const SizedBox(height: 28),
                  _sectionLabel('3  Your Suggestion', required: true),
                  const SizedBox(height: 10),
                  _buildDetailsField(),
                  const SizedBox(height: 28),
                  _sectionLabel('4  Expected Impact'),
                  const SizedBox(height: 12),
                  _buildImpactSelector(),
                  const SizedBox(height: 28),
                  _sectionLabel('5  Attach a Photo (optional)'),
                  const SizedBox(height: 12),
                  _buildPhotoSection(),
                  const SizedBox(height: 28),
                  _sectionLabel('6  Options'),
                  const SizedBox(height: 12),
                  _buildAnonymousToggle(),
                  const SizedBox(height: 10),
                  _buildCrossBarangayToggle(),
                  if (_isCrossBarangay) ...[
                    const SizedBox(height: 12),
                    _buildTargetBarangayDropdown(),
                  ],
                  const SizedBox(height: 32),
                  _buildSubmitButton(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(String text, {bool required = false}) {
    return Row(
      children: [
        Text(text, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: _charcoal)),
        if (required) ...[
          const SizedBox(width: 4),
          const Text('*', style: TextStyle(color: _primary, fontSize: 16)),
        ],
      ],
    );
  }

  Widget _buildCategoryGrid() {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 2.6,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: _categories.length,
      itemBuilder: (context, i) {
        final cat = _categories[i];
        final isSelected = _selectedCategory == cat['label'];
        final color = cat['color'] as Color;
        return GestureDetector(
          onTap: () => _selectCategory(cat['label']),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            decoration: BoxDecoration(
              color: isSelected ? color.withValues(alpha: 0.1) : Colors.white,
              border: Border.all(
                color: isSelected ? color : const Color(0xFFDDE3EE),
                width: isSelected ? 2 : 1,
              ),
              borderRadius: BorderRadius.circular(10),
              boxShadow: isSelected ? [BoxShadow(color: color.withValues(alpha: 0.15), blurRadius: 8)] : [],
            ),
            child: Row(
              children: [
                const SizedBox(width: 12),
                Icon(cat['icon'] as IconData, color: color, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    cat['label'],
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                      color: isSelected ? color : _charcoal,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSubjectField() {
    return TextFormField(
      controller: _subjectController,
      textCapitalization: TextCapitalization.sentences,
      decoration: InputDecoration(
        hintText: 'e.g. Add more street lights along Rizal Ave.',
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFDDE3EE)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _accent, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      validator: (v) {
        if (v == null || v.trim().isEmpty) return 'Please enter a subject';
        if (v.trim().length < 5) return 'Subject is too short';
        return null;
      },
    );
  }

  Widget _buildDetailsField() {
    return TextFormField(
      controller: _detailsController,
      maxLines: 6,
      textCapitalization: TextCapitalization.sentences,
      decoration: InputDecoration(
        hintText: 'Describe your suggestion in detail — what problem does it solve and how can it be implemented?',
        alignLabelWithHint: true,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFDDE3EE)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _accent, width: 2),
        ),
        contentPadding: const EdgeInsets.all(16),
      ),
      validator: (v) {
        if (v == null || v.trim().isEmpty) return 'Please describe your suggestion';
        if (v.trim().length < 20) return 'Details too short (min 20 characters)';
        return null;
      },
    );
  }

  Widget _buildImpactSelector() {
    return Row(
      children: _impacts.map((u) {
        final isSelected = _selectedImpact == u['label'];
        final color = u['color'] as Color;
        return Expanded(
          child: GestureDetector(
            onTap: () => setState(() => _selectedImpact = u['label']),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              margin: EdgeInsets.only(right: u['label'] != 'High' ? 8 : 0),
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: isSelected ? color.withValues(alpha: 0.1) : Colors.white,
                border: Border.all(
                  color: isSelected ? color : const Color(0xFFDDE3EE),
                  width: isSelected ? 2 : 1,
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                children: [
                  Icon(u['icon'] as IconData, color: isSelected ? color : Colors.grey, size: 20),
                  const SizedBox(height: 4),
                  Text(
                    u['label'],
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                      color: isSelected ? color : _charcoal,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  // ── Photo section ───────────────────────────────────────────────────────────
  Widget _buildPhotoSection() {
    if (_photoBytes != null && _photoFilename != null) {
      return Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFDDE3EE)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
              child: Image.memory(
                _photoBytes!,
                width: double.infinity,
                height: 200,
                fit: BoxFit.cover,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.image, size: 16, color: Colors.grey),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _photoFilename!,
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _pickPhoto,
                    icon: const Icon(Icons.edit, size: 14),
                    label: const Text('Change', style: TextStyle(fontSize: 12)),
                    style: TextButton.styleFrom(
                      foregroundColor: _accent,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _removePhoto,
                    icon: const Icon(Icons.delete_outline, size: 14),
                    label: const Text('Remove', style: TextStyle(fontSize: 12)),
                    style: TextButton.styleFrom(
                      foregroundColor: _primary,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return GestureDetector(
      onTap: _pickPhoto,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 28),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFDDE3EE), style: BorderStyle.solid),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _accent.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.add_a_photo_outlined, color: _accent, size: 28),
            ),
            const SizedBox(height: 10),
            const Text('Tap to attach a photo', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _charcoal)),
            const SizedBox(height: 4),
            Text('Optional — helps illustrate your suggestion', style: TextStyle(fontSize: 11, color: _charcoal.withValues(alpha: 0.55))),
          ],
        ),
      ),
    );
  }

  // ── Anonymous toggle ────────────────────────────────────────────────────────
  Widget _buildAnonymousToggle() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: _isAnonymous ? _accent.withValues(alpha: 0.5) : const Color(0xFFDDE3EE),
          width: _isAnonymous ? 2 : 1,
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.visibility_off_outlined, size: 20, color: _charcoal),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Submit Anonymously', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: _charcoal)),
                Text('Your name will not be shown to admins', style: TextStyle(fontSize: 11, color: _charcoal.withValues(alpha: 0.6))),
              ],
            ),
          ),
          Switch(
            value: _isAnonymous,
            onChanged: (v) => setState(() => _isAnonymous = v),
            activeThumbColor: _accent,
          ),
        ],
      ),
    );
  }

  // ── Cross-barangay toggle ───────────────────────────────────────────────────
  Widget _buildCrossBarangayToggle() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: _isCrossBarangay ? _accent.withValues(alpha: 0.5) : const Color(0xFFDDE3EE),
          width: _isCrossBarangay ? 2 : 1,
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.swap_horiz, size: 20, color: _charcoal),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Send to a Different Barangay', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: _charcoal)),
                Text('Route this suggestion to another barangay\'s admin', style: TextStyle(fontSize: 11, color: _charcoal.withValues(alpha: 0.6))),
              ],
            ),
          ),
          Switch(
            value: _isCrossBarangay,
            onChanged: (v) => setState(() {
              _isCrossBarangay = v;
              if (!v) _targetBarangayId = null;
            }),
            activeThumbColor: _accent,
          ),
        ],
      ),
    );
  }

  Widget _buildTargetBarangayDropdown() {
    return DropdownButtonFormField<int>(
      initialValue: _targetBarangayId,
      decoration: InputDecoration(
        labelText: 'Target Barangay *',
        prefixIcon: const Icon(Icons.location_city, size: 18),
        filled: true,
        fillColor: Colors.white,
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFDDE3EE))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _accent, width: 2)),
      ),
      hint: const Text('Select barangay'),
      items: _barangays.map((b) => DropdownMenuItem<int>(
        value: b['id'] as int,
        child: Text(b['name'] as String? ?? ''),
      )).toList(),
      onChanged: (v) => setState(() => _targetBarangayId = v),
      validator: (_) => _isCrossBarangay && _targetBarangayId == null ? 'Please select a target barangay' : null,
    );
  }

  Widget _buildSubmitButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _submit,
        style: ElevatedButton.styleFrom(
          backgroundColor: _accent,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 18),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 2,
        ),
        child: _isLoading
            ? const SizedBox(
                height: 22,
                width: 22,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
              )
            : const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.send_rounded, size: 20),
                  SizedBox(width: 10),
                  Text('Submit Suggestion', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ],
              ),
      ),
    );
  }
}
