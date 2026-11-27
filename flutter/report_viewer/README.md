# report_viewer (Flutter)

The Report Viewer in a Flutter app: **Android, iOS and web**. The report looks and works as in the web
application (pages, zoom, find, export, print); on a phone the toolbar is short, the pages fit the width, two
fingers zoom and a long press opens the copy menu.

- Android / iOS: the viewer in a web view (`webview_flutter`). A web view cannot download or print, so Print gives
  the app a PDF (the phone's print screen opens) and an export gives the app the file (the share sheet opens: Files,
  Drive, Telegram, e-mail …). Or take the files yourself with `onFile`.
- Web: the viewer in an iframe; the browser downloads and prints itself.

## Add it to your app

Copy this folder into your project (or keep it in this repository) and add it to `pubspec.yaml`:

```yaml
dependencies:
  report_viewer:
    path: ../report_viewer          # or: git: { url: https://github.com/Putheara-hun/report-viewer.git, path: flutter/report_viewer }
```

Android: the app needs the internet permission in `android/app/src/main/AndroidManifest.xml` (Flutter adds it only
for debug builds):

```xml
<uses-permission android:name="android.permission.INTERNET" />
```

iOS and web need nothing else.

## Your API

Your server answers a report request with the design text and the rows - HRMS's `POST /api/report/view` does:

```json
{ "report": "<the design text>", "data": [ { "EMP_CODE": "E001", "NET_PAY": 500 } ], "params": { "TITLE": "Payslip" } }
```

`data` is the rows of the main data source, or `{ "DataSet1": [...], "DataSet2": [...] }`.

## A whole report screen

```dart
import 'package:report_viewer/report_viewer.dart';

final api = ReportApi(
  baseUrl: 'https://hrms.example.com',
  // the same headers as your app's other calls (HRMS: the login's token, company and device)
  headers: () => {'x-auth': session.token, 'x-cred': session.company, 'x-user': session.device},
);

Navigator.push(context, MaterialPageRoute(builder: (_) => ReportViewerPage(
  title: 'Payslip',
  load: () => api.view(
    'rpt.payslip',                                   // the report's code (Report Settings)
    filter: {'PRD_CODE': '2026-11'},                 // the procedure's parameters
    params: {'LANG': 'km', 'PRINTED_BY': 'Sok Dara'}, // texts printed on the report
  ),
)));
```

## The widget in your own screen

```dart
final viewer = ReportViewerController();

// in build():
ReportViewer(
  controller: viewer,
  theme: 'light',                                    // or 'dark'
  labels: {'rpt_print': 'បោះពុម្ព', 'rpt_export': 'នាំចេញ'},   // the viewer's words in your language
  onRefresh: reload,                                 // the viewer's Refresh button
  // onFile: (file) => save(file.name, file.bytes),  // take Print / Export yourself (file.action: download | print)
);

// then:
await viewer.load(await api.view('rpt.salary', filter: {'PRD_CODE': '2026-11'}));
// or a design and rows from anywhere:
await viewer.loadReport(designText, data: rows, params: {'TITLE': 'Sales'});
await viewer.print();
await viewer.exportAs('pdf');                        // pdf | xlsx | docx | csv | html | png
```

See `example/lib/main.dart` (`cd example && flutter create . && flutter run`).

## How it works

The viewer is a web page (`viewer.html?embed=1`) that talks with the page around it through `postMessage`
(`reportviewer:ready / init / load / print / export / file …`, see `src/viewer/host.ts`). On the web the iframe is
in your app's page; on a phone the web view holds a small page with the iframe that passes the messages to Dart
(JavaScript channel `ReportViewerApp`). `viewerUrl` changes where the viewer is published.
