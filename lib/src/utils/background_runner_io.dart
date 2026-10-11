import 'dart:async';
import 'dart:isolate';

/// Whether this platform can offload work to a background isolate.
const bool supportsBackgroundIsolates = true;

/// Runs [computation] in a short-lived background isolate.
///
/// If the computation (or something it captures) cannot be sent to another
/// isolate, it falls back to running inline on the current isolate rather
/// than failing the operation.
Future<T> runInBackground<T>(FutureOr<T> Function() computation) async {
  try {
    return await Isolate.run(computation);
  } on ArgumentError catch (e) {
    // Thrown when the closure captures an unsendable object (e.g. a custom
    // processor holding a native resource or a test mock).
    if (_isUnsendableError(e)) {
      return await computation();
    }
    rethrow;
  }
}

bool _isUnsendableError(ArgumentError e) {
  final text = e.toString();
  return text.contains('Illegal argument in isolate message') ||
      text.contains('is unsendable');
}
