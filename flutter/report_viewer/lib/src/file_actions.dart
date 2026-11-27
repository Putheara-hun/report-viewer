import 'package:flutter/widgets.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import 'report_file.dart';

/// What a phone does with the viewer's files when the app does not take them itself (ReportViewer.onFile):
/// Print -> the phone's print screen (printers, Save as PDF); an export -> the share sheet (Files, Drive, Telegram,
/// e-mail ...).
Future<void> defaultFileAction(BuildContext context, ReportFile file) async {
  if (file.action == ReportFileAction.print && file.isPdf) {
    await Printing.layoutPdf(onLayout: (_) async => file.bytes, name: file.name);
    return;
  }
  // an iPad needs to know where the share sheet points from
  final box = context.findRenderObject() as RenderBox?;
  final origin = box != null && box.hasSize ? box.localToGlobal(Offset.zero) & box.size : null;
  await Share.shareXFiles(
    [XFile.fromData(file.bytes, mimeType: file.mime, name: file.name)],
    fileNameOverrides: [file.name],
    subject: file.name,
    sharePositionOrigin: origin,
  );
}
