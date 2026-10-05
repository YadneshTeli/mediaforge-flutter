/// Resize mode for image processing.
///
/// Controls how the image is fitted into the target dimensions.
enum ResizeMode {
  /// Scale to fit within the target dimensions, preserving aspect ratio.
  /// The output may be smaller than the target on one axis.
  fit,

  /// Scale to cover the target dimensions, preserving aspect ratio.
  /// The output is cropped to exactly match the target size.
  cover,

  /// Scale to fit within the target dimensions, preserving aspect ratio.
  /// The output is padded to exactly match the target size.
  contain,

  /// Stretch to exactly match the target dimensions.
  /// Aspect ratio is NOT preserved.
  fill,
}
