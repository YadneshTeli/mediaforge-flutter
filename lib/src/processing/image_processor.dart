import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../exceptions/processing_exception.dart';
import '../models/image_format.dart';
import '../models/resize_mode.dart';
import '../utils/mime_type.dart';

/// Dimensions of an image in pixels.
class ImageDimensions {
  /// Width in pixels.
  final int width;

  /// Height in pixels.
  final int height;

  /// Creates an [ImageDimensions] instance.
  const ImageDimensions({required this.width, required this.height});

  /// Aspect ratio of the image (width / height).
  double get aspectRatio => height > 0 ? width / height : 0;

  @override
  String toString() => '${width}x$height';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ImageDimensions &&
          runtimeType == other.runtimeType &&
          width == other.width &&
          height == other.height;

  @override
  int get hashCode => width.hashCode ^ height.hashCode;
}

/// On-device image processing engine.
///
/// Handles resize, compression, and format conversion entirely locally
/// using pure Dart. No native dependencies, no platform channels,
/// works on all platforms including Flutter Web.
class ImageProcessor {
  /// Creates an [ImageProcessor].
  const ImageProcessor();

  /// Resizes an image according to the specified dimensions and [mode].
  Future<Uint8List> resize(
    Uint8List bytes, {
    int? width,
    int? height,
    ResizeMode mode = ResizeMode.fit,
    bool maintainAspectRatio = true,
  }) async {
    if (width == null && height == null) return bytes;

    try {
      final image = _decode(bytes);
      final resized = _applyResize(image, width, height, mode, maintainAspectRatio);
      return _encodeAsOriginalFormat(resized, bytes);
    } on ProcessingException {
      rethrow;
    } catch (e) {
      throw ProcessingException(
        'Failed to resize image: $e',
        code: 'resize_error',
      );
    }
  }

  /// Compresses an image with the given [quality] (1-100).
  Future<Uint8List> compress(
    Uint8List bytes, {
    int quality = 85,
  }) async {
    final clampedQuality = quality.clamp(1, 100).toInt();

    try {
      final image = _decode(bytes);
      final format = MimeType.formatFromBytes(bytes) ?? ImageFormat.jpeg;
      return _encode(image, format, clampedQuality);
    } on ProcessingException {
      rethrow;
    } catch (e) {
      throw ProcessingException(
        'Failed to compress image: $e',
        code: 'compress_error',
      );
    }
  }

  /// Converts an image to the specified [format].
  Future<Uint8List> convert(
    Uint8List bytes, {
    required ImageFormat format,
    int quality = 85,
    bool lossless = false,
  }) async {
    try {
      final image = _decode(bytes);
      return _encode(image, format, quality, lossless: lossless);
    } on ProcessingException {
      rethrow;
    } catch (e) {
      throw ProcessingException(
        'Failed to convert image: $e',
        code: 'convert_error',
      );
    }
  }

  /// Returns the dimensions of the image without fully decoding pixels when possible.
  ///
  /// Faster than a full decode when you only need width/height.
  Future<ImageDimensions> getDimensions(Uint8List bytes) async {
    final fast = _fastDimensions(bytes);
    if (fast != null) return fast;

    try {
      final image = _decode(bytes);
      return ImageDimensions(
        width: image.width,
        height: image.height,
      );
    } on ProcessingException {
      rethrow;
    } catch (e) {
      throw ProcessingException(
        'Failed to read image dimensions: $e',
        code: 'dimensions_error',
      );
    }
  }

  /// Fast binary header sniffing for image dimensions (<0.1ms, zero pixel decode).
  static ImageDimensions? _fastDimensions(Uint8List bytes) {
    if (bytes.length < 16) return null;

    // 1. PNG: IHDR chunk at bytes 12..23
    if (bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47) {
      if (bytes.length >= 24 &&
          bytes[12] == 0x49 &&
          bytes[13] == 0x48 &&
          bytes[14] == 0x44 &&
          bytes[15] == 0x52) {
        final w = (bytes[16] << 24) | (bytes[17] << 16) | (bytes[18] << 8) | bytes[19];
        final h = (bytes[20] << 24) | (bytes[21] << 16) | (bytes[22] << 8) | bytes[23];
        if (w > 0 && h > 0) return ImageDimensions(width: w, height: h);
      }
    }

    // 2. JPEG: SOF markers
    if (bytes[0] == 0xFF && bytes[1] == 0xD8) {
      var offset = 2;
      while (offset + 8 < bytes.length) {
        if (bytes[offset] != 0xFF) {
          offset++;
          continue;
        }
        final marker = bytes[offset + 1];
        if (marker == 0xD9 || marker == 0xDA) break; // EOI or SOS
        if (offset + 4 > bytes.length) break;
        final length = (bytes[offset + 2] << 8) | bytes[offset + 3];

        final isSof = (marker >= 0xC0 && marker <= 0xC3) ||
            (marker >= 0xC5 && marker <= 0xC7) ||
            (marker >= 0xC9 && marker <= 0xCB);

        if (isSof && offset + 8 < bytes.length) {
          final h = (bytes[offset + 5] << 8) | bytes[offset + 6];
          final w = (bytes[offset + 7] << 8) | bytes[offset + 8];
          if (w > 0 && h > 0) return ImageDimensions(width: w, height: h);
        }

        offset += 2 + length;
      }
    }

    // 3. WebP: RIFF .... WEBP
    if (bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x46 &&
        bytes[8] == 0x57 && bytes[9] == 0x45 && bytes[10] == 0x42 && bytes[11] == 0x50) {
      if (bytes.length >= 30) {
        final fourCc = String.fromCharCodes(bytes.sublist(12, 16));
        if (fourCc == 'VP8X' && bytes.length >= 30) {
          final w = 1 + (bytes[24] | (bytes[25] << 8) | (bytes[26] << 16));
          final h = 1 + (bytes[27] | (bytes[28] << 8) | (bytes[29] << 16));
          return ImageDimensions(width: w, height: h);
        } else if (fourCc == 'VP8 ' && bytes.length >= 30) {
          final w = (bytes[26] | (bytes[27] << 8)) & 0x3fff;
          final h = (bytes[28] | (bytes[29] << 8)) & 0x3fff;
          if (w > 0 && h > 0) return ImageDimensions(width: w, height: h);
        } else if (fourCc == 'VP8L' && bytes.length >= 26) {
          final val = bytes[21] | (bytes[22] << 8) | (bytes[23] << 16) | (bytes[24] << 24);
          final w = 1 + (val & 0x3fff);
          final h = 1 + ((val >> 14) & 0x3fff);
          if (w > 0 && h > 0) return ImageDimensions(width: w, height: h);
        }
      }
    }

    return null;
  }

