import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:barangay_legal_aid/services/api_service.dart';
import 'package:barangay_legal_aid/utils/top_snack.dart';

const _kPrimary = Color(0xFF99272D);
const _kCharcoal = Color(0xFF36454F);

const _statusMeta = <String, _StatusInfo>{
  'pending':    _StatusInfo(label: 'Pending',    color: Color(0xFFF59E0B), icon: Icons.hourglass_empty),
  'reviewing':  _StatusInfo(label: 'Reviewing',  color: Color(0xFF3B82F6), icon: Icons.search),
  'resolved':   _StatusInfo(label: 'Resolved',   color: Color(0xFF10B981), icon: Icons.check_circle),
  'dismissed':  _StatusInfo(label: 'Dismissed',  color: Color(0xFF6B7280), icon: Icons.cancel),
};

class _StatusInfo {
  final String label;
  final Color color;
  final IconData icon;
  const _StatusInfo({required this.label, required this.color, required this.icon});
}

class AdminCasesScreen extends StatefulWidget {
  const AdminCasesScreen({super.key});

  @override
  AdminCasesScreenState createState() => AdminCasesScreenState();
}

class AdminCasesScreenState extends State<AdminCasesScreen> {
  List<Map<String, dynamic>> _cases = [];
  bool _isLoading = true;
  String? _error;
  String _filterStatus = 'all';

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
      final api = Provider.of<ApiService>(context, listen: false);
      final cases = await api.getCases();
      if (!mounted) return;
      setState(() {
        _cases = cases;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  List<Map<String, dynamic>> get _filtered {
    if (_filterStatus == 'all') return _cases;
    return _cases.where((c) => (c['status'] ?? 'pending') == _filterStatus).toList();
  }

  Future<void> _updateStatus(int id, String newStatus) async {
    try {
      final api = Provider.of<ApiService>(context, listen: false);
      await api.updateCase(id, {'status': newStatus});
      if (!mounted) return;
      await _loadCases();
      if (!mounted) return;
      showTopSnack(
        context,
        message: 'Status updated to ${_statusMeta[newStatus]?.label ?? newStatus}',
        backgroundColor: _statusMeta[newStatus]?.color ?? _kCharcoal,
        icon: _statusMeta[newStatus]?.icon,
      );
    } catch (e) {
      if (!mounted) return;
      showTopSnack(
        context,
        message: 'Failed to update: $e',
        backgroundColor: _kPrimary,
        icon: Icons.error_outline,
      );
    }
  }

  Future<void> _deleteCase(Map<String, dynamic> caseData) async {
    final api = Provider.of<ApiService>(context, listen: false);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          Icon(Icons.warning_amber_rounded, color: _kPrimary),
          SizedBox(width: 8),
          Text('Delete Complaint'),
        ]),
        content: Text(
          'Delete "${caseData['title'] ?? 'this complaint'}"?\nThis action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: _kCharcoal)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: _kPrimary),
            child: Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;
    try {
      await api.deleteCase(caseData['id'] as int);
      if (!mounted) return;
      await _loadCases();
      if (!mounted) return;
      showTopSnack(
        context,
        message: 'Complaint deleted',
        backgroundColor: _kCharcoal,
        icon: Icons.delete_outline,
      );
    } catch (e) {
      if (!mounted) return;
      showTopSnack(
        context,
        message: 'Error: $e',
        backgroundColor: _kPrimary,
        icon: Icons.error_outline,
      );
    }
  }

  void _openDetail(Map<String, dynamic> caseData) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _DetailSheet(
        caseData: caseData,
        onStatusChanged: (newStatus) {
          Navigator.pop(context);
          _updateStatus(caseData['id'] as int, newStatus);
        },
        onDelete: () {
          Navigator.pop(context);
          _deleteCase(caseData);
        },
        onRefresh: _loadCases,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text('Complaints'),
        backgroundColor: _kPrimary,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _loadCases,
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Column(
            children: [
              _buildFilterBar(),
              Expanded(child: _buildBody()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilterBar() {
    final filters = [
      ('all', 'All'),
      ('pending', 'Pending'),
      ('reviewing', 'Reviewing'),
      ('resolved', 'Resolved'),
      ('dismissed', 'Dismissed'),
    ];

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: filters.map((f) {
            final key = f.$1;
            final label = f.$2;
            final isSelected = _filterStatus == key;
            final meta = _statusMeta[key];
            final color = meta?.color ?? _kPrimary;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                label: Text(label),
                selected: isSelected,
                onSelected: (_) => setState(() => _filterStatus = key),
                selectedColor: color.withValues(alpha: 0.15),
                checkmarkColor: color,
                labelStyle: TextStyle(
                  color: isSelected ? color : _kCharcoal,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
                side: BorderSide(
                  color: isSelected ? color : Colors.grey.shade300,
                ),
                backgroundColor: Colors.white,
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: _kPrimary));
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 64, color: _kPrimary),
              const SizedBox(height: 16),
              Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: _kCharcoal)),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _loadCases,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final items = _filtered;
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_rounded, size: 72, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text(
              _filterStatus == 'all' ? 'No complaints yet' : 'No $_filterStatus complaints',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 16),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadCases,
      color: _kPrimary,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        itemCount: items.length,
        itemBuilder: (_, i) => _CaseCard(
          caseData: items[i],
          onTap: () => _openDetail(items[i]),
          onDelete: () => _deleteCase(items[i]),
        ),
      ),
    );
  }
}

// ─── Case Card ───────────────────────────────────────────────────────────────

class _CaseCard extends StatelessWidget {
  final Map<String, dynamic> caseData;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _CaseCard({
    required this.caseData,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final status = (caseData['status'] ?? 'pending') as String;
    final meta = _statusMeta[status] ?? _statusMeta['pending']!;
    final title = (caseData['title'] ?? 'Untitled') as String;
    final description = (caseData['description'] ?? '') as String;
    final reporterName = caseData['reporter_name'] as String?;
    final createdAt = caseData['created_at'] as String?;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 1,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: _kCharcoal,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _StatusChip(meta: meta, status: status),
                ],
              ),
              if (description.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: _kCharcoal.withValues(alpha: 0.7)),
                ),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  if (reporterName != null) ...[
                    Icon(Icons.person_outline, size: 14, color: Colors.grey.shade500),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        reporterName,
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                  if (createdAt != null) ...[
                    Icon(Icons.access_time, size: 12, color: Colors.grey.shade400),
                    const SizedBox(width: 3),
                    Text(
                      _formatDate(createdAt),
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                    ),
                  ],
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 18, color: _kPrimary),
                    tooltip: 'Delete',
                    onPressed: onDelete,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(String raw) {
    try {
      final dt = DateTime.parse(raw).toLocal();
      final months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
      final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
      final m = dt.minute.toString().padLeft(2, '0');
      final ampm = dt.hour < 12 ? 'AM' : 'PM';
      return '${months[dt.month - 1]} ${dt.day}, ${dt.year}  $h:$m $ampm';
    } catch (_) {
      return raw;
    }
  }
}

