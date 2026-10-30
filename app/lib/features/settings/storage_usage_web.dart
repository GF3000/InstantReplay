import 'storage_usage.dart';

/// Web keeps clips in memory for the current tab only (D15): nothing to report.
Future<StorageUsage?> savedClipsUsage() async => null;
