import 'dart:io';
import 'package:mediaforge_flutter/mediaforge_flutter.dart';

/// MediaForge Flutter SDK — Example Usage
///
/// This example demonstrates:
/// 1. Reading EXIF metadata from an image
/// 2. Stripping metadata with verification
/// 3. Processing images (resize, compress, convert)
/// 4. Using the chainable pipeline API
/// 5. Developer Cloud API & CDN Edge Upload (v0.2.0)
void main() async {
  // Load an image file
  final file = File('test_photo.jpg');
  if (!file.existsSync()) {
    print('Place a test_photo.jpg in this directory to run the example.');
    return;
  }
  final imageBytes = await file.readAsBytes();
  print('Loaded image: ${imageBytes.length} bytes');

  // ---- 1. Read Metadata ----
  print('\n--- Reading Metadata ---');
  final metadata = await MediaForge.readMetadata(imageBytes);

  if (metadata.isEmpty) {
    print('No metadata found in this image.');
  } else {
    print('Found ${metadata.fieldCount} metadata fields:');
    final summary = metadata.toSummaryMap();
    for (final entry in summary.entries) {
      print('  ${entry.key}: ${entry.value}');
    }

    if (metadata.hasLocation) {
      print('  Google Maps: ${metadata.googleMapsUrl}');
    }

    if (metadata.hasSensitiveData) {
      print('  WARNING: This image contains sensitive metadata!');
    }
  }

  // ---- 2. Strip Metadata ----
  print('\n--- Stripping Metadata ---');
  final strippingResult = await MediaForge.stripAndVerify(imageBytes);
  print('Removed ${strippingResult.fieldsRemoved} fields');
  print('Verified clean: ${strippingResult.isVerified}');
  print('Clean file size: ${strippingResult.cleanBytes.length} bytes');

  // ---- 3. Process Image ----
  print('\n--- Processing Image ---');
  final processed = await MediaForge.process(
    imageBytes,
    const ProcessingOptions(
      stripMetadata: true,
      outputFormat: ImageFormat.webp,
      quality: 85,
      resizeWidth: 800,
      resizeHeight: 600,
      resizeMode: ResizeMode.fit,
    ),
  );
  print('Processed: ${processed.length} bytes');
  print('Savings: ${((1 - processed.length / imageBytes.length) * 100).round()}%');

  // ---- 4. Pipeline API ----
  print('\n--- Pipeline API ---');
  final pipelineResult = await MediaForge.pipeline(imageBytes)
      .stripMetadata()
      .resize(width: 1200, height: 630, mode: ResizeMode.cover)
      .compress(quality: 80)
      .execute();

  print('Pipeline output: ${pipelineResult.sizeBytes} bytes');
  print('Dimensions: ${pipelineResult.width}x${pipelineResult.height}');
  print('Savings: ${pipelineResult.savingsDisplay}');

  // Save the processed file
  final output = File('processed_output.jpg');
  await output.writeAsBytes(pipelineResult.bytes);
  print('Saved to: ${output.path}');

  // ---- 5. Developer Cloud API & CDN Upload (v0.2.0) ----
  print('\n--- Developer Cloud API & CDN Upload ---');
  final apiKey = Platform.environment['MEDIAFORGE_API_KEY'];
  if (apiKey == null || apiKey.isEmpty) {
    print('Set MEDIAFORGE_API_KEY environment variable to test CDN upload and cloud features.');
    return;
  }

  MediaForge.init(apiKey: apiKey);

  // Connectivity and key validation
  final health = await MediaForge.checkHealth();
  print('Health Status: ${health.status}');
  print('Authenticated: ${health.authenticated}');
  print('Plan: ${health.apiKey?.plan}');

  // Live CDN Upload
  print('Uploading sanitized image to Cloudflare R2 CDN...');
  final uploadResult = await MediaForge.upload(
    pipelineResult.bytes,
    filename: 'example_upload.webp',
    onProgress: (progress) {
      print('Upload Progress: ${(progress * 100).toStringAsFixed(1)}%');
    },
  );
  print('Uploaded to CDN: ${uploadResult.cdnUrl}');
  print('File ID: ${uploadResult.fileId}');

  // Query remaining quotas
  final usage = await MediaForge.getUsage();
  print('Operations Used: ${usage.operationsUsed} / ${usage.operationsLimit}');
  print('Storage Used: ${usage.storageUsedBytes} / ${usage.storageLimitBytes} bytes');
}
