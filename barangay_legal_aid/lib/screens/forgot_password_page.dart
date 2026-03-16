import 'dart:async';

import 'package:flutter/material.dart';

import 'package:barangay_legal_aid/services/api_service.dart';
import 'package:barangay_legal_aid/utils/phone_utils.dart';

const _kPrimary  = Color(0xFF99272D);
const _kCharcoal = Color(0xFF36454F);

/// Two-step password reset:
///   Step 1 – Enter email OR phone number → backend sends OTP / Firebase sends SMS.
///             Account name + masked contact shown on Step 2 for confirmation.
///   Step 2 – Enter OTP/SMS code + new password → done.
class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final _api = ApiService();

  // ── Step 1 ───────────────────────────────────────────────────────────────
  final _step1Key       = GlobalKey<FormState>();
  final _identifierCtrl = TextEditingController();
  bool  _usePhone       = false;

  // ── Step 2 shared ────────────────────────────────────────────────────────
  final _step2Key          = GlobalKey<FormState>();
  final _codeCtrl          = TextEditingController();
  final _newPassCtrl       = TextEditingController();
  final _confirmPassCtrl   = TextEditingController();
  bool  _obscureNew        = true;
  bool  _obscureConfirm    = true;

  // ── Shared state ─────────────────────────────────────────────────────────
  bool    _isLoading     = false;
  bool    _onStep2       = false;
  int?    _userId;
  String? _displayName;    // "Juan Dela Cruz"
  String? _maskedContact;  // "ju***@gmail.com" or "+639****920"

  int    _resendCooldown = 0;
  Timer? _cooldownTimer;

  @override
  void dispose() {
    _identifierCtrl.dispose();
    _codeCtrl.dispose();
    _newPassCtrl.dispose();
    _confirmPassCtrl.dispose();
    _cooldownTimer?.cancel();
    super.dispose();
  }

  void _startCooldown() {
    _cooldownTimer?.cancel();
    setState(() => _resendCooldown = 60);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_resendCooldown > 0) setState(() => _resendCooldown--);
      else _cooldownTimer?.cancel();
    });
  }

  // ── Step 1: request OTP / SMS ─────────────────────────────────────────────

  Future<void> _requestCode() async {
    if (!_step1Key.currentState!.validate()) return;
    setState(() => _isLoading = true);

    final raw        = _identifierCtrl.text.trim();
    final identifier = _usePhone ? normalizePhPhone(raw) : raw;

    try {
      // Backend finds the account AND sends the OTP (email via Brevo, SMS via Semaphore)
      final result = await _api.forgotPassword(identifier, _usePhone ? 'phone' : 'email');
      final userId = result['user_id'] as int?;

      if (userId == null) {
        _showError('No account found with that ${_usePhone ? 'phone number' : 'email address'}.');
        return;
      }

      _userId        = userId;
      _displayName   = result['display_name']  as String?;
      _maskedContact = result['masked_contact'] as String?;

      if (!mounted) return;
      setState(() => _onStep2 = true);
      _startCooldown();
    } catch (e) {
      if (mounted) _showError(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Resend ────────────────────────────────────────────────────────────────

  Future<void> _resend() async {
    if (_resendCooldown > 0 || _isLoading) return;
    setState(() { _onStep2 = false; _codeCtrl.clear(); });
    await _requestCode();
  }

  // ── Step 2: verify code + set new password ────────────────────────────────

  Future<void> _verifyAndReset() async {
    if (!_step2Key.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      // Both email and phone now use the same backend OTP verification
      await _api.resetPassword(_userId!, _codeCtrl.text.trim(), _newPassCtrl.text.trim());

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Password reset successfully! Please log in.'),
        backgroundColor: _kCharcoal,
        duration: Duration(seconds: 4),
      ));
      Navigator.pushReplacementNamed(context, '/login');
    } catch (e) {
      if (mounted) _showError(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  void _showError(String msg) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(msg), backgroundColor: _kPrimary),
  );

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHero(),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                    child: Column(children: [
                      _onStep2 ? _buildStep2Card() : _buildStep1Card(),
                      const SizedBox(height: 16),
                      TextButton(
                        onPressed: () => Navigator.pushReplacementNamed(context, '/login'),
                        child: const Text('Back to Login',
                            style: TextStyle(color: _kPrimary)),
                      ),
                    ]),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Hero ──────────────────────────────────────────────────────────────────

  Widget _buildHero() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 48, 24, 36),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [_kPrimary, Color(0xFF6B1A1E)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: 0.3), width: 2),
            ),
            child: const Icon(Icons.lock_reset, size: 56, color: Colors.white),
          ),
          const SizedBox(height: 20),
          const Text('Reset Password',
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold,
                  color: Colors.white, letterSpacing: 0.5)),
          const SizedBox(height: 6),
          Text(
            _onStep2
                ? (_usePhone
                    ? 'Enter the SMS code and your new password'
                    : 'Enter the email code and your new password')
                : 'Enter your email or phone to get started',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Colors.white.withValues(alpha: 0.85)),
          ),
          const SizedBox(height: 20),
          // Step dots
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(2, (i) {
              final done    = _onStep2 && i == 0;
              final current = (_onStep2 ? i == 1 : i == 0);
              return Row(children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: current ? 28 : 20, height: current ? 28 : 20,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: done || current
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.3),
                  ),
                  child: Center(
                    child: done
                        ? Icon(Icons.check, size: 14, color: _kPrimary)
                        : Text('${i + 1}',
                            style: TextStyle(
                              fontSize: current ? 13 : 11,
                              fontWeight: FontWeight.bold,
                              color: current ? _kPrimary : Colors.white,
                            )),
                  ),
                ),
                if (i < 1)
                  Container(
                    width: 40, height: 2,
                    color: _onStep2
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.3),
                  ),
              ]);
            }),
          ),
        ],
      ),
    );
  }

  // ── Step 1 Card ───────────────────────────────────────────────────────────

  Widget _buildStep1Card() {
    return Card(
      elevation: 4,
      margin: EdgeInsets.zero,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(20),
          bottomRight: Radius.circular(20),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
        child: Form(
          key: _step1Key,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Find your account',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: _kCharcoal)),
              const SizedBox(height: 4),
              Text(
                'Enter the email address or phone number linked to your account.',
                style: TextStyle(fontSize: 14, color: _kCharcoal.withValues(alpha: 0.6)),
              ),
              const SizedBox(height: 20),

              // Toggle
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F2F5),
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.all(4),
                child: Row(children: [
                  Expanded(child: _toggleBtn('Email', Icons.email_outlined, !_usePhone,
                      () => setState(() { _usePhone = false; _identifierCtrl.clear(); }))),
                  Expanded(child: _toggleBtn('Phone SMS', Icons.phone_outlined, _usePhone,
                      () => setState(() { _usePhone = true;  _identifierCtrl.clear(); }))),
                ]),
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _identifierCtrl,
                keyboardType: _usePhone ? TextInputType.phone : TextInputType.emailAddress,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _isLoading ? null : _requestCode(),
                decoration: InputDecoration(
                  labelText: _usePhone ? 'Phone number' : 'Email address',
                  hintText: _usePhone ? '09XX or +63XX' : 'you@example.com',
                  prefixIcon: Icon(_usePhone ? Icons.phone_outlined : Icons.email_outlined),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty)
                    return 'Please enter your ${_usePhone ? 'phone number' : 'email'}';
                  if (_usePhone && !isValidPhPhone(v.trim()))
                    return 'Enter a valid PH number (09XX or +63XX)';
                  if (!_usePhone &&
                      !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v.trim()))
                    return 'Enter a valid email address';
                  return null;
                },
              ),
              const SizedBox(height: 24),

              _primaryButton('Find Account & Send Code', _requestCode),
            ],
          ),
        ),
      ),
    );
  }

  // ── Step 2 Card ───────────────────────────────────────────────────────────

  Widget _buildStep2Card() {
    final method = _usePhone ? 'SMS' : 'email';
    return Card(
      elevation: 4,
      margin: EdgeInsets.zero,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(20),
          bottomRight: Radius.circular(20),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
        child: Form(
          key: _step2Key,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Account confirmation banner ──────────────────────────────
              if (_displayName != null || _maskedContact != null)
                Container(
                  padding: const EdgeInsets.all(14),
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.green.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.check_circle_rounded,
                          color: Colors.green.shade600, size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Account found',
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.green)),
                            if (_displayName != null)
                              Text(_displayName!,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                      color: _kCharcoal)),
                            if (_maskedContact != null)
                              Text(_maskedContact!,
                                  style: TextStyle(
                                      fontSize: 13,
                                      color: _kCharcoal.withValues(alpha: 0.7))),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

              Text('Enter $method code & new password',
                  style: const TextStyle(fontSize: 20,
                      fontWeight: FontWeight.bold, color: _kCharcoal)),
              const SizedBox(height: 4),
              Text(
                'A 6-digit code was sent via $method to $_maskedContact.',
                style: TextStyle(fontSize: 14, color: _kCharcoal.withValues(alpha: 0.6)),
              ),
              const SizedBox(height: 24),

              // Code input
              TextFormField(
                controller: _codeCtrl,
                keyboardType: TextInputType.number,
                maxLength: 6,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 28, letterSpacing: 12, fontWeight: FontWeight.bold),
                decoration: InputDecoration(
                  labelText: '6-digit code',
                  hintText: '------',
                  counterText: '',
                  prefixIcon: Icon(_usePhone ? Icons.sms_outlined : Icons.pin_outlined),
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Please enter the code';
                  if (v.length != 6 || !RegExp(r'^\d{6}$').hasMatch(v))
                    return 'Must be exactly 6 digits';
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // New password
              TextFormField(
                controller: _newPassCtrl,
                obscureText: _obscureNew,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: 'New password',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(_obscureNew ? Icons.visibility : Icons.visibility_off),
                    onPressed: () => setState(() => _obscureNew = !_obscureNew),
                  ),
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Please enter a new password';
                  if (v.length < 6) return 'Minimum 6 characters';
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Confirm password
              TextFormField(
                controller: _confirmPassCtrl,
                obscureText: _obscureConfirm,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _isLoading ? null : _verifyAndReset(),
                decoration: InputDecoration(
                  labelText: 'Confirm new password',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(_obscureConfirm ? Icons.visibility : Icons.visibility_off),
                    onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                  ),
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Please confirm your password';
                  if (v != _newPassCtrl.text) return 'Passwords do not match';
                  return null;
                },
              ),
              const SizedBox(height: 24),

              _primaryButton('Reset Password', _verifyAndReset),
              const SizedBox(height: 8),

              // Resend
              TextButton(
                onPressed: (_isLoading || _resendCooldown > 0) ? null : _resend,
                child: Text(
                  _resendCooldown > 0
                      ? 'Resend Code ($_resendCooldown s)'
                      : 'Resend Code',
                  style: TextStyle(
                      color: _resendCooldown > 0 ? Colors.grey : _kPrimary),
                ),
              ),

              // Change method
              TextButton(
                onPressed: _isLoading
                    ? null
                    : () => setState(() {
                          _onStep2 = false;
                          _codeCtrl.clear();
                          _newPassCtrl.clear();
                          _confirmPassCtrl.clear();
                        }),
                child: Text(
                  'Use ${_usePhone ? 'email' : 'phone'} instead',
                  style: TextStyle(color: _kCharcoal.withValues(alpha: 0.6)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Shared widgets ────────────────────────────────────────────────────────

  Widget _toggleBtn(String label, IconData icon, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: active ? _kPrimary : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: active ? Colors.white : _kCharcoal),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: active ? Colors.white : _kCharcoal,
                )),
          ],
        ),
      ),
    );
  }

  Widget _primaryButton(String label, VoidCallback onPressed) {
    return ElevatedButton(
      onPressed: _isLoading ? null : onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: _kPrimary,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: _isLoading
          ? const SizedBox(
              height: 20, width: 20,
              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
          : Text(label,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
    );
  }
}
