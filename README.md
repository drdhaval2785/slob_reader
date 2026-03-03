# Slob Reader

A pure Dart implementation of the [Slob](https://github.com/itkach/slob) (Sorted List of Blobs) file format reader.

Slob is a read-only, compressed data store with a dictionary-like interface to look up content by text keys.

## Features

- Read `.slob` files (reference implementation compatibility).
- Support for multiple compression algorithms:
  - `zlib`
  - `bz2`
  - `lzma2` (via `XZDecoder`)
- Efficient indexing and blob retrieval.
- Multi-file support (not yet fully tested for split files, but header parsing is ready).

## Usage

### Basic Example

```dart
import 'package:slob_reader/slob_reader.dart';

void main() async {
  final reader = await SlobReader.open('path/to/file.slob');
  
  print('Title: ${reader.header.tags['label']}');
  
  // Get a blob by index
  final blob = await reader.getBlob(0);
  print('Key: ${blob.key}');
  print('Content: ${String.fromCharCodes(blob.content)}');
  
  await reader.close();
}
```

## Implementation Details

This package follows the reference implementation in Python closely. It handles:
- Header parsing (magic, UUID, flags).
- Tag retrieval.
- Content type management.
- Ref list (index) and Store bin decompression.

## Dependencies

- [archive](https://pub.dev/packages/archive) - Used for decompression.

## License

MIT
