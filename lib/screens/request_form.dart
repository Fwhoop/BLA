import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:barangay_legal_aid/services/api_service.dart';
import 'package:barangay_legal_aid/utils/top_snack.dart';

class RequestForm extends StatefulWidget {
  final String userBarangay;
  final String? preselectedDocumentType;

  const RequestForm({super.key, 
    required this.userBarangay,
    this.preselectedDocumentType,
  });

  @override
  RequestFormState createState() => RequestFormState();
}

// Requirements that the resident must bring when picking up the document.
const Map<String, List<String>> _docRequirements = {
  'Barangay Clearance': [
    'Valid government-issued ID (PhilSys, Driver\'s License, Passport, UMID)',
    'Proof of residency (utility bill, lease contract, or affidavit)',
    '1 piece 1×1 or 2×2 ID photo',
    'Completed application form (available at barangay hall)',
    'Payment of processing fee (if applicable)',
  ],
  'Certificate of Residency': [
    'Valid government-issued ID',
    'Proof of address (utility bill, lease contract, or affidavit of residency)',
    'Must have resided in the barangay for at least 6 months',
    '1 piece 1×1 ID photo',
  ],
  'Certificate of Good Moral Character': [
    'Valid government-issued ID',
    '1 piece 2×2 ID photo',
    'Completed application form',
    '2 character references from community members',
  ],
  'Certificate of Indigency': [
    'Valid government-issued ID',
    'Proof of low income or unemployment (payslip, sworn statement)',
    'Barangay Clearance (may be required)',
  ],
  'Certificate of No Property': [
    'Valid government-issued ID',
    'Sworn affidavit that you do not own real property',
    '1 piece 1×1 ID photo',
  ],
  'Certificate of No Income': [
    'Valid government-issued ID',
    'Sworn affidavit of no regular income',
    'Supporting proof (e.g., unemployment record)',
  ],
  'Certificate of Live Birth': [
    'Hospital/birth record or CRVS print-out',
    'Valid government-issued ID of parent/guardian',
    'Marriage certificate of parents (if applicable)',
  ],
  'Certificate of Death': [
    'Hospital death certificate or medical certificate of death',
    'Valid government-issued ID of next of kin',
    'Birth certificate of deceased (if available)',
  ],
  'Certificate of Marriage': [
    'Valid government-issued IDs of both parties',
    'Birth certificates of both parties',
    'CENOMAR (Certificate of No Marriage) from PSA',
    'Completed application form',
    'Processing fee (if applicable)',
  ],
  'Certificate of Single Status': [
    'Valid government-issued ID',
    'CENOMAR from PSA (if available)',
    '1 piece 2×2 ID photo',
    'Completed application form',
  ],
};

class RequestFormState extends State<RequestForm> {
  final _formKey = GlobalKey<FormState>();
  final _apiService = ApiService();

  final TextEditingController _purposeController = TextEditingController();
  String? _selectedDocumentType;
  bool _isLoading = false;
  int? _barangayId;

  final List<String> _documentTypes = [
    'Barangay Clearance',
    'Certificate of Residency',
    'Certificate of Good Moral Character',
    'Certificate of Indigency',
    'Certificate of No Property',
    'Certificate of No Income',
    'Certificate of Live Birth',
    'Certificate of Death',
    'Certificate of Marriage',
    'Certificate of Single Status',
  ];

  @override
  void initState() {
    super.initState();
    _selectedDocumentType = widget.preselectedDocumentType;
    _loadBarangayId();
  }

  Future<void> _loadBarangayId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final accessToken = prefs.getString('access_token');
      if (accessToken != null && accessToken.isNotEmpty) {
        try {
          final userUrl = Uri.parse('http://127.0.0.1:8000/auth/me');
          final userResponse = await http.get(
            userUrl,
            headers: {
              'Authorization': 'Bearer $accessToken',
              'Content-Type': 'application/json',
            },
          ).timeout(Duration(seconds: 5));

          if (userResponse.statusCode == 200) {
            final userData = jsonDecode(userResponse.body);
            if (userData['barangay_id'] != null) {
              setState(() {
                _barangayId = userData['barangay_id'] as int;
              });
              return;
            }
          }
        } catch (_) {
          // /auth/me failed; try parse or barangays list
        }
      }

      try {
        final barangayIdInt = int.tryParse(widget.userBarangay);
        if (barangayIdInt != null) {
          setState(() {
            _barangayId = barangayIdInt;
          });
          return;
        }
      } catch (_) {
        // User barangay_id not from /auth/me; try parse or barangays list
      }
      
