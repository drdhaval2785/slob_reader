// ignore_for_file: avoid_print
import 'dart:io';
import 'package:slob_reader/slob_reader.dart';

/// Run with:
///   dart example/example.dart path/to/dictionary.slob
void main(List<String> args) async {
  final path = args.isNotEmpty ? args.first : 'test/abc.slob';

  print('Opening: $path\n');
  final reader = await SlobReader.open(path);

  // ─────────────────────────────────────────────────────────────
  // 1. Inspect file metadata via reader.header
  // ─────────────────────────────────────────────────────────────
  await _showMetadata(reader);

  // ─────────────────────────────────────────────────────────────
  // 2. Read a single entry by index — reader.getBlob(index)
  // ─────────────────────────────────────────────────────────────
  await _showSingleBlob(reader, index: 0);

  // ─────────────────────────────────────────────────────────────
  // 3. Read only the index record (no decompression) — reader.getRef(index)
  // ─────────────────────────────────────────────────────────────
  await _showRef(reader, index: 0);

  // ─────────────────────────────────────────────────────────────
  // 4. Read raw decompressed bytes — reader.getBlobContent(binIndex, itemIndex)
  // ─────────────────────────────────────────────────────────────
  await _showBlobContent(reader, index: 0);

  // ─────────────────────────────────────────────────────────────
  // 5. Batch read multiple ranges — reader.getBlobs(ranges)
  // ─────────────────────────────────────────────────────────────
  await _showBatchRead(reader);

  // ─────────────────────────────────────────────────────────────
  // 6. Binary search for a word using getRef
  // ─────────────────────────────────────────────────────────────
  await _binarySearch(reader, word: 'a');

  // ─────────────────────────────────────────────────────────────
  // 7. Enumerate all headwords without decompressing content
  // ─────────────────────────────────────────────────────────────
  await _listAllKeys(reader, limit: 10);

  // Always close when done.
  await reader.close();
  print('\nFile closed.');

  // ─────────────────────────────────────────────────────────────
  // 8. Open from a custom RandomAccessSource (e.g. for Android SAF)
  // ─────────────────────────────────────────────────────────────
  await _showCustomSource(path);

  print('\nBye!');
}

// ───────────────────────────────────────────────────────────────
// Section 8 — Custom Source
// ───────────────────────────────────────────────────────────────
Future<void> _showCustomSource(String path) async {
  print('══════════════════════════════════');
  print(' 8. Custom Source (RandomAccessSource)');
  print('══════════════════════════════════');

  // Here we use FileRandomAccessSource which implements RandomAccessSource.
  // In a real Flutter app (hdict), you would use SafStreamSource.
  final source = FileRandomAccessSource(path);
  print('Opening via source: ${source.path}');
  
  final reader = await SlobReader.openSource(source);
  print('Successfully opened source.');
  print('Entry count: ${reader.header.blobCount}');

  await reader.close();
  print('Custom source closed.');
}

// ───────────────────────────────────────────────────────────────
// Section 1 — Metadata
// ───────────────────────────────────────────────────────────────
Future<void> _showMetadata(SlobReader reader) async {
  print('══════════════════════════════════');
  print(' 1. File Metadata (reader.header)');
  print('══════════════════════════════════');

  final h = reader.header;
  print('UUID:          ${h.uuid}');
  print('Encoding:      ${h.encoding}');
  print('Compression:   "${h.compression}"');
  print('Total entries: ${h.blobCount}');
  print('File size:     ${h.size} bytes');

  if (h.tags.isNotEmpty) {
    print('\nTags:');
    h.tags.forEach((key, value) => print('  $key = $value'));
  }

  print('\nContent Types:');
  for (var i = 0; i < h.contentTypes.length; i++) {
    print('  [$i] ${h.contentTypes[i]}');
  }
  print('');
}

// ───────────────────────────────────────────────────────────────
// Section 2 — Single entry (getBlob)
// ───────────────────────────────────────────────────────────────
Future<void> _showSingleBlob(SlobReader reader, {required int index}) async {
  print('══════════════════════════════════');
  print(' 2. Single Entry  reader.getBlob($index)');
  print('══════════════════════════════════');

  final blob = await reader.getBlob(index);

  print('id:           ${blob.id}');
  print('key:          "${blob.key}"');
  print('fragment:     "${blob.fragment}"');
  print('contentType:  "${blob.contentType}"');
  print('content size: ${blob.content.length} bytes');

  // Only print text content to avoid noise for binary blobs.
  if (blob.contentType.startsWith('text/')) {
    final text = String.fromCharCodes(blob.content);
    final preview = text.length > 300 ? '${text.substring(0, 300)}…' : text;
    print('\nContent preview:\n$preview');
  }
  print('');
}

