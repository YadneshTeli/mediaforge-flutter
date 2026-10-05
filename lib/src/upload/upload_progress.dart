import 'dart:async';

/// Upload progress tracking for CDN uploads.
///
/// Provides both a stream-based API and a callback-based API for monitoring
/// upload progress.
///
/// ## Example
/// ```dart
/// final progress = UploadProgress();
/// progress.stream.listen((value) {
///   print('Upload: ${(value * 100).toStringAsFixed(0)}%');
/// });
/// ```
///
/// CDN upload progress is reported while the SDK performs an upload.
class UploadProgress {
  final StreamController<double> _controller =
      StreamController<double>.broadcast();

  /// Current progress value (0.0 to 1.0).
  double _progress = 0;

  /// Returns the current progress value.
  double get progress => _progress;

  /// Stream of progress updates (0.0 to 1.0).
  Stream<double> get stream => _controller.stream;

  /// Whether the upload is complete.
  bool get isComplete => _progress >= 1.0;

  /// Optional callback invoked when progress changes.
  final void Function(double progress)? onProgress;

  /// Creates a new [UploadProgress].
  UploadProgress({this.onProgress});

  /// Updates the progress value and notifies listeners.
  void update(double value) {
    _progress = value.clamp(0.0, 1.0).toDouble();
    onProgress?.call(_progress);
    if (!_controller.isClosed) {
      _controller.add(_progress);
    }
  }

  /// Marks the upload as complete and closes the stream controller to prevent leaks.
  void complete() {
    update(1.0);
    if (!_controller.isClosed) {
      _controller.close();
    }
  }

  /// Resets progress to 0.
  void reset() => update(0.0);

  /// Disposes resources and closes the stream controller.
  void dispose() {
    if (!_controller.isClosed) {
      _controller.close();
    }
  }
}
