import 'dart:typed_data';

import 'package:mediaforge_flutter/src/models/file_list_result.dart';
import 'package:mediaforge_flutter/src/models/mediaforge_file.dart';
import 'package:mediaforge_flutter/src/models/mediaforge_health.dart';
import 'package:mediaforge_flutter/src/models/mediaforge_usage.dart';
import 'package:mediaforge_flutter/src/models/upload_result.dart';
import 'package:mediaforge_flutter/src/utils/byte_utils.dart';
import 'package:mediaforge_flutter/src/utils/mime_type.dart';
import 'package:test/test.dart';

void main() {
  group('Phase 1 Models', () {
    test('MediaForgeFile deserializes both camelCase and snake_case', () {
      final jsonCamel = {
        'id': 'file-123',
        'filename': 'photo.webp',
        'originalFilename': 'raw.jpg',
        'cdnUrl': 'https://cdn.mediaforge.tech/u/file-123.webp',
        'sizeBytes': 1024,
        'mimeType': 'image/webp',
        'format': 'webp',
        'width': 800,
        'height': 600,
        'metadataStripped': true,
        'cdnServingEnabled': true,
        'createdAt': '2026-09-17T08:00:00.000Z',
      };

      final file = MediaForgeFile.fromJson(jsonCamel);
      expect(file.id, equals('file-123'));
      expect(file.filename, equals('photo.webp'));
      expect(file.originalFilename, equals('raw.jpg'));
      expect(file.cdnUrl, equals('https://cdn.mediaforge.tech/u/file-123.webp'));
      expect(file.sizeBytes, equals(1024));
      expect(file.width, equals(800));
      expect(file.height, equals(600));
      expect(file.aspectRatio, closeTo(1.333, 0.001));
      expect(file.markdownEmbed, contains('![photo.webp]'));

      final jsonSnake = {
        'id': 'file-456',
        'filename': 'video.mp4',
        'original_filename': 'camera.mov',
        'cdn_url': 'https://cdn.mediaforge.tech/u/file-456.mp4',
        'size_bytes': 2048000,
        'mime_type': 'video/mp4',
        'format': 'mp4',
        'metadata_stripped': true,
        'cdn_serving_enabled': false,
        'created_at': '2026-09-17T08:00:00.000Z',
      };

      final videoFile = MediaForgeFile.fromJson(jsonSnake);
      expect(videoFile.id, equals('file-456'));
      expect(videoFile.filename, equals('video.mp4'));
      expect(videoFile.originalFilename, equals('camera.mov'));
      expect(videoFile.cdnServingEnabled, isFalse);
    });

    test('MediaForgeUsage parses quota telemetry and computes ratios', () {
      final usageJson = {
        'plan': 'forge',
        'keyType': 'live',
        'operations': {'used': 250, 'limit': 1000},
        'storage': {'usedBytes': 500, 'limitBytes': 1000},
        'bandwidth': {'usedBytes': 100, 'limitBytes': 1000},
        'apiKeys': {'active': 2, 'limit': 3},
        'features': {'cdnUpload': true, 'allowVideo': true},
      };

      final usage = MediaForgeUsage.fromJson(usageJson);
      expect(usage.plan, equals('forge'));
      expect(usage.keyType, equals('live'));
      expect(usage.operationsUsed, equals(250));
      expect(usage.operationsLimit, equals(1000));
      expect(usage.operationsRatio, equals(0.25));
      expect(usage.storageRatio, equals(0.5));
      expect(usage.cdnUploadAllowed, isTrue);
      expect(usage.allowVideo, isTrue);
      expect(usage.isOperationsExhausted, isFalse);
    });

    test('MediaForgeHealth parses authenticated and unauthenticated responses', () {
      final unauthJson = {
        'status': 'ok',
        'service': 'MediaForge Developer API',
        'version': '1.0.0',
        'timestamp': '2026-09-17T08:00:00Z',
        'authenticated': false,
      };
      final healthUnauth = MediaForgeHealth.fromJson(unauthJson);
      expect(healthUnauth.isHealthy, isTrue);
      expect(healthUnauth.authenticated, isFalse);
      expect(healthUnauth.apiKey, isNull);

      final authJson = {
        'status': 'ok',
        'service': 'MediaForge Developer API',
        'version': '1.0.0',
        'timestamp': '2026-09-17T08:00:00Z',
        'authenticated': true,
        'apiKey': {
          'id': 'key-abc',
          'name': 'Prod Key',
          'prefix': 'mf_live_123...',
          'type': 'live',
          'plan': 'forge+',
        },
      };
      final healthAuth = MediaForgeHealth.fromJson(authJson);
      expect(healthAuth.isHealthy, isTrue);
      expect(healthAuth.authenticated, isTrue);
      expect(healthAuth.apiKey?.plan, equals('forge+'));
      expect(healthAuth.apiKey?.isLive, isTrue);
    });

    test('FileListResult handles both total pagination and cursor pagination', () {
      final json = {
        'files': [
          {
            'id': 'f-1',
            'filename': '1.png',
            'cdnUrl': 'https://cdn.mediaforge.tech/1.png',
            'sizeBytes': 100,
            'mimeType': 'image/png',
            'format': 'png',
            'metadataStripped': true,
            'createdAt': '2026-09-17T08:00:00Z',
          }
        ],
        'total': 25,
        'page': 1,
        'limit': 10,
        'cursor': 'next_cur_123',
      };

      final result = FileListResult.fromJson(json);
      expect(result.files.length, equals(1));
      expect(result.total, equals(25));
      expect(result.page, equals(1));
      expect(result.hasMore, isTrue);
    });

    test('UploadResult interoperates with MediaForgeFile and wrapped responses', () {
      final wrappedJson = {
        'file': {
          'id': 'f-999',
          'filename': 'wrapped.jpg',
          'cdnUrl': 'https://cdn.mediaforge.tech/wrapped.jpg',
          'sizeBytes': 5000,
          'mimeType': 'image/jpeg',
          'format': 'jpg',
          'metadataStripped': true,
          'createdAt': '2026-09-17T08:00:00Z',
        }
      };

      final uploadResult = UploadResult.fromJson(wrappedJson);
      expect(uploadResult.fileId, equals('f-999'));
      expect(uploadResult.filename, equals('wrapped.jpg'));
      expect(uploadResult.sizeBytes, equals(5000));

      final asFile = uploadResult.toMediaForgeFile();
      expect(asFile.id, equals('f-999'));
      expect(asFile.filename, equals('wrapped.jpg'));

      final fromFile = UploadResult.fromMediaForgeFile(asFile);
      expect(fromFile.fileId, equals('f-999'));
    });
  });

  group('Phase 1 MIME & ByteUtils Video Detection', () {
    test('detects MP4 magic bytes', () {
      // 4 bytes length, 'ftyp', 'isom'
      final mp4Bytes = Uint8List.fromList([
        0x00, 0x00, 0x00, 0x18, // box size
        0x66, 0x74, 0x79, 0x70, // 'ftyp'
        0x69, 0x73, 0x6F, 0x6D, // 'isom'
        0x00, 0x00, 0x02, 0x00,
      ]);

      expect(MimeType.fromBytes(mp4Bytes), equals('video/mp4'));
      expect(MimeType.isVideoBytes(mp4Bytes), isTrue);
      expect(MimeType.isImageBytes(mp4Bytes), isFalse);
      expect(ByteUtils.isVideo(mp4Bytes), isTrue);
      expect(ByteUtils.isValidMedia(mp4Bytes), isTrue);
    });

    test('detects QuickTime MOV magic bytes', () {
      // 4 bytes length, 'ftyp', 'qt  '
      final movBytes = Uint8List.fromList([
        0x00, 0x00, 0x00, 0x14, // box size
        0x66, 0x74, 0x79, 0x70, // 'ftyp'
        0x71, 0x74, 0x20, 0x20, // 'qt  '
      ]);

      expect(MimeType.fromBytes(movBytes), equals('video/quicktime'));
      expect(MimeType.isVideoBytes(movBytes), isTrue);
      expect(ByteUtils.isVideo(movBytes), isTrue);
    });

    test('detects QuickTime moov atom', () {
      final movMoov = Uint8List.fromList([
        0x00, 0x00, 0x00, 0x08,
        0x6D, 0x6F, 0x6F, 0x76, // 'moov'
      ]);

      expect(MimeType.fromBytes(movMoov), equals('video/quicktime'));
    });

    test('detects video extensions', () {
      expect(MimeType.fromExtension('.mp4'), equals('video/mp4'));
      expect(MimeType.fromExtension('mov'), equals('video/quicktime'));
      expect(MimeType.fromExtension('m4v'), equals('video/mp4'));
    });
  });
}
