import 'package:flutter/foundation.dart';

/// Bytes and number of clips kept in the library.
@immutable
class StorageUsage {
  const StorageUsage({required this.bytes, required this.clips});

  final int bytes;
  final int clips;
}
