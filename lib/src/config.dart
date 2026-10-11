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

  /// Request timeout for lightweight API calls (health, usage, file management).
  ///
  /// Defaults to 30 seconds.
  final Duration timeout;

  /// Timeout for heavy multipart requests (CDN upload, cloud strip).
  ///
  /// Defaults to 120 seconds to accommodate slow mobile networks plus edge
  /// sanitization and storage commit.
  final Duration uploadTimeout;

  /// Client-side maximum upload size in bytes, validated before any data is
  /// sent. Set this to your plan or reverse-proxy limit to fail fast instead
  /// of wasting data and battery on a doomed request.
  ///
  /// Defaults to 100 MB. `null` disables the pre-flight check.
  final int? maxUploadBytes;

  /// Creates a new [MediaForgeConfig].
  ///
  /// Throws [AuthException] if [apiKey] does not start with a valid prefix.
  MediaForgeConfig({
    required this.apiKey,
    this.baseUrl = 'https://api.mediaforge.tech',
    this.timeout = const Duration(seconds: 30),
    this.uploadTimeout = const Duration(seconds: 120),
    this.maxUploadBytes = 100 * 1024 * 1024,
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
