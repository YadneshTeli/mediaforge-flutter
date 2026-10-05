/// Model representing a file uploaded to and managed by MediaForge.
///
/// Returned by [MediaForge.upload], [MediaForgeClient.uploadToCdn],
/// [MediaForgeClient.getFile], and [MediaForgeClient.listFiles].
class MediaForgeFile {
  /// Unique UUID identifier of the file in MediaForge.
  final String id;

  /// Stored filename.
  final String filename;

  /// Original filename prior to upload, if available.
  final String? originalFilename;

  /// Edge CDN URL where the file can be retrieved globally.
  final String cdnUrl;

  /// Size of the stripped file in bytes.
  final int sizeBytes;

  /// MIME type (e.g. 'image/jpeg', 'image/png', 'image/webp', 'video/mp4').
  final String mimeType;

  /// File extension format (e.g. 'jpg', 'png', 'webp', 'mp4', 'mov').
  final String format;

  /// Pixel width of image, or `null` for video / non-image media.
  final int? width;

  /// Pixel height of image, or `null` for video / non-image media.
  final int? height;

  /// Whether metadata (EXIF, GPS, device info) was confirmed stripped.
  final bool metadataStripped;

  /// Whether public edge CDN serving is enabled.
  final bool cdnServingEnabled;

  /// When the file was uploaded and registered.
  final DateTime createdAt;

  /// When the file record was last updated, if available.
  final DateTime? updatedAt;

  /// Creates a new [MediaForgeFile].
  const MediaForgeFile({
    required this.id,
    required this.filename,
    this.originalFilename,
    required this.cdnUrl,
    required this.sizeBytes,
    required this.mimeType,
    required this.format,
    this.width,
    this.height,
    required this.metadataStripped,
    this.cdnServingEnabled = true,
    required this.createdAt,
    this.updatedAt,
  });

  /// Deserializes a [MediaForgeFile] from backend JSON.
  /// Supports both camelCase and snake_case keys for interoperability.
  factory MediaForgeFile.fromJson(Map<String, dynamic> json) {
    final rawCreatedAt = json['createdAt'] ?? json['created_at'];
    final rawUpdatedAt = json['updatedAt'] ?? json['updated_at'];

    return MediaForgeFile(
      id: (json['id'] ?? json['file_id'] ?? json['fileId']) as String,
      filename: (json['filename'] ?? '') as String,
      originalFilename: (json['originalFilename'] ?? json['original_filename']) as String?,
      cdnUrl: (json['cdnUrl'] ?? json['cdn_url'] ?? '') as String,
      sizeBytes: ((json['sizeBytes'] ?? json['size_bytes']) as num?)?.toInt() ?? 0,
      mimeType: (json['mimeType'] ?? json['mime_type'] ?? '') as String,
      format: (json['format'] ?? '') as String,
      width: (json['width'] as num?)?.toInt(),
      height: (json['height'] as num?)?.toInt(),
      metadataStripped: (json['metadataStripped'] ?? json['metadata_stripped'] ?? true) as bool,
      cdnServingEnabled: (json['cdnServingEnabled'] ?? json['cdn_serving_enabled'] ?? true) as bool,
      createdAt: rawCreatedAt != null
          ? DateTime.parse(rawCreatedAt as String)
          : DateTime.now().toUtc(),
      updatedAt: rawUpdatedAt != null ? DateTime.parse(rawUpdatedAt as String) : null,
    );
  }

  /// Serializes to a JSON map.
  Map<String, dynamic> toJson() => {
        'id': id,
        'filename': filename,
        if (originalFilename != null) 'originalFilename': originalFilename,
        'cdnUrl': cdnUrl,
        'sizeBytes': sizeBytes,
        'mimeType': mimeType,
        'format': format,
        if (width != null) 'width': width,
        if (height != null) 'height': height,
        'metadataStripped': metadataStripped,
        'cdnServingEnabled': cdnServingEnabled,
        'createdAt': createdAt.toIso8601String(),
        if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
      };

  /// Aspect ratio (width / height), or null if dimensions are unavailable.
  double? get aspectRatio =>
      (width != null && height != null && height! > 0) ? width! / height! : null;

  /// Markdown image embed snippet.
  String get markdownEmbed => '![$filename]($cdnUrl)';

  /// HTML image tag snippet.
  String get htmlEmbed => '<img src="$cdnUrl" alt="$filename" />';

  @override
  String toString() =>
      'MediaForgeFile(id: $id, filename: $filename, cdnUrl: $cdnUrl, sizeBytes: $sizeBytes, format: $format)';
}
