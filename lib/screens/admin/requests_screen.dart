import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:barangay_legal_aid/services/api_service.dart';
import 'package:barangay_legal_aid/utils/top_snack.dart';

const _kPrimary = Color(0xFF99272D);
const _kCharcoal = Color(0xFF36454F);

class AdminRequestsScreen extends StatefulWidget {
  const AdminRequestsScreen({super.key});

  @override
  AdminRequestsScreenState createState() => AdminRequestsScreenState();
}

class AdminRequestsScreenState extends State<AdminRequestsScreen> {
  List<Map<String, dynamic>> _requests = [];
  bool _isLoading = true;
  String? _error;
  String _statusFilter = 'all';

  @override
  void initState() {
    super.initState();
    _loadRequests();
  }

  Future<void> _loadRequests() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final api = Provider.of<ApiService>(context, listen: false);
      final requests = await api.getRequests();
      if (!mounted) return;
      setState(() {
        _requests = requests;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceAll('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  Future<void> _updateStatus(int id, String status) async {
    try {
      final api = Provider.of<ApiService>(context, listen: false);
      await api.updateRequest(id, {'status': status});
      if (!mounted) return;
      await _loadRequests();
      if (!mounted) return;
      final label = status == 'approved' ? 'Approved' : 'Rejected';
      final color = status == 'approved' ? const Color(0xFF43A047) : _kPrimary;
      final icon = status == 'approved' ? Icons.check_circle : Icons.cancel;
      showTopSnack(context, message: 'Request $label', backgroundColor: color, icon: icon);
    } catch (e) {
      if (!mounted) return;
      showTopSnack(context,
          message: 'Error: ${e.toString().replaceAll('Exception: ', '')}',
          backgroundColor: _kPrimary,
          icon: Icons.error_outline);
    }
  }

  Future<void> _deleteRequest(Map<String, dynamic> req) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          Icon(Icons.warning_amber_rounded, color: _kPrimary),
          SizedBox(width: 8),
          Text('Delete Request'),
        ]),
        content: Text(
            'Delete request #${req['id']} for "${req['document_type'] ?? ''}"?\nThis cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel', style: TextStyle(color: _kCharcoal))),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: _kPrimary),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;
    try {
      final api = Provider.of<ApiService>(context, listen: false);
      await api.deleteRequest(req['id'] as int);
      if (!mounted) return;
      await _loadRequests();
      if (!mounted) return;
      showTopSnack(context,
          message: 'Request deleted',
          backgroundColor: _kCharcoal,
          icon: Icons.delete_outline);
    } catch (e) {
      if (!mounted) return;
      showTopSnack(context,
          message: 'Error: $e',
          backgroundColor: _kPrimary,
          icon: Icons.error_outline);
    }
  }

  void _openDetail(Map<String, dynamic> req) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _RequestDetailSheet(
        request: req,
        onApprove: () {
          Navigator.pop(context);
          _updateStatus(req['id'] as int, 'approved');
        },
        onReject: () {
          Navigator.pop(context);
          _updateStatus(req['id'] as int, 'rejected');
        },
        onDelete: () {
          Navigator.pop(context);
          _deleteRequest(req);
        },
      ),
    );
  }

  List<Map<String, dynamic>> get _filtered {
    if (_statusFilter == 'all') return _requests;
    return _requests.where((r) => r['status'] == _statusFilter).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text('Document Requests'),
        backgroundColor: _kPrimary,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _loadRequests,
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
      ('approved', 'Approved'),
      ('rejected', 'Rejected'),
    ];
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: filters.map((f) {
            final isSelected = _statusFilter == f.$1;
            final color = _statusColor(f.$1);
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                label: Text(f.$2),
                selected: isSelected,
                onSelected: (_) => setState(() => _statusFilter = f.$1),
                selectedColor: color.withValues(alpha: 0.15),
                checkmarkColor: color,
                labelStyle: TextStyle(
                  color: isSelected ? color : _kCharcoal,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
                side: BorderSide(color: isSelected ? color : Colors.grey.shade300),
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
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _loadRequests,
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
              _statusFilter == 'all' ? 'No requests yet' : 'No $_statusFilter requests',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 16),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadRequests,
      color: _kPrimary,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        itemCount: items.length,
        itemBuilder: (_, i) => _RequestCard(
          request: items[i],
          onTap: () => _openDetail(items[i]),
          onApprove: () => _updateStatus(items[i]['id'] as int, 'approved'),
          onReject: () => _updateStatus(items[i]['id'] as int, 'rejected'),
          onDelete: () => _deleteRequest(items[i]),
        ),
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'approved':
        return const Color(0xFF43A047);
      case 'rejected':
        return _kPrimary;
      case 'pending':
        return const Color(0xFFF59E0B);
      default:
        return Colors.grey;
    }
  }
}

// ─── Request Card ─────────────────────────────────────────────────────────────

class _RequestCard extends StatelessWidget {
  final Map<String, dynamic> request;
  final VoidCallback onTap;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  final VoidCallback onDelete;

  const _RequestCard({
    required this.request,
    required this.onTap,
    required this.onApprove,
    required this.onReject,
    required this.onDelete,
  });

  Color get _statusColor {
    switch (request['status']) {
      case 'approved': return const Color(0xFF43A047);
      case 'rejected': return _kPrimary;
      case 'pending':  return const Color(0xFFF59E0B);
      default:         return Colors.grey;
    }
  }

  String get _statusLabel => (request['status'] as String? ?? 'pending').toUpperCase();

  String _formatDate(String? raw) {
    if (raw == null) return '';
    try {
      final dt = DateTime.parse(raw).toLocal();
      final m = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'][dt.month - 1];
      final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
      final min = dt.minute.toString().padLeft(2, '0');
      return '$m ${dt.day}, ${dt.year}  $h:$min ${dt.hour < 12 ? 'AM' : 'PM'}';
    } catch (_) { return raw; }
  }

