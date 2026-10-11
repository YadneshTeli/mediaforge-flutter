import 'dart:async';

/// Whether this platform can offload work to a background isolate.
const bool supportsBackgroundIsolates = false;

/// Runs [computation] inline (isolates are unavailable on this platform).
Future<T> runInBackground<T>(FutureOr<T> Function() computation) =>
    Future<T>.sync(computation);
