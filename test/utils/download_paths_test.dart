import 'package:flutter_test/flutter_test.dart';
import 'package:verse/utils/download_paths.dart';

void main() {
  group('download paths', () {
    test('sanitizes Windows-invalid filename characters', () {
      expect(
        sanitizeDownloadFileName('AC/DC: <Live>?* "Best"|Track'),
        'AC DC Live Best Track',
      );
    });

    test('uses fallback when sanitized filename is empty', () {
      expect(
        sanitizeDownloadFileName('///***', fallback: 'untitled'),
        'untitled',
      );
    });

    test('builds mp3 filename from artists and title', () {
      expect(
        buildMp3DownloadFileName(
          songName: 'Song:Name',
          artistNames: const ['Artist/One', 'Artist Two'],
        ),
        'Artist One, Artist Two - Song Name.mp3',
      );
    });

    test('uses Windows desktop as default download directory', () {
      expect(
        resolveDefaultDownloadDirectory(
          environment: const {'USERPROFILE': r'C:\Users\brian'},
          downloadsDirectory: r'D:\Downloads',
          supportDirectory: r'D:\AppSupport',
          isWindows: true,
        ),
        r'C:\Users\brian\Desktop',
      );
    });

    test('falls back to downloads and support directories', () {
      expect(
        resolveDefaultDownloadDirectory(
          environment: const {},
          downloadsDirectory: r'D:\Downloads',
          supportDirectory: r'D:\AppSupport',
          isWindows: true,
        ),
        r'D:\Downloads',
      );

      expect(
        resolveDefaultDownloadDirectory(
          environment: const {},
          downloadsDirectory: null,
          supportDirectory: r'D:\AppSupport',
          isWindows: true,
        ),
        r'D:\AppSupport',
      );
    });
  });
}
