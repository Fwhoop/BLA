import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:barangay_legal_aid/services/api_service.dart';

class OtpVerificationScreen extends StatefulWidget {
  final int userId;
  final String email;

  /// When false, the screen shows a warning banner telling the user the email
  /// could not be delivered (SMTP not configured on the server).
  final bool emailSent;

  const OtpVerificationScreen({
    super.key,
    required this.userId,
    required this.email,
    this.emailSent = true,
  });

  @override
  State<OtpVerificationScreen> createState() => _OtpVerificationScreenState();
}

class _OtpVerificationScreenState extends State<OtpVerificationScreen> {
  final _otpCtrl = TextEditingController();
  bool _isLoading  = false;
  bool _isResending = false;

  // 5-minute expiry countdown (purely informational — does NOT block resend)
  int _secondsLeft = 300;
  Timer? _expiryTimer;

  // 60-second resend cooldown — user must wait this long between sends
  int _resendCooldown = 0;
  Timer? _cooldownTimer;

  @override
  void initState() {
    super.initState();
    _startExpiryTimer();
    // If the initial email failed, start with cooldown = 0 so user can resend immediately
    if (!widget.emailSent) {
      _resendCooldown = 0;
    } else {
      _resendCooldown = 60; // normal 60s cooldown after first send
      _startCooldownTimer();
    }
  }

  @override
  void dispose() {
    _expiryTimer?.cancel();
    _cooldownTimer?.cancel();
    _otpCtrl.dispose();
    super.dispose();
  }

  // ── Timers ─────────────────────────────────────────────────────────────────

  void _startExpiryTimer() {
    _expiryTimer?.cancel();
    setState(() => _secondsLeft = 300);
    _expiryTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_secondsLeft > 0) {
        setState(() => _secondsLeft--);
      } else {
        _expiryTimer?.cancel();
      }
    });
  }

  void _startCooldownTimer() {
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_resendCooldown > 0) {
        setState(() => _resendCooldown--);
      } else {
        _cooldownTimer?.cancel();
      }
    });
  }

  String get _timerDisplay {
    final m = _secondsLeft ~/ 60;
    final s = _secondsLeft % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  // ── Verify ─────────────────────────────────────────────────────────────────

  Future<void> _verifyOtp() async {
    final otp = _otpCtrl.text.trim();
    if (otp.length != 6) {
      _showError('Please enter the 6-digit code');
      return;
    }
    setState(() => _isLoading = true);
    try {
      final api = Provider.of<ApiService>(context, listen: false);
      await api.verifyEmailOtp(widget.userId, otp);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Email verified! Your account is pending admin approval.'),
          backgroundColor: Color(0xFF36454F),
          duration: Duration(seconds: 4),
        ),
      );
      Navigator.pushReplacementNamed(context, '/login');
    } catch (e) {
      if (mounted) {
        _showError(e.toString().replaceFirst('Exception: ', ''));
        setState(() => _isLoading = false);
      }
    }
  }

  // ── Resend ─────────────────────────────────────────────────────────────────

  Future<void> _resendOtp() async {
    if (_isResending || _resendCooldown > 0) return;
    setState(() => _isResending = true);
    try {
      final api = Provider.of<ApiService>(context, listen: false);
      final res = await api.sendEmailOtp(widget.email);
      final emailSent = res['email_sent'] as bool? ?? true;
      _startExpiryTimer();
      setState(() {
        _resendCooldown = 60;
      });
      _startCooldownTimer();
      if (mounted) {
        if (emailSent) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('A new code has been sent to your email.'),
              backgroundColor: Color(0xFF36454F),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Email delivery failed — SMTP is not configured on the server. '
                'Please contact your administrator.',
              ),
              backgroundColor: Color(0xFF99272D),
              duration: Duration(seconds: 6),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) _showError(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isResending = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: const Color(0xFF99272D)),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Verify Email'),
        backgroundColor: const Color(0xFF99272D),
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── SMTP warning banner ──────────────────────────────────
                  if (!widget.emailSent) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF3CD),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFFFEBA0)),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.warning_amber_rounded, color: Color(0xFF856404)),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Email could not be delivered — the server\'s email service '
                              'is not configured. Tap "Resend Code" once SMTP is set up, '
                              'or contact your administrator.',
                              style: TextStyle(fontSize: 12, color: Color(0xFF856404)),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  const Icon(Icons.mark_email_read, size: 72, color: Color(0xFF99272D)),
                  const SizedBox(height: 20),
                  const Text(
                    'Check your email',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF36454F)),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'We sent a 6-digit code to\n${widget.email}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Color(0xFF36454F)),
                  ),
                  const SizedBox(height: 32),
                  TextField(
                    controller: _otpCtrl,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 28, letterSpacing: 12, fontWeight: FontWeight.bold),
                    decoration: const InputDecoration(
                      hintText: '------',
                      counterText: '',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _secondsLeft > 0 ? 'Code expires in $_timerDisplay' : 'Code has expired — tap Resend',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _secondsLeft > 0 ? const Color(0xFF36454F) : const Color(0xFF99272D),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: _isLoading ? null : _verifyOtp,
                    child: _isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          )
                        : const Text('Verify Email'),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: (_isResending || _resendCooldown > 0) ? null : _resendOtp,
                    child: _isResending
                        ? const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            _resendCooldown > 0
                                ? 'Resend Code (${_resendCooldown}s)'
                                : 'Resend Code',
                            style: TextStyle(
                              color: _resendCooldown > 0
                                  ? Colors.grey
                                  : const Color(0xFF99272D),
                            ),
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
