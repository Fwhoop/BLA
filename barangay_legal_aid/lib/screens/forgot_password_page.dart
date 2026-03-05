import 'package:flutter/material.dart';
import 'package:barangay_legal_aid/services/api_service.dart';

/// Two-step forgot-password flow:
///   Step 1 – User enters their email and requests an OTP.
///   Step 2 – User enters the OTP and a new password to complete the reset.
class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final _apiService = ApiService();

  // ── Step 1 ──────────────────────────────────────────────────────────────
  final _emailFormKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();

  // ── Step 2 ──────────────────────────────────────────────────────────────
  final _resetFormKey = GlobalKey<FormState>();
  final _otpController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _isLoading = false;
  bool _otpSent = false;
  bool _obscureNew = true;
  bool _obscureConfirm = true;

  /// If the backend returns a dev OTP (SMTP not configured), we show it.
  String? _devOtp;

  @override
  void dispose() {
    _emailController.dispose();
    _otpController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  // ── Actions ──────────────────────────────────────────────────────────────

  Future<void> _requestOtp() async {
    if (!_emailFormKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      final result = await _apiService.forgotPassword(
        _emailController.text.trim(),
      );
      final devOtp = result['dev_otp'] as String?;
      if (!mounted) return;
      setState(() {
        _otpSent = true;
        _devOtp = devOtp;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            devOtp != null
                ? 'OTP: $devOtp  (SMTP not configured – shown for testing)'
                : 'OTP sent! Check your email.',
          ),
          backgroundColor: devOtp != null ? Colors.orange[800] : const Color(0xFF36454F),
          duration: Duration(seconds: devOtp != null ? 10 : 4),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceFirst('Exception: ', '')),
            backgroundColor: const Color(0xFF99272D),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _resetPassword() async {
    if (!_resetFormKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      await _apiService.resetPassword(
        token: _otpController.text.trim(),
        newPassword: _newPasswordController.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Password reset successfully. Please log in.'),
          backgroundColor: Color(0xFF36454F),
        ),
      );
      Navigator.pushReplacementNamed(context, '/login');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceFirst('Exception: ', '')),
            backgroundColor: const Color(0xFF99272D),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

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
                    child: Column(
                      children: [
                        _otpSent ? _buildStep2Card() : _buildStep1Card(),
                        const SizedBox(height: 16),
                        TextButton(
                          onPressed: () =>
                              Navigator.pushReplacementNamed(context, '/login'),
                          child: const Text(
                            'Back to Login',
                            style: TextStyle(color: Color(0xFF99272D)),
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

  Widget _buildHero() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 48, 24, 36),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF99272D), Color(0xFF6B1A1E)],
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
              border: Border.all(
                  color: Colors.white.withValues(alpha: 0.3), width: 2),
            ),
            child: const Icon(Icons.lock_reset, size: 56, color: Colors.white),
          ),
          const SizedBox(height: 20),
          const Text(
            'Forgot Password',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _otpSent
                ? 'Enter the OTP sent to your email'
                : 'Enter your email to receive an OTP',
            style: TextStyle(
              fontSize: 14,
              color: Colors.white.withValues(alpha: 0.85),
            ),
          ),
        ],
      ),
    );
  }

  // ── Step 1: Email entry ──────────────────────────────────────────────────

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
          key: _emailFormKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Reset your password',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF36454F),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'We\'ll send a one-time password to your registered email.',
                style: TextStyle(
                  fontSize: 14,
                  color: const Color(0xFF36454F).withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _isLoading ? null : _requestOtp(),
                decoration: const InputDecoration(
                  labelText: 'Email address',
                  hintText: 'you@example.com',
                  prefixIcon: Icon(Icons.email_outlined),
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Please enter your email';
                  final re = RegExp(r"^[^@\s]+@[^@\s]+\.[^@\s]+$");
                  if (!re.hasMatch(v)) return 'Enter a valid email address';
                  return null;
                },
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _isLoading ? null : _requestOtp,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF99272D),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2),
                      )
                    : const Text(
                        'Send OTP',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Step 2: OTP + new password ────────────────────────────────────────────

  Widget _buildStep2Card() {
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
          key: _resetFormKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Enter OTP & new password',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF36454F),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Check your email for the 6-digit OTP.',
                style: TextStyle(
                  fontSize: 14,
                  color: const Color(0xFF36454F).withValues(alpha: 0.6),
                ),
              ),
              if (_devOtp != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.orange[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange[300]!),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline,
                          color: Colors.orange[800], size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Dev mode OTP: $_devOtp',
                          style: TextStyle(
                            color: Colors.orange[900],
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 24),
              // OTP field
              TextFormField(
                controller: _otpController,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.next,
                maxLength: 6,
                decoration: const InputDecoration(
                  labelText: '6-digit OTP',
                  hintText: '123456',
                  prefixIcon: Icon(Icons.pin_outlined),
                  counterText: '',
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Please enter the OTP';
                  if (v.length != 6) return 'OTP must be exactly 6 digits';
                  if (!RegExp(r'^\d{6}$').hasMatch(v))
                    return 'OTP must be numeric';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              // New password
              TextFormField(
                controller: _newPasswordController,
                obscureText: _obscureNew,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: 'New password',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(_obscureNew
                        ? Icons.visibility
                        : Icons.visibility_off),
                    onPressed: () =>
                        setState(() => _obscureNew = !_obscureNew),
                  ),
                ),
                validator: (v) {
                  if (v == null || v.isEmpty)
                    return 'Please enter a new password';
                  if (v.length < 8)
                    return 'Password must be at least 8 characters';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              // Confirm password
              TextFormField(
                controller: _confirmPasswordController,
                obscureText: _obscureConfirm,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _isLoading ? null : _resetPassword(),
                decoration: InputDecoration(
                  labelText: 'Confirm new password',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(_obscureConfirm
                        ? Icons.visibility
                        : Icons.visibility_off),
                    onPressed: () =>
                        setState(() => _obscureConfirm = !_obscureConfirm),
                  ),
                ),
                validator: (v) {
                  if (v == null || v.isEmpty)
                    return 'Please confirm your password';
                  if (v != _newPasswordController.text)
                    return 'Passwords do not match';
                  return null;
                },
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _isLoading ? null : _resetPassword,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF99272D),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2),
                      )
                    : const Text(
                        'Reset Password',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                      ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _isLoading
                    ? null
                    : () => setState(() {
                          _otpSent = false;
                          _devOtp = null;
                        }),
                child: const Text(
                  'Resend OTP',
                  style: TextStyle(color: Color(0xFF99272D)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