// ───────────────────────────────────────────────────────────────
// Section 3 — Index entry only (getRef)
// ───────────────────────────────────────────────────────────────
Future<void> _showRef(SlobReader reader, {required int index}) async {
  print('══════════════════════════════════');
  print(' 3. Index Entry  reader.getRef($index)');
  print('══════════════════════════════════');

  final ref = await reader.getRef(index);

  print('key:       "${ref.key}"');
  print('binIndex:  ${ref.binIndex}');
  print('itemIndex: ${ref.itemIndex}');
  print('fragment:  "${ref.fragment}"');
  print('');
}

// ───────────────────────────────────────────────────────────────
// Section 4 — Raw content bytes (getBlobContent)
// ───────────────────────────────────────────────────────────────
Future<void> _showBlobContent(SlobReader reader, {required int index}) async {
  print('══════════════════════════════════');
  print(' 4. Raw Bytes  reader.getBlobContent(binIndex, itemIndex)');
  print('══════════════════════════════════');

  final ref = await reader.getRef(index);
  final bytes = await reader.getBlobContent(ref.binIndex, ref.itemIndex);

  print('For key "${ref.key}" → bin=${ref.binIndex}, item=${ref.itemIndex}');
  print('Decompressed size: ${bytes.length} bytes');
  // Show first 16 bytes as hex
  final hex = bytes
      .take(16)
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join(' ');
  print('First 16 bytes:    $hex');
  print('');
}

// ───────────────────────────────────────────────────────────────
// Section 5 — Batch read (getBlobs)
// ───────────────────────────────────────────────────────────────
Future<void> _showBatchRead(SlobReader reader) async {
  print('══════════════════════════════════');
  print(' 5. Batch Read  reader.getBlobs(ranges)');
  print('══════════════════════════════════');

  final total = reader.header.blobCount;

  // Range 1: first 3 entries.
  // Range 2: last 2 entries (or fewer if total < 5).
  final range1Length = total.clamp(0, 3);
  final range2Start = (total - 2).clamp(0, total);
  final range2Length = total - range2Start;

  final ranges = [
    (0, range1Length),
    if (range2Length > 0) (range2Start, range2Length),
  ];

  print('Reading ranges: $ranges');
  final blobs = await reader.getBlobs(ranges);

  print('Got ${blobs.length} blobs:');
  for (final blob in blobs) {
    print('  [${blob.id}] "${blob.key}"  (${blob.content.length} bytes, ${blob.contentType})');
  }
  print('');
}

// ───────────────────────────────────────────────────────────────
// Section 6 — Binary search with getRef
// ───────────────────────────────────────────────────────────────
Future<void> _binarySearch(SlobReader reader, {required String word}) async {
  print('══════════════════════════════════');
  print(' 6. Binary Search for "$word"');
  print('══════════════════════════════════');

  var lo = 0;
  var hi = reader.header.blobCount - 1;
  SlobBlob? found;

  while (lo <= hi) {
    final mid = (lo + hi) ~/ 2;
    final blob = await reader.getBlob(mid);
    final cmp = blob.key.toLowerCase().compareTo(word.toLowerCase());
    if (cmp == 0) {
      found = blob;
      break;
    } else if (cmp < 0) {
      lo = mid + 1;
    } else {
      hi = mid - 1;
    }
  }

  if (found != null) {
    print('✅ Found: "${found.key}" (${found.content.length} bytes)');
  } else {
    print('❌ "$word" not found in this file.');
  }
  print('');
}

// ───────────────────────────────────────────────────────────────
// Section 7 — List all keys using getRef (no decompression)
// ───────────────────────────────────────────────────────────────
Future<void> _listAllKeys(SlobReader reader, {required int limit}) async {
  print('══════════════════════════════════');
  print(' 7. All Headwords  reader.getRef(i)  [first $limit]');
  print('══════════════════════════════════');

  final count = reader.header.blobCount.clamp(0, limit);
  for (var i = 0; i < count; i++) {
    final ref = await reader.getRef(i);
    final frag = ref.fragment.isNotEmpty ? '#${ref.fragment}' : '';
    print('  [$i] ${ref.key}$frag');
  }

  if (reader.header.blobCount > limit) {
    print('  … (${reader.header.blobCount - limit} more entries)');
  }
  print('');
}
