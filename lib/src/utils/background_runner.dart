/// Runs heavy computations off the calling isolate where supported.
///
/// On native platforms (Android, iOS, desktop, Dart VM) this uses
/// `Isolate.run`. On the Web, where isolates are unavailable, the computation
/// runs inline so the SDK stays 100% cross-platform.
library;

export 'background_runner_stub.dart'
    if (dart.library.io) 'background_runner_io.dart';
