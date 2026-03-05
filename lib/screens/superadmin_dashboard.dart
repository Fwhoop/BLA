import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:barangay_legal_aid/services/auth_service.dart';
import 'package:barangay_legal_aid/services/api_service.dart';
import 'package:barangay_legal_aid/screens/superadmin/barangays_screen.dart';
import 'package:barangay_legal_aid/screens/superadmin/admins_screen.dart';
import 'package:barangay_legal_aid/screens/superadmin/system_screen.dart';
import 'package:barangay_legal_aid/screens/superadmin/analytics_screen.dart';
import 'package:barangay_legal_aid/screens/notification_screen.dart';

const _kPrimary  = Color(0xFF99272D);
const _kCharcoal = Color(0xFF36454F);
const _kBg       = Color(0xFFF0F2F5);

class SuperAdminDashboard extends StatefulWidget {
  const SuperAdminDashboard({super.key});

  @override
  State<SuperAdminDashboard> createState() => _SuperAdminDashboardState();
}

class _SuperAdminDashboardState extends State<SuperAdminDashboard>
    with SingleTickerProviderStateMixin {

  late final AnimationController _chartCtrl;
  late final Animation<double>    _chartAnim;

  // ── raw data ────────────────────────────────────────────────────────────────
  List<Map<String, dynamic>> _cases     = [];
  List<Map<String, dynamic>> _requests  = [];
  List<Map<String, dynamic>> _users     = [];
  List<Map<String, dynamic>> _barangays = [];

  bool  _isLoading  = true;
  int   _unreadCount = 0;
  Timer? _pollTimer;

  // ── derived ─────────────────────────────────────────────────────────────────
  int get _totalBarangays  => _barangays.length;
  int get _totalAdmins     => _users.where((u) => u['role'] == 'admin').length;
  int get _totalResidents  => _users.where((u) => u['role'] == 'user').length;
  int get _totalCases      => _cases.length;
  int get _pendingCases    => _cases.where((c) => (c['status'] ?? '') == 'pending').length;
  int get _reviewingCases  => _cases.where((c) => (c['status'] ?? '') == 'reviewing').length;
  int get _resolvedCases   => _cases.where((c) => (c['status'] ?? '') == 'resolved').length;
  int get _dismissedCases  => _cases.where((c) => (c['status'] ?? '') == 'dismissed').length;
  int get _totalRequests   => _requests.length;
  int get _pendingRequests => _requests.where((r) => (r['status'] ?? '') == 'pending').length;
  int get _approvedRequests => _requests.where((r) => (r['status'] ?? '') == 'approved').length;
  int get _rejectedRequests => _requests.where((r) => (r['status'] ?? '') == 'rejected').length;
  int get _totalPending    => _pendingCases + _pendingRequests;

  @override
  void initState() {
    super.initState();
    _chartCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _chartAnim = CurvedAnimation(parent: _chartCtrl, curve: Curves.easeOutCubic);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
      _pollUnreadCount();
    });
    _pollTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _pollUnreadCount(),
    );
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _chartCtrl.dispose();
    super.dispose();
  }

  Future<void> _pollUnreadCount() async {
    try {
      final api = Provider.of<ApiService>(context, listen: false);
      final c = await api.getUnreadNotificationCount();
      if (mounted) setState(() => _unreadCount = c);
    } catch (_) {}
  }

  Future<void> _loadData() async {
    setState(() { _isLoading = true; });
    _chartCtrl.reset();
    try {
      final api = Provider.of<ApiService>(context, listen: false);
      final results = await Future.wait([
        api.getBarangays().catchError((_) => <Map<String, dynamic>>[]),
        api.getUsers().catchError((_) => <Map<String, dynamic>>[]),
        api.getRequests().catchError((_) => <Map<String, dynamic>>[]),
        api.getCases().catchError((_) => <Map<String, dynamic>>[]),
      ]);
      if (!mounted) return;
      setState(() {
        _barangays = List<Map<String, dynamic>>.from(results[0] as List);
        _users     = List<Map<String, dynamic>>.from(results[1] as List);
        _requests  = List<Map<String, dynamic>>.from(results[2] as List);
        _cases     = List<Map<String, dynamic>>.from(results[3] as List);
        _isLoading = false;
      });
      _chartCtrl.forward();
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good Morning';
    if (h < 17) return 'Good Afternoon';
    return 'Good Evening';
  }

  // ── build ───────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('SuperAdmin Dashboard'),
        backgroundColor: _kPrimary,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          NotificationBell(
            count: _unreadCount,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const NotificationScreen(userRole: 'superadmin'),
              ),
            ).then((_) => _pollUnreadCount()),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _loadData,
          ),
          TextButton(
            onPressed: () async {
              final nav = Navigator.of(context);
              await AuthService().logout();
              nav.pushNamedAndRemoveUntil('/login', (_) => false);
            },
            child: const Text(
              'LOGOUT',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: _kPrimary))
          : RefreshIndicator(
              color: _kPrimary,
              onRefresh: _loadData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(20),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1400),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildBanner(),
                        const SizedBox(height: 20),
                        _buildKpiRow(),
                        const SizedBox(height: 20),
                        _buildAnalyticsSection(),
                        const SizedBox(height: 20),
                        _buildQuickAccessSection(),
                        const SizedBox(height: 20),
                      ],
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  // ── Banner ──────────────────────────────────────────────────────────────────
  Widget _buildBanner() {
    final date = DateFormat('EEEE, MMMM d, y').format(DateTime.now());
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [_kPrimary, Color(0xFF6B1A1E)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: _kPrimary.withValues(alpha: 0.3),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_greeting()}, Super Admin!',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  date,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.8),
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  '$_totalBarangays barangays  ·  '
                  '$_totalAdmins admins  ·  '
                  '$_totalPending pending actions',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.admin_panel_settings_rounded,
              color: Colors.white,
              size: 36,
            ),
          ),
        ],
      ),
    );
  }

  // ── KPI Strip ───────────────────────────────────────────────────────────────
  Widget _buildKpiRow() {
    final kpis = [
      _KpiData('Barangays',    _totalBarangays,  Icons.location_city_rounded,     const Color(0xFF1E88E5)),
      _KpiData('Admins',       _totalAdmins,     Icons.manage_accounts_rounded,   _kCharcoal),
      _KpiData('Residents',    _totalResidents,  Icons.people_alt_rounded,        const Color(0xFF8E24AA)),
      _KpiData('Pending',      _totalPending,    Icons.pending_actions_rounded,   const Color(0xFFF59E0B)),
    ];
    return LayoutBuilder(
      builder: (_, c) {
        if (c.maxWidth > 600) {
          return Row(
            children: kpis.asMap().entries.map((e) => Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: e.key < kpis.length - 1 ? 12 : 0),
                child: _kpiCard(e.value),
              ),
            )).toList(),
          );
        }
        return Column(
          children: kpis.map((k) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _kpiCard(k),
          )).toList(),
        );
      },
    );
  }

  Widget _kpiCard(_KpiData k) {
    return AnimatedBuilder(
      animation: _chartAnim,
      builder: (_, __) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: k.color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(k.icon, color: k.color, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    (k.value * _chartAnim.value).round().toString(),
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: k.color,
                    ),
                  ),
                  Text(
                    k.label,
                    style: TextStyle(
                      fontSize: 12,
                      color: _kCharcoal.withValues(alpha: 0.65),
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

  // ── Analytics ───────────────────────────────────────────────────────────────
  Widget _buildAnalyticsSection() {
    return LayoutBuilder(
      builder: (_, c) {
        final isWide = c.maxWidth > 700;
        return isWide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _casesDonutCard()),
                  const SizedBox(width: 16),
                  Expanded(child: _requestsBarsCard()),
                ],
              )
            : Column(
                children: [
                  _casesDonutCard(),
                  const SizedBox(height: 16),
                  _requestsBarsCard(),
                ],
              );
      },
    );
  }

  Widget _casesDonutCard() {
    final segs = [
      _DonutSeg('Pending',   _pendingCases.toDouble(),   const Color(0xFFF59E0B)),
      _DonutSeg('Reviewing', _reviewingCases.toDouble(), const Color(0xFF3B82F6)),
      _DonutSeg('Resolved',  _resolvedCases.toDouble(),  const Color(0xFF10B981)),
      _DonutSeg('Dismissed', _dismissedCases.toDouble(), const Color(0xFF9CA3AF)),
    ].where((s) => s.value > 0).toList();

    return _ChartCard(
      title: 'Complaints by Status',
      badge: '$_totalCases total',
      child: _totalCases == 0
          ? _emptyState('No complaints yet')
          : Column(
              children: [
                AnimatedBuilder(
                  animation: _chartAnim,
                  builder: (_, __) => SizedBox(
                    width: 170, height: 170,
                    child: CustomPaint(
                      painter: _DonutPainter(segs, _chartAnim.value),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              (_totalCases * _chartAnim.value).round().toString(),
                              style: const TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.bold,
                                color: _kCharcoal,
                              ),
                            ),
                            const Text(
                              'Total',
                              style: TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 14, runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    if (_pendingCases   > 0) _legend('Pending',   _pendingCases,   const Color(0xFFF59E0B)),
                    if (_reviewingCases > 0) _legend('Reviewing', _reviewingCases, const Color(0xFF3B82F6)),
                    if (_resolvedCases  > 0) _legend('Resolved',  _resolvedCases,  const Color(0xFF10B981)),
                    if (_dismissedCases > 0) _legend('Dismissed', _dismissedCases, const Color(0xFF9CA3AF)),
                  ],
                ),
              ],
            ),
    );
  }

  Widget _requestsBarsCard() {
    final bars = [
      _Bar('Pending',  _pendingRequests,  const Color(0xFFF59E0B)),
      _Bar('Approved', _approvedRequests, const Color(0xFF10B981)),
      _Bar('Rejected', _rejectedRequests, _kPrimary),
    ];
    final maxVal = bars.fold(1, (m, b) => b.value > m ? b.value : m);

    return _ChartCard(
      title: 'Document Requests',
      badge: '$_totalRequests total',
      child: _totalRequests == 0
          ? _emptyState('No requests yet')
          : Column(
              children: [
                ...bars.map((b) => Padding(
                  padding: const EdgeInsets.only(bottom: 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(b.label, style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600, color: _kCharcoal,
                          )),
                          AnimatedBuilder(
                            animation: _chartAnim,
                            builder: (_, __) => Text(
                              (b.value * _chartAnim.value).round().toString(),
                              style: TextStyle(
                                fontSize: 13, fontWeight: FontWeight.bold, color: b.color,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: AnimatedBuilder(
                          animation: _chartAnim,
                          builder: (_, __) => LinearProgressIndicator(
                            value: maxVal == 0 ? 0 : (b.value / maxVal) * _chartAnim.value,
                            minHeight: 12,
                            backgroundColor: b.color.withValues(alpha: 0.1),
                            valueColor: AlwaysStoppedAnimation(b.color),
                          ),
                        ),
                      ),
                    ],
                  ),
                )),
                const SizedBox(height: 4),
                AnimatedBuilder(
                  animation: _chartAnim,
                  builder: (_, __) {
                    final segs = bars.where((b) => b.value > 0)
                        .map((b) => _DonutSeg(b.label, b.value.toDouble(), b.color))
                        .toList();
                    return SizedBox(
                      width: 100, height: 100,
                      child: CustomPaint(
                        painter: _DonutPainter(segs, _chartAnim.value),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                (_totalRequests * _chartAnim.value).round().toString(),
                                style: const TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.bold, color: _kCharcoal,
                                ),
                              ),
                              const Text(
                                'Reqs',
                                style: TextStyle(fontSize: 10, color: Colors.grey),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
    );
  }

  Widget _legend(String label, int value, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10, height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text('$label ($value)',
            style: const TextStyle(fontSize: 12, color: _kCharcoal)),
      ],
    );
  }

  Widget _emptyState(String msg) {
    return SizedBox(
      height: 130,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bar_chart_rounded, size: 40, color: Colors.grey.shade300),
            const SizedBox(height: 8),
            Text(msg, style: TextStyle(color: Colors.grey.shade400, fontSize: 13)),
          ],
        ),
      ),
    );
  }

  // ── Quick Access ─────────────────────────────────────────────────────────────
  Widget _buildQuickAccessSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Quick Access',
          style: TextStyle(
            fontSize: 15, fontWeight: FontWeight.bold, color: _kCharcoal,
          ),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (_, c) {
            final crossCount = c.maxWidth > 900 ? 5 : c.maxWidth > 600 ? 3 : 2;
            final items = [
              _Nav('Barangays',  'Register & manage',        Icons.location_city_rounded,     _kPrimary,                 BarangaysScreen()),
              _Nav('Admins',     'Manage admin accounts',    Icons.manage_accounts_rounded,   _kCharcoal,                AdminsScreen()),
              _Nav('All Users',  'View all residents',       Icons.people_alt_rounded,        const Color(0xFF8E24AA),   AnalyticsScreen()),
              _Nav('Analytics',  'System-wide statistics',   Icons.bar_chart_rounded,         const Color(0xFF1E88E5),   AnalyticsScreen()),
              _Nav('System',     'System configuration',     Icons.settings_rounded,          const Color(0xFFF59E0B),   SystemScreen()),
            ];
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossCount,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1.5,
              ),
              itemCount: items.length,
              itemBuilder: (_, i) {
                final item = items[i];
                return Card(
                  elevation: 1,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  child: InkWell(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => item.screen),
                    ),
                    borderRadius: BorderRadius.circular(14),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: item.color.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(item.icon, color: item.color, size: 20),
                          ),
                          const Spacer(),
                          Text(
                            item.title,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: _kCharcoal,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            item.subtitle,
                            style: TextStyle(
                              fontSize: 11,
                              color: _kCharcoal.withValues(alpha: 0.55),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared chart card wrapper
// ─────────────────────────────────────────────────────────────────────────────

class _ChartCard extends StatelessWidget {
  final String title;
  final String badge;
  final Widget child;
  const _ChartCard({required this.title, required this.badge, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 15, color: _kCharcoal,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _kCharcoal.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  badge,
                  style: TextStyle(fontSize: 11, color: _kCharcoal.withValues(alpha: 0.65)),
                ),
              ),
            ],
          ),
          const Divider(height: 20),
          child,
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Donut chart painter (same as admin dashboard)
// ─────────────────────────────────────────────────────────────────────────────

class _DonutSeg {
  final String label;
  final double value;
  final Color color;
  const _DonutSeg(this.label, this.value, this.color);
}

class _DonutPainter extends CustomPainter {
  final List<_DonutSeg> segments;
  final double progress;
  const _DonutPainter(this.segments, this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final outerR = math.min(size.width, size.height) / 2;
    final strokeW = outerR * 0.30;
    final r = outerR - strokeW / 2;
    final rect = Rect.fromCircle(center: center, radius: r);

    final total = segments.fold(0.0, (s, e) => s + e.value);
    if (total == 0) {
      canvas.drawArc(
        rect, 0, math.pi * 2, false,
        Paint()
          ..color = Colors.grey.shade200
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeW,
      );
      return;
    }

    const gap = 0.05;
    double startAngle = -math.pi / 2;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeW
      ..strokeCap = StrokeCap.butt
      ..isAntiAlias = true;

    for (final seg in segments) {
      final sweep = (seg.value / total) *
          (math.pi * 2 - segments.length * gap) * progress;
      if (sweep > 0) {
        paint.color = seg.color;
        canvas.drawArc(rect, startAngle, sweep, false, paint);
        startAngle += sweep + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) => old.progress != progress;
}

// ─────────────────────────────────────────────────────────────────────────────
// Simple data holders
// ─────────────────────────────────────────────────────────────────────────────

class _KpiData {
  final String label;
  final int value;
  final IconData icon;
  final Color color;
  const _KpiData(this.label, this.value, this.icon, this.color);
}

class _Bar {
  final String label;
  final int value;
  final Color color;
  const _Bar(this.label, this.value, this.color);
}

class _Nav {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final Widget screen;
  const _Nav(this.title, this.subtitle, this.icon, this.color, this.screen);
}
