// How a Flutter app (Android, iOS or web) shows the reports of its system with the Report Viewer.
//
//   1. ReportApi asks your API for a report: { report: <design text>, data: <rows>, params: {...} }
//   2. ReportViewerPage (a whole screen) or ReportViewer (a widget) shows it.
//
// Run:  cd example && flutter create . && flutter run      (Android: see the README for the INTERNET permission)
import 'package:flutter/material.dart';
import 'package:report_viewer/report_viewer.dart';

/// What your app keeps after the user logs in (HRMS: the token, the company and the device it logged in from).
class Session {
  static String token = '';
  static String company = '';
  static String device = '';
  static String userName = 'Me';
}

/// Your system's report API. HRMS: POST /api/report/view, the user proved by the headers of its login.
final api = ReportApi(
  baseUrl: 'https://your-hrms-api.example.com',
  headers: () => {'x-auth': Session.token, 'x-cred': Session.company, 'x-user': Session.device},
);

void main() => runApp(const ExampleApp());

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Reports',
        theme: ThemeData(colorSchemeSeed: const Color(0xFF4338CA), useMaterial3: true),
        darkTheme: ThemeData(colorSchemeSeed: const Color(0xFF4338CA), brightness: Brightness.dark, useMaterial3: true),
        home: const PayslipFilterScreen(),
      );
}

/// Example 1 - a report of your system: choose the month, then the report from the API on its own screen.
class PayslipFilterScreen extends StatefulWidget {
  const PayslipFilterScreen({super.key});

  @override
  State<PayslipFilterScreen> createState() => _PayslipFilterScreenState();
}

class _PayslipFilterScreenState extends State<PayslipFilterScreen> {
  late final List<DateTime> _months = List.generate(12, (i) {
    final now = DateTime.now();
    return DateTime(now.year, now.month - i);
  });
  late DateTime _month = _months.first;
  String _lang = 'km';

  String _code(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}'; // 2026-11

  void _preview() {
    final month = _code(_month);
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ReportViewerPage(
        title: 'Payslip $month',
        // the viewer's words in Khmer (keys left out stay English)
        labels: _lang == 'km' ? const {'rpt_print': 'បោះពុម្ព', 'rpt_export': 'នាំចេញ', 'rpt_find': 'ស្វែងរក', 'rpt_of': 'នៃ'} : null,
        load: () => api.view(
          'rpt.payslip', // the report's code in Report Settings
          filter: {'PRD_CODE': month}, // the procedure's parameters
          params: {'LANG': _lang, 'FILTER': month, 'PRINTED_BY': Session.userName}, // texts printed on it
        ),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Payslip')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            DropdownButtonFormField<DateTime>(
              value: _month,
              decoration: const InputDecoration(labelText: 'Salary month', border: OutlineInputBorder()),
              items: [for (final m in _months) DropdownMenuItem(value: m, child: Text(_code(m)))],
              onChanged: (m) => setState(() => _month = m ?? _month),
            ),
            const SizedBox(height: 12),
            SegmentedButton<String>(
              segments: const [ButtonSegment(value: 'km', label: Text('ខ្មែរ')), ButtonSegment(value: 'en', label: Text('English'))],
              selected: {_lang},
              onSelectionChanged: (s) => setState(() => _lang = s.first),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(onPressed: _preview, icon: const Icon(Icons.description_outlined), label: const Text('Preview')),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const OwnDataScreen())),
              child: const Text('Example 2: a design and rows from anywhere'),
            ),
          ],
        ),
      );
}

/// Example 2 - no report API: the viewer only needs a design text (from the designer: Copy Text, or saved in your
/// database) and the rows. Here the widget sits in your own screen and you keep the buttons.
class OwnDataScreen extends StatefulWidget {
  const OwnDataScreen({super.key});

  @override
  State<OwnDataScreen> createState() => _OwnDataScreenState();
}

