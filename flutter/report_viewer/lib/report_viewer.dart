/// The Report Viewer in a Flutter app (Android, iOS, web).
///
/// ```dart
/// final controller = ReportViewerController();
/// ReportViewer(controller: controller);                       // a widget anywhere in your screen
/// await controller.load(await api.view('rpt.payslip', filter: {'PRD_CODE': '2026-11'}));
/// ```
/// or the whole screen at once:
/// ```dart
/// Navigator.push(context, MaterialPageRoute(builder: (_) => ReportViewerPage(
///   title: 'Payslip',
///   load: () => api.view('rpt.payslip', filter: {'PRD_CODE': '2026-11'}, params: {'LANG': 'km'}),
/// )));
/// ```
library report_viewer;

export 'src/report_api.dart' show ReportApi, ReportException;
export 'src/report_file.dart' show ReportFile, ReportFileAction;
export 'src/report_viewer_page.dart' show ReportViewerPage;
export 'src/report_viewer_widget.dart' show ReportViewer, ReportViewerController;
export 'src/session.dart' show ReportViewerException, kDefaultViewerUrl;
