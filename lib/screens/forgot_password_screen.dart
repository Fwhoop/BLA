import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:barangay_legal_aid/services/api_service.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _identifierCtrl = TextEditingController();
  final _otpCtrl = TextEditingController();
  final _newPasswordCtrl = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();

  String _method = 'email'; // 'email' or 'phone'
  int _step = 1;            // 1 = input, 2 = code + new password
  int? _userId;
  bool _isLoading = false;
  bool _obscureNew = true;
  bool _obscureConfirm = true;

  // Firebase phone flow
  String? _verificationId;

  @override
  void dispose() {
    _identifierCtrl.dispose();
    _otpCtrl.dispose();
    _newPasswordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      final api = Provider.of<ApiService>(context, listen: false);
      final res = await api.forgotPassword(_identifierCtrl.text.trim(), _method);
      _userId = res['user_id'] as int?;

      if (_method == 'phone') {
        // Trigger Firebase phone OTP
        final phone = _identifierCtrl.text.trim();
        await FirebaseAuth.instance.verifyPhoneNumber(
          phoneNumber: phone,
          verificationCompleted: (PhoneAuthCredential cred) async {
            final userCred = await FirebaseAuth.instance.signInWithCredential(cred);
            final idToken = await userCred.user!.getIdToken();
            if (mounted) _onPhoneVerified(idToken!);
          },
          verificationFailed: (FirebaseAuthException e) {
            if (mounted) {
              _showError(e.message ?? 'Phone verification failed');
              setState(() => _isLoading = false);
            }
          },
          codeSent: (String verificationId, int? resendToken) {
            setState(() {
              _verificationId = verificationId;
              _step = 2;
              _isLoading = false;
            });
          },
          codeAutoRetrievalTimeout: (_) {},
        );
      } else {
        // Email OTP — just move to step 2
        setState(() {
          _step = 2;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        _showError(e.toString().replaceFirst('Exception: ', ''));
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _submitReset() async {
    if (!_formKey.currentState!.validate()) return;
    if (_newPasswordCtrl.text != _confirmPasswordCtrl.text) {
      _showError('Passwords do not match');
      return;
    }
    if (_userId == null) {
      _showError('Session expired. Please start over.');
      return;
    }
    setState(() => _isLoading = true);
    try {
      final api = Provider.of<ApiService>(context, listen: false);
      if (_method == 'email') {
        await api.resetPassword(_userId!, _otpCtrl.text.trim(), _newPasswordCtrl.text);
      } else {
        // Verify the SMS code with Firebase and get ID token
        final credential = PhoneAuthProvider.credential(
          verificationId: _verificationId!,
          smsCode: _otpCtrl.text.trim(),
        );
        final userCred = await FirebaseAuth.instance.signInWithCredential(credential);
        final idToken = await userCred.user!.getIdToken();
        await api.resetPasswordPhone(_userId!, idToken!, _newPasswordCtrl.text);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Password reset successfully! Please login.'),
          backgroundColor: Color(0xFF36454F),
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

  void _onPhoneVerified(String idToken) async {
    if (_userId == null) return;
    setState(() => _isLoading = true);
    try {
      // Need password fields — go to step 2 with idToken stored
      // In auto-verification we skip OTP entry, so just show new password fields
      setState(() {
        _step = 2;
        _isLoading = false;
      });
    } catch (_) {
      setState(() => _isLoading = false);
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
        title: const Text('Forgot Password'),
        backgroundColor: const Color(0xFF99272D),
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: _step == 1 ? _buildStep1() : _buildStep2(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStep1() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.lock_reset, size: 64, color: Color(0xFF99272D)),
        const SizedBox(height: 16),
        const Text(
          'Reset your password',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF36454F)),
        ),
        const SizedBox(height: 8),
        const Text(
          'Enter your email or phone number and choose a reset method.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Color(0xFF36454F)),
        ),
        const SizedBox(height: 24),
        TextFormField(
          controller: _identifierCtrl,
          decoration: const InputDecoration(
            labelText: 'Email or Phone Number',
            hintText: 'you@example.com or +639XXXXXXXXX',
            prefixIcon: Icon(Icons.person_outline),
          ),
          validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
        ),
        const SizedBox(height: 20),
        const Text('Reset method:', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: RadioListTile<String>(
                title: const Text('Email OTP'),
                value: 'email',
                groupValue: _method,
                activeColor: const Color(0xFF99272D),
                onChanged: (v) => setState(() => _method = v!),
              ),
            ),
            Expanded(
              child: RadioListTile<String>(
                title: const Text('Phone SMS'),
                value: 'phone',
                groupValue: _method,
                activeColor: const Color(0xFF99272D),
                onChanged: (v) => setState(() => _method = v!),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: _isLoading ? null : _sendCode,
          child: _isLoading
              ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : const Text('Send Code'),
        ),
      ],
    );
  }

  Widget _buildStep2() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.verified_user, size: 64, color: Color(0xFF99272D)),
        const SizedBox(height: 16),
        Text(
          _method == 'email' ? 'Enter the code sent to your email' : 'Enter the SMS code',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF36454F)),
        ),
        const SizedBox(height: 24),
        TextFormField(
          controller: _otpCtrl,
          keyboardType: TextInputType.number,
          maxLength: 6,
          decoration: const InputDecoration(
            labelText: '6-digit Code',
            prefixIcon: Icon(Icons.pin_outlined),
          ),
          validator: (v) => (v == null || v.length < 6) ? 'Enter the 6-digit code' : null,
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _newPasswordCtrl,
          obscureText: _obscureNew,
          decoration: InputDecoration(
            labelText: 'New Password',
            prefixIcon: const Icon(Icons.lock_outline),
            suffixIcon: IconButton(
              icon: Icon(_obscureNew ? Icons.visibility : Icons.visibility_off),
              onPressed: () => setState(() => _obscureNew = !_obscureNew),
            ),
          ),
          validator: (v) => (v == null || v.length < 6) ? 'At least 6 characters' : null,
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _confirmPasswordCtrl,
          obscureText: _obscureConfirm,
          decoration: InputDecoration(
            labelText: 'Confirm New Password',
            prefixIcon: const Icon(Icons.lock_outline),
            suffixIcon: IconButton(
              icon: Icon(_obscureConfirm ? Icons.visibility : Icons.visibility_off),
              onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
            ),
          ),
          validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
        ),
        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: _isLoading ? null : _submitReset,
          child: _isLoading
              ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : const Text('Reset Password'),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: () => setState(() => _step = 1),
          child: const Text('Back', style: TextStyle(color: Color(0xFF99272D))),
        ),
      ],
    );
  }
}
