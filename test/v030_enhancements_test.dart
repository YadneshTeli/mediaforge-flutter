import 'dart:convert';
import 'dart:io';

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

  group('v0.3.0 Architecture & Ergonomics', () {
    test('MediaForge.local provides pure on-device methods with zero auth (Suggestion 3.1)', () async {
      final input = FixtureHelper.createJpegWithExif(width: 120, height: 120);

      // Verify no init was called
      expect(MediaForge.isInitialized, isFalse);

      final metadata = await MediaForge.local.readMetadata(input);
      expect(metadata.isEmpty, isFalse);

      final clean = await MediaForge.local.stripMetadata(input);
      expect(await MediaForge.local.verifyClean(clean), isTrue);

      final stripRes = await MediaForge.local.stripAndVerify(input);
      expect(stripRes.isVerified, isTrue);

      final gpsClean = await MediaForge.local.stripGps(input);
      expect(gpsClean, isNotEmpty);

      final processed = await MediaForge.local.process(
        input,
        const ProcessingOptions(resizeWidth: 60, stripMetadata: true),
      );
      expect(processed, isNotEmpty);

      final pipelineRes = await MediaForge.local.pipeline(input)
          .resize(width: 50, height: 50)
          .execute();
      expect(pipelineRes.width, equals(50));
    });

    test('MediaForge.cloud namespaces developer services and requires init (Suggestion 3.1)', () async {
      expect(
        () => MediaForge.cloud.getUsage(),
        throwsA(isA<AuthException>()),
      );

      final mockHttp = MockClient((request) async {
        if (request.url.path == '/v1/developer/usage') {
          return http.Response(
            jsonEncode({
              'plan': 'forge',
              'keyType': 'live',
              'operations': {'used': 5, 'limit': 100},
              'storage': {'usedBytes': 500, 'limitBytes': 1000},
              'bandwidth': {'usedBytes': 200, 'limitBytes': 2000},
              'apiKeys': {'active': 1, 'limit': 3},
              'features': {'cdnUpload': true, 'allowVideo': true},
            }),
            200,
          );
        }
        return http.Response('Not Found', 404);
      });

      final client = MediaForgeClient(
        apiKey: 'mf_live_testcloud123',
        httpClient: mockHttp,
      );
      MediaForge.init(apiKey: 'mf_live_testcloud123', client: client);

      final usage = await MediaForge.cloud.getUsage();
      expect(usage.operationsUsed, equals(5));
      expect(usage.plan, equals('forge'));
    });

    test('Pipeline directly chains into .upload() in one fluent statement (Suggestion 2.2)', () async {
      final input = FixtureHelper.createJpegWithExif(width: 150, height: 150);

      final mockHttp = MockClient((request) async {
        expect(request.url.path, equals('/v1/developer/upload'));
        return http.Response(
          jsonEncode({
            'file': {
              'id': 'file-pipeline-upload-1',
              'filename': 'clean.jpg',
              'cdnUrl': 'https://cdn.mediaforge.tech/u/clean.jpg',
              'sizeBytes': 1000,
              'mimeType': 'image/jpeg',
              'format': 'jpg',
              'width': 80,
              'height': 80,
              'metadataStripped': true,
              'createdAt': '2026-09-17T09:00:00Z',
            }
          }),
          201,
        );
      });

      final client = MediaForgeClient(
        apiKey: 'mf_live_testpipeline',
        httpClient: mockHttp,
      );
      MediaForge.init(apiKey: 'mf_live_testpipeline', client: client);

      final uploadResult = await MediaForge.pipeline(input)
          .stripMetadata()
          .resize(width: 80, height: 80)
          .compress(quality: 80)
          .upload(filename: 'clean.jpg');

      expect(uploadResult.fileId, equals('file-pipeline-upload-1'));
      expect(uploadResult.cdnUrl, equals('https://cdn.mediaforge.tech/u/clean.jpg'));
      expect(uploadResult.width, equals(80));
    });

    test('Pipeline execution in background isolate works on supported platforms (Suggestion 2.3)', () async {
      final input = FixtureHelper.createJpeg(width: 100, height: 100);

      // Force background isolate execution
      final result = await MediaForge.pipeline(input, runInIsolate: true)
          .resize(width: 50, height: 50)
          .execute();

      expect(result.width, equals(50));
      expect(result.height, equals(50));
      expect(result.bytes, isNotEmpty);
    });

    test('File-based operations read, strip, and upload files without OOM (Suggestion 2.1)', () async {
      final tempDir = await Directory.systemTemp.createTemp('mediaforge_test_');
      try {
        final imageFile = File('${tempDir.path}/sample.jpg');
        final cleanFile = File('${tempDir.path}/clean.jpg');
        final rawBytes = FixtureHelper.createJpegWithExif(width: 100, height: 100);
        await imageFile.writeAsBytes(rawBytes);

        // 1. readMetadataFile
        final metadata = await MediaForge.readMetadataFile(imageFile);
        expect(metadata.isEmpty, isFalse);

        // Also via local namespace
        final localMetadata = await MediaForge.local.readMetadataFile(imageFile);
        expect(localMetadata.isEmpty, isFalse);

        // 2. stripMetadataFile
        final stripped = await MediaForge.stripMetadataFile(
          imageFile,
          destinationFile: cleanFile,
        );
        expect(cleanFile.existsSync(), isTrue);
        final isClean = await MediaForge.verifyClean(await (stripped as File).readAsBytes());
        expect(isClean, isTrue);

        // 3. uploadFile
        final mockHttp = MockClient((request) async {
          expect(request.url.path, equals('/v1/developer/upload'));
          return http.Response(
            jsonEncode({
              'file': {
                'id': 'f-file-uploaded',
                'filename': 'sample.jpg',
                'cdnUrl': 'https://cdn.mediaforge.tech/sample.jpg',
                'sizeBytes': rawBytes.length,
                'mimeType': 'image/jpeg',
                'format': 'jpg',
                'width': 100,
                'height': 100,
                'metadataStripped': false,
                'createdAt': '2026-09-17T09:00:00Z',
              }
            }),
            201,
          );
        });

        final client = MediaForgeClient(
          apiKey: 'mf_live_testfile',
          httpClient: mockHttp,
        );
        MediaForge.init(apiKey: 'mf_live_testfile', client: client);

        final uploadResult = await MediaForge.uploadFile(imageFile);
        expect(uploadResult.fileId, equals('f-file-uploaded'));
        expect(uploadResult.cdnUrl, contains('sample.jpg'));
      } finally {
        await tempDir.delete(recursive: true);
      }
    });

    test('MediaForge.deleteFiles delegates batch deletion', () async {
      final mockHttp = MockClient((request) async {
        return http.Response('', 204);
      });

      final client = MediaForgeClient(
        apiKey: 'mf_live_batch',
        httpClient: mockHttp,
      );
      MediaForge.init(apiKey: 'mf_live_batch', client: client);

      final result = await MediaForge.deleteFiles(['file-1', 'file-2']);
      expect(result.allSucceeded, isTrue);
      expect(result.deleted, equals(['file-1', 'file-2']));
    });
  });
}
