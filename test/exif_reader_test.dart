import 'package:mediaforge_flutter/mediaforge_flutter.dart';
import 'package:test/test.dart';

import 'fixtures/fixture_helper.dart';

void main() {
  group('ExifReader', () {
    const reader = ExifReader();

    test('clean image reports no metadata and returns empty ExifData', () async {
      final cleanJpeg = FixtureHelper.createJpeg();
      final hasMeta = await reader.hasMetadata(cleanJpeg);
      expect(hasMeta, isFalse);

      final metadata = await reader.read(cleanJpeg);
      expect(metadata.isEmpty, isTrue);
      expect(metadata.hasLocation, isFalse);
      expect(metadata.hasCameraInfo, isFalse);
    });

    test('image with EXIF tags extracts camera and software metadata', () async {
      final exifJpeg = FixtureHelper.createJpegWithExif(
        make: 'MediaForgeCamera',
        model: 'TestForge-1',
      );

      final hasMeta = await reader.hasMetadata(exifJpeg);
      expect(hasMeta, isTrue);

      final metadata = await reader.read(exifJpeg);
      expect(metadata.isEmpty, isFalse);
      expect(metadata.cameraMake, equals('MediaForgeCamera'));
      expect(metadata.cameraModel, equals('TestForge-1'));
      expect(metadata.software, equals('MediaForge SDK Test Suite'));
      expect(metadata.dateTimeOriginal, equals(DateTime(2023, 8, 15, 14, 30, 0)));
    });

    test('corrupt image throws ProcessingException', () async {
      final corrupt = FixtureHelper.corruptBytes;
      expect(() => reader.read(corrupt), throwsA(isA<ProcessingException>()));
    });
  });
}
