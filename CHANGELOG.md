# Changelog

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
