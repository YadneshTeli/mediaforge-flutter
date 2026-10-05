/// MediaForge Flutter SDK
///
/// Privacy-first media processing and CDN upload.
/// Strip EXIF metadata on-device or via cloud, compress, resize, convert —
/// then upload to MediaForge CDN. Your server never sees the raw file.
///
/// ## Quick Start
///
/// ```dart
/// import 'package:mediaforge_flutter/mediaforge_flutter.dart';
///
/// // Read metadata from an image
/// final metadata = await MediaForge.readMetadata(imageBytes);
/// print('GPS: ${metadata.gpsLatitude}, ${metadata.gpsLongitude}');
///
/// // Strip all metadata and verify
/// final cleanBytes = await MediaForge.stripMetadata(imageBytes);
/// final isClean = await MediaForge.verifyClean(cleanBytes);
/// print('Clean: $isClean'); // true
///
/// // Process with pipeline
/// final result = await MediaForge.pipeline(imageBytes)
///   .stripMetadata()
///   .resize(width: 800, height: 600)
///   .compress(quality: 85)
///   .convert(format: ImageFormat.jpeg)
///   .execute();
/// ```
///
/// ## CDN Upload & Cloud APIs (requires API key)
///
/// ```dart
/// MediaForge.init(apiKey: 'mf_live_xxxx');
/// final uploaded = await MediaForge.upload(cleanBytes, filename: 'hero.jpg');
/// print('CDN URL: ${uploaded.cdnUrl}');
///
/// final usage = await MediaForge.getUsage();
/// print('Remaining Ops: ${usage.operationsLimit - usage.operationsUsed}');
/// ```
library;

// Client & Configuration
export 'src/client/mediaforge_client.dart';
export 'src/config.dart';

// Exceptions
export 'src/exceptions/auth_exception.dart';
export 'src/exceptions/mediaforge_exception.dart';
export 'src/exceptions/network_exception.dart';
export 'src/exceptions/plan_limit_exception.dart';
export 'src/exceptions/processing_exception.dart';

// Main entry point
export 'src/mediaforge.dart';

// Models
export 'src/models/exif_data.dart';
export 'src/models/file_list_result.dart';
export 'src/models/image_format.dart';
export 'src/models/mediaforge_file.dart';
export 'src/models/mediaforge_health.dart';
export 'src/models/mediaforge_usage.dart';
export 'src/models/processing_options.dart';
export 'src/models/resize_mode.dart';
export 'src/models/upload_result.dart';

// Processing
export 'src/processing/exif_reader.dart';
export 'src/processing/exif_stripper.dart';
export 'src/processing/image_processor.dart';
export 'src/processing/processing_pipeline.dart';

// Upload
export 'src/upload/upload_progress.dart';
export 'src/upload/uploader.dart';

// Utilities
export 'src/utils/byte_utils.dart';
export 'src/utils/mime_type.dart';
