import 'dart:convert';
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
    switch (_header.compression) {
      case '':
        return compressedContent;
      case 'zlib':
        return Uint8List.fromList(ZLibDecoder().decodeBytes(compressedContent));
      case 'bz2':
        return Uint8List.fromList(BZip2Decoder().decodeBytes(compressedContent));
      case 'lzma2':
        return _decompressLzma2(compressedContent);
      default:
        throw Exception('Unsupported compression: ${_header.compression}');
    }
  }

  /// Decompresses raw LZMA2 data stored in slob files.
  ///
  /// Slob uses Python's `lzma.compress(data, format=lzma.FORMAT_RAW,
  /// filters=[{"id": lzma.FILTER_LZMA2}])`, which produces bare LZMA2 chunks
  /// with NO XZ container. These bytes are exactly the inner block data of an
  /// XZ stream. We wrap them in a minimal valid XZ container so that
  /// [XZDecoder] can decode them.
  ///
  /// Key insight: [XZDecoder.decodeBytes] ignores the return value of
  /// [XZDecoder.decodeStream]. Even if the index verification fails (we use a
  /// 0-record dummy index to avoid needing the uncompressed size), the decoded
  /// output is already written to the output buffer and is returned correctly.
  Uint8List _decompressLzma2(Uint8List rawLzma2) {
    final xzData = _buildXzContainer(rawLzma2);
    return Uint8List.fromList(XZDecoder().decodeBytes(xzData));
  }

  /// Computes CRC32 (ISO 3309 polynomial, same as used by XZ format).
  static int _crc32(List<int> data) {
    var crc = 0xFFFFFFFF;
    for (final b in data) {
      crc ^= b;
      for (var j = 0; j < 8; j++) {
        crc = (crc & 1) != 0 ? (crc >>> 1) ^ 0xEDB88320 : crc >>> 1;
      }
    }
    return (~crc) & 0xFFFFFFFF;
  }

  /// Writes [value] as a 32-bit little-endian integer into [buf] at [offset].
  static void _writeUint32LE(Uint8List buf, int offset, int value) {
    buf[offset]     =  value        & 0xFF;
    buf[offset + 1] = (value >>  8) & 0xFF;
    buf[offset + 2] = (value >> 16) & 0xFF;
    buf[offset + 3] = (value >> 24) & 0xFF;
  }

  /// Wraps [rawLzma2] (bare LZMA2 chunks from slob) in a minimal valid XZ
  /// stream container so that [XZDecoder] can decode the data.
  ///
  /// XZ container layout produced:
  /// ```
  /// [Stream Header 12 B]  magic + flags(00 00) + CRC32
  /// [Block Header  12 B]  size + flags + LZMA2 filter(0x21) + props + CRC32
  /// [Raw LZMA2    N  B]  the bytes directly from the slob bin
  /// [Padding       P  B]  0–3 zero bytes → (12+N+P) % 4 == 0
  /// [Index stub    2  B]  0x00 (indicator) + 0x00 (0 records VLI)
  ///                        nRecords=0 ≠ actual block count=1 → decode()=false
  ///                        decodeBytes() ignores that → decoded output returned
  /// ```
  ///
  /// Notes:
  /// - dict_prop = 0x16 (8 MB) matches Python lzma's default preset 6.
  ///   The `dictionarySize` parameter is not actually used by the archive
  ///   package's `_readLZMA2` during decoding, so this value is a safe default
  ///   for all slob files regardless of their original compression settings.
  /// - stream_flags CRC32 = 0x41D912FF (precomputed, CRC32 of {0x00,0x00}).
  /// - block header CRC is computed at runtime (depends on dict_prop).
  static Uint8List _buildXzContainer(Uint8List rawLzma2) {
    const dictProp = 0x16; // 8 MB, Python lzma default (preset 6)

    // CRC32([0x00, 0x00]) — stream flags bytes. Precomputed constant.
    const streamFlagsCrc = 0x41D912FF;

    // Build 8-byte block header prefix (excludes the 4-byte CRC field).
    final blockHdr = Uint8List(8);
    blockHdr[0] = 0x02; // size byte → total block header = (2+1)*4 = 12 bytes
    blockHdr[1] = 0x00; // flags: 1 filter, no optional compressed/uncompressed lengths
    blockHdr[2] = 0x21; // LZMA2 filter ID
    blockHdr[3] = 0x01; // filter properties length = 1 byte
    blockHdr[4] = dictProp;
    // blockHdr[5..7] = 0x00 padding (already zero)
    final blockHdrCrc = _crc32(blockHdr);

    // Zero-padding to make (block_header + raw_data) a multiple of 4 bytes.
    final padLen = (4 - (12 + rawLzma2.length) % 4) % 4;

    // Allocate output: stream_hdr(12) + block_hdr(12) + data(N) + pad(P) + stub(2)
    final out = Uint8List(24 + rawLzma2.length + padLen + 2);
    var p = 0;

    // ── Stream header (12 bytes) ──────────────────────────────────────────────
    out[p++] = 0xFD; out[p++] = 0x37; out[p++] = 0x7A;
    out[p++] = 0x58; out[p++] = 0x5A; out[p++] = 0x00; // XZ magic
    out[p++] = 0x00; out[p++] = 0x00;                   // stream flags (check=none)
    _writeUint32LE(out, p, streamFlagsCrc); p += 4;

    // ── Block header (12 bytes) ───────────────────────────────────────────────
    out.setRange(p, p + 8, blockHdr); p += 8;
    _writeUint32LE(out, p, blockHdrCrc); p += 4;

    // ── Raw LZMA2 data ───────────────────────────────────────────────────────
    out.setRange(p, p + rawLzma2.length, rawLzma2);
    p += rawLzma2.length;

    // ── Block padding (already zero-filled by Uint8List) ────────────────────
    p += padLen;

    // ── Dummy index stub ─────────────────────────────────────────────────────
    out[p++] = 0x00; // index indicator byte (signals start of index section)
    out[p++] = 0x00; // nRecords VLI = 0 → mismatch with 1 block → decode()=false
    //                  XZDecoder.decodeBytes() ignores that return value. ✓

    return out;
  }

  Future<SlobBlob> getBlob(int index) async {
    final ref = await getRef(index);
    final content = await getBlobContent(ref.binIndex, ref.itemIndex);
    final contentType = _header
        .contentTypes[await _getContentTypeId(ref.binIndex, ref.itemIndex)];

    return SlobBlob(
      id: index,
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
          id: index,
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
    return utf8.decode(actualBytes, allowMalformed: true);
  }

  Future<String> _readText() async {
    final len = await _readShort();
    final bytes = await _read(len);
    return utf8.decode(bytes, allowMalformed: true);
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
