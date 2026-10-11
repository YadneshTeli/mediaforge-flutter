/// File-based operations with cross-platform support.
///
/// On platforms supporting `dart:io` (Android, iOS, macOS, Windows, Linux),
/// operations use streaming random access and [File.openRead] to prevent OOM
/// issues. On web platforms, stub methods throw an [UnsupportedError].
library;

export 'file_support_stub.dart'
    if (dart.library.io) 'file_support_io.dart';
