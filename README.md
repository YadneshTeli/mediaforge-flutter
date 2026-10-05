# mediaforge_flutter

[![pub package](https://img.shields.io/pub/v/mediaforge_flutter.svg)](https://pub.dev/packages/mediaforge_flutter)
[![pub points](https://img.shields.io/pub/points/mediaforge_flutter?color=2E8B57)](https://pub.dev/packages/mediaforge_flutter/score)
[![license](https://img.shields.io/badge/license-Apache_2.0-blue.svg)](LICENSE)

Privacy-first media processing and CDN upload for Flutter and Dart.

Strip EXIF metadata on-device or in cloud, compress, resize, convert formats — then upload to MediaForge CDN. **Your server never sees the raw file.**

## Why MediaForge?

| Feature | mediaforge_flutter | flutter_image_compress | cloudinary_flutter |
|---|---|---|---|
| EXIF metadata reading | Yes (typed, categorized) | No | No |
| Metadata stripping | Yes (with verification) | Side-effect only | No |
| Selective stripping | Yes (GPS only, etc.) | No | No |
| Post-strip verification | Yes (unique) | No | No |
| Compress / resize | Yes | Yes | No (server-side) |
| Format conversion | Yes (JPEG/PNG) | Yes | No (server-side) |
| CDN upload | Yes (Cloudflare R2 edge) | No | Yes (raw file!) |
| Cloud strip streaming | Yes (/v1/developer/strip) | No | No |
| Video support | Yes (MP4, MOV on Forge) | No | Yes |
| Server sees raw file? | **Never** | N/A | **Always** |
| Pure Dart (no native) | Yes | No | Yes |
| Works on Web | Yes | Limited | Yes |

## Installation

```yaml
dependencies:
  mediaforge_flutter: ^0.2.1
```

Or run:

```bash
dart pub add mediaforge_flutter
```

## Quick Start — Local Processing (No API key needed)

Local on-device processing requires zero setup and works offline.

### Read Metadata

```dart
import 'package:mediaforge_flutter/mediaforge_flutter.dart';

final metadata = await MediaForge.readMetadata(imageBytes);

if (metadata.hasLocation) {
  print('GPS: ${metadata.gpsLatitude}, ${metadata.gpsLongitude}');
  print('Maps: ${metadata.googleMapsUrl}');
}

if (metadata.hasDeviceInfo) {
  print('Camera: ${metadata.cameraMake} ${metadata.cameraModel}');
  print('Serial: ${metadata.serialNumber}');
}

print('Total fields: ${metadata.fieldCount}');
print('Has sensitive data: ${metadata.hasSensitiveData}');
```

### Strip Metadata On-Device

```dart
// Strip ALL metadata locally
final cleanBytes = await MediaForge.stripMetadata(imageBytes);

// Verify stripping worked (unique to MediaForge)
final isClean = await MediaForge.verifyClean(cleanBytes);
print('Clean: $isClean'); // true

// Strip and verify in one call
final result = await MediaForge.stripAndVerify(imageBytes);
print('Removed ${result.fieldsRemoved} fields');
print('Verified: ${result.isVerified}');
```

### Strip GPS Only

```dart
// Remove location data, keep camera info and timestamps
final safe = await MediaForge.stripGps(imageBytes);
```

### Process Images

```dart
// Using ProcessingOptions
final processed = await MediaForge.process(imageBytes, ProcessingOptions(
  stripMetadata: true,
  outputFormat: ImageFormat.jpeg,
  quality: 85,
  resizeWidth: 800,
  resizeHeight: 600,
  resizeMode: ResizeMode.fit,
));
```

> **Format notes:** the on-device engine encodes JPEG and PNG output. WebP is
> fully supported as *input* — metadata stripping on WebP is lossless (RIFF
> container chunk removal, no re-encode) — but pure-Dart WebP *encoding* is not
> available. For WebP output, use cloud processing.

### Processing Pipeline (Chainable)

```dart
final result = await MediaForge.pipeline(imageBytes)
  .stripMetadata()
  .resize(width: 800, height: 600, mode: ResizeMode.fit)
  .compress(quality: 85)
  .convert(format: ImageFormat.jpeg)
  .execute();

print('Output: ${result.sizeBytes} bytes');
print('Savings: ${result.savingsDisplay}'); // e.g., "-42%"
print('Dimensions: ${result.width}x${result.height}');

// Use the processed bytes
final processedBytes = result.bytes;
```

---

## Developer Cloud APIs & CDN Upload (v0.2.0+)

Cloud capabilities require an API key (`mf_live_...` or `mf_test_...`) from your [MediaForge Dashboard](https://mediaforge.tech/dashboard/keys).

### 1. Initialize the SDK

```dart
MediaForge.init(apiKey: 'mf_live_xxxx');
```

### 2. Verify Health & Key Connectivity

```dart
final health = await MediaForge.checkHealth();
print('Status: ${health.status}');           // 'ok'
print('Authenticated: ${health.authenticated}');
print('Plan: ${health.apiKey?.plan}');       // 'forge' or 'forge+'
```

### 3. Direct CDN Edge Upload

Upload clean media directly to Cloudflare R2 edge storage with real-time byte progress:

```dart
final uploaded = await MediaForge.upload(
  cleanBytes,
  filename: 'profile.jpg',
  onProgress: (progress) {
    print('Upload: ${(progress * 100).toStringAsFixed(1)}%');
  },
);

print('Public CDN URL: ${uploaded.cdnUrl}');
print('File ID: ${uploaded.fileId}');
```

### 4. Process and Upload in One Call

```dart
final result = await MediaForge.processAndUpload(
  rawBytes,
  options: const ProcessingOptions(
    stripMetadata: true,
    resizeWidth: 1080,
    outputFormat: ImageFormat.jpeg,
  ),
  filename: 'banner.jpg',
  onProgress: (p) => print('${(p * 100).round()}%'),
);
print('CDN URL: ${result.cdnUrl}');
```

### 5. Server-Side Strip Stream (Cloud Offloading)

Offload stripping to the server without storing the file on the CDN:

```dart
final cleanStream = await MediaForge.stripCloud(largeImageBytes);
```

### 6. Check Real-Time Account Quotas

```dart
final usage = await MediaForge.getUsage();
print('Plan: ${usage.plan}');
print('Operations: ${usage.operationsUsed} / ${usage.operationsLimit}');
print('Storage: ${usage.storageUsedBytes} / ${usage.storageLimitBytes} bytes');
print('CDN Upload Allowed: ${usage.cdnUploadAllowed}');
print('Video Allowed: ${usage.allowVideo}');
```

### 7. Remote Asset Management

```dart
// List uploaded files (paginated)
final fileList = await MediaForge.listFiles(page: 1, limit: 20);
for (final file in fileList.files) {
  print('${file.filename} -> ${file.cdnUrl}');
}

// Delete an asset from CDN storage
await MediaForge.deleteFile(fileList.files.first.id);
```

---

## Direct Client Instance

If you prefer dependency injection or multiple accounts/keys, use `MediaForgeClient` directly:

```dart
final client = MediaForgeClient(
  apiKey: 'mf_live_custom_key',
  baseUrl: 'https://api.mediaforge.tech',
);

final health = await client.checkHealth();
final usage = await client.getUsage();
final file = await client.uploadToCdn(bytes, filename: 'hero.png');

client.close();
```

---

## Error Handling

All errors extend `MediaForgeException` for typed, predictable handling:

```dart
try {
  final uploaded = await MediaForge.upload(bytes);
} on AuthException catch (e) {
  print('Authentication failed: ${e.message}');
} on PlanLimitException catch (e) {
  print('Plan limit reached: ${e.message} (${e.limitName})');
} on ProcessingException catch (e) {
  print('Processing failed: ${e.message}');
} on NetworkException catch (e) {
  print('Network issue: ${e.message} (Status: ${e.statusCode})');
} on MediaForgeException catch (e) {
  print('MediaForge error: ${e.message}');
}
```

Exception types:
- `ProcessingException` — corrupt file, unsupported format, too large
- `AuthException` — missing, invalid, or revoked API key
- `PlanLimitException` — storage or monthly operation limit exceeded
- `NetworkException` — connectivity, timeout, HTTP 429 rate limit, 5xx server errors

## Privacy Architecture

```
User's Device                          MediaForge Server
--------------                         ----------------
[Raw Image + EXIF]
       |
  MediaForge SDK
  (runs locally)
       |
  Strip metadata
  Compress / resize
  Convert format
       |
[Clean Image ONLY] ---- upload ----> [Stores processed file on R2]
                                      [Returns public CDN URL]

The server NEVER receives:
  - GPS coordinates
  - Camera serial numbers
  - Original timestamps
  - Author information
  - Any raw/unprocessed data
```

## Platform Support

| Platform | Status |
|---|---|
| Android | Supported |
| iOS | Supported |
| macOS | Supported |
| Windows | Supported |
| Linux | Supported |
| Web | Supported |

Pure Dart — no platform-specific native code required.

## API Reference

See the full [API documentation](https://pub.dev/documentation/mediaforge_flutter/latest/).

## License

Apache License 2.0. See [LICENSE](LICENSE) for details.

## Links

- [Website](https://mediaforge.tech)
- [Documentation](https://mediaforge.tech/docs/)
- [GitHub](https://github.com/YadneshTeli/mediaforge-flutter)
- [Support](mailto:support@mediaforge.tech)
- [pub.dev](https://pub.dev/packages/mediaforge_flutter)
