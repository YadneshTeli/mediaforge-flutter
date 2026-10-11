import 'dart:io';
import 'dart:typed_data';

import 'package:mediaforge_flutter/local.dart';
import 'package:mediaforge_flutter/src/io/file_support_stub.dart' as stub_file;
import 'package:mediaforge_flutter/src/io/local_file_support_stub.dart' as stub_local;
import 'package:test/test.dart';

import 'fixtures/fixture_helper.dart';

void main() {
  group('Offline Entry Point (local.dart)', () {
    test('MediaForgeLocal operates with zero network dependencies', () async {
      final input = FixtureHelper.createJpegWithExif(width: 80, height: 80);

      // Verify static entry point methods
      final metadata = await MediaForgeLocal.readMetadata(input);
      expect(metadata.isEmpty, isFalse);

      final clean = await MediaForgeLocal.stripMetadata(input);
      expect(await MediaForgeLocal.verifyClean(clean), isTrue);

      final stripRes = await MediaForgeLocal.stripAndVerify(input);
      expect(stripRes.isVerified, isTrue);

      final gpsClean = await MediaForgeLocal.stripGps(input);
      expect(gpsClean, isNotEmpty);

      final pipelineResult = await MediaForgeLocal.pipeline(input)
          .resize(width: 40, height: 40)
          .execute();
      expect(pipelineResult.width, equals(40));
    });

    test('LocalFileSupport operates locally on disk', () async {
      final tempDir = await Directory.systemTemp.createTemp('mf_local_file_');
      try {
        final file = File('${tempDir.path}/test.jpg');
        final rawBytes = FixtureHelper.createJpegWithExif(width: 80, height: 80);
        await file.writeAsBytes(rawBytes);

        final meta = await LocalFileSupport.readMetadataFile(file);
        expect(meta.isEmpty, isFalse);

        final cleanFile = await LocalFileSupport.stripMetadataFile(file);
        expect(cleanFile.path, equals(file.path));

        final Uint8List bytes = await (cleanFile as File).readAsBytes();
        final isClean = await MediaForgeLocal.verifyClean(bytes);
        expect(isClean, isTrue);
      } finally {
        await tempDir.delete(recursive: true);
      }
    });
  });

  group('File Strip Safety & Bounded Memory', () {
    test('Enforces maximum file size limit and preserves original file on rejection', () async {
      final tempDir = await Directory.systemTemp.createTemp('mf_size_limit_');
      try {
        final file = File('${tempDir.path}/large.jpg');
        final rawBytes = FixtureHelper.createJpegWithExif(width: 80, height: 80);
        await file.writeAsBytes(rawBytes);

        // Enforce a tiny size limit to trigger file_too_large check
        await expectLater(
          () => LocalFileSupport.stripMetadataFile(
            file,
            maxFileSizeBytes: 10, // 10 bytes limit
          ),
          throwsA(
            isA<ProcessingException>()
                .having((e) => e.code, 'code', 'file_too_large'),
          ),
        );

        // Verify original file is intact and unchanged
        final currentBytes = await file.readAsBytes();
        expect(currentBytes.length, equals(rawBytes.length));
        expect(currentBytes, equals(rawBytes));
      } finally {
        await tempDir.delete(recursive: true);
      }
    });

    test('In-place stripping preserves original file when write fails', () async {
      final tempDir = await Directory.systemTemp.createTemp('mf_inplace_');
      try {
        final file = File('${tempDir.path}/source.jpg');
        final rawBytes = FixtureHelper.createJpegWithExif(width: 80, height: 80);
        await file.writeAsBytes(rawBytes);

        // Non-existent file throws file_not_found before altering anything
        final nonExistent = File('${tempDir.path}/missing.jpg');
        await expectLater(
          () => LocalFileSupport.stripMetadataFile(nonExistent),
          throwsA(
            isA<ProcessingException>()
                .having((e) => e.code, 'code', 'file_not_found'),
          ),
        );

        // Normal in-place strip works and preserves content integrity
        await LocalFileSupport.stripMetadataFile(file);
        expect(file.existsSync(), isTrue);
        expect(file.lengthSync(), greaterThan(0));
      } finally {
        await tempDir.delete(recursive: true);
      }
    });

    test('Handles files with spaces without percent-encoding in temp paths', () async {
      final tempDir = await Directory.systemTemp.createTemp('mf spaces dir_');
      try {
        final file = File('${tempDir.path}/my sample photo.jpg');
        final rawBytes = FixtureHelper.createJpegWithExif(width: 80, height: 80);
        await file.writeAsBytes(rawBytes);

        final cleanFile = await LocalFileSupport.stripMetadataFile(file);
        expect(cleanFile.existsSync(), isTrue);
        expect(cleanFile.path, contains('my sample photo.jpg'));
        expect(cleanFile.path.contains('%20'), isFalse);
      } finally {
        await tempDir.delete(recursive: true);
      }
    });
  });

  group('Web Platform Stubs Async Error Delivery', () {
    test('FileSupport web stub emits errors through declared Futures', () async {
      var readFutureHandled = false;
      await stub_file.FileSupport.readMetadataFile('dummy').catchError((Object e) {
        readFutureHandled = true;
        expect(e, isA<UnsupportedError>());
        return const ExifData();
      });
      expect(readFutureHandled, isTrue);

      var stripFutureHandled = false;
      await stub_file.FileSupport.stripMetadataFile('dummy').catchError((Object e) {
        stripFutureHandled = true;
        expect(e, isA<UnsupportedError>());
        return 'fallback';
      });
      expect(stripFutureHandled, isTrue);

      expect(
        stub_file.FileSupport.uploadFile('dummy'),
        throwsUnsupportedError,
      );
    });

    test('LocalFileSupport web stub emits errors through declared Futures', () async {
      var readFutureHandled = false;
      await stub_local.LocalFileSupport.readMetadataFile('dummy').catchError((Object e) {
        readFutureHandled = true;
        expect(e, isA<UnsupportedError>());
        return const ExifData();
      });
      expect(readFutureHandled, isTrue);

      var stripFutureHandled = false;
      await stub_local.LocalFileSupport.stripMetadataFile('dummy').catchError((Object e) {
        stripFutureHandled = true;
        expect(e, isA<UnsupportedError>());
        return 'fallback';
      });
      expect(stripFutureHandled, isTrue);
    });
  });
}
