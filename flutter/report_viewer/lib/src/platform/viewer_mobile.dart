import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../session.dart';

/// Android / iOS: a web view with a small page that holds the viewer in an iframe and passes the messages
/// between the viewer and Dart (the JavaScript channel `ReportViewerApp` one way, `rvSend(...)` the other).
/// The page's address is the viewer's own site, so the viewer accepts it as its host.
PlatformViewer createPlatformViewer(Uri viewerUrl) => _MobileViewer(viewerUrl);

class _MobileViewer extends PlatformViewer {
  _MobileViewer(Uri viewerUrl) {
    final origin = viewerUrl.origin;
    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..enableZoom(false) // the viewer zooms its pages itself (two fingers)
      ..addJavaScriptChannel('ReportViewerApp', onMessageReceived: (JavaScriptMessage m) {
        final data = jsonDecode(m.message);
        if (data is Map) deliver(data.map((k, v) => MapEntry('$k', v as Object?)));
      })
      ..loadHtmlString(_hostPage(viewerPageUrl(viewerUrl, origin), origin), baseUrl: '$origin/');
  }

  late final WebViewController _web;

  @override
  void send(Map<String, Object?> message) {
    // JSON is a JavaScript value: the message goes in as it is
    _web.runJavaScript('rvSend(${jsonEncode(message)});');
  }

  // a web view can neither download nor print: Export and Print come to the app
  @override
  bool get takesFilesByDefault => true;

  @override
  Widget build(BuildContext context) => WebViewWidget(controller: _web);

  @override
  void dispose() {}
}

String _hostPage(Uri viewerPage, String origin) => '''<!doctype html>
<html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
<style>html,body{margin:0;height:100%;overflow:hidden}iframe{display:block;width:100%;height:100%;border:0}</style>
</head><body>
<script>
  var ORIGIN = ${jsonEncode(origin)};
  var frame = document.createElement('iframe');
  frame.setAttribute('allow', 'clipboard-write');
  frame.title = 'Report';
  // the viewer -> Dart (only messages of the viewer in this frame)
  window.addEventListener('message', function (e) {
    if (e.source !== frame.contentWindow || e.origin !== ORIGIN) return;
    var m = e.data;
    if (!m || typeof m.type !== 'string' || m.type.indexOf('reportviewer:') !== 0) return;
    ReportViewerApp.postMessage(JSON.stringify(m));
  });
  // Dart -> the viewer
  window.rvSend = function (m) { frame.contentWindow.postMessage(m, ORIGIN); };
  frame.src = ${jsonEncode(viewerPage.toString())};
  document.body.appendChild(frame);
</script>
</body></html>''';
