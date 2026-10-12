import 'dart:async';
import 'dart:io';

import 'package:exif/exif.dart' hide ExifData;

import '../exceptions/processing_exception.dart';
import '../models/exif_data.dart';
import '../processing/exif_reader.dart';
import '../processing/exif_stripper.dart';

/// Native local file-based operations utilizing streaming and bounded-memory I/O.
///
/// Contains zero networking code or HTTP dependencies.
class LocalFileSupport {
  /// Whether file operations are supported on this platform.
  static const bool isSupported = true;

  /// Maximum file size supported for on-device stripping operations (50 MB).
  ///
  /// Enforced to maintain bounded memory behavior and prevent Out-Of-Memory (OOM)
  /// crashes on constrained devices.
  static const int maxStripFileSizeBytes = 50 * 1024 * 1024;

  /// Resolves a [File] instance from a [File] or any object with a valid `.path`
  /// property (such as Flutter's `XFile`), preventing runtime type crashes.
  static File resolveFile(dynamic file, [String paramName = 'file']) {
    if (file is File) return file;
    if (file != null) {
      try {
        final dynamic path = (file as dynamic).path;
        if (path is String && path.isNotEmpty) {
          return File(path);
        }
      } catch (_) {}
    }
    throw ArgumentError.value(
      file,
      paramName,
      'Expected a dart:io File instance or an object with a file path (e.g. XFile)',
    );
  }

  /// Reads EXIF metadata directly from a [File] using streaming header access.
  ///
  /// Accepts a `dart:io` [File] or any object exposing a `.path` (such as `XFile`).
  /// Does not load the entire image into a memory buffer.
  static Future<ExifData> readMetadataFile(dynamic file) async {
    final sourceFile = resolveFile(file, 'file');
    if (!sourceFile.existsSync()) {
      throw ProcessingException(
        'File does not exist: ${sourceFile.path}',
        code: 'file_not_found',
      );
    }

    try {
      final tags = await readExifFromFile(sourceFile);
      return const ExifReader().parseTags(tags);
    } on ProcessingException {
      rethrow;
    } catch (e) {
      throw ProcessingException(
        'Failed to read metadata from file: $e',
        code: 'metadata_read_error',
      );
    }
  }

  /// Strips metadata from a [File] on-device with bounded memory and safe in-place replacement.
  ///
  /// Overwrites [file] if [destinationFile] is omitted, or writes to [destinationFile]
  /// if provided. Returns the resulting [File]. Accepts [File] or `XFile`.
  ///
  /// Enforces a file size limit of [maxFileSizeBytes] (defaults to
  /// [maxStripFileSizeBytes], 50 MB) to guarantee bounded memory usage and prevent
  /// memory exhaustion on constrained devices. Throws [ProcessingException] with code
  /// `file_too_large` if the file exceeds the limit.
  ///
  /// Writes and verifies a temporary file before replacing the target, ensuring
  /// the original source file is preserved intact if a write failure occurs.
  static Future<File> stripMetadataFile(
    dynamic file, {
    dynamic destinationFile,
    int? maxFileSizeBytes,
  }) async {
    final sourceFile = resolveFile(file, 'file');
    final targetFile = destinationFile != null
        ? resolveFile(destinationFile, 'destinationFile')
        : sourceFile;

    if (!sourceFile.existsSync()) {
      throw ProcessingException(
        'File does not exist: ${sourceFile.path}',
        code: 'file_not_found',
      );
    }

    final limit = maxFileSizeBytes ?? maxStripFileSizeBytes;
    final fileSize = await sourceFile.length();
    if (fileSize > limit) {
      throw ProcessingException(
        'File size ($fileSize bytes) exceeds maximum limit of '
        '$limit bytes (${(limit / (1024 * 1024)).round()} MB) for on-device stripping.',
        code: 'file_too_large',
      );
    }

    final bytes = await sourceFile.readAsBytes();
    final cleanBytes = await const ExifStripper().stripAll(bytes);

    await _safeWriteFile(targetFile, cleanBytes);
    return targetFile;
  }

  /// Writes [data] to a temporary sibling file, verifies its integrity, and
  /// atomically replaces [target]. If anything fails, the original [target]
  /// is preserved intact.
  static Future<void> _safeWriteFile(File target, List<int> data) async {
    final parent = target.parent;
    if (!parent.existsSync()) {
      await parent.create(recursive: true);
    }

    final rawName = target.path.split(RegExp(r'[/\\]')).last;
    final targetName = rawName.isNotEmpty ? rawName : 'output';
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    final tempPath =
        '${parent.path}${Platform.pathSeparator}.mf_tmp_${timestamp}_$targetName';
    final tempFile = File(tempPath);

    try {
      // 1. Write replacement data to temporary file
      await tempFile.writeAsBytes(data, flush: true);

      // 2. Verify temporary file exists and matches expected data length
      final tempLength = await tempFile.length();
      if (tempLength != data.length) {
        throw ProcessingException(
          'Verification failed: temporary file length ($tempLength) does not match expected length (${data.length})',
          code: 'file_verification_failed',
        );
      }

      // 3. Atomically replace target file
      await tempFile.rename(target.path);
    } finally {
      if (tempFile.existsSync()) {
        try {
          await tempFile.delete();
        } catch (_) {}
      }
    }
  }
}
