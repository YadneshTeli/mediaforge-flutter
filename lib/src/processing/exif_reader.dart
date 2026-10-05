import 'dart:typed_data';

import 'package:exif/exif.dart' hide ExifData;

import '../exceptions/processing_exception.dart';
import '../models/exif_data.dart';
import '../utils/byte_utils.dart';

/// Reads EXIF, XMP, and IPTC metadata from image bytes.
///
/// Uses the `exif` package to parse metadata fields and returns
/// a typed [ExifData] object with categorized fields.
///
/// ## Example
/// ```dart
/// final reader = ExifReader();
/// final metadata = await reader.read(imageBytes);
/// print('GPS: ${metadata.gpsLatitude}, ${metadata.gpsLongitude}');
/// print('Camera: ${metadata.cameraMake} ${metadata.cameraModel}');
/// ```
class ExifReader {
  /// Creates a new [ExifReader].
  const ExifReader();

  /// Reads all metadata from the given image [bytes].
  ///
  /// Returns an [ExifData] with all found fields populated.
  /// Fields not present in the image will be `null`.
  ///
  /// Throws [ProcessingException] if the image cannot be parsed.
  Future<ExifData> read(Uint8List bytes) async {
    if (!ByteUtils.isValidImage(bytes)) {
      throw const ProcessingException.corruptFile();
    }

    try {
      final tags = await readExifFromBytes(bytes);

      if (tags.isEmpty) {
        return const ExifData.empty();
      }

      return ExifData(
        // Location
        gpsLatitude: _extractGpsCoordinate(tags, 'GPS GPSLatitude',
            refTag: 'GPS GPSLatitudeRef', positiveRef: 'N'),
        gpsLongitude: _extractGpsCoordinate(tags, 'GPS GPSLongitude',
            refTag: 'GPS GPSLongitudeRef', positiveRef: 'E'),
        gpsAltitude: _extractDouble(tags, 'GPS GPSAltitude'),
        // Camera
        cameraMake: _extractString(tags, 'Image Make'),
        cameraModel: _extractString(tags, 'Image Model'),
        serialNumber: _extractString(tags, 'EXIF BodySerialNumber') ??
            _extractString(tags, 'MakerNote SerialNumber'),
        lensModel: _extractString(tags, 'EXIF LensModel'),
        // Timestamps
        dateTimeOriginal:
            _extractDateTime(tags, 'EXIF DateTimeOriginal'),
        dateTimeDigitized:
            _extractDateTime(tags, 'EXIF DateTimeDigitized'),
        dateTimeModified: _extractDateTime(tags, 'Image DateTime'),
        // Software
        software: _extractString(tags, 'Image Software'),
        firmware: _extractString(tags, 'EXIF Firmware') ??
            _extractString(tags, 'MakerNote Firmware'),
        // Author
        artist: _extractString(tags, 'Image Artist'),
        copyright: _extractString(tags, 'Image Copyright'),
        // Raw fields
        rawFields: _buildRawFieldsMap(tags),
      );
    } on ProcessingException {
      rethrow;
    } catch (e) {
      throw ProcessingException(
        'Failed to read image metadata: $e',
        code: 'metadata_read_error',
      );
    }
  }

  /// Checks if the given [bytes] contain any EXIF metadata.
  ///
  /// This is faster than [read] when you only need to know
  /// whether metadata exists, not its contents.
  Future<bool> hasMetadata(Uint8List bytes) async {
    try {
      final tags = await readExifFromBytes(bytes);
      return tags.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  // -- Private helpers --

  String? _extractString(Map<String, IfdTag> tags, String key) {
    final tag = tags[key];
    if (tag == null) return null;
    final value = tag.printable.trim();
    if (value.isEmpty || value == 'None' || value == 'null') return null;
    return value;
  }

  double? _extractDouble(Map<String, IfdTag> tags, String key) {
    final tag = tags[key];
    if (tag == null) return null;
    try {
      final values = tag.values;
      if (values is IfdRatios && values.ratios.isNotEmpty) {
        return values.ratios.first.toDouble();
      }
      return double.tryParse(tag.printable);
    } catch (_) {
      return null;
    }
  }

  double? _extractGpsCoordinate(
    Map<String, IfdTag> tags,
    String key, {
    required String refTag,
    required String positiveRef,
  }) {
    final tag = tags[key];
    if (tag == null) return null;

    try {
      final values = tag.values;
      if (values is! IfdRatios || values.ratios.length < 3) return null;

      final degrees = values.ratios[0].toDouble();
      final minutes = values.ratios[1].toDouble();
      final seconds = values.ratios[2].toDouble();

      var decimal = degrees + (minutes / 60.0) + (seconds / 3600.0);

      final ref = _extractString(tags, refTag);
      if (ref != null && ref != positiveRef) {
        decimal = -decimal;
      }

      return decimal;
    } catch (_) {
      return null;
    }
  }

  DateTime? _extractDateTime(Map<String, IfdTag> tags, String key) {
    final value = _extractString(tags, key);
    if (value == null) return null;

    try {
      final trimmed = value.trim();
      final parts = trimmed.split(' ');
      if (parts.length >= 2) {
        final datePart = parts[0].replaceAll(':', '-');
        final timePart = parts.sublist(1).join(' ');
        return DateTime.tryParse('${datePart}T$timePart') ??
            DateTime.tryParse('$datePart $timePart');
      }
      return DateTime.tryParse(trimmed);
    } catch (_) {
      return null;
    }
  }

  /// Tag keys that are already mapped to typed [ExifData] fields.
  /// These are excluded from [rawFields] to avoid double-counting.
  static const _typedKeys = <String>{
    'GPS GPSLatitude',
    'GPS GPSLatitudeRef',
    'GPS GPSLongitude',
    'GPS GPSLongitudeRef',
    'GPS GPSAltitude',
    'GPS GPSAltitudeRef',
    'Image Make',
    'Image Model',
    'EXIF BodySerialNumber',
    'EXIF LensModel',
    'EXIF DateTimeOriginal',
    'EXIF DateTimeDigitized',
    'Image DateTime',
    'Image Software',
    'EXIF Firmware',
    'MakerNote Firmware',
    'Image Artist',
    'Image Copyright',
  };

  Map<String, dynamic> _buildRawFieldsMap(Map<String, IfdTag> tags) {
    final map = <String, dynamic>{};
    for (final entry in tags.entries) {
      if (_typedKeys.contains(entry.key)) continue;
      final value = entry.value.printable;
      if (value.isNotEmpty && value != 'None' && value != 'null') {
        map[entry.key] = value;
      }
    }
    return map;
  }
}
