import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:barangay_legal_aid/services/api_service.dart';

class OtpVerificationScreen extends StatefulWidget {
  final int userId;
  final String email;

  const OtpVerificationScreen({
    super.key,
    required this.userId,
    required this.email,
  });

  @override
  State<OtpVerificationScreen> createState() => _OtpVerificationScreenState();
}

class _OtpVerificationScreenState extends State<OtpVerificationScreen> {
  final _otpCtrl = TextEditingController();
  bool _isLoading = false;
  bool _isResending = false;

  // 5-minute countdown
  int _secondsLeft = 300;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _otpCtrl.dispose();
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    setState(() => _secondsLeft = 300);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_secondsLeft > 0) {
        setState(() => _secondsLeft--);
      } else {
        _timer?.cancel();
      }
    });
  }

  String get _timerDisplay {
    final m = _secondsLeft ~/ 60;
    final s = _secondsLeft % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

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

  Future<void> _resendOtp() async {
    setState(() => _isResending = true);
    try {
      final api = Provider.of<ApiService>(context, listen: false);
      await api.sendEmailOtp(widget.email);
      _startTimer();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('A new code has been sent to your email.'),
            backgroundColor: Color(0xFF36454F),
          ),
        );
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
                    _secondsLeft > 0 ? 'Code expires in $_timerDisplay' : 'Code has expired',
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
                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Text('Verify Email'),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: (_isResending || _secondsLeft > 0) ? null : _resendOtp,
                    child: _isResending
                        ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Resend Code', style: TextStyle(color: Color(0xFF99272D))),
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
