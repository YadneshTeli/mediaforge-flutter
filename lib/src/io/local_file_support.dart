/// Local file-based operations without network dependencies.
///
/// On platforms supporting `dart:io`, operations use streaming random access
/// to read metadata and safe temporary files to strip metadata with bounded memory.
/// On web platforms, stub methods throw an [UnsupportedError] asynchronously.
library;

export 'local_file_support_stub.dart'
    if (dart.library.io) 'local_file_support_io.dart';
