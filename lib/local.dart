/// Offline-only, zero-network entry point for MediaForge Flutter SDK.
///
/// Guaranteed to contain zero networking code or HTTP dependencies.
/// Ideal for privacy-focused apps that require strict network auditing.
///
/// ```dart
/// import 'package:mediaforge_flutter/local.dart';
///
/// final clean = await MediaForgeLocal.stripMetadata(imageBytes);
/// ```
library;

// Exceptions (local processing only)
export 'src/exceptions/mediaforge_exception.dart';
export 'src/exceptions/processing_exception.dart';

// File I/O (local operations only)
export 'src/io/local_file_support.dart';

// Main offline entry point
export 'src/mediaforge_local.dart';

// Models
export 'src/models/exif_data.dart';
export 'src/models/image_format.dart';
export 'src/models/processing_options.dart';
export 'src/models/resize_mode.dart';

// Processing
export 'src/processing/exif_reader.dart';
export 'src/processing/exif_stripper.dart';
export 'src/processing/image_processor.dart';
export 'src/processing/processing_pipeline.dart';

// Utilities
export 'src/utils/byte_utils.dart';
export 'src/utils/mime_type.dart';
