import 'dart:typed_data';

import '../models/image_format.dart';
import '../models/resize_mode.dart';
import '../utils/background_runner.dart';
import '../utils/mime_type.dart';
import 'exif_stripper.dart';
import 'image_processor.dart';

/// A chainable pipeline for composing image processing operations.
///
/// Operations are queued and executed in order when [execute] is called.
/// This provides a clean, fluent API for multi-step processing.
///
/// ## Example
/// ```dart
/// final result = await ProcessingPipeline(imageBytes)
///   .stripMetadata()
///   .resize(width: 800, height: 600)
///   .compress(quality: 85)
///   .convert(format: ImageFormat.jpeg)
///   .execute();
///
/// print('Output: ${result.sizeBytes} bytes');
/// final cleanBytes = result.bytes;
/// ```
///
/// ## Background isolates
///
/// Decoding, resizing and re-encoding are CPU-heavy. To keep the UI at 60fps,
/// the pipeline runs in a background isolate when [runInIsolate] is `true`,
/// or automatically when it is `null` (default) and the input is larger than
/// [autoIsolateThresholdBytes]. On the Web, work always runs inline.
///
/// ```dart
/// final result = await MediaForge.pipeline(bytes, runInIsolate: true)
///   .resize(width: 1080)
///   .execute();
/// ```
class ProcessingPipeline {
  /// Inputs larger than this are processed in a background isolate when
  /// `runInIsolate` is left as `null`.
  static const int autoIsolateThresholdBytes = 500 * 1024;

  final Uint8List _inputBytes;
  final List<_PipelineStep> _steps = [];
  final ExifStripper _stripper;
  final ImageProcessor _processor;
  final bool? _runInIsolate;

  /// Creates a new [ProcessingPipeline] with the given input [bytes].
  ///
  /// [runInIsolate]: `true` forces background isolate execution, `false`
  /// forces inline execution, `null` (default) decides automatically based on
  /// input size.
  ProcessingPipeline(
    Uint8List bytes, {
    ExifStripper? stripper,
    ImageProcessor? processor,
    bool? runInIsolate,
  })  : _inputBytes = bytes,
        _stripper = stripper ?? const ExifStripper(),
        _processor = processor ?? const ImageProcessor(),
        _runInIsolate = runInIsolate;

  /// Whether [execute] will offload work to a background isolate.
  bool get willRunInIsolate =>
      supportsBackgroundIsolates &&
      (_runInIsolate ??
          _inputBytes.lengthInBytes > autoIsolateThresholdBytes);

  /// Adds a metadata stripping step to the pipeline.
  ///
  /// This removes all EXIF/XMP/IPTC metadata from the image.
  ProcessingPipeline stripMetadata() {
    _steps.add(_PipelineStep.strip);
    return this;
  }

  /// Adds a selective GPS-only stripping step to the pipeline.
  ProcessingPipeline stripGps() {
    _steps.add(_PipelineStep.stripGps);
    return this;
  }

  /// Adds a resize step to the pipeline.
  ///
  /// At least one of [width] or [height] must be specified.
  ProcessingPipeline resize({
    int? width,
    int? height,
    ResizeMode mode = ResizeMode.fit,
    bool maintainAspectRatio = true,
  }) {
    _steps.add(_PipelineStep.resize(
      width: width,
      height: height,
      mode: mode,
      maintainAspectRatio: maintainAspectRatio,
    ));
    return this;
  }

  /// Adds a compression step to the pipeline.
  ///
  /// [quality] must be between 1 and 100.
  ProcessingPipeline compress({int quality = 85}) {
    _steps.add(_PipelineStep.compress(quality: quality));
    return this;
  }

  /// Adds a format conversion step to the pipeline.
  ///
  /// [quality] applies to lossy formats (JPEG).
  ProcessingPipeline convert({
    required ImageFormat format,
    int quality = 85,
  }) {
    _steps.add(_PipelineStep.convert(format: format, quality: quality));
    return this;
  }

  /// Executes all queued steps in order and returns the result.
  ///
  /// Each step receives the output of the previous step as input.
  /// If no steps were added, returns the original bytes unchanged.
  ///
  /// Runs in a background isolate when [willRunInIsolate] is `true`.
  Future<PipelineResult> execute() {
    // Snapshot into locals so the closure captures only sendable values
    // (never `this`), which is required to cross the isolate boundary.
    final input = _inputBytes;
    final steps = List<_PipelineStep>.unmodifiable(_steps);
    final stripper = _stripper;
    final processor = _processor;

    if (willRunInIsolate) {
      return runInBackground(
        () => _runSteps(input, steps, stripper, processor),
      );
    }
    return _runSteps(input, steps, stripper, processor);
  }


