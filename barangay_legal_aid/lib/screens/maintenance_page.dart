import 'package:flutter/material.dart';
import 'package:barangay_legal_aid/services/api_service.dart';

class MaintenancePage extends StatefulWidget {
  const MaintenancePage({super.key});

  @override
  State<MaintenancePage> createState() => _MaintenancePageState();
}

class _MaintenancePageState extends State<MaintenancePage> {
  static const _kPrimary  = Color(0xFF99272D);
  static const _kCharcoal = Color(0xFF36454F);
  static const _kBg       = Color(0xFFF0F2F5);

  bool _isChecking = false;

  Future<void> _checkAgain() async {
    setState(() => _isChecking = true);
    try {
      final still = await ApiService().getSystemStatus();
      if (!mounted) return;
      if (!still) {
        Navigator.pushReplacementNamed(context, '/login');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Still under maintenance. Please check back soon.'),
            backgroundColor: _kCharcoal,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not reach server. Try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isChecking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: _kBg,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // ── Red gradient header ──────────────────────────────────
                  Container(
                    width: double.infinity,
                    constraints: const BoxConstraints(maxWidth: 440),
                    padding: const EdgeInsets.symmetric(vertical: 36),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF99272D), Color(0xFFB83A41)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                    ),
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.build_rounded,
                            size: 48,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 14),
                        const Text(
                          'BARANGAY LEGAL AID',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 2.5,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // ── White content card ───────────────────────────────────
                  Container(
                    width: double.infinity,
                    constraints: const BoxConstraints(maxWidth: 440),
                    padding: const EdgeInsets.fromLTRB(28, 32, 28, 28),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
                      boxShadow: [
                        BoxShadow(
                          color: Color(0x1A000000),
                          blurRadius: 24,
                          offset: Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        const Icon(
                          Icons.construction_rounded,
                          size: 64,
                          color: _kPrimary,
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          'System Under Maintenance',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: _kCharcoal,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          "We're making improvements to serve you better.\nPlease check back soon.",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade600,
                            height: 1.6,
                          ),
                        ),
                        const SizedBox(height: 24),
                        Divider(color: _kPrimary.withValues(alpha: 0.18), thickness: 1),
                        const SizedBox(height: 16),
                        Text(
                          'Barangay Legal Aid System',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade400,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: _kPrimary,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            onPressed: _isChecking ? null : _checkAgain,
                            icon: _isChecking
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.refresh_rounded, size: 18),
                            label: Text(
                              _isChecking ? 'Checking...' : 'Check Again',
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
