## 0.3.0

- **Lossless JPEG & WebP Stripping**: Implemented fast, 100% lossless segment stripping for JPEG (`APP1` EXIF/XMP, `APP13` IPTC, `COM`) and container chunks for WebP without re-encoding pixels, preserving exact image quality with minimal memory usage.
- **Deep Container Verification**: Extended `verifyClean` and `verify` to scan raw byte headers for JPEG APP1/APP13/COM markers, PNG `tEXt`/`iTXt`/`zTXt`/`eXIf` chunks, and WebP chunks, preventing false-positive clean verification when XMP or text chunks remain.
- **Complete PNG Metadata Sanitization**: Ensured `stripAll` and `stripSelective` eliminate PNG text/comment and XMP chunks (`image.textData`), preventing metadata leakage in PNG outputs.
- **Special Character & Percent Sign Path Safety**: Resolved filename sanitization in `LocalFileSupport` to safely handle filenames containing `%`, spaces, and special symbols without double URL-decoding errors.
- **XFile & Duck-Typed File Compatibility**: `readMetadataFile`, `stripMetadataFile`, and `uploadFile` now seamlessly accept `dart:io File` and any object with a `.path` getter (such as Flutter's `XFile`), avoiding runtime `ArgumentError`s.
- **Proportional Fit Scaling**: Corrected `ResizeMode.fit` behavior with `maintainAspectRatio` to scale inside the bounding box without adding letterbox padding.
- **WebP Processing Safety**: Added safe PNG compression fallback for WebP and preserved native WebP format in `process()` when no format conversion is requested.
- **Request-Level Cancellation & Client Lifecycle**: Implemented stream-level cancellation for multipart transfers on timeout without terminating caller-injected shared `http.Client`s. Added client lifecycle management in `MediaForgeClient.close()` to cleanly abort active transfers and reject subsequent requests.
- **Realistic Pre-Flight Ceiling**: Adjusted default `maxUploadBytes` to 10MB to match standard edge proxy ceilings and prevent wasteful uploads.
- **Negative Altitude Support**: Handled `GPS GPSAltitudeRef` in `ExifReader` to accurately report altitudes below sea level as negative values.
- **Edge Error Sanitization**: Sanitized reverse proxy and edge HTML error pages (Nginx 413, 502, 504, WAF 403), preventing raw HTML tags and Cloudflare beacon scripts from leaking into exceptions.
- **Multi-Phase Upload Progress**: Introduced structured progress tracking (`UploadProgressEvent`, `UploadPhase.buffering`, `UploadPhase.edgeProcessing`, `UploadPhase.completed`) with 64KB chunk backpressure. Legacy `onProgress` now only reports `1.0` after server confirms upload.
- **Generous Upload Timeouts**: Increased default upload timeout from 30s to 120s (`uploadTimeout`), distinct from metadata request timeouts, with per-call override support.
- **Pre-Flight Payload Size Validation**: Added client-side payload validation (`maxUploadBytes`, default 10MB) to fail fast with `PlanLimitException` (`client_payload_too_large`) before wasting cellular data and battery.
- **Streaming & File Support (OOM Prevention)**: Added `uploadStreamToCdn`, `uploadStream`, `uploadFile`, `readMetadataFile`, and `stripMetadataFile` using streaming I/O to prevent mobile Out-Of-Memory crashes on high-res camera photos (20MB–50MB).
- **Fluent Pipeline-to-Upload Chaining**: Enabled chaining directly from `MediaForge.pipeline(...)` into `.upload()` in a single statement via `ProcessingPipelineUploadExtension`.
- **Background Isolate Offloading**: Offloaded CPU-heavy pipeline image processing (decode, resize, compress) to background isolates automatically for payloads >500KB or via explicit `runInIsolate: true`.
- **Batch Asset Deletions**: Added parallel batch asset deletion (`MediaForge.deleteFiles` and `MediaForgeClient.deleteFiles`) with concurrency control returning typed `BatchDeleteResult`.
- **Explicit Offline vs. Cloud Namespacing**: Introduced `MediaForge.local` (100% on-device, zero network permissions) and `MediaForge.cloud`, along with a dedicated `package:mediaforge_flutter/local.dart` entry point that exports only `LocalFileSupport` and `MediaForgeLocal` with zero HTTP dependencies or upload APIs.
- **Bounded Memory & Crash-Safe File Stripping**: Enforced a 50MB file size limit (`maxStripFileSizeBytes`) on `stripMetadataFile` throwing `ProcessingException` (`file_too_large`). Added atomic temp file staging with native platform path resolution and verification before replacing source files, preserving originals if writes fail.
- **Async Web Platform Errors**: Made web stubs for `readMetadataFile`, `stripMetadataFile`, and `uploadFile` asynchronous, ensuring `UnsupportedError` is delivered through returned `Future`s for consistent `.catchError(...)` handling.

## 0.2.2

- Added official public GitHub repository link
- Added pub.dev version, points, and license badges to documentation

## 0.2.1

- Added direct `http_parser` dependency for full lower-bound dependency compatibility
- Optimized package description length for pub.dev and search engine discoverability
- Updated documentation URL in `pubspec.yaml`

## 0.2.0

- Integrated with MediaForge Developer REST API (developer-api-key branch)
- Implemented live CDN upload to Cloudflare R2 storage via `MediaForge.upload` and `MediaForgeClient.uploadToCdn`
- Added streaming multipart upload with real-time byte progress reporting (`onProgress`)
- Added server-side metadata stripping stream via `MediaForge.stripCloud` (`POST /v1/developer/strip`)
- Added developer API health check and key validation via `MediaForge.checkHealth` (`GET /v1/developer/health`)
- Added real-time quota telemetry via `MediaForge.getUsage` (`GET /v1/developer/usage`)
- Added remote asset management: `MediaForge.listFiles`, `MediaForge.getFile`, and `MediaForge.deleteFile`
- Added video format detection for MP4 (`video/mp4`) and QuickTime MOV (`video/quicktime`)
- Introduced typed models: `MediaForgeFile`, `MediaForgeUsage`, `MediaForgeHealth`, `FileListResult`
- Enhanced `UploadResult` with dual-format deserialization and full backward compatibility
- Maintained 100% pure Dart cross-platform architecture supporting Flutter Web, iOS, Android, macOS, Windows, Linux

## 0.1.0

- Initial release
- EXIF metadata reading (GPS, camera, timestamps, software, author)
- Metadata stripping with post-strip verification
- Selective metadata removal (GPS only, camera only, etc.)
- Image resize with 4 modes (fit, cover, contain, fill)
- Image compression with quality control (1-100)
- Format conversion (JPEG, WebP, PNG)
- Chainable processing pipeline
- Typed exception hierarchy for error handling
- CDN upload interface defined
- Pure Dart — works on all platforms including Web
