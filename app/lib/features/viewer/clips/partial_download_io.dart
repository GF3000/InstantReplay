import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'partial_download.dart';

PartialDownload createPlatformPartialDownload(String clipId) => FilePartialDownload(() async {
      final dir = await Directory('${(await getTemporaryDirectory()).path}/viewer_clips').create(recursive: true);
      return File('${dir.path}/$clipId.part');
    });

/// Android: the received bytes go to a `.part` file, so a 30 MB clip is never held twice in memory
/// while it downloads.
class FilePartialDownload implements PartialDownload {
  FilePartialDownload(this._resolve);

  final Future<File> Function() _resolve;
  File? _file;
  RandomAccessFile? _out;
  int _length = 0;

  @override
  int get length => _length;

  Future<File> get _path async => _file ??= await _resolve();

  @override
  Future<void> append(List<int> chunk) async {
    // The first write truncates, so a stale file from an earlier run never leaks into this one.
    final out = _out ??= await (await _path).open(mode: _length == 0 ? FileMode.write : FileMode.append);
    await out.writeFrom(chunk);
    _length += chunk.length;
  }

  @override
  Future<Uint8List> read() async {
    await _close();
    if (_length == 0) return Uint8List(0);
    return (await _path).readAsBytes();
  }

  @override
  Future<void> clear() async {
    await _close();
    _length = 0;
  }

  @override
  Future<void> delete() async {
    await clear();
    final file = _file;
    if (file != null && await file.exists()) await file.delete();
  }

  Future<void> _close() async {
    final out = _out;
    _out = null;
    await out?.close();
  }
}
