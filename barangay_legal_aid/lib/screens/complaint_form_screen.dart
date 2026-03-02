import 'package:flutter/material.dart';
import 'package:barangay_legal_aid/services/api_service.dart';
import 'package:provider/provider.dart';

class ComplaintFormScreen extends StatefulWidget {
  const ComplaintFormScreen({super.key});

  @override
  State<ComplaintFormScreen> createState() => _ComplaintFormScreenState();
}

class _ComplaintFormScreenState extends State<ComplaintFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _subjectController = TextEditingController();
  final _descriptionController = TextEditingController();

  String? _selectedCategory;
  String _selectedUrgency = 'Medium';
  bool _declared = false;
  bool _isLoading = false;
  bool _submitted = false;

  static const Color _primary = Color(0xFF99272D);
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
                    child: const Icon(Icons.report_problem_rounded,
                        color: Colors.white, size: 28),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'File a Complaint',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'All complaints are treated with confidentiality and reviewed by the barangay office.',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.9),
                            fontSize: 13,
                            height: 1.4,
                          ),
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
                    backgroundColor: _primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('Got It',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ),
          ],
        ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _subjectController.dispose();
    _descriptionController.dispose();
    super.dispose();
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a complaint category.'),
          backgroundColor: _primary,
        ),
      );
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    if (!_declared) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please check the declaration box before submitting.'),
          backgroundColor: _primary,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final api = Provider.of<ApiService>(context, listen: false);
      final title = '[$_selectedCategory] ${_subjectController.text.trim()}';
      final description =
          'Urgency: $_selectedUrgency\n\n${_descriptionController.text.trim()}';
      await api.createCase(title: title, description: description);
      if (!mounted) return;
      setState(() => _submitted = true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to submit: $e'),
          backgroundColor: _primary,
        ),
      );
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
              child: const Icon(Icons.check_circle_rounded,
                  color: Color(0xFF43A047), size: 72),
            ),
            const SizedBox(height: 28),
            const Text(
              'Complaint Submitted!',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: _charcoal,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Your complaint has been received and will be reviewed by the barangay office.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                color: _charcoal.withValues(alpha: 0.7),
                height: 1.5,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'You can track the status under My Complaints.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: _charcoal.withValues(alpha: 0.55),
              ),
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
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => setState(() {
                _submitted = false;
                _selectedCategory = null;
                _subjectController.clear();
                _descriptionController.clear();
                _declared = false;
                _selectedUrgency = 'Medium';
              }),
              child: const Text('File Another Complaint',
                  style: TextStyle(color: _primary)),
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
        Text(
          text,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: _charcoal,
          ),
        ),
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
                      fontWeight:
                          isSelected ? FontWeight.w700 : FontWeight.w500,
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
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
        hintText:
            'Describe the incident in detail — include date, time, location, and any witnesses if applicable.',
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
        final color = u['color'] as Color;
        return Expanded(
          child: GestureDetector(
            onTap: () => setState(() => _selectedUrgency = u['label']),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              margin: EdgeInsets.only(
                right: u['label'] != 'High' ? 8 : 0,
              ),
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
                  Icon(u['icon'] as IconData,
                      color: isSelected ? color : Colors.grey, size: 20),
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
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 2,
        ),
        child: _isLoading
            ? const SizedBox(
                height: 22,
                width: 22,
                child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2.5),
              )
            : const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.send_rounded, size: 20),
                  SizedBox(width: 10),
                  Text(
                    'Submit Complaint',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
      ),
    );
  }
}
