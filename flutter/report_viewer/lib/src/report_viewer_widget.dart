import 'dart:async';

import 'package:flutter/widgets.dart';

import 'file_actions.dart';
import 'report_file.dart';
import 'session.dart';
import 'platform/viewer_stub.dart'
    if (dart.library.js_interop) 'platform/viewer_web.dart'
    if (dart.library.io) 'platform/viewer_mobile.dart';

/// Tells a [ReportViewer] what to show and asks it to print or export. It can be used before the widget is on
/// screen: the calls wait until the viewer is ready.
class ReportViewerController {
  Completer<ViewerSession> _attached = Completer<ViewerSession>();

  void _attach(ViewerSession s) {
    if (_attached.isCompleted) _attached = Completer<ViewerSession>();
    _attached.complete(s);
  }

  void _detach(ViewerSession s) {
    if (_attached.isCompleted) _attached = Completer<ViewerSession>();
  }

  Future<Map<String, Object?>> _request(String type, [Map<String, Object?> data = const {}]) async {
    final s = await _attached.future;
    return s.request(type, data);
  }

  /// Shows your API's answer as it is: `{ report, data, params, name?, format?, layout? }`.
  /// [params] are added to the answer's own (e.g. the user's name, the language).
  Future<void> load(Map<String, dynamic> answer, {Map<String, Object?> params = const {}}) async {
    final report = answer['report'];
    if (report is! String) {
      throw ReportViewerException('${answer['message'] ?? 'The answer has no report (its "report" text is missing).'}');
    }
    await loadReport(
      report,
      data: answer['data'],
      params: {...?(answer['params'] as Map?)?.cast<String, Object?>(), ...params},
      name: answer['name'] as String?,
      format: answer['format'] as String?,
      layout: answer['layout'] as String?,
    );
  }

  /// Shows a report from its design text and rows, wherever they come from.
  /// [data]: the rows of the main data source (a list), or `{'DataSet1': rows, 'DataSet2': rows}`.
  Future<void> loadReport(String report, {Object? data, Map<String, Object?>? params, String? name, String? format, String? layout}) =>
      _request('load', {'content': report, 'data': data, 'params': params, 'name': name, 'format': format, 'layout': layout});

  /// New rows (no [name] = the main data source); the report is drawn again.
  Future<void> setData(List<Object?> rows, {String? name}) => _request('setData', {'name': name, 'rows': rows});

  /// New parameter values (`{?NAME}` in the design); drawn again unless [refresh] is false.
  Future<void> setParams(Map<String, Object?> values, {bool refresh = true}) =>
      _request('setParams', {'values': values, 'refresh': refresh});

  /// Print. On a phone the viewer makes a PDF and the app prints it (see [ReportViewer.onFile]).
  Future<void> print() => _request('print');

  /// `pdf`, `xlsx`, `docx`, `csv`, `html` or `png`. On a phone the file comes to the app (share / save).
  Future<void> exportAs(String format) => _request('export', {'format': format});

  /// Draw again (true: the data sources that read by themselves read again).
  Future<void> refresh({bool reloadData = false}) => _request('refresh', {'reloadData': reloadData});
}

/// The Report Viewer as a widget: the report with its own toolbar (pages, zoom, find, export, print). On a phone
/// the toolbar is short, the pages fit the width and two fingers zoom.
class ReportViewer extends StatefulWidget {
  const ReportViewer({
    super.key,
    required this.controller,
    this.viewerUrl = kDefaultViewerUrl,
    this.theme = 'light',
    this.layout = 'scroll',
    this.labels,
    this.onFile,
    this.onRendered,
    this.onRefresh,
    this.onError,
  });

  final ReportViewerController controller;

  /// where the viewer is published (the folder of viewer.html)
  final String viewerUrl;

  /// `light` or `dark`
  final String theme;

  /// `scroll` (all pages one after another) or `page` (one at a time); the user can switch in the toolbar
  final String layout;

  /// the viewer's words in your language by key, e.g. `{'rpt_print': 'បោះពុម្ព'}`
  final Map<String, String>? labels;

  /// Export and Print as files. Without it: on a phone, Print opens the phone's print screen and an export opens
  /// the share sheet (save to Files, Drive, Telegram ...); on the web the browser downloads / prints.
  final void Function(ReportFile file)? onFile;

  /// the report is drawn: its number of pages
  final void Function(int pages)? onRendered;

  /// the user pressed Refresh in the viewer: load the report again (fresh rows)
  final VoidCallback? onRefresh;

  final void Function(ReportViewerException error)? onError;

  @override
  State<ReportViewer> createState() => _ReportViewerState();
}

class _ReportViewerState extends State<ReportViewer> {
  late final PlatformViewer _platform;
  late final ViewerSession _session;

  bool get _appTakesFiles => widget.onFile != null || _platform.takesFilesByDefault;

  @override
  void initState() {
    super.initState();
    _platform = createPlatformViewer(normalizeViewerUrl(widget.viewerUrl));
    _session = ViewerSession(_platform, init: _init, onEvent: _onEvent);
    widget.controller._attach(_session);
  }

  Map<String, Object?> _init() => {
        'labels': widget.labels,
        'theme': widget.theme,
        'layout': widget.layout,
        'files': _appTakesFiles ? 'host' : 'browser',
      };

  void _onEvent(String type, Map<String, Object?> m) {
    switch (type) {
      case 'rendered':
        widget.onRendered?.call((m['pages'] as num?)?.toInt() ?? 0);
      case 'refresh':
        widget.onRefresh?.call();
      case 'error':
        widget.onError?.call(ReportViewerException('${m['message'] ?? 'The report could not be shown.'}'));
      case 'file':
        final file = ReportFile.fromMessage(m);
        final take = widget.onFile;
        if (take != null) {
          take(file);
        } else if (mounted) {
          _defaultFile(file);
        }
    }
  }

  // no onFile: print / share it the phone's way
  Future<void> _defaultFile(ReportFile file) async {
    try {
      await defaultFileAction(context, file);
    } catch (e) {
      widget.onError?.call(ReportViewerException('$e'));
    }
  }

  @override
  void didUpdateWidget(ReportViewer old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller._detach(_session);
      widget.controller._attach(_session);
    }
    if (old.theme != widget.theme || old.labels != widget.labels) {
      _session.request('init', {'theme': widget.theme, 'labels': widget.labels}).ignore();
    }
  }

  @override
  void dispose() {
    widget.controller._detach(_session);
    _session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _platform.build(context);
}
