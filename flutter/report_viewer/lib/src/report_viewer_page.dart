import 'package:flutter/material.dart';

import 'report_api.dart';
import 'report_viewer_widget.dart';
import 'session.dart';

/// A whole report screen: an app bar (title, Refresh, Print, Export) and the report. [load] gets the report from
/// your API - called at once, on Refresh and on the viewer's own Refresh button.
class ReportViewerPage extends StatefulWidget {
  const ReportViewerPage({
    super.key,
    required this.title,
    required this.load,
    this.viewerUrl = kDefaultViewerUrl,
    this.theme,
    this.labels,
  });

  final String title;

  /// your API's answer `{ report, data, params }`, e.g. `() => api.view('rpt.payslip', filter: {...})`
  final Future<Map<String, dynamic>> Function() load;
  final String viewerUrl;

  /// `light` / `dark`; empty = like the app's theme
  final String? theme;

  /// the viewer's words in your language, e.g. `{'rpt_print': 'បោះពុម្ព'}`
  final Map<String, String>? labels;

  @override
  State<ReportViewerPage> createState() => _ReportViewerPageState();
}

class _ReportViewerPageState extends State<ReportViewerPage> {
  final _controller = ReportViewerController();
  bool _busy = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _show();
  }

  Future<void> _show() async {
    if (!_busy) {
      setState(() {
        _busy = true;
        _error = null;
      });
    }
    try {
      await _controller.load(await widget.load());
    } catch (e) {
      _error = e is ReportException ? e.message : '$e';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme ?? (Theme.of(context).brightness == Brightness.dark ? 'dark' : 'light');
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), tooltip: 'Refresh', onPressed: _busy ? null : _show),
          IconButton(icon: const Icon(Icons.print_outlined), tooltip: 'Print', onPressed: _busy ? null : () => _run(_controller.print)),
          PopupMenuButton<String>(
            icon: const Icon(Icons.ios_share),
            tooltip: 'Export',
            enabled: !_busy,
            onSelected: (format) => _run(() => _controller.exportAs(format)),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'pdf', child: Text('PDF')),
              PopupMenuItem(value: 'xlsx', child: Text('Excel (.xlsx)')),
              PopupMenuItem(value: 'docx', child: Text('Word (.docx)')),
              PopupMenuItem(value: 'png', child: Text('Image (.png)')),
            ],
          ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: ReportViewer(
              controller: _controller,
              viewerUrl: widget.viewerUrl,
              theme: theme,
              labels: widget.labels,
              onRefresh: _show,
              onError: (e) => setState(() => _error = e.message),
            ),
          ),
          if (_busy) const Positioned(left: 0, right: 0, top: 0, child: LinearProgressIndicator()),
          if (_error != null)
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: Material(
                elevation: 3,
                borderRadius: BorderRadius.circular(10),
                color: Theme.of(context).colorScheme.errorContainer,
                child: ListTile(
                  leading: const Icon(Icons.error_outline),
                  title: Text(_error!),
                  trailing: IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => _error = null)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
