import 'dart:async';
import 'package:flutter/material.dart';
import 'package:barangay_legal_aid/services/api_service.dart';
import 'package:provider/provider.dart';

// ── Per-respondent state ──────────────────────────────────────────────────────
class _RespondentEntry {
  bool isRegistered = false;
  int? selectedUserId;
  String? selectedUserDisplay;
  String? selectedUserBarangayName;
  int? barangayId;
  final TextEditingController nameCtrl    = TextEditingController();
  final TextEditingController addressCtrl = TextEditingController();
  final TextEditingController searchCtrl  = TextEditingController();
  List<Map<String, dynamic>> searchResults = [];
  bool isSearching = false;
  Timer? debounce;

  void dispose() {
    nameCtrl.dispose();
    addressCtrl.dispose();
    searchCtrl.dispose();
    debounce?.cancel();
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class ComplaintFormScreen extends StatefulWidget {
  const ComplaintFormScreen({super.key});

  @override
  State<ComplaintFormScreen> createState() => _ComplaintFormScreenState();
}

class _ComplaintFormScreenState extends State<ComplaintFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _subjectController     = TextEditingController();
  final _descriptionController = TextEditingController();

  String? _selectedCategory;
  String _selectedUrgency = 'Medium';
  bool _declared     = false;
  bool _isLoading    = false;
  bool _submitted    = false;
  bool _isCrossBarangay = false;

  // Respondents list — starts with one blank entry
  final List<_RespondentEntry> _respondents = [_RespondentEntry()];

  List<Map<String, dynamic>> _barangays = [];

  static const Color _primary  = Color(0xFF99272D);
  static const Color _charcoal = Color(0xFF36454F);

  static const List<Map<String, dynamic>> _categories = [
    {'label': 'Noise Complaint',    'icon': Icons.volume_up,      'color': Color(0xFF1E88E5)},
    {'label': 'Illegal Drugs',      'icon': Icons.dangerous,      'color': Color(0xFFE53935)},
    {'label': 'Property Dispute',   'icon': Icons.home_work,      'color': Color(0xFFFF9800)},
    {'label': 'Harassment',         'icon': Icons.person_off,     'color': Color(0xFF8E24AA)},
    {'label': 'Violence / Assault', 'icon': Icons.warning_amber,  'color': Color(0xFFB71C1C)},
    {'label': 'Theft / Robbery',    'icon': Icons.security,       'color': Color(0xFF5D4037)},
    {'label': 'Environmental',      'icon': Icons.eco,            'color': Color(0xFF388E3C)},
    {'label': 'Other',              'icon': Icons.more_horiz,     'color': Color(0xFF607D8B)},
  ];

  static const List<Map<String, dynamic>> _urgencies = [
    {'label': 'Low',    'color': Color(0xFF43A047), 'icon': Icons.arrow_downward},
    {'label': 'Medium', 'color': Color(0xFFFB8C00), 'icon': Icons.remove},
    {'label': 'High',   'color': Color(0xFFE53935), 'icon': Icons.arrow_upward},
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _showWelcomeDialog());
    _loadBarangays();
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
    _subjectController.dispose();
    _descriptionController.dispose();
    for (final e in _respondents) { e.dispose(); }
    super.dispose();
  }

  // ── Per-respondent search ─────────────────────────────────────────────────

  void _onUserSearch(int idx, String query) {
    final entry = _respondents[idx];
    entry.debounce?.cancel();
    if (query.trim().length < 2) {
      setState(() { entry.searchResults = []; entry.isSearching = false; });
      return;
    }
    setState(() => entry.isSearching = true);
    entry.debounce = Timer(const Duration(milliseconds: 400), () async {
      final api = Provider.of<ApiService>(context, listen: false);
      try {
        final results = await api.searchUsers(query);
        if (mounted) setState(() { entry.searchResults = results; entry.isSearching = false; });
      } catch (_) {
        if (mounted) setState(() { entry.searchResults = []; entry.isSearching = false; });
      }
    });
  }

