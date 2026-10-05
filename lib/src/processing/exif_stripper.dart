import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../exceptions/processing_exception.dart';
import '../models/image_format.dart';
import '../utils/mime_type.dart';
import 'exif_reader.dart';

/// Strips EXIF/XMP/IPTC metadata from image bytes.
///
/// Supports two modes:
/// - **Strip all**: Removes all metadata fields
/// - **Selective strip**: Removes only specific categories (e.g., GPS only)
///
/// After stripping, use [verify] to confirm no metadata remains —
/// this post-strip verification is a unique MediaForge feature
/// that no other Flutter package offers.
///
/// ## Example
/// ```dart
/// final stripper = ExifStripper();
///
/// // Strip all metadata
/// final cleanBytes = await stripper.stripAll(imageBytes);
///
/// // Verify stripping worked
/// final isClean = await stripper.verify(cleanBytes);
/// print('Clean: $isClean'); // true
///
/// // Selective strip — GPS only, keep camera info
/// final gpsStripped = await stripper.stripSelective(
///   imageBytes,
///   stripGps: true,
///   stripCamera: false,
///   stripTimestamps: false,
/// );
/// ```
class ExifStripper {
  final ExifReader _reader;

  /// Creates a new [ExifStripper].
  const ExifStripper({ExifReader reader = const ExifReader()}) : _reader = reader;

  /// Strips ALL metadata from the image [bytes].
  ///
  /// For WebP images, strips metadata at the RIFF container chunk level
  /// without re-encoding pixels, preserving authentic, lossless WebP output.
  /// For JPEG and PNG, decodes and re-encodes clean image bytes.
  ///
  /// Returns clean image bytes with no EXIF/XMP/IPTC data.
  ///
  /// Throws [ProcessingException] if the image cannot be decoded.
  Future<Uint8List> stripAll(Uint8List bytes) async {
    // Fast lossless RIFF chunk stripping for WebP
    if (MimeType.fromBytes(bytes) == 'image/webp') {
      try {
        return _stripWebpChunks(bytes);
      } catch (_) {
        // Fallback to decode/re-encode if chunk parsing fails
      }
    }

    try {
      final image = img.decodeImage(bytes);
      if (image == null) {
        throw const ProcessingException.corruptFile();
      }

      // Clear all EXIF data from the decoded image
      image.exif = img.ExifData();

      // Re-encode in original format (without metadata)
      return _reEncode(image, bytes);
    } on ProcessingException {
      rethrow;
    } catch (e) {
      throw ProcessingException(
        'Failed to strip metadata: $e',
        code: 'strip_error',
      );
    }
  }

  /// Strips metadata selectively from the image [bytes].
  ///
  /// Enable specific categories to remove:
  /// - [stripGps]: Remove GPS location data
  /// - [stripCamera]: Remove camera make/model/serial
  /// - [stripTimestamps]: Remove date/time information
  /// - [stripSoftware]: Remove software/firmware info
  /// - [stripAuthor]: Remove artist/copyright info
  ///
  /// If all flags are `true`, this is equivalent to [stripAll].
  Future<Uint8List> stripSelective(
    Uint8List bytes, {
    bool stripGps = true,
    bool stripCamera = false,
    bool stripTimestamps = false,
    bool stripSoftware = false,
    bool stripAuthor = false,
  }) async {
    // If stripping everything, use the faster stripAll path
    if (stripGps && stripCamera && stripTimestamps && stripSoftware && stripAuthor) {
      return stripAll(bytes);
    }

    // WebP metadata exists in container chunks (EXIF/XMP) which don't support
    // tag-level selective filtering. If any stripping is requested, all metadata
    // is removed; if no flags are set, return the original bytes unchanged.
    if (MimeType.fromBytes(bytes) == 'image/webp') {
      if (!stripGps && !stripCamera && !stripTimestamps && !stripSoftware && !stripAuthor) {
        return bytes;
      }
      return _stripWebpChunks(bytes);
    }

    try {
      final image = img.decodeImage(bytes);
      if (image == null) {
        throw const ProcessingException.corruptFile();
      }

      // Filter EXIF directories and tags selectively
      _filterExifSelective(
        image.exif,
        stripGps: stripGps,
        stripCamera: stripCamera,
        stripTimestamps: stripTimestamps,
        stripSoftware: stripSoftware,
        stripAuthor: stripAuthor,
      );

      return _reEncode(image, bytes);
    } on ProcessingException {
      rethrow;
    } catch (e) {
      throw ProcessingException(
        'Failed to strip metadata selectively: $e',
        code: 'selective_strip_error',
      );
    }
  }

