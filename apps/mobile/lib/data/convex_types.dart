/// Small types shared by the Convex gateway, the outbox and the stores.
/// Pure Dart: no Flutter and no `dartvex` here.
library;

import '../models.dart';

/// Coarse link state to the hosted backend.
enum ConvexLink { notConfigured, connecting, connected, reconnecting, offline }

/// Result of one authenticated test call.
enum AccessStatus { ok, notConfigured, unauthorized, unreachable, failed }

/// Why a call failed. Decides what the outbox does with a write.
enum ConvexFailure {
  /// The server refused this write and said why. Sending it again is pointless.
  rejected,

  /// The token was not accepted. Keep the write; the user must fix the token.
  unauthorized,

  /// No answer, a timeout or a server fault. Keep the write and retry.
  transient,
}

/// The one error the gateway throws. [message] is safe to show to the user:
/// it comes from the Convex error `.data`, never from the raw `.message`
/// (which carries a server stack trace).
class ConvexCallException implements Exception {
  const ConvexCallException(this.message, {this.kind = ConvexFailure.transient});

  /// Builds the exception from the parts of a Convex error. [data] is the
  /// `ConvexError` payload (a string or an object with a `message`), or null.
  factory ConvexCallException.fromData(Object? data) {
    if (data is Map && data['message'] is String) {
      return ConvexCallException(data['message'] as String, kind: ConvexFailure.rejected);
    }
    if (data is String && data.isNotEmpty) {
      if (data == 'unauthorized') {
        return const ConvexCallException.unauthorized();
      }
      return ConvexCallException(data, kind: ConvexFailure.rejected);
    }
    return const ConvexCallException(
      'The server could not finish that. The app will try again.',
    );
  }

  const ConvexCallException.unauthorized()
      : message = 'The token was not accepted. Check it in Settings.',
        kind = ConvexFailure.unauthorized;

  const ConvexCallException.notConfigured()
      : message = 'Set the server address and token in Settings.',
        kind = ConvexFailure.transient;

  const ConvexCallException.unreachable()
      : message = 'Could not reach the server.',
        kind = ConvexFailure.transient;

  final String message;
  final ConvexFailure kind;

  bool get rejected => kind == ConvexFailure.rejected;
  bool get unauthorized => kind == ConvexFailure.unauthorized;

  @override
  String toString() => 'ConvexCallException($kind): $message';
}

/// A read-model answer. [stored] false means "rules answer, the AI version is
/// not built yet": the stream pushes the AI version later.
class Stored<T> {
  const Stored(this.value, {required this.stored, this.source = 'rules'});

  final T value;
  final bool stored;

  /// `ai` or `rules`.
  final String source;
}

/// True for a hosted Convex address (`https://<name>.convex.cloud`).
bool isConvexUrl(String url) {
  final Uri? u = Uri.tryParse(url.trim());
  if (u == null || u.host.isEmpty) {
    return false;
  }
  return u.host.endsWith('.convex.cloud') || u.host.endsWith('.convex.site') || u.port == 3210;
}

/// True when [url] can be opened as a Convex deployment address.
bool isUsableServerUrl(String url) {
  final Uri? u = Uri.tryParse(url.trim());
  return u != null && (u.scheme == 'https' || u.scheme == 'http') && u.host.isNotEmpty;
}

/// File details and a URL that serves the bytes (null when storage lost them).
class FileLink {
  const FileLink(this.meta, this.url);

  final FileMeta meta;
  final String? url;
}
