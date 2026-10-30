import 'package:flutter/foundation.dart';

import 'storage_usage_io.dart' if (dart.library.js_interop) 'storage_usage_web.dart' as platform;

/// Bytes and number of clip files kept on this device.
@immutable
class StorageUsage {
  const StorageUsage({required this.bytes, required this.clips});

  final int bytes;
  final int clips;
}

/// The one place Settings reads clip storage from. Today it walks the clip directories; the drift
/// library can answer from its `sizeBytes` column instead. Null where it cannot be measured (web).
Future<StorageUsage?> savedClipsUsage() => platform.savedClipsUsage();
