import 'dart:io';
import 'dart:typed_data';

import 'package:barangay_legal_aid/screens/otp_verification_screen.dart';
import 'package:barangay_legal_aid/services/auth_service.dart';
import 'package:barangay_legal_aid/services/api_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

class SignupPage extends StatefulWidget {
  const SignupPage({super.key});

  @override
  State<SignupPage> createState() => SignupPageState();
}

class SignupPageState extends State<SignupPage> {
  final _formKey = GlobalKey<FormState>();
  final ImagePicker _imagePicker = ImagePicker();

  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();

  String? _selectedBarangay;
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  File? _idPhotoFile;
  Uint8List? _idPhotoBytes; // For web platform

  String _role = 'user';               // 'user' or 'admin'
  String _verificationMethod = 'email'; // 'email' or 'phone'

  List<Map<String, dynamic>> _barangayItems = [];
  bool _barangaysLoading = true;

  @override
  void initState() {
    super.initState();
    _loadBarangays();
  }

  Future<void> _loadBarangays() async {
    try {
      final api = Provider.of<ApiService>(context, listen: false);
      final items = await api.getBarangays();
      if (mounted) setState(() { _barangayItems = items; _barangaysLoading = false; });
    } catch (_) {
      if (mounted) setState(() => _barangaysLoading = false);
    }
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _pickIdPhoto() async {
    try {
      // On web, camera is not supported - use gallery directly
      if (kIsWeb) {
        final pickedFile = await _imagePicker.pickImage(
          source: ImageSource.gallery,
          maxWidth: 1600,
          maxHeight: 1600,
          imageQuality: 85,
        );

        if (pickedFile != null) {
          final bytes = await pickedFile.readAsBytes();
          setState(() {
            _idPhotoBytes = bytes;
            _idPhotoFile = null;
          });
          
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('ID photo selected successfully'),
                backgroundColor: Color(0xFF36454F),
                duration: Duration(seconds: 2),
              ),
            );
          }
        }
        return;
      }

