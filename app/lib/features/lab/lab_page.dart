// The harness uses dart:io, shelf and the Android plugin, so web gets a stub.
export 'lab_page_stub.dart' if (dart.library.io) 'lab_page_native.dart';
