import 'package:mediaforge_flutter/mediaforge_flutter.dart';
import 'package:test/test.dart';

import 'fixtures/fixture_helper.dart';

void main() {
  group('ByteUtils', () {
    test('formatFileSize formats across bytes, KB, MB, GB', () {
      expect(ByteUtils.formatFileSize(500), equals('500 bytes'));
      expect(ByteUtils.formatFileSize(1024), equals('1.0 KB'));
      expect(ByteUtils.formatFileSize(1536), equals('1.5 KB'));
      expect(ByteUtils.formatFileSize(1024 * 1024), equals('1.0 MB'));
      expect(ByteUtils.formatFileSize(1024 * 1024 * 1024), equals('1.0 GB'));
    });

    test('calculateSavings handles positive, negative, zero', () {
      expect(ByteUtils.calculateSavings(100, 75), closeTo(0.25, 0.001));
      expect(ByteUtils.calculateSavings(100, 120), closeTo(-0.20, 0.001));
      expect(ByteUtils.calculateSavings(0, 100), equals(0.0));
    });

    test('isValidImage and detectMimeType identify formats correctly', () {
      final jpeg = FixtureHelper.createJpeg();
      final png = FixtureHelper.createPng();
      final webp = FixtureHelper.createWebp();
      final corrupt = FixtureHelper.corruptBytes;

      expect(ByteUtils.isValidImage(jpeg), isTrue);
      expect(ByteUtils.isValidImage(png), isTrue);
      expect(ByteUtils.isValidImage(webp), isTrue);
      expect(ByteUtils.isValidImage(corrupt), isFalse);

      expect(ByteUtils.detectMimeType(jpeg), equals('image/jpeg'));
      expect(ByteUtils.detectMimeType(png), equals('image/png'));
      expect(ByteUtils.detectMimeType(webp), equals('image/webp'));
      expect(ByteUtils.detectMimeType(corrupt), isNull);
    });
  });

  group('MimeType', () {
    test('fromBytes and formatFromBytes detect format', () {
      final jpeg = FixtureHelper.createJpeg();
      final png = FixtureHelper.createPng();
      final webp = FixtureHelper.createWebp();

      expect(MimeType.fromBytes(jpeg), equals('image/jpeg'));
      expect(MimeType.formatFromBytes(jpeg), equals(ImageFormat.jpeg));

      expect(MimeType.fromBytes(png), equals('image/png'));
      expect(MimeType.formatFromBytes(png), equals(ImageFormat.png));

      expect(MimeType.fromBytes(webp), equals('image/webp'));
      expect(MimeType.formatFromBytes(webp), equals(ImageFormat.webp));
    });

    test('isSupported checks supported MIME types', () {
      expect(MimeType.isSupported('image/jpeg'), isTrue);
      expect(MimeType.isSupported('image/png'), isTrue);
      expect(MimeType.isSupported('image/webp'), isTrue);
      expect(MimeType.isSupported('image/gif'), isFalse);
    });

    test('fromExtension checks common extensions', () {
      expect(MimeType.fromExtension('jpg'), equals('image/jpeg'));
      expect(MimeType.fromExtension('.jpeg'), equals('image/jpeg'));
      expect(MimeType.fromExtension('png'), equals('image/png'));
      expect(MimeType.fromExtension('webp'), equals('image/webp'));
      expect(MimeType.fromExtension('svg'), isNull);
    });

    test('WebP fixture is decodable and reads dimensions', () async {
      final webp = FixtureHelper.createWebp();
      final dims = await const ImageProcessor().getImageDimensions(webp);
      expect(dims.width, equals(1));
      expect(dims.height, equals(1));
    });
  });
}