      try {
        final barangays = await _apiService.getBarangays();
        final matchingBarangay = barangays.firstWhere(
          (b) {
            final name = b['name'] as String? ?? '';
            return name == widget.userBarangay || 
                   widget.userBarangay.contains(name) ||
                   name.contains(widget.userBarangay);
          },
          orElse: () => barangays.isNotEmpty ? barangays.first : {},
        );
        if (matchingBarangay.isNotEmpty && matchingBarangay['id'] != null) {
          setState(() {
            _barangayId = matchingBarangay['id'] as int;
          });
        }
      } catch (_) {
        // Barangay name match failed
      }
    } catch (_) {
      // _loadBarangayId failed; form may still submit if backend accepts
    }
  }

  @override
  void dispose() {
    _purposeController.dispose();
    super.dispose();
  }

  Future<void> _submitRequest() async {
    if (_formKey.currentState!.validate()) {
      if (_selectedDocumentType == null) {
        showTopSnack(
          context,
          message: 'Please select a document type',
          backgroundColor: Color(0xFF99272D),
          icon: Icons.warning_amber_rounded,
        );
        return;
      }

      if (_barangayId == null) {
        showTopSnack(
          context,
          message: 'Unable to determine barangay. Please try again.',
          backgroundColor: Color(0xFF99272D),
          icon: Icons.warning_amber_rounded,
        );
        return;
      }

      setState(() => _isLoading = true);

      try {
        await _apiService.createRequest(
          barangayId: _barangayId!,
          documentType: _selectedDocumentType!,
          purpose: _purposeController.text.trim(),
        );
        if (!mounted) return;
        showTopSnack(
          context,
          message: 'Request submitted successfully!',
          backgroundColor: Color(0xFF36454F),
          icon: Icons.check_circle_outline,
          duration: Duration(seconds: 3),
        );

        await _showRequirementsSheet(_selectedDocumentType!);
        if (mounted) Navigator.pop(context, true);
      } catch (e) {
        if (!mounted) return;
        showTopSnack(
          context,
          message: 'Error: ${e.toString().replaceAll('Exception: ', '')}',
          backgroundColor: Color(0xFF99272D),
          icon: Icons.error_outline,
          duration: Duration(seconds: 4),
        );
      } finally {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _showRequirementsSheet(String documentType) async {
    final reqs = _docRequirements[documentType] ?? [
      'Valid government-issued ID',
      'Completed application form (available at barangay hall)',
    ];

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => Padding(
        padding: EdgeInsets.fromLTRB(24, 20, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            SizedBox(height: 16),
            Row(
              children: [
                Icon(Icons.assignment_turned_in, color: Color(0xFF36454F), size: 24),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'What to Bring',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF36454F),
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 6),
            Text(
              'Your request for "$documentType" has been submitted. Please prepare the following when picking it up at the barangay hall:',
              style: TextStyle(fontSize: 13, color: Color(0xFF36454F).withValues(alpha: 0.7)),
            ),
            SizedBox(height: 16),
            ...reqs.map((req) => Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.check_circle, color: Color(0xFF99272D), size: 18),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(req, style: TextStyle(fontSize: 14)),
                  ),
                ],
              ),
            )),
            SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(sheetCtx),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Color(0xFF99272D),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: Text('Got it!'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Document Request'),
        backgroundColor: Color(0xFF99272D),
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 600),
            child: SingleChildScrollView(
              padding: EdgeInsets.all(20),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildHeader(),
                    SizedBox(height: 24),
                    _buildDocumentTypeDropdown(),
                    SizedBox(height: 16),
                    _buildPurposeField(),
                    SizedBox(height: 24),
                    _buildSubmitButton(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
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
                Icons.description,
                size: 50,
                color: Colors.white,
              ),
            ),
            SizedBox(height: 16),
            Text(
              'Document Request',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Fill out the form below to submit your barangay document request.',
              style: TextStyle(
                fontSize: 15,
                color: Colors.white.withValues(alpha:0.9),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDocumentTypeDropdown() {
    return DropdownButtonFormField<String>(
      initialValue: _selectedDocumentType,
      decoration: InputDecoration(
        labelText: 'Document Type',
        prefixIcon: Icon(Icons.description_outlined),
      ),
      items: _documentTypes.map((String documentType) {
        return DropdownMenuItem<String>(
          value: documentType,
          child: Text(documentType),
        );
      }).toList(),
      onChanged: (String? newValue) {
        setState(() => _selectedDocumentType = newValue);
      },
      validator: (value) {
        if (value == null) {
          return 'Please select a document type';
        }
        return null;
      },
    );
  }

  Widget _buildPurposeField() {
    return TextFormField(
      controller: _purposeController,
      maxLines: 3,
      decoration: InputDecoration(
        labelText: 'Purpose of Request',
        hintText: 'Please specify the purpose for requesting this document...',
        prefixIcon: Icon(Icons.info_outline),
      ),
      validator: (value) {
        if (value == null || value.isEmpty) {
          return 'Please specify the purpose';
        }
        if (value.length < 10) {
          return 'Please provide a more detailed purpose';
        }
        return null;
      },
    );
  }

  Widget _buildSubmitButton() {
    return Center(
      child: SizedBox(
        width: 220,
        child: ElevatedButton(
          onPressed: _isLoading ? null : _submitRequest,
          style: ElevatedButton.styleFrom(
            backgroundColor: Color(0xFF99272D),
            foregroundColor: Colors.white,
            padding: EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
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
                  'Submit Request',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
        ),
      ),
    );
  }
}