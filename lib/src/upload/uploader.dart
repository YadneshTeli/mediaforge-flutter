import 'dart:typed_data';

import '../client/mediaforge_client.dart';
import '../config.dart';
import '../exceptions/auth_exception.dart';
import '../models/upload_result.dart';

/// Uploads sanitized media to the MediaForge edge CDN.
///
/// Requires a valid API key from an account on a paid plan (Forge or Forge+).
/// Only processed output is uploaded; your server never sees the raw file.
///
/// ## Usage
/// ```dart
/// final config = MediaForgeConfig(apiKey: 'mf_live_xxxx');
/// final uploader = MediaForgeUploader(config);
/// final result = await uploader.upload(
///   cleanBytes,
///   filename: 'hero.webp',
///   onProgress: (p) => print('${(p * 100).round()}%'),
/// );
/// print('CDN URL: ${result.cdnUrl}');
/// ```
class MediaForgeUploader {
  final MediaForgeConfig _config;
  final MediaForgeClient _client;

  /// Creates a new [MediaForgeUploader] with the given [config] and optional [client].
  MediaForgeUploader(this._config, {MediaForgeClient? client})
      : _client = client ??
            MediaForgeClient(
              apiKey: _config.apiKey,
              baseUrl: _config.baseUrl,
              timeout: _config.timeout,
            );

  /// The underlying [MediaForgeClient] used for network communication.
  MediaForgeClient get client => _client;

  /// Uploads processed media [bytes] to the MediaForge CDN.
  ///
  /// Parameters:
  /// - [bytes]: The processed image or video bytes to upload
  /// - [filename]: Optional filename for the uploaded file
  /// - [folder]: Optional folder path on CDN
  /// - [onProgress]: Optional callback for upload progress updates (0.0 to 1.0)
  ///
  /// Returns an [UploadResult] with the CDN URL and file metadata.
  ///
  /// Throws [AuthException] if the API key is invalid or not initialized.
  /// Throws [PlanLimitException] if the account is on Spark or quotas are exceeded.
  Future<UploadResult> upload(
    Uint8List bytes, {
    String? filename,
    String? folder,
    void Function(double progress)? onProgress,
  }) async {
    if (!isConfigured || _config.apiKey.isEmpty) {
      throw const AuthException.notInitialized();
    }

    final file = await _client.uploadToCdn(
      bytes,
      filename: filename,
      folder: folder,
      onProgress: onProgress,
    );

    return UploadResult.fromMediaForgeFile(file);
  }

  /// Validates that the uploader is properly configured with an API key.
  ///
  /// Returns `true` if the API key and base URL are valid.
  bool get isConfigured =>
      _config.apiKey.isNotEmpty && (_config.isProduction || _config.isSandbox);
}
