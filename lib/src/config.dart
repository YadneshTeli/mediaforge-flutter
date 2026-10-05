import 'exceptions/auth_exception.dart';

/// SDK configuration for MediaForge.
///
/// Holds API key, base URL, and timeout settings.
/// Only required for CDN upload — local processing works without configuration.
class MediaForgeConfig {
  /// The API key for authenticating CDN upload requests.
  ///
  /// Must start with `mf_live_` (production) or `mf_test_` (sandbox).
  final String apiKey;

  /// The base URL for the MediaForge API.
  ///
  /// Defaults to `https://api.mediaforge.tech`.
  final String baseUrl;

  /// Request timeout duration.
  ///
  /// Defaults to 30 seconds.
  final Duration timeout;

  /// Creates a new [MediaForgeConfig].
  ///
  /// Throws [AuthException] if [apiKey] does not start with a valid prefix.
  MediaForgeConfig({
    required this.apiKey,
    this.baseUrl = 'https://api.mediaforge.tech',
    this.timeout = const Duration(seconds: 30),
  }) {
    if (!apiKey.startsWith('mf_live_') && !apiKey.startsWith('mf_test_')) {
      throw AuthException.invalidApiKey(apiKey);
    }
  }

  /// Whether this config uses a sandbox/test API key.
  bool get isSandbox => apiKey.startsWith('mf_test_');

  /// Alias for [isSandbox].
  bool get isTest => isSandbox;

  /// Whether this config uses a production API key.
  bool get isProduction => apiKey.startsWith('mf_live_');

  /// Alias for [isProduction].
  bool get isLive => isProduction;
}
