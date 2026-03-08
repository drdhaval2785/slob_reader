import 'package:test/test.dart';
import 'package:slob_reader/slob_reader.dart';
import 'dart:io';

void main() {
  group('SlobReader', () {
    test('can open abc.slob and read header', () async {
      final path = 'abc.slob';
      if (!File(path).existsSync()) {
        markTestSkipped('abc.slob not found in current directory');
        return;
      }

      final reader = await SlobReader.open(path);
      expect(reader.header.magic, equals(SlobReader.magicBytes));
      expect(reader.header.encoding, equals('utf-8'));
      expect(reader.header.compression, equals('zlib'));
      expect(reader.header.blobCount, isPositive);

      await reader.close();
    });

    test('can read a blob', () async {
      final path = 'abc.slob';
      if (!File(path).existsSync()) {
        markTestSkipped('abc.slob not found');
        return;
      }

      final reader = await SlobReader.open(path);
      final blob = await reader.getBlob(0);
      expect(blob.key, isNotEmpty);
      expect(blob.content, isNotEmpty);

      await reader.close();
    });
    test('can read multiple blobs (getBlobs)', () async {
      final path = 'abc.slob';
      if (!File(path).existsSync()) {
        markTestSkipped('abc.slob not found');
        return;
      }

      final reader = await SlobReader.open(path);
      
      // Read indices 0, 1, 5, 10
      final indices = [0, 1, 5, 10];
      final individualBlobs = <SlobBlob>[];
      for (final i in indices) {
        individualBlobs.add(await reader.getBlob(i));
      }

      final bulkBlobs = await reader.getBlobs([(0, 2), (5, 1), (10, 1)]);

      expect(bulkBlobs.length, equals(individualBlobs.length));
      for (var i = 0; i < bulkBlobs.length; i++) {
        expect(bulkBlobs[i].key, equals(individualBlobs[i].key));
        expect(bulkBlobs[i].content, equals(individualBlobs[i].content));
        expect(bulkBlobs[i].contentType, equals(individualBlobs[i].contentType));
      }

      await reader.close();
    });
  });
}
