import 'dart:async';
import 'dart:typed_data';

import 'io/local_file_support.dart';
import 'models/exif_data.dart';
import 'models/processing_options.dart';
import 'processing/exif_reader.dart';
import 'processing/exif_stripper.dart';
import 'processing/image_processor.dart';
import 'processing/processing_pipeline.dart';

/// Offline-only entry point for MediaForge media processing.
///
/// Guaranteed zero network communication, zero API key requirement,
/// zero HTTP dependencies, and 100% on-device execution.
class MediaForgeLocal {
  static const ExifReader _reader = ExifReader();
  static const ExifStripper _stripper = ExifStripper();
  static const ImageProcessor _processor = ImageProcessor();

  /// Creates a [MediaForgeLocal] instance.
  const MediaForgeLocal();

  /// Reads EXIF metadata from in-memory [bytes].
  static Future<ExifData> readMetadata(Uint8List bytes) => _reader.read(bytes);

  /// Reads EXIF metadata from a `dart:io` `File` via streaming random access.
  ///
  /// Prevents Out-Of-Memory (OOM) crashes on high-resolution camera photos.
  /// Emits [UnsupportedError] asynchronously through the returned Future on web platforms.
  static Future<ExifData> readMetadataFile(dynamic file) =>
      LocalFileSupport.readMetadataFile(file);

  /// Strips all EXIF/XMP/IPTC metadata on-device from [bytes].
  static Future<Uint8List> stripMetadata(Uint8List bytes) =>
      _stripper.stripAll(bytes);

  /// Strips metadata from a `dart:io` `File` on disk.
  ///
  /// Enforces a maximum file size limit (50 MB) and uses safe temp-file writing
  /// to ensure the original source file is preserved intact on write failures.
  /// Emits [UnsupportedError] asynchronously through the returned Future on web platforms.
  static Future<dynamic> stripMetadataFile(
    dynamic file, {
    dynamic destinationFile,
    int? maxFileSizeBytes,
  }) =>
      LocalFileSupport.stripMetadataFile(
        file,
        destinationFile: destinationFile,
        maxFileSizeBytes: maxFileSizeBytes,
      );

  /// Strips only GPS location tags from [bytes].
  static Future<Uint8List> stripGps(Uint8List bytes) =>
      _stripper.stripSelective(bytes, stripGps: true);

  /// Verifies that [bytes] contains 0 metadata tags.
  static Future<bool> verifyClean(Uint8List bytes) => _stripper.verify(bytes);

  /// Strips and verifies metadata in a single step.
  static Future<StrippingResult> stripAndVerify(Uint8List bytes) =>
      _stripper.stripAndVerify(bytes);

  /// Applies image processing operations locally.
  static Future<Uint8List> process(
    Uint8List bytes,
    ProcessingOptions options,
  ) async {
    var current = bytes;

    if (options.stripMetadata) {
      current = await _stripper.stripAll(current);
    } else if (options.stripGpsOnly) {
      current = await _stripper.stripSelective(current, stripGps: true);
    }

    if (options.hasResize) {
      current = await _processor.resize(
        current,
        width: options.resizeWidth,
        height: options.resizeHeight,
        mode: options.resizeMode,
        maintainAspectRatio: options.maintainAspectRatio,
      );
    }

    if (options.hasFormatConversion) {
      current = await _processor.convert(
        current,
        format: options.outputFormat!,
        quality: options.quality,
        lossless: options.lossless,
      );
    } else if (!options.lossless) {
      current = await _processor.compress(
        current,
        quality: options.quality,
      );
    }

    return current;
  }

  /// Creates a chainable processing pipeline.
  static ProcessingPipeline pipeline(Uint8List bytes, {bool? runInIsolate}) =>
      ProcessingPipeline(bytes, runInIsolate: runInIsolate);
}

/// Namespace instance providing local API methods via instance invocation
/// (e.g. `MediaForge.local.readMetadata(...)`).
class MediaForgeLocalNamespace {
  /// Default const constructor.
  const MediaForgeLocalNamespace();

  /// Reads EXIF metadata from in-memory [bytes].
  Future<ExifData> readMetadata(Uint8List bytes) =>
      MediaForgeLocal.readMetadata(bytes);

  /// Reads EXIF metadata from a `dart:io` `File` via streaming random access.
  Future<ExifData> readMetadataFile(dynamic file) =>
      MediaForgeLocal.readMetadataFile(file);

  /// Strips all EXIF/XMP/IPTC metadata on-device from [bytes].
  Future<Uint8List> stripMetadata(Uint8List bytes) =>
      MediaForgeLocal.stripMetadata(bytes);

  /// Strips metadata from a `dart:io` `File` on disk.
  Future<dynamic> stripMetadataFile(
    dynamic file, {
    dynamic destinationFile,
    int? maxFileSizeBytes,
  }) =>
      MediaForgeLocal.stripMetadataFile(
        file,
        destinationFile: destinationFile,
        maxFileSizeBytes: maxFileSizeBytes,
      );

  /// Strips only GPS location tags from [bytes].
  Future<Uint8List> stripGps(Uint8List bytes) =>
      MediaForgeLocal.stripGps(bytes);

  /// Verifies that [bytes] contains 0 metadata tags.
  Future<bool> verifyClean(Uint8List bytes) =>
      MediaForgeLocal.verifyClean(bytes);

  /// Strips and verifies metadata in a single step.
  Future<StrippingResult> stripAndVerify(Uint8List bytes) =>
      MediaForgeLocal.stripAndVerify(bytes);

  /// Applies image processing operations locally.
  Future<Uint8List> process(Uint8List bytes, ProcessingOptions options) =>
      MediaForgeLocal.process(bytes, options);

  /// Creates a chainable processing pipeline.
  ProcessingPipeline pipeline(Uint8List bytes, {bool? runInIsolate}) =>
      MediaForgeLocal.pipeline(bytes, runInIsolate: runInIsolate);
}