  void _selectUser(int idx, Map<String, dynamic> user) {
    final entry = _respondents[idx];
    final display = '${user['first_name']} ${user['last_name']}'.trim();
    setState(() {
      entry.selectedUserId          = user['id'] as int?;
      entry.selectedUserDisplay     = display;
      entry.nameCtrl.text           = display;
      entry.searchCtrl.text         = display;
      entry.searchResults           = [];
      entry.isSearching             = false;
      if (user['barangay_id'] != null) {
        entry.barangayId                = user['barangay_id'] as int?;
        entry.selectedUserBarangayName  = user['barangay_name'] as String?;
      }
    });
  }

  void _clearSelectedUser(int idx) {
    final entry = _respondents[idx];
    setState(() {
      entry.selectedUserId      = null;
      entry.selectedUserDisplay = null;
      entry.nameCtrl.clear();
      entry.searchCtrl.clear();
      entry.searchResults = [];
      entry.isSearching   = false;
    });
  }

  void _addRespondent() {
    if (_respondents.length >= 30) return;
    setState(() => _respondents.add(_RespondentEntry()));
  }

  void _removeRespondent(int idx) {
    _respondents[idx].dispose();
    setState(() => _respondents.removeAt(idx));
  }

  // ── Welcome dialog ────────────────────────────────────────────────────────

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
                            'All complaints are treated with confidentiality and reviewed by the barangay office.',
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
        content: Text('Please select a complaint category.'),
        backgroundColor: _primary,
      ));
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    if (!_declared) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Please check the declaration box before submitting.'),
        backgroundColor: _primary,
      ));
      return;
    }

    setState(() => _isLoading = true);
    try {
      final api   = Provider.of<ApiService>(context, listen: false);
      final title = '[$_selectedCategory] ${_subjectController.text.trim()}';
      final description =
          'Urgency: $_selectedUrgency\n\n${_descriptionController.text.trim()}';
      final newCase = await api.createCase(title: title, description: description);
      final caseId = newCase['id'] as int?;

      if (caseId != null) {
        for (final entry in _respondents) {
          final name    = entry.nameCtrl.text.trim();
          final address = entry.addressCtrl.text.trim();
          // Skip completely empty entries
          if (entry.selectedUserId == null && name.isEmpty && address.isEmpty && entry.barangayId == null) {
            continue;
          }
          await api.addRespondent(caseId, {
            'is_registered_user': entry.isRegistered,
            if (entry.isRegistered && entry.selectedUserId != null)
              'respondent_id': entry.selectedUserId,
            if (name.isNotEmpty) 'respondent_name': name,
            if (_isCrossBarangay && entry.barangayId != null)
              'respondent_barangay_id': entry.barangayId,
            if (address.isNotEmpty) 'respondent_address': address,
          });
        }
      }

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
        title: const Text('File a Complaint'),
        backgroundColor: _primary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _submitted ? _buildSuccessView() : _buildForm(),
    );
  }

  // ── Success screen ────────────────────────────────────────────────────────
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
              const SizedBox(height: 8),
              Text(
                'You can track the status under My Complaints.',
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
                    backgroundColor: _primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () {
                  for (final e in _respondents) { e.dispose(); }
                  _respondents.clear();
                  _respondents.add(_RespondentEntry());
                  setState(() {
                    _submitted        = false;
                    _selectedCategory = null;
                    _subjectController.clear();
                    _descriptionController.clear();
                    _declared         = false;
                    _selectedUrgency  = 'Medium';
                    _isCrossBarangay  = false;
                  });
                },
                child: const Text('File Another Complaint', style: TextStyle(color: _primary)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Form ─────────────────────────────────────────────────────────────────
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
                  _buildRespondentSection(),
                  const SizedBox(height: 28),
                  _buildDeclarationBox(),
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
        final cat        = _categories[i];
        final isSelected = _selectedCategory == cat['label'];
        final color      = cat['color'] as Color;
        return GestureDetector(
          onTap: () => _selectCategory(cat['label']),
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
      controller: _descriptionController,
      maxLines: 6,
      textCapitalization: TextCapitalization.sentences,
      decoration: InputDecoration(
        hintText: 'Describe the incident in detail — include date, time, location, and any witnesses if applicable.',
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
        if (v.trim().length < 20) return 'Description is too short (min 20 characters)';
        return null;
      },
    );
  }

  Widget _buildUrgencySelector() {
    return Row(
      children: _urgencies.map((u) {
        final isSelected = _selectedUrgency == u['label'];
        final color      = u['color'] as Color;
        return Expanded(
          child: GestureDetector(
            onTap: () => setState(() => _selectedUrgency = u['label']),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              margin: EdgeInsets.only(right: u['label'] != 'High' ? 8 : 0),
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

  // ── Respondent section ───────────────────────────────────────────────────

  Widget _buildRespondentSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('5  Respondent / Person Involved'),
        const SizedBox(height: 12),
        // Cross-barangay toggle
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: _isCrossBarangay ? _primary.withValues(alpha: 0.5) : const Color(0xFFDDE3EE),
              width: _isCrossBarangay ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              const Icon(Icons.location_on_outlined, color: _primary, size: 20),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Cross-Barangay Complaint',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _charcoal)),
                    Text('The person I\'m complaining about is from a different barangay',
                        style: TextStyle(fontSize: 11, color: Colors.grey)),
                  ],
                ),
              ),
              Switch(
                value: _isCrossBarangay,
                onChanged: (v) => setState(() => _isCrossBarangay = v),
                activeThumbColor: _primary,
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        // Respondent cards
        ...List.generate(_respondents.length, (i) => Padding(
          padding: EdgeInsets.only(bottom: i < _respondents.length - 1 ? 10 : 0),
          child: _buildRespondentCard(i),
        )),
        // Add respondent button
        if (_respondents.length < 30) ...[
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _addRespondent,
            icon: const Icon(Icons.person_add_outlined, size: 18),
            label: Text(
              _respondents.length == 1
                  ? 'Add Another Person Involved'
                  : 'Add Another (${_respondents.length}/30)',
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: _primary,
              side: const BorderSide(color: _primary),
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildRespondentCard(int idx) {
    final entry = _respondents[idx];
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFDDE3EE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              Text(
                _respondents.length > 1 ? 'Respondent ${idx + 1}' : 'Person Involved',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _charcoal),
              ),
              const Spacer(),
              if (_respondents.length > 1)
                InkWell(
                  onTap: () => _removeRespondent(idx),
                  borderRadius: BorderRadius.circular(20),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.remove_circle_outline, size: 16, color: Colors.redAccent),
                        const SizedBox(width: 4),
                        Text('Remove', style: TextStyle(fontSize: 11, color: Colors.redAccent.shade200)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          // Registered toggle
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF8F9FA),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFDDE3EE)),
            ),
            child: Row(
              children: [
                const Icon(Icons.verified_user_outlined, color: Color(0xFF1565C0), size: 16),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('Registered in Barangay Legal Aid',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _charcoal)),
                ),
                Switch(
                  value: entry.isRegistered,
                  onChanged: (v) => setState(() {
                    entry.isRegistered = v;
                    if (!v) _clearSelectedUser(idx);
                  }),
                  activeThumbColor: const Color(0xFF1565C0),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          // Name: search if registered, plain text if not
          if (entry.isRegistered)
            _buildUserSearchField(idx)
          else
            TextFormField(
              controller: entry.nameCtrl,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: 'Name (optional)',
                hintText: 'Full name — leave blank if unknown',
                prefixIcon: const Icon(Icons.person_outline, size: 18),
                filled: true,
                fillColor: const Color(0xFFF8F9FA),
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFFDDE3EE))),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: _primary, width: 2)),
              ),
            ),
          const SizedBox(height: 10),
          // Address
          TextFormField(
            controller: entry.addressCtrl,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: 'Address (optional)',
              hintText: 'e.g. 123 Rizal St.',
              prefixIcon: const Icon(Icons.home_outlined, size: 18),
              filled: true,
              fillColor: const Color(0xFFF8F9FA),
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFFDDE3EE))),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: _primary, width: 2)),
            ),
          ),
          // Barangay dropdown — only when cross-barangay is on
          if (_isCrossBarangay) ...[
            const SizedBox(height: 10),
            DropdownButtonFormField<int>(
              initialValue: entry.barangayId,
              decoration: InputDecoration(
                labelText: 'Respondent\'s Barangay *',
                prefixIcon: const Icon(Icons.location_city, size: 18),
                filled: true,
                fillColor: const Color(0xFFF8F9FA),
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFFDDE3EE))),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: _primary, width: 2)),
              ),
              hint: const Text('Select barangay'),
              items: _barangays.map((b) => DropdownMenuItem<int>(
                value: b['id'] as int,
                child: Text(b['name'] as String? ?? ''),
              )).toList(),
              onChanged: (v) => setState(() => entry.barangayId = v),
              validator: (_) => _isCrossBarangay && entry.barangayId == null
                  ? 'Please select the respondent\'s barangay'
                  : null,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildUserSearchField(int idx) {
    final entry = _respondents[idx];

    if (entry.selectedUserDisplay != null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFE8F5E9),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF43A047).withValues(alpha: 0.5)),
        ),
        child: Row(
          children: [
            const Icon(Icons.check_circle, color: Color(0xFF43A047), size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(entry.selectedUserDisplay!,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _charcoal)),
                  if (entry.selectedUserBarangayName != null)
                    Text('Brgy. ${entry.selectedUserBarangayName}',
                        style: const TextStyle(fontSize: 11, color: Colors.grey)),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 18, color: Colors.grey),
              tooltip: 'Clear selection',
              onPressed: () => _clearSelectedUser(idx),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: entry.searchCtrl,
          onChanged: (q) => _onUserSearch(idx, q),
          decoration: InputDecoration(
            labelText: 'Search Respondent',
            hintText: 'Type name or email...',
            prefixIcon: const Icon(Icons.search, size: 18),
            suffixIcon: entry.isSearching
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                : entry.searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () => _clearSelectedUser(idx),
                      )
                    : null,
            filled: true,
            fillColor: const Color(0xFFF8F9FA),
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFFDDE3EE))),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: _primary, width: 2)),
          ),
        ),
        if (entry.searchResults.isNotEmpty) ...[
          const SizedBox(height: 4),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFDDE3EE)),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(0, 2))],
            ),
            child: Column(
              children: entry.searchResults.map((user) {
                final name     = '${user['first_name']} ${user['last_name']}'.trim();
                final email    = user['email'] as String? ?? '';
                final barangay = user['barangay_name'] as String?;
                return InkWell(
                  onTap: () => _selectUser(idx, user),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 16,
                          backgroundColor: _primary.withValues(alpha: 0.12),
                          child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _primary)),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _charcoal)),
                              Text(
                                [email, if (barangay != null) 'Brgy. $barangay'].join(' · '),
                                style: const TextStyle(fontSize: 11, color: Colors.grey),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right, size: 16, color: Colors.grey),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ] else if (!entry.isSearching && entry.searchCtrl.text.trim().length >= 2) ...[
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Text('No registered users found for "${entry.searchCtrl.text.trim()}"',
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ),
        ],
      ],
    );
  }

  Widget _buildDeclarationBox() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _declared ? const Color(0xFF43A047).withValues(alpha: 0.5) : const Color(0xFFDDE3EE),
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
                style: TextStyle(fontSize: 13, color: _charcoal.withValues(alpha: 0.8), height: 1.4),
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
                height: 22,
                width: 22,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
              )
            : const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.send_rounded, size: 20),
                  SizedBox(width: 10),
                  Text('Submit Complaint', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ],
              ),
      ),
    );
  }
}