class _OwnDataScreenState extends State<OwnDataScreen> {
  final _viewer = ReportViewerController();
  String _status = '';

  // A small design: a title ({?TITLE}) and one line per row ([ITEM], [AMOUNT]). Yours comes from the designer
  // (Copy Text: JSON, HTML or RDL), from your database or a file; the rows from your database, a file, another API ...
  static const _design = r'''
{"version":1,"name":"Sales",
 "page":{"paper":"A4","orientation":"portrait","width":793.7,"height":1122.5,"baseWidth":793.7,"autoWidth":false,"autoHeight":false,
         "margins":{"top":40,"right":40,"bottom":40,"left":40}},
 "bands":[{"id":"b1","type":"pageHeader","height":40,"visible":true,"printOnFirstPage":true,"printOnLastPage":true},
          {"id":"b2","type":"detail","height":24,"visible":true}],
 "elements":[
  {"id":"e1","bandId":"b1","name":"txtTitle","type":"text","x":0,"y":0,"width":400,"height":30,"text":"{?TITLE}","expression":"","format":"",
   "summaryFunc":"none","summaryRunning":"none","wordWrap":true,"canGrow":false,"canShrink":false,"nullText":"","style":{"fontSize":16,"bold":true}},
  {"id":"e2","bandId":"b2","name":"txtItem","type":"text","x":0,"y":0,"width":300,"height":22,"text":"","expression":"[ITEM]","format":"",
   "summaryFunc":"none","summaryRunning":"none","wordWrap":true,"canGrow":false,"canShrink":false,"nullText":"","style":{}},
  {"id":"e3","bandId":"b2","name":"txtAmount","type":"text","x":300,"y":0,"width":120,"height":22,"text":"","expression":"[AMOUNT]","format":"n2",
   "summaryFunc":"none","summaryRunning":"none","wordWrap":true,"canGrow":false,"canShrink":false,"nullText":"","style":{"textAlign":"right"}}],
 "groups":[],"sort":[],"filter":"","dataSourceId":"ds1","detailReports":[],
 "dataSources":[{"id":"ds1","name":"DataSet1","kind":"json","content":"[]",
                 "fields":[{"name":"ITEM","type":"string"},{"name":"AMOUNT","type":"number"}]}],
 "parameters":[{"id":"p1","name":"TITLE","label":"TITLE","type":"string","defaultValue":"","values":"","visible":false}],
 "calculatedFields":[],"styles":[],
 "baseStyle":{"fontFamily":"Arial","fontSize":10,"bold":false,"italic":false,"underline":false,"strike":false,"color":"#111827",
              "backColor":"","textAlign":"left","vAlign":"middle","padding":3,"borders":"","borderWidth":1,"borderColor":"#d1d5db","borderStyle":"solid"},
 "locale":"en-US","currency":"USD"}
''';

  @override
  void initState() {
    super.initState();
    _viewer.loadReport(
      _design,
      data: const [
        {'ITEM': 'Coffee', 'AMOUNT': 2.5},
        {'ITEM': 'Tea', 'AMOUNT': 1.75},
      ],
      params: const {'TITLE': 'Sales'},
    ).catchError((Object e) => setState(() => _status = '$e'));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Sales'),
          actions: [
            IconButton(icon: const Icon(Icons.print_outlined), onPressed: () => _viewer.print()),
            IconButton(icon: const Icon(Icons.picture_as_pdf_outlined), onPressed: () => _viewer.exportAs('pdf')),
          ],
        ),
        body: Column(
          children: [
            if (_status.isNotEmpty) Padding(padding: const EdgeInsets.all(8), child: Text(_status)),
            Expanded(
              child: ReportViewer(
                controller: _viewer,
                onRendered: (pages) => setState(() => _status = '$pages page(s)'),
                // take the files yourself instead of the print screen / share sheet:
                // onFile: (file) => saveSomewhere(file.name, file.bytes),
              ),
            ),
          ],
        ),
      );
}
