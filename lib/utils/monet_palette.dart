import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// Cover-derived colour roles modelled on folia-major's Monet theme
/// (`generateBuiltinDualTheme`, dark variant):
///
/// * [primary] – near-white ink tinted toward the cover's lead hue (lyrics,
///   title, artist);
/// * [secondary] – a quieter tone between the lead and accent hues (album,
///   romanization);
/// * [accent] – a saturated companion hue (word glow, progress, bloom);
/// * [background] – a deep tinted ground (veil, text shadow).
///
/// Unlike folia, every choice is deterministic so a song always gets the same
/// colours. Each text role is pushed along its lightness axis until it clears
/// a contrast floor against [backdrop], so it keeps its hue instead of
/// collapsing into plain white.
@immutable
class MonetPalette {
  const MonetPalette({
    required this.primary,
    required this.secondary,
    required this.accent,
    required this.background,
  });

  static const fallback = MonetPalette(
    primary: Color(0xFFF2F2F4),
    secondary: Color(0xFFB4B8C2),
    accent: Color(0xFF9DB4E8),
    background: Color(0xFF14161C),
  );

  final Color primary;
  final Color secondary;
  final Color accent;
  final Color background;

  static const double primaryMinContrast = 9;
  static const double accentMinContrast = 3.2;
  static const double secondaryMinContrast = 4.5;

  /// Share of [background] the player paints over the blurred cover; used to
  /// estimate the backdrop the text actually sits on.
  static const double veilStrength = 0.4;

  static const double _minSupportSaturation = 0.15;
  static const double _minSupportHueDistance = 25;
  static const double _maxSupportHueDistance = 160;
  static const double _neutralSaturation = 0.08;
  static const double _monochromeSaturation = 0.18;

  /// [coverColors] should lead with the cover's dominant colour.
  factory MonetPalette.fromCoverColors(List<Color> coverColors) {
    if (coverColors.isEmpty) return fallback;

    final swatches = [
      for (final color in coverColors) HSLColor.fromColor(color),
    ];
    final base = _pickBase(swatches);
    final isNeutral = base.saturation < _neutralSaturation;
    final supportHue = _pickSupportHue(swatches, base);
    final accentHue =
        supportHue ??
        (base.saturation < _monochromeSaturation
            ? base.hue
            : _normalizeHue(base.hue + 30));

    // Background: a deep ground that reads calmer for a washed-out cover.
    final coverWeight = 0.55 + 0.45 * (base.saturation / 0.7).clamp(0.0, 1.0);
    final background =
        HSLColor.fromAHSL(
          1,
          base.hue,
          math.max(0.04, 0.3 * coverWeight),
          0.1,
        ).toColor();

    // The text sits on the blurred cover darkened by the player, then veiled.
    final dimmedCover =
        Color.lerp(coverColors.first, const Color(0xFF000000), 0.36)!;
    final backdrop = Color.lerp(dimmedCover, background, veilStrength)!;

    final primary = adjustLightnessForContrast(
      HSLColor.fromAHSL(1, base.hue, isNeutral ? 0.04 : 0.2, 0.93).toColor(),
      backdrop,
      primaryMinContrast,
    );

    final accentSaturation = isNeutral ? 0.14 : 0.74;
    var accent = adjustLightnessForContrast(
      HSLColor.fromAHSL(1, accentHue, accentSaturation, 0.66).toColor(),
      backdrop,
      accentMinContrast,
    );
    // A monochrome accent can land on top of the primary ink; rotate it away.
    if (!isNeutral &&
        hueDistance(accentHue, base.hue) < 15 &&
        contrastRatio(accent, primary) < 1.3) {
      accent = adjustLightnessForContrast(
        HSLColor.fromAHSL(
          1,
          _normalizeHue(accentHue + 40),
          accentSaturation,
          0.66,
        ).toColor(),
        backdrop,
        accentMinContrast,
      );
    }

    final secondary = adjustLightnessForContrast(
      HSLColor.fromAHSL(
        1,
        _lerpHue(base.hue, accentHue, 0.4),
        isNeutral ? 0.06 : 0.3,
        0.7,
      ).toColor(),
      backdrop,
      secondaryMinContrast,
    );

    return MonetPalette(
      primary: primary,
      secondary: secondary,
      accent: accent,
      background: background,
    );
  }

  /// Prefers colours that are both saturated and mid-lightness: those carry
  /// the cover's identity, while near-black / near-white pixels only describe
  /// its background.
  static double _coverColorScore(HSLColor color) {
    return color.saturation *
        math.max(0, 1 - (color.lightness - 0.5).abs() * 1.2);
  }

  static HSLColor _pickBase(List<HSLColor> swatches) {
    var best = swatches.first;
    for (final candidate in swatches) {
      if (_coverColorScore(candidate) > _coverColorScore(best)) {
        best = candidate;
      }
    }
    return _coverColorScore(best) > 0.02 ? best : swatches.first;
  }

  static double? _pickSupportHue(List<HSLColor> swatches, HSLColor base) {
    for (final candidate in swatches) {
      if (candidate.saturation < _minSupportSaturation) continue;
      final distance = hueDistance(candidate.hue, base.hue);
      if (distance >= _minSupportHueDistance &&
          distance <= _maxSupportHueDistance) {
        return candidate.hue;
      }
    }
    return null;
  }

  static double hueDistance(double a, double b) {
    final distance = (_normalizeHue(a) - _normalizeHue(b)).abs();
    return math.min(distance, 360 - distance);
  }

  static double contrastRatio(Color a, Color b) {
    final luminanceA = a.computeLuminance();
    final luminanceB = b.computeLuminance();
    final lighter = math.max(luminanceA, luminanceB);
    final darker = math.min(luminanceA, luminanceB);
    return (lighter + 0.05) / (darker + 0.05);
  }

  /// Walks [color]'s lightness away from [background] until [minRatio] is
  /// met, keeping hue and saturation. Returns the best candidate when the
  /// floor is unreachable.
  static Color adjustLightnessForContrast(
    Color color,
    Color background,
    double minRatio,
  ) {
    const step = 0.02;
    const maxSteps = 50;
    final hsl = HSLColor.fromColor(color);
    final direction = background.computeLuminance() > 0.35 ? -1 : 1;

    var best = color;
    var bestRatio = contrastRatio(color, background);
    for (var index = 0; index <= maxSteps; index++) {
      final lightness = (hsl.lightness + direction * step * index).clamp(
        0.0,
        1.0,
      );
      final candidate = hsl.withLightness(lightness).toColor();
      final ratio = contrastRatio(candidate, background);
      if (ratio > bestRatio) {
        bestRatio = ratio;
        best = candidate;
      }
      if (ratio >= minRatio) return candidate;
      if (index > 0 && (lightness == 0 || lightness == 1)) break;
    }
    return best;
  }

  static double _normalizeHue(double hue) => ((hue % 360) + 360) % 360;

  /// Interpolates along the shorter arc.
  static double _lerpHue(double from, double to, double amount) {
    final delta = ((to - from + 540) % 360) - 180;
    return _normalizeHue(from + delta * amount);
  }

  @override
  bool operator ==(Object other) {
    return other is MonetPalette &&
        other.primary == primary &&
        other.secondary == secondary &&
        other.accent == accent &&
        other.background == background;
  }

  @override
  int get hashCode => Object.hash(primary, secondary, accent, background);
}
