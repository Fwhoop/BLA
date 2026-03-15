import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:barangay_legal_aid/services/api_service.dart';

const _kPrimary  = Color(0xFF99272D);
const _kCharcoal = Color(0xFF36454F);

const _statusMeta = <String, _StatusInfo>{
  'pending':   _StatusInfo(label: 'Pending',   color: Color(0xFFF59E0B), icon: Icons.hourglass_empty),
  'reviewing': _StatusInfo(label: 'Reviewing', color: Color(0xFF3B82F6), icon: Icons.search),
  'resolved':  _StatusInfo(label: 'Resolved',  color: Color(0xFF10B981), icon: Icons.check_circle),
  'dismissed': _StatusInfo(label: 'Dismissed', color: Color(0xFF6B7280), icon: Icons.cancel),
};

class _StatusInfo {
  final String label;
  final Color color;
  final IconData icon;
  const _StatusInfo({required this.label, required this.color, required this.icon});
}

class MyCasesScreen extends StatefulWidget {
  const MyCasesScreen({super.key});

  @override
  State<MyCasesScreen> createState() => _MyCasesScreenState();
}

class _MyCasesScreenState extends State<MyCasesScreen> {
  List<Map<String, dynamic>> _cases = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _isLoading = true; _error = null; });
    try {
      final api = Provider.of<ApiService>(context, listen: false);
      final cases = await api.getCases();
      if (mounted) setState(() { _cases = cases; _isLoading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _isLoading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text('My Complaints'),
        backgroundColor: _kPrimary,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) return const Center(child: CircularProgressIndicator(color: _kPrimary));
    if (_error != null) return Center(child: Text(_error!, style: const TextStyle(color: _kPrimary)));
    if (_cases.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.inbox_rounded, size: 72, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text('No complaints filed yet', style: TextStyle(color: Colors.grey.shade500, fontSize: 16)),
        ]),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      color: _kPrimary,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        itemCount: _cases.length,
        itemBuilder: (_, i) => _CaseTile(
          caseData: _cases[i],
          onTap: () => _openDetail(_cases[i]),
        ),
      ),
    );
  }

  void _openDetail(Map<String, dynamic> caseData) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _UserCaseDetailSheet(caseData: caseData),
    );
  }
}

// ─── Case Tile ────────────────────────────────────────────────────────────────

class _CaseTile extends StatelessWidget {
  final Map<String, dynamic> caseData;
  final VoidCallback onTap;
  const _CaseTile({required this.caseData, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final status = (caseData['status'] ?? 'pending') as String;
    final meta   = _statusMeta[status] ?? _statusMeta['pending']!;
    final title  = (caseData['title'] ?? 'Untitled') as String;
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
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: meta.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(meta.icon, color: meta.color, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _kCharcoal)),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: meta.color.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(meta.label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: meta.color)),
                        ),
                        if (createdAt != null) ...[
                          const SizedBox(width: 8),
                          Text(_fmt(createdAt), style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }

  String _fmt(String raw) {
    try {
      final dt = DateTime.parse(raw).toLocal();
      final months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
      return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
    } catch (_) { return raw; }
  }
}

// ─── User Detail Sheet ────────────────────────────────────────────────────────

class _UserCaseDetailSheet extends StatefulWidget {
  final Map<String, dynamic> caseData;
  const _UserCaseDetailSheet({required this.caseData});

  @override
  State<_UserCaseDetailSheet> createState() => _UserCaseDetailSheetState();
}

