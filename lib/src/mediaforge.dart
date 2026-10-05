import 'dart:typed_data';

import 'client/mediaforge_client.dart';
import 'config.dart';
import 'exceptions/auth_exception.dart';
import 'models/exif_data.dart';
import 'models/file_list_result.dart';
import 'models/mediaforge_file.dart';
import 'models/mediaforge_health.dart';
import 'models/mediaforge_usage.dart';
import 'models/processing_options.dart';
import 'models/upload_result.dart';
import 'processing/exif_reader.dart';
import 'processing/exif_stripper.dart';
import 'processing/image_processor.dart';
import 'processing/processing_pipeline.dart';
import 'upload/uploader.dart';

/// Main entry point for the MediaForge Flutter SDK.
///
/// Provides static methods for both privacy-first on-device media processing
/// and Developer API cloud services (stripping stream, Cloudflare R2 CDN upload,
/// quota telemetry, remote asset management).
///
/// **Local processing works without initialization.**
/// Call [init] only when you need CDN upload or cloud Developer API functionality.
///
/// ## Quick Start — Local Processing (no API key needed)
///
/// ```dart
/// import 'package:mediaforge_flutter/mediaforge_flutter.dart';
///
/// // Read metadata
/// final metadata = await MediaForge.readMetadata(imageBytes);
///
/// // Strip all metadata with verification
/// final clean = await MediaForge.stripMetadata(imageBytes);
/// final verified = await MediaForge.verifyClean(clean); // true
///
/// // Pipeline: strip -> resize -> compress -> convert
/// final result = await MediaForge.pipeline(imageBytes)
///   .stripMetadata()
///   .resize(width: 800, height: 600)
///   .compress(quality: 85)
///   .convert(format: ImageFormat.jpeg)
///   .execute();
/// ```
///
/// ## Cloud & CDN Upload (requires account + API key)
///
/// ```dart
/// MediaForge.init(apiKey: 'mf_live_xxxx');
///
/// // 1. Upload clean bytes to global CDN
/// final uploaded = await MediaForge.upload(cleanBytes, filename: 'hero.jpg');
/// print('CDN URL: ${uploaded.cdnUrl}');
///
/// // 2. Check remaining operations and storage
/// final usage = await MediaForge.getUsage();
/// print('Ops used: ${usage.operationsUsed} / ${usage.operationsLimit}');
/// ```
class MediaForge {
  static MediaForgeConfig? _config;
  static MediaForgeClient? _client;
  static const ExifReader _reader = ExifReader();
  static const ExifStripper _stripper = ExifStripper();
  static const ImageProcessor _processor = ImageProcessor();

  // Prevent instantiation
  MediaForge._();

  // =====================================================
  // INITIALIZATION (optional — only needed for cloud features)
  // =====================================================

  /// Initializes the SDK with an API key for CDN upload and Developer APIs.
  ///
  /// **This is optional.** Local processing (read, strip, resize,
  /// compress, convert) works without calling [init].
  ///
  /// The [apiKey] must start with `mf_live_` (production) or
  /// `mf_test_` (sandbox). Get your key at
  /// https://mediaforge.tech/dashboard/keys
  ///
  /// [baseUrl] defaults to `https://api.mediaforge.tech`.
  static void init({
    required String apiKey,
    String? baseUrl,
    Duration? timeout,
    MediaForgeClient? client,
  }) {
    _config = MediaForgeConfig(
      apiKey: apiKey,
      baseUrl: baseUrl ?? 'https://api.mediaforge.tech',
      timeout: timeout ?? const Duration(seconds: 30),
    );
    _client = client ??
        MediaForgeClient(
          apiKey: _config!.apiKey,
          baseUrl: _config!.baseUrl,
          timeout: _config!.timeout,
        );
  }

  /// Whether the SDK has been initialized with an API key.
  static bool get isInitialized => _config != null;

