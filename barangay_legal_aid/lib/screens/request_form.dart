import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:barangay_legal_aid/services/api_service.dart';

class RequestForm extends StatefulWidget {
  final String userBarangay;
  final String? preselectedDocumentType;

  const RequestForm({super.key, 
    required this.userBarangay,
    this.preselectedDocumentType,
  });

  @override
  _RequestFormState createState() => _RequestFormState();
}

class _RequestFormState extends State<RequestForm> {
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
              print('Loaded barangay_id: $_barangayId');
              return;
            }
          }
        } catch (e) {
          print('Error fetching user barangay_id: $e');
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
      } catch (e) {
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
          print('Matched barangay by name: $_barangayId');
        }
      } catch (e) {
        print('Error matching barangay by name: $e');
      }
    } catch (e) {
      print('Error loading barangay_id: $e');
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Please select a document type'),
            backgroundColor: Color(0xFF99272D),
          ),
        );
        return;
      }

      if (_barangayId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Unable to determine barangay. Please try again.'),
            backgroundColor: Color(0xFF99272D),
          ),
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

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Request submitted successfully!'),
            backgroundColor: Color(0xFF36454F),
            duration: Duration(seconds: 3),
          ),
        );

        Navigator.pop(context, true);
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error submitting request: ${e.toString().replaceAll('Exception: ', '')}'),
            backgroundColor: Color(0xFF99272D),
            duration: Duration(seconds: 4),
          ),
        );
      } finally {
        setState(() => _isLoading = false);
      }
    }
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
                color: Colors.white.withOpacity(0.2),
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
              'Request a document from ${widget.userBarangay}',
              style: TextStyle(
                fontSize: 16,
                color: Colors.white.withOpacity(0.9),
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
    return ElevatedButton(
      onPressed: _isLoading ? null : _submitRequest,
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
              style: Theme.of(context).textTheme.labelLarge,
            ),
    );
  }
}