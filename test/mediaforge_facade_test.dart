import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mediaforge_flutter/mediaforge_flutter.dart';
import 'package:test/test.dart';

import 'fixtures/fixture_helper.dart';

void main() {
  setUp(() {
    MediaForge.reset();
  });

  tearDown(() {
    MediaForge.reset();
  });

  group('MediaForge Static Facade', () {
    test('initialization state lifecycle', () {
      expect(MediaForge.isInitialized, isFalse);

      MediaForge.init(apiKey: 'mf_live_testkey123');
      expect(MediaForge.isInitialized, isTrue);

      MediaForge.reset();
      expect(MediaForge.isInitialized, isFalse);
    });

    test('local processing works without init', () async {
      final input = FixtureHelper.createJpegWithExif(width: 150, height: 150);

      // 1. Read metadata
      final metadata = await MediaForge.readMetadata(input);
      expect(metadata.isEmpty, isFalse);

      // 2. Strip metadata
      final clean = await MediaForge.stripMetadata(input);
      expect(clean, isNotEmpty);

      // 3. Verify clean
      final isClean = await MediaForge.verifyClean(clean);
      expect(isClean, isTrue);

      // 4. Strip and verify
      final result = await MediaForge.stripAndVerify(input);
      expect(result.isVerified, isTrue);

      // 5. Process with options
      final processed = await MediaForge.process(
        input,
        const ProcessingOptions(
          stripMetadata: true,
          outputFormat: ImageFormat.png,
          resizeWidth: 80,
        ),
      );
      expect(processed, isNotEmpty);

      // 6. Pipeline
      final pipeResult = await MediaForge.pipeline(input)
          .stripMetadata()
          .resize(width: 50, height: 50)
          .execute();
      expect(pipeResult.width, equals(50));
      expect(pipeResult.height, equals(50));
    });

    test('upload throws AuthException when not initialized', () async {
      final input = FixtureHelper.createJpeg();
      expect(
        () => MediaForge.upload(input),
        throwsA(isA<AuthException>()),
      );
    });

    test('upload and processAndUpload work with initialized client', () async {
      final input = FixtureHelper.createJpeg();

      final mockHttp = MockClient((request) async {
        if (request.url.path == '/v1/developer/upload') {
          return http.Response(
            jsonEncode({
              'file': {
                'id': 'file-facade-1',
                'filename': 'facade.jpg',
                'cdnUrl': 'https://cdn.mediaforge.tech/u/file-facade-1.jpg',
                'sizeBytes': input.length,
                'mimeType': 'image/jpeg',
                'format': 'jpg',
                'width': 150,
                'height': 150,
                'metadataStripped': true,
                'createdAt': '2026-09-17T09:00:00Z',
              }
            }),
            201,
          );
        }
        return http.Response('Not Found', 404);
      });

      final customClient = MediaForgeClient(
        apiKey: 'mf_live_validfacadekey',
        httpClient: mockHttp,
      );

      MediaForge.init(
        apiKey: 'mf_live_validfacadekey',
        client: customClient,
      );

      final uploadResult = await MediaForge.upload(input, filename: 'facade.jpg');
      expect(uploadResult.fileId, equals('file-facade-1'));
      expect(uploadResult.cdnUrl, contains('file-facade-1.jpg'));

      final processedUpload = await MediaForge.processAndUpload(
        input,
        options: const ProcessingOptions(
          stripMetadata: true,
          resizeWidth: 100,
        ),
        filename: 'facade.jpg',
      );
      expect(processedUpload.fileId, equals('file-facade-1'));
    });

    test('facade exposes developer cloud methods', () async {
      final cleanBytes = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xDB]);

      final mockHttp = MockClient((request) async {
        if (request.url.path == '/v1/developer/health') {
          return http.Response(
            jsonEncode({
              'status': 'ok',
              'service': 'MediaForge Developer API',
              'version': '1.0.0',
              'timestamp': '2026-09-17T09:00:00Z',
              'authenticated': true,
              'apiKey': {
                'id': 'k-1',
                'name': 'Test Key',
                'prefix': 'mf_test_...',
                'type': 'test',
                'plan': 'forge',
              },
            }),
            200,
          );
        }

        if (request.url.path == '/v1/developer/strip') {
          return http.Response.bytes(cleanBytes, 200);
        }

        if (request.url.path == '/v1/developer/usage') {
          return http.Response(
            jsonEncode({
              'plan': 'forge',
              'keyType': 'test',
              'operations': {'used': 10, 'limit': 1000},
              'storage': {'usedBytes': 1024, 'limitBytes': 2048},
              'bandwidth': {'usedBytes': 2048, 'limitBytes': 4096},
              'apiKeys': {'active': 1, 'limit': 3},
              'features': {'cdnUpload': true, 'allowVideo': true},
            }),
            200,
          );
        }

        if (request.url.path == '/v1/developer/files') {
          return http.Response(
            jsonEncode({
              'files': <Map<String, dynamic>>[],
              'total': 0,
              'page': 1,
              'limit': 20,
            }),
            200,
          );
        }

        return http.Response('Not Found', 404);
      });

      final customClient = MediaForgeClient(
        apiKey: 'mf_test_facade',
        httpClient: mockHttp,
      );

      MediaForge.init(apiKey: 'mf_test_facade', client: customClient);

      final health = await MediaForge.checkHealth();
      expect(health.isHealthy, isTrue);

      final stripped = await MediaForge.stripCloud(cleanBytes);
      expect(stripped, equals(cleanBytes));

      final usage = await MediaForge.getUsage();
      expect(usage.operationsUsed, equals(10));

      final list = await MediaForge.listFiles();
      expect(list.files, isEmpty);
    });
  });
}
