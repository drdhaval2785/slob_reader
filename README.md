# slob_reader

A pure Dart implementation of the [Slob](https://github.com/itkach/slob) (Sorted List of Blobs) file format reader. Supports `zlib`, `bz2`, and `lzma2` compression and is compatible with files produced by the [pyslob](https://github.com/itkach/slob) reference implementation.

## Features

- 🔓 Open any `.slob` file (read-only, random access)
- 📖 Read individual entries by index (`getBlob`)
- 📌 Read raw index entries (`getRef`)
- 🚀 Batch read multiple ranges efficiently (`getBlobs`)
- 🗜️ Transparent decompression — `zlib`, `bz2`, `lzma2`
- 🏷️ Rich file metadata — UUID, encoding, tags, content types
- ✅ Tested against the reference Python implementation

---

## Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  slob_reader: ^0.1.2
```

Then run:

```sh
dart pub get
```

---

## Quick Start

```dart
import 'package:slob_reader/slob_reader.dart';

void main() async {
  final reader = await SlobReader.open('path/to/dictionary.slob');

  // Read the first entry
  final blob = await reader.getBlob(0);
  print('Key:          ${blob.key}');
  print('Content-Type: ${blob.contentType}');
  print('Content:      ${String.fromCharCodes(blob.content)}');

  await reader.close();
}
```

---

## Core API

### `SlobReader.open(String path)`

Opens a `.slob` file for reading. Validates the magic bytes, parses the header, and loads both the ref-index and store-index into memory. This is a convenience wrapper around `openSource` using `FileRandomAccessSource`.

```dart
final reader = await SlobReader.open('en-wiktionary.slob');
```

---

### `SlobReader.openSource(RandomAccessSource source)`

Opens a `.slob` from an arbitrary source. This is useful for environments where `dart:io` `File` is not directly accessible, such as Android Storage Access Framework (SAF) `content://` URIs or Web Blobs.

```dart
class MyCustomSource implements RandomAccessSource {
  @override
  Future<Uint8List> read(int offset, int length) async {
    // Implement your own reading logic here (e.g., platform channel call)
  }
  
  @override
  Future<int> get length async => 12345;
  
  @override
  Future<void> close() async {}
}

final reader = await SlobReader.openSource(MyCustomSource());
```

---

### `reader.header` → `SlobHeader`

Provides access to the file's metadata. All fields are populated during `open()`.

| Field | Type | Description |
|---|---|---|
| `uuid` | `String` | Unique file identifier (hex string) |
| `encoding` | `String` | Character encoding (e.g. `"utf-8"`) |
| `compression` | `String` | Compression algorithm (`"zlib"`, `"bz2"`, `"lzma2"`, or `""`) |
| `tags` | `Map<String, String>` | Arbitrary key-value metadata set by the creator |
| `contentTypes` | `List<String>` | MIME types used for blobs (e.g. `"text/html; charset=utf-8"`) |
| `blobCount` | `int` | Total number of entries in the file |
| `size` | `int` | Total file size in bytes |

**Example — inspecting metadata:**

```dart
final h = reader.header;

print('UUID:        ${h.uuid}');
print('Encoding:    ${h.encoding}');
print('Compression: ${h.compression}');
print('Entries:     ${h.blobCount}');
print('File size:   ${h.size} bytes');

// Tags set by the dictionary creator, e.g. 'label', 'uri', 'copyright'
h.tags.forEach((key, value) => print('  tag[$key] = $value'));

// Content-type strings (indexed by blob.contentType id)
for (final ct in h.contentTypes) {
  print('  content-type: $ct');
}
```

---

### `reader.getBlob(int index)` → `Future<SlobBlob>`

Fetches the complete entry at the given position. This is the primary way to retrieve content.

Returns a `SlobBlob` with the following fields:

| Field | Type | Description |
|---|---|---|
| `key` | `String` | The dictionary headword / lookup key |
| `fragment` | `String` | Optional in-page fragment (anchor), may be empty |
| `contentType` | `String` | Full MIME type string |
| `content` | `Uint8List` | Raw (decompressed) entry content |
| `id` | `int` | Composite id: `(binIndex << 16) | itemIndex` |

**Example — reading entries sequentially:**

```dart
for (var i = 0; i < reader.header.blobCount; i++) {
  final blob = await reader.getBlob(i);

  if (blob.contentType.startsWith('text/html')) {
    final html = String.fromCharCodes(blob.content);
    print('=== ${blob.key} ===');
    print(html.substring(0, html.length.clamp(0, 200)));
  } else {
    // Binary content (images, CSS, etc.)
    print('${blob.key}: ${blob.content.length} bytes (${blob.contentType})');
  }
}
```

**Example — using the fragment for deep linking:**

```dart
final blob = await reader.getBlob(42);
if (blob.fragment.isNotEmpty) {
  // In a WebView you might navigate to: article.html#${blob.fragment}
  print('Fragment: #${blob.fragment}');
}
```

---

### `reader.getRef(int index)` → `Future<SlobRef>`

Fetches only the lightweight index entry for a given position, without decompressing the content. Useful for building search indexes or enumerating keys.

Returns a `SlobRef`:

| Field | Type | Description |
|---|---|---|
| `key` | `String` | The headword / lookup key |
| `binIndex` | `int` | Which compressed bin this entry lives in |
| `itemIndex` | `int` | Position within that bin |
| `fragment` | `String` | Optional anchor fragment |

**Example — listing all headwords without decompressing content:**

```dart
print('Total entries: ${reader.header.blobCount}');

for (var i = 0; i < reader.header.blobCount; i++) {
  final ref = await reader.getRef(i);
  print('[$i] ${ref.key}  (bin=${ref.binIndex}, item=${ref.itemIndex})');
}
```

**Example — simple binary search for a word:**

```dart
Future<SlobRef?> findRef(SlobReader reader, String word) async {
  var lo = 0;
  var hi = reader.header.blobCount - 1;

  while (lo <= hi) {
    final mid = (lo + hi) ~/ 2;
    final ref = await reader.getRef(mid);
    final cmp = ref.key.compareTo(word);
    if (cmp == 0) return ref;
    if (cmp < 0) lo = mid + 1;
    else hi = mid - 1;
  }
  return null; // not found
}
```

---

### `reader.getBlobContent(int binIndex, int itemIndex)` → `Future<Uint8List>`

Low-level method: decompresses the given bin and extracts the raw bytes for the specified item. You normally get `binIndex` and `itemIndex` from a `SlobRef`.

```dart
final ref = await reader.getRef(0);
final bytes = await reader.getBlobContent(ref.binIndex, ref.itemIndex);
print('Raw content length: ${bytes.length} bytes');
```

---

### `reader.getBlobs(List<(int, int)> ranges)` → `Future<List<SlobBlob>>`

Batch reads multiple ranges of entries efficiently. Entries that share the same compressed bin are decompressed only once, making this significantly faster than calling `getBlob` in a loop when reading many entries.

Each element in `ranges` is a record `(int startIndex, int length)`.

**Example — read first 10 and entries 500–509:**

```dart
final blobs = await reader.getBlobs([
  (0,   10),   // indices 0–9
  (500, 10),   // indices 500–509
]);

for (final blob in blobs) {
  print('${blob.key}: ${blob.contentType}');
}
```

**Example — reading a page of results (e.g. for a list view):**

```dart
Future<List<SlobBlob>> fetchPage(SlobReader reader, {
  required int page,
  int pageSize = 20,
}) async {
  final start = page * pageSize;
  final safeLength = (start + pageSize)
      .clamp(0, reader.header.blobCount) - start;
  if (safeLength <= 0) return [];
  return reader.getBlobs([(start, safeLength)]);
}

final page0 = await fetchPage(reader, page: 0);
final page1 = await fetchPage(reader, page: 1);
```

---

### `reader.close()`

Closes the underlying file handle. Always call this when you are done.

```dart
await reader.close();
```

---

## Complete Usage Examples

### Print the first 5 entries

```dart
import 'package:slob_reader/slob_reader.dart';

void main() async {
  final reader = await SlobReader.open('dictionary.slob');

  final blobs = await reader.getBlobs([(0, 5)]);
  for (final blob in blobs) {
    print('--- ${blob.key} ---');
    print(String.fromCharCodes(blob.content));
    print('');
  }

  await reader.close();
}
```

### Lookup a word using binary search

```dart
import 'package:slob_reader/slob_reader.dart';

void main() async {
  final reader = await SlobReader.open('dictionary.slob');
  final word = 'hello';

  var lo = 0;
  var hi = reader.header.blobCount - 1;
  SlobBlob? result;

  while (lo <= hi) {
    final mid = (lo + hi) ~/ 2;
    final blob = await reader.getBlob(mid);
    final cmp = blob.key.toLowerCase().compareTo(word);
    if (cmp == 0) { result = blob; break; }
    if (cmp < 0) lo = mid + 1;
    else hi = mid - 1;
  }

  if (result != null) {
    print('Found: ${result.key}');
    print(String.fromCharCodes(result.content));
  } else {
    print('"$word" not found.');
  }

  await reader.close();
}
```

### Print file metadata and tag information

```dart
import 'package:slob_reader/slob_reader.dart';

void main() async {
  final reader = await SlobReader.open('dictionary.slob');
  final h = reader.header;

  print('UUID:          ${h.uuid}');
  print('Encoding:      ${h.encoding}');
  print('Compression:   ${h.compression}');
  print('Total entries: ${h.blobCount}');
  print('File size:     ${h.size} bytes');

  print('\nTags:');
  h.tags.forEach((k, v) => print('  $k = $v'));

  print('\nContent Types:');
  for (var i = 0; i < h.contentTypes.length; i++) {
    print('  [$i] ${h.contentTypes[i]}');
  }

  await reader.close();
}
```

### Export all HTML entries to files

```dart
import 'dart:io';
import 'package:slob_reader/slob_reader.dart';

void main() async {
  final reader = await SlobReader.open('dictionary.slob');
  final outDir = Directory('output')..createSync();

  for (var i = 0; i < reader.header.blobCount; i++) {
    final blob = await reader.getBlob(i);
    if (blob.contentType.contains('text/html')) {
      final safe = blob.key.replaceAll(RegExp(r'[^\w]'), '_');
      File('output/$safe.html')
          .writeAsBytesSync(blob.content);
    }
  }

  print('Done.');
  await reader.close();
}
```

---

## Supported Compressions

| Value in header | Algorithm | Notes |
|---|---|---|
| `zlib` | Deflate | Most common in Wikipedia slobs |
| `bz2` | BZip2 | Older slob files |
| `lzma2` | LZMA2 (XZ) | High compression ratio |
| `""` (empty) | None | Raw, uncompressed bins |

---

## Dependencies

- [`archive`](https://pub.dev/packages/archive) — Decompression (zlib, bz2, lzma2/XZ)

---

## License

MIT
