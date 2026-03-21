import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:archive/archive_io.dart';
import 'models.dart';
import 'package:dictzip_reader/dictzip_reader.dart' show RandomAccessSource, FileRandomAccessSource;

class SlobReader {
  final RandomAccessSource _source;
  int _position = 0;
  late final SlobHeader _header;
  late final List<int> _refOffsets;
  late final List<int> _storeOffsets;

  static const List<int> magicBytes = [
    0x21,
    0x2d,
    0x31,
    0x53,
    0x4c,
    0x4f,
    0x42,
    0x1f
  ];

  SlobReader._(this._source);

  static Future<SlobReader> open(String path) async {
    return openSource(FileRandomAccessSource(path));
  }

  static Future<SlobReader> openSource(RandomAccessSource source) async {
    final reader = SlobReader._(source);
    await reader._init();
    return reader;
  }

  Future<void> _init() async {
    _position = 0;
    final magic = await _read(8);
    if (!_listEquals(magic, magicBytes)) {
      throw Exception('Invalid Slob magic: $magic');
    }

    // UUID
    final uuidBytes = await _read(16);
    final uuid =
        uuidBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

    final encoding = await _readTinyText();
    final compression = await _readTinyText();

    final tagCount = await _readByte();
    final tags = <String, String>{};
    for (var i = 0; i < tagCount; i++) {
      final name = await _readTinyText();
      final value = await _readTinyText(padded: true);
      tags[name] = value;
    }

    final contentTypeCount = await _readByte();
    final contentTypes = <String>[];
    for (var i = 0; i < contentTypeCount; i++) {
      contentTypes.add(await _readText());
    }

    final blobCount = await _readInt();
    final storeOffset = await _readLong();
    final size = await _readLong();
    final refsOffset = _position;

    _header = SlobHeader(
      magic: Uint8List.fromList(magic),
      uuid: uuid,
      encoding: encoding,
      compression: compression,
      tags: tags,
      contentTypes: contentTypes,
      blobCount: blobCount,
      storeOffset: storeOffset,
      size: size,
      refsOffset: refsOffset,
    );

    await _loadRefs();
    await _loadStore();
  }

  Future<void> _loadRefs() async {
    _position = _header.refsOffset;
    final count = await _readInt();
    final bytes = await _read(count * 8);
    final view = ByteData.view(bytes.buffer);
    _refOffsets = List<int>.generate(count, (i) => view.getUint64(i * 8));
  }

  Future<void> _loadStore() async {
    _position = _header.storeOffset;
    final count = await _readInt();
    final bytes = await _read(count * 8);
    final view = ByteData.view(bytes.buffer);
    _storeOffsets = List<int>.generate(count, (i) => view.getUint64(i * 8));
  }

  Future<SlobRef> getRef(int index) async {
    final itemDataPos =
        _header.refsOffset + 4 + (8 * _refOffsets.length) + _refOffsets[index];

    _position = itemDataPos;
    final key = await _readText();
    final binIndex = await _readInt();
    final itemIndex = await _readShort();
    final fragment = await _readTinyText();

    return SlobRef(
      key: key,
      binIndex: binIndex,
      itemIndex: itemIndex,
      fragment: fragment,
    );
  }

  Future<Uint8List> getBlobContent(int binIndex, int itemIndex) async {
    final itemDataPos = _header.storeOffset +
        4 +
        (8 * _storeOffsets.length) +
        _storeOffsets[binIndex];

    _position = itemDataPos;
    final binItemCount = await _readInt();
    await _read(binItemCount);
    final compressedSize = await _readInt();
    final compressedContent = await _read(compressedSize);

    final decompressed = _decompress(compressedContent);

    // Extract item from bin
    final binReader = _BinReader(decompressed, binItemCount);
    return binReader.getItem(itemIndex);
  }

  Uint8List _decompress(Uint8List compressedContent) {
    if (_header.compression == 'zlib') {
      return Uint8List.fromList(ZLibDecoder().decodeBytes(compressedContent));
    } else if (_header.compression == 'bz2') {
      return Uint8List.fromList(BZip2Decoder().decodeBytes(compressedContent));
    } else if (_header.compression == 'lzma2') {
      return Uint8List.fromList(XZDecoder().decodeBytes(compressedContent));
    } else if (_header.compression == '') {
      return compressedContent;
    } else {
      throw Exception('Unsupported compression: ${_header.compression}');
    }
  }

