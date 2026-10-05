import 'mediaforge_file.dart';

/// Result of a successful CDN upload.
///
/// Contains the CDN URL, file metadata, and identifiers needed to
/// manage the uploaded file.
///
/// ## Example
/// ```dart
/// final result = await MediaForge.upload(cleanBytes, filename: 'hero.webp');
/// print(result.cdnUrl);    // https://cdn.mediaforge.tech/...
/// print(result.fileId);    // 550e8400-e29b-41d4-a716-446655440000
/// print(result.sizeBytes); // 48320
/// ```
class UploadResult {
  /// Unique file identifier assigned by MediaForge.
  final String fileId;

  /// Public CDN URL for the uploaded file.
  ///
  /// This URL is permanently accessible and served via
  /// Cloudflare CDN edge (<50ms TTFB globally).
  final String cdnUrl;

  /// Stored filename.
  final String filename;

  /// Original filename prior to upload.
  final String? originalFilename;

  /// File size in bytes.
  final int sizeBytes;

  /// MIME type (e.g., "image/jpeg", "image/png", "image/webp", "video/mp4").
  final String mimeType;

  /// File format extension (e.g., "webp", "jpg", "png", "mp4").
  final String format;

  /// Image width in pixels (null for non-image files).
  final int? width;

  /// Image height in pixels (null for non-image files).
  final int? height;

  /// Whether metadata (EXIF/GPS) was confirmed stripped.
  final bool metadataStripped;

  /// Whether edge CDN serving is active.
  final bool cdnServingEnabled;

  /// Timestamp when the file was uploaded.
  final DateTime createdAt;

  /// Creates a new [UploadResult].
  const UploadResult({
    required this.fileId,
    required this.cdnUrl,
    this.filename = '',
    this.originalFilename,
    required this.sizeBytes,
    this.mimeType = '',
    required this.format,
    this.width,
    this.height,
    this.metadataStripped = true,
    this.cdnServingEnabled = true,
    required this.createdAt,
  });

  /// Creates an [UploadResult] from an API JSON response.
  /// Handles both direct file map and wrapped `{"file": { ... }}` responses.
  factory UploadResult.fromJson(Map<String, dynamic> json) {
    final fileMap = json['file'] is Map<String, dynamic>
        ? json['file'] as Map<String, dynamic>
        : json;

    return UploadResult(
      fileId: (fileMap['file_id'] ?? fileMap['fileId'] ?? fileMap['id']) as String,
      cdnUrl: (fileMap['cdn_url'] ?? fileMap['cdnUrl']) as String,
      filename: (fileMap['filename'] ?? '') as String,
      originalFilename: (fileMap['original_filename'] ?? fileMap['originalFilename']) as String?,
      sizeBytes: ((fileMap['size_bytes'] ?? fileMap['sizeBytes']) as num?)?.toInt() ?? 0,
      mimeType: (fileMap['mime_type'] ?? fileMap['mimeType'] ?? '') as String,
      format: (fileMap['format'] ?? '') as String,
      width: (fileMap['width'] as num?)?.toInt(),
      height: (fileMap['height'] as num?)?.toInt(),
      metadataStripped: (fileMap['metadata_stripped'] ?? fileMap['metadataStripped'] ?? true) as bool,
      cdnServingEnabled: (fileMap['cdn_serving_enabled'] ?? fileMap['cdnServingEnabled'] ?? true) as bool,
      createdAt: DateTime.parse(
        (fileMap['created_at'] ?? fileMap['uploadedAt'] ?? fileMap['createdAt']) as String,
      ),
    );
  }

  /// Creates an [UploadResult] wrapping a [MediaForgeFile].
  factory UploadResult.fromMediaForgeFile(MediaForgeFile file) {
    return UploadResult(
      fileId: file.id,
      cdnUrl: file.cdnUrl,
      filename: file.filename,
      originalFilename: file.originalFilename,
      sizeBytes: file.sizeBytes,
      mimeType: file.mimeType,
      format: file.format,
      width: file.width,
      height: file.height,
      metadataStripped: file.metadataStripped,
      cdnServingEnabled: file.cdnServingEnabled,
      createdAt: file.createdAt,
    );
  }

  /// Converts this result into a [MediaForgeFile].
  MediaForgeFile toMediaForgeFile() {
    return MediaForgeFile(
      id: fileId,
      filename: filename,
      originalFilename: originalFilename,
      cdnUrl: cdnUrl,
      sizeBytes: sizeBytes,
      mimeType: mimeType,
      format: format,
      width: width,
      height: height,
      metadataStripped: metadataStripped,
      cdnServingEnabled: cdnServingEnabled,
      createdAt: createdAt,
    );
  }

  /// Converts this result to a JSON-compatible map.
  Map<String, dynamic> toJson() => {
        'file_id': fileId,
        'id': fileId,
        'cdn_url': cdnUrl,
        'cdnUrl': cdnUrl,
        'filename': filename,
        if (originalFilename != null) 'original_filename': originalFilename,
        'size_bytes': sizeBytes,
        'sizeBytes': sizeBytes,
        'mime_type': mimeType,
        'format': format,
        if (width != null) 'width': width,
        if (height != null) 'height': height,
        'metadata_stripped': metadataStripped,
        'cdn_serving_enabled': cdnServingEnabled,
        'created_at': createdAt.toIso8601String(),
      };

  /// Aspect ratio of the image (width / height), or `null` if dimensions are not available.
  double? get aspectRatio =>
      (width != null && height != null && height! > 0) ? width! / height! : null;

  /// HTML embed snippet for this file.
  String get htmlEmbed => '<img src="$cdnUrl" alt="${filename.isNotEmpty ? filename : fileId}" />';

  /// Markdown embed snippet for this file.
  String get markdownEmbed => '![${filename.isNotEmpty ? filename : fileId}]($cdnUrl)';

  /// CSS url() snippet for this file.
  String get cssEmbed => "url('$cdnUrl')";

  @override
  String toString() => 'UploadResult(fileId: $fileId, '
      'cdnUrl: $cdnUrl, '
      'size: $sizeBytes bytes, '
      'format: $format)';
}
