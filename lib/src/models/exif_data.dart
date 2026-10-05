/// Typed representation of EXIF/XMP/IPTC metadata extracted from an image.
///
/// Fields are nullable — a `null` value means the field was not present
/// in the image metadata.
///
/// ## Example
/// ```dart
/// final metadata = await MediaForge.readMetadata(imageBytes);
/// if (metadata.hasLocation) {
///   print('GPS: ${metadata.gpsLatitude}, ${metadata.gpsLongitude}');
/// }
/// if (metadata.hasSensitiveData) {
///   print('Warning: this image contains sensitive metadata');
/// }
/// ```
class ExifData {
  // -- Location --
  /// GPS latitude in decimal degrees. Positive = North, Negative = South.
  final double? gpsLatitude;

  /// GPS longitude in decimal degrees. Positive = East, Negative = West.
  final double? gpsLongitude;

  /// GPS altitude in meters above sea level.
  final double? gpsAltitude;

  /// City name extracted from XMP/IPTC, if available.
  final String? city;

  /// Country name extracted from XMP/IPTC, if available.
  final String? country;

  // -- Camera --
  /// Camera manufacturer (e.g., "Apple", "Canon", "Nikon").
  final String? cameraMake;

  /// Camera model (e.g., "iPhone 14 Pro", "EOS R5").
  final String? cameraModel;

  /// Camera or device serial number.
  final String? serialNumber;

  /// Lens model used to capture the image.
  final String? lensModel;

  // -- Timestamps --
  /// Date and time when the original image was taken.
  final DateTime? dateTimeOriginal;

  /// Date and time when the image was digitized/scanned.
  final DateTime? dateTimeDigitized;

  /// Date and time when the file was last modified.
  final DateTime? dateTimeModified;

  // -- Software --
  /// Software used to process or edit the image.
  final String? software;

  /// Firmware version of the capture device.
  final String? firmware;

  // -- Author --
  /// Artist or photographer name.
  final String? artist;

  /// Copyright information.
  final String? copyright;

  /// All raw metadata fields as key-value pairs.
  ///
  /// Includes any fields not captured by the typed properties above.
  final Map<String, dynamic> rawFields;

  /// Creates a new [ExifData] instance.
  const ExifData({
    this.gpsLatitude,
    this.gpsLongitude,
    this.gpsAltitude,
    this.city,
    this.country,
    this.cameraMake,
    this.cameraModel,
    this.serialNumber,
    this.lensModel,
    this.dateTimeOriginal,
    this.dateTimeDigitized,
    this.dateTimeModified,
    this.software,
    this.firmware,
    this.artist,
    this.copyright,
    this.rawFields = const {},
  });

  /// Creates an empty [ExifData] representing a clean image with no metadata.
  const ExifData.empty() : this();

  /// Whether this image contains GPS location data.
  bool get hasLocation => gpsLatitude != null && gpsLongitude != null;

  /// Whether this image contains device identification data
  /// (camera make/model or serial number).
  bool get hasDeviceInfo =>
      cameraMake != null || cameraModel != null || serialNumber != null;

  /// Alias for [hasDeviceInfo].
  bool get hasCameraInfo => hasDeviceInfo;

  /// Whether this image contains any timestamp information.
  bool get hasTimestamps =>
      dateTimeOriginal != null ||
      dateTimeDigitized != null ||
      dateTimeModified != null;

  /// Whether this image contains any potentially sensitive metadata.
  ///
  /// Returns `true` if GPS location, serial number, or author info is present.
  bool get hasSensitiveData =>
      hasLocation || serialNumber != null || artist != null;

  /// Whether this image has any metadata at all.
  bool get isEmpty =>
      !hasLocation &&
      !hasDeviceInfo &&
      city == null &&
      country == null &&
      lensModel == null &&
      gpsAltitude == null &&
      dateTimeOriginal == null &&
      dateTimeDigitized == null &&
      dateTimeModified == null &&
      software == null &&
      firmware == null &&
      artist == null &&
      copyright == null &&
      rawFields.isEmpty;

  /// Whether this image has metadata.
  bool get isNotEmpty => !isEmpty;

  /// The total number of metadata fields found.
  int get fieldCount {
    var count = 0;
    if (gpsLatitude != null) count++;
    if (gpsLongitude != null) count++;
    if (gpsAltitude != null) count++;
    if (city != null) count++;
    if (country != null) count++;
    if (cameraMake != null) count++;
    if (cameraModel != null) count++;
    if (serialNumber != null) count++;
    if (lensModel != null) count++;
    if (dateTimeOriginal != null) count++;
    if (dateTimeDigitized != null) count++;
    if (dateTimeModified != null) count++;
    if (software != null) count++;
    if (firmware != null) count++;
    if (artist != null) count++;
    if (copyright != null) count++;
    count += rawFields.length;
    return count;
  }

  /// Returns a Google Maps URL for the GPS coordinates, or `null`.
  String? get googleMapsUrl {
    if (!hasLocation) return null;
    return 'https://maps.google.com/?q=$gpsLatitude,$gpsLongitude';
  }

  /// Returns a human-readable summary of the metadata.
  Map<String, String> toSummaryMap() {
    final map = <String, String>{};
    if (hasLocation) {
      map['Location'] = '$gpsLatitude, $gpsLongitude';
    }
    if (gpsAltitude != null) map['Altitude'] = '${gpsAltitude}m';
    if (city != null) map['City'] = city!;
    if (country != null) map['Country'] = country!;
    if (cameraMake != null) map['Camera Make'] = cameraMake!;
    if (cameraModel != null) map['Camera Model'] = cameraModel!;
    if (serialNumber != null) map['Serial Number'] = serialNumber!;
    if (lensModel != null) map['Lens'] = lensModel!;
    if (dateTimeOriginal != null) {
      map['Date Taken'] = dateTimeOriginal!.toIso8601String();
    }
    if (dateTimeDigitized != null) {
      map['Date Digitized'] = dateTimeDigitized!.toIso8601String();
    }
    if (software != null) map['Software'] = software!;
    if (firmware != null) map['Firmware'] = firmware!;
    if (artist != null) map['Artist'] = artist!;
    if (copyright != null) map['Copyright'] = copyright!;
    return map;
  }

  /// Converts this metadata into a map representation.
  Map<String, dynamic> toMap() => {
        if (gpsLatitude != null) 'gpsLatitude': gpsLatitude,
        if (gpsLongitude != null) 'gpsLongitude': gpsLongitude,
        if (gpsAltitude != null) 'gpsAltitude': gpsAltitude,
        if (city != null) 'city': city,
        if (country != null) 'country': country,
        if (cameraMake != null) 'cameraMake': cameraMake,
        if (cameraModel != null) 'cameraModel': cameraModel,
        if (serialNumber != null) 'serialNumber': serialNumber,
        if (lensModel != null) 'lensModel': lensModel,
        if (dateTimeOriginal != null)
          'dateTimeOriginal': dateTimeOriginal!.toIso8601String(),
        if (dateTimeDigitized != null)
          'dateTimeDigitized': dateTimeDigitized!.toIso8601String(),
        if (dateTimeModified != null)
          'dateTimeModified': dateTimeModified!.toIso8601String(),
        if (software != null) 'software': software,
        if (firmware != null) 'firmware': firmware,
        if (artist != null) 'artist': artist,
        if (copyright != null) 'copyright': copyright,
        if (rawFields.isNotEmpty) 'rawFields': rawFields,
      };

  @override
  String toString() => 'ExifData(fields: $fieldCount, '
      'hasLocation: $hasLocation, '
      'hasDeviceInfo: $hasDeviceInfo)';
}
