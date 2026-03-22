import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:barangay_legal_aid/services/api_service.dart';

const _kPrimary  = Color(0xFF99272D);
const _kCharcoal = Color(0xFF36454F);

class SystemScreen extends StatefulWidget {
  const SystemScreen({super.key});

  @override
  SystemScreenState createState() => SystemScreenState();
}

class SystemScreenState extends State<SystemScreen> {

  Future<void> _showResetConfirmationDialog() async {
    final passwordCtrl      = TextEditingController();
    final confirmationCtrl  = TextEditingController();
    bool passwordVisible     = false;
    bool isLoading           = false;
    String? errorMsg;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setS) {
          final confirmationValid = confirmationCtrl.text == 'CONFIRM';

          return AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.warning_amber_rounded, color: _kPrimary, size: 22),
                const SizedBox(width: 8),
                const Text('Reset All Data'),
              ],
            ),
            content: SizedBox(
              width: 380,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _kPrimary.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: _kPrimary.withValues(alpha: 0.2)),
                      ),
                      child: const Text(
                        'This will permanently delete:\n'
                        '• All barangays\n'
                        '• All resident and admin accounts\n'
                        '• All cases, complaints, and mediations\n'
                        '• All document requests and notifications\n\n'
                        'Your superadmin account will NOT be deleted.\n'
                        'Deleted emails can be re-registered.',
                        style: TextStyle(fontSize: 13, color: _kPrimary, height: 1.5),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Password
                    TextField(
                      controller: passwordCtrl,
                      obscureText: !passwordVisible,
                      decoration: InputDecoration(
                        labelText: 'Your Password',
                        border: const OutlineInputBorder(),
                        isDense: true,
                        suffixIcon: IconButton(
                          icon: Icon(passwordVisible ? Icons.visibility_off : Icons.visibility),
                          onPressed: () => setS(() => passwordVisible = !passwordVisible),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Confirmation text
                    const Text(
                      'Type CONFIRM to proceed:',
                      style: TextStyle(fontSize: 13, color: _kCharcoal),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: confirmationCtrl,
                      decoration: InputDecoration(
                        hintText: 'CONFIRM',
                        border: const OutlineInputBorder(),
                        isDense: true,
                        suffixIcon: confirmationValid
                            ? const Icon(Icons.check_circle, color: Colors.green)
                            : null,
                      ),
                      onChanged: (_) => setS(() {}),
                    ),

                    if (errorMsg != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        errorMsg!,
                        style: const TextStyle(color: _kPrimary, fontSize: 13),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: isLoading ? null : () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: _kPrimary),
                onPressed: (!confirmationValid || isLoading)
                    ? null
                    : () async {
                        final password = passwordCtrl.text;
                        if (password.isEmpty) {
                          setS(() => errorMsg = 'Please enter your password.');
                          return;
                        }
                        setS(() { isLoading = true; errorMsg = null; });
                        try {
                          final api = Provider.of<ApiService>(ctx, listen: false);
                          await api.resetDatabase(password, 'CONFIRM');
                          if (ctx.mounted) Navigator.pop(ctx);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('All data has been reset. The system is now clean.'),
                                backgroundColor: _kCharcoal,
                                duration: Duration(seconds: 4),
                              ),
                            );
                          }
                        } catch (e) {
                          setS(() {
                            isLoading = false;
                            errorMsg = e.toString().replaceFirst('Exception: ', '');
                          });
                        }
                      },
                child: isLoading
                    ? const SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : const Text('Delete Everything'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('System Configuration'),
        backgroundColor: _kPrimary,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Database',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: _kPrimary),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Reset All Data',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                  color: _kPrimary,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Permanently deletes all barangays, users, cases, and requests. '
                                'Your superadmin account is preserved. '
                                'Use this for a clean test environment.',
                                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        OutlinedButton.icon(
                          onPressed: _showResetConfirmationDialog,
                          icon: const Icon(Icons.delete_forever, color: _kPrimary),
                          label: const Text('Reset', style: TextStyle(color: _kPrimary)),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: _kPrimary),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
