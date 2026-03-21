import 'dart:io';
import 'dart:typed_data';

/// Abstract source that provides random-access read capability.
abstract class RandomAccessSource {
  /// Reads [length] bytes starting at [offset].
  Future<Uint8List> read(int offset, int length);

  /// Returns the total size of the data source in bytes.
  Future<int> get length;

  /// Releases any system resources (file handles, SAF sessions).
  Future<void> close();
}

/// Default implementation of [RandomAccessSource] using [dart:io].
class FileRandomAccessSource implements RandomAccessSource {
  final String path;
  RandomAccessFile? _file;
  int? _cachedLength;

  FileRandomAccessSource(this.path);

  Future<void> _ensureOpen() async {
    if (_file == null) {
      _file = await File(path).open(mode: FileMode.read);
      _cachedLength = await _file!.length();
    }
  }

  @override
  Future<int> get length async {
    await _ensureOpen();
    return _cachedLength!;
  }

  @override
  Future<Uint8List> read(int offset, int length) async {
    await _ensureOpen();
    await _file!.setPosition(offset);
    return await _file!.read(length);
  }

  @override
  Future<void> close() async {
    await _file?.close();
    _file = null;
  }
}
