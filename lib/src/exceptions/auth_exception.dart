import 'mediaforge_exception.dart';

/// Thrown when authentication fails — invalid or missing API key.
///
/// Common causes:
/// - [MediaForge.init] was not called before attempting upload
/// - API key is invalid, revoked, or expired
/// - API key does not have the required permissions
class AuthException extends MediaForgeException {
  /// Creates a new [AuthException].
  const AuthException(super.message, {super.code});

  /// Creates an [AuthException] for a missing API key.
  const AuthException.notInitialized()
      : super(
          'MediaForge SDK not initialized. '
          'Call MediaForge.init(apiKey: "mf_live_xxxx") before uploading. '
          'Local processing does not require initialization.',
          code: 'not_initialized',
        );

  /// Creates an [AuthException] for an invalid API key.
  const AuthException.invalidKey()
      : super(
          'Invalid API key. Check your key at '
          'https://mediaforge.tech/dashboard/developer',
          code: 'invalid_api_key',
        );

  /// Creates an [AuthException] for an invalid API key format or value.
  const AuthException.invalidApiKey([String? key])
      : super(
          'Invalid API key format. API key must start with "mf_live_" or "mf_test_". '
          'Check your key at https://mediaforge.tech/dashboard/developer',
          code: 'invalid_api_key',
        );
}
