import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:barangay_legal_aid/services/api_service.dart';

const _kPrimary  = Color(0xFF99272D);
const _kCharcoal = Color(0xFF36454F);

/// Screen shown after Firebase sends the SMS OTP during phone-based registration.
///
/// The user enters the 6-digit code from SMS here.  On success the credential is
/// exchanged for a Firebase ID token which is sent to the backend
/// `POST /auth/verify-firebase-phone` to mark [userId] as phone-verified.
class PhoneSmsVerificationScreen extends StatefulWidget {
  /// The `verificationId` returned by `FirebaseAuth.verifyPhoneNumber → codeSent`.
  /// Not used on web — pass empty string when providing [webConfirmationResult].
  final String verificationId;

  /// Backend user ID created during registration — used to link the verified
  /// Firebase phone number to the correct DB record.
  final int userId;

  /// E.164 phone number (e.g. +639XXXXXXXXX) shown on screen for clarity.
  final String phoneNumber;

  /// Web-only: result from `FirebaseAuth.signInWithPhoneNumber`.
  /// When set, code verification uses `confirmationResult.confirm()` instead of
  /// `PhoneAuthProvider.credential`.
  final ConfirmationResult? webConfirmationResult;

  const PhoneSmsVerificationScreen({
    super.key,
    required this.verificationId,
    required this.userId,
    required this.phoneNumber,
    this.webConfirmationResult,
  });

  @override
  State<PhoneSmsVerificationScreen> createState() => _PhoneSmsVerificationScreenState();
}

class _PhoneSmsVerificationScreenState extends State<PhoneSmsVerificationScreen> {
  final _codeCtrl = TextEditingController();
  bool _isVerifying = false;
  bool _isResending = false;

  // 5-minute expiry display timer
  int _secondsLeft = 300;
  Timer? _expiryTimer;

  // 60-second resend cooldown
  int _resendCooldown = 60;
  Timer? _cooldownTimer;

  // Resend tracking — Firebase may give us a new verificationId (native)
  // or a new ConfirmationResult (web)
  String _currentVerificationId = '';
  ConfirmationResult? _currentWebConfirmationResult;

  @override
  void initState() {
    super.initState();
    _currentVerificationId = widget.verificationId;
    _currentWebConfirmationResult = widget.webConfirmationResult;
    _startExpiryTimer();
    _startCooldownTimer();
  }

