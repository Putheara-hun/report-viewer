import '../session.dart';

/// Neither a web view (dart:io) nor a browser (dart:js_interop): not supported.
PlatformViewer createPlatformViewer(Uri viewerUrl) =>
    throw UnsupportedError('The Report Viewer needs Android, iOS or the web.');
