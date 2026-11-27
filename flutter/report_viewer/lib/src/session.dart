import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// The published Report Viewer (the folder of viewer.html and viewer.js).
const String kDefaultViewerUrl = 'https://report-viewer-h88h.onrender.com/';

/// The viewer could not do what was asked (its own sentence), or it was closed.
class ReportViewerException implements Exception {
  const ReportViewerException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// The viewer's address with a slash at the end, so `viewer.html` resolves inside it.
Uri normalizeViewerUrl(String url) {
  final u = Uri.parse(url.trim());
  return u.path.endsWith('/') ? u : u.replace(path: '${u.path}/');
}

/// The page that runs inside the frame: embed=1 (talk to the page around it), origins = who may talk to it.
Uri viewerPageUrl(Uri viewerUrl, String hostOrigin) =>
    viewerUrl.resolve('viewer.html').replace(queryParameters: {'embed': '1', 'origins': hostOrigin});

/// One platform's way to show the viewer and pass messages to and from it: a web view (Android / iOS) or an
/// iframe (Flutter web). The messages are the viewer's own (`reportviewer:*`, see src/viewer/host.ts).
abstract class PlatformViewer {
  /// set by the session: a message from the viewer
  void Function(Map<String, Object?> message)? onMessage;

  @protected
  void deliver(Map<String, Object?> message) => onMessage?.call(message);

  /// a message to the viewer
  void send(Map<String, Object?> message);

  /// true where the platform cannot download or print by itself (a phone's web view): the app takes the files
  bool get takesFilesByDefault;

  Widget build(BuildContext context);
  void dispose();
}

/// The conversation with one viewer: waits for `ready`, sends the words / theme / layout / who takes the files,
/// numbers each request and completes it with the viewer's answer, passes the rest (rendered, refresh, error, file)
/// to [onEvent].
class ViewerSession {
  ViewerSession(this.platform, {required this.init, required this.onEvent}) {
    platform.onMessage = _onMessage;
  }

  final PlatformViewer platform;
  final Map<String, Object?> Function() init;
  final void Function(String type, Map<String, Object?> message) onEvent;

  final Completer<void> _ready = Completer<void>();
  final Map<String, Completer<Map<String, Object?>>> _pending = {};
  int _seq = 0;
  bool _closed = false;

  Future<void> get ready => _ready.future;

  void _onMessage(Map<String, Object?> m) {
    final full = m['type'];
    if (full is! String || !full.startsWith('reportviewer:')) return;
    final type = full.substring('reportviewer:'.length);
    final id = m['requestId'];
    if (id is String && _pending.containsKey(id)) {
      final c = _pending.remove(id)!;
      if (type == 'error') {
        c.completeError(ReportViewerException('${m['message'] ?? 'The report viewer failed.'}'));
      } else {
        c.complete(m);
      }
      return;
    }
    if (type == 'ready') {
      // first the words, theme and layout, so the report never shows in the wrong language or colours
      platform.send(_clean({'type': 'reportviewer:init', ...init()}));
      if (!_ready.isCompleted) _ready.complete();
      return;
    }
    onEvent(type, m);
  }

  /// a request (load, print, export, setData, setParams, refresh, init) and the viewer's answer
  Future<Map<String, Object?>> request(String type, Map<String, Object?> data) async {
    await ready;
    if (_closed) throw const ReportViewerException('The report viewer was closed.');
    final id = 'f${++_seq}';
    final c = Completer<Map<String, Object?>>();
    _pending[id] = c;
    platform.send(_clean({...data, 'type': 'reportviewer:$type', 'requestId': id}));
    return c.future;
  }

  void dispose() {
    _closed = true;
    for (final c in _pending.values) {
      if (!c.isCompleted) c.completeError(const ReportViewerException('The report viewer was closed.'));
    }
    _pending.clear();
    platform.dispose();
  }

  // the viewer treats a missing value and null differently: nulls are left out
  static Map<String, Object?> _clean(Map<String, Object?> m) => Map.of(m)..removeWhere((_, v) => v == null);
}
