import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import 'package:signature/signature.dart';
import 'package:barangay_legal_aid/config/env_config.dart';
import 'package:barangay_legal_aid/services/api_service.dart';
import 'package:barangay_legal_aid/utils/document_templates.dart';
import 'package:barangay_legal_aid/utils/top_snack.dart';

// Document types that can be generated
const _kGeneratableTypes = {
  'Barangay Clearance',
  'Certificate of Residency',
  'Certificate of Good Moral Character',
  'Certificate of Indigency',
  'Certificate of No Income',
  'Certificate of No Property',
  'Certificate of Single Status',
};

bool isGeneratableDocumentType(String? type) =>
    type != null && _kGeneratableTypes.contains(type);

class DocumentEditorScreen extends StatefulWidget {
  final Map<String, dynamic> request;

  const DocumentEditorScreen({super.key, required this.request});

  @override
  DocumentEditorScreenState createState() => DocumentEditorScreenState();
}

class DocumentEditorScreenState extends State<DocumentEditorScreen>
    with TickerProviderStateMixin {
  bool _loading = true;
  bool _generating = false;
  bool _showPreview = false;

  // Asset bytes
  Uint8List? _logoLeftBytes;
  Uint8List? _logoRightBytes;
  Uint8List? _signatureBytes;

  // Stamps and text overlays placed interactively on the preview
  final List<SignatureStamp> _stamps = [];
  final List<TextOverlay> _textOverlays = [];
  Uint8List? _rasterizedPage; // rasterized base page for interactive preview

  // Requester data (loaded from API)
  String _fullName = '';
  String _firstName = '';
  String _barangayName = '';
  String _municipality = '';
  String _province = '';
  String _address = '';

  // Editable field controllers
  final _titleCtrl = TextEditingController(text: 'Mr.');
  final _civilStatusCtrl = TextEditingController(text: 'Single');
  final _purposeCtrl = TextEditingController();
  final _dateDayCtrl = TextEditingController();
  final _dateMonthCtrl = TextEditingController();
  final _dateYearCtrl = TextEditingController();
  final _punongNameCtrl = TextEditingController();
  final _communityTaxCtrl = TextEditingController();
  final _taxIssuedAtCtrl = TextEditingController();
  final _taxIssuedOnCtrl = TextEditingController();
  final _receiptNoCtrl = TextEditingController();
  final _receiptIssuedAtCtrl = TextEditingController();
  final _receiptIssuedOnCtrl = TextEditingController();
  String _pronoun = 'he';
  String _pronounPossessive = 'his';
  String _gender = 'male';

  String get _documentType =>
      widget.request['document_type'] as String? ?? '';

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _dateDayCtrl.text = ordinalDate(now.day);
    _dateMonthCtrl.text = _monthName(now.month);
    _dateYearCtrl.text = now.year.toString();
    _purposeCtrl.text =
        widget.request['purpose'] as String? ?? 'FOR ANY LEGAL PURPOSE';
    _loadData();
  }

  @override
  void dispose() {
    for (final c in [
      _titleCtrl, _civilStatusCtrl, _purposeCtrl, _dateDayCtrl,
      _dateMonthCtrl, _dateYearCtrl, _punongNameCtrl, _communityTaxCtrl,
      _taxIssuedAtCtrl, _taxIssuedOnCtrl, _receiptNoCtrl,
      _receiptIssuedAtCtrl, _receiptIssuedOnCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  String _monthName(int m) => const [
        'January', 'February', 'March', 'April', 'May', 'June',
        'July', 'August', 'September', 'October', 'November', 'December',
      ][m - 1];

  Future<void> _loadData() async {
    // Capture ApiService before async gaps
    final api = Provider.of<ApiService>(context, listen: false);
    try {
      // 1. Current admin info
      final me = await api.getCurrentUser();
      if (me != null) {
        _punongNameCtrl.text =
            '${me['first_name'] ?? ''} ${me['last_name'] ?? ''}'.trim();
        final bid = me['barangay_id'] as int?;
        if (bid != null) {
          final bd = await api.getBarangay(bid);
          _barangayName = bd['name'] as String? ?? '';
          final logoUrl = bd['logo_url'] as String?;
          final logoSecUrl = bd['logo_url_secondary'] as String?;
          if (logoUrl != null && logoUrl.isNotEmpty) {
            _logoLeftBytes = await _fetchImageBytes('$apiBaseUrl$logoUrl');
          }
          if (logoSecUrl != null && logoSecUrl.isNotEmpty) {
            _logoRightBytes = await _fetchImageBytes('$apiBaseUrl$logoSecUrl');
          }
        }
        final sigPath = me['signature_path'] as String?;
        if (sigPath != null && sigPath.isNotEmpty) {
          _signatureBytes = await _fetchImageBytes('$apiBaseUrl$sigPath');
        }
      }

      // 2. Requester user profile
      final requesterId = widget.request['requester_id'] as int?;
      if (requesterId != null) {
        final user = await api.getUser(requesterId);
        if (user != null) {
          final fn = user['first_name'] as String? ?? '';
          final mn = user['middle_name'] as String? ?? '';
          final ln = user['last_name'] as String? ?? '';
          final mi = mn.isNotEmpty ? '${mn[0].toUpperCase()}.' : '';
          _fullName = [fn, if (mi.isNotEmpty) mi, ln]
              .where((p) => p.isNotEmpty)
              .join(' ');
          _firstName = fn;

          final purok = user['purok'] as String? ?? '';
          final street = user['street_name'] as String? ?? '';
          _address = [purok, street].where((s) => s.isNotEmpty).join(', ');
          if (_address.isEmpty) _address = user['address'] as String? ?? '';

          _municipality = user['city'] as String? ?? '';
          _province = user['province'] as String? ?? '';
          final bname = user['barangay_name'] as String?;
          if (bname != null && bname.isNotEmpty) _barangayName = bname;
        }
      }
    } catch (_) {
      // proceed with whatever was loaded
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<Uint8List?> _fetchImageBytes(String url) async {
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) return response.bodyBytes;
    } catch (_) {}
    return null;
  }

  DocumentData _buildDocumentData() => DocumentData(
        title: _titleCtrl.text,
        fullName: _fullName.isNotEmpty
            ? _fullName
            : (widget.request['requester_name'] as String? ?? ''),
        firstName: _firstName,
        civilStatus: _civilStatusCtrl.text,
        gender: _gender,
        pronoun: _pronoun,
        pronounPossessive: _pronounPossessive,
        address: _address.isNotEmpty ? _address : '',
        barangayName: _barangayName,
        municipality: _municipality,
        province: _province,
        purpose: _purposeCtrl.text.isNotEmpty
            ? _purposeCtrl.text
            : 'FOR ANY LEGAL PURPOSE',
        dateDay: _dateDayCtrl.text,
        dateMonth: _dateMonthCtrl.text,
        dateYear: _dateYearCtrl.text,
        punongBarangayName: _punongNameCtrl.text,
        communityTaxNo: _communityTaxCtrl.text,
        taxIssuedAt: _taxIssuedAtCtrl.text,
        taxIssuedOn: _taxIssuedOnCtrl.text,
        officialReceiptNo: _receiptNoCtrl.text,
        receiptIssuedAt: _receiptIssuedAtCtrl.text,
        receiptIssuedOn: _receiptIssuedOnCtrl.text,
      );

  /// Generates the final PDF with stamps + text overlays baked in (used when sending).
  Future<Uint8List> _generatePdf() => generateDocument(
        _documentType,
        _buildDocumentData(),
        logoLeftBytes: _logoLeftBytes,
        logoRightBytes: _logoRightBytes,
        signatureBytes: _signatureBytes,
        stamps: _stamps,
        textOverlays: _textOverlays,
      );

  /// Generates the base PDF (no stamps) and rasterizes it for the interactive preview.
  Future<void> _preview() async {
    setState(() => _generating = true);
    try {
      final baseBytes = await generateDocument(
        _documentType,
        _buildDocumentData(),
        logoLeftBytes: _logoLeftBytes,
        logoRightBytes: _logoRightBytes,
        signatureBytes: _signatureBytes,
      );
      final pages = await Printing.raster(baseBytes, dpi: 150).toList();
      if (!mounted) return;
      if (pages.isNotEmpty) {
        final png = await pages.first.toPng();
        if (!mounted) return;
        setState(() {
          _rasterizedPage = png;
          _showPreview = true;
        });
      }
    } catch (e) {
      if (!mounted) return;
      showTopSnack(context,
          message: 'Preview error: ${e.toString().replaceAll('Exception: ', '')}',
          backgroundColor: const Color(0xFF99272D),
          icon: Icons.error_outline);
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _generateAndSend() async {
    setState(() => _generating = true);
    // Capture context-dependent refs before async
    final api = Provider.of<ApiService>(context, listen: false);
    final requestId = widget.request['id'] as int;
    try {
      final bytes = await _generatePdf();
      final filename =
          '${_documentType.toLowerCase().replaceAll(' ', '_')}.pdf';
      await api.uploadRequestDocument(requestId, bytes, filename);
      if (!mounted) return;
      showTopSnack(context,
          message: 'Document generated and sent!',
          backgroundColor: const Color(0xFF36454F),
          icon: Icons.check_circle_outline,
          duration: const Duration(seconds: 3));
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      showTopSnack(context,
          message: e.toString().replaceAll('Exception: ', ''),
          backgroundColor: const Color(0xFF99272D),
          icon: Icons.error_outline);
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  // ─── Text overlay editor ───────────────────────────────────────────────────

  Future<void> _showAddTextSheet({TextOverlay? existing, int? index}) async {
    final textCtrl = TextEditingController(text: existing?.text ?? '');
    double fontSize = existing?.fontSize ?? 10;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.only(
            left: 16, right: 16, top: 16,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(existing == null ? 'Add Text' : 'Edit Text',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              TextField(
                controller: textCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Text (e.g. Juan dela Cruz)',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('Font size: ', style: TextStyle(fontSize: 13)),
                  Text('${fontSize.round()} pt',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                ],
              ),
              Slider(
                value: fontSize,
                min: 7,
                max: 24,
                divisions: 17,
                activeColor: const Color(0xFF99272D),
                onChanged: (v) => setSheet(() => fontSize = v),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF99272D),
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () {
                    final t = textCtrl.text.trim();
                    if (t.isEmpty) return;
                    setState(() {
                      final overlay = TextOverlay(
                        text: t,
                        xFraction: existing?.xFraction ?? 0.5,
                        yFraction: existing?.yFraction ?? 0.5,
                        fontSize: fontSize,
                      );
                      if (index != null) {
                        _textOverlays[index] = overlay;
                      } else {
                        _textOverlays.add(overlay);
                      }
                    });
                    Navigator.pop(ctx);
                  },
                  child: Text(existing == null ? 'Add' : 'Save'),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    textCtrl.dispose();
  }

  // ─── Stamp picker ──────────────────────────────────────────────────────────

  Future<void> _showAddStampSheet() async {
    final sigCtrl = SignatureController(
      penStrokeWidth: 2,
      penColor: Colors.black,
      exportBackgroundColor: Colors.transparent,
    );
    Uint8List? uploadedBytes;
    final tabCtrl = TabController(length: 2, vsync: this);

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.only(
            left: 16, right: 16, top: 16,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text('Add Signature Stamp',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const Text(
                'Draw or upload a signature. It will appear in the center — drag it anywhere on the document.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 12),
              TabBar(
                controller: tabCtrl,
                labelColor: const Color(0xFF99272D),
                unselectedLabelColor: Colors.grey,
                indicatorColor: const Color(0xFF99272D),
                tabs: const [Tab(text: 'Draw'), Tab(text: 'Upload')],
              ),
              SizedBox(
                height: 180,
                child: TabBarView(
                  controller: tabCtrl,
                  children: [
                    // Draw tab
                    Column(
                      children: [
                        Expanded(
                          child: Container(
                            margin: const EdgeInsets.only(top: 8),
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey[300]!),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Signature(
                                controller: sigCtrl,
                                backgroundColor: Colors.white,
                              ),
                            ),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: sigCtrl.clear,
                          icon: const Icon(Icons.clear, size: 14),
                          label: const Text('Clear'),
                          style: TextButton.styleFrom(foregroundColor: Colors.grey),
                        ),
                      ],
                    ),
                    // Upload tab
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (uploadedBytes != null)
                          Image.memory(uploadedBytes!, height: 80, fit: BoxFit.contain),
                        const SizedBox(height: 8),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.upload_file, size: 16),
                          label: Text(uploadedBytes == null ? 'Choose Image' : 'Replace'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF99272D),
                            foregroundColor: Colors.white,
                          ),
                          onPressed: () async {
                            final picked = await ImagePicker().pickImage(
                                source: ImageSource.gallery, imageQuality: 90);
                            if (picked != null) {
                              final b = await picked.readAsBytes();
                              setSheet(() => uploadedBytes = b);
                            }
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.add),
                  label: const Text('Add Stamp'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF99272D),
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () async {
                    Uint8List? bytes;
                    if (tabCtrl.index == 1 && uploadedBytes != null) {
                      bytes = uploadedBytes;
                    } else if (tabCtrl.index == 0 && sigCtrl.isNotEmpty) {
                      bytes = await sigCtrl.toPngBytes();
                    }
                    if (bytes == null || !ctx.mounted) return;
                    setState(() {
                      _stamps.add(SignatureStamp(
                        bytes: bytes!,
                        xFraction: 0.5,
                        yFraction: 0.5,
                      ));
                    });
                    Navigator.pop(ctx);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );

    sigCtrl.dispose();
    tabCtrl.dispose();
  }

  // ─── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Generate Document'),
          backgroundColor: const Color(0xFF99272D),
          foregroundColor: Colors.white,
        ),
        body: const Center(
            child: CircularProgressIndicator(color: Color(0xFF99272D))),
      );
    }

    if (_showPreview && _rasterizedPage != null) {
      final displayW = MediaQuery.of(context).size.width;
      final displayH = displayW * 1.4142; // A4 aspect ratio

      return Scaffold(
        appBar: AppBar(
          title: const Text('Preview'),
          backgroundColor: const Color(0xFF99272D),
          foregroundColor: Colors.white,
          actions: [
            IconButton(
              icon: const Icon(Icons.draw),
              tooltip: 'Add Signature Stamp',
              onPressed: _showAddStampSheet,
            ),
            IconButton(
              icon: const Icon(Icons.text_fields),
              tooltip: 'Add Text',
              onPressed: () => _showAddTextSheet(),
            ),
            TextButton(
              onPressed: () => setState(() => _showPreview = false),
              child: const Text('Edit', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: SizedBox(
                  width: displayW,
                  height: displayH,
                  child: Stack(
                    children: [
                      // Rasterized base page
                      Image.memory(
                        _rasterizedPage!,
                        width: displayW,
                        height: displayH,
                        fit: BoxFit.fill,
                      ),
                      // Draggable text overlays
                      ..._textOverlays.asMap().entries.map((entry) {
                        final idx = entry.key;
                        final o = entry.value;
                        final scale = displayW / 595.28;
                        final flutterSize = o.fontSize * scale;
                        final left = (o.xFraction * displayW)
                            .clamp(0.0, displayW - 160);
                        final top = (o.yFraction * displayH)
                            .clamp(0.0, displayH - flutterSize * 2);
                        return Positioned(
                          left: left,
                          top: top,
                          child: GestureDetector(
                            onPanUpdate: (d) {
                              setState(() {
                                _textOverlays[idx] = TextOverlay(
                                  text: o.text,
                                  xFraction: (o.xFraction + d.delta.dx / displayW).clamp(0.0, 1.0),
                                  yFraction: (o.yFraction + d.delta.dy / displayH).clamp(0.0, 1.0),
                                  fontSize: o.fontSize,
                                );
                              });
                            },
                            onDoubleTap: () => _showAddTextSheet(existing: o, index: idx),
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: Colors.blue.withValues(alpha: 0.5),
                                    ),
                                  ),
                                  child: Text(
                                    o.text,
                                    style: TextStyle(
                                      fontSize: flutterSize,
                                      color: Colors.black,
                                    ),
                                  ),
                                ),
                                Positioned(
                                  top: -8,
                                  right: -8,
                                  child: GestureDetector(
                                    onTap: () => setState(() => _textOverlays.removeAt(idx)),
                                    child: Container(
                                      width: 18,
                                      height: 18,
                                      decoration: const BoxDecoration(
                                        color: Colors.red,
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(Icons.close, size: 12, color: Colors.white),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                      // Draggable stamp overlays
                      ..._stamps.asMap().entries.map((entry) {
                        final idx = entry.key;
                        final s = entry.value;
                        const stampW = 110.0;
                        final left = (s.xFraction * displayW - stampW / 2)
                            .clamp(0.0, displayW - stampW);
                        final top = (s.yFraction * displayH - 20.0)
                            .clamp(0.0, displayH - 50.0);
                        return Positioned(
                          left: left,
                          top: top,
                          child: GestureDetector(
                            onPanUpdate: (d) {
                              setState(() {
                                _stamps[idx] = SignatureStamp(
                                  bytes: s.bytes,
                                  xFraction: (s.xFraction + d.delta.dx / displayW)
                                      .clamp(0.0, 1.0),
                                  yFraction: (s.yFraction + d.delta.dy / displayH)
                                      .clamp(0.0, 1.0),
                                  widthPoints: s.widthPoints,
                                );
                              });
                            },
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                Image.memory(s.bytes,
                                    width: stampW, fit: BoxFit.contain),
                                Positioned(
                                  top: -8,
                                  right: -8,
                                  child: GestureDetector(
                                    onTap: () =>
                                        setState(() => _stamps.removeAt(idx)),
                                    child: Container(
                                      width: 20,
                                      height: 20,
                                      decoration: const BoxDecoration(
                                        color: Colors.red,
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(Icons.close,
                                          size: 13, color: Colors.white),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _generating ? null : _generateAndSend,
                  icon: _generating
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.send),
                  label: const Text('Generate & Send'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF99272D),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Generate: $_documentType'),
        backgroundColor: const Color(0xFF99272D),
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildAutoFilledSection(),
                  const SizedBox(height: 20),
                  _buildEditableSection(),
                  const SizedBox(height: 28),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _generating ? null : _preview,
                          icon: const Icon(Icons.preview),
                          label: const Text('Preview'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF99272D),
                            side: const BorderSide(
                                color: Color(0xFF99272D)),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _generating ? null : _generateAndSend,
                          icon: _generating
                              ? const SizedBox(
                                  height: 16,
                                  width: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.send),
                          label: const Text('Generate & Send'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF99272D),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAutoFilledSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.person, size: 18, color: Color(0xFF99272D)),
                SizedBox(width: 8),
                Text('Auto-filled from requester\'s profile',
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF99272D))),
              ],
            ),
            const SizedBox(height: 12),
            _readonlyRow('Full Name',
                _fullName.isNotEmpty
                    ? _fullName
                    : (widget.request['requester_name'] as String? ?? '—')),
            _readonlyRow('Address',
                _address.isNotEmpty ? _address : '—'),
            _readonlyRow('Barangay',
                _barangayName.isNotEmpty ? _barangayName : '—'),
            _readonlyRow('Municipality',
                _municipality.isNotEmpty ? _municipality : '—'),
            _readonlyRow('Province',
                _province.isNotEmpty ? _province : '—'),
          ],
        ),
      ),
    );
  }

  Widget _readonlyRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(label,
                style: const TextStyle(fontSize: 13, color: Colors.grey)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }

  Widget _buildEditableSection() {
    final type = _documentType;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.edit, size: 18, color: Color(0xFF99272D)),
                SizedBox(width: 8),
                Text('Fill in the blanks',
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF99272D))),
              ],
            ),
            const SizedBox(height: 16),

            // Punong Barangay name (all docs)
            _field(_punongNameCtrl, 'Punong Barangay Name'),
            const SizedBox(height: 12),

            // Date (all docs)
            Row(children: [
              Expanded(child: _field(_dateDayCtrl, 'Day (e.g. 3rd)')),
              const SizedBox(width: 8),
              Expanded(child: _field(_dateMonthCtrl, 'Month')),
              const SizedBox(width: 8),
              Expanded(child: _field(_dateYearCtrl, 'Year')),
            ]),
            const SizedBox(height: 12),

            // Title (some docs)
            if (_needsTitle(type)) ...[
              _dropdownField(
                label: 'Title',
                value: _titleCtrl.text,
                items: const ['Mr.', 'Mrs.', 'Ms.'],
                onChanged: (v) =>
                    setState(() => _titleCtrl.text = v ?? 'Mr.'),
              ),
              const SizedBox(height: 12),
            ],

            // Civil status (most docs)
            if (_needsCivilStatus(type)) ...[
              _dropdownField(
                label: 'Civil Status',
                value: _civilStatusCtrl.text,
                items: const ['Single', 'Married', 'Widowed', 'Separated'],
                onChanged: (v) =>
                    setState(() => _civilStatusCtrl.text = v ?? 'Single'),
              ),
              const SizedBox(height: 12),
            ],

            // Pronoun (most docs)
            if (_needsPronoun(type)) ...[
              _dropdownField(
                label: 'Gender Pronoun',
                value: _pronoun,
                items: const ['he', 'she'],
                onChanged: (v) => setState(() {
                  _pronoun = v ?? 'he';
                  _pronounPossessive = _pronoun == 'he' ? 'his' : 'her';
                  _gender = _pronoun == 'he' ? 'male' : 'female';
                }),
              ),
              const SizedBox(height: 12),
            ],

            // Purpose (Barangay Clearance + No Income)
            if (_needsPurpose(type)) ...[
              _field(_purposeCtrl, 'Purpose', maxLines: 2),
              const SizedBox(height: 12),
            ],

            // Community Tax (Barangay Clearance only)
            if (type == 'Barangay Clearance') ...[
              const Divider(),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('Community Tax Certificate',
                    style: TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13)),
              ),
              _field(_communityTaxCtrl, 'Community Tax Cert. No.'),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: _field(_taxIssuedAtCtrl, 'Issued At')),
                const SizedBox(width: 8),
                Expanded(child: _field(_taxIssuedOnCtrl, 'Issued On (date)')),
              ]),
              const SizedBox(height: 8),
              _field(_receiptNoCtrl, 'Official Receipt No.'),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                    child: _field(_receiptIssuedAtCtrl, 'Receipt Issued At')),
                const SizedBox(width: 8),
                Expanded(
                    child: _field(_receiptIssuedOnCtrl, 'Receipt Issued On')),
              ]),
            ],
          ],
        ),
      ),
    );
  }

  bool _needsTitle(String type) => const [
        'Certificate of Residency',
        'Certificate of No Income',
        'Certificate of No Property',
        'Certificate of Single Status',
      ].contains(type);

  bool _needsCivilStatus(String type) => const [
        'Barangay Clearance',
        'Certificate of Residency',
        'Certificate of Good Moral Character',
        'Certificate of Indigency',
        'Certificate of No Income',
      ].contains(type);

  bool _needsPronoun(String type) => const [
        'Barangay Clearance',
        'Certificate of Residency',
        'Certificate of Good Moral Character',
        'Certificate of Indigency',
        'Certificate of No Income',
      ].contains(type);

  bool _needsPurpose(String type) => const [
        'Barangay Clearance',
        'Certificate of No Income',
      ].contains(type);

  Widget _field(TextEditingController ctrl, String label,
      {int maxLines = 1}) {
    return TextField(
      controller: ctrl,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        isDense: true,
      ),
    );
  }

  Widget _dropdownField({
    required String label,
    required String value,
    required List<String> items,
    required void Function(String?) onChanged,
  }) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        isDense: true,
      ),
      items: items
          .map((e) => DropdownMenuItem(value: e, child: Text(e)))
          .toList(),
      onChanged: onChanged,
    );
  }
}
