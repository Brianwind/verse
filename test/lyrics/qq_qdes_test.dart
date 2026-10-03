import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:verse/lyrics/qq_qdes.dart';

void main() {
  group('QqQdes', () {
    test('round-trips complete QDES blocks', () {
      final plainText = Uint8List.fromList(utf8.encode('12345678abcdefgh'));

      final encrypted = QqQdes.encryptBytes(plainText);
      final decrypted = QqQdes.decryptBytes(encrypted);
      final encryptedHex =
          encrypted
              .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
              .join();

      expect(decrypted, plainText);
      expect(encryptedHex, '015ea69c23303ceef95817db1b0c5191');
    });

    test('decrypts, inflates, and decodes a QRC payload', () {
      const source = '[1000,800](1000,400)群(1400,400)青';
      final compressed = Uint8List.fromList(
        ZLibCodec().encode(utf8.encode(source)),
      );
      final paddedLength = ((compressed.length + 7) ~/ 8) * 8;
      final padded = Uint8List(paddedLength)..setAll(0, compressed);
      final encrypted = QqQdes.encryptBytes(padded);
      final hex =
          encrypted
              .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
              .join();

      expect(QqQdes.decryptAndInflate(hex), source);
    });

    test('rejects invalid hexadecimal and incomplete blocks', () {
      expect(() => QqQdes.decodeHex('xyz'), throwsFormatException);
      expect(() => QqQdes.decodeHex('0011'), throwsFormatException);
      expect(() => QqQdes.decodeHex('0'), throwsFormatException);
    });
  });
}
