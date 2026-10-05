import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../exceptions/auth_exception.dart';
import '../exceptions/mediaforge_exception.dart';
import '../exceptions/network_exception.dart';
import '../exceptions/plan_limit_exception.dart';
import '../exceptions/processing_exception.dart';
import '../models/file_list_result.dart';
import '../models/mediaforge_file.dart';
import '../models/mediaforge_health.dart';
import '../models/mediaforge_usage.dart';
import '../utils/mime_type.dart';

/// Progress callback reporting upload completion ratio from 0.0 to 1.0.
typedef ProgressCallback = void Function(double progress);

/// Client for communicating with the MediaForge Developer REST API.
///
/// Handles authentication, multipart streaming, progress tracking,
/// quota telemetry, and remote asset management.
class MediaForgeClient {
  /// The Developer API key (`mf_live_...` or `mf_test_...`).
  final String apiKey;

  /// Root URL of the MediaForge API.
  final String baseUrl;

  /// Request timeout duration.
  final Duration timeout;

  final http.Client _httpClient;
  final bool _ownsClient;

  /// Creates a [MediaForgeClient].
  ///
  /// Parameters:
  /// - [apiKey]: Developer API key
  /// - [baseUrl]: API base URL (defaults to `https://api.mediaforge.tech`)
  /// - [timeout]: Request timeout (defaults to 30 seconds)
  /// - [httpClient]: Optional custom [http.Client] (useful for testing or proxying)
  MediaForgeClient({
    required this.apiKey,
    String baseUrl = 'https://api.mediaforge.tech',
    this.timeout = const Duration(seconds: 30),
    http.Client? httpClient,
  })  : baseUrl = _normalizeBaseUrl(baseUrl),
        _httpClient = httpClient ?? http.Client(),
        _ownsClient = httpClient == null;

  static String _normalizeBaseUrl(String url) {
    var clean = url.trim();
    while (clean.endsWith('/')) {
      clean = clean.substring(0, clean.length - 1);
    }
    return clean;
  }

  /// Default headers sent with requests.
  Map<String, String> get _headers => {
        'X-API-Key': apiKey,
        'User-Agent': 'mediaforge-flutter/0.2.1',
      };

  // ---------------------------------------------------------------------------
  // 1. Health & Key Verification (GET /v1/developer/health)
  // ---------------------------------------------------------------------------