  /// The active [MediaForgeClient] instance.
  ///
  /// Throws [AuthException.notInitialized] if [init] has not been called.
  static MediaForgeClient get client {
    if (_client != null) return _client!;
    if (_config != null) {
      _client = MediaForgeClient(
        apiKey: _config!.apiKey,
        baseUrl: _config!.baseUrl,
        timeout: _config!.timeout,
      );
      return _client!;
    }
    throw const AuthException.notInitialized();
  }

  /// Resets the SDK state. Primarily for testing.
  static void reset() {
    _client?.close();
    _client = null;
    _config = null;
  }

  // =====================================================
  // LOCAL PROCESSING (no API key required)
  // =====================================================

  /// Reads all EXIF/XMP/IPTC metadata from the image [bytes].
  ///
  /// Returns an [ExifData] object with all found fields.
  /// Fields not present in the image will be `null`.
  ///
  /// Does NOT require [init] — this is a local-only operation.
  static Future<ExifData> readMetadata(Uint8List bytes) {
    return _reader.read(bytes);
  }

  /// Strips ALL metadata from the image [bytes].
  ///
  /// Returns clean image bytes with all EXIF/XMP/IPTC data removed.
  /// The output format matches the input format.
  ///
  /// Does NOT require [init] — this is a local-only operation.
  static Future<Uint8List> stripMetadata(Uint8List bytes) {
    return _stripper.stripAll(bytes);
  }

  /// Strips only GPS location data from the image [bytes].
  ///
  /// Camera info, timestamps, and other metadata are preserved.
  ///
  /// Does NOT require [init] — this is a local-only operation.
  static Future<Uint8List> stripGps(Uint8List bytes) {
    return _stripper.stripSelective(bytes, stripGps: true);
  }

  /// Verifies that the image [bytes] contain NO metadata.
  ///
  /// Returns `true` if the image is clean (0 metadata fields remaining).
  /// This post-strip verification is a unique MediaForge feature.
  ///
  /// Does NOT require [init] — this is a local-only operation.
  static Future<bool> verifyClean(Uint8List bytes) {
    return _stripper.verify(bytes);
  }

  /// Strips metadata and verifies in one call.
  ///
  /// Returns a [StrippingResult] with clean bytes, verification status,
  /// and the number of fields removed.
  ///
  /// Does NOT require [init] — this is a local-only operation.
  static Future<StrippingResult> stripAndVerify(Uint8List bytes) {
    return _stripper.stripAndVerify(bytes);
  }

  /// Processes an image with the given [options].
  ///
  /// Applies all configured operations: strip, resize, compress, convert.
  ///
  /// Does NOT require [init] — this is a local-only operation.
  static Future<Uint8List> process(
    Uint8List bytes,
    ProcessingOptions options,
  ) async {
    var current = bytes;

    // Strip metadata first (if enabled)
    if (options.stripMetadata) {
      current = await _stripper.stripAll(current);
    } else if (options.stripGpsOnly) {
      current = await _stripper.stripSelective(current, stripGps: true);
    }

    // Resize (if configured)
    if (options.hasResize) {
      current = await _processor.resize(
        current,
        width: options.resizeWidth,
        height: options.resizeHeight,
        mode: options.resizeMode,
        maintainAspectRatio: options.maintainAspectRatio,
      );
    }

    // Convert format and/or compress
    if (options.hasFormatConversion) {
      current = await _processor.convert(
        current,
        format: options.outputFormat!,
        quality: options.quality,
        lossless: options.lossless,
      );
    } else if (!options.lossless) {
      current = await _processor.compress(
        current,
        quality: options.quality,
      );
    }

    return current;
  }

  /// Creates a chainable processing pipeline.
  ///
  /// Does NOT require [init] — this is a local-only operation.
  static ProcessingPipeline pipeline(Uint8List bytes) {
    return ProcessingPipeline(bytes);
  }

  // =====================================================
  // DEVELOPER CLOUD APIS (requires account + API key)
  // =====================================================

