import 'dart:convert';
import 'dart:typed_data';

/// What the user asked for: an export (download) or Print (the report as a PDF to print).
enum ReportFileAction { download, print }

/// A file the viewer made: an export (PDF, Excel, Word, CSV, HTML, PNG) or the PDF of Print.
class ReportFile {
  const ReportFile({required this.name, required this.mime, required this.action, required this.bytes});

  /// e.g. `Payslip.pdf`, `Payslip.xlsx`
  final String name;

  /// e.g. `application/pdf`
  final String mime;
  final ReportFileAction action;
  final Uint8List bytes;

  bool get isPdf => mime == 'application/pdf' || name.toLowerCase().endsWith('.pdf');

  /// from the viewer's `reportviewer:file` message (the bytes come as base64)
  factory ReportFile.fromMessage(Map<String, Object?> m) => ReportFile(
        name: '${m['name'] ?? 'report'}',
        mime: '${m['mime'] ?? 'application/octet-stream'}',
        action: m['action'] == 'print' ? ReportFileAction.print : ReportFileAction.download,
        bytes: base64Decode('${m['base64'] ?? ''}'),
      );
}
