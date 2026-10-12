import 'dart:async';
import 'dart:typed_data';

import 'client/mediaforge_client.dart';
import 'config.dart';
import 'exceptions/auth_exception.dart';
import 'io/file_support.dart';
import 'mediaforge_local.dart';
import 'models/batch_delete_result.dart';
import 'models/exif_data.dart';
import 'models/file_list_result.dart';
import 'models/mediaforge_file.dart';
import 'models/mediaforge_health.dart';
import 'models/mediaforge_usage.dart';
import 'models/processing_options.dart';
import 'models/upload_result.dart';
import 'processing/exif_reader.dart';
import 'processing/exif_stripper.dart';
import 'processing/processing_pipeline.dart';
import 'upload/upload_phase.dart';
import 'upload/uploader.dart';

export 'mediaforge_local.dart' show MediaForgeLocal, MediaForgeLocalNamespace;

/// Main entry point for the MediaForge Flutter SDK.
///
/// Provides static methods and explicit namespaces ([local] and [cloud])
/// for both privacy-first on-device media processing and Developer API
/// cloud services (Cloudflare R2 CDN upload, streaming uploads, quota
/// telemetry, remote asset management).
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
/// final metadata = await MediaForge.local.readMetadata(imageBytes);
/// // Or directly:
/// final metadata = await MediaForge.readMetadata(imageBytes);
///
/// // Strip all metadata with verification
/// final clean = await MediaForge.local.stripMetadata(imageBytes);
/// final verified = await MediaForge.local.verifyClean(clean); // true
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
/// // 1. Fluent Pipeline -> Upload chain
/// final uploaded = await MediaForge.pipeline(rawBytes)
///   .stripMetadata()
///   .compress(quality: 80)
///   .upload(filename: 'clean.jpg');
///
/// // 2. Direct upload
/// final uploaded = await MediaForge.upload(cleanBytes, filename: 'hero.jpg');
/// print('CDN URL: ${uploaded.cdnUrl}');
///
/// // 3. Check remaining operations and storage
/// final usage = await MediaForge.getUsage();
/// print('Ops used: ${usage.operationsUsed} / ${usage.operationsLimit}');
/// ```
class MediaForge {
  static MediaForgeConfig? _config;
  static MediaForgeClient? _client;
  static const ExifReader _reader = ExifReader();
  static const ExifStripper _stripper = ExifStripper();

  /// Explicit namespace for offline-only, zero-network media operations.
  ///
  /// Guarantees 100% on-device execution with zero network communication.
  static const MediaForgeLocalNamespace local = MediaForgeLocalNamespace();

