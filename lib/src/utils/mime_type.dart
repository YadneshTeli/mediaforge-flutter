import 'dart:typed_data';

import '../models/image_format.dart';

/// MIME type detection and validation utilities for image and video media.
class MimeType {
  MimeType._();

  /// Supported image MIME types.
  static const supportedImageTypes = {
    'image/jpeg',
    'image/png',
    'image/webp',
  };

  /// Supported video MIME types (supported on Forge and Forge+ tiers).
  static const supportedVideoTypes = {
    'video/mp4',
    'video/quicktime',
  };

  /// All supported media MIME types.
  static const supportedTypes = {
    ...supportedImageTypes,
    ...supportedVideoTypes,
  };

  /// Detects the MIME type from magic bytes.
  ///
  /// Returns `null` if the format is not recognized.
  static String? fromBytes(Uint8List bytes) {
    if (bytes.length < 4) return null;

    // JPEG: FF D8 FF
    if (bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) {
      return 'image/jpeg';
    }

    // PNG: 89 50 4E 47
    if (bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return 'image/png';
    }

    // WebP: RIFF....WEBP
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return 'image/webp';
    }

    // MP4 / MOV (ISO Base Media File Format)
    // Box structure: 4 bytes length, 4 bytes box type ('ftyp' = 0x66 0x74 0x79 0x70)
    if (bytes.length >= 12 &&
        bytes[4] == 0x66 &&
        bytes[5] == 0x74 &&
        bytes[6] == 0x79 &&
        bytes[7] == 0x70) {
      // Major brand check at bytes 8-11
      // QuickTime MOV: 'qt  ' (0x71 0x74 0x20 0x20)
      if (bytes[8] == 0x71 &&
          bytes[9] == 0x74 &&
          bytes[10] == 0x20 &&
          bytes[11] == 0x20) {
        return 'video/quicktime';
      }
      // MP4 brands (isom, iso2, mp41, mp42, avc1, etc.) or generic MP4
      return 'video/mp4';
    }

    // QuickTime MOV atom headers: moov, wide, mdat, free
    if (bytes.length >= 8 &&
        bytes[4] == 0x6D &&
        bytes[5] == 0x6F &&
        bytes[6] == 0x6F &&
        bytes[7] == 0x76) {
      return 'video/quicktime';
    }

    return null;
  }

  /// Returns the [ImageFormat] matching the given bytes, or `null` if not an image.
  static ImageFormat? formatFromBytes(Uint8List bytes) {
    final mime = fromBytes(bytes);
    if (mime == null || !supportedImageTypes.contains(mime)) return null;
    return ImageFormat.fromMimeType(mime);
  }

  /// Whether the given MIME type is supported by MediaForge (image or video).
  static bool isSupported(String mimeType) {
    return supportedTypes.contains(mimeType.toLowerCase().trim());
  }

  /// Whether the given MIME type is an image.
  static bool isImage(String mimeType) {
    return supportedImageTypes.contains(mimeType.toLowerCase().trim());
  }

  /// Whether the given MIME type is a video.
  static bool isVideo(String mimeType) {
    return supportedVideoTypes.contains(mimeType.toLowerCase().trim());
  }

  /// Detects whether the given bytes represent a supported video.
  static bool isVideoBytes(Uint8List bytes) {
    final mime = fromBytes(bytes);
    return mime != null && isVideo(mime);
  }

  /// Detects whether the given bytes represent a supported image.
  static bool isImageBytes(Uint8List bytes) {
    final mime = fromBytes(bytes);
    return mime != null && isImage(mime);
  }

  /// Detects the MIME type from a file extension.
  static String? fromExtension(String extension) {
    final normalized = extension.toLowerCase().replaceAll('.', '');
    return switch (normalized) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'webp' => 'image/webp',
      'mp4' || 'm4v' => 'video/mp4',
      'mov' || 'qt' => 'video/quicktime',
      _ => null,
    };
  }
}
