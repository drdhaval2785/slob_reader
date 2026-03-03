import 'package:slob_reader/slob_reader.dart';
import 'package:test/test.dart';

void main() {
  group('SlobReader Pub.dev Check', () {
    test('public API is consistent', () {
      // Just a compile check for exports
      expect(SlobReader, isNotNull);
      expect(SlobBlob, isNotNull);
      expect(SlobHeader, isNotNull);
      expect(SlobRef, isNotNull);
    });
  });
}
