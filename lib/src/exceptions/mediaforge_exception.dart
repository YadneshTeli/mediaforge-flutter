/// Base exception for all MediaForge SDK errors.
///
/// All MediaForge exceptions extend this class, allowing you to
/// catch all SDK errors with a single `catch (MediaForgeException)`.
class MediaForgeException implements Exception {
  /// A human-readable error message.
  final String message;

  /// Optional error code from the API (e.g., "plan_limit_exceeded").
  final String? code;

  /// Creates a new [MediaForgeException].
  const MediaForgeException(this.message, {this.code});

  @override
  String toString() => '$runtimeType: $message'
      '${code != null ? ' (code: $code)' : ''}';
}
