import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mediaforge_flutter/mediaforge_flutter.dart';
import 'package:test/test.dart';

import 'fixtures/fixture_helper.dart';

void main() {
  group('MediaForgeConfig & Uploader', () {
    test('valid API key prefixes are accepted', () {
      final configLive = MediaForgeConfig(apiKey: 'mf_live_secret123');
      expect(configLive.isLive, isTrue);
      expect(configLive.isTest, isFalse);

      final configTest = MediaForgeConfig(apiKey: 'mf_test_sandbox456');
      expect(configTest.isLive, isFalse);
      expect(configTest.isTest, isTrue);
    });

    test('invalid API key prefix throws AuthException', () {
      expect(
        () => MediaForgeConfig(apiKey: 'invalid_prefix_key'),
        throwsA(isA<AuthException>()),
      );
    });

    test('uploader successfully uploads clean bytes via mock client', () async {
      final image = FixtureHelper.createJpeg();

      final mockHttp = MockClient((request) async {
        expect(request.url.path, equals('/v1/developer/upload'));
        expect(request.headers['X-API-Key'], equals('mf_test_validkey123'));
        return http.Response(
          jsonEncode({
            'file': {
              'id': 'file-uploaded-1',
              'filename': 'test.jpg',
              'cdnUrl': 'https://cdn.mediaforge.tech/u/file-uploaded-1.jpg',
              'sizeBytes': image.length,
              'mimeType': 'image/jpeg',
              'format': 'jpg',
              'width': 100,
              'height': 100,
              'metadataStripped': true,
              'createdAt': '2026-09-17T09:00:00Z',
            }
          }),
          201,
        );
      });

      final config = MediaForgeConfig(apiKey: 'mf_test_validkey123');
      final client = MediaForgeClient(apiKey: config.apiKey, httpClient: mockHttp);
      final uploader = MediaForgeUploader(config, client: client);

      final result = await uploader.upload(image, filename: 'test.jpg');
      expect(result.fileId, equals('file-uploaded-1'));
      expect(result.cdnUrl, equals('https://cdn.mediaforge.tech/u/file-uploaded-1.jpg'));
      expect(result.width, equals(100));
      expect(result.metadataStripped, isTrue);
    });

    test('UploadProgress tracks progress and completes', () async {
      final progress = UploadProgress();
      final values = <double>[];

      final sub = progress.stream.listen(values.add);

      progress.update(0.25);
      progress.update(0.75);
      progress.complete();

      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(values, equals([0.25, 0.75, 1.0]));
      expect(progress.isComplete, isTrue);

      await sub.cancel();
      progress.dispose();
    });

    test('UploadProgress automatically closes controller on complete() without leaking', () async {
      final progress = UploadProgress();
      var streamClosed = false;

      progress.stream.listen((_) {}, onDone: () {
        streamClosed = true;
      });

      progress.complete();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(streamClosed, isTrue);

      // Calling dispose after complete is safe
      progress.dispose();
    });
  });
}