  /// Explicit namespace for remote MediaForge Developer Cloud services.
  ///
  /// Requires initialization with [MediaForge.init].
  static const MediaForgeCloud cloud = MediaForgeCloud();

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
  /// [timeout] defaults to 30 seconds for standard queries.
  /// [uploadTimeout] defaults to 120 seconds for heavy uploads.
  /// [maxUploadBytes] defaults to 10 MB client-side ceiling (`null` disables).
  static void init({
    required String apiKey,
    String? baseUrl,
    Duration? timeout,
    Duration? uploadTimeout,
    int? maxUploadBytes = MediaForgeClient.defaultMaxUploadBytes,
    MediaForgeClient? client,
  }) {
    _config = MediaForgeConfig(
      apiKey: apiKey,
      baseUrl: baseUrl ?? 'https://api.mediaforge.tech',
      timeout: timeout ?? const Duration(seconds: 30),
      uploadTimeout: uploadTimeout ?? MediaForgeClient.defaultUploadTimeout,
      maxUploadBytes: maxUploadBytes,
    );
    _client = client ??
        MediaForgeClient(
          apiKey: _config!.apiKey,
          baseUrl: _config!.baseUrl,
          timeout: _config!.timeout,
          uploadTimeout: _config!.uploadTimeout,
          maxUploadBytes: _config!.maxUploadBytes,
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
        uploadTimeout: _config!.uploadTimeout,
        maxUploadBytes: _config!.maxUploadBytes,
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

  /// Reads EXIF metadata directly from a `dart:io` `File` using streaming
  /// random-access reading without loading the entire image into memory.
  ///
  /// Prevents Out-Of-Memory (OOM) crashes on high-resolution camera photos.
  ///
  /// Throws [UnsupportedError] if called on web platforms.
  static Future<ExifData> readMetadataFile(dynamic file) {
    return FileSupport.readMetadataFile(file);
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

  /// Strips metadata from a `dart:io` `File` on disk.
  ///
  /// Writes clean bytes to [destinationFile], or overwrites [file] if omitted.
  /// Enforces a maximum file size limit (50 MB) and uses safe temp-file writing
  /// to ensure the original source file is preserved intact on write failures.
  ///
  /// Emits [UnsupportedError] through the returned Future on web platforms.
  static Future<dynamic> stripMetadataFile(
    dynamic file, {
    dynamic destinationFile,
    int? maxFileSizeBytes,
  }) {
    return FileSupport.stripMetadataFile(
      file,
      destinationFile: destinationFile,
      maxFileSizeBytes: maxFileSizeBytes,
    );
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
  ) {
    return MediaForgeLocal.process(bytes, options);
  }

  /// Creates a chainable processing pipeline.
  ///
  /// [runInIsolate]: `true` forces background isolate execution, `false`
  /// forces inline execution, `null` (default) decides automatically based on
  /// input size (>500KB offloads to isolate on native platforms).
  ///
  /// Does NOT require [init] — this is a local-only operation.
  static ProcessingPipeline pipeline(
    Uint8List bytes, {
    bool? runInIsolate,
  }) {
    return ProcessingPipeline(bytes, runInIsolate: runInIsolate);
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
    Duration? timeout,
  }) {
    return client.stripCloud(bytes, filename: filename, timeout: timeout);
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
  /// - [onProgressEvent]: Structured phase-aware progress callback
  /// - [timeout]: Custom upload timeout overriding the default (120s)
  ///
  /// Returns an [UploadResult] containing the public CDN URL and file metadata.
  static Future<UploadResult> upload(
    Uint8List bytes, {
    String? filename,
    String? folder,
    ProgressCallback? onProgress,
    UploadProgressCallback? onProgressEvent,
    Duration? timeout,
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
      onProgressEvent: onProgressEvent,
      timeout: timeout,
    );
  }

  /// Uploads media from a byte [stream] directly to the CDN without loading
  /// the full file into memory at once.
  ///
  /// Highly recommended for camera photos and videos to avoid mobile OOM crashes.
  static Future<UploadResult> uploadStream(
    Stream<List<int>> stream, {
    required int length,
    required String filename,
    String? contentType,
    String? folder,
    ProgressCallback? onProgress,
    UploadProgressCallback? onProgressEvent,
    Duration? timeout,
  }) async {
    if (_config == null) {
      throw const AuthException.notInitialized();
    }

    final uploader = MediaForgeUploader(_config!, client: _client);
    return uploader.uploadStream(
      stream,
      length: length,
      filename: filename,
      contentType: contentType,
      folder: folder,
      onProgress: onProgress,
      onProgressEvent: onProgressEvent,
      timeout: timeout,
    );
  }

  /// Streams a `dart:io` `File` directly from disk to the CDN.
  ///
  /// Avoids loading large files into memory buffers.
  /// Throws [UnsupportedError] on web platforms.
  static Future<UploadResult> uploadFile(
    dynamic file, {
    String? filename,
    String? folder,
    ProgressCallback? onProgress,
    UploadProgressCallback? onProgressEvent,
    Duration? timeout,
  }) {
    return FileSupport.uploadFile(
      file,
      filename: filename,
      folder: folder,
      onProgress: onProgress,
      onProgressEvent: onProgressEvent,
      timeout: timeout,
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
    ProgressCallback? onProgress,
    UploadProgressCallback? onProgressEvent,
    Duration? timeout,
  }) async {
    final processed = options != null ? await process(bytes, options) : bytes;

    return upload(
      processed,
      filename: filename,
      folder: folder,
      onProgress: onProgress,
      onProgressEvent: onProgressEvent,
      timeout: timeout,
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

  /// Deletes multiple files in parallel with controlled concurrency.
  ///
  /// Returns a [BatchDeleteResult] reporting both succeeded and failed deletions.
  /// **Requires [init] with a valid API key.**
  static Future<BatchDeleteResult> deleteFiles(
    Iterable<String> fileIds, {
    int concurrency = 4,
  }) {
    return client.deleteFiles(fileIds, concurrency: concurrency);
  }
}

/// Remote cloud services namespace for MediaForge.
///
/// Requires [MediaForge.init] with a Developer API key.
class MediaForgeCloud {
  /// Creates a [MediaForgeCloud] instance.
  const MediaForgeCloud();

  /// Verifies API connectivity and key validity.
  Future<MediaForgeHealth> checkHealth({String? apiKey, String? baseUrl}) =>
      MediaForge.checkHealth(apiKey: apiKey, baseUrl: baseUrl);

  /// Offloads metadata stripping to MediaForge cloud without CDN storage.
  Future<Uint8List> strip(
    Uint8List bytes, {
    String? filename,
    Duration? timeout,
  }) =>
      MediaForge.stripCloud(bytes, filename: filename, timeout: timeout);

  /// Uploads media [bytes] to Cloudflare R2 CDN.
  Future<UploadResult> upload(
    Uint8List bytes, {
    String? filename,
    String? folder,
    ProgressCallback? onProgress,
    UploadProgressCallback? onProgressEvent,
    Duration? timeout,
  }) =>
      MediaForge.upload(
        bytes,
        filename: filename,
        folder: folder,
        onProgress: onProgress,
        onProgressEvent: onProgressEvent,
        timeout: timeout,
      );

  /// Streams a byte [stream] directly to the CDN.
  Future<UploadResult> uploadStream(
    Stream<List<int>> stream, {
    required int length,
    required String filename,
    String? contentType,
    String? folder,
    ProgressCallback? onProgress,
    UploadProgressCallback? onProgressEvent,
    Duration? timeout,
  }) =>
      MediaForge.uploadStream(
        stream,
        length: length,
        filename: filename,
        contentType: contentType,
        folder: folder,
        onProgress: onProgress,
        onProgressEvent: onProgressEvent,
        timeout: timeout,
      );

  /// Streams a `dart:io` `File` directly from disk to the CDN.
  Future<UploadResult> uploadFile(
    dynamic file, {
    String? filename,
    String? folder,
    ProgressCallback? onProgress,
    UploadProgressCallback? onProgressEvent,
    Duration? timeout,
  }) =>
      MediaForge.uploadFile(
        file,
        filename: filename,
        folder: folder,
        onProgress: onProgress,
        onProgressEvent: onProgressEvent,
        timeout: timeout,
      );

  /// Processes media on-device and uploads the result in one step.
  Future<UploadResult> processAndUpload(
    Uint8List bytes, {
    ProcessingOptions? options,
    String? filename,
    String? folder,
    ProgressCallback? onProgress,
    UploadProgressCallback? onProgressEvent,
    Duration? timeout,
  }) =>
      MediaForge.processAndUpload(
        bytes,
        options: options,
        filename: filename,
        folder: folder,
        onProgress: onProgress,
        onProgressEvent: onProgressEvent,
        timeout: timeout,
      );

  /// Retrieves account usage and remaining quota.
  Future<MediaForgeUsage> getUsage() => MediaForge.getUsage();

  /// Lists assets stored in Cloudflare R2 CDN.
  Future<FileListResult> listFiles({
    int page = 1,
    int limit = 20,
    String? cursor,
  }) =>
      MediaForge.listFiles(page: page, limit: limit, cursor: cursor);

  /// Retrieves details for a specific uploaded asset.
  Future<MediaForgeFile> getFile(String fileId) => MediaForge.getFile(fileId);

  /// Deletes a file from Cloudflare R2 CDN.
  Future<void> deleteFile(String fileId) => MediaForge.deleteFile(fileId);

  /// Deletes multiple files in parallel with controlled concurrency.
  Future<BatchDeleteResult> deleteFiles(
    Iterable<String> fileIds, {
    int concurrency = 4,
  }) =>
      MediaForge.deleteFiles(fileIds, concurrency: concurrency);
}
