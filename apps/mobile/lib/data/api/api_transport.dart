import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'open_gym_api.dart';

/// Low-level HTTP: base URL, Bearer token, JSON, a timeout on every call and
/// one error type ([ApiException]).
class ApiTransport {
  ApiTransport({http.Client? client}) : _client = client ?? http.Client();

  static const Duration defaultTimeout = Duration(seconds: 4);
  static const Duration planTimeout = Duration(seconds: 12);
  static const Duration longTimeout = Duration(seconds: 60);

  final http.Client _client;
  String _base = '';
  String _token = '';

  void configure(String serverUrl, String token) {
    _base = normalizeBaseUrl(serverUrl);
    _token = token.trim();
  }

  bool get configured => _base.isNotEmpty;

  /// "192.168.1.5:8787/" becomes "http://192.168.1.5:8787".
  static String normalizeBaseUrl(String raw) {
    String u = raw.trim();
    if (u.isEmpty) {
      return '';
    }
    if (!u.startsWith('http://') && !u.startsWith('https://')) {
      u = 'http://$u';
    }
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    return u;
  }

  Map<String, String> _headers({bool json = false}) {
    final Map<String, String> h = <String, String>{};
    if (_token.isNotEmpty) {
      h['Authorization'] = 'Bearer $_token';
    }
    if (json) {
      h['Content-Type'] = 'application/json';
    }
    return h;
  }

  Uri _uri(String path) {
    if (!configured) {
      throw const ApiException('No server set. Open Settings and add the URL.');
    }
    try {
      return Uri.parse('$_base$path');
    } on FormatException {
      throw const ApiException('The server URL looks wrong.');
    }
  }

  Future<http.Response> _run(
    Future<http.Response> Function() call,
    Duration timeout,
  ) async {
    try {
      return await call().timeout(timeout);
    } on ApiException {
      rethrow;
    } on TimeoutException {
      throw const ApiException('The server did not answer in time.');
    } on SocketException {
      throw const ApiException('Cannot reach the server.');
    } on http.ClientException {
      throw const ApiException('Cannot reach the server.');
    } on FormatException {
      throw const ApiException('The server URL looks wrong.');
    } catch (_) {
      throw const ApiException('Something went wrong talking to the server.');
    }
  }

  http.Response _check(http.Response res) {
    final int code = res.statusCode;
    if (code >= 200 && code < 300) {
      return res;
    }
    String msg = 'The server said no (HTTP $code).';
    if (code == 401) {
      msg = 'The token was not accepted. Check it in Settings.';
    } else {
      try {
        final Object? body = jsonDecode(utf8.decode(res.bodyBytes));
        if (body is Map && body['error'] is String) {
          msg = body['error'] as String;
        }
      } catch (_) {
        // keep the default message
      }
    }
    throw ApiException(msg, statusCode: code);
  }

  Map<String, dynamic> _json(http.Response res) {
    try {
      final Object? body = jsonDecode(utf8.decode(res.bodyBytes));
      if (body is Map) {
        return Map<String, dynamic>.from(body);
      }
    } catch (_) {
      // fall through
    }
    throw const ApiException('The server sent something unexpected.');
  }

  Future<Map<String, dynamic>> get(String path, [Duration? t]) async {
    final Uri u = _uri(path);
    final http.Response r =
        await _run(() => _client.get(u, headers: _headers()), t ?? defaultTimeout);
    return _json(_check(r));
  }

  Future<Map<String, dynamic>> send(
    String method,
    String path,
    Object? body, [
    Duration? t,
  ]) async {
    final Uri u = _uri(path);
    final String? payload = body == null ? null : jsonEncode(body);
    final Map<String, String> h = _headers(json: payload != null);
    Future<http.Response> call() {
      switch (method) {
        case 'POST':
          return _client.post(u, headers: h, body: payload);
        case 'PUT':
          return _client.put(u, headers: h, body: payload);
        case 'PATCH':
          return _client.patch(u, headers: h, body: payload);
        default:
          return _client.delete(u, headers: h);
      }
    }

    final http.Response r = await _run(call, t ?? defaultTimeout);
    return _json(_check(r));
  }

  Future<Map<String, dynamic>> upload(
    String path,
    String field,
    List<UploadItem> items,
  ) async {
    final Uri u = _uri(path);
    Future<http.Response> call() async {
      final http.MultipartRequest req = http.MultipartRequest('POST', u);
      req.headers.addAll(_headers());
      for (final UploadItem it in items) {
        req.files.add(
          await http.MultipartFile.fromPath(field, it.path, filename: it.name),
        );
      }
      final http.StreamedResponse streamed = await _client.send(req);
      return http.Response.fromStream(streamed);
    }

    final http.Response r = await _run(call, longTimeout);
    return _json(_check(r));
  }

  Future<List<int>> bytes(String path) async {
    final Uri u = _uri(path);
    final http.Response r =
        await _run(() => _client.get(u, headers: _headers()), longTimeout);
    return _check(r).bodyBytes;
  }
}

List<T> parseList<T>(Object? raw, T Function(Map<String, dynamic>) f) {
  final List<T> out = <T>[];
  if (raw is List) {
    for (final Object? e in raw) {
      if (e is Map) {
        out.add(f(Map<String, dynamic>.from(e)));
      }
    }
  }
  return out;
}

Map<String, dynamic> parseObj(Map<String, dynamic> j, String key) {
  final Object? v = j[key];
  if (v is Map) {
    return Map<String, dynamic>.from(v);
  }
  throw const ApiException('The server sent something unexpected.');
}
