import 'dart:convert';

import 'package:http/http.dart' as http;

/// Your API refused the report (its own sentence: no right, not set up, a filter missing ...).
class ReportException implements Exception {
  const ReportException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;
  @override
  String toString() => message;
}

/// Asks your system's report API for a report: `POST {baseUrl}{viewPath}` with `{ RPT_CODE, the filter, PARAMS }`
/// and answers `{ report, data, params }` for [ReportViewerController.load] - e.g. HRMS's /api/report/view.
///
/// ```dart
/// final api = ReportApi(
///   baseUrl: 'https://hrms.example.com',
///   headers: () => {'x-auth': session.token, 'x-cred': session.company, 'x-user': session.device},
/// );
/// final answer = await api.view('rpt.payslip', filter: {'PRD_CODE': '2026-11'}, params: {'LANG': 'km'});
/// ```
class ReportApi {
  ReportApi({required this.baseUrl, this.viewPath = '/api/report/view', this.headers, http.Client? client})
      : _client = client ?? http.Client();

  final String baseUrl;
  final String viewPath;

  /// who is asking - the same headers the app's other calls send (read each time, so a new login is used)
  final Map<String, String> Function()? headers;
  final http.Client _client;

  Future<Map<String, dynamic>> view(
    String rptCode, {
    Map<String, Object?> filter = const {},
    Map<String, Object?> params = const {},
  }) async {
    final res = await _client.post(
      Uri.parse(baseUrl).resolve(viewPath),
      headers: {'Content-Type': 'application/json', 'Accept': 'application/json', ...?headers?.call()},
      body: jsonEncode({'RPT_CODE': rptCode, ...filter, 'PARAMS': params}),
    );
    Object? body;
    try {
      body = jsonDecode(utf8.decode(res.bodyBytes));
    } catch (_) {
      body = null;
    }
    if (body is Map<String, dynamic> && body['report'] is String && res.statusCode < 400) return body;
    final message = body is Map && body['message'] != null
        ? '${body['message']}'
        : res.statusCode == 401 || res.statusCode == 403
            ? 'You do not have permission for this report, or your login has ended.'
            : 'The report could not be loaded (HTTP ${res.statusCode}).';
    throw ReportException(message, statusCode: res.statusCode);
  }

  void close() => _client.close();
}
