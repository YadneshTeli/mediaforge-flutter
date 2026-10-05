import 'dart:typed_data';

import 'mime_type.dart';

/// Utility functions for working with media byte data.
class ByteUtils {
  ByteUtils._();

  /// Returns a human-readable file size string.
  ///
  /// Examples: "1.2 KB", "3.5 MB", "48 bytes"
  static String formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes bytes';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  /// Calculates the size savings between original and processed bytes.
  ///
  /// Returns a value between -1.0 and 1.0 where:
  /// - Positive = file got smaller (savings)
  /// - Negative = file got larger
  /// - 0 = no change
  static double calculateSavings(int originalBytes, int processedBytes) {
    if (originalBytes == 0) return 0;
    return 1 - (processedBytes / originalBytes);
  }

  /// Checks if the given bytes represent a valid image by checking magic bytes.
  ///
  /// Supports JPEG, PNG, and WebP detection.
  static bool isValidImage(Uint8List bytes) {
    return MimeType.isImageBytes(bytes);
  }

  /// Checks if the given bytes represent a supported video (MP4 or MOV).
  static bool isVideo(Uint8List bytes) {
    return MimeType.isVideoBytes(bytes);
  }

  /// Checks if the given bytes represent any supported media (image or video).
  static bool isValidMedia(Uint8List bytes) {
    return MimeType.fromBytes(bytes) != null;
  }

  /// Detects the MIME type of a media buffer from its magic bytes.
  ///
  /// Returns `null` if the format is not recognized.
  static String? detectMimeType(Uint8List bytes) {
    return MimeType.fromBytes(bytes);
  }
}
