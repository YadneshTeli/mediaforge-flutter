import 'dart:typed_data';

import '../client/mediaforge_client.dart';
import '../config.dart';
import '../exceptions/auth_exception.dart';
import '../mediaforge.dart';
import '../models/upload_result.dart';
import '../processing/processing_pipeline.dart';
import 'upload_phase.dart';

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
///   onProgressEvent: (e) => print('${e.phase.name} ${(e.progress * 100).round()}%'),
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
              uploadTimeout: _config.uploadTimeout,
              maxUploadBytes: _config.maxUploadBytes,
            );

  /// The underlying [MediaForgeClient] used for network communication.
  MediaForgeClient get client => _client;

  /// Uploads processed media [bytes] to the MediaForge CDN.
  ///
  /// Parameters:
  /// - [bytes]: The processed image or video bytes to upload
  /// - [filename]: Optional filename for the uploaded file
  /// - [folder]: Optional folder path on CDN
  /// - [onProgress]: Optional progress callback (0.0 to 1.0); reaches `1.0`
  ///   only after the server confirms the upload
  /// - [onProgressEvent]: Optional phase-aware progress callback
  /// - [timeout]: Optional per-call timeout overriding the configured upload timeout
  ///
  /// Returns an [UploadResult] with the CDN URL and file metadata.
  ///
  /// Throws [AuthException] if the API key is invalid or not initialized.
  /// Throws [PlanLimitException] if the account is on Spark, quotas are
  /// exceeded, or the payload exceeds the configured maximum upload size.
  Future<UploadResult> upload(
    Uint8List bytes, {
    String? filename,
    String? folder,
    ProgressCallback? onProgress,
    UploadProgressCallback? onProgressEvent,
    Duration? timeout,
  }) async {
    _ensureConfigured();

    final file = await _client.uploadToCdn(
      bytes,
      filename: filename,
      folder: folder,
      onProgress: onProgress,
      onProgressEvent: onProgressEvent,
      timeout: timeout,
    );

    return UploadResult.fromMediaForgeFile(file);
  }

  /// Uploads media from a byte [stream] without loading it fully into memory.
  ///
  /// See [MediaForgeClient.uploadStreamToCdn] for parameter details.
  Future<UploadResult> uploadStream(
    Stream<List<int>> stream, {
    required int length,
    required String filename,
    String? contentType,
    String? folder,
    ProgressCallback? onProgress,
    UploadProgressCallback? onProgressEvent,
    Duration? timeout,
  }) async {
    _ensureConfigured();

    final file = await _client.uploadStreamToCdn(
      stream,
      length: length,
      filename: filename,
      contentType: contentType,
      folder: folder,
      onProgress: onProgress,
      onProgressEvent: onProgressEvent,
      timeout: timeout,
    );

    return UploadResult.fromMediaForgeFile(file);
  }

  void _ensureConfigured() {
    if (_config.apiKey.isEmpty) {
      throw const AuthException.notInitialized();
    }
    if (!_config.isProduction && !_config.isSandbox) {
      throw AuthException.invalidApiKey(_config.apiKey);
    }
  }

  /// Validates that the uploader is properly configured with an API key.
  ///
  /// Returns `true` if the API key and base URL are valid.
  bool get isConfigured =>
      _config.apiKey.isNotEmpty && (_config.isProduction || _config.isSandbox);
}

/// Fluent chaining extension enabling [ProcessingPipeline] to upload directly.
extension ProcessingPipelineUploadExtension on ProcessingPipeline {
  /// Executes all pipeline steps and uploads the resulting bytes directly to
  /// the MediaForge CDN in a single fluent chain.
  ///
  /// ```dart
  /// final uploaded = await MediaForge.pipeline(rawBytes)
  ///   .stripMetadata()
  ///   .compress(quality: 80)
  ///   .upload(filename: 'clean.jpg');
  /// ```
  ///
  /// Requires the SDK to be initialized with [MediaForge.init].
  Future<UploadResult> upload({
    String? filename,
    String? folder,
    ProgressCallback? onProgress,
    UploadProgressCallback? onProgressEvent,
    Duration? timeout,
  }) async {
    final result = await execute();
    return MediaForge.upload(
      result.bytes,
      filename: filename,
      folder: folder,
      onProgress: onProgress,
      onProgressEvent: onProgressEvent,
      timeout: timeout,
    );
  }
}