  /// Selectively removes tags from [exif] based on category flags.
  static void _filterExifSelective(
    img.ExifData exif, {
    required bool stripGps,
    required bool stripCamera,
    required bool stripTimestamps,
    required bool stripSoftware,
    required bool stripAuthor,
  }) {
    // 1. GPS location data
    if (stripGps) {
      // Clear GPS IFD directory (sub-IFD)
      exif.directories.remove('GPS');
      exif.directories.remove('gps');
      // Remove GPS pointer tag (0x8825 = 34853) from image IFD
      exif.imageIfd.data.remove(0x8825);
    }

    // 2. Camera hardware tags
    if (stripCamera) {
      const cameraTags = [
        0x010f, // Make
        0x0110, // Model
        0xa431, // SerialNumber
        0xa433, // LensMake
        0xa434, // LensModel
        0xa435, // LensSerialNumber
        0xa420, // ImageUniqueID
      ];
      for (final tag in cameraTags) {
        exif.imageIfd.data.remove(tag);
        exif.exifIfd.data.remove(tag);
      }
    }

    // 3. Timestamps
    if (stripTimestamps) {
      const timestampTags = [
        0x0132, // DateTime
        0x9003, // DateTimeOriginal
        0x9004, // DateTimeDigitized
        0x9010, // OffsetTime
        0x9011, // OffsetTimeOriginal
        0x9012, // OffsetTimeDigitized
        0x9290, // SubSecTime
        0x9291, // SubSecTimeOriginal
        0x9292, // SubSecTimeDigitized
      ];
      for (final tag in timestampTags) {
        exif.imageIfd.data.remove(tag);
        exif.exifIfd.data.remove(tag);
      }
    }

    // 4. Software
    if (stripSoftware) {
      const softwareTags = [
        0x0131, // Software
        0x000b, // ProcessingSoftware
        0x013c, // HostComputer
      ];
      for (final tag in softwareTags) {
        exif.imageIfd.data.remove(tag);
        exif.exifIfd.data.remove(tag);
      }
    }

    // 5. Author / Copyright
    if (stripAuthor) {
      const authorTags = [
        0x013b, // Artist
        0x8298, // Copyright
        0x010e, // ImageDescription
      ];
      for (final tag in authorTags) {
        exif.imageIfd.data.remove(tag);
        exif.exifIfd.data.remove(tag);
      }
    }
  }

