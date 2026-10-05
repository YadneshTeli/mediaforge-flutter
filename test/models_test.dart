import 'package:mediaforge_flutter/mediaforge_flutter.dart';
import 'package:test/test.dart';

void main() {
  group('ExifData Model', () {
    test('empty constructor has all null fields and isEmpty is true', () {
      const empty = ExifData.empty();
      expect(empty.isEmpty, isTrue);
      expect(empty.isNotEmpty, isFalse);
      expect(empty.hasLocation, isFalse);
      expect(empty.hasCameraInfo, isFalse);
      expect(empty.hasTimestamps, isFalse);
      expect(empty.hasSensitiveData, isFalse);
      expect(empty.fieldCount, equals(0));
      expect(empty.googleMapsUrl, isNull);
      expect(empty.toSummaryMap(), isEmpty);
    });

    test('populated fields report location, camera, and sensitive data', () {
      final data = ExifData(
        gpsLatitude: 37.7749,
        gpsLongitude: -122.4194,
        gpsAltitude: 15.5,
        cameraMake: 'Apple',
        cameraModel: 'iPhone 15 Pro',
        dateTimeOriginal: DateTime(2026, 1, 1, 12, 0),
        artist: 'Photographer',
      );

      expect(data.isEmpty, isFalse);
      expect(data.isNotEmpty, isTrue);
      expect(data.hasLocation, isTrue);
      expect(data.hasCameraInfo, isTrue);
      expect(data.hasTimestamps, isTrue);
      expect(data.hasSensitiveData, isTrue);
      expect(data.googleMapsUrl, equals('https://maps.google.com/?q=37.7749,-122.4194'));

      final summary = data.toSummaryMap();
      expect(summary['Location'], equals('37.7749, -122.4194'));
      expect(summary['Camera Make'], equals('Apple'));
      expect(summary['Camera Model'], equals('iPhone 15 Pro'));

      final fullMap = data.toMap();
      expect(fullMap['gpsLatitude'], equals(37.7749));
      expect(fullMap['cameraMake'], equals('Apple'));
      expect(fullMap['artist'], equals('Photographer'));
    });

    test('fieldCount includes rawFields count', () {
      const data = ExifData(
        cameraMake: 'Sony',
        rawFields: {
          'ExposureProgram': 'Manual',
          'MeteringMode': 'Pattern',
          'Flash': 'Off',
        },
      );
      expect(data.fieldCount, equals(4)); // 1 structured + 3 raw
    });
  });

  group('ProcessingOptions Model & Presets', () {
    test('default options have sensible defaults', () {
      const opts = ProcessingOptions();
      expect(opts.stripMetadata, isTrue);
      expect(opts.stripGpsOnly, isFalse);
      expect(opts.quality, equals(85));
      expect(opts.outputFormat, isNull);
      expect(opts.lossless, isFalse);
      expect(opts.hasResize, isFalse);
      expect(opts.hasFormatConversion, isFalse);
    });

    test('privacyFirst preset strips all metadata', () {
      const opts = ProcessingOptions.privacyFirst();
      expect(opts.stripMetadata, isTrue);
      expect(opts.quality, equals(90));
    });

    test('webOptimized preset targets jpeg format', () {
      const opts = ProcessingOptions.webOptimized(maxWidth: 1600);
      expect(opts.stripMetadata, isTrue);
      expect(opts.outputFormat, equals(ImageFormat.jpeg));
      expect(opts.quality, equals(80));
      expect(opts.resizeWidth, equals(1600));
      expect(opts.hasResize, isTrue);
      expect(opts.hasFormatConversion, isTrue);
    });

    test('thumbnail preset creates small box', () {
      const opts = ProcessingOptions.thumbnail(size: 150);
      expect(opts.stripMetadata, isTrue);
      expect(opts.resizeWidth, equals(150));
      expect(opts.resizeHeight, equals(150));
      expect(opts.resizeMode, equals(ResizeMode.cover));
    });

    test('avatar preset creates square avatar', () {
      const opts = ProcessingOptions.avatar(size: 200);
      expect(opts.stripMetadata, isTrue);
      expect(opts.resizeWidth, equals(200));
      expect(opts.resizeHeight, equals(200));
      expect(opts.resizeMode, equals(ResizeMode.cover));
      expect(opts.outputFormat, equals(ImageFormat.jpeg));
    });

    test('quality clamped validation', () {
      expect(() => ProcessingOptions(quality: -5), throwsA(isA<AssertionError>()));
      expect(() => ProcessingOptions(quality: 105), throwsA(isA<AssertionError>()));
    });

    test('copyWith can clear nullable fields when passing null', () {
      const initial = ProcessingOptions(
        outputFormat: ImageFormat.jpeg,
        resizeWidth: 800,
        resizeHeight: 600,
      );
      final cleared = initial.copyWith(
        outputFormat: null,
        resizeWidth: null,
        resizeHeight: null,
      );
      expect(cleared.outputFormat, isNull);
      expect(cleared.resizeWidth, isNull);
      expect(cleared.resizeHeight, isNull);
      expect(cleared.hasFormatConversion, isFalse);
      expect(cleared.hasResize, isFalse);
    });
  });

  group('ImageFormat Enum', () {
    test('extensions and MIME types match expectations', () {
      expect(ImageFormat.jpeg.extension, equals('jpg'));
      expect(ImageFormat.jpeg.mimeType, equals('image/jpeg'));

      expect(ImageFormat.png.extension, equals('png'));
      expect(ImageFormat.png.mimeType, equals('image/png'));

      expect(ImageFormat.webp.extension, equals('webp'));
      expect(ImageFormat.webp.mimeType, equals('image/webp'));
    });

    test('fromExtension resolves correctly', () {
      expect(ImageFormat.fromExtension('jpg'), equals(ImageFormat.jpeg));
      expect(ImageFormat.fromExtension('.jpeg'), equals(ImageFormat.jpeg));
      expect(ImageFormat.fromExtension('png'), equals(ImageFormat.png));
      expect(ImageFormat.fromExtension('webp'), equals(ImageFormat.webp));
      expect(ImageFormat.fromExtension('gif'), isNull);
    });

    test('fromMimeType resolves correctly', () {
      expect(ImageFormat.fromMimeType('image/jpeg'), equals(ImageFormat.jpeg));
      expect(ImageFormat.fromMimeType('image/png'), equals(ImageFormat.png));
      expect(ImageFormat.fromMimeType('image/webp'), equals(ImageFormat.webp));
      expect(ImageFormat.fromMimeType('application/pdf'), isNull);
    });
  });

  group('UploadResult Model', () {
    test('serializes and deserializes from JSON', () {
      final json = {
        'cdnUrl': 'https://cdn.mediaforge.tech/img123.webp',
        'fileId': 'file_123',
        'sizeBytes': 20480,
        'format': 'webp',
        'width': 800,
        'height': 600,
        'uploadedAt': '2026-09-08T12:00:00.000Z',
      };

      final result = UploadResult.fromJson(json);
      expect(result.cdnUrl, equals('https://cdn.mediaforge.tech/img123.webp'));
      expect(result.fileId, equals('file_123'));
      expect(result.sizeBytes, equals(20480));
      expect(result.format, equals('webp'));
      expect(result.width, equals(800));
      expect(result.height, equals(600));
      expect(result.aspectRatio, closeTo(800 / 600, 0.001));

      final serialized = result.toJson();
      expect(serialized['file_id'], equals('file_123'));
      expect(serialized['cdn_url'], equals('https://cdn.mediaforge.tech/img123.webp'));
    });

    test('fromJson safely parses doubles and missing values without crashing', () {
      final json = {
        'file_id': 'f_num_test',
        'cdn_url': 'https://cdn.mediaforge.tech/num_test.jpg',
        'size_bytes': 1024.0, // double returned by backend
        'format': 'jpg',
        'width': 640.0, // double
        'height': 480.0, // double
        'created_at': '2026-09-17T12:00:00Z',
      };

      final result = UploadResult.fromJson(json);
      expect(result.sizeBytes, equals(1024));
      expect(result.width, equals(640));
      expect(result.height, equals(480));

      final file = result.toMediaForgeFile();
      expect(file.sizeBytes, equals(1024));
      expect(file.width, equals(640));
    });
  });
}
