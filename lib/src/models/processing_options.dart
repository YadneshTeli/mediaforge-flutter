import 'image_format.dart';
import 'resize_mode.dart';

/// Options for image processing operations.
///
/// Configure which operations to apply and their parameters.
/// All operations are optional — only enabled operations are executed.
///
/// ## Example
/// ```dart
/// final options = ProcessingOptions(
///   stripMetadata: true,
///   outputFormat: ImageFormat.jpeg,
///   quality: 85,
///   resizeWidth: 800,
///   resizeHeight: 600,
///   resizeMode: ResizeMode.fit,
/// );
///
/// final result = await MediaForge.process(imageBytes, options);
/// ```
class ProcessingOptions {
  /// Whether to strip all EXIF/XMP/IPTC metadata.
  ///
  /// Defaults to `true` (strip by default — privacy-first).
  final bool stripMetadata;

  /// Whether to strip only GPS location data (selective strip).
  ///
  /// If [stripMetadata] is `true`, this is ignored (all metadata is stripped).
  /// If [stripMetadata] is `false` and this is `true`, only GPS data is removed.
  final bool stripGpsOnly;

  /// Output image format.
  ///
  /// If `null`, the original format is preserved.
  final ImageFormat? outputFormat;

  /// Compression quality (1-100).
  ///
  /// Only applies to lossy formats (JPEG).
  /// Higher values = better quality, larger file size.
  /// Defaults to 85.
  final int quality;

  /// Whether to use lossless compression.
  ///
  /// PNG output is always lossless; for JPEG this forces quality 100.
  /// Ignored for WebP (not encodable on-device).
  final bool lossless;

  /// Target width in pixels for resize.
  ///
  /// If `null`, the image is not resized horizontally.
  final int? resizeWidth;

  /// Target height in pixels for resize.
  ///
  /// If `null`, the image is not resized vertically.
  final int? resizeHeight;

  /// Resize mode — how to fit the image into target dimensions.
  ///
  /// Defaults to [ResizeMode.fit].
  final ResizeMode resizeMode;

  /// Whether to maintain the original aspect ratio when resizing.
  ///
  /// Defaults to `true`.
  final bool maintainAspectRatio;

  /// Creates processing options.
  const ProcessingOptions({
    this.stripMetadata = true,
    this.stripGpsOnly = false,
    this.outputFormat,
    this.quality = 85,
    this.lossless = false,
    this.resizeWidth,
    this.resizeHeight,
    this.resizeMode = ResizeMode.fit,
    this.maintainAspectRatio = true,
  }) : assert(quality >= 1 && quality <= 100, 'Quality must be between 1 and 100');

  /// Factory preset for maximum privacy and high quality.
  const ProcessingOptions.privacyFirst({
    int quality = 90,
  }) : this(
          stripMetadata: true,
          quality: quality,
        );

  /// Factory preset for web delivery — strips metadata, caps width, and
  /// compresses to JPEG.
  ///
  /// Note: the on-device engine cannot encode WebP (pure Dart limitation).
  /// Use [ImageFormat.png] manually if lossless output is required.
  const ProcessingOptions.webOptimized({
    int maxWidth = 1600,
    int quality = 80,
  }) : this(
          stripMetadata: true,
          outputFormat: ImageFormat.jpeg,
          quality: quality,
          resizeWidth: maxWidth,
          resizeMode: ResizeMode.fit,
        );

  /// Factory preset for thumbnail generation.
  const ProcessingOptions.thumbnail({
    int size = 150,
    int quality = 80,
  }) : this(
          stripMetadata: true,
          resizeWidth: size,
          resizeHeight: size,
          resizeMode: ResizeMode.cover,
          quality: quality,
        );

  /// Factory preset for profile avatar images — square crop to [size]px JPEG.
  const ProcessingOptions.avatar({
    int size = 200,
    int quality = 85,
  }) : this(
          stripMetadata: true,
          outputFormat: ImageFormat.jpeg,
          resizeWidth: size,
          resizeHeight: size,
          resizeMode: ResizeMode.cover,
          quality: quality,
        );

  /// Whether any resize operation is configured.
  bool get hasResize => resizeWidth != null || resizeHeight != null;

  /// Whether a format conversion is configured.
  bool get hasFormatConversion => outputFormat != null;

  static const Object _sentinel = Object();

  /// Creates a copy of this with overridden values.
  ///
  /// Passing `null` explicitly for nullable fields ([outputFormat], [resizeWidth],
  /// [resizeHeight]) clears them.
  ProcessingOptions copyWith({
    bool? stripMetadata,
    bool? stripGpsOnly,
    Object? outputFormat = _sentinel,
    int? quality,
    bool? lossless,
    Object? resizeWidth = _sentinel,
    Object? resizeHeight = _sentinel,
    ResizeMode? resizeMode,
    bool? maintainAspectRatio,
  }) {
    return ProcessingOptions(
      stripMetadata: stripMetadata ?? this.stripMetadata,
      stripGpsOnly: stripGpsOnly ?? this.stripGpsOnly,
      outputFormat: identical(outputFormat, _sentinel)
          ? this.outputFormat
          : outputFormat as ImageFormat?,
      quality: quality ?? this.quality,
      lossless: lossless ?? this.lossless,
      resizeWidth: identical(resizeWidth, _sentinel)
          ? this.resizeWidth
          : resizeWidth as int?,
      resizeHeight: identical(resizeHeight, _sentinel)
          ? this.resizeHeight
          : resizeHeight as int?,
      resizeMode: resizeMode ?? this.resizeMode,
      maintainAspectRatio: maintainAspectRatio ?? this.maintainAspectRatio,
    );
  }

  @override
  String toString() => 'ProcessingOptions('
      'strip: $stripMetadata, '
      'format: $outputFormat, '
      'quality: $quality, '
      'resize: ${resizeWidth}x$resizeHeight $resizeMode)';
}