  /// Strips EXIF and XMP metadata chunks directly from a WebP RIFF stream.
  static Uint8List _stripWebpChunks(Uint8List bytes) {
    if (MimeType.fromBytes(bytes) != 'image/webp') {
      return bytes;
    }

    final out = BytesBuilder();
    // Placeholder for 12-byte RIFF header (will write updated header at end)
    out.add(Uint8List(12));

    var offset = 12;
    var strippedAny = false;

    while (offset + 8 <= bytes.length) {
      final fourCc = String.fromCharCodes(bytes.sublist(offset, offset + 4));
      final chunkSize = bytes[offset + 4] |
          (bytes[offset + 5] << 8) |
          (bytes[offset + 6] << 16) |
          (bytes[offset + 7] << 24);

      // WebP chunks are padded to even length
      final pad = (chunkSize % 2 != 0) ? 1 : 0;
      final totalChunkLength = 8 + chunkSize + pad;

      if (offset + totalChunkLength > bytes.length) {
        // Truncated chunk; copy remaining bytes and break
        out.add(bytes.sublist(offset));
        break;
      }

      final fourCcUpper = fourCc.toUpperCase();
      if (fourCcUpper == 'EXIF' || fourCcUpper == 'XMP ') {
        // Discard metadata chunk
        strippedAny = true;
      } else if (fourCc == 'VP8X' && totalChunkLength >= 18) {
        // Extended WebP header: clear EXIF (bit 3 = 0x08) and XMP (bit 2 = 0x04) in flags byte
        final chunkData = Uint8List.fromList(bytes.sublist(offset, offset + totalChunkLength));
        // Flag byte is at offset 8 within VP8X chunk data
        chunkData[8] = chunkData[8] & ~(0x08 | 0x04);
        out.add(chunkData);
      } else {
        out.add(bytes.sublist(offset, offset + totalChunkLength));
      }

      offset += totalChunkLength;
    }

    if (!strippedAny) {
      return bytes; // No EXIF or XMP chunks found, return original
    }

    final result = out.toBytes();
    final newRiffLength = result.length - 8;

    // Write valid RIFF header
    result[0] = 0x52; // 'R'
    result[1] = 0x49; // 'I'
    result[2] = 0x46; // 'F'
    result[3] = 0x46; // 'F'
    result[4] = newRiffLength & 0xFF;
    result[5] = (newRiffLength >> 8) & 0xFF;
    result[6] = (newRiffLength >> 16) & 0xFF;
    result[7] = (newRiffLength >> 24) & 0xFF;
    result[8] = 0x57; // 'W'
    result[9] = 0x45; // 'E'
    result[10] = 0x42; // 'B'
    result[11] = 0x50; // 'P'

    return result;
  }

  /// Verifies that the given [bytes] contain NO metadata.
  ///
  /// Returns `true` if the image is clean (0 metadata fields).
  /// Returns `false` if any metadata fields are still present.
  Future<bool> verify(Uint8List bytes) async {
    try {
      final metadata = await _reader.read(bytes);
      return metadata.isEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Strips metadata and verifies the result in one call.
  Future<StrippingResult> stripAndVerify(Uint8List bytes) async {
    final cleanBytes = await stripAll(bytes);
    final isClean = await verify(cleanBytes);
    final originalMetadata = await _reader.read(bytes);

    return StrippingResult(
      cleanBytes: cleanBytes,
      isVerified: isClean,
      fieldsRemoved: originalMetadata.fieldCount,
    );
  }

  /// Re-encodes an image in its detected original format.
  Uint8List _reEncode(img.Image image, Uint8List originalBytes) {
    final format = MimeType.formatFromBytes(originalBytes);

    final encoded = switch (format) {
      ImageFormat.png => img.encodePng(image),
      ImageFormat.webp => img.encodePng(image), // fallback if decoded
      ImageFormat.jpeg || _ => img.encodeJpg(image, quality: 95),
    };

    return Uint8List.fromList(encoded);
  }
}

/// Result of a strip-and-verify operation.
class StrippingResult {
  /// The clean image bytes with metadata removed.
  final Uint8List cleanBytes;

  /// Whether the post-strip verification passed (0 fields remaining).
  final bool isVerified;

  /// The number of metadata fields that were removed.
  final int fieldsRemoved;

  /// Creates a new [StrippingResult].
  const StrippingResult({
    required this.cleanBytes,
    required this.isVerified,
    required this.fieldsRemoved,
  });

  @override
  String toString() => 'StrippingResult('
      'verified: $isVerified, '
      'fieldsRemoved: $fieldsRemoved, '
      'size: ${cleanBytes.length} bytes)';
}
