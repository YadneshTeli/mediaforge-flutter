/// Supported image formats.
enum ImageFormat {
  /// JPEG format — lossy compression, widely supported.
  jpeg('image/jpeg', 'jpg'),

  /// WebP format — supported as input (metadata stripping is lossless via RIFF
  /// chunk removal), but the pure-Dart on-device engine cannot *encode* WebP.
  /// Cloud/edge processing supports WebP output.
  webp('image/webp', 'webp'),

  /// PNG format — lossless compression with transparency support.
  png('image/png', 'png');

  /// The MIME type for this format.
  final String mimeType;

  /// The file extension for this format (without dot).
  final String extension;

  const ImageFormat(this.mimeType, this.extension);

  /// Returns the [ImageFormat] matching the given MIME type, or `null`.
  static ImageFormat? fromMimeType(String mimeType) {
    final normalized = mimeType.toLowerCase().trim();
    for (final format in values) {
      if (format.mimeType == normalized) return format;
    }
    // Handle common aliases
    if (normalized == 'image/jpg') return ImageFormat.jpeg;
    return null;
  }

  /// Returns the [ImageFormat] matching the given file extension, or `null`.
  static ImageFormat? fromExtension(String ext) {
    final normalized = ext.toLowerCase().replaceAll('.', '').trim();
    for (final format in values) {
      if (format.extension == normalized) return format;
    }
    if (normalized == 'jpeg') return ImageFormat.jpeg;
    return null;
  }
}
