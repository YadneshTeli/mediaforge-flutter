import 'package:mediaforge_flutter/mediaforge_flutter.dart';
import 'package:test/test.dart';

import 'fixtures/fixture_helper.dart';

void main() {
  group('ProcessingPipeline', () {
    test('chains strip, resize, compress, and convert successfully', () async {
      final input = FixtureHelper.createJpegWithExif(width: 200, height: 200);

      final result = await ProcessingPipeline(input)
          .stripMetadata()
          .resize(width: 100, height: 100, mode: ResizeMode.fit)
          .compress(quality: 75)
          .convert(format: ImageFormat.png)
          .execute();

      expect(result.bytes, isNotEmpty);
      expect(result.width, equals(100));
      expect(result.height, equals(100));
      expect(result.format, equals(ImageFormat.png));
      expect(MimeType.fromBytes(result.bytes), equals('image/png'));
      expect(result.savingsDisplay, isNotEmpty);

      // Verify EXIF was stripped
      final hasMeta = await const ExifReader().hasMetadata(result.bytes);
      expect(hasMeta, isFalse);
    });

    test('pipeline with no steps returns original bytes wrapped in PipelineResult', () async {
      final input = FixtureHelper.createJpeg(width: 120, height: 60);

      final result = await ProcessingPipeline(input).execute();
      expect(result.bytes.length, equals(input.length));
      expect(result.width, equals(120));
      expect(result.height, equals(60));
      expect(result.savingsPercent, closeTo(0.0, 0.001));
      expect(result.savingsDisplay, equals('0%'));
    });
  });
}
