import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:slob_reader/slob_reader.dart';

/// A simple memory-based implementation of [RandomAccessSource] for testing.
class MemoryRandomAccessSource implements RandomAccessSource {
  final Uint8List _data;

  MemoryRandomAccessSource(this._data);

  @override
  Future<Uint8List> read(int offset, int length) async {
    if (offset >= _data.length) return Uint8List(0);
    final end = (offset + length) > _data.length ? _data.length : (offset + length);
    return _data.sublist(offset, end);
  }

  @override
  Future<int> get length async => _data.length;

  @override
  Future<void> close() async {}
}

void main() {
  group('RandomAccessSource Abstraction', () {
    test('MemoryRandomAccessSource reads data correctly', () async {
      final data = Uint8List.fromList([0, 1, 2, 3, 4, 5, 6, 7, 8, 9]);
      final source = MemoryRandomAccessSource(data);
      
      expect(await source.read(0, 5), equals([0, 1, 2, 3, 4]));
      expect(await source.read(5, 5), equals([5, 6, 7, 8, 9]));
      expect(await source.read(8, 5), equals([8, 9]));
      expect(await source.read(10, 5), equals([]));
    });

    test('SlobReader can open from a custom source', () async {
      final builder = BytesBuilder();
      builder.add(SlobReader.magicBytes);
      builder.add(List.filled(16, 0)); // UUID
      builder.add([5, ...'utf-8'.codeUnits]); // Encoding
      builder.add([0]); // Compression (none)
      builder.add([0]); // TagCount
      builder.add([0]); // ContentTypeCount
      builder.add([0, 0, 0, 0]); // BlobCount
      
      // We will calculate offsets after building
      final headerSize = 8 + 16 + 6 + 1 + 1 + 1 + 4 + 8 + 8;
      final storeOffset = headerSize + 4; // After refs count (0 refs)
      
      // StoreOffset (8 bytes, big-endian)
      final storeOffsetBytes = ByteData(8)..setUint64(0, storeOffset);
      builder.add(storeOffsetBytes.buffer.asUint8List());
      
      builder.add([0, 0, 0, 0, 0, 0, 0, 100]); // Size (8 bytes)
      
      builder.add([0, 0, 0, 0]); // Refs count (0) pointing at current pos (headerSize)
      builder.add([0, 0, 0, 0]); // Store count (0) pointing at storeOffset

      final source = MemoryRandomAccessSource(builder.takeBytes());
      final reader = await SlobReader.openSource(source);
      
      expect(reader.header.encoding, equals('utf-8'));
      expect(reader.header.blobCount, equals(0));
      
      await reader.close();
    });
  });
}