  /// Checks connectivity to the Developer API and verifies the active API key.
  ///
  /// If the SDK is initialized, verifies the configured key and plan.
  /// If not initialized, performs an unauthenticated ping.
  static Future<MediaForgeHealth> checkHealth({
    String? apiKey,
    String? baseUrl,
  }) async {
    if (apiKey != null) {
      final tempClient = MediaForgeClient(
        apiKey: apiKey,
        baseUrl: baseUrl ?? 'https://api.mediaforge.tech',
      );
      try {
        return await tempClient.checkHealth();
      } finally {
        tempClient.close();
      }
    }

    if (isInitialized) {
      return client.checkHealth();
    }

    // Unauthenticated connectivity ping
    final pingClient = MediaForgeClient(
      apiKey: '',
      baseUrl: baseUrl ?? 'https://api.mediaforge.tech',
    );
    try {
      return await pingClient.checkHealth();
    } finally {
      pingClient.close();
    }
  }

  /// Strips metadata via the MediaForge cloud service and streams back clean bytes.
  ///
  /// Offloads stripping to the server without storing the file on the CDN.
  /// Available across all plans (Spark, Forge, Forge+).
  static Future<Uint8List> stripCloud(
    Uint8List bytes, {
    String? filename,
  }) {
    return client.stripCloud(bytes, filename: filename);
  }

  /// Uploads media [bytes] to the Cloudflare R2 edge CDN with metadata stripping.
  ///
  /// Requires a paid plan (Forge or Forge+).
  ///
  /// Parameters:
  /// - [bytes]: Processed image or video bytes to upload
  /// - [filename]: Optional filename for storage (e.g. 'hero.jpg')
  /// - [folder]: Optional folder path on CDN
  /// - [onProgress]: Progress callback receiving ratio (0.0 to 1.0)
  ///
  /// Returns an [UploadResult] containing the public CDN URL and file metadata.
  static Future<UploadResult> upload(
    Uint8List bytes, {
    String? filename,
    String? folder,
    void Function(double progress)? onProgress,
  }) async {
    if (_config == null) {
      throw const AuthException.notInitialized();
    }

    final uploader = MediaForgeUploader(_config!, client: _client);
    return uploader.upload(
      bytes,
      filename: filename,
      folder: folder,
      onProgress: onProgress,
    );
  }

  /// Processes media and uploads the sanitized result to CDN in one call.
  ///
  /// Convenience method that combines [process] and [upload].
  ///
  /// **Requires [init] to be called first with a valid API key.**
  static Future<UploadResult> processAndUpload(
    Uint8List bytes, {
    ProcessingOptions? options,
    String? filename,
    String? folder,
    void Function(double progress)? onProgress,
  }) async {
    final processed = options != null
        ? await process(bytes, options)
        : bytes;

    return upload(
      processed,
      filename: filename,
      folder: folder,
      onProgress: onProgress,
    );
  }

  /// Retrieves real-time operations, storage, and bandwidth quota usage.
  ///
  /// **Requires [init] with a valid API key.**
  static Future<MediaForgeUsage> getUsage() {
    return client.getUsage();
  }

  /// Retrieves a paginated list of files uploaded to the user's account.
  ///
  /// **Requires [init] with a valid API key.**
  static Future<FileListResult> listFiles({
    int page = 1,
    int limit = 20,
    String? cursor,
  }) {
    return client.listFiles(page: page, limit: limit, cursor: cursor);
  }

  /// Retrieves details and CDN URL for a specific file by its [fileId].
  ///
  /// **Requires [init] with a valid API key.**
  static Future<MediaForgeFile> getFile(String fileId) {
    return client.getFile(fileId);
  }

  /// Deletes a file from Cloudflare R2 CDN and releases storage quota.
  ///
  /// **Requires [init] with a valid API key.**
  static Future<void> deleteFile(String fileId) {
    return client.deleteFile(fileId);
  }
}
