import 'mediaforge_exception.dart';

/// Thrown when image processing fails.
///
/// Common causes:
/// - Corrupt or unsupported image file
/// - Image too large for available memory
/// - Unsupported image format
class ProcessingException extends MediaForgeException {
  /// Creates a new [ProcessingException].
  const ProcessingException(super.message, {super.code});

  /// Creates a [ProcessingException] for an unsupported format.
  factory ProcessingException.unsupportedFormat(String format) {
    return ProcessingException(
      'Unsupported image format: $format. '
      'MediaForge supports JPEG, PNG, and WebP.',
      code: 'unsupported_format',
    );
  }

  /// Creates a [ProcessingException] for a corrupt file.
  const ProcessingException.corruptFile()
      : super(
          'Unable to process this file. It may be corrupt or not a valid image.',
          code: 'corrupt_file',
        );

  /// Creates a [ProcessingException] for an image too large for memory.
  const ProcessingException.tooLarge()
      : super(
          'Image is too large to process in available memory. '
          'Try a smaller file or resize first.',
          code: 'too_large',
        );
}
