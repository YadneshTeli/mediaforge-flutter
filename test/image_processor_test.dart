import 'package:mediaforge_flutter/mediaforge_flutter.dart';
import 'package:test/test.dart';

import 'fixtures/fixture_helper.dart';

void main() {
  group('ImageProcessor', () {
    const processor = ImageProcessor();

    test('getImageDimensions returns correct dimensions for JPEG and PNG', () async {
      final jpeg = FixtureHelper.createJpeg(width: 150, height: 90);
      final jpegDims = await processor.getImageDimensions(jpeg);
      expect(jpegDims.width, equals(150));
      expect(jpegDims.height, equals(90));

      final png = FixtureHelper.createPng(width: 240, height: 180);
      final pngDims = await processor.getImageDimensions(png);
      expect(pngDims.width, equals(240));
      expect(pngDims.height, equals(180));
    });

    test('resize with ResizeMode.fit scales image properly', () async {
      final input = FixtureHelper.createJpeg(width: 200, height: 100);
      final resized = await processor.resize(
        input,
        width: 100,
        height: 50,
        mode: ResizeMode.fit,
      );

      final dims = await processor.getImageDimensions(resized);
      expect(dims.width, equals(100));
      expect(dims.height, equals(50));
    });

    test('resize with ResizeMode.cover preserves cover dimensions', () async {
      final input = FixtureHelper.createJpeg(width: 200, height: 100);
      final resized = await processor.resize(
        input,
        width: 80,
        height: 80,
        mode: ResizeMode.cover,
      );

      final dims = await processor.getImageDimensions(resized);
      expect(dims.width, equals(80));
      expect(dims.height, equals(80));
    });

    test('convert converts JPEG to PNG and PNG to JPEG', () async {
      final jpeg = FixtureHelper.createJpeg(width: 100, height: 100);
      final png = await processor.convert(jpeg, format: ImageFormat.png);
      expect(MimeType.fromBytes(png), equals('image/png'));

      final jpegAgain = await processor.convert(png, format: ImageFormat.jpeg);
      expect(MimeType.fromBytes(jpegAgain), equals('image/jpeg'));
    });

    test('convert to WebP throws ProcessingException unsupportedFormat', () async {
      final jpeg = FixtureHelper.createJpeg(width: 100, height: 100);
      expect(
        () => processor.convert(jpeg, format: ImageFormat.webp),
        throwsA(isA<ProcessingException>()),
      );
    });

    test('resize on WebP input falls back to PNG output', () async {
      final webp = FixtureHelper.createWebp();
      final resized = await processor.resize(webp, width: 1, height: 1);
      expect(MimeType.fromBytes(resized), equals('image/png'));
    });

    test('compress reduces or changes image quality', () async {
      final jpeg = FixtureHelper.createJpeg(width: 200, height: 200);
      final compressed = await processor.compress(jpeg, quality: 50);

      expect(compressed, isNotEmpty);
      expect(MimeType.fromBytes(compressed), equals('image/jpeg'));
    });

    test('corrupt image throws ProcessingException', () async {
      final corrupt = FixtureHelper.corruptBytes;
      expect(
        () => processor.resize(corrupt, width: 50, height: 50),
        throwsA(isA<ProcessingException>()),
      );
    });
  });
}
