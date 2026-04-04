import 'dart:io';
import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:slob_reader/slob_reader.dart';

// Known facts about the abc.slob test file (English-French FreeDict Dictionary)
// These values were recorded from a verified run of example.dart.
const _slobPath = 'abc.slob';
const _expectedEncoding = 'utf-8';
const _expectedCompression = 'zlib';
const _expectedBlobCount = 8802;
const _expectedTagLabel = 'English-French FreeDict Dictionary';
const _expectedTagEdition = '0.1.6';
// Content types: [0]=text/css, [1]=application/javascript, [2]=text/html;charset=utf-8
const _expectedHtmlType = 'text/html;charset=utf-8';
// First entry is the CSS asset
const _firstBlobKey = '~/css/default.css';
const _firstBlobContentType = 'text/css';

void main() {
  // Helper to skip tests gracefully when the .slob is missing
  // (e.g. in a CI environment without the file).
  bool _slobPresent() => File(_slobPath).existsSync();

  // ─────────────────────────────────────────────────────────────
  // Opening / closing
  // ─────────────────────────────────────────────────────────────
  group('SlobReader.open / close', () {
    test('opens a valid .slob file without throwing', () async {
      if (!_slobPresent()) return markTestSkipped('abc.slob not found');
      final reader = await SlobReader.open(_slobPath);
      expect(reader, isNotNull);
      await reader.close();
    });

    test('throws on a non-existent file', () async {
      expect(
        () => SlobReader.open('non_existent_file.slob'),
        throwsA(anything),
      );
    });

    test('throws on a file with invalid magic bytes', () async {
      // Write a tiny file with wrong magic
      final tmp = await File('test_invalid.slob').create();
      await tmp.writeAsBytes(List.filled(32, 0x00));
      addTearDown(() async {
        if (await tmp.exists()) await tmp.delete();
      });
      expect(() => SlobReader.open('test_invalid.slob'), throwsException);
    });

    test('magicBytes constant has correct 8-byte value', () {
      expect(SlobReader.magicBytes, equals([0x21, 0x2d, 0x31, 0x53, 0x4c, 0x4f, 0x42, 0x1f]));
      expect(SlobReader.magicBytes.length, equals(8));
    });
  });

  // ─────────────────────────────────────────────────────────────
  // SlobHeader / reader.header
  // ─────────────────────────────────────────────────────────────
  group('SlobHeader (reader.header)', () {
    late SlobReader reader;

    setUpAll(() async {
      if (!_slobPresent()) return;
      reader = await SlobReader.open(_slobPath);
    });

    tearDownAll(() async {
      if (!_slobPresent()) return;
      await reader.close();
    });

    test('magic bytes match SlobReader.magicBytes', () {
      if (!_slobPresent()) return markTestSkipped('abc.slob not found');
      expect(reader.header.magic.toList(), equals(SlobReader.magicBytes));
    });

    test('uuid is a non-empty hex string', () {
      if (!_slobPresent()) return markTestSkipped('abc.slob not found');
      final uuid = reader.header.uuid;
      expect(uuid, isNotEmpty);
      // UUID is stored as hex digits only (no dashes)
      expect(RegExp(r'^[0-9a-f]+$').hasMatch(uuid), isTrue,
          reason: 'UUID should be a lowercase hex string');
    });

    test('encoding is utf-8', () {
      if (!_slobPresent()) return markTestSkipped('abc.slob not found');
      expect(reader.header.encoding, equals(_expectedEncoding));
    });

    test('compression is zlib', () {
      if (!_slobPresent()) return markTestSkipped('abc.slob not found');
      expect(reader.header.compression, equals(_expectedCompression));
    });

    test('blobCount matches known value', () {
      if (!_slobPresent()) return markTestSkipped('abc.slob not found');
      expect(reader.header.blobCount, equals(_expectedBlobCount));
    });

    test('size is a positive number of bytes', () {
      if (!_slobPresent()) return markTestSkipped('abc.slob not found');
      expect(reader.header.size, greaterThan(0));
    });

    test('refsOffset is positive', () {
      if (!_slobPresent()) return markTestSkipped('abc.slob not found');
      expect(reader.header.refsOffset, greaterThan(0));
    });

    test('storeOffset is positive and after refsOffset', () {
      if (!_slobPresent()) return markTestSkipped('abc.slob not found');
      expect(reader.header.storeOffset, greaterThan(reader.header.refsOffset));
    });

    test('tags contains expected label', () {
      if (!_slobPresent()) return markTestSkipped('abc.slob not found');
      expect(reader.header.tags['label'], equals(_expectedTagLabel));
    });

    test('tags contains edition', () {
      if (!_slobPresent()) return markTestSkipped('abc.slob not found');
      expect(reader.header.tags['edition'], equals(_expectedTagEdition));
    });

    test('tags contains license, uri, and copyright fields', () {
      if (!_slobPresent()) return markTestSkipped('abc.slob not found');
      expect(reader.header.tags.containsKey('license.name'), isTrue);
      expect(reader.header.tags.containsKey('uri'), isTrue);
      expect(reader.header.tags.containsKey('copyright'), isTrue);
    });

    test('contentTypes is non-empty', () {
      if (!_slobPresent()) return markTestSkipped('abc.slob not found');
      expect(reader.header.contentTypes, isNotEmpty);
    });

    test('contentTypes contains css, js, and html types', () {
      if (!_slobPresent()) return markTestSkipped('abc.slob not found');
      final types = reader.header.contentTypes;
      expect(types.any((t) => t.contains('text/css')), isTrue);
      expect(types.any((t) => t.contains('application/javascript')), isTrue);
      expect(types.any((t) => t.contains('text/html')), isTrue);
    });
  });

  // ─────────────────────────────────────────────────────────────
  // getRef
  // ─────────────────────────────────────────────────────────────
  group('getRef', () {
    late SlobReader reader;

    setUpAll(() async {
      if (!_slobPresent()) return;
      reader = await SlobReader.open(_slobPath);
    });

    tearDownAll(() async {
      if (!_slobPresent()) return;
      await reader.close();
    });

    test('returns a SlobRef with non-empty key for index 0', () async {
      if (!_slobPresent()) return markTestSkipped('abc.slob not found');
      final ref = await reader.getRef(0);
      expect(ref.key, equals(_firstBlobKey));
    });

    test('ref has valid binIndex and itemIndex (non-negative)', () async {
      if (!_slobPresent()) return markTestSkipped('abc.slob not found');
      final ref = await reader.getRef(0);
      expect(ref.binIndex, greaterThanOrEqualTo(0));
      expect(ref.itemIndex, greaterThanOrEqualTo(0));
    });

    test('fragment field is a String (may be empty)', () async {
      if (!_slobPresent()) return markTestSkipped('abc.slob not found');
      final ref = await reader.getRef(0);
      expect(ref.fragment, isA<String>());
    });

    test('different indices return different keys', () async {
      if (!_slobPresent()) return markTestSkipped('abc.slob not found');
      final ref0 = await reader.getRef(0);
      final ref1 = await reader.getRef(1);
      expect(ref0.key, isNot(equals(ref1.key)));
    });

    test('getRef is consistent with getBlob for the same index', () async {
      if (!_slobPresent()) return markTestSkipped('abc.slob not found');
      for (final i in [0, 1, 3, 100, 500]) {
        final ref = await reader.getRef(i);
        final blob = await reader.getBlob(i);
        expect(ref.key, equals(blob.key),
            reason: 'ref.key should match blob.key at index $i');
        expect(ref.fragment, equals(blob.fragment),
            reason: 'ref.fragment should match blob.fragment at index $i');
      }
    });

    test('headwords from index 3 onward are non-empty strings', () async {
      if (!_slobPresent()) return markTestSkipped('abc.slob not found');
      // Indices 0-2 are asset files (css/js); 3 onward are dictionary headwords.
      final sampleIndices = [3, 4, 5, 6, 7, 50, 200, 1000];
      for (final i in sampleIndices) {
        final ref = await reader.getRef(i);
        expect(ref.key, isNotEmpty,
            reason: 'key at index $i should be non-empty');
      }
    });
  });

  // ─────────────────────────────────────────────────────────────
  // getBlob
  // ─────────────────────────────────────────────────────────────
  group('getBlob', () {
    late SlobReader reader;

    setUpAll(() async {
      if (!_slobPresent()) return;
      reader = await SlobReader.open(_slobPath);
    });

    tearDownAll(() async {
      if (!_slobPresent()) return;
      await reader.close();
    });

    test('first blob is the CSS asset', () async {
      if (!_slobPresent()) return markTestSkipped('abc.slob not found');
      final blob = await reader.getBlob(0);
      expect(blob.key, equals(_firstBlobKey));
      expect(blob.contentType, equals(_firstBlobContentType));
    });

    test('blob content is non-empty Uint8List', () async {
      if (!_slobPresent()) return markTestSkipped('abc.slob not found');
      final blob = await reader.getBlob(0);
      expect(blob.content, isA<Uint8List>());
      expect(blob.content, isNotEmpty);
    });

    test('CSS blob content starts with "body"', () async {
      if (!_slobPresent()) return markTestSkipped('abc.slob not found');
      final blob = await reader.getBlob(0);
      final text = String.fromCharCodes(blob.content);
      expect(text.trimLeft().startsWith('body'), isTrue);
    });

    test('blob id is a positive integer', () async {
      if (!_slobPresent()) return markTestSkipped('abc.slob not found');
      final blob = await reader.getBlob(0);
      expect(blob.id, isA<int>());
      expect(blob.id, greaterThanOrEqualTo(0));
    });

    test('blob id matches its global index', () async {
      if (!_slobPresent()) return markTestSkipped('abc.slob not found');
      // Use an index other than zero to be definitive.
      const index = 5;
      final blob = await reader.getBlob(index);
      expect(blob.id, equals(index));
    });

    test('fragment field is a String (may be empty)', () async {
      if (!_slobPresent()) return markTestSkipped('abc.slob not found');
      final blob = await reader.getBlob(0);
      expect(blob.fragment, isA<String>());
    });

    test('HTML entries have text/html content type', () async {
      if (!_slobPresent()) return markTestSkipped('abc.slob not found');
      // Index 3 onward are dictionary entries (HTML)
      final blob = await reader.getBlob(3);
      expect(blob.contentType, equals(_expectedHtmlType));
    });

    test('HTML entry content looks like HTML', () async {
      if (!_slobPresent()) return markTestSkipped('abc.slob not found');
      final blob = await reader.getBlob(3);
      final text = String.fromCharCodes(blob.content);
      expect(text.contains('<'), isTrue,
          reason: 'HTML content should contain angle brackets');
    });

    test('reading last blob does not throw', () async {
      if (!_slobPresent()) return markTestSkipped('abc.slob not found');
      final last = reader.header.blobCount - 1;
      final blob = await reader.getBlob(last);
      expect(blob.key, isNotEmpty);
      expect(blob.content, isNotEmpty);
    });

    test('sequential reads return consistent data', () async {
      if (!_slobPresent()) return markTestSkipped('abc.slob not found');
      // Read the same blob twice and verify identical output.
      final blob1 = await reader.getBlob(5);
      final blob2 = await reader.getBlob(5);
      expect(blob1.key, equals(blob2.key));
      expect(blob1.content, equals(blob2.content));
      expect(blob1.contentType, equals(blob2.contentType));
    });
  });

  // ─────────────────────────────────────────────────────────────
  // getBlobContent
  // ─────────────────────────────────────────────────────────────
  group('getBlobContent', () {
    late SlobReader reader;

    setUpAll(() async {
      if (!_slobPresent()) return;
      reader = await SlobReader.open(_slobPath);
    });

    tearDownAll(() async {
      if (!_slobPresent()) return;
      await reader.close();
    });

    test('returns same bytes as getBlob.content for the same entry', () async {
      if (!_slobPresent()) return markTestSkipped('abc.slob not found');
      for (final i in [0, 1, 3, 10, 100]) {
        final ref = await reader.getRef(i);
        final rawBytes = await reader.getBlobContent(ref.binIndex, ref.itemIndex);
        final blob = await reader.getBlob(i);
        expect(rawBytes, equals(blob.content),
            reason: 'getBlobContent and getBlob.content should match at index $i');
      }
    });

    test('returns a Uint8List', () async {
      if (!_slobPresent()) return markTestSkipped('abc.slob not found');
      final ref = await reader.getRef(0);
      final bytes = await reader.getBlobContent(ref.binIndex, ref.itemIndex);
      expect(bytes, isA<Uint8List>());
    });

    test('returns non-empty bytes for a known entry', () async {
      if (!_slobPresent()) return markTestSkipped('abc.slob not found');
      final ref = await reader.getRef(0);
      final bytes = await reader.getBlobContent(ref.binIndex, ref.itemIndex);
      expect(bytes.length, greaterThan(0));
    });

    test('same binIndex + itemIndex always returns identical bytes', () async {
      if (!_slobPresent()) return markTestSkipped('abc.slob not found');
      final ref = await reader.getRef(0);
      final bytes1 = await reader.getBlobContent(ref.binIndex, ref.itemIndex);
      final bytes2 = await reader.getBlobContent(ref.binIndex, ref.itemIndex);
      expect(bytes1, equals(bytes2));
    });
  });

  // ─────────────────────────────────────────────────────────────
  // getBlobs (batch read)
  // ─────────────────────────────────────────────────────────────
  group('getBlobs (batch read)', () {
    late SlobReader reader;

    setUpAll(() async {
      if (!_slobPresent()) return;
      reader = await SlobReader.open(_slobPath);
    });

    tearDownAll(() async {
      if (!_slobPresent()) return;
      await reader.close();
    });

    test('empty ranges returns empty list', () async {
      if (!_slobPresent()) return markTestSkipped('abc.slob not found');
      final blobs = await reader.getBlobs([]);
      expect(blobs, isEmpty);
    });

    test('range of length 0 returns empty list', () async {
      if (!_slobPresent()) return markTestSkipped('abc.slob not found');
      final blobs = await reader.getBlobs([(0, 0)]);
      expect(blobs, isEmpty);
    });

    test('single range returns correct number of blobs', () async {
      if (!_slobPresent()) return markTestSkipped('abc.slob not found');
      final blobs = await reader.getBlobs([(0, 5)]);
      expect(blobs.length, equals(5));
    });

    test('multiple ranges return combined total', () async {
      if (!_slobPresent()) return markTestSkipped('abc.slob not found');
      final blobs = await reader.getBlobs([(0, 3), (10, 2), (100, 4)]);
      expect(blobs.length, equals(9));
    });

    test('batch results match individual getBlob results — keys', () async {
      if (!_slobPresent()) return markTestSkipped('abc.slob not found');
      final indices = [0, 1, 2, 5, 10];
      final individual = <SlobBlob>[];
      for (final i in indices) {
        individual.add(await reader.getBlob(i));
      }

      final batch = await reader.getBlobs([(0, 3), (5, 1), (10, 1)]);

      expect(batch.length, equals(individual.length));
      for (var i = 0; i < batch.length; i++) {
        expect(batch[i].key, equals(individual[i].key),
            reason: 'key mismatch at position $i');
      }
    });

    test('batch results match individual getBlob results — content', () async {
      if (!_slobPresent()) return markTestSkipped('abc.slob not found');
      final indices = [0, 1, 2, 5, 10];
      final individual = <SlobBlob>[];
      for (final i in indices) {
        individual.add(await reader.getBlob(i));
      }

      final batch = await reader.getBlobs([(0, 3), (5, 1), (10, 1)]);

      for (var i = 0; i < batch.length; i++) {
        expect(batch[i].content, equals(individual[i].content),
            reason: 'content mismatch at position $i');
        expect(batch[i].contentType, equals(individual[i].contentType),
            reason: 'contentType mismatch at position $i');
      }
    });

    test('batch preserves order of indices across ranges', () async {
      if (!_slobPresent()) return markTestSkipped('abc.slob not found');
      // Read [500–502] and [100–101]. The batch should return them in the order
      // they were requested.
      final batch = await reader.getBlobs([(500, 3), (100, 2)]);
      expect(batch.length, equals(5));

      final b500 = await reader.getBlob(500);
      final b501 = await reader.getBlob(501);
      final b502 = await reader.getBlob(502);
      final b100 = await reader.getBlob(100);
      final b101 = await reader.getBlob(101);

      expect(batch[0].key, equals(b500.key));
      expect(batch[1].key, equals(b501.key));
      expect(batch[2].key, equals(b502.key));
      expect(batch[3].key, equals(b100.key));
      expect(batch[4].key, equals(b101.key));
    });

    test('batch read last two entries', () async {
      if (!_slobPresent()) return markTestSkipped('abc.slob not found');
      final total = reader.header.blobCount;
      final blobs = await reader.getBlobs([(total - 2, 2)]);
      expect(blobs.length, equals(2));
      for (final b in blobs) {
        expect(b.key, isNotEmpty);
        expect(b.content, isNotEmpty);
      }
    });
  });

  // ─────────────────────────────────────────────────────────────
  // Binary search (README example)
  // ─────────────────────────────────────────────────────────────
  group('Binary search example', () {
    late SlobReader reader;

    setUpAll(() async {
      if (!_slobPresent()) return;
      reader = await SlobReader.open(_slobPath);
    });

    tearDownAll(() async {
      if (!_slobPresent()) return;
      await reader.close();
    });

    Future<SlobBlob?> binarySearch(String word) async {
      var lo = 0;
      var hi = reader.header.blobCount - 1;
      while (lo <= hi) {
        final mid = (lo + hi) ~/ 2;
        final blob = await reader.getBlob(mid);
        final cmp = blob.key.toLowerCase().compareTo(word.toLowerCase());
        if (cmp == 0) return blob;
        if (cmp < 0) {
          lo = mid + 1;
        } else {
          hi = mid - 1;
        }
      }
      return null;
    }

    test('finds a known headword "a"', () async {
      if (!_slobPresent()) return markTestSkipped('abc.slob not found');
      final result = await binarySearch('a');
      expect(result, isNotNull);
      expect(result!.key, equals('a'));
    });

    test('finds a known headword "abandon"', () async {
      if (!_slobPresent()) return markTestSkipped('abc.slob not found');
      final result = await binarySearch('abandon');
      expect(result, isNotNull);
      expect(result!.key.toLowerCase(), equals('abandon'));
    });

    test('returns null for a word not in the dictionary', () async {
      if (!_slobPresent()) return markTestSkipped('abc.slob not found');
      final result = await binarySearch('zzzzzzznotthere99999');
      expect(result, isNull);
    });
  });

  // ─────────────────────────────────────────────────────────────
  // Public API surface (compile-time checks)
  // ─────────────────────────────────────────────────────────────
  group('Public API surface', () {
    test('SlobReader, SlobBlob, SlobHeader, SlobRef are exported', () {
      expect(SlobReader, isNotNull);
      expect(SlobBlob, isNotNull);
      expect(SlobHeader, isNotNull);
      expect(SlobRef, isNotNull);
    });

    test('SlobReader.magicBytes is exported and has 8 items', () {
      expect(SlobReader.magicBytes.length, equals(8));
    });
  });
}
