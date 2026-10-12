import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../exceptions/auth_exception.dart';
import '../exceptions/mediaforge_exception.dart';
import '../exceptions/network_exception.dart';
import '../exceptions/plan_limit_exception.dart';
import '../exceptions/processing_exception.dart';
import '../models/batch_delete_result.dart';
import '../models/file_list_result.dart';
import '../models/mediaforge_file.dart';
import '../models/mediaforge_health.dart';
import '../models/mediaforge_usage.dart';
import '../upload/upload_phase.dart';
import '../utils/byte_utils.dart';
import '../utils/mime_type.dart';

/// Progress callback reporting upload completion ratio from 0.0 to 1.0.
///
/// Since 0.3.0 this callback only reports `1.0` once the **server has
/// confirmed** the upload. While the request is in flight, values are capped
/// at [MediaForgeClient.inFlightProgressCeiling] (0.99). Use
/// [UploadProgressCallback] (`onProgressEvent`) for phase-aware progress.
typedef ProgressCallback = void Function(double progress);

/// Client for communicating with the MediaForge Developer REST API.
///
/// Handles authentication, multipart streaming, progress tracking,
/// quota telemetry, and remote asset management.
class MediaForgeClient {
  /// SDK version reported in the `User-Agent` header.
  static const String sdkVersion = '0.3.0';

  /// Default timeout for lightweight requests (health, usage, file listing).
  static const Duration defaultTimeout = Duration(seconds: 30);

  /// Default timeout for heavy multipart requests (upload, cloud strip).
  ///
  /// Covers transfer over slow mobile links plus edge sanitization and the
  /// Cloudflare R2 commit.
  static const Duration defaultUploadTimeout = Duration(seconds: 120);

  /// Default client-side ceiling for upload payloads (10 MB).
  ///
  /// Matches the MediaForge API's edge direct-upload ceiling (10 MB). Lower it via
  /// the `maxUploadBytes` constructor argument to match your plan or reverse
  /// proxy limits, or pass `null` to disable the pre-flight check.
  static const int defaultMaxUploadBytes = 10 * 1024 * 1024;

  /// Maximum value reported to a legacy [ProgressCallback] before the server
  /// confirms the upload.
  static const double inFlightProgressCeiling = 0.99;

  /// Maximum length of a non-JSON error body surfaced in exception messages.
  static const int _maxErrorMessageLength = 300;

  /// The Developer API key (`mf_live_...` or `mf_test_...`).
  final String apiKey;

  /// Root URL of the MediaForge API.
  final String baseUrl;

  /// Timeout for lightweight requests (health, usage, file management).
  final Duration timeout;

  /// Timeout for heavy multipart requests ([uploadToCdn], [uploadStreamToCdn],
  /// [stripCloud]). Can be overridden per call.
  final Duration uploadTimeout;

  /// Client-side maximum payload size in bytes, checked **before** any data
  /// is sent. `null` disables the check.
  final int? maxUploadBytes;

  final http.Client _httpClient;
  final bool _ownsClient;
  bool _isClosed = false;

  /// Whether this client instance has been closed.
  bool get isClosed => _isClosed;

  final Set<http.Client> _activeMultipartClients = {};
  final Set<_CancellableTrackedMultipartRequest> _activeRequests = {};

  /// Creates a [MediaForgeClient].
  ///
  /// Parameters:
  /// - [apiKey]: Developer API key
  /// - [baseUrl]: API base URL (defaults to `https://api.mediaforge.tech`)
  /// - [timeout]: Timeout for lightweight requests (defaults to 30 seconds)
  /// - [uploadTimeout]: Timeout for uploads and cloud strip (defaults to 120 seconds)
  /// - [maxUploadBytes]: Client-side payload ceiling (defaults to 10 MB, `null` disables)
  /// - [httpClient]: Optional custom [http.Client] (useful for testing or proxying)
  MediaForgeClient({
    required this.apiKey,
    String baseUrl = 'https://api.mediaforge.tech',
    this.timeout = defaultTimeout,
    this.uploadTimeout = defaultUploadTimeout,
    this.maxUploadBytes = defaultMaxUploadBytes,
    http.Client? httpClient,
  })  : baseUrl = _normalizeBaseUrl(baseUrl),
        _httpClient = httpClient ?? http.Client(),
        _ownsClient = httpClient == null;

