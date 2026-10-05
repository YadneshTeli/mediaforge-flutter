import 'mediaforge_exception.dart';

/// Thrown when a plan limit is exceeded.
///
/// Common causes:
/// - Storage quota exceeded (e.g., 10MB on Spark, 10GB on Forge, 25GB on Forge+)
/// - Monthly file upload limit reached (10 files on Spark, 2,500 on Forge)
/// - File size exceeds plan maximum (5MB on Spark, 100MB on Forge, 500MB on Forge+)
class PlanLimitException extends MediaForgeException {
  /// The name of the limit that was exceeded.
  final String limitName;

  /// The current usage value.
  final int? currentUsage;

  /// The maximum allowed value.
  final int? maxAllowed;

  /// Creates a new [PlanLimitException].
  const PlanLimitException(
    super.message, {
    required this.limitName,
    this.currentUsage,
    this.maxAllowed,
    super.code,
  });

  /// Creates a [PlanLimitException] for storage quota exceeded.
  factory PlanLimitException.storageExceeded({
    int? currentBytes,
    int? maxBytes,
  }) {
    return PlanLimitException(
      'Storage limit exceeded. '
      'Upgrade your plan at https://mediaforge.tech/upgrade',
      limitName: 'storage',
      currentUsage: currentBytes,
      maxAllowed: maxBytes,
      code: 'storage_exceeded',
    );
  }

  /// Creates a [PlanLimitException] for monthly file limit exceeded.
  factory PlanLimitException.fileCountExceeded({
    int? currentCount,
    int? maxCount,
  }) {
    return PlanLimitException(
      'Monthly file upload limit reached. '
      'Upgrade your plan at https://mediaforge.tech/upgrade',
      limitName: 'file_count',
      currentUsage: currentCount,
      maxAllowed: maxCount,
      code: 'file_count_exceeded',
    );
  }

  /// Creates a [PlanLimitException] for file size exceeded.
  factory PlanLimitException.fileSizeExceeded({
    int? currentBytes,
    int? maxBytes,
  }) {
    return PlanLimitException(
      'File size exceeds plan limit. '
      'Upgrade your plan at https://mediaforge.tech/upgrade',
      limitName: 'file_size',
      currentUsage: currentBytes,
      maxAllowed: maxBytes,
      code: 'file_size_exceeded',
    );
  }
}
