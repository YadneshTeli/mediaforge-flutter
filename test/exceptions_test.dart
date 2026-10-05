import 'package:mediaforge_flutter/mediaforge_flutter.dart';
import 'package:test/test.dart';

void main() {
  group('Exceptions Suite', () {
    test('AuthException constructors', () {
      const invalid = AuthException.invalidApiKey('bad_key');
      expect(invalid.code, equals('invalid_api_key'));
      expect(invalid.message, contains('mf_live_'));
      expect(invalid.toString(), contains('AuthException'));

      const notInit = AuthException.notInitialized();
      expect(notInit.code, equals('not_initialized'));
      expect(notInit.message, contains('MediaForge.init'));

      const invalidKey = AuthException.invalidKey();
      expect(invalidKey.code, equals('invalid_api_key'));
    });

    test('NetworkException constructors', () {
      final timeout = NetworkException.timeout('https://api.mediaforge.tech');
      expect(timeout.code, equals('timeout'));
      expect(timeout.isTimeout, isTrue);

      const noConn = NetworkException.noConnection();
      expect(noConn.code, equals('no_connection'));
      expect(noConn.isConnectionError, isTrue);

      final serverErr = NetworkException.serverError(500, 'Internal error');
      expect(serverErr.code, equals('server_error_500'));
      expect(serverErr.statusCode, equals(500));
      expect(serverErr.isServerError, isTrue);
    });

    test('PlanLimitException constructors', () {
      final fileLimit = PlanLimitException.fileSizeExceeded(
        currentBytes: 15 * 1024 * 1024,
        maxBytes: 10 * 1024 * 1024,
      );
      expect(fileLimit.code, equals('file_size_exceeded'));
      expect(fileLimit.currentUsage, equals(15 * 1024 * 1024));
      expect(fileLimit.maxAllowed, equals(10 * 1024 * 1024));

      final storageLimit = PlanLimitException.storageExceeded(
        currentBytes: 100 * 1024 * 1024,
        maxBytes: 100 * 1024 * 1024,
      );
      expect(storageLimit.code, equals('storage_exceeded'));
    });

    test('ProcessingException constructors', () {
      final unsupported = ProcessingException.unsupportedFormat('image/bmp');
      expect(unsupported.code, equals('unsupported_format'));
      expect(unsupported.message, contains('image/bmp'));

      const corrupt = ProcessingException.corruptFile();
      expect(corrupt.code, equals('corrupt_file'));
      expect(corrupt.message, contains('corrupt'));
    });
  });
}
