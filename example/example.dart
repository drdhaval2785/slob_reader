import 'package:slob_reader/slob_reader.dart';

void main() async {
  // Opening a slob file
  final reader = await SlobReader.open('abc.slob');

  // Multi-range bulk read
  final ranges = [
    (0, 5),    // First 5 entries
    (100, 10), // Entries from index 100 to 109
  ];

  final blobs = await reader.getBlobs(ranges);

  print('Read ${blobs.length} blobs in bulk style.');
  for (final blob in blobs.take(3)) {
    print('Key: ${blob.key}, Content-Type: ${blob.contentType}');
  }

  await reader.close();
}
