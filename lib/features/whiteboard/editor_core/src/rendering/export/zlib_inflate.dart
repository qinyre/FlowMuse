/// Platform-adaptive zlib inflate.
///
/// On native platforms, uses dart:io's ZLibDecoder.
/// On web, throws UnsupportedError (no dart:io).
library;

export 'zlib_inflate_stub.dart' if (dart.library.io) 'zlib_inflate_native.dart';