  static Future<PipelineResult> _runSteps(
    Uint8List input,
    List<_PipelineStep> steps,
    ExifStripper stripper,
    ImageProcessor processor,
  ) async {
    final originalSize = input.length;

    var currentBytes = input;
    for (final step in steps) {
      currentBytes = await step.execute(currentBytes, stripper, processor);
    }

    // Get final dimensions
    final dimensions = await processor.getDimensions(currentBytes);

    return PipelineResult(
      bytes: currentBytes,
      sizeBytes: currentBytes.length,
      originalSizeBytes: originalSize,
      width: dimensions.width,
      height: dimensions.height,
    );
  }
}

/// Result of a pipeline execution.
class PipelineResult {
  /// The processed image bytes.
  final Uint8List bytes;

  /// The size of the processed image in bytes.
  final int sizeBytes;

  /// The size of the original image in bytes.
  final int originalSizeBytes;

  /// The width of the processed image in pixels.
  final int width;

  /// The height of the processed image in pixels.
  final int height;

  /// Creates a new [PipelineResult].
  const PipelineResult({
    required this.bytes,
    required this.sizeBytes,
    required this.originalSizeBytes,
    required this.width,
    required this.height,
  });

  /// The size savings as a percentage (0.0 to 1.0).
  ///
  /// Positive values mean the file got smaller.
  /// Negative values mean the file got larger.
  double get savingsPercent {
    if (originalSizeBytes == 0) return 0;
    return 1 - (sizeBytes / originalSizeBytes);
  }

  /// Detected format of the processed image.
  ImageFormat? get format => MimeType.formatFromBytes(bytes);

  /// Human-readable size savings string (e.g., "-42%").
  String get savingsDisplay {
    final percent = (savingsPercent * 100).round();
    if (percent == 0) return '0%';
    return '${percent > 0 ? '-' : '+'}${percent.abs()}%';
  }

  @override
  String toString() => 'PipelineResult('
      'size: $sizeBytes bytes ($savingsDisplay), '
      'dimensions: ${width}x$height)';
}

/// Internal pipeline step representation.
sealed class _PipelineStep {
  Future<Uint8List> execute(
    Uint8List bytes,
    ExifStripper stripper,
    ImageProcessor processor,
  );

  static _PipelineStep get strip => _StripStep();
  static _PipelineStep get stripGps => _StripGpsStep();

  static _PipelineStep resize({
    int? width,
    int? height,
    ResizeMode mode = ResizeMode.fit,
    bool maintainAspectRatio = true,
  }) =>
      _ResizeStep(width, height, mode, maintainAspectRatio);

  static _PipelineStep compress({int quality = 85}) => _CompressStep(quality);

  static _PipelineStep convert({
    required ImageFormat format,
    int quality = 85,
  }) =>
      _ConvertStep(format, quality);
}

class _StripStep extends _PipelineStep {
  @override
  Future<Uint8List> execute(
    Uint8List bytes,
    ExifStripper stripper,
    ImageProcessor processor,
  ) =>
      stripper.stripAll(bytes);
}

class _StripGpsStep extends _PipelineStep {
  @override
  Future<Uint8List> execute(
    Uint8List bytes,
    ExifStripper stripper,
    ImageProcessor processor,
  ) =>
      stripper.stripSelective(bytes, stripGps: true);
}

class _ResizeStep extends _PipelineStep {
  final int? width;
  final int? height;
  final ResizeMode mode;
  final bool maintainAspectRatio;

  _ResizeStep(this.width, this.height, this.mode, this.maintainAspectRatio);

  @override
  Future<Uint8List> execute(
    Uint8List bytes,
    ExifStripper stripper,
    ImageProcessor processor,
  ) =>
      processor.resize(
        bytes,
        width: width,
        height: height,
        mode: mode,
        maintainAspectRatio: maintainAspectRatio,
      );
}

class _CompressStep extends _PipelineStep {
  final int quality;

  _CompressStep(this.quality);

  @override
  Future<Uint8List> execute(
    Uint8List bytes,
    ExifStripper stripper,
    ImageProcessor processor,
  ) =>
      processor.compress(bytes, quality: quality);
}

class _ConvertStep extends _PipelineStep {
  final ImageFormat format;
  final int quality;

  _ConvertStep(this.format, this.quality);

  @override
  Future<Uint8List> execute(
    Uint8List bytes,
    ExifStripper stripper,
    ImageProcessor processor,
  ) =>
      processor.convert(bytes, format: format, quality: quality);
}
