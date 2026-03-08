import 'dart:io';
import 'dart:math';
import 'package:slob_reader/slob_reader.dart';

void main() async {
  final path = 'abc.slob';
  if (!File(path).existsSync()) {
    print('Error: $path not found');
    return;
  }

  final reader = await SlobReader.open(path);
  final blobCount = reader.header.blobCount;
  print('File: $path (${(File(path).lengthSync() / 1024 / 1024).toStringAsFixed(2)} MB)');
  print('Total blobs: $blobCount');

  const queryCount = 500;
  final random = Random(42);
  final indices = List.generate(queryCount, (_) => random.nextInt(blobCount));

  print('Testing performance with $queryCount queries...');

  // 1. One by one
  final stopwatch1 = Stopwatch()..start();
  for (final index in indices) {
    await reader.getBlob(index);
  }
  stopwatch1.stop();
  print('One by one: ${stopwatch1.elapsedMilliseconds} ms');

  // 2. Bulk (grouped)
  // To make it interesting, let's group them into some ranges
  final ranges = <(int, int)>[];
  for (var i = 0; i < indices.length; i += 10) {
    final start = indices[i];
    final length = min(10, indices.length - i);
    ranges.add((start, length));
  }

  final stopwatch2 = Stopwatch()..start();
  await reader.getBlobs(ranges);
  stopwatch2.stop();
  print('Bulk method (ranges of 10): ${stopwatch2.elapsedMilliseconds} ms');

  // 3. Bulk (all at once)
  final stopwatch3 = Stopwatch()..start();
  await reader.getBlobs(indices.map((i) => (i, 1)).toList());
  stopwatch3.stop();
  print('Bulk method (all 500 at once): ${stopwatch3.elapsedMilliseconds} ms');

  await reader.close();
}
