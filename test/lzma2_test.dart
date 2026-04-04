import 'dart:io';
import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:slob_reader/slob_reader.dart';

/// Path to the lzma2-compressed slob file used for testing.
const _lzma2SlobPath = '/Users/dhaval/Downloads/hindiwiktionary_2021-01-17.slob';

void main() {
  bool _slobPresent() => File(_lzma2SlobPath).existsSync();

  // ─────────────────────────────────────────────────────────────
  // Internal helpers — unit-test the XZ container builder
  // ─────────────────────────────────────────────────────────────
  group('_buildXzContainer (via _crc32 sanity check)', () {
    test('CRC32 of two zero bytes equals 0x41D912FF', () {
      // This is the precomputed stream_flags CRC32 constant baked into
      // _buildXzContainer. Verify the algorithm produces the expected value.
      final result = _dartCrc32([0x00, 0x00]);
      expect(result, equals(0x41D912FF),
          reason: 'CRC32([0x00,0x00]) must equal the XZ stream-flags constant');
    });

    test('CRC32 of block header bytes equals 0xA3E52F74', () {
      // Block header: [02 00 21 01 16 00 00 00]
      final bh = [0x02, 0x00, 0x21, 0x01, 0x16, 0x00, 0x00, 0x00];
      expect(_dartCrc32(bh), equals(0xA3E52F74));
    });
  });

  // ─────────────────────────────────────────────────────────────
  // Header validation
  // ─────────────────────────────────────────────────────────────
  group('lzma2 SlobHeader', () {
    late SlobReader reader;

    setUpAll(() async {
      if (!_slobPresent()) return;
      reader = await SlobReader.open(_lzma2SlobPath);
    });

    tearDownAll(() async {
      if (!_slobPresent()) return;
      await reader.close();
    });

    test('opens without throwing', () async {
      if (!_slobPresent()) return markTestSkipped('lzma2 slob not found');
      expect(reader, isNotNull);
    });

    test('compression is lzma2', () {
      if (!_slobPresent()) return markTestSkipped('lzma2 slob not found');
      expect(reader.header.compression, equals('lzma2'));
    });

    test('encoding is utf-8', () {
      if (!_slobPresent()) return markTestSkipped('lzma2 slob not found');
      expect(reader.header.encoding, equals('utf-8'));
    });

    test('blobCount is positive', () {
      if (!_slobPresent()) return markTestSkipped('lzma2 slob not found');
      expect(reader.header.blobCount, greaterThan(0));
    });

    test('contentTypes is non-empty', () {
      if (!_slobPresent()) return markTestSkipped('lzma2 slob not found');
      expect(reader.header.contentTypes, isNotEmpty);
    });

    test('uuid is a non-empty hex string', () {
      if (!_slobPresent()) return markTestSkipped('lzma2 slob not found');
      final uuid = reader.header.uuid;
      expect(uuid, isNotEmpty);
      expect(RegExp(r'^[0-9a-f]+$').hasMatch(uuid), isTrue);
    });
  });

  // ─────────────────────────────────────────────────────────────
  // Content decoding
  // ─────────────────────────────────────────────────────────────
  group('lzma2 blob decoding', () {
    late SlobReader reader;

    setUpAll(() async {
      if (!_slobPresent()) return;
      reader = await SlobReader.open(_lzma2SlobPath);
    });

    tearDownAll(() async {
      if (!_slobPresent()) return;
      await reader.close();
    });

    test('first blob key is non-empty', () async {
      if (!_slobPresent()) return markTestSkipped('lzma2 slob not found');
      final ref = await reader.getRef(0);
      expect(ref.key, isNotEmpty);
    });

    test('first blob content is non-empty Uint8List', () async {
      if (!_slobPresent()) return markTestSkipped('lzma2 slob not found');
      final blob = await reader.getBlob(0);
      expect(blob.content, isA<Uint8List>());
      expect(blob.content, isNotEmpty);
    });

    test('first blob has a valid contentType', () async {
      if (!_slobPresent()) return markTestSkipped('lzma2 slob not found');
      final blob = await reader.getBlob(0);
      expect(blob.contentType, isNotEmpty);
    });

    test('reads blobs 0-4 without throwing', () async {
      if (!_slobPresent()) return markTestSkipped('lzma2 slob not found');
      for (var i = 0; i < 5; i++) {
        final blob = await reader.getBlob(i);
        expect(blob.content, isNotEmpty,
            reason: 'blob $i content should not be empty');
      }
    });

    test('mid-file blob decodes successfully', () async {
      if (!_slobPresent()) return markTestSkipped('lzma2 slob not found');
      final mid = reader.header.blobCount ~/ 2;
      final blob = await reader.getBlob(mid);
      expect(blob.key, isNotEmpty);
      expect(blob.content, isNotEmpty);
    });

    test('last blob decodes successfully', () async {
      if (!_slobPresent()) return markTestSkipped('lzma2 slob not found');
      final last = reader.header.blobCount - 1;
      final blob = await reader.getBlob(last);
      expect(blob.key, isNotEmpty);
      expect(blob.content, isNotEmpty);
    });

    test('sequential reads return consistent data', () async {
      if (!_slobPresent()) return markTestSkipped('lzma2 slob not found');
      final blob1 = await reader.getBlob(3);
      final blob2 = await reader.getBlob(3);
      expect(blob1.key, equals(blob2.key));
      expect(blob1.content, equals(blob2.content));
      expect(blob1.contentType, equals(blob2.contentType));
    });

    test('html blobs contain angle brackets', () async {
      if (!_slobPresent()) return markTestSkipped('lzma2 slob not found');
      // Dictionary entries are typically HTML. Find the first html blob.
      for (var i = 0; i < reader.header.blobCount; i++) {
        final blob = await reader.getBlob(i);
        if (blob.contentType.contains('text/html')) {
          final text = String.fromCharCodes(blob.content);
          expect(text.contains('<'), isTrue,
              reason: 'HTML blob[$i] should contain angle brackets');
          return;
        }
      }
    });

    test('getBlobContent matches getBlob.content', () async {
      if (!_slobPresent()) return markTestSkipped('lzma2 slob not found');
      for (final i in [0, 1, 5]) {
        final ref = await reader.getRef(i);
        final raw = await reader.getBlobContent(ref.binIndex, ref.itemIndex);
        final blob = await reader.getBlob(i);
        expect(raw, equals(blob.content),
            reason: 'getBlobContent and getBlob.content must match at index $i');
      }
    });

    test('batch getBlobs matches individual getBlob results', () async {
      if (!_slobPresent()) return markTestSkipped('lzma2 slob not found');
      final batch = await reader.getBlobs([(0, 3)]);
      expect(batch.length, equals(3));
      for (var i = 0; i < 3; i++) {
        final single = await reader.getBlob(i);
        expect(batch[i].key, equals(single.key),
            reason: 'batch[i].key mismatch at $i');
        expect(batch[i].content, equals(single.content),
            reason: 'batch[i].content mismatch at $i');
      }
    });
  });
}

/// Mirror of SlobReader._crc32 — used in tests to validate the algorithm
/// produces the precomputed constants baked into _buildXzContainer.
int _dartCrc32(List<int> data) {
  var crc = 0xFFFFFFFF;
  for (final b in data) {
    crc ^= b;
    for (var j = 0; j < 8; j++) {
      crc = (crc & 1) != 0 ? (crc >>> 1) ^ 0xEDB88320 : crc >>> 1;
    }
  }
  return (~crc) & 0xFFFFFFFF;
}
