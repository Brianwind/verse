import 'dart:convert';
import 'dart:typed_data';

class Mp3Metadata {
  const Mp3Metadata({
    this.title,
    this.artists = const [],
    this.album,
    this.albumArtist,
    this.year,
    this.durationMs,
    this.coverBytes,
    this.coverMimeType,
    this.customText = const {},
    this.unsynchronizedLyrics,
  });

  final String? title;
  final List<String> artists;
  final String? album;
  final String? albumArtist;
  final String? year;
  final int? durationMs;
  final Uint8List? coverBytes;
  final String? coverMimeType;
  final Map<String, String> customText;
  final String? unsynchronizedLyrics;
}

class Id3v23Writer {
  Uint8List writeMetadataToBytes(Uint8List mp3Bytes, Mp3Metadata metadata) {
    final audioBytes = _stripLeadingId3Tag(mp3Bytes);
    return Uint8List.fromList([...buildTag(metadata), ...audioBytes]);
  }

  Uint8List buildTag(Mp3Metadata metadata) {
    final frames = <int>[];

    _addTextFrame(frames, 'TIT2', metadata.title);
    _addTextFrame(frames, 'TPE1', metadata.artists.join('/'));
    _addTextFrame(frames, 'TALB', metadata.album);
    _addTextFrame(frames, 'TPE2', metadata.albumArtist);
    _addTextFrame(frames, 'TYER', metadata.year);
    _addTextFrame(frames, 'TLEN', metadata.durationMs?.toString());

    for (final entry in metadata.customText.entries) {
      _addUserTextFrame(frames, entry.key, entry.value);
    }

    final cover = metadata.coverBytes;
    if (cover != null && cover.isNotEmpty) {
      _addAttachedPictureFrame(
        frames,
        metadata.coverMimeType ?? 'image/jpeg',
        cover,
      );
    }
    _addUnsynchronizedLyricsFrame(frames, metadata.unsynchronizedLyrics);

    final header = <int>[
      ...ascii.encode('ID3'),
      3,
      0,
      0,
      ..._encodeSynchsafe(frames.length),
    ];

    return Uint8List.fromList([...header, ...frames]);
  }

  Uint8List _stripLeadingId3Tag(Uint8List bytes) {
    if (bytes.length < 10) return bytes;
    if (ascii.decode(bytes.sublist(0, 3), allowInvalid: true) != 'ID3') {
      return bytes;
    }

    final size = _decodeSynchsafe(bytes, 6);
    final end = 10 + size;
    if (end < 10 || end > bytes.length) return bytes;
    return Uint8List.fromList(bytes.sublist(end));
  }

  void _addTextFrame(List<int> frames, String id, String? value) {
    final normalized = value?.trim();
    if (normalized == null || normalized.isEmpty) return;
    _addFrame(frames, id, [1, ..._encodeUtf16LeWithBom(normalized)]);
  }

  void _addUserTextFrame(List<int> frames, String description, String value) {
    final normalizedDescription = description.trim();
    final normalizedValue = value.trim();
    if (normalizedDescription.isEmpty || normalizedValue.isEmpty) return;

    _addFrame(frames, 'TXXX', [
      1,
      ..._encodeUtf16LeWithBom(normalizedDescription),
      0,
      0,
      ..._encodeUtf16Le(normalizedValue),
    ]);
  }

  void _addAttachedPictureFrame(
    List<int> frames,
    String mimeType,
    Uint8List coverBytes,
  ) {
    final normalizedMimeType =
        mimeType.trim().isEmpty ? 'image/jpeg' : mimeType.trim();
    _addFrame(frames, 'APIC', [
      0,
      ...ascii.encode(normalizedMimeType),
      0,
      3,
      0,
      ...coverBytes,
    ]);
  }

  void _addUnsynchronizedLyricsFrame(List<int> frames, String? lyrics) {
    final normalizedLyrics = lyrics?.trim();
    if (normalizedLyrics == null || normalizedLyrics.isEmpty) return;

    _addFrame(frames, 'USLT', [
      1,
      ...ascii.encode('und'),
      ..._encodeUtf16LeWithBom('LRC'),
      0,
      0,
      ..._encodeUtf16Le(normalizedLyrics),
    ]);
  }

  void _addFrame(List<int> frames, String id, List<int> payload) {
    frames.addAll([
      ...ascii.encode(id),
      ..._encodeFrameSize(payload.length),
      0,
      0,
      ...payload,
    ]);
  }

  List<int> _encodeSynchsafe(int size) {
    return [
      (size >> 21) & 0x7f,
      (size >> 14) & 0x7f,
      (size >> 7) & 0x7f,
      size & 0x7f,
    ];
  }

  int _decodeSynchsafe(Uint8List bytes, int offset) {
    return (bytes[offset] << 21) |
        (bytes[offset + 1] << 14) |
        (bytes[offset + 2] << 7) |
        bytes[offset + 3];
  }

  List<int> _encodeFrameSize(int size) {
    return [
      (size >> 24) & 0xff,
      (size >> 16) & 0xff,
      (size >> 8) & 0xff,
      size & 0xff,
    ];
  }

  List<int> _encodeUtf16LeWithBom(String value) {
    return [0xff, 0xfe, ..._encodeUtf16Le(value)];
  }

  List<int> _encodeUtf16Le(String value) {
    final bytes = <int>[];
    for (final unit in value.codeUnits) {
      bytes.add(unit & 0xff);
      bytes.add((unit >> 8) & 0xff);
    }
    return bytes;
  }
}
