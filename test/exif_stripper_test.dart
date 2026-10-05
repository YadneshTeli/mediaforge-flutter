import 'package:mediaforge_flutter/mediaforge_flutter.dart';
import 'package:test/test.dart';

import 'fixtures/fixture_helper.dart';

void main() {
  group('ExifStripper', () {
    const stripper = ExifStripper();
    const reader = ExifReader();

    test('stripAll removes all metadata and verifies clean', () async {
      final dirtyJpeg = FixtureHelper.createJpegWithExif();
      expect(await reader.hasMetadata(dirtyJpeg), isTrue);

      final cleanBytes = await stripper.stripAll(dirtyJpeg);
      expect(cleanBytes, isNotEmpty);

      final isClean = await stripper.verify(cleanBytes);
      expect(isClean, isTrue);

      final metaAfter = await reader.read(cleanBytes);
      expect(metaAfter.isEmpty, isTrue);
    });

    test('stripAndVerify returns verified StrippingResult', () async {
      final dirtyJpeg = FixtureHelper.createJpegWithExif();
      final result = await stripper.stripAndVerify(dirtyJpeg);

      expect(result.isVerified, isTrue);
      expect(result.fieldsRemoved, greaterThan(0));
      expect(result.cleanBytes, isNotEmpty);
    });

    test('corrupt image throws ProcessingException', () async {
      final corrupt = FixtureHelper.corruptBytes;
      expect(() => stripper.stripAll(corrupt), throwsA(isA<ProcessingException>()));
    });

    test('stripSelective removes targeted metadata while preserving untouched', () async {
      final dirtyJpeg = FixtureHelper.createJpegWithExif(make: 'Nikon', model: 'D850');
      final strippedGpsOnly = await stripper.stripSelective(
        dirtyJpeg,
        stripGps: true,
        stripCamera: false,
        stripTimestamps: false,
      );

      final metaAfter = await reader.read(strippedGpsOnly);
      expect(metaAfter.cameraMake, equals('Nikon'));
      expect(metaAfter.cameraModel, equals('D850'));
    });

    test('WebP RIFF chunk stripping preserves WebP structure', () async {
      final webp = FixtureHelper.createWebp();
      final stripped = await stripper.stripAll(webp);
      expect(stripped, isNotEmpty);
      expect(stripped.sublist(0, 4), equals([0x52, 0x49, 0x46, 0x46])); // RIFF
      expect(stripped.sublist(8, 12), equals([0x57, 0x45, 0x42, 0x50])); // WEBP
    });

    test('verify returns false on corrupt or invalid bytes', () async {
      final isClean = await stripper.verify(FixtureHelper.corruptBytes);
      expect(isClean, isFalse);
    });

    test('ExifData.isEmpty returns false if city, country, lensModel, or gpsAltitude are set', () {
      expect(const ExifData(city: 'Tokyo').isEmpty, isFalse);
      expect(const ExifData(country: 'Japan').isEmpty, isFalse);
      expect(const ExifData(lensModel: '50mm f/1.8').isEmpty, isFalse);
      expect(const ExifData(gpsAltitude: 120.5).isEmpty, isFalse);
      expect(const ExifData().isEmpty, isTrue);
    });
  });
}
