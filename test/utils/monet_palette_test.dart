import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:verse/utils/monet_palette.dart';

void main() {
  group('MonetPalette', () {
    test('falls back when the cover has no colours', () {
      expect(MonetPalette.fromCoverColors(const []), MonetPalette.fallback);
    });

    test('gives each role its own colour, tinted by the cover', () {
      final palette = MonetPalette.fromCoverColors(const [
        Color(0xFF2F6FD0), // saturated blue: the lead hue
        Color(0xFF4A9C5A), // muted green: the support hue
      ]);

      final roles = {
        palette.primary,
        palette.secondary,
        palette.accent,
        palette.background,
      };
      expect(roles, hasLength(4));

      final primary = HSLColor.fromColor(palette.primary);
      expect(primary.lightness, greaterThan(0.85));
      expect(primary.saturation, greaterThan(0.05));
      expect(
        MonetPalette.hueDistance(primary.hue, 216),
        lessThan(10),
        reason: 'primary ink keeps the lead hue',
      );
      expect(
        MonetPalette.hueDistance(HSLColor.fromColor(palette.accent).hue, 132),
        lessThan(10),
        reason: 'accent uses the cover support hue',
      );
    });

    test('text roles clear their contrast floors on a dark backdrop', () {
      final palette = MonetPalette.fromCoverColors(const [Color(0xFF7A2E3B)]);
      final backdrop =
          Color.lerp(
            Color.lerp(const Color(0xFF7A2E3B), const Color(0xFF000000), 0.36)!,
            palette.background,
            MonetPalette.veilStrength,
          )!;

      expect(
        MonetPalette.contrastRatio(palette.primary, backdrop),
        greaterThanOrEqualTo(MonetPalette.primaryMinContrast),
      );
      expect(
        MonetPalette.contrastRatio(palette.secondary, backdrop),
        greaterThanOrEqualTo(MonetPalette.secondaryMinContrast),
      );
      expect(
        MonetPalette.contrastRatio(palette.accent, backdrop),
        greaterThanOrEqualTo(MonetPalette.accentMinContrast),
      );
    });

    test('a bright cover still yields readable light ink', () {
      final palette = MonetPalette.fromCoverColors(const [Color(0xFFF4F1E8)]);

      expect(
        palette.primary.computeLuminance(),
        greaterThan(palette.background.computeLuminance()),
      );
      expect(HSLColor.fromColor(palette.primary).saturation, lessThan(0.1));
    });
  });
}
