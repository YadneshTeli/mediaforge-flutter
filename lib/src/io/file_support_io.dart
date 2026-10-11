import 'dart:async';
import 'dart:io';

import '../client/mediaforge_client.dart';
import '../exceptions/processing_exception.dart';
import '../mediaforge.dart';
import '../models/exif_data.dart';
import '../models/upload_result.dart';
import '../upload/upload_phase.dart';
import 'local_file_support_io.dart';

/// Native file-based operations utilizing streaming I/O to avoid mobile OOM errors.
class FileSupport {
  /// Whether file operations are supported on this platform.
  static const bool isSupported = LocalFileSupport.isSupported;

  /// Maximum file size supported for on-device stripping operations (50 MB).
  static const int maxStripFileSizeBytes = LocalFileSupport.maxStripFileSizeBytes;

  /// Reads EXIF metadata directly from a [File] using streaming header access.
  ///
  /// Does not load the entire image into a memory buffer.
  static Future<ExifData> readMetadataFile(dynamic file) =>
      LocalFileSupport.readMetadataFile(file);

  /// Strips metadata from a [File] on-device with bounded memory and safe in-place replacement.
  ///
  /// Overwrites [file] if [destinationFile] is omitted, or writes to [destinationFile]
  /// if provided. Returns the resulting [File].
  ///
  /// Enforces [maxStripFileSizeBytes] (50 MB) to prevent Out-Of-Memory (OOM) errors.
  /// Writes and verifies a temporary file before replacing the target, ensuring
  /// the original source file is preserved intact if a write failure occurs.
  static Future<File> stripMetadataFile(
    dynamic file, {
    dynamic destinationFile,
    int? maxFileSizeBytes,
  }) =>
      LocalFileSupport.stripMetadataFile(
        file,
        destinationFile: destinationFile,
        maxFileSizeBytes: maxFileSizeBytes,
      );

  /// Streams a [File] directly from disk to the MediaForge edge CDN.
  ///
  /// By streaming chunk-by-chunk via [File.openRead], high-resolution camera
  /// images (20MB - 50MB) are uploaded without risk of Out-Of-Memory (OOM) crashes.
  static Future<UploadResult> uploadFile(
    dynamic file, {
    String? filename,
    String? folder,
    ProgressCallback? onProgress,
    UploadProgressCallback? onProgressEvent,
    Duration? timeout,
  }) async {
    if (file is! File) {
      throw ArgumentError.value(file, 'file', 'Expected a dart:io File instance');
    }
    if (!file.existsSync()) {
      throw ProcessingException(
        'File does not exist: ${file.path}',
        code: 'file_not_found',
      );
    }

    final length = await file.length();
    final name = filename ?? _filenameOf(file.path);

    return MediaForge.uploadStream(
      file.openRead(),
      length: length,
      filename: name,
      folder: folder,
      onProgress: onProgress,
      onProgressEvent: onProgressEvent,
      timeout: timeout,
    );
  }

  static String _filenameOf(String path) {
    final normalized = path.replaceAll(r'\', '/');
    final slash = normalized.lastIndexOf('/');
    return slash >= 0 ? normalized.substring(slash + 1) : normalized;
  }
}
