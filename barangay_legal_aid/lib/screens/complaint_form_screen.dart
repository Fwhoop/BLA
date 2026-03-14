import 'dart:async';
import 'package:flutter/material.dart';
import 'package:barangay_legal_aid/services/api_service.dart';
import 'package:provider/provider.dart';

class ComplaintFormScreen extends StatefulWidget {
  const ComplaintFormScreen({super.key});

  @override
  State<ComplaintFormScreen> createState() => _ComplaintFormScreenState();
}

// Holds one respondent entry (registered or manual)
class _RespondentEntry {
  bool isRegistered = false;
  // Registered user fields
  Map<String, dynamic>? selectedUser;
  // Manual fields
  bool unknownName = false;
  final nameCtrl    = TextEditingController();
  final addressCtrl = TextEditingController();
  String? barangayId;
  String? barangayName;

  void dispose() {
    nameCtrl.dispose();
    addressCtrl.dispose();
  }
}

class _ComplaintFormScreenState extends State<ComplaintFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _subjectCtrl     = TextEditingController();
  final _descriptionCtrl = TextEditingController();

  String? _selectedCategory;
  String  _selectedUrgency = 'medium';
  bool    _declared  = false;
  bool    _isLoading = false;
  bool    _submitted = false;

  // Respondents
  final List<_RespondentEntry> _respondents = [_RespondentEntry()];

  // Barangays for respondent dropdown
  List<Map<String, dynamic>> _barangays = [];

  static const Color _primary  = Color(0xFF99272D);
  static const Color _charcoal = Color(0xFF36454F);

  static const List<Map<String, dynamic>> _categories = [
    {'label': 'Noise Complaint',    'value': 'noise',       'icon': Icons.volume_up,      'color': Color(0xFF1E88E5)},
    {'label': 'Illegal Drugs',      'value': 'drugs',       'icon': Icons.dangerous,      'color': Color(0xFFE53935)},
    {'label': 'Property Dispute',   'value': 'property',    'icon': Icons.home_work,      'color': Color(0xFFFF9800)},
    {'label': 'Harassment',         'value': 'harassment',  'icon': Icons.person_off,     'color': Color(0xFF8E24AA)},
    {'label': 'Violence / Assault', 'value': 'violence',    'icon': Icons.warning_amber,  'color': Color(0xFFB71C1C)},
    {'label': 'Theft / Robbery',    'value': 'theft',       'icon': Icons.security,       'color': Color(0xFF5D4037)},
    {'label': 'Environmental',      'value': 'environment', 'icon': Icons.eco,            'color': Color(0xFF388E3C)},
    {'label': 'Other',              'value': 'other',       'icon': Icons.more_horiz,     'color': Color(0xFF607D8B)},
  ];

  static const List<Map<String, dynamic>> _urgencies = [
    {'label': 'Low',    'value': 'low',    'color': Color(0xFF43A047), 'icon': Icons.arrow_downward},
    {'label': 'Medium', 'value': 'medium', 'color': Color(0xFFFB8C00), 'icon': Icons.remove},
    {'label': 'High',   'value': 'high',   'color': Color(0xFFE53935), 'icon': Icons.arrow_upward},
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _showWelcomeDialog();
      _loadBarangays();
    });
  }

  Future<void> _loadBarangays() async {
    try {
      final api = Provider.of<ApiService>(context, listen: false);
      final list = await api.getBarangays();
      if (mounted) setState(() => _barangays = list);
    } catch (_) {}
  }

  @override
  void dispose() {
    _subjectCtrl.dispose();
    _descriptionCtrl.dispose();
    for (final r in _respondents) { r.dispose(); }
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
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF99272D), Color(0xFF6B1A1E)],
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
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.report_problem_rounded, color: Colors.white, size: 28),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('File a Complaint',
                              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 6),
                          Text(
                            'All complaints are treated with confidentiality and reviewed by the barangay office. You may file against anyone, including persons from other barangays.',
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 13, height: 1.4),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _primary,
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

  // ── Submit ───────────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    if (_selectedCategory == null) {
      _showSnack('Please select a complaint category.');
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    if (!_declared) {
      _showSnack('Please check the declaration box before submitting.');
      return;
    }

    setState(() => _isLoading = true);
    try {
      final api = Provider.of<ApiService>(context, listen: false);

      // Find category label
      final catLabel = _categories.firstWhere(
        (c) => c['value'] == _selectedCategory,
        orElse: () => _categories.last,
      )['label'] as String;

      final newCase = await api.createCase(
        title:       '[$catLabel] ${_subjectCtrl.text.trim()}',
        description: _descriptionCtrl.text.trim(),
        category:    _selectedCategory,
        urgency:     _selectedUrgency,
      );

      final caseId = newCase['id'] as int?;
      if (caseId != null) {
        for (final r in _respondents) {
          // Skip blank entries
          if (r.isRegistered && r.selectedUser == null) continue;
          if (!r.isRegistered && !r.unknownName && r.nameCtrl.text.trim().isEmpty) continue;

          final payload = <String, dynamic>{
            'is_registered_user': r.isRegistered,
            'unknown_name': r.unknownName,
          };
          if (r.isRegistered && r.selectedUser != null) {
            payload['respondent_id'] = r.selectedUser!['id'];
          } else {
            if (!r.unknownName) payload['respondent_name'] = r.nameCtrl.text.trim();
            if (r.addressCtrl.text.trim().isNotEmpty) {
              payload['respondent_address'] = r.addressCtrl.text.trim();
            }
            if (r.barangayId != null) {
              payload['respondent_barangay_id'] = int.tryParse(r.barangayId!);
            }
          }
          try {
            await api.addRespondent(caseId, payload);
          } catch (_) {
            // Non-fatal — case was created; respondent may fail silently
          }
        }
      }

      if (!mounted) return;
      setState(() => _submitted = true);
    } catch (e) {
      if (!mounted) return;
      _showSnack('Failed to submit: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: _primary),
    );
  }

  void _selectCategory(String value) {
    setState(() {
      _selectedCategory = value;
      final label = _categories.firstWhere((c) => c['value'] == value)['label'] as String;
      if (_subjectCtrl.text.isEmpty ||
          _categories.any((c) => c['label'] == _subjectCtrl.text)) {
        _subjectCtrl.text = label;
      }
    });
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        title: const Text('File a Complaint'),
        backgroundColor: _primary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _submitted ? _buildSuccessView() : _buildForm(),
    );
  }

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
                  color: const Color(0xFF43A047).withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_circle_rounded, color: Color(0xFF43A047), size: 72),
              ),
              const SizedBox(height: 28),
              const Text('Complaint Submitted!',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: _charcoal)),
              const SizedBox(height: 12),
              Text(
                'Your complaint has been received and will be reviewed by the barangay office.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, color: _charcoal.withValues(alpha: 0.7), height: 1.5),
              ),
              const SizedBox(height: 36),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Back to Services'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primary,
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
                  _subjectCtrl.clear();
                  _descriptionCtrl.clear();
                  _declared = false;
                  _selectedUrgency = 'medium';
                  for (final r in _respondents) { r.dispose(); }
                  _respondents.clear();
                  _respondents.add(_RespondentEntry());
                }),
                child: const Text('File Another Complaint', style: TextStyle(color: _primary)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildForm() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionLabel('1  Select Complaint Category', required: true),
                const SizedBox(height: 12),
                _buildCategoryGrid(),
                const SizedBox(height: 28),
                _sectionLabel('2  Subject', required: true),
                const SizedBox(height: 10),
                _buildSubjectField(),
                const SizedBox(height: 28),
                _sectionLabel('3  Describe the Complaint', required: true),
                const SizedBox(height: 10),
                _buildDescriptionField(),
                const SizedBox(height: 28),
                _sectionLabel('4  Urgency Level'),
                const SizedBox(height: 12),
                _buildUrgencySelector(),
                const SizedBox(height: 28),
                _sectionLabel('5  Respondent(s)'),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFBFDBFE)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.info_outline_rounded, size: 14, color: Color(0xFF1D4ED8)),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'You can file against anyone, including persons from a different barangay.',
                          style: TextStyle(fontSize: 12, color: Color(0xFF1D4ED8)),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                ..._respondents.asMap().entries.map((e) => _RespondentCard(
                  index: e.key,
                  entry: e.value,
                  barangays: _barangays,
                  canRemove: _respondents.length > 1,
                  onRemove: () => setState(() {
                    e.value.dispose();
                    _respondents.removeAt(e.key);
                  }),
                  onChanged: () => setState(() {}),
                )),
                if (_respondents.length < 5) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () => setState(() => _respondents.add(_RespondentEntry())),
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Add Another Respondent'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ],
                const SizedBox(height: 28),
                _buildDeclarationBox(),
                const SizedBox(height: 32),
                _buildSubmitButton(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(String text, {bool required = false}) {
    return Row(
      children: [
        Text(text,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: _charcoal)),
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
        crossAxisCount: 2, childAspectRatio: 2.6, crossAxisSpacing: 10, mainAxisSpacing: 10,
      ),
      itemCount: _categories.length,
      itemBuilder: (_, i) {
        final cat = _categories[i];
        final isSelected = _selectedCategory == cat['value'];
        final color = cat['color'] as Color;
        return GestureDetector(
          onTap: () => _selectCategory(cat['value'] as String),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            decoration: BoxDecoration(
              color: isSelected ? color.withValues(alpha: 0.12) : Colors.white,
              border: Border.all(
                color: isSelected ? color : const Color(0xFFDDE3EE),
                width: isSelected ? 2 : 1,
              ),
              borderRadius: BorderRadius.circular(10),
              boxShadow: isSelected
                  ? [BoxShadow(color: color.withValues(alpha: 0.18), blurRadius: 8)]
                  : [],
            ),
            child: Row(
              children: [
                const SizedBox(width: 12),
                Icon(cat['icon'] as IconData, color: color, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    cat['label'] as String,
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
      controller: _subjectCtrl,
      textCapitalization: TextCapitalization.sentences,
      decoration: InputDecoration(
        hintText: 'e.g. Loud music from neighbor every night',
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFDDE3EE)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _primary, width: 2),
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

  Widget _buildDescriptionField() {
    return TextFormField(
      controller: _descriptionCtrl,
      maxLines: 6,
      textCapitalization: TextCapitalization.sentences,
      decoration: InputDecoration(
        hintText: 'Describe the incident — include date, time, location, and witnesses if applicable.',
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
          borderSide: const BorderSide(color: _primary, width: 2),
        ),
        contentPadding: const EdgeInsets.all(16),
      ),
      validator: (v) {
        if (v == null || v.trim().isEmpty) return 'Please describe the complaint';
        if (v.trim().length < 20) return 'Description too short (min 20 characters)';
        return null;
      },
    );
  }

  Widget _buildUrgencySelector() {
    return Row(
      children: _urgencies.map((u) {
        final isSelected = _selectedUrgency == u['value'];
        final color = u['color'] as Color;
        return Expanded(
          child: GestureDetector(
            onTap: () => setState(() => _selectedUrgency = u['value'] as String),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              margin: EdgeInsets.only(right: u['value'] != 'high' ? 8 : 0),
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: isSelected ? color.withValues(alpha: 0.12) : Colors.white,
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
                    u['label'] as String,
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

  Widget _buildDeclarationBox() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _declared
              ? const Color(0xFF43A047).withValues(alpha: 0.5)
              : const Color(0xFFDDE3EE),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Checkbox(
            value: _declared,
            onChanged: (v) => setState(() => _declared = v ?? false),
            activeColor: const Color(0xFF43A047),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Text(
                'I declare that the information provided above is true and accurate to the best of my knowledge.',
                style: TextStyle(
                  fontSize: 13,
                  color: _charcoal.withValues(alpha: 0.8),
                  height: 1.4,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubmitButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _submit,
        style: ElevatedButton.styleFrom(
          backgroundColor: _primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 18),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 2,
        ),
        child: _isLoading
            ? const SizedBox(
                height: 22, width: 22,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
              )
            : const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.send_rounded, size: 20),
                  SizedBox(width: 10),
                  Text('Submit Complaint',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ],
              ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Respondent Card Widget
// ─────────────────────────────────────────────────────────────────────────────

class _RespondentCard extends StatefulWidget {
  final int index;
  final _RespondentEntry entry;
  final List<Map<String, dynamic>> barangays;
  final bool canRemove;
  final VoidCallback onRemove;
  final VoidCallback onChanged;

  const _RespondentCard({
    required this.index,
    required this.entry,
    required this.barangays,
    required this.canRemove,
    required this.onRemove,
    required this.onChanged,
  });

  @override
  State<_RespondentCard> createState() => _RespondentCardState();
}

class _RespondentCardState extends State<_RespondentCard> {
  // User search
  final _userSearchCtrl = TextEditingController();
  List<Map<String, dynamic>> _searchResults = [];
  Timer? _searchDebounce;
  bool _isSearching = false;

  @override
  void dispose() {
    _userSearchCtrl.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  void _onUserSearch(String q) {
    _searchDebounce?.cancel();
    if (q.trim().length < 2) {
      setState(() => _searchResults = []);
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 400), () async {
      if (!mounted) return;
      setState(() => _isSearching = true);
      try {
        final api = Provider.of<ApiService>(context, listen: false);
        final results = await api.searchUsers(q.trim());
        if (mounted) setState(() => _searchResults = results);
      } catch (_) {
        if (mounted) setState(() => _searchResults = []);
      } finally {
        if (mounted) setState(() => _isSearching = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    const Color primary  = Color(0xFF99272D);
    const Color charcoal = Color(0xFF36454F);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: primary.withValues(alpha: 0.05),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                Icon(Icons.person_pin_outlined, size: 16, color: primary.withValues(alpha: 0.8)),
                const SizedBox(width: 8),
                Text('Respondent ${widget.index + 1}',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: charcoal)),
                const Spacer(),
                if (widget.canRemove)
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline, size: 18, color: Color(0xFFEF4444)),
                    onPressed: widget.onRemove,
                    tooltip: 'Remove respondent',
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Toggle: registered vs manual
                Row(
                  children: [
                    const Text('Is respondent a registered user?',
                        style: TextStyle(fontSize: 13, color: charcoal)),
                    const Spacer(),
                    Switch(
                      value: entry.isRegistered,
                      onChanged: (v) => setState(() {
                        entry.isRegistered = v;
                        entry.selectedUser = null;
                        _searchResults = [];
                        _userSearchCtrl.clear();
                        widget.onChanged();
                      }),
                      activeThumbColor: primary,
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                if (entry.isRegistered) ...[
                  // Registered user search
                  TextField(
                    controller: _userSearchCtrl,
                    onChanged: _onUserSearch,
                    decoration: InputDecoration(
                      hintText: 'Search by name or email…',
                      prefixIcon: const Icon(Icons.search, size: 18),
                      suffixIcon: _isSearching
                          ? const SizedBox(
                              width: 18, height: 18,
                              child: Padding(
                                padding: EdgeInsets.all(12),
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ))
                          : null,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      isDense: true,
                    ),
                  ),
                  if (_searchResults.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Container(
                      constraints: const BoxConstraints(maxHeight: 200),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade200),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: _searchResults.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final u = _searchResults[i];
                          final name = '${u['first_name'] ?? ''} ${u['last_name'] ?? ''}'.trim();
                          final email = u['email'] as String? ?? '';
                          return ListTile(
                            dense: true,
                            leading: CircleAvatar(
                              radius: 14,
                              backgroundColor: primary.withValues(alpha: 0.1),
                              child: Text(
                                name.isNotEmpty ? name[0].toUpperCase() : '?',
                                style: const TextStyle(fontSize: 12, color: primary, fontWeight: FontWeight.bold),
                              ),
                            ),
                            title: Text(name, style: const TextStyle(fontSize: 13)),
                            subtitle: Text(email, style: const TextStyle(fontSize: 11)),
                            onTap: () {
                              setState(() {
                                entry.selectedUser = u;
                                _userSearchCtrl.text = name;
                                _searchResults = [];
                              });
                              widget.onChanged();
                            },
                          );
                        },
                      ),
                    ),
                  ],
                  if (entry.selectedUser != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0FDF4),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFBBF7D0)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle_rounded, size: 14, color: Color(0xFF16A34A)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${entry.selectedUser!['first_name'] ?? ''} ${entry.selectedUser!['last_name'] ?? ''}'.trim(),
                              style: const TextStyle(fontSize: 13, color: Color(0xFF166534), fontWeight: FontWeight.w600),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, size: 14, color: Color(0xFF166534)),
                            onPressed: () => setState(() { entry.selectedUser = null; _userSearchCtrl.clear(); }),
                            visualDensity: VisualDensity.compact,
                          ),
                        ],
                      ),
                    ),
                  ],
                ] else ...[
                  // Manual entry
                  Row(
                    children: [
                      Checkbox(
                        value: entry.unknownName,
                        onChanged: (v) => setState(() {
                          entry.unknownName = v ?? false;
                          if (entry.unknownName) entry.nameCtrl.clear();
                          widget.onChanged();
                        }),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                      ),
                      const Text('I don\'t know the respondent\'s name',
                          style: TextStyle(fontSize: 12, color: charcoal)),
                    ],
                  ),
                  if (!entry.unknownName) ...[
                    const SizedBox(height: 8),
                    TextField(
                      controller: entry.nameCtrl,
                      textCapitalization: TextCapitalization.words,
                      decoration: InputDecoration(
                        labelText: 'Respondent\'s full name',
                        prefixIcon: const Icon(Icons.person_outline, size: 18),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        isDense: true,
                      ),
                      onChanged: (_) => widget.onChanged(),
                    ),
                  ],
                  const SizedBox(height: 10),
                  TextField(
                    controller: entry.addressCtrl,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      labelText: 'Respondent\'s address (optional)',
                      prefixIcon: const Icon(Icons.location_on_outlined, size: 18),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      isDense: true,
                    ),
                    onChanged: (_) => widget.onChanged(),
                  ),
                  const SizedBox(height: 10),
                  // Barangay of respondent
                  if (widget.barangays.isNotEmpty)
                    DropdownButtonFormField<String>(
                      initialValue: entry.barangayId,
                      decoration: InputDecoration(
                        labelText: 'Respondent\'s barangay (optional)',
                        prefixIcon: const Icon(Icons.place_outlined, size: 18),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        isDense: true,
                      ),
                      items: [
                        const DropdownMenuItem<String>(value: null, child: Text('— Not specified —')),
                        ...widget.barangays.map((b) => DropdownMenuItem<String>(
                          value: b['id'].toString(),
                          child: Text(b['name'] as String? ?? ''),
                        )),
                      ],
                      onChanged: (v) => setState(() {
                        entry.barangayId = v;
                        entry.barangayName = widget.barangays
                            .firstWhere((b) => b['id'].toString() == v, orElse: () => {})['name']
                            as String?;
                        widget.onChanged();
                      }),
                    ),
                  if (entry.barangayId != null) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline_rounded, size: 12, color: Color(0xFF1D4ED8)),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              entry.barangayName != null
                                  ? 'Cross-barangay complaint — both barangay offices will be notified.'
                                  : '',
                              style: const TextStyle(fontSize: 11, color: Color(0xFF1D4ED8)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