// ─── Status Chip ─────────────────────────────────────────────────────────────

class _StatusChip extends StatelessWidget {
  final _StatusInfo meta;
  final String status;
  const _StatusChip({required this.meta, required this.status});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: meta.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: meta.color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(meta.icon, size: 12, color: meta.color),
          const SizedBox(width: 4),
          Text(
            meta.label,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: meta.color),
          ),
        ],
      ),
    );
  }
}

// ─── Detail Bottom Sheet ─────────────────────────────────────────────────────

class _DetailSheet extends StatefulWidget {
  final Map<String, dynamic> caseData;
  final ValueChanged<String> onStatusChanged;
  final VoidCallback onDelete;
  final VoidCallback onRefresh;

  const _DetailSheet({
    required this.caseData,
    required this.onStatusChanged,
    required this.onDelete,
    required this.onRefresh,
  });

  @override
  State<_DetailSheet> createState() => _DetailSheetState();
}

class _DetailSheetState extends State<_DetailSheet> {
  List<Map<String, dynamic>> _mediations = [];
  bool _mediationsLoading = true;
  bool _addingMediation = false;

  @override
  void initState() {
    super.initState();
    _loadMediations();
  }

  Future<void> _loadMediations() async {
    final caseId = widget.caseData['id'] as int?;
    if (caseId == null) { setState(() => _mediationsLoading = false); return; }
    try {
      final api = Provider.of<ApiService>(context, listen: false);
      final list = await api.getMediations(caseId);
      if (mounted) setState(() { _mediations = list; _mediationsLoading = false; });
    } catch (_) {
      if (mounted) setState(() => _mediationsLoading = false);
    }
  }

