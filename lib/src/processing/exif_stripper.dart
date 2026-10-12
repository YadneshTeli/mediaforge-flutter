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
  /// For WebP and JPEG images, strips metadata at the container/segment level
  /// without re-encoding pixels, preserving authentic, 100% lossless output.
  /// For PNG and fallback cases, decodes and re-encodes clean image bytes with
  /// all EXIF and text/XMP chunks removed.
  ///
  /// Returns clean image bytes with no EXIF/XMP/IPTC data.
  ///
  /// Throws [ProcessingException] if the image cannot be decoded.
  Future<Uint8List> stripAll(Uint8List bytes) async {
    final mime = MimeType.fromBytes(bytes);

    // Fast lossless RIFF chunk stripping for WebP
    if (mime == 'image/webp') {
      try {
        return _stripWebpChunks(bytes);
      } catch (_) {
        // Fallback to decode/re-encode if chunk parsing fails
      }
    }

    // Fast lossless segment stripping for JPEG
    if (mime == 'image/jpeg') {
      try {
        return _stripJpegSegments(bytes);
      } catch (_) {
        // Fallback to decode/re-encode if segment parsing fails
      }
    }

    try {
      final image = img.decodeImage(bytes);
      if (image == null) {
        throw const ProcessingException.corruptFile();
      }

      // Clear all EXIF data from the decoded image
      image.exif = img.ExifData();
      // Clear PNG text chunks / XMP blocks (fixes H1)
      image.textData = null;

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
      try {
        return _stripWebpChunks(bytes);
      } catch (e) {
        throw ProcessingException(
          'Failed to strip metadata selectively from WebP: $e',
          code: 'selective_strip_error',
        );
      }
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

      // Filter PNG text chunks selectively if present
      if (image.textData != null) {
        if (stripAuthor) {
          image.textData!.remove('Author');
          image.textData!.remove('Artist');
          image.textData!.remove('Copyright');
          image.textData!.remove('Description');
        }
        if (stripTimestamps) {
          image.textData!.remove('Creation Time');
        }
        if (stripSoftware) {
          image.textData!.remove('Software');
        }
        if (stripGps || stripAuthor || stripCamera || stripTimestamps || stripSoftware) {
          image.textData!.remove('XML:com.adobe.xmp');
          image.textData!.remove('Raw profile type xmp');
          image.textData!.remove('Comment');
        }
      }

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

  /// Losslessly strips JPEG metadata segments (APP1, APP13, COM) directly from the
  /// byte stream without decompressing or re-encoding pixels.
  Uint8List _stripJpegSegments(Uint8List bytes) {
    if (bytes.length < 4 || bytes[0] != 0xFF || bytes[1] != 0xD8) {
      throw const ProcessingException.corruptFile();
    }

    final out = BytesBuilder(copy: false);
    out.add([0xFF, 0xD8]); // SOI

    var offset = 2;
    var strippedAny = false;

    while (offset < bytes.length) {
      if (bytes[offset] != 0xFF) {
        throw const ProcessingException.corruptFile();
      }

      while (offset < bytes.length && bytes[offset] == 0xFF) {
        offset++;
      }
      if (offset >= bytes.length) break;

      final marker = bytes[offset++];

      // Standalone markers: EOI (D9), TEM (01), RST0-7 (D0-D7)
      if (marker == 0xD9) {
        out.add([0xFF, 0xD9]);
        break;
      }
      if ((marker >= 0xD0 && marker <= 0xD7) || marker == 0x01) {
        out.add([0xFF, marker]);
        continue;
      }
      // SOS (Start of Scan): Followed by compressed image data
      if (marker == 0xDA) {
        out.add([0xFF, 0xDA]);
        out.add(bytes.sublist(offset));
        break;
      }

      if (offset + 2 > bytes.length) {
        throw const ProcessingException.corruptFile();
      }
      final length = (bytes[offset] << 8) | bytes[offset + 1];
      if (length < 2 || offset + length > bytes.length) {
        throw const ProcessingException.corruptFile();
      }

      // APP1 (Exif / XMP), APP13 (IPTC / Photoshop), COM (Comment)
      if (marker == 0xE1 || marker == 0xED || marker == 0xFE) {
        strippedAny = true;
        offset += length;
        continue;
      }

      out.add([0xFF, marker]);
      out.add(bytes.sublist(offset, offset + length));
      offset += length;
    }

    return strippedAny ? out.toBytes() : bytes;
  }

  /// Inspects raw image bytes to check for residual metadata headers or chunks.
  ///
  /// Detects:
  /// - JPEG: APP1 (EXIF / XMP), APP13 (IPTC), COM markers
  /// - PNG: `tEXt`, `zTXt`, `iTXt`, `eXIf` chunks
  /// - WebP: `EXIF`, `XMP ` chunks
  static bool hasMetadataHeaders(Uint8List bytes) {
    if (bytes.length < 12) return false;

    // 1. JPEG
    if (bytes[0] == 0xFF && bytes[1] == 0xD8) {
      var offset = 2;
      while (offset + 4 <= bytes.length) {
        if (bytes[offset] != 0xFF) {
          offset++;
          continue;
        }
        while (offset < bytes.length && bytes[offset] == 0xFF) {
          offset++;
        }
        if (offset >= bytes.length) break;

        final marker = bytes[offset++];
        if (marker == 0xD9 || marker == 0xDA) break;
        if ((marker >= 0xD0 && marker <= 0xD7) || marker == 0x01) continue;

        if (offset + 2 > bytes.length) break;
        final length = (bytes[offset] << 8) | bytes[offset + 1];
        if (length < 2 || offset + length > bytes.length) break;

        if (marker == 0xE1 || marker == 0xED || marker == 0xFE) {
          return true;
        }

        offset += length;
      }
      return false;
    }

    // 2. PNG
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47 &&
        bytes[4] == 0x0D &&
        bytes[5] == 0x0A &&
        bytes[6] == 0x1A &&
        bytes[7] == 0x0A) {
      var offset = 8;
      while (offset + 8 <= bytes.length) {
        final length = (bytes[offset] << 24) |
            (bytes[offset + 1] << 16) |
            (bytes[offset + 2] << 8) |
            bytes[offset + 3];
        final type = String.fromCharCodes(bytes.sublist(offset + 4, offset + 8));
        if (type == 'tEXt' || type == 'zTXt' || type == 'iTXt' || type == 'eXIf') {
          return true;
        }
        if (type == 'IEND') break;
        offset += 8 + length + 4;
      }
      return false;
    }

    // 3. WebP
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      var offset = 12;
      while (offset + 8 <= bytes.length) {
        final fourCc = String.fromCharCodes(bytes.sublist(offset, offset + 4));
        if (fourCc == 'EXIF' || fourCc == 'XMP ') {
          return true;
        }
        final chunkLen = bytes[offset + 4] |
            (bytes[offset + 5] << 8) |
            (bytes[offset + 6] << 16) |
            (bytes[offset + 7] << 24);
        final paddedLen = chunkLen + (chunkLen % 2);
        offset += 8 + paddedLen;
      }
      return false;
    }

    return false;
  }

  /// Verifies that the given [bytes] contain NO metadata.
  ///
  /// Returns `true` if the image is clean (0 metadata fields and no residual
  /// metadata headers).
  /// Returns `false` if any metadata fields or chunks are still present.
  Future<bool> verify(Uint8List bytes) async {
    try {
      if (hasMetadataHeaders(bytes)) {
        return false;
      }
      final metadata = await _reader.read(bytes);
      return metadata.isEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Strips metadata and verifies the result in one call.
  ///
  /// Inspects the original file first to prevent losing stripped data
  /// if reading original metadata throws.
  Future<StrippingResult> stripAndVerify(Uint8List bytes) async {
    final originalMetadata = await _reader.read(bytes);
    final cleanBytes = await stripAll(bytes);
    final isClean = await verify(cleanBytes);

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