  Future<SlobBlob> getBlob(int index) async {
    final ref = await getRef(index);
    final content = await getBlobContent(ref.binIndex, ref.itemIndex);
    final contentType = _header
        .contentTypes[await _getContentTypeId(ref.binIndex, ref.itemIndex)];

    return SlobBlob(
      id: (ref.binIndex << 16) | ref.itemIndex,
      key: ref.key,
      fragment: ref.fragment,
      contentType: contentType,
      content: content,
    );
  }

  Future<List<SlobBlob>> getBlobs(List<(int, int)> ranges) async {
    final List<int> allIndices = [];
    for (final (start, length) in ranges) {
      for (var i = 0; i < length; i++) {
        allIndices.add(start + i);
      }
    }

    if (allIndices.isEmpty) return [];

    // Map global index to its Ref
    // We can optimize this by sorting indices and reading sequentially if there are many
    final Map<int, SlobRef> refs = {};
    for (final index in allIndices) {
      refs[index] = await getRef(index);
    }

    // Group indices by binIndex
    final Map<int, List<int>> binGroups = {};
    for (final index in allIndices) {
      final ref = refs[index]!;
      binGroups.putIfAbsent(ref.binIndex, () => []).add(index);
    }

    final Map<int, SlobBlob> blobsMap = {};

    for (final binIndex in binGroups.keys) {
      final indicesInBin = binGroups[binIndex]!;

      final itemDataPos = _header.storeOffset +
          4 +
          (8 * _storeOffsets.length) +
          _storeOffsets[binIndex];

      _position = itemDataPos;
      final binItemCount = await _readInt();
      final contentTypeIds = await _read(binItemCount);
      final compressedSize = await _readInt();
      final compressedContent = await _read(compressedSize);

      final decompressed = _decompress(compressedContent);
      final binReader = _BinReader(decompressed, binItemCount);

      for (final index in indicesInBin) {
        final ref = refs[index]!;
        final content = binReader.getItem(ref.itemIndex);
        final contentType = _header.contentTypes[contentTypeIds[ref.itemIndex]];

        blobsMap[index] = SlobBlob(
          id: (ref.binIndex << 16) | ref.itemIndex,
          key: ref.key,
          fragment: ref.fragment,
          contentType: contentType,
          content: content,
        );
      }
    }

    return allIndices.map((i) => blobsMap[i]!).toList();
  }

  Future<int> _getContentTypeId(int binIndex, int itemIndex) async {
    final itemDataPos = _header.storeOffset +
        4 +
        (8 * _storeOffsets.length) +
        _storeOffsets[binIndex];
    _position = itemDataPos + 4; // skip itemCount
    final contentTypeIds = await _read(itemIndex + 1);
    return contentTypeIds[itemIndex];
  }

  // Helpers
  Future<Uint8List> _read(int length) async {
    final bytes = await _source.read(_position, length);
    _position += bytes.length;
    return bytes;
  }

  Future<int> _readByte() async => (await _read(1))[0];
  Future<int> _readShort() async {
    final bytes = await _read(2);
    return ByteData.view(bytes.buffer).getUint16(0);
  }

  Future<int> _readInt() async {
    final bytes = await _read(4);
    return ByteData.view(bytes.buffer).getUint32(0);
  }

  Future<int> _readLong() async {
    final bytes = await _read(8);
    return ByteData.view(bytes.buffer).getUint64(0);
  }

  Future<String> _readTinyText({bool padded = false}) async {
    final len = await _readByte();
    final bytes = await _read(padded ? 255 : len);
    var actualBytes = bytes;
    if (padded) {
      final nullIndex = bytes.indexOf(0);
      actualBytes = nullIndex == -1 ? bytes : bytes.sublist(0, nullIndex);
    } else {
      actualBytes = bytes.sublist(0, len);
    }
    return String.fromCharCodes(actualBytes);
  }

  Future<String> _readText() async {
    final len = await _readShort();
    final bytes = await _read(len);
    return String.fromCharCodes(bytes);
  }

  bool _listEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  SlobHeader get header => _header;

  Future<void> close() async {
    await _source.close();
  }
}

class _BinReader {
  final Uint8List data;
  final int count;
  late final List<int> offsets;

  _BinReader(this.data, this.count) {
    offsets = [];
    final view =
        ByteData.view(data.buffer, data.offsetInBytes, data.lengthInBytes);
    for (var i = 0; i < count; i++) {
      offsets.add(view.getUint32(i * 4));
    }
  }

  Uint8List getItem(int index) {
    final offset = offsets[index];
    final dataOffset = count * 4;
    final view =
        ByteData.view(data.buffer, data.offsetInBytes, data.lengthInBytes);
    final itemLen = view.getUint32(dataOffset + offset);
    return data.sublist(
        dataOffset + offset + 4, dataOffset + offset + 4 + itemLen);
  }
}