  Future<void> _showAddMediationDialog() async {
    final dateCtrl = TextEditingController();
    final timeCtrl = TextEditingController();
    final locationCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    String resolutionStatus = 'scheduled';
    DateTime? pickedDate;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(children: [
            Icon(Icons.event_note, color: _kPrimary),
            SizedBox(width: 8),
            Text('Schedule Mediation', style: TextStyle(fontSize: 16)),
          ]),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Date picker
                TextFormField(
                  controller: dateCtrl,
                  readOnly: true,
                  decoration: const InputDecoration(
                    labelText: 'Date *',
                    prefixIcon: Icon(Icons.calendar_today, size: 18),
                    isDense: true,
                  ),
                  onTap: () async {
                    final d = await showDatePicker(
                      context: ctx,
                      initialDate: DateTime.now().add(const Duration(days: 1)),
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (d != null) {
                      pickedDate = d;
                      dateCtrl.text = '${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';
                      setS(() {});
                    }
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: timeCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Time (e.g. 9:00 AM)',
                    prefixIcon: Icon(Icons.access_time, size: 18),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: locationCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Location',
                    prefixIcon: Icon(Icons.place_outlined, size: 18),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: resolutionStatus,
                  decoration: const InputDecoration(labelText: 'Status', isDense: true),
                  items: const [
                    DropdownMenuItem(value: 'scheduled', child: Text('Scheduled')),
                    DropdownMenuItem(value: 'ongoing',   child: Text('Ongoing')),
                    DropdownMenuItem(value: 'resolved',  child: Text('Resolved')),
                    DropdownMenuItem(value: 'failed',    child: Text('Failed')),
                  ],
                  onChanged: (v) => setS(() => resolutionStatus = v ?? 'scheduled'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: notesCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Notes (optional)',
                    isDense: true,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: pickedDate == null ? null : () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: _kPrimary, foregroundColor: Colors.white),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || pickedDate == null) return;

    setState(() => _addingMediation = true);
    try {
      final api = Provider.of<ApiService>(context, listen: false);
      await api.createMediation(widget.caseData['id'] as int, {
        'mediation_date': dateCtrl.text,
        if (timeCtrl.text.trim().isNotEmpty) 'mediation_time': timeCtrl.text.trim(),
        if (locationCtrl.text.trim().isNotEmpty) 'location': locationCtrl.text.trim(),
        if (notesCtrl.text.trim().isNotEmpty) 'summary_notes': notesCtrl.text.trim(),
        'resolution_status': resolutionStatus,
      });
      await _loadMediations();
      widget.onRefresh();
      if (mounted) {
        showTopSnack(context,
          message: 'Mediation session scheduled',
          backgroundColor: const Color(0xFF10B981),
          icon: Icons.check_circle_outline,
        );
      }
    } catch (e) {
      if (mounted) {
        showTopSnack(context,
          message: 'Failed: ${e.toString().replaceFirst("Exception: ", "")}',
          backgroundColor: _kPrimary,
          icon: Icons.error_outline,
        );
      }
    } finally {
      if (mounted) setState(() => _addingMediation = false);
    }
  }

  Future<void> _deleteMediationItem(int mediationId) async {
    try {
      final api = Provider.of<ApiService>(context, listen: false);
      await api.deleteMediation(mediationId);
      await _loadMediations();
      widget.onRefresh();
    } catch (e) {
      if (mounted) {
        showTopSnack(context, message: 'Delete failed: $e', backgroundColor: _kPrimary, icon: Icons.error_outline);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cd = widget.caseData;
    final status = (cd['status'] ?? 'pending') as String;
    final meta = _statusMeta[status] ?? _statusMeta['pending']!;
    final title = (cd['title'] ?? 'Untitled') as String;
    final description = (cd['description'] ?? '') as String;
    final reporterName = cd['reporter_name'] as String?;
    final reporterEmail = cd['reporter_email'] as String?;
    final createdAt = cd['created_at'] as String?;

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (_, controller) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
            ),
            Expanded(
              child: ListView(
                controller: controller,
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                children: [
                  // Header
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _kCharcoal))),
                      _StatusChip(meta: meta, status: status),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Reporter info
                  if (reporterName != null || reporterEmail != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: const Color(0xFFF8F9FA), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey.shade200)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Reporter', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey, letterSpacing: 0.8)),
                          const SizedBox(height: 6),
                          if (reporterName != null)
                            Row(children: [const Icon(Icons.person, size: 16, color: _kCharcoal), const SizedBox(width: 8), Text(reporterName, style: const TextStyle(color: _kCharcoal, fontWeight: FontWeight.w500))]),
                          if (reporterEmail != null) ...[
                            const SizedBox(height: 4),
                            Row(children: [const Icon(Icons.email_outlined, size: 16, color: _kCharcoal), const SizedBox(width: 8), Text(reporterEmail, style: TextStyle(color: _kCharcoal.withValues(alpha: 0.8)))]),
                          ],
                        ],
                      ),
                    ),

                  const SizedBox(height: 16),

                  // Description
                  const Text('Description', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey)),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: const Color(0xFFF8F9FA), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey.shade200)),
                    child: Text(description.isEmpty ? 'No description provided.' : description,
                        style: TextStyle(fontSize: 14, color: _kCharcoal.withValues(alpha: 0.9), height: 1.5)),
                  ),

                  if (createdAt != null) ...[
                    const SizedBox(height: 12),
                    Row(children: [
                      Icon(Icons.access_time, size: 14, color: Colors.grey.shade400),
                      const SizedBox(width: 6),
                      Text('Submitted ${_formatDate(createdAt)}', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                    ]),
                  ],

                  const SizedBox(height: 24),

                  // ── Mediation Section ──────────────────────────────────────
                  Row(
                    children: [
                      const Icon(Icons.gavel, size: 16, color: _kPrimary),
                      const SizedBox(width: 6),
                      const Text('Mediation Sessions', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey)),
                      const Spacer(),
                      if (_addingMediation)
                        const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: _kPrimary))
                      else
                        TextButton.icon(
                          onPressed: _showAddMediationDialog,
                          icon: const Icon(Icons.add, size: 16),
                          label: const Text('Add'),
                          style: TextButton.styleFrom(foregroundColor: _kPrimary, visualDensity: VisualDensity.compact),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_mediationsLoading)
                    const Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(color: _kPrimary, strokeWidth: 2)))
                  else if (_mediations.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(color: const Color(0xFFF8F9FA), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey.shade200)),
                      child: const Row(children: [
                        Icon(Icons.info_outline, size: 16, color: Colors.grey),
                        SizedBox(width: 8),
                        Text('No mediation sessions yet.', style: TextStyle(fontSize: 13, color: Colors.grey)),
                      ]),
                    )
                  else
                    ...(_mediations.map((m) => _MediationTile(mediation: m, onDelete: () => _deleteMediationItem(m['id'] as int)))),

                  const SizedBox(height: 24),

                  // Status update
                  const Text('Update Status', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey)),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8, runSpacing: 8,
                    children: _statusMeta.entries.map((e) {
                      final isActive = e.key == status;
                      final m = e.value;
                      return GestureDetector(
                        onTap: isActive ? null : () => widget.onStatusChanged(e.key),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: isActive ? m.color : m.color.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: isActive ? m.color : m.color.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(m.icon, size: 14, color: isActive ? Colors.white : m.color),
                              const SizedBox(width: 6),
                              Text(m.label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: isActive ? Colors.white : m.color)),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),

                  const SizedBox(height: 24),

                  // Delete button
                  OutlinedButton.icon(
                    onPressed: widget.onDelete,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Delete Complaint'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _kPrimary,
                      side: const BorderSide(color: _kPrimary),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(String raw) {
    try {
      final dt = DateTime.parse(raw).toLocal();
      final months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
      final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
      final m = dt.minute.toString().padLeft(2, '0');
      final ampm = dt.hour < 12 ? 'AM' : 'PM';
      return '${months[dt.month - 1]} ${dt.day}, ${dt.year}  $h:$m $ampm';
    } catch (_) {
      return raw;
    }
  }
}

// ─── Mediation Tile ───────────────────────────────────────────────────────────

class _MediationTile extends StatelessWidget {
  final Map<String, dynamic> mediation;
  final VoidCallback onDelete;
  const _MediationTile({required this.mediation, required this.onDelete});

  static const _statusColors = <String, Color>{
    'scheduled': Color(0xFF3B82F6),
    'ongoing':   Color(0xFFF59E0B),
    'resolved':  Color(0xFF10B981),
    'failed':    Color(0xFF6B7280),
  };

  @override
  Widget build(BuildContext context) {
    final date      = mediation['mediation_date'] as String?;
    final time      = mediation['mediation_time'] as String?;
    final location  = mediation['location'] as String?;
    final notes     = mediation['summary_notes'] as String?;
    final resStatus = (mediation['resolution_status'] ?? 'scheduled') as String;
    final color = _statusColors[resStatus] ?? _statusColors['scheduled']!;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.4)),
        color: color.withValues(alpha: 0.04),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 4, height: 60,
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                        child: Text(resStatus.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color)),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 16, color: _kPrimary),
                        onPressed: onDelete,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        visualDensity: VisualDensity.compact,
                        tooltip: 'Remove',
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  if (date != null)
                    Row(children: [
                      const Icon(Icons.calendar_today, size: 13, color: _kCharcoal),
                      const SizedBox(width: 6),
                      Text(date + (time != null ? '  $time' : ''),
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _kCharcoal)),
                    ]),
                  if (location != null) ...[
                    const SizedBox(height: 4),
                    Row(children: [
                      const Icon(Icons.place_outlined, size: 13, color: Colors.grey),
                      const SizedBox(width: 6),
                      Text(location, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                    ]),
                  ],
                  if (notes != null && notes.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(notes,
                        style: TextStyle(fontSize: 12, color: _kCharcoal.withValues(alpha: 0.7)),
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
