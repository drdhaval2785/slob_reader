import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:archive/archive_io.dart';
import 'models.dart';

class SlobReader {
  final RandomAccessFile _file;
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

  SlobReader._(this._file);

  static Future<SlobReader> open(String path) async {
    final file = await File(path).open(mode: FileMode.read);
    final reader = SlobReader._(file);
    await reader._init();
    return reader;
  }

  Future<void> _init() async {
    await _file.setPosition(0);
    final magic = await _file.read(8);
    if (!_listEquals(magic, magicBytes)) {
      throw Exception('Invalid Slob magic: $magic');
    }

    // UUID
    final uuidBytes = await _file.read(16);
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
    final refsOffset = await _file.position();

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
    await _file.setPosition(_header.refsOffset);
    final count = await _readInt();
    final bytes = await _file.read(count * 8);
    final view = ByteData.view(bytes.buffer);
    _refOffsets = List<int>.generate(count, (i) => view.getUint64(i * 8));
  }

  Future<void> _loadStore() async {
    await _file.setPosition(_header.storeOffset);
    final count = await _readInt();
    final bytes = await _file.read(count * 8);
    final view = ByteData.view(bytes.buffer);
    _storeOffsets = List<int>.generate(count, (i) => view.getUint64(i * 8));
  }

  Future<SlobRef> getRef(int index) async {
    final pos = _header.refsOffset +
        4 +
        (index * 8); // Skip count (4) + refs (index * 8)
    await _file.setPosition(pos);
    final itemDataPos = (await _file.position()) +
        (8 * (_refOffsets.length - index)) +
        _refOffsets[index];

    await _file.setPosition(itemDataPos);
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
    final pos = _header.storeOffset + 4 + (binIndex * 8);
    await _file.setPosition(pos);
    final itemDataPos = (await _file.position()) +
        (8 * (_storeOffsets.length - binIndex)) +
        _storeOffsets[binIndex];

    await _file.setPosition(itemDataPos);
    final binItemCount = await _readInt();
    await _file.read(binItemCount);
    final compressedSize = await _readInt();
    final compressedContent = await _file.read(compressedSize);

    Uint8List decompressed;
    if (_header.compression == 'zlib') {
      decompressed =
          Uint8List.fromList(ZLibDecoder().decodeBytes(compressedContent));
    } else if (_header.compression == 'bz2') {
      decompressed =
          Uint8List.fromList(BZip2Decoder().decodeBytes(compressedContent));
    } else if (_header.compression == 'lzma2') {
      // Archive's XZDecoder might be needed for LZMA2 if raw is not directly exposed
      // But xz is usually a container for lzma2. Slob uses "raw lzma2 compression with LZMA2 filter".
      // Let's try XZDecoder or search if archive has raw lzma2.
      // Based on research, archive handles LZMA2 via XZ.
      decompressed =
          Uint8List.fromList(XZDecoder().decodeBytes(compressedContent));
    } else if (_header.compression == '') {
      decompressed = compressedContent;
    } else {
      throw Exception('Unsupported compression: ${_header.compression}');
    }

    // Extract item from bin
    final binReader = _BinReader(decompressed, binItemCount);
    return binReader.getItem(itemIndex);
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

  Future<int> _getContentTypeId(int binIndex, int itemIndex) async {
    final pos = _header.storeOffset + 4 + (binIndex * 8);
    await _file.setPosition(pos);
    final itemDataPos = (await _file.position()) +
        (8 * (_storeOffsets.length - binIndex)) +
        _storeOffsets[binIndex];
    await _file.setPosition(itemDataPos + 4); // skip itemCount
    final contentTypeIds = await _file.read(itemIndex + 1);
    return contentTypeIds[itemIndex];
  }

  // Helpers
  Future<int> _readByte() async => (await _file.read(1))[0];
  Future<int> _readShort() async {
    final bytes = await _file.read(2);
    return ByteData.view(bytes.buffer).getUint16(0);
  }

  Future<int> _readInt() async {
    final bytes = await _file.read(4);
    return ByteData.view(bytes.buffer).getUint32(0);
  }

  Future<int> _readLong() async {
    final bytes = await _file.read(8);
    return ByteData.view(bytes.buffer).getUint64(0);
  }

  Future<String> _readTinyText({bool padded = false}) async {
    final len = await _readByte();
    final bytes = await _file.read(padded ? 255 : len);
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
    final bytes = await _file.read(len);
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
    await _file.close();
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
