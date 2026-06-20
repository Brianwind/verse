import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:verse/utils/id3v23_writer.dart';

void main() {
  group('Id3v23Writer', () {
    test('builds text, custom, duration, and cover frames', () {
      final tag = Id3v23Writer().buildTag(
        Mp3Metadata(
          title: '歌曲',
          artists: const ['歌手 A', '歌手 B'],
          album: '专辑',
          albumArtist: '专辑歌手',
          year: '2026',
          durationMs: 198765,
          coverBytes: Uint8List.fromList([1, 2, 3, 4]),
          coverMimeType: 'image/jpeg',
          customText: const {
            'NETEASE_SONG_ID': '123',
            'NETEASE_ALBUM_ID': '456',
          },
        ),
      );

      expect(ascii.decode(tag.sublist(0, 3)), 'ID3');
      expect(tag[3], 3);
      expect(tag[4], 0);

      final frames = _parseFrames(tag);
      expect(_decodeTextFrame(frames['TIT2']!), '歌曲');
      expect(_decodeTextFrame(frames['TPE1']!), '歌手 A/歌手 B');
      expect(_decodeTextFrame(frames['TALB']!), '专辑');
      expect(_decodeTextFrame(frames['TPE2']!), '专辑歌手');
      expect(_decodeTextFrame(frames['TYER']!), '2026');
      expect(_decodeTextFrame(frames['TLEN']!), '198765');
      expect(
        _decodeTxxxFrames(frames['TXXX']!),
        containsPair('NETEASE_SONG_ID', '123'),
      );

      final apic = frames['APIC']!;
      expect(apic[0], 0);
      expect(ascii.decode(apic.sublist(1, 11)), 'image/jpeg');
      expect(apic[12], 3);
      expect(apic.sublist(apic.length - 4), [1, 2, 3, 4]);
    });

    test('builds an unsynchronized lyrics frame with LRC text', () {
      const lyrics = '[00:01.00]第一句\n[00:02.50]第二句';

      final tag = Id3v23Writer().buildTag(
        const Mp3Metadata(title: 'Song', unsynchronizedLyrics: lyrics),
      );

      final frames = _parseFrames(tag);
      expect(frames, contains('USLT'));
      final uslt = _decodeUsltFrame(frames['USLT']!);
      expect(uslt.language, 'und');
      expect(uslt.description, 'LRC');
      expect(uslt.lyrics, lyrics);
    });

    test('does not build an unsynchronized lyrics frame for empty lyrics', () {
      final tag = Id3v23Writer().buildTag(
        const Mp3Metadata(title: 'Song', unsynchronizedLyrics: '   '),
      );

      expect(_parseFrames(tag), isNot(contains('USLT')));
    });

    test('replaces an existing leading ID3 tag', () {
      final oldTag = <int>[
        ...ascii.encode('ID3'),
        3,
        0,
        0,
        0,
        0,
        0,
        3,
        9,
        9,
        9,
      ];
      final audio = <int>[0xff, 0xfb, 1, 2, 3];

      final result = Id3v23Writer().writeMetadataToBytes(
        Uint8List.fromList([...oldTag, ...audio]),
        const Mp3Metadata(title: 'New'),
      );

      final tagSize = _decodeSynchsafe(result, 6);
      expect(ascii.decode(result.sublist(0, 3)), 'ID3');
      expect(result.sublist(10 + tagSize), audio);
      expect(result.sublist(10 + tagSize), isNot(contains(9)));
    });
  });
}

Map<String, Uint8List> _parseFrames(Uint8List tag) {
  final tagSize = _decodeSynchsafe(tag, 6);
  final frames = <String, Uint8List>{};
  var offset = 10;
  final end = 10 + tagSize;

  while (offset + 10 <= end) {
    final id = ascii.decode(tag.sublist(offset, offset + 4));
    if (id.trim().isEmpty || tag[offset] == 0) break;
    final size = _decodeFrameSize(tag, offset + 4);
    final dataStart = offset + 10;
    final dataEnd = dataStart + size;
    final data = Uint8List.fromList(tag.sublist(dataStart, dataEnd));
    if (frames.containsKey(id)) {
      frames[id] = Uint8List.fromList([...frames[id]!, ...data]);
    } else {
      frames[id] = data;
    }
    offset = dataEnd;
  }

  return frames;
}

int _decodeSynchsafe(Uint8List bytes, int offset) {
  return (bytes[offset] << 21) |
      (bytes[offset + 1] << 14) |
      (bytes[offset + 2] << 7) |
      bytes[offset + 3];
}

int _decodeFrameSize(Uint8List bytes, int offset) {
  return (bytes[offset] << 24) |
      (bytes[offset + 1] << 16) |
      (bytes[offset + 2] << 8) |
      bytes[offset + 3];
}

String _decodeTextFrame(Uint8List data) {
  expect(data.first, 1);
  return _decodeUtf16LeWithBom(data.sublist(1));
}

Map<String, String> _decodeTxxxFrames(Uint8List data) {
  final result = <String, String>{};
  var offset = 0;
  while (offset < data.length) {
    expect(data[offset], 1);
    offset++;
    final separator = _findUtf16Terminator(data, offset);
    final description = _decodeUtf16LeWithBom(data.sublist(offset, separator));
    offset = separator + 2;
    final nextFrame = _findNextTxxxFrame(data, offset);
    final value = _decodeUtf16Le(data.sublist(offset, nextFrame));
    result[description] = value;
    offset = nextFrame;
  }
  return result;
}

({String language, String description, String lyrics}) _decodeUsltFrame(
  Uint8List data,
) {
  expect(data.first, 1);
  final language = ascii.decode(data.sublist(1, 4));
  final descriptionStart = 4;
  final separator = _findUtf16Terminator(data, descriptionStart);
  final description = _decodeUtf16LeWithBom(
    data.sublist(descriptionStart, separator),
  );
  final lyrics = _decodeUtf16Le(data.sublist(separator + 2));
  return (language: language, description: description, lyrics: lyrics);
}

int _findUtf16Terminator(Uint8List data, int start) {
  for (var i = start; i + 1 < data.length; i += 2) {
    if (data[i] == 0 && data[i + 1] == 0) return i;
  }
  return data.length;
}

int _findNextTxxxFrame(Uint8List data, int start) {
  for (var i = start; i < data.length; i++) {
    if (data[i] == 1 &&
        i + 2 < data.length &&
        data[i + 1] == 0xff &&
        data[i + 2] == 0xfe) {
      return i;
    }
  }
  return data.length;
}

String _decodeUtf16LeWithBom(Uint8List bytes) {
  if (bytes.length >= 2 && bytes[0] == 0xff && bytes[1] == 0xfe) {
    return _decodeUtf16Le(bytes.sublist(2));
  }
  return _decodeUtf16Le(bytes);
}

String _decodeUtf16Le(Uint8List bytes) {
  final units = <int>[];
  for (var i = 0; i + 1 < bytes.length; i += 2) {
    units.add(bytes[i] | (bytes[i + 1] << 8));
  }
  return String.fromCharCodes(units);
}
