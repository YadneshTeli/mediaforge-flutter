/// The lifecycle phase of a CDN upload.
///
/// Byte-level progress alone is misleading on mobile: the OS socket buffer
/// can absorb a multi-megabyte payload almost instantly, after which the
/// request may still spend many seconds in flight and in server-side
/// processing. [UploadPhase] lets apps show an honest state for each stage.
enum UploadPhase {
  /// Request bytes are being streamed to the network.
  ///
  /// [UploadProgressEvent.progress] advances from 0.0 to 1.0 during this phase.
  buffering,

  /// All bytes have been handed to the network; awaiting the server response
  /// (edge transfer, metadata sanitization and Cloudflare R2 commit).
  ///
  /// Show an indeterminate indicator (e.g. "Processing…") in this phase.
  edgeProcessing,

  /// The server responded successfully and the CDN URL is available.
  completed,
}

/// A structured upload progress update.
///
/// Delivered to an [UploadProgressCallback] (the `onProgressEvent` parameter
/// of the upload APIs).
///
/// ```dart
/// await MediaForge.upload(
///   bytes,
///   filename: 'photo.jpg',
///   onProgressEvent: (event) {
///     switch (event.phase) {
///       case UploadPhase.buffering:
///         print('Sending ${(event.progress * 100).round()}%');
///       case UploadPhase.edgeProcessing:
///         print('Processing on edge…');
///       case UploadPhase.completed:
///         print('Done');
///     }
///   },
/// );
/// ```
class UploadProgressEvent {
  /// Ratio of request bytes sent so far, from 0.0 to 1.0.
  final double progress;

  /// The current upload phase.
  final UploadPhase phase;

  /// Number of request bytes (multipart body) sent so far.
  final int bytesSent;

  /// Total size of the request body in bytes, or 0 if unknown.
  final int totalBytes;

  /// Creates a new [UploadProgressEvent].
  const UploadProgressEvent({
    required this.progress,
    required this.phase,
    required this.bytesSent,
    required this.totalBytes,
  });

  /// Whether the upload has fully completed on the server.
  bool get isComplete => phase == UploadPhase.completed;

  @override
  String toString() => 'UploadProgressEvent(phase: ${phase.name}, '
      'progress: ${(progress * 100).toStringAsFixed(1)}%, '
      'bytes: $bytesSent/$totalBytes)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UploadProgressEvent &&
          other.progress == progress &&
          other.phase == phase &&
          other.bytesSent == bytesSent &&
          other.totalBytes == totalBytes;

  @override
  int get hashCode => Object.hash(progress, phase, bytesSent, totalBytes);
}

/// Callback receiving structured [UploadProgressEvent]s.
typedef UploadProgressCallback = void Function(UploadProgressEvent event);