  void _ensureNotClosed() {
    if (_isClosed) {
      throw const NetworkException(
        'MediaForgeClient is closed.',
        code: 'client_closed',
      );
    }
  }

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
        'User-Agent': 'mediaforge-flutter/$sdkVersion',
      };

  // ---------------------------------------------------------------------------
  // 1. Health & Key Verification (GET /v1/developer/health)
  // ---------------------------------------------------------------------------

  /// Checks connectivity to the MediaForge API and verifies API key validity.
  ///
  /// Does not require the SDK to be in an active billing state.
  Future<MediaForgeHealth> checkHealth() async {
    _ensureNotClosed();
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
            throw const NetworkException(
              'Health endpoint returned an invalid (non-JSON) response.',
              statusCode: 200,
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
  ///
  /// [timeout] overrides [uploadTimeout] for this call.
  ///
  /// Throws [PlanLimitException] (code `client_payload_too_large`) before
  /// sending anything if [bytes] exceed [maxUploadBytes].
  Future<Uint8List> stripCloud(
    Uint8List bytes, {
    String? filename,
    Duration? timeout,
  }) async {
    _ensureNotClosed();
    final uri = Uri.parse('$baseUrl/v1/developer/strip');
    _ensureWithinUploadLimit(bytes.lengthInBytes);
    final actualFilename = filename ?? _inferFilename(bytes, defaultName: 'media');

    try {
      final mimeType = MimeType.fromBytes(bytes) ?? 'application/octet-stream';
      final multipartFile = http.MultipartFile.fromBytes(
        'file',
        bytes,
        filename: actualFilename,
        contentType: MediaType.parse(mimeType),
      );

      final response = await _sendMultipart(
        uri: uri,
        file: multipartFile,
        timeout: timeout ?? uploadTimeout,
      );

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
  /// - [onProgress]: Optional callback with progress (0.0 to 1.0). Reaches
  ///   `1.0` only after the server confirms the upload.
  /// - [onProgressEvent]: Optional phase-aware progress callback
  /// - [timeout]: Overrides [uploadTimeout] for this call
  ///
  /// Returns a [MediaForgeFile] containing the public edge CDN URL and file details.
  ///
  /// Throws [PlanLimitException] (code `client_payload_too_large`) before
  /// sending anything if [bytes] exceed [maxUploadBytes].
  Future<MediaForgeFile> uploadToCdn(
    Uint8List bytes, {
    String? filename,
    String? folder,
    ProgressCallback? onProgress,
    UploadProgressCallback? onProgressEvent,
    Duration? timeout,
  }) async {
    _ensureWithinUploadLimit(bytes.lengthInBytes);
    final actualFilename = filename ?? _inferFilename(bytes, defaultName: 'upload');
    final mimeType = MimeType.fromBytes(bytes) ?? 'application/octet-stream';

    return _uploadMultipart(
      () => http.MultipartFile.fromBytes(
        'file',
        bytes,
        filename: actualFilename,
        contentType: MediaType.parse(mimeType),
      ),
      folder: folder,
      onProgress: onProgress,
      onProgressEvent: onProgressEvent,
      timeout: timeout,
    );
  }

  /// Uploads media from a byte [stream] to the CDN without buffering the
  /// whole file in memory.
  ///
  /// Use this for large camera photos and videos to avoid Out-Of-Memory
  /// crashes, e.g. with `File.openRead()` or `XFile.openRead()`:
  ///
  /// ```dart
  /// final file = await picker.pickImage(source: ImageSource.camera);
  /// final uploaded = await client.uploadStreamToCdn(
  ///   file!.openRead(),
  ///   length: await file.length(),
  ///   filename: file.name,
  /// );
  /// ```
  ///
  /// Parameters:
  /// - [stream]: The file content. It is listened to exactly once.
  /// - [length]: Exact number of bytes [stream] will emit (required for multipart).
  /// - [filename]: Filename with extension (used to infer the content type).
  /// - [contentType]: Optional explicit MIME type; inferred from [filename] if omitted.
  /// - [folder], [onProgress], [onProgressEvent], [timeout]: As in [uploadToCdn].
  ///
  /// Throws [PlanLimitException] (code `client_payload_too_large`) before
  /// listening to [stream] if [length] exceeds [maxUploadBytes].
  Future<MediaForgeFile> uploadStreamToCdn(
    Stream<List<int>> stream, {
    required int length,
    required String filename,
    String? contentType,
    String? folder,
    ProgressCallback? onProgress,
    UploadProgressCallback? onProgressEvent,
    Duration? timeout,
  }) async {
    if (length < 0) {
      throw ArgumentError.value(length, 'length', 'must be non-negative');
    }
    _ensureWithinUploadLimit(length);

    final mimeType = contentType ??
        MimeType.fromExtension(_extensionOf(filename)) ??
        'application/octet-stream';

    return _uploadMultipart(
      () => http.MultipartFile(
        'file',
        stream,
        length,
        filename: filename,
        contentType: MediaType.parse(mimeType),
      ),
      folder: folder,
      onProgress: onProgress,
      onProgressEvent: onProgressEvent,
      timeout: timeout,
    );
  }

  Future<MediaForgeFile> _uploadMultipart(
    http.MultipartFile Function() buildFile, {
    String? folder,
    ProgressCallback? onProgress,
    UploadProgressCallback? onProgressEvent,
    Duration? timeout,
  }) async {
    final uri = Uri.parse('$baseUrl/v1/developer/upload');
    final reporter = (onProgress != null || onProgressEvent != null)
        ? _ProgressReporter(onProgress, onProgressEvent)
        : null;

    try {
      final response = await _sendMultipart(
        uri: uri,
        file: buildFile(),
        fields: {
          if (folder != null && folder.isNotEmpty) 'folder': folder,
        },
        timeout: timeout ?? uploadTimeout,
        reporter: reporter,
      );

      if (response.statusCode == 201 || response.statusCode == 200) {
        try {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          final fileMap = (data['file'] is Map<String, dynamic>)
              ? data['file'] as Map<String, dynamic>
              : data;
          final file = MediaForgeFile.fromJson(fileMap);
          reporter?.completed();
          return file;
        } catch (parseError) {
          throw NetworkException(
            'Upload succeeded on server (HTTP ${response.statusCode}), but response body could not be parsed: $parseError',
            statusCode: response.statusCode,
            code: 'upload_parse_error',
          );
        }
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

  /// Sends a multipart POST, applying a single overall [timeout] covering
  /// both the request transfer and reading the response.
  Future<http.Response> _sendMultipart({
    required Uri uri,
    required http.MultipartFile file,
    Map<String, String> fields = const {},
    required Duration timeout,
    _ProgressReporter? reporter,
  }) {
    _ensureNotClosed();

    final request = http.MultipartRequest('POST', uri)
      ..headers.addAll(_headers)
      ..fields.addAll(fields)
      ..files.add(file);

    final cancellable = _CancellableTrackedMultipartRequest(request, reporter);

    final clientToUse = _ownsClient ? http.Client() : _httpClient;
    if (_ownsClient) {
      _activeMultipartClients.add(clientToUse);
    }
    _activeRequests.add(cancellable);

    Future<http.Response> exchange() async {
      try {
        final streamed = await clientToUse.send(cancellable);
        return await http.Response.fromStream(streamed);
      } finally {
        _activeRequests.remove(cancellable);
        if (_ownsClient) {
          _activeMultipartClients.remove(clientToUse);
          clientToUse.close();
        }
      }
    }

    return exchange().timeout(
      timeout,
      onTimeout: () {
        cancellable.cancel(
          TimeoutException('Request timed out after ${timeout.inSeconds}s', timeout),
        );
        if (_ownsClient) {
          clientToUse.close();
        }
        throw TimeoutException('Request timed out after ${timeout.inSeconds}s', timeout);
      },
    );
  }

  // ---------------------------------------------------------------------------
  // 4. Quota & Usage Telemetry (GET /v1/developer/usage)
  // ---------------------------------------------------------------------------

  /// Retrieves real-time operations, storage, and bandwidth quota usage.
  Future<MediaForgeUsage> getUsage() async {
    _ensureNotClosed();
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
    _ensureNotClosed();
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
    _ensureNotClosed();
    final uri = _fileUri(fileId);
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
    _ensureNotClosed();
    final uri = _fileUri(fileId);
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

  /// Deletes multiple files, running up to [concurrency] requests in parallel.
  ///
  /// Duplicate IDs are removed. Each file is deleted independently, so the
  /// returned [BatchDeleteResult] reports which IDs succeeded and which
  /// failed (with the error for each) instead of aborting on the first failure.
  ///
  /// [concurrency] defaults to 4 to stay well within API rate limits.
  ///
  /// ```dart
  /// final result = await client.deleteFiles(['f1', 'f2', 'f3']);
  /// if (result.hasFailures) {
  ///   result.failed.forEach((id, error) => print('$id: ${error.message}'));
  /// }
  /// ```
  Future<BatchDeleteResult> deleteFiles(
    Iterable<String> fileIds, {
    int concurrency = 4,
  }) async {
    _ensureNotClosed();
    if (concurrency < 1) {
      throw ArgumentError.value(concurrency, 'concurrency', 'must be >= 1');
    }

    final ids = fileIds.toSet().toList(growable: false);
    if (ids.isEmpty) {
      return const BatchDeleteResult(deleted: [], failed: {});
    }

    final deletedIds = <String>{};
    final failed = <String, MediaForgeException>{};
    var nextIndex = 0;

    Future<void> worker() async {
      while (nextIndex < ids.length) {
        final id = ids[nextIndex++];
        try {
          await deleteFile(id);
          deletedIds.add(id);
        } on MediaForgeException catch (e) {
          failed[id] = e;
        }
      }
    }

    await Future.wait(
      List.generate(math.min(concurrency, ids.length), (_) => worker()),
    );

    return BatchDeleteResult(
      deleted: List.unmodifiable(ids.where(deletedIds.contains)),
      failed: Map.unmodifiable({
        for (final id in ids)
          if (failed.containsKey(id)) id: failed[id]!,
      }),
    );
  }

  /// Closes the HTTP client if owned by this instance, aborts active multipart
  /// requests, and prevents new exchanges.
  void close() {
    _isClosed = true;
    if (_ownsClient) {
      _httpClient.close();
      for (final client in _activeMultipartClients.toList()) {
        try {
          client.close();
        } catch (_) {}
      }
      _activeMultipartClients.clear();
    }
    for (final req in _activeRequests.toList()) {
      try {
        req.cancel(
          const NetworkException('MediaForgeClient was closed.', code: 'client_closed'),
        );
      } catch (_) {}
    }
    _activeRequests.clear();
  }

  // ---------------------------------------------------------------------------
  // Internal Helpers & Error Handling
  // ---------------------------------------------------------------------------

  Uri _fileUri(String fileId) => Uri.parse(
        '$baseUrl/v1/developer/files/${Uri.encodeComponent(fileId)}',
      );

  /// Throws before any network I/O if [length] exceeds [maxUploadBytes].
  void _ensureWithinUploadLimit(int length) {
    final limit = maxUploadBytes;
    if (limit == null || length <= limit) return;

    throw PlanLimitException(
      'Payload size (${ByteUtils.formatFileSize(length)}) exceeds the maximum '
      'upload size of ${ByteUtils.formatFileSize(limit)}. '
      'Compress or resize the file before uploading.',
      limitName: 'file_size',
      currentUsage: length,
      maxAllowed: limit,
      code: 'client_payload_too_large',
    );
  }

  static String _extensionOf(String filename) {
    final dot = filename.lastIndexOf('.');
    return (dot >= 0 && dot < filename.length - 1) ? filename.substring(dot + 1) : '';
  }

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

  /// Decodes the response body without throwing on malformed encodings.
  static String _safeBody(http.Response response) {
    try {
      return response.body;
    } catch (_) {
      return utf8.decode(response.bodyBytes, allowMalformed: true);
    }
  }

  /// Whether [body] is an HTML/XML page (typically from a reverse proxy such
  /// as Nginx or Cloudflare) rather than a MediaForge JSON error.
  static bool _isMarkupResponse(http.Response response, String body) {
    final contentType = (response.headers['content-type'] ?? '').toLowerCase();
    if (contentType.contains('text/html') ||
        contentType.contains('application/xhtml') ||
        contentType.contains('text/xml')) {
      return true;
    }
    return body.trimLeft().startsWith('<');
  }

  /// A safe, human-readable message for proxy/edge responses whose raw body
  /// must never reach end users (it may contain HTML and injected scripts).
  static String _edgeMessageFor(int statusCode) => switch (statusCode) {
        400 => 'The MediaForge edge rejected the request as malformed (HTTP 400).',
        401 => 'The request was not authorized by the MediaForge edge (HTTP 401).',
        403 => 'The request was blocked by the MediaForge edge network (HTTP 403).',
        404 => 'The requested MediaForge endpoint was not found (HTTP 404).',
        408 => 'The MediaForge edge timed out waiting for the request (HTTP 408).',
        413 => 'Payload exceeds the edge upload limit (HTTP 413). '
            'Compress or resize the file before uploading.',
        429 => 'Too many requests to the MediaForge edge (HTTP 429). '
            'Slow down and try again.',
        500 => 'MediaForge edge gateway encountered an internal error (HTTP 500).',
        502 => 'MediaForge edge gateway is temporarily unavailable (HTTP 502 Bad Gateway).',
        503 => 'MediaForge service is temporarily unavailable (HTTP 503). Try again shortly.',
        504 => 'MediaForge edge gateway timed out processing the payload (HTTP 504).',
        _ => 'MediaForge API returned an unexpected response (HTTP $statusCode).',
      };

  /// Collapses whitespace and truncates plain-text bodies for messages.
  static String _sanitizePlainText(String body) {
    final collapsed = body.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (collapsed.length <= _maxErrorMessageLength) return collapsed;
    return '${collapsed.substring(0, _maxErrorMessageLength)}…';
  }

  Never _handleErrorResponse(http.Response response) {
    final code = response.statusCode;
    final body = _safeBody(response);
    final isEdgeMarkup = _isMarkupResponse(response, body);

    String message = 'Unexpected error occurred (HTTP $code).';
    String? apiCode;

    if (isEdgeMarkup) {
      // Never surface raw proxy HTML (Nginx/Cloudflare pages, beacon scripts).
      message = _edgeMessageFor(code);
    } else if (body.trim().isNotEmpty) {
      try {
        final data = jsonDecode(body);
        if (data is Map) {
          final rawMessage = data['error'] ?? data['message'];
          if (rawMessage != null) {
            message = rawMessage.toString();
          }
          if (data['code'] != null) {
            apiCode = data['code'].toString();
          }
        }
      } catch (_) {
        message = _sanitizePlainText(body);
      }
    }

    if (code == 401) {
      throw AuthException(message, code: 'unauthorized');
    }
    if (code == 403) {
      if (isEdgeMarkup) {
        // An HTML 403 comes from the edge/WAF, not from MediaForge plan checks.
        throw NetworkException(message, statusCode: 403, code: 'edge_forbidden');
      }
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

    throw MediaForgeException(message, code: apiCode ?? 'http_$code');
  }
}

/// Translates raw byte counts into phase-aware progress notifications.
class _ProgressReporter {
  final ProgressCallback? _onProgress;
  final UploadProgressCallback? _onProgressEvent;

  int _totalBytes = 0;
  int _bytesSent = 0;
  double _lastLegacyValue = -1;

  _ProgressReporter(this._onProgress, this._onProgressEvent);

  void start(int totalBytes) {
    _totalBytes = totalBytes > 0 ? totalBytes : 0;
    _bytesSent = 0;
    _emit(UploadPhase.buffering);
  }

  void buffering(int bytesSent) {
    _bytesSent = bytesSent;
    _emit(UploadPhase.buffering);
  }

  void edgeProcessing(int bytesSent) {
    _bytesSent = bytesSent;
    _emit(UploadPhase.edgeProcessing);
  }

  void completed() {
    if (_totalBytes > 0) _bytesSent = _totalBytes;
    _emit(UploadPhase.completed);
  }

  void _emit(UploadPhase phase) {
    final ratio = _totalBytes > 0
        ? (_bytesSent / _totalBytes).clamp(0.0, 1.0).toDouble()
        : (phase == UploadPhase.buffering ? 0.0 : 1.0);

    _onProgressEvent?.call(UploadProgressEvent(
      progress: ratio,
      phase: phase,
      bytesSent: _bytesSent,
      totalBytes: _totalBytes,
    ));

    final legacy = _onProgress;
    if (legacy != null) {
      final value = phase == UploadPhase.completed
          ? 1.0
          : math.min(ratio, MediaForgeClient.inFlightProgressCeiling);
      // Avoid flooding legacy listeners with duplicate values.
      if (value != _lastLegacyValue) {
        _lastLegacyValue = value;
        legacy(value);
      }
    }
  }
}

/// Wraps an [http.MultipartRequest] to report byte-level progress and enable
/// request-level cancellation without closing shared caller HTTP clients.
///
/// The body is re-chunked into [chunkSize] pieces and emitted with backpressure.
/// If cancelled via [cancel], the byte stream terminates immediately with an error,
/// instructing the transport to abort the socket transfer.
class _CancellableTrackedMultipartRequest extends http.BaseRequest {
  /// Size of each emitted body chunk.
  static const int chunkSize = 64 * 1024;

  final http.MultipartRequest _original;
  final _ProgressReporter? _reporter;

  bool _isCancelled = false;

  /// Whether this request has been cancelled.
  bool get isCancelled => _isCancelled;

  StreamSubscription<List<int>>? _sourceSubscription;
  StreamController<List<int>>? _controller;

  _CancellableTrackedMultipartRequest(this._original, [this._reporter])
      : super(_original.method, _original.url);

  @override
  int get contentLength => _original.contentLength;

  /// Cancels the multipart request stream, aborting transport transfer.
  void cancel([Object? error]) {
    if (_isCancelled) return;
    _isCancelled = true;
    final err = error ?? TimeoutException('Request was cancelled');

    try {
      _sourceSubscription?.cancel();
    } catch (_) {}

    final ctrl = _controller;
    if (ctrl != null && !ctrl.isClosed) {
      try {
        ctrl.addError(err);
      } catch (_) {}
      try {
        ctrl.close();
      } catch (_) {}
    }
  }

  @override
  http.ByteStream finalize() {
    // Finalize original first so Content-Type with boundary is generated
    final stream = _original.finalize();
    // Copy headers AFTER finalize so the boundary-bearing Content-Type is included
    headers.addAll(_original.headers);
    super.finalize();

    _reporter?.start(contentLength);

    final controller = StreamController<List<int>>(sync: true);
    _controller = controller;

    if (_isCancelled) {
      controller.addError(
        TimeoutException('Request was cancelled before transmission'),
      );
      controller.close();
      return http.ByteStream(controller.stream);
    }

    var sent = 0;

    controller.onListen = () {
      _sourceSubscription = stream.listen(
        (chunk) {
          if (_isCancelled || controller.isClosed) return;

          if (chunk.length <= chunkSize) {
            controller.add(chunk);
            sent += chunk.length;
            _reporter?.buffering(sent);
            return;
          }

          for (var offset = 0; offset < chunk.length; offset += chunkSize) {
            if (_isCancelled || controller.isClosed) return;
            final end = math.min(offset + chunkSize, chunk.length);
            final slice = chunk is Uint8List
                ? Uint8List.sublistView(chunk, offset, end)
                : chunk.sublist(offset, end);
            controller.add(slice);
            sent += end - offset;
            _reporter?.buffering(sent);
          }
        },
        onError: (Object e, StackTrace st) {
          if (!_isCancelled && !controller.isClosed) {
            controller.addError(e, st);
          }
        },
        onDone: () {
          if (!_isCancelled && !controller.isClosed) {
            _reporter?.edgeProcessing(sent);
            controller.close();
          }
        },
        cancelOnError: true,
      );

      controller.onPause = () {
        try {
          _sourceSubscription?.pause();
        } catch (_) {}
      };
      controller.onResume = () {
        try {
          _sourceSubscription?.resume();
        } catch (_) {}
      };
      controller.onCancel = () {
        try {
          _sourceSubscription?.cancel();
        } catch (_) {}
      };
    };

    return http.ByteStream(controller.stream);
  }
}
