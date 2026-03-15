// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:barangay_legal_aid/services/api_service.dart';
import 'package:barangay_legal_aid/models/user_model.dart';

/// Displays all document requests submitted by the current user and
/// allows them to download or print a request receipt as a PDF.
class MyRequestsScreen extends StatefulWidget {
  final User currentUser;

  const MyRequestsScreen({super.key, required this.currentUser});

  @override
  State<MyRequestsScreen> createState() => _MyRequestsScreenState();
}

class _MyRequestsScreenState extends State<MyRequestsScreen> {
  final _apiService = ApiService();
  List<Map<String, dynamic>> _requests = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadRequests();
  }

  Future<void> _loadRequests() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final data = await _apiService.getRequests();
      if (mounted) {
        setState(() {
          _requests = data;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
          _isLoading = false;
        });
      }
    }
  }

  // ── PDF Generation ─────────────────────────────────────────────────────────

  Future<pw.Document> _buildPdf(Map<String, dynamic> request) async {
    final doc = pw.Document();

    final dateStr = _formatDate(request['created_at'] as String?);
    final updatedStr = _formatDate(request['updated_at'] as String?);
    final status = (request['status'] as String? ?? 'pending').toUpperCase();
    final docType = request['document_type'] as String? ?? '—';
    final purpose = request['purpose'] as String? ?? '—';
    final requestId = request['id']?.toString() ?? '—';
    final requesterName =
        '${widget.currentUser.firstName} ${widget.currentUser.lastName}'.trim();

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (pw.Context ctx) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Header
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.all(20),
                decoration: pw.BoxDecoration(
                  color: PdfColor.fromHex('99272D'),
                  borderRadius: pw.BorderRadius.circular(8),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.Text(
                      'BARANGAY LEGAL AID',
                      style: pw.TextStyle(
                        fontSize: 20,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.white,
                      ),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      'Document Request Receipt',
                      style: pw.TextStyle(
                        fontSize: 14,
                        color: PdfColors.white,
                      ),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 24),

              // Status badge
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(
                    horizontal: 12, vertical: 6),
                decoration: pw.BoxDecoration(
                  color: _statusPdfColor(status),
                  borderRadius: pw.BorderRadius.circular(20),
                ),
                child: pw.Text(
                  status,
                  style: pw.TextStyle(
                    fontSize: 12,
                    color: PdfColors.white,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
              pw.SizedBox(height: 20),

              // Details table
              _buildPdfRow('Request ID', '#$requestId'),
              _buildPdfDivider(),
              _buildPdfRow('Document Type', docType),
              _buildPdfDivider(),
              _buildPdfRow('Requested By', requesterName),
              _buildPdfDivider(),
              _buildPdfRow('Email', widget.currentUser.email),
              _buildPdfDivider(),
              _buildPdfRow('Purpose', purpose),
              _buildPdfDivider(),
              _buildPdfRow('Date Submitted', dateStr),
              _buildPdfDivider(),
              _buildPdfRow('Last Updated', updatedStr),
              pw.SizedBox(height: 32),

              // Note
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  color: PdfColor.fromHex('F5F5F5'),
                  border: pw.Border.all(color: PdfColor.fromHex('DDDDDD')),
                  borderRadius: pw.BorderRadius.circular(6),
                ),
                child: pw.Text(
                  'This document serves as proof of your request submission to the barangay. '
                  'Please present this receipt when following up at the barangay hall.',
                  style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
                ),
              ),
              pw.Spacer(),

              // Footer
              pw.Divider(),
              pw.Text(
                'Generated on ${DateFormat('MMMM d, yyyy – h:mm a').format(DateTime.now())}',
                style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey),
              ),
            ],
          );
        },
      ),
    );

    return doc;
  }

  pw.Widget _buildPdfRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 8),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 140,
            child: pw.Text(
              label,
              style: pw.TextStyle(
                fontSize: 11,
                fontWeight: pw.FontWeight.bold,
                color: PdfColor.fromHex('36454F'),
              ),
            ),
          ),
          pw.Expanded(
            child: pw.Text(
              value,
              style: const pw.TextStyle(fontSize: 11, color: PdfColors.black),
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildPdfDivider() =>
      pw.Divider(color: PdfColor.fromHex('EEEEEE'), height: 1);

  PdfColor _statusPdfColor(String status) {
    switch (status) {
      case 'APPROVED':
        return PdfColor.fromHex('2E7D32');
      case 'REJECTED':
        return PdfColor.fromHex('B71C1C');
      default:
        return PdfColor.fromHex('E65100');
    }
  }

  // ── Download / Print ──────────────────────────────────────────────────────

  Future<void> _downloadOrPrint(
      Map<String, dynamic> request, bool printMode) async {
    try {
      final doc = await _buildPdf(request);
      final bytes = await doc.save();
      final docType = (request['document_type'] as String? ?? 'request')
          .replaceAll(' ', '_');
      final requestId = request['id']?.toString() ?? '0';

      if (printMode) {
        await Printing.layoutPdf(
          onLayout: (_) async => bytes,
          name: 'Request_${requestId}_$docType',
        );
      } else {
        await Printing.sharePdf(
          bytes: bytes,
          filename: 'Request_${requestId}_$docType.pdf',
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed: ${e.toString().replaceFirst('Exception: ', '')}'),
            backgroundColor: const Color(0xFF99272D),
          ),
        );
      }
    }
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  String _formatDate(String? iso) {
    if (iso == null) return '—';
    try {
      final dt = DateTime.parse(iso).toLocal();
      return DateFormat('MMM d, yyyy – h:mm a').format(dt);
    } catch (_) {
      return iso;
    }
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'approved':
        return const Color(0xFF2E7D32);
      case 'rejected':
        return const Color(0xFFB71C1C);
      default:
        return const Color(0xFFE65100);
    }
  }

  IconData _statusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'approved':
        return Icons.check_circle_outline;
      case 'rejected':
        return Icons.cancel_outlined;
      default:
        return Icons.hourglass_top_outlined;
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Document Requests'),
        backgroundColor: const Color(0xFF99272D),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _loadRequests,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 56, color: Colors.grey[400]),
            const SizedBox(height: 12),
            Text(_error!,
                style: TextStyle(color: Colors.grey[700]),
                textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _loadRequests,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF99272D),
                  foregroundColor: Colors.white),
            ),
          ],
        ),
      );
    }
    if (_requests.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox_outlined, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text('No requests yet',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[700])),
            const SizedBox(height: 8),
            Text('Submit a document request from the Forms hub.',
                style: TextStyle(fontSize: 14, color: Colors.grey[500])),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _requests.length,
      itemBuilder: (context, i) => _buildRequestCard(_requests[i]),
    );
  }

  Widget _buildRequestCard(Map<String, dynamic> req) {
    final docType = req['document_type'] as String? ?? '—';
    final status = req['status'] as String? ?? 'pending';
    final purpose = req['purpose'] as String? ?? '—';
    final dateStr = _formatDate(req['created_at'] as String?);
    final color = _statusColor(status);
    final icon = _statusIcon(status);

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF99272D).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.description_outlined,
                      color: Color(0xFF99272D), size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        docType,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF36454F),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        dateStr,
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
                // Status badge
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: color.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, color: color, size: 14),
                      const SizedBox(width: 4),
                      Text(
                        status[0].toUpperCase() + status.substring(1),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: color,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 10),

            // Purpose
            Text(
              'Purpose: $purpose',
              style: TextStyle(fontSize: 13, color: Colors.grey[700]),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),

            const SizedBox(height: 14),

            // Admin-attached document download
            if ((req['file_url'] as String?) != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F5E9),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF43A047).withValues(alpha: 0.4)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.insert_drive_file, color: Color(0xFF2E7D32), size: 18),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Document ready for download',
                        style: TextStyle(fontSize: 13, color: Color(0xFF2E7D32), fontWeight: FontWeight.w500),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () {
                        const baseUrl = 'https://bla-production-441d.up.railway.app';
                        html.window.open('$baseUrl${req['file_url']}', '_blank');
                      },
                      icon: const Icon(Icons.download, size: 16),
                      label: const Text('Download'),
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF2E7D32),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
            ],

            // Receipt Download / Print buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _downloadOrPrint(req, false),
                  icon: const Icon(Icons.receipt_outlined, size: 18),
                  label: const Text('Receipt'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF99272D),
                    side: const BorderSide(color: Color(0xFF99272D)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: () => _downloadOrPrint(req, true),
                  icon: const Icon(Icons.print_outlined, size: 18),
                  label: const Text('Print'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF99272D),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    elevation: 0,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
