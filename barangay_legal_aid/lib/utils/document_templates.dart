import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

// ─────────────────────────────────────────────────────────────────────────────
// Data container passed to every template
// ─────────────────────────────────────────────────────────────────────────────

class DocumentData {
  final String title;          // Mr. / Mrs. / Ms.
  final String fullName;       // "Juan S. dela Cruz"
  final String firstName;      // for "Furthermore, Juan is also…"
  final String civilStatus;    // Single / Married / Widowed
  final String gender;         // male / female
  final String pronoun;        // he / she
  final String pronounPossessive; // his / her
  final String address;        // full address string
  final String barangayName;
  final String municipality;
  final String province;
  final String purpose;        // user-stated purpose
  final String dateDay;        // ordinal: "3rd"
  final String dateMonth;      // "December"
  final String dateYear;       // "2024"
  final String punongBarangayName; // admin's display name

  // Barangay Clearance extras
  final String communityTaxNo;
  final String taxIssuedAt;
  final String taxIssuedOn;
  final String officialReceiptNo;
  final String receiptIssuedAt;
  final String receiptIssuedOn;

  const DocumentData({
    this.title = 'Mr.',
    required this.fullName,
    required this.firstName,
    this.civilStatus = 'Single',
    this.gender = 'male',
    this.pronoun = 'he',
    this.pronounPossessive = 'his',
    required this.address,
    required this.barangayName,
    this.municipality = '',
    this.province = '',
    this.purpose = 'FOR ANY LEGAL PURPOSE',
    required this.dateDay,
    required this.dateMonth,
    required this.dateYear,
    required this.punongBarangayName,
    this.communityTaxNo = '',
    this.taxIssuedAt = '',
    this.taxIssuedOn = '',
    this.officialReceiptNo = '',
    this.receiptIssuedAt = '',
    this.receiptIssuedOn = '',
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Signature stamp — placed at arbitrary position on the PDF page
// ─────────────────────────────────────────────────────────────────────────────

class SignatureStamp {
  /// Fraction of the full page width/height (0.0–1.0, including margins).
  final double xFraction;
  final double yFraction;
  final Uint8List bytes;
  final double widthPoints; // stamp width in PDF points
  final String name; // UI label for saved stamp picker (not rendered in PDF)
  const SignatureStamp({
    required this.bytes,
    required this.xFraction,
    required this.yFraction,
    this.widthPoints = 110,
    this.name = '',
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Text overlay — draggable text placed anywhere on the PDF page
// ─────────────────────────────────────────────────────────────────────────────

class TextOverlay {
  final double xFraction;
  final double yFraction;
  final String text;
  final double fontSize; // PDF points
  const TextOverlay({
    required this.text,
    required this.xFraction,
    required this.yFraction,
    this.fontSize = 10,
  });
}

// Converts stamp/text overlay fractions → positioned overlays on the PDF page.
// All templates share the same A4 size + margins (h:60, v:48).
pw.Widget _wrapWithStamps(
  pw.Widget base,
  List<SignatureStamp> stamps,
  List<TextOverlay> textOverlays,
) {
  if (stamps.isEmpty && textOverlays.isEmpty) return base;
  const pageW = 595.28;
  const pageH = 841.89;
  const mH = 60.0; // horizontal margin
  const mV = 48.0; // vertical margin
  const availW = pageW - 2 * mH; // 475.28
  const availH = pageH - 2 * mV; // 745.89
  return pw.Stack(
    children: [
      pw.SizedBox(width: availW, height: availH, child: base),
      ...stamps.map((s) {
        final stampH = s.widthPoints * 0.45;
        final left = (s.xFraction * pageW - mH - s.widthPoints / 2).clamp(0.0, availW - s.widthPoints);
        final top  = (s.yFraction * pageH - mV - stampH / 2).clamp(0.0, availH - stampH);
        return pw.Positioned(
          left: left,
          top: top,
          child: pw.Image(pw.MemoryImage(s.bytes), width: s.widthPoints),
        );
      }),
      ...textOverlays.map((o) {
        final left = (o.xFraction * pageW - mH).clamp(0.0, pageW * 0.88 - mH);
        final top  = (o.yFraction * pageH - mV).clamp(0.0, availH - o.fontSize * 2);
        return pw.Positioned(
          left: left,
          top: top,
          child: pw.Text(
            o.text,
            style: pw.TextStyle(font: pw.Font.helvetica(), fontSize: o.fontSize),
          ),
        );
      }),
    ],
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

String ordinalDate(int n) {
  if (n >= 11 && n <= 13) return '${n}th';
  switch (n % 10) {
    case 1: return '${n}st';
    case 2: return '${n}nd';
    case 3: return '${n}rd';
    default: return '${n}th';
  }
}


// ─────────────────────────────────────────────────────────────────────────────
// Shared header (all documents)
// ─────────────────────────────────────────────────────────────────────────────

pw.Widget _buildDocumentHeader({
  required DocumentData data,
  Uint8List? logoLeftBytes,
  Uint8List? logoRightBytes,
  required pw.Font bold,
  required pw.Font regular,
}) {
  final leftLogo = logoLeftBytes != null
      ? pw.Image(pw.MemoryImage(logoLeftBytes), width: 65, height: 65)
      : pw.Container(
          width: 65,
          height: 65,
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.grey300),
            borderRadius: pw.BorderRadius.circular(32),
          ),
          child: pw.Center(
            child: pw.Text('LOGO', style: pw.TextStyle(font: regular, fontSize: 8, color: PdfColors.grey)),
          ),
        );

  final rightLogo = logoRightBytes != null
      ? pw.Image(pw.MemoryImage(logoRightBytes), width: 65, height: 65)
      : pw.SizedBox(width: 65, height: 65);

  return pw.Column(
    children: [
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.center,
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          leftLogo,
          pw.SizedBox(width: 16),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Text('Republic of the Philippines',
                    style: pw.TextStyle(font: regular, fontSize: 10),
                    textAlign: pw.TextAlign.center),
                pw.Text('Province of ${data.province}',
                    style: pw.TextStyle(font: regular, fontSize: 10),
                    textAlign: pw.TextAlign.center),
                pw.Text('Municipality of ${data.municipality}',
                    style: pw.TextStyle(font: regular, fontSize: 10),
                    textAlign: pw.TextAlign.center),
                pw.Text('BARANGAY ${data.barangayName.toUpperCase()}',
                    style: pw.TextStyle(font: bold, fontSize: 12),
                    textAlign: pw.TextAlign.center),
              ],
            ),
          ),
          pw.SizedBox(width: 16),
          rightLogo,
        ],
      ),
      pw.SizedBox(height: 8),
      pw.Text(
        'OFFICE OF THE BARANGAY CAPTAIN',
        style: pw.TextStyle(font: bold, fontSize: 11),
        textAlign: pw.TextAlign.center,
      ),
      pw.SizedBox(height: 6),
      pw.Divider(thickness: 1.5, color: PdfColors.black),
    ],
  );
}

// Signature block used by most documents
pw.Widget _buildSignatureBlock({
  required String name,
  required String title,
  Uint8List? signatureBytes,
  required pw.Font bold,
  required pw.Font regular,
  pw.MainAxisAlignment alignment = pw.MainAxisAlignment.end,
}) {
  final sigImage = signatureBytes != null
      ? pw.Image(pw.MemoryImage(signatureBytes), width: 120, height: 40, fit: pw.BoxFit.contain)
      : pw.SizedBox(height: 40);

  return pw.Row(
    mainAxisAlignment: alignment,
    children: [
      pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          sigImage,
          pw.Container(width: 180, height: 1, color: PdfColors.black),
          pw.SizedBox(height: 2),
          pw.Text(name.toUpperCase(),
              style: pw.TextStyle(font: bold, fontSize: 10),
              textAlign: pw.TextAlign.center),
          pw.Text(title,
              style: pw.TextStyle(font: regular, fontSize: 9),
              textAlign: pw.TextAlign.center),
        ],
      ),
    ],
  );
}