  /// Alias for [getDimensions].
  Future<ImageDimensions> getImageDimensions(Uint8List bytes) =>
      getDimensions(bytes);

  // -- Private helpers --

  img.Image _decode(Uint8List bytes) {
    final image = img.decodeImage(bytes);
    if (image == null) {
      throw const ProcessingException.corruptFile();
    }
    return image;
  }

  img.Image _applyResize(
    img.Image image,
    int? width,
    int? height,
    ResizeMode mode,
    bool maintainAspectRatio,
  ) {
    final targetWidth = width ?? -1;
    final targetHeight = height ?? -1;

    const interpolation = img.Interpolation.linear;

    return switch (mode) {
      ResizeMode.fit => img.copyResize(
          image,
          width: targetWidth > 0 ? targetWidth : null,
          height: targetHeight > 0 ? targetHeight : null,
          interpolation: interpolation,
          maintainAspect: maintainAspectRatio,
        ),
      ResizeMode.cover => _resizeCover(image, targetWidth, targetHeight, interpolation),
      ResizeMode.contain => _resizeContain(image, targetWidth, targetHeight, interpolation),
      ResizeMode.fill => img.copyResize(
          image,
          width: targetWidth > 0 ? targetWidth : image.width,
          height: targetHeight > 0 ? targetHeight : image.height,
          interpolation: interpolation,
          maintainAspect: false,
        ),
    };
  }

  img.Image _resizeCover(
    img.Image image,
    int targetWidth,
    int targetHeight,
    img.Interpolation interpolation,
  ) {
    final w = targetWidth > 0 ? targetWidth : image.width;
    final h = targetHeight > 0 ? targetHeight : image.height;

    final scaleX = w / image.width;
    final scaleY = h / image.height;
    final scale = scaleX > scaleY ? scaleX : scaleY;

    final resizedWidth = (image.width * scale).round();
    final resizedHeight = (image.height * scale).round();

    final resized = img.copyResize(
      image,
      width: resizedWidth,
      height: resizedHeight,
      interpolation: interpolation,
    );

    // Crop to exact target size
    final cropX = (resizedWidth - w) ~/ 2;
    final cropY = (resizedHeight - h) ~/ 2;

    return img.copyCrop(resized, x: cropX, y: cropY, width: w, height: h);
  }

  img.Image _resizeContain(
    img.Image image,
    int targetWidth,
    int targetHeight,
    img.Interpolation interpolation,
  ) {
    final w = targetWidth > 0 ? targetWidth : image.width;
    final h = targetHeight > 0 ? targetHeight : image.height;

    // Fit the image inside the target dimensions
    final resized = img.copyResize(
      image,
      width: w,
      height: h,
      interpolation: interpolation,
      maintainAspect: true,
    );

    // If already fits, return as-is
    if (resized.width == w && resized.height == h) return resized;

    // Create canvas at target size and center the image
    final canvas = img.Image(width: w, height: h);
    final offsetX = (w - resized.width) ~/ 2;
    final offsetY = (h - resized.height) ~/ 2;

    return img.compositeImage(canvas, resized, dstX: offsetX, dstY: offsetY);
  }

  Uint8List _encode(
    img.Image image,
    ImageFormat format,
    int quality, {
    bool lossless = false,
  }) {
    final encoded = switch (format) {
      ImageFormat.jpeg => img.encodeJpg(image, quality: lossless ? 100 : quality),
      ImageFormat.png => img.encodePng(image),
      ImageFormat.webp => throw const ProcessingException(
          'Encoding to WebP is not supported by the pure-Dart on-device engine. '
          'Convert to JPEG or PNG, or use cloud processing via MediaForge.stripCloud().',
          code: 'unsupported_format',
        ),
    };
    return Uint8List.fromList(encoded);
  }

  Uint8List _encodeAsOriginalFormat(img.Image image, Uint8List originalBytes) {
    final format = MimeType.formatFromBytes(originalBytes) ?? ImageFormat.jpeg;
    // Pure Dart cannot encode WebP — fall back to lossless PNG so resize
    // still succeeds on WebP input instead of throwing.
    final safeFormat = format == ImageFormat.webp ? ImageFormat.png : format;
    return _encode(image, safeFormat, 95);
  }
}