  @override
  void dispose() {
    _expiryTimer?.cancel();
    _cooldownTimer?.cancel();
    _codeCtrl.dispose();
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

  // ── Verify SMS code ────────────────────────────────────────────────────────

  Future<void> _verifyCode() async {
    final code = _codeCtrl.text.trim();
    if (code.length != 6) {
      _showError('Please enter the 6-digit SMS code');
      return;
    }
    setState(() => _isVerifying = true);
    try {
      // 1. Get a Firebase UserCredential — web uses ConfirmationResult.confirm(),
      //    native uses PhoneAuthProvider.credential + signInWithCredential.
      UserCredential userCred;
      if (kIsWeb && _currentWebConfirmationResult != null) {
        userCred = await _currentWebConfirmationResult!.confirm(code);
      } else {
        final credential = PhoneAuthProvider.credential(
          verificationId: _currentVerificationId,
          smsCode: code,
        );
        userCred = await FirebaseAuth.instance.signInWithCredential(credential);
      }

      // 2. Get Firebase ID token
      final idToken = await userCred.user?.getIdToken();
      if (idToken == null) {
        throw Exception('Could not retrieve Firebase ID token. Please try again.');
      }

      // 3. Send the token to our backend to mark the user as phone-verified
      if (!mounted) return;
      final api = Provider.of<ApiService>(context, listen: false);
      await api.verifyFirebasePhone(widget.userId, idToken);

      // 4. Sign out from Firebase — we use our own JWT system for sessions
      await FirebaseAuth.instance.signOut();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Phone verified! Your account is pending admin approval.'),
          backgroundColor: _kCharcoal,
          duration: Duration(seconds: 4),
        ),
      );
      Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        final msg = _friendlyFirebaseError(e);
        _showError(msg);
        setState(() => _isVerifying = false);
      }
    } catch (e) {
      if (mounted) {
        _showError(e.toString().replaceFirst('Exception: ', ''));
        setState(() => _isVerifying = false);
      }
    }
  }

  // ── Resend SMS ─────────────────────────────────────────────────────────────

  Future<void> _resendCode() async {
    if (_isResending || _resendCooldown > 0) return;
    setState(() => _isResending = true);
    try {
      // Web: re-send via signInWithPhoneNumber + invisible reCAPTCHA
      if (kIsWeb) {
        final result = await FirebaseAuth.instance
            .signInWithPhoneNumber(widget.phoneNumber);
        if (mounted) {
          setState(() {
            _currentWebConfirmationResult = result;
            _resendCooldown = 60;
          });
          _startExpiryTimer();
          _startCooldownTimer();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('A new SMS code has been sent.'),
              backgroundColor: _kCharcoal,
            ),
          );
        }
        setState(() => _isResending = false);
        return;
      }

      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: widget.phoneNumber,
        verificationCompleted: (PhoneAuthCredential cred) async {
          // Auto-verified — handle silently
          try {
            final userCred = await FirebaseAuth.instance.signInWithCredential(cred);
            final idToken = await userCred.user?.getIdToken();
            if (idToken != null && mounted) {
              final api = Provider.of<ApiService>(context, listen: false);
              await api.verifyFirebasePhone(widget.userId, idToken);
              await FirebaseAuth.instance.signOut();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Phone auto-verified! Awaiting admin approval.'),
                    backgroundColor: _kCharcoal,
                  ),
                );
                Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
              }
            }
          } catch (_) {}
        },
        verificationFailed: (FirebaseAuthException e) {
          if (mounted) _showError(_friendlyFirebaseError(e));
        },
        codeSent: (String newVerificationId, int? _) {
          if (mounted) {
            setState(() {
              _currentVerificationId = newVerificationId;
              _resendCooldown = 60;
            });
            _startExpiryTimer();
            _startCooldownTimer();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('A new SMS code has been sent.'),
                backgroundColor: _kCharcoal,
              ),
            );
          }
        },
        codeAutoRetrievalTimeout: (_) {},
        timeout: const Duration(seconds: 60),
      );
    } catch (e) {
      if (mounted) _showError('Failed to resend code: $e');
    } finally {
      if (mounted) setState(() => _isResending = false);
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  String _friendlyFirebaseError(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-verification-code':
        return 'Incorrect SMS code. Please check and try again.';
      case 'session-expired':
        return 'The SMS code has expired. Please request a new one.';
      case 'too-many-requests':
        return 'Too many attempts. Please wait a moment before trying again.';
      case 'invalid-phone-number':
        return 'The phone number format is invalid. Use +639XXXXXXXXX.';
      case 'quota-exceeded':
        return 'SMS quota exceeded. Please try again later or use email verification.';
      default:
        return e.message ?? 'Phone verification failed. Please try again.';
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: _kPrimary),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Verify Phone'),
        backgroundColor: _kPrimary,
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
                  const Icon(Icons.phone_android_rounded, size: 72, color: _kPrimary),
                  const SizedBox(height: 20),
                  const Text(
                    'Check your messages',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: _kCharcoal),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'We sent a 6-digit code via SMS to\n${widget.phoneNumber}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: _kCharcoal),
                  ),
                  const SizedBox(height: 32),
                  TextField(
                    controller: _codeCtrl,
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
                    _secondsLeft > 0
                        ? 'Code expires in $_timerDisplay'
                        : 'Code has expired — tap Resend',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _secondsLeft > 0 ? _kCharcoal : _kPrimary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: _isVerifying ? null : _verifyCode,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kPrimary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: _isVerifying
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          )
                        : const Text('Verify Phone'),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: (_isResending || _resendCooldown > 0) ? null : _resendCode,
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
                              color: _resendCooldown > 0 ? Colors.grey : _kPrimary,
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