  /// Checks connectivity to the MediaForge API and verifies API key validity.
  ///
  /// Does not require the SDK to be in an active billing state.
  Future<MediaForgeHealth> checkHealth() async {
    final uri = Uri.parse('$baseUrl/v1/developer/health');
    try {
      final response =
          await _httpClient.get(uri, headers: _headers).timeout(timeout);

      if (response.statusCode == 200 || response.statusCode == 401) {
        try {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          return MediaForgeHealth.fromJson(data);
        } catch (parseError) {
          if (response.statusCode == 200) {
            throw NetworkException(
              'Health endpoint returned invalid JSON: $parseError',
              code: 'health_parse_error',
            );
          }
          // For 401 with unparseable body, fall through to error handler
        }
      }

      _handleErrorResponse(response);
    } on TimeoutException {
      throw NetworkException.timeout(uri.toString());
    } on MediaForgeException {
      rethrow;
    } catch (e) {
      throw NetworkException(
        'Failed to connect to MediaForge Developer API at $uri: $e',
        code: 'health_connection_failed',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // 2. Direct Cloud Metadata Stripping Stream (POST /v1/developer/strip)
  // ---------------------------------------------------------------------------

  /// Sends media [bytes] to be stripped server-side on MediaForge cloud.
  ///
  /// Immediately streams back the clean binary bytes without storing the file on CDN.
  /// Available across all plans (Spark, Forge, Forge+).
  Future<Uint8List> stripCloud(
    Uint8List bytes, {
    String? filename,
  }) async {
    final uri = Uri.parse('$baseUrl/v1/developer/strip');
    final actualFilename = filename ?? _inferFilename(bytes, defaultName: 'media');

    try {
      final request = http.MultipartRequest('POST', uri);
      request.headers.addAll(_headers);

      final mimeType = MimeType.fromBytes(bytes) ?? 'application/octet-stream';
      final multipartFile = http.MultipartFile.fromBytes(
        'file',
        bytes,
        filename: actualFilename,
        contentType: MediaType.parse(mimeType),
      );
      request.files.add(multipartFile);

      final streamedResponse =
          await _httpClient.send(request).timeout(timeout);
      final response =
          await http.Response.fromStream(streamedResponse).timeout(timeout);

      if (response.statusCode == 200) {
        return response.bodyBytes;
      }

      _handleErrorResponse(response);
    } on TimeoutException {
      throw NetworkException.timeout(uri.toString());
    } on MediaForgeException {
      rethrow;
    } catch (e) {
      throw NetworkException(
        'Failed to execute cloud strip request: $e',
        code: 'strip_failed',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // 3. Direct CDN Upload (POST /v1/developer/upload)
  // ---------------------------------------------------------------------------

  /// Strips metadata and uploads the sanitized media directly to Cloudflare R2 CDN.
  ///
  /// Requires a paid plan (Forge or Forge+).
  ///
  /// Parameters:
  /// - [bytes]: Raw image or video bytes to process and upload
  /// - [filename]: Desired filename (with extension, e.g. 'avatar.png')
  /// - [folder]: Optional folder path on CDN
  /// - [onProgress]: Optional callback invoked with upload progress (0.0 to 1.0)
  ///
  /// Returns a [MediaForgeFile] containing the public edge CDN URL and file details.
  Future<MediaForgeFile> uploadToCdn(
    Uint8List bytes, {
    String? filename,
    String? folder,
    ProgressCallback? onProgress,
  }) async {
    final uri = Uri.parse('$baseUrl/v1/developer/upload');
    final actualFilename = filename ?? _inferFilename(bytes, defaultName: 'upload');
    final mimeType = MimeType.fromBytes(bytes) ?? 'application/octet-stream';

    try {
      final request = http.MultipartRequest('POST', uri);
      request.headers.addAll(_headers);

      final multipartFile = http.MultipartFile.fromBytes(
        'file',
        bytes,
        filename: actualFilename,
        contentType: MediaType.parse(mimeType),
      );
      request.files.add(multipartFile);

      if (folder != null && folder.isNotEmpty) {
        request.fields['folder'] = folder;
      }

      http.StreamedResponse streamedResponse;
      if (onProgress != null) {
        final trackedRequest = _TrackedMultipartRequest(request, onProgress);
        streamedResponse =
            await _httpClient.send(trackedRequest).timeout(timeout);
      } else {
        streamedResponse = await _httpClient.send(request).timeout(timeout);
      }

      final response =
          await http.Response.fromStream(streamedResponse).timeout(timeout);

      if (response.statusCode == 201 || response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final fileMap = (data['file'] is Map<String, dynamic>)
            ? data['file'] as Map<String, dynamic>
            : data;
        return MediaForgeFile.fromJson(fileMap);
      }

      _handleErrorResponse(response);
    } on TimeoutException {
      throw NetworkException.timeout(uri.toString());
    } on MediaForgeException {
      rethrow;
    } catch (e) {
      throw NetworkException(
        'Failed to upload file to MediaForge CDN: $e',
        code: 'upload_failed',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // 4. Quota & Usage Telemetry (GET /v1/developer/usage)
  // ---------------------------------------------------------------------------

  /// Retrieves real-time operations, storage, and bandwidth quota usage.
  Future<MediaForgeUsage> getUsage() async {
    final uri = Uri.parse('$baseUrl/v1/developer/usage');
    try {
      final response =
          await _httpClient.get(uri, headers: _headers).timeout(timeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return MediaForgeUsage.fromJson(data);
      }

      _handleErrorResponse(response);
    } on TimeoutException {
      throw NetworkException.timeout(uri.toString());
    } on MediaForgeException {
      rethrow;
    } catch (e) {
      throw NetworkException(
        'Failed to retrieve developer usage metrics: $e',
        code: 'usage_failed',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // 5. Remote Asset Management
  // ---------------------------------------------------------------------------

  /// Fetches a paginated list of uploaded files.
  ///
  /// Parameters:
  /// - [page]: 1-based page number (defaults to 1)
  /// - [limit]: Number of items per page (1 to 100, defaults to 20)
  /// - [cursor]: Optional timestamp cursor for cursor-based pagination
  Future<FileListResult> listFiles({
    int page = 1,
    int limit = 20,
    String? cursor,
  }) async {
    final queryParams = <String, String>{
      'limit': limit.toString(),
    };
    if (cursor != null && cursor.isNotEmpty) {
      queryParams['cursor'] = cursor;
    } else {
      queryParams['page'] = page.toString();
    }

    final uri = Uri.parse('$baseUrl/v1/developer/files').replace(
      queryParameters: queryParams,
    );

    try {
      final response =
          await _httpClient.get(uri, headers: _headers).timeout(timeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return FileListResult.fromJson(data);
      }

      _handleErrorResponse(response);
    } on TimeoutException {
      throw NetworkException.timeout(uri.toString());
    } on MediaForgeException {
      rethrow;
    } catch (e) {
      throw NetworkException(
        'Failed to list developer files: $e',
        code: 'list_files_failed',
      );
    }
  }

  /// Retrieves metadata and CDN URL for a specific file by its [fileId].
  Future<MediaForgeFile> getFile(String fileId) async {
    final uri = Uri.parse('$baseUrl/v1/developer/files/$fileId');
    try {
      final response =
          await _httpClient.get(uri, headers: _headers).timeout(timeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final fileMap = (data['file'] is Map<String, dynamic>)
            ? data['file'] as Map<String, dynamic>
            : data;
        return MediaForgeFile.fromJson(fileMap);
      }

      _handleErrorResponse(response);
    } on TimeoutException {
      throw NetworkException.timeout(uri.toString());
    } on MediaForgeException {
      rethrow;
    } catch (e) {
      throw NetworkException(
        'Failed to retrieve file $fileId: $e',
        code: 'get_file_failed',
      );
    }
  }

  /// Deletes a file from Cloudflare R2 CDN and releases storage quota.
  Future<void> deleteFile(String fileId) async {
    final uri = Uri.parse('$baseUrl/v1/developer/files/$fileId');
    try {
      final response =
          await _httpClient.delete(uri, headers: _headers).timeout(timeout);

      if (response.statusCode == 200 || response.statusCode == 204) {
        return;
      }

      _handleErrorResponse(response);
    } on TimeoutException {
      throw NetworkException.timeout(uri.toString());
    } on MediaForgeException {
      rethrow;
    } catch (e) {
      throw NetworkException(
        'Failed to delete file $fileId: $e',
        code: 'delete_file_failed',
      );
    }
  }

  /// Closes the HTTP client if owned by this instance.
  void close() {
    if (_ownsClient) {
      _httpClient.close();
    }
  }

  // ---------------------------------------------------------------------------
  // Internal Helpers & Error Handling
  // ---------------------------------------------------------------------------

  static String _inferFilename(Uint8List bytes, {required String defaultName}) {
    final mime = MimeType.fromBytes(bytes);
    final ext = switch (mime) {
      'image/jpeg' => '.jpg',
      'image/png' => '.png',
      'image/webp' => '.webp',
      'video/mp4' => '.mp4',
      'video/quicktime' => '.mov',
      _ => '',
    };
    return '$defaultName$ext';
  }

  Never _handleErrorResponse(http.Response response) {
    String message = 'Unexpected error occurred';
    String? apiCode;
    try {
      final data = jsonDecode(response.body);
      if (data is Map) {
        if (data['error'] != null) {
          message = data['error'].toString();
        } else if (data['message'] != null) {
          message = data['message'].toString();
        }
        if (data['code'] != null) {
          apiCode = data['code'].toString();
        }
      }
    } catch (_) {
      if (response.body.isNotEmpty) {
        message = response.body;
      }
    }

    final code = response.statusCode;
    if (code == 401) {
      throw AuthException(message, code: 'unauthorized');
    }
    if (code == 403) {
      if (apiCode == 'bandwidth_exceeded') {
        throw PlanLimitException(
          message,
          limitName: 'bandwidth',
          code: 'bandwidth_exceeded',
        );
      }
      throw PlanLimitException(
        message,
        limitName: 'plan_feature',
        code: 'forbidden',
      );
    }
    if (code == 413) {
      throw PlanLimitException(
        message,
        limitName: 'file_size',
        code: 'file_size_exceeded',
      );
    }
    if (code == 415) {
      throw ProcessingException.unsupportedFormat(message);
    }
    if (code == 429) {
      if (apiCode == 'quota_exceeded') {
        throw PlanLimitException(
          message,
          limitName: 'operations',
          code: 'quota_exceeded',
        );
      }
      throw NetworkException.fromStatusCode(429, body: message);
    }
    if (code >= 500 && code < 600) {
      throw NetworkException.serverError(code, message);
    }

    throw MediaForgeException(message, code: 'http_$code');
  }
}

/// Helper wrapper that wraps an [http.MultipartRequest] to track byte progress.
class _TrackedMultipartRequest extends http.BaseRequest {
  final http.MultipartRequest _original;
  final ProgressCallback _onProgress;

  _TrackedMultipartRequest(this._original, this._onProgress)
      : super(_original.method, _original.url);

  @override
  int get contentLength => _original.contentLength;

  @override
  http.ByteStream finalize() {
    // Finalize original first so Content-Type with boundary is generated
    final stream = _original.finalize();
    // Copy headers AFTER finalize so the boundary-bearing Content-Type is included
    headers.addAll(_original.headers);
    super.finalize();
    final totalLength = contentLength;

    if (totalLength <= 0) {
      return stream;
    }

    var sent = 0;
    final controller = StreamController<List<int>>(sync: true);

    stream.listen(
      (chunk) {
        sent += chunk.length;
        _onProgress((sent / totalLength).clamp(0.0, 1.0).toDouble());
        controller.add(chunk);
      },
      onDone: () {
        _onProgress(1.0);
        controller.close();
      },
      onError: (Object error, StackTrace stackTrace) {
        controller.addError(error, stackTrace);
      },
      cancelOnError: true,
    );

    return http.ByteStream(controller.stream);
  }
}
