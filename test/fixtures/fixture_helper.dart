import 'dart:convert';
import 'dart:typed_data';
import 'package:image/image.dart' as img;

/// Test fixture generator for generating pure-memory images for testing.
class FixtureHelper {
  FixtureHelper._();

  /// Generates a simple valid 100x100 RGB JPEG image without EXIF.
  static Uint8List createJpeg({int width = 100, int height = 100}) {
    final image = img.Image(width: width, height: height);
    img.fill(image, color: img.ColorRgb8(255, 0, 0)); // Solid red
    return Uint8List.fromList(img.encodeJpg(image));
  }

  /// Generates a valid 100x100 PNG image.
  static Uint8List createPng({int width = 100, int height = 100}) {
    final image = img.Image(width: width, height: height);
    img.fill(image, color: img.ColorRgb8(0, 255, 0)); // Solid green
    return Uint8List.fromList(img.encodePng(image));
  }

  /// Generates a valid, fully-decodable 1x1 WebP byte array.
  static Uint8List createWebp({int width = 1, int height = 1}) {
    return Uint8List.fromList(
      base64Decode('UklGRh4AAABXRUJQVlA4TBEAAAAvAAAAAAfQ//73v/+BiOh/AAA='),
    );
  }

  /// Generates a JPEG with EXIF tags populated.
  static Uint8List createJpegWithExif({
    int width = 120,
    int height = 80,
    String make = 'MediaForgeCamera',
    String model = 'TestForge-1',
    String? dateTimeOriginal = '2023:08:15 14:30:00',
  }) {
    final image = img.Image(width: width, height: height);
    img.fill(image, color: img.ColorRgb8(128, 128, 128));
    
    // Populate EXIF tags
    image.exif.imageIfd['Make'] = make;
    image.exif.imageIfd['Model'] = model;
    image.exif.imageIfd['Software'] = 'MediaForge SDK Test Suite';
    if (dateTimeOriginal != null) {
      image.exif.exifIfd['DateTimeOriginal'] = dateTimeOriginal;
    }
    
    return Uint8List.fromList(img.encodeJpg(image));
  }

  /// Corrupted byte array that cannot be decoded as an image.
  static Uint8List get corruptBytes =>
      Uint8List.fromList([0xDE, 0xAD, 0xBE, 0xEF, 0x00, 0x11, 0x22, 0x33]);

  /// Empty byte array.
  static Uint8List get emptyBytes => Uint8List(0);
}
