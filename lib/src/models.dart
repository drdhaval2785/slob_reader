import 'dart:typed_data';

class SlobHeader {
  final Uint8List magic;
  final String uuid;
  final String encoding;
  final String compression;
  final Map<String, String> tags;
  final List<String> contentTypes;
  final int blobCount;
  final int storeOffset;
  final int size;
  final int refsOffset;

  SlobHeader({
    required this.magic,
    required this.uuid,
    required this.encoding,
    required this.compression,
    required this.tags,
    required this.contentTypes,
    required this.blobCount,
    required this.storeOffset,
    required this.size,
    required this.refsOffset,
  });
}

class SlobRef {
  final String key;
  final int binIndex;
  final int itemIndex;
  final String fragment;

  SlobRef({
    required this.key,
    required this.binIndex,
    required this.itemIndex,
    required this.fragment,
  });
}

class SlobBlob {
  final int id;
  final String key;
  final String fragment;
  final String contentType;
  final Uint8List content;

  SlobBlob({
    required this.id,
    required this.key,
    required this.fragment,
    required this.contentType,
    required this.content,
  });
}
