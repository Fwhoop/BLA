import 'package:flutter/material.dart';

class RequestForm extends StatefulWidget {
  final String userBarangay;

  const RequestForm({required this.userBarangay});

  @override
  _RequestFormState createState() => _RequestFormState();
}

class _RequestFormState extends State<RequestForm> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _purposeController = TextEditingController();
  String? _selectedDocumentType;
  bool _isLoading = false;

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

      setState(() => _isLoading = true);

      try {
        // Simulate API call
        await Future.delayed(Duration(seconds: 2));

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Request submitted successfully!'),
            backgroundColor: Color(0xFF36454F),
            duration: Duration(seconds: 3),
          ),
        );

        Navigator.pop(context);
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error submitting request: $e'),
            backgroundColor: Color(0xFF99272D),
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
      value: _selectedDocumentType,
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