      // For mobile/desktop, show dialog to choose between camera and gallery
      final ImageSource? source = await showDialog<ImageSource>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Select Photo Source'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(Icons.camera_alt, color: Color(0xFF99272D)),
                title: Text('Take Photo'),
                onTap: () => Navigator.pop(context, ImageSource.camera),
              ),
              ListTile(
                leading: Icon(Icons.photo_library, color: Color(0xFF99272D)),
                title: Text('Choose from Gallery'),
                onTap: () => Navigator.pop(context, ImageSource.gallery),
              ),
            ],
          ),
        ),
      );

      if (source == null) return; // User cancelled

      final actualSource = source;

      final pickedFile = await _imagePicker.pickImage(
        source: actualSource,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 85,
      );

      if (pickedFile != null) {
        if (kIsWeb) {
          // For web, read as bytes directly (XFile.readAsBytes works on web)
          final bytes = await pickedFile.readAsBytes();
          setState(() {
            _idPhotoBytes = bytes;
            // On web, we don't create a File object, just store the path string
            _idPhotoFile = null; // Will be null on web, we use bytes instead
          });
        } else {
          // For mobile/desktop, use File object
          setState(() {
            _idPhotoFile = File(pickedFile.path);
          });
        }
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('ID photo selected successfully'),
              backgroundColor: Color(0xFF36454F),
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    } on Exception catch (e) {
      String errorMessage = 'Unable to pick ID photo';
      if (e.toString().contains('camera')) {
        errorMessage = 'Camera permission denied. Please enable camera access in settings.';
      } else if (e.toString().contains('photo')) {
        errorMessage = 'Photo permission denied. Please enable photo access in settings.';
      } else {
        errorMessage = 'Unable to pick ID photo: ${e.toString()}';
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Color(0xFF99272D),
            duration: Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('An unexpected error occurred: $e'),
            backgroundColor: Color(0xFF99272D),
            duration: Duration(seconds: 4),
          ),
        );
      }
    }
  }

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) return;

    if (_passwordController.text != _confirmPasswordController.text) {
      _showError('Passwords do not match');
      return;
    }
    if (_selectedBarangay == null) {
      _showError('Please select your barangay');
      return;
    }
    if (_idPhotoFile == null && _idPhotoBytes == null) {
      _showError('Please upload a valid ID photo');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final idPhotoPath = kIsWeb
          ? 'web_image_${DateTime.now().millisecondsSinceEpoch}.jpg'
          : (_idPhotoFile?.path ?? '');

      final auth = Provider.of<AuthService>(context, listen: false);
      final api = Provider.of<ApiService>(context, listen: false);

      await auth.signUp(
        firstName: _firstNameController.text,
        lastName: _lastNameController.text,
        email: _emailController.text,
        password: _passwordController.text,
        phone: _phoneController.text,
        address: _addressController.text,
        barangay: _selectedBarangay!,
        idPhotoPath: idPhotoPath,
        idPhotoBytes: _idPhotoBytes,
        role: _role,
      );

      if (!mounted) return;

      if (_verificationMethod == 'email') {
        // Send OTP then navigate to OTP screen
        final res = await api.sendEmailOtp(_emailController.text.trim());
        final userId = res['user_id'] as int?;
        if (!mounted) return;
        if (userId != null) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => OtpVerificationScreen(
                userId: userId,
                email: _emailController.text.trim(),
              ),
            ),
          );
          return;
        }
      } else {
        // Firebase phone OTP
        final phone = _phoneController.text.trim();
        await FirebaseAuth.instance.verifyPhoneNumber(
          phoneNumber: phone,
          verificationCompleted: (PhoneAuthCredential cred) async {
            final userCred = await FirebaseAuth.instance.signInWithCredential(cred);
            final idToken = await userCred.user!.getIdToken();
            // Get userId from backend
            final res = await api.sendEmailOtp(_emailController.text.trim()).catchError((_) => <String, dynamic>{});
            final uid = res['user_id'] as int?;
            if (uid != null && idToken != null) {
              await api.verifyFirebasePhone(uid, idToken);
            }
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Phone verified! Awaiting admin approval.'), backgroundColor: Color(0xFF36454F)),
              );
              Navigator.pushReplacementNamed(context, '/login');
            }
          },
          verificationFailed: (FirebaseAuthException e) {
            if (mounted) _showError(e.message ?? 'Phone verification failed');
          },
          codeSent: (String verificationId, int? _) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('SMS code sent! Check your messages.\nApplication submitted — await admin approval.'),
                  backgroundColor: Color(0xFF36454F),
                  duration: Duration(seconds: 5),
                ),
              );
              Navigator.pushReplacementNamed(context, '/login');
            }
          },
          codeAutoRetrievalTimeout: (_) {},
        );
        return;
      }

      // Fallback — no OTP flow needed
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Application submitted! An admin will review your ID for approval.'),
          backgroundColor: Color(0xFF36454F),
          duration: Duration(seconds: 3),
        ),
      );
      await Future.delayed(const Duration(seconds: 2));
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/login');
    } catch (e) {
      if (mounted) {
        _showError(e is Exception ? e.toString().replaceFirst('Exception: ', '') : 'Signup failed. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
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
        title: Text('Create Account'),
        leading: IconButton(
          icon: Icon(Icons.arrow_back),
          onPressed: () {
            Navigator.pushReplacementNamed(context, '/login');
          },
          tooltip: 'Back to Login',
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 640),
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildLogo(),
                    SizedBox(height: 24),
                    _buildNameFields(),
                    SizedBox(height: 16),
                    _buildEmailField(),
                    SizedBox(height: 16),
                    _buildPasswordField(),
                    SizedBox(height: 16),
                    _buildConfirmPasswordField(),
                    SizedBox(height: 16),
                    _buildPhoneField(),
                    SizedBox(height: 16),
                    _buildAddressField(),
                    SizedBox(height: 16),
                    _buildIdPhotoUploader(),
                    SizedBox(height: 16),
                    _buildBarangayDropdown(),
                    SizedBox(height: 16),
                    _buildRoleSelector(),
                    SizedBox(height: 16),
                    _buildVerificationMethodSelector(),
                    SizedBox(height: 24),
                    _buildSignupButton(),
                    SizedBox(height: 16),
                    _buildLoginLink(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLogo() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        padding: EdgeInsets.all(24),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: [Color(0xFF99272D), Color(0xFF36454F)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Column(
          children: [
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha:0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.gavel,
                size: 60,
                color: Colors.white,
              ),
            ),
            SizedBox(height: 16),
            Text(
              'Barangay Legal Aid',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Create your account',
              style: TextStyle(
                fontSize: 16,
                color: Colors.white.withValues(alpha:0.9),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNameFields() {
    return Row(
      children: [
        Expanded(
          child: TextFormField(
            controller: _firstNameController,
            decoration: InputDecoration(
              labelText: 'First name',
              prefixIcon: Icon(Icons.person_outline),
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Please enter your first name';
              }
              return null;
            },
          ),
        ),
        SizedBox(width: 10),
        Expanded(
          child: TextFormField(
            controller: _lastNameController,
            decoration: InputDecoration(
              labelText: 'Last name',
              prefixIcon: Icon(Icons.person_outline),
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Please enter your last name';
              }
              return null;
            },
          ),
        ),
      ],
    );
  }

  Widget _buildEmailField() {
    return TextFormField(
      controller: _emailController,
      keyboardType: TextInputType.emailAddress,
      decoration: InputDecoration(
        labelText: 'Email address',
        hintText: 'you@example.com',
        prefixIcon: Icon(Icons.email_outlined),
      ),
      validator: (value) {
        if (value == null || value.isEmpty) {
          return 'Please enter your email';
        }
        final emailRegex = RegExp(r"^[^@\s]+@[^@\s]+\.[^@\s]+$");
        if (!emailRegex.hasMatch(value)) {
          return 'Please enter a valid email';
        }
        return null;
      },
    );
  }

  Widget _buildPasswordField() {
    return TextFormField(
      controller: _passwordController,
      obscureText: _obscurePassword,
      decoration: InputDecoration(
        labelText: 'Password',
        prefixIcon: Icon(Icons.lock_outline),
        suffixIcon: IconButton(
          icon: Icon(
            _obscurePassword ? Icons.visibility : Icons.visibility_off,
          ),
          onPressed: () {
            setState(() => _obscurePassword = !_obscurePassword);
          },
        ),
      ),
      validator: (value) {
        if (value == null || value.isEmpty) {
          return 'Please enter a password';
        }
        if (value.length < 6) {
          return 'Password must be at least 6 characters';
        }
        return null;
      },
    );
  }

  Widget _buildConfirmPasswordField() {
    return TextFormField(
      controller: _confirmPasswordController,
      obscureText: _obscureConfirmPassword,
      decoration: InputDecoration(
        labelText: 'Confirm Password',
        prefixIcon: Icon(Icons.lock_outline),
        suffixIcon: IconButton(
          icon: Icon(
            _obscureConfirmPassword ? Icons.visibility : Icons.visibility_off,
          ),
          onPressed: () {
            setState(() => _obscureConfirmPassword = !_obscureConfirmPassword);
          },
        ),
      ),
      validator: (value) {
        if (value == null || value.isEmpty) {
          return 'Please confirm your password';
        }
        return null;
      },
    );
  }

  Widget _buildPhoneField() {
    return TextFormField(
      controller: _phoneController,
      keyboardType: TextInputType.phone,
      decoration: InputDecoration(
        labelText: 'Phone number',
        prefixIcon: Icon(Icons.phone_outlined),
      ),
      validator: (value) {
        if (value == null || value.isEmpty) {
          return 'Please enter your phone number';
        }
        if (value.length < 10) {
          return 'Please enter a valid phone number';
        }
        return null;
      },
    );
  }

  Widget _buildAddressField() {
    return TextFormField(
      controller: _addressController,
      decoration: InputDecoration(
        labelText: 'Complete address',
        prefixIcon: Icon(Icons.home_outlined),
      ),
      validator: (value) {
        if (value == null || value.isEmpty) {
          return 'Please enter your address';
        }
        return null;
      },
    );
  }

  Widget _buildIdPhotoUploader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Valid ID Photo',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Color(0xFF36454F),
          ),
        ),
        SizedBox(height: 8),
        Container(
          padding: EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: (_idPhotoFile == null && _idPhotoBytes == null) ? Color(0xFF99272D) : Color(0xFFCDD5DF),
            ),
            color: Colors.white,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_idPhotoFile != null || _idPhotoBytes != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: kIsWeb && _idPhotoBytes != null
                      ? Image.memory(
                          _idPhotoBytes!,
                          height: 160,
                          width: double.infinity,
                          fit: BoxFit.cover,
                        )
                      : _idPhotoFile != null
                          ? Image.file(
                              _idPhotoFile!,
                              height: 160,
                              width: double.infinity,
                              fit: BoxFit.cover,
                            )
                          : SizedBox.shrink(),
                )
              else
                Column(
                  children: [
                    Icon(Icons.badge_outlined, size: 48, color: Color(0xFF99272D)),
                    SizedBox(height: 8),
                    Text(
                      'Upload a clear photo of your valid ID.\nPNG or JPG formats are accepted.',
                      style: TextStyle(color: Color(0xFF36454F)),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isLoading ? null : _pickIdPhoto,
                      icon: Icon(Icons.upload_file),
                      label: Text(_idPhotoFile == null ? 'Upload ID Photo' : 'Replace Photo'),
                      style: OutlinedButton.styleFrom(
                        padding: EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  if (_idPhotoFile != null || _idPhotoBytes != null) ...[
                    SizedBox(width: 8),
                    IconButton(
                      onPressed: _isLoading
                          ? null
                          : () {
                              setState(() {
                                _idPhotoFile = null;
                                _idPhotoBytes = null;
                              });
                            },
                      icon: Icon(Icons.delete_outline, color: Color(0xFF99272D)),
                      tooltip: 'Remove photo',
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBarangayDropdown() {
    if (_barangaysLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Text('Loading barangays…', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }
    if (_barangayItems.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text(
          'No barangays available. Please contact your administrator.',
          style: TextStyle(color: Colors.red, fontSize: 13),
        ),
      );
    }
    return DropdownButtonFormField<String>(
      initialValue: _selectedBarangay,
      decoration: const InputDecoration(
        labelText: 'Select barangay',
        prefixIcon: Icon(Icons.location_on_outlined),
      ),
      items: _barangayItems.map((b) {
        final name = b['name'] as String? ?? '';
        return DropdownMenuItem<String>(value: name, child: Text(name));
      }).toList(),
      onChanged: (String? newValue) {
        setState(() => _selectedBarangay = newValue);
      },
      validator: (value) {
        if (value == null || value.isEmpty) {
          return 'Please select your barangay';
        }
        return null;
      },
    );
  }

  Widget _buildRoleSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Register as',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF36454F)),
        ),
        Row(
          children: [
            Expanded(
              child: RadioListTile<String>(
                title: Text('Resident'),
                value: 'user',
                groupValue: _role,
                activeColor: Color(0xFF99272D),
                onChanged: (v) => setState(() => _role = v!),
              ),
            ),
            Expanded(
              child: RadioListTile<String>(
                title: Text('Barangay Admin'),
                value: 'admin',
                groupValue: _role,
                activeColor: Color(0xFF99272D),
                onChanged: (v) => setState(() => _role = v!),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildVerificationMethodSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Verify identity with',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF36454F)),
        ),
        Row(
          children: [
            Expanded(
              child: RadioListTile<String>(
                title: Text('Email OTP'),
                value: 'email',
                groupValue: _verificationMethod,
                activeColor: Color(0xFF99272D),
                onChanged: (v) => setState(() => _verificationMethod = v!),
              ),
            ),
            Expanded(
              child: RadioListTile<String>(
                title: Text('Phone SMS'),
                value: 'phone',
                groupValue: _verificationMethod,
                activeColor: Color(0xFF99272D),
                onChanged: (v) => setState(() => _verificationMethod = v!),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSignupButton() {
    return ElevatedButton(
      onPressed: _isLoading ? null : _submitForm,
      child: _isLoading
          ? SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 2,
              ),
            )
          : Text(
              'Create Account',
            style: Theme.of(context).textTheme.labelLarge,
            ),
    );
  }

  Widget _buildLoginLink() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text('Already have an account?'),
        SizedBox(width: 5),
        TextButton(
          onPressed: () {
            Navigator.pushReplacementNamed(context, '/login');
          },
          child: Text(
            'Sign In',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }
}