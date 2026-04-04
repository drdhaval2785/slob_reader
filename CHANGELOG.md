# Changelog

## 0.1.6

- Added support for `lzma2` compressed slob files.

## 0.1.5

- Added `RandomAccessSource` abstraction to allow reading from arbitrary byte sources (e.g., Android SAF `content://` URIs).
- Added `FileRandomAccessSource` as the default implementation for `dart:io`.
- Added `SlobReader.openSource` for direct source-based initialization.

## 0.1.4

- Added documentation and examples.

## 0.1.3

- Added `getBlobs` method for bulk reading dictionary entries with optimized bin-level grouping.
- Optimized existing `getRef`, `getBlobContent`, and `_getContentTypeId` by reducing redundant file seek operations.
- Extracted compression logic into a separate internal helper.

## 0.1.2

- Optimized index loading with bulk reads, significantly reducing initial delay.

## 0.1.1

- Updated archive package to newest version.

## 0.1.0

- Initial release.
- Support for reading Slob (.slob) files.
- Support for zlib, bz2, and lzma2 compression.