  @override
  Widget build(BuildContext context) {
    final status = request['status'] as String? ?? 'pending';
    final isPending = status == 'pending';
    final requesterName = request['requester_name'] as String?;

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
              // ── Header row ────────────────────────────────────────────────
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: _kPrimary.withValues(alpha: 0.1),
                    child: const Icon(Icons.description, color: _kPrimary, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          request['document_type'] as String? ?? 'Document Request',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: _kCharcoal,
                          ),
                        ),
                        if (request['purpose'] != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              'Purpose: ${request['purpose']}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 13, color: _kCharcoal.withValues(alpha: 0.7)),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Status badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: _statusColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: _statusColor.withValues(alpha: 0.4)),
                    ),
                    child: Text(
                      _statusLabel,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: _statusColor,
                      ),
                    ),
                  ),
                ],
              ),

              // ── Meta row ──────────────────────────────────────────────────
              const SizedBox(height: 10),
              Row(
                children: [
                  if (requesterName != null) ...[
                    Icon(Icons.person_outline, size: 14, color: Colors.grey.shade500),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        requesterName,
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ] else
                    const Spacer(),
                  if (request['created_at'] != null) ...[
                    Icon(Icons.access_time, size: 12, color: Colors.grey.shade400),
                    const SizedBox(width: 3),
                    Text(
                      _formatDate(request['created_at'] as String?),
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                    ),
                  ],
                ],
              ),

              // ── Action buttons (pending only) ─────────────────────────────
              if (isPending) ...[
                const SizedBox(height: 14),
                const Divider(height: 1),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: onReject,
                        icon: const Icon(Icons.close, size: 16),
                        label: const Text('Reject'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _kPrimary,
                          side: const BorderSide(color: _kPrimary),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: onApprove,
                        icon: const Icon(Icons.check, size: 16),
                        label: const Text('Approve'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF43A047),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.grey),
                      tooltip: 'Delete',
                      onPressed: onDelete,
                      style: IconButton.styleFrom(
                        padding: const EdgeInsets.all(8),
                      ),
                    ),
                  ],
                ),
              ] else ...[
                // Non-pending: only show delete in corner
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerRight,
                  child: IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.grey, size: 18),
                    tooltip: 'Delete',
                    onPressed: onDelete,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Detail Bottom Sheet ──────────────────────────────────────────────────────

class _RequestDetailSheet extends StatelessWidget {
  final Map<String, dynamic> request;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  final VoidCallback onDelete;

  const _RequestDetailSheet({
    required this.request,
    required this.onApprove,
    required this.onReject,
    required this.onDelete,
  });

  String _formatDate(String? raw) {
    if (raw == null) return 'N/A';
    try {
      final dt = DateTime.parse(raw).toLocal();
      final m = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'][dt.month - 1];
      final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
      final min = dt.minute.toString().padLeft(2, '0');
      return '$m ${dt.day}, ${dt.year}  $h:$min ${dt.hour < 12 ? 'AM' : 'PM'}';
    } catch (_) { return raw; }
  }

  Color get _statusColor {
    switch (request['status']) {
      case 'approved': return const Color(0xFF43A047);
      case 'rejected': return _kPrimary;
      case 'pending':  return const Color(0xFFF59E0B);
      default:         return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = request['status'] as String? ?? 'pending';
    final isPending = status == 'pending';
    final requesterName = request['requester_name'] as String?;
    final requesterEmail = request['requester_email'] as String?;

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      builder: (_, controller) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Expanded(
              child: ListView(
                controller: controller,
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                children: [
                  // Title + status
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          request['document_type'] as String? ?? 'Document Request',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: _kCharcoal,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: _statusColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: _statusColor.withValues(alpha: 0.4)),
                        ),
                        child: Text(
                          status.toUpperCase(),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: _statusColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Requester info
                  if (requesterName != null || requesterEmail != null)
                    _infoBox('Requester', [
                      if (requesterName != null)
                        _infoRow(Icons.person, requesterName),
                      if (requesterEmail != null)
                        _infoRow(Icons.email_outlined, requesterEmail),
                    ]),

                  const SizedBox(height: 12),

                  // Purpose
                  const Text('Purpose',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey)),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8F9FA),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Text(
                      request['purpose'] as String? ?? 'No purpose provided.',
                      style: TextStyle(fontSize: 14, color: _kCharcoal.withValues(alpha: 0.9), height: 1.5),
                    ),
                  ),

                  const SizedBox(height: 12),
                  Row(children: [
                    Icon(Icons.access_time, size: 14, color: Colors.grey.shade400),
                    const SizedBox(width: 6),
                    Text(
                      'Submitted ${_formatDate(request['created_at'] as String?)}',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                    ),
                  ]),

                  if (isPending) ...[
                    const SizedBox(height: 28),
                    const Text('Actions',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey)),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: onReject,
                            icon: const Icon(Icons.close, size: 18),
                            label: const Text('Reject'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: _kPrimary,
                              side: const BorderSide(color: _kPrimary),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: onApprove,
                            icon: const Icon(Icons.check, size: 18),
                            label: const Text('Approve'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF43A047),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              elevation: 0,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],

                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Delete Request'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.grey,
                      side: const BorderSide(color: Colors.grey),
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

  Widget _infoBox(String label, List<Widget> rows) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FA),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(),
              style: const TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey, letterSpacing: 0.8)),
          const SizedBox(height: 8),
          ...rows,
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(children: [
        Icon(icon, size: 16, color: _kCharcoal),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: const TextStyle(color: _kCharcoal, fontWeight: FontWeight.w500))),
      ]),
    );
  }
}
