import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mediaforge_flutter/src/client/mediaforge_client.dart';
import 'package:mediaforge_flutter/src/exceptions/auth_exception.dart';
import 'package:mediaforge_flutter/src/exceptions/network_exception.dart';
import 'package:mediaforge_flutter/src/exceptions/plan_limit_exception.dart';
import 'package:mediaforge_flutter/src/exceptions/processing_exception.dart';
import 'package:test/test.dart';

void main() {
  group('MediaForgeClient - Phase 2', () {
    const testApiKey = 'mf_live_testkey12345';
    const baseUrl = 'https://api.mediaforge.tech';

    test('checkHealth() handles authenticated 200 OK', () async {
      final mock = MockClient((request) async {
        expect(request.url.path, equals('/v1/developer/health'));
        expect(request.headers['X-API-Key'], equals(testApiKey));
        return http.Response(
          jsonEncode({
            'status': 'ok',
            'service': 'MediaForge Developer API',
            'version': '1.0.0',
            'timestamp': '2026-09-17T08:00:00Z',
            'authenticated': true,
            'apiKey': {
              'id': 'key-uuid-1',
              'name': 'CI Key',
              'prefix': 'mf_live_test...',
              'type': 'live',
              'plan': 'forge',
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final client = MediaForgeClient(
        apiKey: testApiKey,
        baseUrl: baseUrl,
        httpClient: mock,
      );

      final health = await client.checkHealth();
      expect(health.isHealthy, isTrue);
      expect(health.authenticated, isTrue);
      expect(health.apiKey?.plan, equals('forge'));
      expect(health.apiKey?.type, equals('live'));
    });

    test('checkHealth() handles 401 invalid key gracefully', () async {
      final mock = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'status': 'unhealthy',
            'error': 'Invalid, revoked, or expired API key',
          }),
          401,
          headers: {'content-type': 'application/json'},
        );
      });

      final client = MediaForgeClient(
        apiKey: 'mf_live_badkey',
        baseUrl: baseUrl,
        httpClient: mock,
      );

      final health = await client.checkHealth();
      expect(health.isHealthy, isFalse);
      expect(health.authenticated, isFalse);
      expect(health.error, contains('Invalid, revoked, or expired'));
    });

    test('stripCloud() streams sanitized binary response', () async {
      final fakeJpg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0x01, 0x02]);
      final cleanJpg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xDB, 0x09]);

      final mock = MockClient((request) async {
        expect(request.url.path, equals('/v1/developer/strip'));
        expect(request.method, equals('POST'));
        expect(request.headers['X-API-Key'], equals(testApiKey));
        return http.Response.bytes(
          cleanJpg,
          200,
          headers: {
            'content-type': 'image/jpeg',
            'x-metadata-stripped': 'true',
          },
        );
      });

      final client = MediaForgeClient(
        apiKey: testApiKey,
        baseUrl: baseUrl,
        httpClient: mock,
      );

      final stripped = await client.stripCloud(fakeJpg, filename: 'photo.jpg');
      expect(stripped, equals(cleanJpg));
    });

    test('uploadToCdn() uploads with progress and returns MediaForgeFile', () async {
      final fakePng = Uint8List.fromList([
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
      ]);

      final progressUpdates = <double>[];

      final mock = MockClient((request) async {
        expect(request.url.path, equals('/v1/developer/upload'));
        expect(request.method, equals('POST'));
        expect(request.headers['X-API-Key'], equals(testApiKey));

        return http.Response(
          jsonEncode({
            'file': {
              'id': 'file-9988',
              'filename': 'icon.png',
              'cdnUrl': 'https://cdn.mediaforge.tech/u/file-9988.png',
              'sizeBytes': fakePng.length,
              'mimeType': 'image/png',
              'format': 'png',
              'width': 64,
              'height': 64,
              'metadataStripped': true,
              'createdAt': '2026-09-17T08:30:00Z',
            }
          }),
          201,
          headers: {'content-type': 'application/json'},
        );
      });

      final client = MediaForgeClient(
        apiKey: testApiKey,
        baseUrl: baseUrl,
        httpClient: mock,
      );

      final uploaded = await client.uploadToCdn(
        fakePng,
        filename: 'icon.png',
        onProgress: (p) => progressUpdates.add(p),
      );

      expect(uploaded.id, equals('file-9988'));
      expect(uploaded.cdnUrl, equals('https://cdn.mediaforge.tech/u/file-9988.png'));
      expect(uploaded.width, equals(64));
      expect(progressUpdates, isNotEmpty);
      expect(progressUpdates.last, equals(1.0));
    });

    test('getUsage() parses account quota telemetry', () async {
      final mock = MockClient((request) async {
        expect(request.url.path, equals('/v1/developer/usage'));
        return http.Response(
          jsonEncode({
            'plan': 'forge',
            'keyType': 'live',
            'operations': {'used': 45, 'limit': 5000},
            'storage': {'usedBytes': 2048, 'limitBytes': 10737418240},
            'bandwidth': {'usedBytes': 4096, 'limitBytes': 53687091200},
            'apiKeys': {'active': 1, 'limit': 3},
            'features': {'cdnUpload': true, 'allowVideo': true},
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final client = MediaForgeClient(
        apiKey: testApiKey,
        baseUrl: baseUrl,
        httpClient: mock,
      );

      final usage = await client.getUsage();
      expect(usage.plan, equals('forge'));
      expect(usage.operationsUsed, equals(45));
      expect(usage.operationsLimit, equals(5000));
      expect(usage.cdnUploadAllowed, isTrue);
    });

    test('listFiles() and deleteFile() manage remote assets', () async {
      final mock = MockClient((request) async {
        if (request.method == 'GET' && request.url.path == '/v1/developer/files') {
          expect(request.url.queryParameters['page'], equals('1'));
          expect(request.url.queryParameters['limit'], equals('10'));
          return http.Response(
            jsonEncode({
              'files': [
                {
                  'id': 'f-item-1',
                  'filename': 'item1.jpg',
                  'cdnUrl': 'https://cdn.mediaforge.tech/item1.jpg',
                  'sizeBytes': 1200,
                  'mimeType': 'image/jpeg',
                  'format': 'jpg',
                  'metadataStripped': true,
                  'createdAt': '2026-09-17T09:00:00Z',
                }
              ],
              'total': 1,
              'page': 1,
              'limit': 10,
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }

        if (request.method == 'GET' && request.url.path == '/v1/developer/files/f-item-1') {
          return http.Response(
            jsonEncode({
              'file': {
                'id': 'f-item-1',
                'filename': 'item1.jpg',
                'cdnUrl': 'https://cdn.mediaforge.tech/item1.jpg',
                'sizeBytes': 1200,
                'mimeType': 'image/jpeg',
                'format': 'jpg',
                'metadataStripped': true,
                'createdAt': '2026-09-17T09:00:00Z',
              }
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }

        if (request.method == 'DELETE' && request.url.path == '/v1/developer/files/f-item-1') {
          return http.Response('', 204);
        }

        return http.Response('Not Found', 404);
      });

      final client = MediaForgeClient(
        apiKey: testApiKey,
        baseUrl: baseUrl,
        httpClient: mock,
      );

      final list = await client.listFiles(page: 1, limit: 10);
      expect(list.files.length, equals(1));
      expect(list.files.first.id, equals('f-item-1'));

      final single = await client.getFile('f-item-1');
      expect(single.id, equals('f-item-1'));

      expect(client.deleteFile('f-item-1'), completes);
    });

    group('Error Status Code Mappings', () {
      test('401 maps to AuthException', () async {
        final mock = MockClient((r) async => http.Response(
              jsonEncode({'error': 'Invalid API Key'}),
              401,
            ));
        final client = MediaForgeClient(apiKey: 'bad', httpClient: mock);

        expect(
          () => client.getUsage(),
          throwsA(isA<AuthException>()),
        );
      });

      test('403 maps to PlanLimitException', () async {
        final mock = MockClient((r) async => http.Response(
              jsonEncode({'error': 'CDN upload requires paid plan'}),
              403,
            ));
        final client = MediaForgeClient(apiKey: 'spark_key', httpClient: mock);

        expect(
          () => client.uploadToCdn(Uint8List(10)),
          throwsA(isA<PlanLimitException>()),
        );
      });

      test('413 maps to PlanLimitException.fileSizeExceeded', () async {
        final mock = MockClient((r) async => http.Response(
              jsonEncode({'error': 'File exceeds 50 MB plan limit'}),
              413,
            ));
        final client = MediaForgeClient(apiKey: 'key', httpClient: mock);

        expect(
          () => client.uploadToCdn(Uint8List(10)),
          throwsA(isA<PlanLimitException>()),
        );
      });

      test('415 maps to ProcessingException', () async {
        final mock = MockClient((r) async => http.Response(
              jsonEncode({'error': 'Unsupported file type'}),
              415,
            ));
        final client = MediaForgeClient(apiKey: 'key', httpClient: mock);

        expect(
          () => client.uploadToCdn(Uint8List(10)),
          throwsA(isA<ProcessingException>()),
        );
      });

      test('429 maps to NetworkException', () async {
        final mock = MockClient((r) async => http.Response(
              jsonEncode({'error': 'Rate limit exceeded'}),
              429,
            ));
        final client = MediaForgeClient(apiKey: 'key', httpClient: mock);

        expect(
          () => client.getUsage(),
          throwsA(isA<NetworkException>()),
        );
      });

      test('429 with quota_exceeded code maps to PlanLimitException', () async {
        final mock = MockClient((r) async => http.Response(
              jsonEncode({
                'error': 'Monthly operation limit reached.',
                'code': 'quota_exceeded',
              }),
              429,
            ));
        final client = MediaForgeClient(apiKey: 'key', httpClient: mock);

        expect(
          () => client.uploadToCdn(Uint8List(10)),
          throwsA(
            isA<PlanLimitException>()
                .having((e) => e.limitName, 'limitName', 'operations')
                .having((e) => e.code, 'code', 'quota_exceeded'),
          ),
        );
      });

      test('403 with bandwidth_exceeded code maps to PlanLimitException',
          () async {
        final mock = MockClient((r) async => http.Response(
              jsonEncode({
                'error': 'Monthly bandwidth limit reached.',
                'code': 'bandwidth_exceeded',
              }),
              403,
            ));
        final client = MediaForgeClient(apiKey: 'key', httpClient: mock);

        expect(
          () => client.uploadToCdn(Uint8List(10)),
          throwsA(
            isA<PlanLimitException>()
                .having((e) => e.limitName, 'limitName', 'bandwidth'),
          ),
        );
      });

      test('request timeout maps to NetworkException with isTimeout', () async {
        final mock = MockClient((r) async {
          await Future<void>.delayed(const Duration(seconds: 5));
          return http.Response('{}', 200);
        });
        final client = MediaForgeClient(
          apiKey: 'key',
          httpClient: mock,
          timeout: const Duration(milliseconds: 50),
        );

        try {
          await client.getUsage();
          fail('Expected NetworkException');
        } on NetworkException catch (e) {
          expect(e.isTimeout, isTrue);
          expect(e.code, equals('timeout'));
        }
      });

      test('500 maps to NetworkException server error', () async {
        final mock = MockClient((r) async => http.Response(
              jsonEncode({'error': 'Internal server error'}),
              500,
            ));
        final client = MediaForgeClient(apiKey: 'key', httpClient: mock);

        expect(
          () => client.getUsage(),
          throwsA(isA<NetworkException>()),
        );
      });
    });
  });
}