class _UserCaseDetailSheetState extends State<_UserCaseDetailSheet> {
  List<Map<String, dynamic>> _mediations = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadMediations();
  }

  Future<void> _loadMediations() async {
    final caseId = widget.caseData['id'] as int?;
    if (caseId == null) { setState(() => _loading = false); return; }
    try {
      final api = Provider.of<ApiService>(context, listen: false);
      final list = await api.getMediations(caseId);
      if (mounted) setState(() { _mediations = list; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cd = widget.caseData;
    final status = (cd['status'] ?? 'pending') as String;
    final meta   = _statusMeta[status] ?? _statusMeta['pending']!;
    final title  = (cd['title'] ?? 'Untitled') as String;
    final description = (cd['description'] ?? '') as String;
    final createdAt = cd['created_at'] as String?;

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (_, ctrl) => Container(
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
                controller: ctrl,
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _kCharcoal))),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(color: meta.color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20), border: Border.all(color: meta.color.withValues(alpha: 0.4))),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(meta.icon, size: 13, color: meta.color),
                          const SizedBox(width: 4),
                          Text(meta.label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: meta.color)),
                        ]),
                      ),
                    ],
                  ),
                  if (createdAt != null) ...[
                    const SizedBox(height: 8),
                    Row(children: [
                      Icon(Icons.access_time, size: 13, color: Colors.grey.shade400),
                      const SizedBox(width: 6),
                      Text('Filed ${_fmt(createdAt)}', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                    ]),
                  ],
                  const SizedBox(height: 16),
                  const Text('Description', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey)),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: const Color(0xFFF8F9FA), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey.shade200)),
                    child: Text(description.isEmpty ? 'No description.' : description,
                        style: TextStyle(fontSize: 14, color: _kCharcoal.withValues(alpha: 0.9), height: 1.5)),
                  ),
                  const SizedBox(height: 24),

                  // Mediation section
                  const Row(children: [
                    Icon(Icons.gavel, size: 16, color: _kPrimary),
                    SizedBox(width: 6),
                    Text('Mediation Schedule', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey)),
                  ]),
                  const SizedBox(height: 10),
                  if (_loading)
                    const Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(color: _kPrimary, strokeWidth: 2)))
                  else if (_mediations.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(color: const Color(0xFFF8F9FA), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey.shade200)),
                      child: const Row(children: [
                        Icon(Icons.info_outline, size: 16, color: Colors.grey),
                        SizedBox(width: 8),
                        Text('No mediation sessions scheduled yet.', style: TextStyle(fontSize: 13, color: Colors.grey)),
                      ]),
                    )
                  else
                    ...(_mediations.map((m) => _UserMediationCard(mediation: m))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _fmt(String raw) {
    try {
      final dt = DateTime.parse(raw).toLocal();
      final months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
      return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
    } catch (_) { return raw; }
  }
}

// ─── User Mediation Card ──────────────────────────────────────────────────────

class _UserMediationCard extends StatelessWidget {
  final Map<String, dynamic> mediation;
  const _UserMediationCard({required this.mediation});

  static const _statusColors = <String, Color>{
    'scheduled': Color(0xFF3B82F6),
    'ongoing':   Color(0xFFF59E0B),
    'resolved':  Color(0xFF10B981),
    'failed':    Color(0xFF6B7280),
  };
  static const _statusLabels = <String, String>{
    'scheduled': 'Scheduled',
    'ongoing':   'Ongoing',
    'resolved':  'Resolved',
    'failed':    'Failed / No Agreement',
  };

  @override
  Widget build(BuildContext context) {
    final date      = mediation['mediation_date'] as String?;
    final time      = mediation['mediation_time'] as String?;
    final location  = mediation['location'] as String?;
    final notes     = mediation['summary_notes'] as String?;
    final resStatus = (mediation['resolution_status'] ?? 'scheduled') as String;
    final color = _statusColors[resStatus] ?? _statusColors['scheduled']!;
    final label = _statusLabels[resStatus] ?? resStatus;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
        color: Colors.white,
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.08),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(children: [
              Icon(Icons.event_available, size: 16, color: color),
              const SizedBox(width: 8),
              Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color)),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (date != null)
                  _row(Icons.calendar_today, date + (time != null ? '  $time' : ''), bold: true),
                if (location != null) _row(Icons.place_outlined, location),
                if (notes != null && notes.isNotEmpty) _row(Icons.notes, notes),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(IconData icon, String text, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: Colors.grey.shade500),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(fontSize: 13, color: _kCharcoal, fontWeight: bold ? FontWeight.w600 : FontWeight.normal))),
        ],
      ),
    );
  }
}
