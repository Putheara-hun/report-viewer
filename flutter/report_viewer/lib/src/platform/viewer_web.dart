import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

import '../session.dart';

/// Flutter web: the viewer in an iframe of this page, talked to with postMessage - exactly what viewer.js does.
/// The browser downloads and prints by itself, so the app gets files only when it asks (ReportViewer.onFile).
PlatformViewer createPlatformViewer(Uri viewerUrl) => _WebViewer(viewerUrl);

class _WebViewer extends PlatformViewer {
  _WebViewer(Uri viewerUrl) : _origin = viewerUrl.origin {
    _frame = web.document.createElement('iframe') as web.HTMLIFrameElement;
    _frame
      ..setAttribute('src', viewerPageUrl(viewerUrl, web.window.location.origin).toString())
      ..setAttribute('allow', 'clipboard-write')
      ..setAttribute('title', 'Report')
      ..setAttribute('style', 'display:block;width:100%;height:100%;border:0');
    _viewType = 'report-viewer-${_count++}';
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int viewId) => _frame);
    _listener = _onWindowMessage.toJS;
    web.window.addEventListener('message', _listener);
  }

  static int _count = 0;
  final String _origin;
  late final web.HTMLIFrameElement _frame;
  late final String _viewType;
  late final JSFunction _listener;

  void _onWindowMessage(web.Event event) {
    final e = event as web.MessageEvent;
    // only the viewer in this frame
    if (e.origin != _origin || !e.source.strictEquals(_frame.contentWindow).toDart) return;
    final data = e.data.dartify();
    if (data is Map) deliver(data.map((k, v) => MapEntry('$k', v)));
  }

  @override
  void send(Map<String, Object?> message) => _frame.contentWindow?.postMessage(message.jsify(), _origin.toJS);

  @override
  bool get takesFilesByDefault => false;

  @override
  Widget build(BuildContext context) => HtmlElementView(viewType: _viewType);

  @override
  void dispose() => web.window.removeEventListener('message', _listener);
}
