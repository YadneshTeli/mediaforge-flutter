import 'dart:io';
import 'dart:typed_data';

import 'package:exif/exif.dart' show IfdBytes, IfdTag, IfdRatios, Ratio;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:mediaforge_flutter/mediaforge_flutter.dart';
import 'package:test/test.dart';

import 'fixtures/fixture_helper.dart';

class MockXFile {
  final String path;
  MockXFile(this.path);
}

void main() {
  group('Audit Remediation (H1-H3, M1-M6, L1-L10)', () {
    test(
        'H3: stripMetadataFile handles filenames with percent signs without throwing',
        () async {
      final tempDir = await Directory.systemTemp.createTemp('mf_pct_test_');
      try {
        final file = File('${tempDir.path}/photo_50%.jpg');
        final rawBytes =
            FixtureHelper.createJpegWithExif(width: 50, height: 50);
        await file.writeAsBytes(rawBytes);

        final cleanFile = await LocalFileSupport.stripMetadataFile(file);
        expect(cleanFile.existsSync(), isTrue);
        final bytes = await (cleanFile as File).readAsBytes();
        final isClean = await MediaForgeLocal.verifyClean(bytes);
        expect(isClean, isTrue);
      } finally {
        await tempDir.delete(recursive: true);
      }
    });

    test('L1: LocalFileSupport accepts duck-typed XFile objects with .path',
        () async {
      final tempDir = await Directory.systemTemp.createTemp('mf_xfile_test_');
      try {
        final file = File('${tempDir.path}/input.jpg');
        await file.writeAsBytes(
            FixtureHelper.createJpegWithExif(width: 40, height: 40));

        final xfile = MockXFile(file.path);
        final meta = await LocalFileSupport.readMetadataFile(xfile);
        expect(meta.isEmpty, isFalse);

        final cleanFile = await LocalFileSupport.stripMetadataFile(xfile);
        expect(cleanFile.existsSync(), isTrue);
      } finally {
        await tempDir.delete(recursive: true);
      }
    });

    test(
        'H1: PNG text/XMP chunks are stripped by stripAll and detected by verify',
        () async {
      final im = img.Image(width: 10, height: 10);
      im.textData = {
        'Comment': 'Secret Comment',
        'XML:com.adobe.xmp': '<xmp>Secret</xmp>',
      };
      final pngBytes = Uint8List.fromList(img.encodePng(im));

      expect(ExifStripper.hasMetadataHeaders(pngBytes), isTrue);
      final isCleanBefore = await const ExifStripper().verify(pngBytes);
      expect(isCleanBefore, isFalse);

      final clean = await const ExifStripper().stripAll(pngBytes);
      expect(ExifStripper.hasMetadataHeaders(clean), isFalse);
      final isCleanAfter = await const ExifStripper().verify(clean);
      expect(isCleanAfter, isTrue);
    });

    test(
        'H2: JPEG with XMP APP1 block fails verify before strip and passes after',
        () async {
      const xmp =
          'http://ns.adobe.com/xap/1.0/\x00<x:xmpmeta>GPS:37.7</x:xmpmeta>';
      const len = xmp.length + 2;
      final jpegWithXmp = Uint8List.fromList([
        0xFF, 0xD8, // SOI
        0xFF, 0xE1, // APP1
        (len >> 8) & 0xFF, len & 0xFF,
        ...xmp.codeUnits,
        0xFF, 0xDB, 0x00, 0x04, 0x00, 0x00, // DQT
        0xFF, 0xC0, 0x00, 0x0B, 0x08, 0x00, 0x0A, 0x00, 0x0A, 0x01, 0x01, 0x11,
        0x00, // SOF0
        0xFF, 0xDA, 0x00, 0x08, 0x01, 0x01, 0x00, 0x00, 0x3F, 0x00, 0x00, // SOS
        0xFF, 0xD9, // EOI
      ]);

      final isCleanBefore = await const ExifStripper().verify(jpegWithXmp);
      expect(isCleanBefore, isFalse);

      final clean = await const ExifStripper().stripAll(jpegWithXmp);
      expect(await const ExifStripper().verify(clean), isTrue);
    });

    test(
        'M1: ResizeMode.fit scales within bounding box preserving aspect ratio without padding',
        () async {
      final image = img.Image(width: 100, height: 50);
      final bytes = Uint8List.fromList(img.encodeJpg(image));

      final resizedBytes = await const ImageProcessor().resize(
        bytes,
        width: 40,
        height: 40,
        mode: ResizeMode.fit,
        maintainAspectRatio: true,
      );

      final dims = await const ImageProcessor().getDimensions(resizedBytes);
      expect(dims.width, equals(40));
      expect(dims.height, equals(20));
    });

    test('M2: WebP compress succeeds via safe fallback without throwing',
        () async {
      final webp = FixtureHelper.createWebp(width: 40, height: 40);
      final compressed =
          await const ImageProcessor().compress(webp, quality: 75);
      expect(compressed, isNotEmpty);
      expect(MimeType.fromBytes(compressed), equals('image/png'));
    });

    test(
        'M2: MediaForgeLocal.process preserves WebP when no format conversion requested',
        () async {
      final webp = FixtureHelper.createWebp(width: 40, height: 40);
      final processed =
          await MediaForgeLocal.process(webp, const ProcessingOptions());
      expect(MimeType.fromBytes(processed), equals('image/webp'));
    });

    test('L8: GPS altitude below sea level produces negative altitude', () {
      final tags = <String, IfdTag>{
        'GPS GPSAltitude': IfdTag(
          tag: 0x0006,
          printable: '150',
          tagType: 'Ratio',
          values: IfdRatios([Ratio(150, 1)]),
        ),
        'GPS GPSAltitudeRef': IfdTag(
          tag: 0x0005,
          printable: '1',
          tagType: 'Byte',
          values: IfdBytes(Uint8List.fromList([1])),
        ),
      };
      final parsed = const ExifReader().parseTags(tags);
      expect(parsed.gpsAltitude, equals(-150.0));
    });

    test(
        'Lossless JPEG segment stripping removes EXIF and preserves dimensions',
        () async {
      final rawBytes = FixtureHelper.createJpegWithExif(width: 60, height: 40);
      final cleanBytes = await const ExifStripper().stripAll(rawBytes);

      expect(cleanBytes.length, lessThan(rawBytes.length));
      final dims = await const ImageProcessor().getDimensions(cleanBytes);
      expect(dims.width, equals(60));
      expect(dims.height, equals(40));
      expect(await const ExifStripper().verify(cleanBytes), isTrue);
    });

    test(
        'Default maxUploadBytes is 10 MB in MediaForgeClient and MediaForgeConfig',
        () {
      expect(MediaForgeClient.defaultMaxUploadBytes, equals(10 * 1024 * 1024));
      final client = MediaForgeClient(apiKey: 'mf_test_123');
      expect(client.maxUploadBytes, equals(10 * 1024 * 1024));
      client.close();

      final config = MediaForgeConfig(apiKey: 'mf_test_123');
      expect(config.maxUploadBytes, equals(10 * 1024 * 1024));
    });

    test(
        'MediaForgeClient.close marks isClosed and prevents subsequent requests',
        () async {
      final client = MediaForgeClient(apiKey: 'mf_test_123');
      expect(client.isClosed, isFalse);

      client.close();
      expect(client.isClosed, isTrue);

      expect(
        () => client.checkHealth(),
        throwsA(
          isA<NetworkException>()
              .having((e) => e.code, 'code', equals('client_closed')),
        ),
      );

      expect(
        () => client.getUsage(),
        throwsA(
          isA<NetworkException>()
              .having((e) => e.code, 'code', equals('client_closed')),
        ),
      );

      expect(
        () => client.uploadToCdn(Uint8List.fromList([1, 2, 3])),
        throwsA(
          isA<NetworkException>()
              .having((e) => e.code, 'code', equals('client_closed')),
        ),
      );
    });

    test('Injected httpClient remains open and usable after request timeout',
        () async {
      var requestCount = 0;

      final mockClient = MockClient((request) async {
        requestCount++;
        if (requestCount == 1) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        return http.Response('{"status":"ok"}', 200);
      });

      final client = MediaForgeClient(
        apiKey: 'mf_test_123',
        httpClient: mockClient,
      );

      expect(
        () => client.stripCloud(
          Uint8List.fromList([1, 2, 3, 4]),
          timeout: const Duration(milliseconds: 20),
        ),
        throwsA(isA<NetworkException>()
            .having((e) => e.isTimeout, 'isTimeout', isTrue)),
      );

      await Future<void>.delayed(const Duration(milliseconds: 120));

      // The injected mockClient must not be closed and must remain completely functional
      final res = await mockClient
          .get(Uri.parse('https://api.mediaforge.tech/v1/test'));
      expect(res.statusCode, equals(200));

      client.close();
    });

    test(
        'L5: Malformed JSON response on 200/201 throws typed upload_parse_error',
        () async {
      final mockClient = MockClient((request) async {
        return http.Response('not valid json', 200);
      });

      final client = MediaForgeClient(
        apiKey: 'mf_test_123',
        httpClient: mockClient,
      );

      await expectLater(
        client.uploadToCdn(Uint8List.fromList([1, 2, 3])),
        throwsA(
          isA<NetworkException>()
              .having((e) => e.code, 'code', equals('upload_parse_error'))
              .having((e) => e.statusCode, 'statusCode', equals(200)),
        ),
      );

      client.close();
    });
  });
}
