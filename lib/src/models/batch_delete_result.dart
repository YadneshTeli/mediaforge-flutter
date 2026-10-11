import '../exceptions/mediaforge_exception.dart';

/// Outcome of a batch delete via [MediaForgeClient.deleteFiles].
///
/// Batch deletes are not all-or-nothing: each file is deleted independently,
/// so some may succeed while others fail (e.g. already deleted, not found).
class BatchDeleteResult {
  /// IDs of files that were deleted successfully, in request order.
  final List<String> deleted;

  /// IDs of files that failed to delete, mapped to the error raised.
  final Map<String, MediaForgeException> failed;

  /// Creates a new [BatchDeleteResult].
  const BatchDeleteResult({
    required this.deleted,
    required this.failed,
  });

  /// Whether every requested file was deleted.
  bool get allSucceeded => failed.isEmpty;

  /// Whether at least one file failed to delete.
  bool get hasFailures => failed.isNotEmpty;

  /// Total number of file IDs processed.
  int get total => deleted.length + failed.length;

  @override
  String toString() =>
      'BatchDeleteResult(deleted: ${deleted.length}, failed: ${failed.length})';
}
