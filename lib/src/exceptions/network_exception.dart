import 'mediaforge_exception.dart';

/// Thrown when a network error occurs during API communication.
///
/// Common causes:
/// - No internet connection
/// - DNS resolution failure
/// - Request timeout
/// - Server unreachable
class NetworkException extends MediaForgeException {
  /// The HTTP status code, if available.
  final int? statusCode;

  /// Creates a new [NetworkException].
  const NetworkException(super.message, {this.statusCode, super.code});

  /// Creates a [NetworkException] for a timeout.
  NetworkException.timeout([String? url])
      : statusCode = null,
        super(
          url != null
              ? 'Request to $url timed out. Check your internet connection and try again.'
              : 'Request timed out. Check your internet connection and try again.',
          code: 'timeout',
        );

  /// Creates a [NetworkException] for no connectivity.
  const NetworkException.noConnection()
      : statusCode = null,
        super(
          'No internet connection. Check your network and try again.',
          code: 'no_connection',
        );

  /// Creates a [NetworkException] from a server error status code.
  factory NetworkException.serverError(int statusCode, [String? message]) {
    return NetworkException(
      message ?? 'Server error $statusCode',
      statusCode: statusCode,
      code: 'server_error_$statusCode',
    );
  }

  /// Whether this exception was caused by a timeout.
  bool get isTimeout => code == 'timeout';

  /// Whether this exception was caused by network connectivity loss.
  bool get isConnectionError => code == 'no_connection';

  /// Whether this error represents an HTTP 5xx server-side error.
  bool get isServerError =>
      statusCode != null && statusCode! >= 500 && statusCode! < 600;

  /// Creates a [NetworkException] from an HTTP status code.
  factory NetworkException.fromStatusCode(int statusCode, {String? body}) {
    final fallback = switch (statusCode) {
      429 => 'Too many requests. Slow down and try again.',
      500 => 'MediaForge server error. We are looking into it.',
      502 || 503 => 'MediaForge service temporarily unavailable. Try again shortly.',
      _ => 'HTTP error $statusCode',
    };
    final message = (body != null && body.isNotEmpty) ? body : fallback;
    return NetworkException(
      message,
      statusCode: statusCode,
      code: 'http_$statusCode',
    );
  }
}
