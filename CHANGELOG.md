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
