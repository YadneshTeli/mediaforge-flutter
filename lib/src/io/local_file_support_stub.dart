import 'dart:async';

import '../models/exif_data.dart';

/// Stub implementation of [LocalFileSupport] for platforms without `dart:io` (e.g. Flutter Web).
class LocalFileSupport {
  /// Whether file operations are supported on this platform.
  static const bool isSupported = false;

  /// Maximum file size supported for on-device stripping operations (50 MB).
  static const int maxStripFileSizeBytes = 50 * 1024 * 1024;

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
}
