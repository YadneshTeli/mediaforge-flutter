import 'mediaforge_file.dart';

/// Paginated file listing result returned by the MediaForge Developer API.
///
/// Returned by [MediaForge.listFiles] and [MediaForgeClient.listFiles].
class FileListResult {
  /// List of uploaded files on this page.
  final List<MediaForgeFile> files;

  /// Total count of files owned by user, if available (page-based pagination).
  final int? total;

  /// Current page number (page-based pagination).
  final int? page;

  /// Page limit size.
  final int? limit;

  /// Next cursor for cursor-based pagination, if available.
  final String? cursor;

  /// Creates a new [FileListResult].
  const FileListResult({
    required this.files,
    this.total,
    this.page,
    this.limit,
    this.cursor,
  });

  /// Deserializes [FileListResult] from JSON.
  factory FileListResult.fromJson(Map<String, dynamic> json) {
    final rawList = (json['files'] as List<dynamic>?) ?? [];
    final fileItems = rawList
        .map((item) => MediaForgeFile.fromJson(item as Map<String, dynamic>))
        .toList();

    final rawTotal = json['total'] ?? json['totalCount'] ?? json['total_count'];
    final totalCount = (rawTotal as num?)?.toInt();
    final pageNum = (json['page'] as num?)?.toInt();
    final limitNum = (json['limit'] as num?)?.toInt();
    final nextCursor = (json['cursor'] ?? json['nextCursor'] ?? json['next_cursor']) as String?;

    return FileListResult(
      files: fileItems,
      total: totalCount,
      page: pageNum,
      limit: limitNum,
      cursor: nextCursor?.isNotEmpty == true ? nextCursor : null,
    );
  }

  /// Whether there are more files available (using cursor or page count).
  bool get hasMore {
    if (cursor != null) return true;
    if (total != null && page != null && limit != null) {
      return (page! * limit!) < total!;
    }
    return false;
  }

  @override
  String toString() =>
      'FileListResult(count: ${files.length}, total: $total, page: $page, cursor: $cursor)';
}