// ─────────────────────────────────────────────────────────────────────────────
// 1. Barangay Clearance
// ─────────────────────────────────────────────────────────────────────────────

Future<Uint8List> generateBarangayClearance(
  DocumentData data, {
  Uint8List? logoLeftBytes,
  Uint8List? logoRightBytes,
  Uint8List? signatureBytes,
  List<SignatureStamp> stamps = const [],
  List<TextOverlay> textOverlays = const [],
}) async {
  final doc = pw.Document();
  final bold = pw.Font.helveticaBold();
  final regular = pw.Font.helvetica();

  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.symmetric(horizontal: 60, vertical: 48),
      build: (ctx) => _wrapWithStamps(pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          _buildDocumentHeader(
            data: data, logoLeftBytes: logoLeftBytes, logoRightBytes: logoRightBytes,
            bold: bold, regular: regular,
          ),
          pw.SizedBox(height: 20),
          pw.Center(
            child: pw.Text('BARANGAY CLEARANCE',
                style: pw.TextStyle(font: bold, fontSize: 16),
                textAlign: pw.TextAlign.center),
          ),
          pw.SizedBox(height: 20),
          pw.Text('TO WHOM IT MAY CONCERN:', style: pw.TextStyle(font: bold, fontSize: 11)),
          pw.SizedBox(height: 12),
          pw.RichText(
            textAlign: pw.TextAlign.justify,
            text: pw.TextSpan(
              children: [
                pw.TextSpan(text: '\t\tTHIS IS TO CERTIFY that ', style: pw.TextStyle(font: regular, fontSize: 11)),
                pw.TextSpan(text: data.fullName.toUpperCase(), style: pw.TextStyle(font: bold, fontSize: 11,
                    decoration: pw.TextDecoration.underline)),
                pw.TextSpan(
                  text: ', ${data.civilStatus} and bona fide resident of ${data.address}, '
                      'is personally known by the undersigned to be a person of good moral character and law-abiding citizen.',
                  style: pw.TextStyle(font: regular, fontSize: 11),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 10),
          pw.Text(
            '\t\tThis certifies that according to the records complied by this office as of this date, '
            '${data.pronoun} has never been accused of any crime involving moral turpitude nor a member to '
            'any group of subversive organization.',
            style: pw.TextStyle(font: regular, fontSize: 11),
            textAlign: pw.TextAlign.justify,
          ),
          pw.SizedBox(height: 10),
          pw.RichText(
            textAlign: pw.TextAlign.justify,
            text: pw.TextSpan(
              children: [
                pw.TextSpan(
                  text: '\t\tThis certification is issued upon the request of herein interested party in connection '
                      'with ${data.pronounPossessive} purpose: ',
                  style: pw.TextStyle(font: regular, fontSize: 11),
                ),
                pw.TextSpan(
                  text: data.purpose.toUpperCase() + '.',
                  style: pw.TextStyle(font: bold, fontSize: 11,
                      decoration: pw.TextDecoration.underline),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 10),
          pw.RichText(
            textAlign: pw.TextAlign.justify,
            text: pw.TextSpan(
              children: [
                pw.TextSpan(text: '\t\tGiven this ', style: pw.TextStyle(font: regular, fontSize: 11)),
                pw.TextSpan(
                  text: '${data.dateDay} day of ${data.dateMonth} ${data.dateYear}',
                  style: pw.TextStyle(font: bold, fontSize: 11,
                      decoration: pw.TextDecoration.underline),
                ),
                pw.TextSpan(
                  text: ', at Barangay ${data.barangayName}, ${data.municipality}, ${data.province}, Philippines.',
                  style: pw.TextStyle(font: bold, fontSize: 11),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 30),
          // Two-column signature block
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.SizedBox(height: 40),
                  pw.Container(width: 160, height: 1, color: PdfColors.black),
                  pw.Text('Barangay Secretary',
                      style: pw.TextStyle(font: regular, fontSize: 10)),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  signatureBytes != null
                      ? pw.Image(pw.MemoryImage(signatureBytes), width: 120, height: 40, fit: pw.BoxFit.contain)
                      : pw.SizedBox(height: 40),
                  pw.Container(width: 160, height: 1, color: PdfColors.black),
                  pw.Text('Punong Barangay',
                      style: pw.TextStyle(font: regular, fontSize: 10)),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 20),
          // Community Tax fields
          pw.Row(
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('Community Tax Cert. No: ${data.communityTaxNo}',
                      style: pw.TextStyle(font: regular, fontSize: 9)),
                  pw.Text('Issued at: ${data.taxIssuedAt}',
                      style: pw.TextStyle(font: regular, fontSize: 9)),
                  pw.Text('On: ${data.taxIssuedOn}',
                      style: pw.TextStyle(font: regular, fontSize: 9)),
                  pw.Text('Official Receipt: ${data.officialReceiptNo}',
                      style: pw.TextStyle(font: regular, fontSize: 9)),
                  pw.Text('Issued at: ${data.receiptIssuedAt}',
                      style: pw.TextStyle(font: regular, fontSize: 9)),
                  pw.Text('On: ${data.receiptIssuedOn}',
                      style: pw.TextStyle(font: regular, fontSize: 9)),
                ],
              ),
              pw.Spacer(),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.SizedBox(height: 30),
                  pw.Container(width: 160, height: 1, color: PdfColors.black),
                  pw.Text('Signature of Applicant',
                      style: pw.TextStyle(font: regular, fontSize: 9)),
                ],
              ),
            ],
          ),
        ],
      ), stamps, textOverlays),
    ),
  );
  return doc.save();
}

