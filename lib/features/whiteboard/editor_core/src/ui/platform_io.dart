/// Platform-adaptive file I/O utilities.
///
/// On native platforms (iOS, Android, macOS, Windows, Linux), uses dart:io.
/// On web, uses blob downloads via `package:web`.
library;

export 'platform_io_stub.dart' if (dart.library.io) 'platform_io_native.dart';
