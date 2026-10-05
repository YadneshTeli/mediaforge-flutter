# MediaForge Flutter SDK — Example

This example demonstrates the core features of `mediaforge_flutter`:

- Reading EXIF/XMP/IPTC metadata from images (GPS coordinates, camera model, timestamps)
- Stripping metadata with post-strip verification
- Image processing (resizing, WebP/JPEG conversion, quality compression)
- Fluent chainable `ProcessingPipeline` API

## Running the Example

1. Ensure dependencies are fetched:
   ```bash
   dart pub get
   ```

2. Place a test photo named `test_photo.jpg` into the `example` directory (or use your own image file).

3. Run the example:
   ```bash
   dart run lib/main.dart
   ```