// ─────────────────────────────────────────────────────────────────────────────
// 2. Certificate of Residency
// ─────────────────────────────────────────────────────────────────────────────

Future<Uint8List> generateCertificateOfResidency(
  DocumentData data, {
  Uint8List? logoLeftBytes,
  Uint8List? logoRightBytes,
  Uint8List? signatureBytes,
  List<SignatureStamp> stamps = const [],
  List<TextOverlay> textOverlays = const [],
}) async {
  final doc = pw.Document();
  final bold = pw.Font.helveticaBold();
  final regular = pw.Font.helvetica();

  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.symmetric(horizontal: 60, vertical: 48),
      build: (ctx) => _wrapWithStamps(pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          _buildDocumentHeader(
            data: data, logoLeftBytes: logoLeftBytes, logoRightBytes: logoRightBytes,
            bold: bold, regular: regular,
          ),
          pw.SizedBox(height: 24),
          pw.Center(
            child: pw.Text('CERTIFICATE OF RESIDENCY',
                style: pw.TextStyle(font: bold, fontSize: 16),
                textAlign: pw.TextAlign.center),
          ),
          pw.SizedBox(height: 20),
          pw.Text('TO WHOM IT MAY CONCERN:', style: pw.TextStyle(font: bold, fontSize: 11)),
          pw.SizedBox(height: 12),
          pw.RichText(
            textAlign: pw.TextAlign.justify,
            text: pw.TextSpan(
              children: [
                pw.TextSpan(text: '\t\tThis is to certify that ', style: pw.TextStyle(font: regular, fontSize: 11)),
                pw.TextSpan(
                  text: '${data.title} ${data.fullName.toUpperCase()}',
                  style: pw.TextStyle(font: bold, fontSize: 11,
                      decoration: pw.TextDecoration.underline),
                ),
                pw.TextSpan(
                  text: ', of legal age, ${data.civilStatus}, Filipino citizen, whose specimen signature appears below, is a ',
                  style: pw.TextStyle(font: regular, fontSize: 11),
                ),
                pw.TextSpan(
                  text: 'PERMANENT RESIDENT',
                  style: pw.TextStyle(font: bold, fontSize: 11),
                ),
                pw.TextSpan(
                  text: ' of this Barangay ${data.barangayName}, ${data.municipality}, ${data.province}.',
                  style: pw.TextStyle(font: regular, fontSize: 11),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 10),
          pw.Text(
            '\t\tBased on records of this office, ${data.pronoun} has been residing at Barangay '
            '${data.barangayName}, Municipality of ${data.municipality}, ${data.province}.',
            style: pw.TextStyle(font: regular, fontSize: 11),
            textAlign: pw.TextAlign.justify,
          ),
          pw.SizedBox(height: 10),
          pw.RichText(
            textAlign: pw.TextAlign.justify,
            text: pw.TextSpan(
              children: [
                pw.TextSpan(text: '\t\tThis ', style: pw.TextStyle(font: regular, fontSize: 11)),
                pw.TextSpan(text: 'CERTIFICATION', style: pw.TextStyle(font: bold, fontSize: 11)),
                pw.TextSpan(
                  text: ' is being issued upon the request of the above-named person for whatever legal purpose it may serve.',
                  style: pw.TextStyle(font: regular, fontSize: 11),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 10),
          pw.RichText(
            textAlign: pw.TextAlign.justify,
            text: pw.TextSpan(
              children: [
                pw.TextSpan(text: '\t\tIssued this ', style: pw.TextStyle(font: regular, fontSize: 11)),
                pw.TextSpan(
                  text: '${data.dateDay} day of ${data.dateMonth}, ${data.dateYear}',
                  style: pw.TextStyle(font: bold, fontSize: 11,
                      decoration: pw.TextDecoration.underline),
                ),
                pw.TextSpan(
                  text: ' at Barangay ${data.barangayName}, Municipality of ${data.municipality}, ${data.province}, Philippines.',
                  style: pw.TextStyle(font: regular, fontSize: 11),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 40),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('Specimen Signature:',
                      style: pw.TextStyle(font: regular, fontSize: 10)),
                  pw.SizedBox(height: 24),
                  pw.Container(width: 140, height: 1, color: PdfColors.black),
                ],
              ),
              _buildSignatureBlock(
                name: data.punongBarangayName,
                title: 'Punong Barangay',
                signatureBytes: signatureBytes,
                bold: bold,
                regular: regular,
              ),
            ],
          ),
          pw.SizedBox(height: 16),
          pw.Text('"Not valid without official seal"',
              style: pw.TextStyle(font: pw.Font.helveticaOblique(), fontSize: 9, color: PdfColors.grey700)),
        ],
      ), stamps, textOverlays),
    ),
  );
  return doc.save();
}

// ─────────────────────────────────────────────────────────────────────────────
// 3. Certificate of Good Moral Character
// ─────────────────────────────────────────────────────────────────────────────

Future<Uint8List> generateCertificateOfGoodMoral(
  DocumentData data, {
  Uint8List? logoLeftBytes,
  Uint8List? logoRightBytes,
  Uint8List? signatureBytes,
  List<SignatureStamp> stamps = const [],
  List<TextOverlay> textOverlays = const [],
}) async {
  final doc = pw.Document();
  final bold = pw.Font.helveticaBold();
  final regular = pw.Font.helvetica();

  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.symmetric(horizontal: 60, vertical: 48),
      build: (ctx) => _wrapWithStamps(pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          _buildDocumentHeader(
            data: data, logoLeftBytes: logoLeftBytes, logoRightBytes: logoRightBytes,
            bold: bold, regular: regular,
          ),
          pw.SizedBox(height: 24),
          pw.Center(
            child: pw.Text('CERTIFICATE OF GOOD MORAL CHARACTER',
                style: pw.TextStyle(font: bold, fontSize: 15),
                textAlign: pw.TextAlign.center),
          ),
          pw.SizedBox(height: 20),
          pw.Text('TO WHOM IT MAY CONCERN:', style: pw.TextStyle(font: bold, fontSize: 11)),
          pw.SizedBox(height: 12),
          pw.RichText(
            textAlign: pw.TextAlign.justify,
            text: pw.TextSpan(
              children: [
                pw.TextSpan(text: '\t\tThis is to certify that ', style: pw.TextStyle(font: regular, fontSize: 11)),
                pw.TextSpan(
                  text: data.fullName.toUpperCase(),
                  style: pw.TextStyle(font: bold, fontSize: 11, decoration: pw.TextDecoration.underline),
                ),
                pw.TextSpan(
                  text: ' has been a bona fide resident of Barangay ${data.barangayName}, '
                      '${data.municipality}, ${data.province}. ${data.pronoun.substring(0, 1).toUpperCase()}${data.pronoun.substring(1)} '
                      'possesses good moral character, is a peaceful and law-abiding citizen, and has not committed any '
                      'misconduct or misdemeanor contrary to the laws of the land.',
                  style: pw.TextStyle(font: regular, fontSize: 11),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 10),
          pw.Text(
            '\t\tThis certification is issued upon request of the above-mentioned person for all legal intents and purposes.',
            style: pw.TextStyle(font: regular, fontSize: 11),
            textAlign: pw.TextAlign.justify,
          ),
          pw.SizedBox(height: 10),
          pw.RichText(
            textAlign: pw.TextAlign.justify,
            text: pw.TextSpan(
              children: [
                pw.TextSpan(text: '\t\tGiven this ', style: pw.TextStyle(font: regular, fontSize: 11)),
                pw.TextSpan(
                  text: '${data.dateDay} day of ${data.dateMonth}, ${data.dateYear}',
                  style: pw.TextStyle(font: bold, fontSize: 11, decoration: pw.TextDecoration.underline),
                ),
                pw.TextSpan(
                  text: ' at Barangay ${data.barangayName}, ${data.municipality}, ${data.province}, Philippines.',
                  style: pw.TextStyle(font: regular, fontSize: 11),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 40),
          _buildSignatureBlock(
            name: data.punongBarangayName,
            title: 'Punong Barangay',
            signatureBytes: signatureBytes,
            bold: bold, regular: regular,
          ),
        ],
      ), stamps, textOverlays),
    ),
  );
  return doc.save();
}

// ─────────────────────────────────────────────────────────────────────────────
// 4. Certificate of Indigency
// ─────────────────────────────────────────────────────────────────────────────

Future<Uint8List> generateCertificateOfIndigency(
  DocumentData data, {
  Uint8List? logoLeftBytes,
  Uint8List? logoRightBytes,
  Uint8List? signatureBytes,
  List<SignatureStamp> stamps = const [],
  List<TextOverlay> textOverlays = const [],
}) async {
  final doc = pw.Document();
  final bold = pw.Font.helveticaBold();
  final regular = pw.Font.helvetica();

  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.symmetric(horizontal: 60, vertical: 48),
      build: (ctx) => _wrapWithStamps(pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          _buildDocumentHeader(
            data: data, logoLeftBytes: logoLeftBytes, logoRightBytes: logoRightBytes,
            bold: bold, regular: regular,
          ),
          pw.SizedBox(height: 24),
          pw.Center(
            child: pw.Text('CERTIFICATE OF INDIGENCY',
                style: pw.TextStyle(font: bold, fontSize: 16,
                    fontStyle: pw.FontStyle.italic, decoration: pw.TextDecoration.underline),
                textAlign: pw.TextAlign.center),
          ),
          pw.SizedBox(height: 20),
          pw.Text('TO WHOM IT MAY CONCERN:', style: pw.TextStyle(font: regular, fontSize: 11)),
          pw.SizedBox(height: 12),
          pw.RichText(
            textAlign: pw.TextAlign.justify,
            text: pw.TextSpan(
              children: [
                pw.TextSpan(text: '\t\tThis is to certify that ', style: pw.TextStyle(font: regular, fontSize: 11)),
                pw.TextSpan(
                  text: data.fullName.toUpperCase(),
                  style: pw.TextStyle(font: bold, fontSize: 11, decoration: pw.TextDecoration.underline),
                ),
                pw.TextSpan(
                  text: ', of legal age, ${data.gender}, ${data.civilStatus}, Filipino, is a resident of this Barangay is one of the ',
                  style: pw.TextStyle(font: regular, fontSize: 11),
                ),
                pw.TextSpan(
                  text: 'indigents',
                  style: pw.TextStyle(font: bold, fontSize: 11, fontStyle: pw.FontStyle.italic),
                ),
                pw.TextSpan(
                  text: ' in our barangay.',
                  style: pw.TextStyle(font: regular, fontSize: 11),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 10),
          pw.Text(
            '\t\tThis certification is being issued upon the request of the above-named person for '
            'whatever legal purpose it may serve ${data.pronounPossessive} best.',
            style: pw.TextStyle(font: regular, fontSize: 11),
            textAlign: pw.TextAlign.justify,
          ),
          pw.SizedBox(height: 10),
          pw.RichText(
            textAlign: pw.TextAlign.justify,
            text: pw.TextSpan(
              children: [
                pw.TextSpan(text: '\t\tIssued this ', style: pw.TextStyle(font: regular, fontSize: 11)),
                pw.TextSpan(
                  text: '${data.dateDay} day of ${data.dateMonth} ${data.dateYear}',
                  style: pw.TextStyle(font: regular, fontSize: 11, decoration: pw.TextDecoration.underline),
                ),
                pw.TextSpan(
                  text: ' at the Office of the Punong Barangay, Barangay ${data.barangayName}, '
                      '${data.municipality}, ${data.province}, Philippines.',
                  style: pw.TextStyle(font: regular, fontSize: 11),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 40),
          _buildSignatureBlock(
            name: data.punongBarangayName,
            title: 'Punong Barangay',
            signatureBytes: signatureBytes,
            bold: bold, regular: regular,
          ),
        ],
      ), stamps, textOverlays),
    ),
  );
  return doc.save();
}

// ─────────────────────────────────────────────────────────────────────────────
// 5. Certificate of No Income
// ─────────────────────────────────────────────────────────────────────────────

Future<Uint8List> generateCertificateOfNoIncome(
  DocumentData data, {
  Uint8List? logoLeftBytes,
  Uint8List? logoRightBytes,
  Uint8List? signatureBytes,
  List<SignatureStamp> stamps = const [],
  List<TextOverlay> textOverlays = const [],
}) async {
  final doc = pw.Document();
  final bold = pw.Font.helveticaBold();
  final regular = pw.Font.helvetica();

  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.symmetric(horizontal: 60, vertical: 48),
      build: (ctx) => _wrapWithStamps(pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          _buildDocumentHeader(
            data: data, logoLeftBytes: logoLeftBytes, logoRightBytes: logoRightBytes,
            bold: bold, regular: regular,
          ),
          pw.SizedBox(height: 24),
          pw.Center(
            child: pw.Text('CERTIFICATION',
                style: pw.TextStyle(font: bold, fontSize: 16),
                textAlign: pw.TextAlign.center),
          ),
          pw.SizedBox(height: 20),
          pw.Text('TO WHOM IT MAY CONCERN:', style: pw.TextStyle(font: bold, fontSize: 11)),
          pw.SizedBox(height: 12),
          pw.RichText(
            textAlign: pw.TextAlign.justify,
            text: pw.TextSpan(
              children: [
                pw.TextSpan(text: '\t\tThis is to certify that ', style: pw.TextStyle(font: regular, fontSize: 11)),
                pw.TextSpan(
                  text: '${data.title} ${data.fullName.toUpperCase()}',
                  style: pw.TextStyle(font: bold, fontSize: 11, decoration: pw.TextDecoration.underline),
                ),
                pw.TextSpan(
                  text: ', Filipino, of legal age, ${data.civilStatus}, is a bonafide resident of '
                      '${data.address}, Barangay ${data.barangayName}, ${data.municipality}, ${data.province}. '
                      'The said person is of good moral character, a law-abiding citizen, and an active member of the community.',
                  style: pw.TextStyle(font: regular, fontSize: 11),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 10),
          pw.Text(
            '\t\tFurthermore, ${data.firstName} is also one of those who belong to a No income family.',
            style: pw.TextStyle(font: regular, fontSize: 11),
            textAlign: pw.TextAlign.justify,
          ),
          pw.SizedBox(height: 10),
          pw.RichText(
            textAlign: pw.TextAlign.justify,
            text: pw.TextSpan(
              children: [
                pw.TextSpan(
                  text: '\t\tThis certification is being issued upon the request of the above-named person for ${data.purpose}. '
                      'Given this ',
                  style: pw.TextStyle(font: regular, fontSize: 11),
                ),
                pw.TextSpan(
                  text: '${data.dateDay} day of ${data.dateMonth}, ${data.dateYear}',
                  style: pw.TextStyle(font: regular, fontSize: 11, decoration: pw.TextDecoration.underline),
                ),
                pw.TextSpan(
                  text: ' at Barangay ${data.barangayName}, ${data.municipality}, ${data.province}.',
                  style: pw.TextStyle(font: regular, fontSize: 11),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 30),
          pw.Text('CERTIFIED BY:', style: pw.TextStyle(font: bold, fontSize: 11)),
          pw.SizedBox(height: 30),
          _buildSignatureBlock(
            name: data.punongBarangayName,
            title: 'PUNONG BARANGAY',
            signatureBytes: signatureBytes,
            bold: bold, regular: regular,
          ),
        ],
      ), stamps, textOverlays),
    ),
  );
  return doc.save();
}

// ─────────────────────────────────────────────────────────────────────────────
// 6. Certificate of No Property
// ─────────────────────────────────────────────────────────────────────────────

Future<Uint8List> generateCertificateOfNoProperty(
  DocumentData data, {
  Uint8List? logoLeftBytes,
  Uint8List? logoRightBytes,
  Uint8List? signatureBytes,
  List<SignatureStamp> stamps = const [],
  List<TextOverlay> textOverlays = const [],
}) async {
  final doc = pw.Document();
  final bold = pw.Font.helveticaBold();
  final regular = pw.Font.helvetica();

  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.symmetric(horizontal: 60, vertical: 48),
      build: (ctx) => _wrapWithStamps(pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          _buildDocumentHeader(
            data: data, logoLeftBytes: logoLeftBytes, logoRightBytes: logoRightBytes,
            bold: bold, regular: regular,
          ),
          pw.SizedBox(height: 24),
          pw.Center(
            child: pw.Text('CERTIFICATE OF NO PROPERTY',
                style: pw.TextStyle(font: bold, fontSize: 16),
                textAlign: pw.TextAlign.center),
          ),
          pw.SizedBox(height: 20),
          pw.Text('TO WHOM IT MAY CONCERN:', style: pw.TextStyle(font: bold, fontSize: 11)),
          pw.SizedBox(height: 12),
          pw.RichText(
            textAlign: pw.TextAlign.justify,
            text: pw.TextSpan(
              children: [
                pw.TextSpan(text: '\t\tThis is to certify that ', style: pw.TextStyle(font: regular, fontSize: 11)),
                pw.TextSpan(
                  text: '${data.title} ${data.fullName.toUpperCase()}',
                  style: pw.TextStyle(font: bold, fontSize: 11, decoration: pw.TextDecoration.underline),
                ),
                pw.TextSpan(
                  text: ', of legal age, Filipino, and a resident of ${data.address}, '
                      'Barangay ${data.barangayName}, ${data.municipality}, ${data.province}, '
                      'has no registered land, house, or real property within the jurisdiction of this barangay '
                      'based on available records.',
                  style: pw.TextStyle(font: regular, fontSize: 11),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 10),
          pw.Text(
            '\t\tThis certification is issued upon the request of the above-named person for whatever legal purpose it may serve.',
            style: pw.TextStyle(font: regular, fontSize: 11),
            textAlign: pw.TextAlign.justify,
          ),
          pw.SizedBox(height: 10),
          pw.RichText(
            textAlign: pw.TextAlign.justify,
            text: pw.TextSpan(
              children: [
                pw.TextSpan(text: '\t\tIssued this ', style: pw.TextStyle(font: regular, fontSize: 11)),
                pw.TextSpan(
                  text: '${data.dateDay} day of ${data.dateMonth}, ${data.dateYear}',
                  style: pw.TextStyle(font: regular, fontSize: 11, decoration: pw.TextDecoration.underline),
                ),
                pw.TextSpan(
                  text: ' at the Office of the Punong Barangay, Barangay ${data.barangayName}, '
                      '${data.municipality}, ${data.province}, Philippines.',
                  style: pw.TextStyle(font: regular, fontSize: 11),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 40),
          _buildSignatureBlock(
            name: data.punongBarangayName,
            title: 'Barangay Captain',
            signatureBytes: signatureBytes,
            bold: bold, regular: regular,
          ),
        ],
      ), stamps, textOverlays),
    ),
  );
  return doc.save();
}

// ─────────────────────────────────────────────────────────────────────────────
// 7. Certificate of Single Status
// ─────────────────────────────────────────────────────────────────────────────

Future<Uint8List> generateCertificateOfSingleStatus(
  DocumentData data, {
  Uint8List? logoLeftBytes,
  Uint8List? logoRightBytes,
  Uint8List? signatureBytes,
  List<SignatureStamp> stamps = const [],
  List<TextOverlay> textOverlays = const [],
}) async {
  final doc = pw.Document();
  final bold = pw.Font.helveticaBold();
  final regular = pw.Font.helvetica();

  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.symmetric(horizontal: 60, vertical: 48),
      build: (ctx) => _wrapWithStamps(pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          _buildDocumentHeader(
            data: data, logoLeftBytes: logoLeftBytes, logoRightBytes: logoRightBytes,
            bold: bold, regular: regular,
          ),
          pw.SizedBox(height: 24),
          pw.Center(
            child: pw.Text('CERTIFICATE OF SINGLE STATUS',
                style: pw.TextStyle(font: bold, fontSize: 16),
                textAlign: pw.TextAlign.center),
          ),
          pw.SizedBox(height: 20),
          pw.Text('TO WHOM IT MAY CONCERN:', style: pw.TextStyle(font: bold, fontSize: 11)),
          pw.SizedBox(height: 12),
          pw.RichText(
            textAlign: pw.TextAlign.justify,
            text: pw.TextSpan(
              children: [
                pw.TextSpan(text: '\t\tThis is to certify that ', style: pw.TextStyle(font: regular, fontSize: 11)),
                pw.TextSpan(
                  text: '${data.title} ${data.fullName.toUpperCase()}',
                  style: pw.TextStyle(font: bold, fontSize: 11, decoration: pw.TextDecoration.underline),
                ),
                pw.TextSpan(
                  text: ', of legal age, Filipino, and a resident of ${data.address}, '
                      'Barangay ${data.barangayName}, ${data.municipality}, ${data.province}, is declared to be ',
                  style: pw.TextStyle(font: regular, fontSize: 11),
                ),
                pw.TextSpan(
                  text: 'single and not married',
                  style: pw.TextStyle(font: bold, fontSize: 11),
                ),
                pw.TextSpan(
                  text: ' based on available barangay records and personal declaration of the above-named individual.',
                  style: pw.TextStyle(font: regular, fontSize: 11),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 10),
          pw.Text(
            '\t\tThis certification is being issued upon the request of the above-named person for whatever lawful purpose it may serve.',
            style: pw.TextStyle(font: regular, fontSize: 11),
            textAlign: pw.TextAlign.justify,
          ),
          pw.SizedBox(height: 10),
          pw.RichText(
            textAlign: pw.TextAlign.justify,
            text: pw.TextSpan(
              children: [
                pw.TextSpan(text: '\t\tIssued this ', style: pw.TextStyle(font: regular, fontSize: 11)),
                pw.TextSpan(
                  text: '${data.dateDay} day of ${data.dateMonth}, ${data.dateYear}',
                  style: pw.TextStyle(font: regular, fontSize: 11, decoration: pw.TextDecoration.underline),
                ),
                pw.TextSpan(
                  text: ' at the Office of the Punong Barangay, Barangay ${data.barangayName}, '
                      '${data.municipality}, ${data.province}, Philippines.',
                  style: pw.TextStyle(font: regular, fontSize: 11),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 40),
          _buildSignatureBlock(
            name: data.punongBarangayName,
            title: 'Punong Barangay',
            signatureBytes: signatureBytes,
            bold: bold, regular: regular,
          ),
          pw.SizedBox(height: 20),
          pw.Text(
            '"This does not replace PSA-issued CENOMAR."',
            style: pw.TextStyle(font: pw.Font.helveticaOblique(), fontSize: 9, color: PdfColors.grey700),
          ),
        ],
      ), stamps, textOverlays),
    ),
  );
  return doc.save();
}

// ─────────────────────────────────────────────────────────────────────────────
// Dispatcher — call the right template by document type string
// ─────────────────────────────────────────────────────────────────────────────

Future<Uint8List> generateDocument(
  String documentType,
  DocumentData data, {
  Uint8List? logoLeftBytes,
  Uint8List? logoRightBytes,
  Uint8List? signatureBytes,
  List<SignatureStamp> stamps = const [],
  List<TextOverlay> textOverlays = const [],
}) {
  switch (documentType) {
    case 'Certificate of Residency':
      return generateCertificateOfResidency(data,
          logoLeftBytes: logoLeftBytes, logoRightBytes: logoRightBytes,
          signatureBytes: signatureBytes, stamps: stamps, textOverlays: textOverlays);
    case 'Certificate of Good Moral Character':
      return generateCertificateOfGoodMoral(data,
          logoLeftBytes: logoLeftBytes, logoRightBytes: logoRightBytes,
          signatureBytes: signatureBytes, stamps: stamps, textOverlays: textOverlays);
    case 'Certificate of Indigency':
      return generateCertificateOfIndigency(data,
          logoLeftBytes: logoLeftBytes, logoRightBytes: logoRightBytes,
          signatureBytes: signatureBytes, stamps: stamps, textOverlays: textOverlays);
    case 'Certificate of No Income':
      return generateCertificateOfNoIncome(data,
          logoLeftBytes: logoLeftBytes, logoRightBytes: logoRightBytes,
          signatureBytes: signatureBytes, stamps: stamps, textOverlays: textOverlays);
    case 'Certificate of No Property':
      return generateCertificateOfNoProperty(data,
          logoLeftBytes: logoLeftBytes, logoRightBytes: logoRightBytes,
          signatureBytes: signatureBytes, stamps: stamps, textOverlays: textOverlays);
    case 'Certificate of Single Status':
      return generateCertificateOfSingleStatus(data,
          logoLeftBytes: logoLeftBytes, logoRightBytes: logoRightBytes,
          signatureBytes: signatureBytes, stamps: stamps, textOverlays: textOverlays);
    case 'Barangay Clearance':
    default:
      return generateBarangayClearance(data,
          logoLeftBytes: logoLeftBytes, logoRightBytes: logoRightBytes,
          signatureBytes: signatureBytes, stamps: stamps, textOverlays: textOverlays);
  }
}
