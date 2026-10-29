// The server uses dart:io, so web gets a stub.
export 'server_platform_stub.dart' if (dart.library.io) 'server_platform_io.dart';
