import 'dart:async';

import '../client/mediaforge_client.dart';
import '../models/exif_data.dart';
import '../models/upload_result.dart';
import '../upload/upload_phase.dart';
import 'local_file_support_stub.dart';

/// Stub implementation of [FileSupport] for platforms without `dart:io` (e.g. Flutter Web).
class FileSupport {
  /// Whether file operations are supported on this platform.
  static const bool isSupported = LocalFileSupport.isSupported;

  /// Maximum file size supported for on-device stripping operations (50 MB).
  static const int maxStripFileSizeBytes = LocalFileSupport.maxStripFileSizeBytes;

  /// Emits [UnsupportedError] asynchronously through the returned Future on web platforms.
  static Future<ExifData> readMetadataFile(dynamic file) async {
    throw UnsupportedError(
      'File operations are not supported on web platforms. '
      'Use Uint8List or Streams instead.',
    );
  }

  /// Emits [UnsupportedError] asynchronously through the returned Future on web platforms.
  static Future<dynamic> stripMetadataFile(
    dynamic file, {
    dynamic destinationFile,
    int? maxFileSizeBytes,
  }) async {
    throw UnsupportedError(
      'File operations are not supported on web platforms. '
      'Use Uint8List or Streams instead.',
    );
  }

  /// Emits [UnsupportedError] asynchronously through the returned Future on web platforms.
  static Future<UploadResult> uploadFile(
    dynamic file, {
    String? filename,
    String? folder,
    ProgressCallback? onProgress,
    UploadProgressCallback? onProgressEvent,
    Duration? timeout,
  }) async {
    throw UnsupportedError(
      'File operations are not supported on web platforms. '
      'Use Uint8List or Streams instead.',
    );
  }
}
