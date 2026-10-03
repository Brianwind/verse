import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'fluid_background.dart';
import 'lyrics/amll_db_client.dart';
import 'lyrics/lyric_models.dart';
import 'lyrics/lyric_resolver.dart';
import 'lyrics/lyric_source.dart';
import 'lyrics/playback_clock.dart';
import 'lyrics/qq_lyric_client.dart';
import 'lyrics/timed_lyric_text.dart';
import 'netease_api/netease_music_api.dart';
import 'player_model.dart';
import 'utils/lyric_visibility.dart';
import 'utils/monet_palette.dart';

typedef LyricsLoader = Future<SongLyricWrap> Function(String songId);

class LyricsView extends StatefulWidget {
  const LyricsView({
    super.key,
    this.songId,
    this.song,
    this.themeColors,
    this.position,
    this.lyricsLoader,
    this.amllLyricsLoader,
    this.qqLyricsLoader,
  });

  final String? songId;
  final Song2? song;
  final ImageThemeColors? themeColors;
  final ValueListenable<Duration>? position;
  final LyricsLoader? lyricsLoader;
  final AmllLyricsLoader? amllLyricsLoader;
  final QqLyricsLoader? qqLyricsLoader;

  @override
  State<LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends State<LyricsView>
    with SingleTickerProviderStateMixin {
  bool _loading = false;
  LyricDocument _document = LyricDocument.empty;
  int _currentLyricIndex = -1;
  int _loadGeneration = 0;

  ValueListenable<Duration>? _position;
  VoidCallback? _positionListener;
  PlaybackClock? _ownedPlaybackClock;

  final List<double> _lineHeights = [];
  List<_LineTransform> _lineTransforms = [];
  double _containerHeight = 0;
  double _containerWidth = 0;
  bool _shouldTransit = true;

  // Monet 的景深：前后句轻微模糊。
  static const bool _lyricBlur = true;
  static const bool _scrollingMode = false;
  int _scrollingFocusLine = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_fetchLyrics());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ensurePositionSource();
  }

  @override
  void didUpdateWidget(covariant LyricsView oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.position != widget.position) {
      _detachPositionSource();
      _ownedPlaybackClock?.dispose();
      _ownedPlaybackClock = null;
      _ensurePositionSource();
    }

    if (_effectiveSongId(oldWidget) != _effectiveSongId(widget)) {
      unawaited(_fetchLyrics());
    } else if (oldWidget.themeColors != widget.themeColors) {
      _scheduleTransformRecalculation();
    }
  }

  void _ensurePositionSource() {
    if (_position != null) return;

    final providedPosition = widget.position;
    if (providedPosition != null) {
      _attachPositionSource(providedPosition);
      return;
    }

    final player = context.read<PlayerModel>();
    final clock = PlaybackClock(player: player.audioPlayer, vsync: this);
    _ownedPlaybackClock = clock;
    _attachPositionSource(clock);
  }

  void _attachPositionSource(ValueListenable<Duration> position) {
    _position = position;
    _positionListener = _handlePositionChanged;
    position.addListener(_positionListener!);
    _handlePositionChanged();
  }

  void _detachPositionSource() {
    final position = _position;
    final listener = _positionListener;
    if (position != null && listener != null) {
      position.removeListener(listener);
    }
    _position = null;
    _positionListener = null;
  }

  Future<void> _fetchLyrics() async {
    final generation = ++_loadGeneration;
    final songId = _effectiveSongId(widget);

    if (songId == null || songId.isEmpty) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _document = LyricDocument.empty;
        _currentLyricIndex = -1;
        _lineTransforms = [];
      });
      return;
    }

    setState(() {
      _loading = true;
      _document = LyricDocument.empty;
      _currentLyricIndex = -1;
      _lineTransforms = [];
    });

    try {
      final resolver = LyricResolver(
        neteaseLoader: widget.lyricsLoader ?? NeteaseMusicApi().songLyricNew,
        amllLoader: widget.amllLyricsLoader ?? AmllDbClient.instance.fetch,
        qqLoader: widget.qqLyricsLoader ?? QqLyricClient.instance.fetch,
      );
      final songContext =
          widget.song == null
              ? LyricSongContext.idOnly(songId)
              : LyricSongContext.fromSong(widget.song!);
      final document = await resolver.load(songContext);
      if (!mounted ||
          generation != _loadGeneration ||
          _effectiveSongId(widget) != songId) {
        return;
      }

      setState(() {
        _loading = false;
        _document = document;
        _currentLyricIndex = document.lineIndexAt(
          _position?.value ?? Duration.zero,
        );
        _scrollingFocusLine = _currentLyricIndex.clamp(
          0,
          document.lines.isEmpty ? 0 : document.lines.length - 1,
        );
        _lineTransforms = [];
        _shouldTransit = false;
      });
      _scheduleTransformRecalculation();
    } catch (error) {
      debugPrint('获取歌词失败: $error');
      if (!mounted ||
          generation != _loadGeneration ||
          _effectiveSongId(widget) != songId) {
        return;
      }
      setState(() {
        _loading = false;
        _document = LyricDocument.empty;
        _currentLyricIndex = -1;
        _lineTransforms = [];
      });
    }
  }

  static String? _effectiveSongId(LyricsView widget) {
    return widget.song?.id ?? widget.songId;
  }

  void _handlePositionChanged() {
    if (!mounted || _document.isEmpty || _position == null) return;

    final newIndex = _document.lineIndexAt(_position!.value);
    if (newIndex == _currentLyricIndex) return;

    setState(() {
      _currentLyricIndex = newIndex;
      _shouldTransit = true;
      if (!_scrollingMode && newIndex >= 0) {
        _scrollingFocusLine = newIndex;
      }
    });
    _recalculateLineTransforms();
  }

  // Monet 风格排版：所有行按当前句字号排版，非当前句通过缩放缩小，避免切换时重新换行。
  static const double _lyricFontSize = 32;
  static const double _lyricLineHeight = 1.18;
  static const double _textPaddingTop = 8;
  static const double _textPaddingBottom = 14;
  static const double _alternatePaddingTop = 6;
  static const int _inactiveMaxLines = 2;
  static const int _windowRadius = 4;
  static const double _focusCenter = 0.46;
  static const double _inactiveBaseScale = 0.78;

  MonetPalette get _palette =>
      widget.themeColors?.monet ?? MonetPalette.fallback;

  TextStyle get _lyricStyle => DefaultTextStyle.of(context).style.copyWith(
    fontSize: _lyricFontSize,
    fontWeight: FontWeight.w600,
    height: _lyricLineHeight,
  );

  TextStyle get _romanizationStyle => DefaultTextStyle.of(
    context,
  ).style.copyWith(fontSize: 17, fontWeight: FontWeight.w500, height: 1.3);

  TextStyle get _translationStyle => DefaultTextStyle.of(
    context,
  ).style.copyWith(fontSize: 18, fontWeight: FontWeight.w500, height: 1.28);

  double _measureText(
    String text,
    TextStyle style,
    double maxWidth, {
    int? maxLines,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: Directionality.of(context),
      textScaler:
          MediaQuery.maybeOf(context)?.textScaler ?? TextScaler.noScaling,
      maxLines: maxLines,
      ellipsis: maxLines == null ? null : '…',
    )..layout(maxWidth: maxWidth);
    final height = painter.height;
    painter.dispose();
    return height;
  }

  void _measureLineHeights(int activeIndex) {
    _lineHeights.clear();
    if (_document.isEmpty || _containerWidth <= 0) return;

    final maxTextWidth = (_containerWidth - 32).clamp(0.0, double.infinity);
    for (var index = 0; index < _document.lines.length; index++) {
      final line = _document.lines[index];
      final isActive = index == activeIndex;
      var height =
          _textPaddingTop +
          _measureText(
            line.text,
            _lyricStyle,
            maxTextWidth,
            maxLines: isActive ? null : _inactiveMaxLines,
          ) +
          _textPaddingBottom;
      if (isActive) {
        for (final (text, style) in _alternateTexts(line)) {
          height +=
              _alternatePaddingTop + _measureText(text, style, maxTextWidth);
        }
      }
      _lineHeights.add(height);
    }
  }

  /// 当前句下方依次显示罗马音、翻译（与原文相同或为空时省略）。
  List<(String, TextStyle)> _alternateTexts(LyricLine line) {
    final original = line.text.trim();
    final result = <(String, TextStyle)>[];
    final romanization = line.romanization?.trim();
    if (romanization != null &&
        romanization.isNotEmpty &&
        romanization != original) {
      result.add((romanization, _romanizationStyle));
    }
    final translation = line.translation?.trim();
    if (translation != null &&
        translation.isNotEmpty &&
        translation != original) {
      result.add((translation, _translationStyle));
    }
    return result;
  }

  void _recalculateLineTransforms() {
    if (!mounted ||
        _document.isEmpty ||
        _containerHeight <= 0 ||
        _containerWidth <= 0) {
      return;
    }

    final lineCount = _document.lines.length;
    var anchor = _scrollingMode ? _scrollingFocusLine : _currentLyricIndex;
    anchor = anchor.clamp(0, lineCount - 1);
    // 尚未到第一句时没有当前句，前奏阶段所有行都是等待态。
    final activeIndex = _currentLyricIndex;

    _measureLineHeights(activeIndex);
    if (_lineHeights.length != lineCount) return;

    final transforms = List<_LineTransform>.generate(lineCount, (index) {
      return _toneFor(index: index, anchor: anchor, activeIndex: activeIndex);
    });
    final scaledHeights = [
      for (var index = 0; index < lineCount; index++)
        _lineHeights[index] * transforms[index].scale,
    ];

    double gapBetween(int upper, int lower) {
      final touchesActive = upper == activeIndex || lower == activeIndex;
      return touchesActive
          ? (_lyricFontSize * 0.49).clamp(18.0, double.infinity)
          : (_lyricFontSize * 0.38).clamp(14.0, double.infinity);
    }

    final tops = List<double>.filled(lineCount, 0);
    tops[anchor] = _containerHeight * _focusCenter - scaledHeights[anchor] / 2;
    for (var index = anchor + 1; index < lineCount; index++) {
      tops[index] =
          tops[index - 1] +
          scaledHeights[index - 1] +
          gapBetween(index - 1, index);
    }
    for (var index = anchor - 1; index >= 0; index--) {
      tops[index] =
          tops[index + 1] - scaledHeights[index] - gapBetween(index, index + 1);
    }

    setState(() {
      _lineTransforms = [
        for (var index = 0; index < lineCount; index++)
          transforms[index].copyWith(top: tops[index]),
      ];
    });
  }

  /// 对应 folia Monet 的 resolveLineTone：当前句清晰完整，前后句缩小、变淡、轻微模糊。
  _LineTransform _toneFor({
    required int index,
    required int anchor,
    required int activeIndex,
  }) {
    if (index == activeIndex) {
      return const _LineTransform(
        top: 0,
        scale: 1,
        opacity: 1,
        blur: 0,
        status: _LineStatus.active,
      );
    }

    final distance = (index - anchor).abs().clamp(1, 1 << 20);
    final waiting = activeIndex < 0 || index > activeIndex;
    final scale = (_inactiveBaseScale * _pow(0.9, distance - 1)).clamp(
      0.68,
      0.92,
    );
    final opacity =
        waiting
            ? (0.72 - (distance - 1) * 0.18).clamp(0.36, 0.72)
            : (0.52 - (distance - 1) * 0.12).clamp(0.28, 0.52);
    final blur =
        !_lyricBlur
            ? 0.0
            : waiting
            ? (distance == 1 ? 0.7 : 1.8 + (distance - 2) * 0.8)
            : 1.1 + (distance - 1) * 0.7;
    return _LineTransform(
      top: 0,
      scale: scale.toDouble(),
      opacity: opacity.toDouble(),
      blur: blur,
      status: waiting ? _LineStatus.waiting : _LineStatus.passed,
    );
  }

  static double _pow(double base, int exponent) {
    var result = 1.0;
    for (var i = 0; i < exponent; i++) {
      result *= base;
    }
    return result;
  }

  void _scheduleTransformRecalculation() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _recalculateLineTransforms();
      }
    });
  }

  void _onContainerSizeChanged(Size size) {
    if (_containerHeight == size.height && _containerWidth == size.width) {
      return;
    }

    _containerHeight = size.height;
    _containerWidth = size.width;
    _shouldTransit = false;
    _scheduleTransformRecalculation();
  }

  @override
  void dispose() {
    _loadGeneration++;
    _detachPositionSource();
    _ownedPlaybackClock?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_document.isEmpty) {
      return Center(
        child: Text(
          '暂无歌词',
          style: TextStyle(color: _palette.primary.withValues(alpha: 0.72)),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        _onContainerSizeChanged(
          Size(constraints.maxWidth, constraints.maxHeight),
        );

        // 与 Monet 歌词轨一致：上下边缘渐隐。
        return ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (bounds) {
            return const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.transparent,
                Colors.black,
                Colors.black,
                Colors.transparent,
              ],
              stops: [0.0, 0.11, 0.88, 1.0],
            ).createShader(bounds);
          },
          child: ClipRect(
            child: SizedBox.expand(
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  for (var index = 0; index < _document.lines.length; index++)
                    _buildLyricLine(index),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildLyricLine(int index) {
    if (index >= _lineTransforms.length) {
      return const SizedBox.shrink();
    }

    final line = _document.lines[index];
    final transform = _lineTransforms[index];
    final isCurrentLyric = transform.status == _LineStatus.active;
    final visibilityOpacity = lyricLineVisibilityOpacity(
      index: index,
      currentIndex: _currentLyricIndex,
      lineCount: _document.lines.length,
      radius: _windowRadius,
    );

    // folia Monet 配色：歌词用封面色调的主色墨水，未唱部分半透明；
    // 已唱的逐字句保持实色，待唱句更淡；正在唱的字带强调色光晕。
    final palette = _palette;
    final style = _lyricStyle;
    final position = _position;

    final Widget lineText;
    if (isCurrentLyric && position != null) {
      lineText = RepaintBoundary(
        child: TimedLyricText(
          line: line,
          position: position,
          style: style.copyWith(
            shadows: [
              Shadow(
                color: palette.background.withValues(alpha: 0.22),
                offset: const Offset(0, 14),
                blurRadius: 34,
              ),
            ],
          ),
          baseColor: palette.primary.withValues(alpha: 0.34),
          highlightColor: palette.primary.withValues(alpha: 0.98),
          glowColor: Color.lerp(
            palette.primary,
            palette.accent,
            0.55,
          )!.withValues(alpha: 0.88),
        ),
      );
    } else {
      final double baseAlpha;
      if (transform.status == _LineStatus.waiting) {
        baseAlpha = 0.46;
      } else {
        baseAlpha = line.words.isNotEmpty ? 0.98 : 0.36;
      }
      lineText = Text(
        line.text,
        style: style.copyWith(
          color: palette.primary.withValues(alpha: baseAlpha),
        ),
        textAlign: TextAlign.left,
        maxLines: _inactiveMaxLines,
        overflow: TextOverflow.ellipsis,
      );
    }

    // 原歌词 - 罗马音 - 翻译；只有当前句显示罗马音和翻译。
    final alternates = isCurrentLyric ? _alternateTexts(line) : const [];
    final lineBody = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(
            top: _textPaddingTop,
            bottom: _textPaddingBottom,
          ),
          child: lineText,
        ),
        for (final (index, (text, altStyle)) in alternates.indexed)
          Padding(
            padding: const EdgeInsets.only(top: _alternatePaddingTop),
            child: _FadeSlideIn(
              key: ValueKey('alt-${line.start.inMilliseconds}-$text'),
              child: Text(
                text,
                // 第一行副轨（通常为罗马音）略亮，第二行再降一档。
                style: altStyle.copyWith(
                  color: palette.primary.withValues(
                    alpha: index == 0 ? 0.68 : 0.68 * 0.82,
                  ),
                ),
              ),
            ),
          ),
      ],
    );

    final lineContent =
        transform.blur > 0
            ? ImageFiltered(
              imageFilter: ImageFilter.blur(
                sigmaX: transform.blur,
                sigmaY: transform.blur,
              ),
              child: lineBody,
            )
            : lineBody;

    return Positioned(
      key: ValueKey('lyric-line-${line.start.inMilliseconds}-${line.text}'),
      left: 0,
      right: 0,
      top: 0,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(end: transform.top),
        duration:
            _shouldTransit ? const Duration(milliseconds: 500) : Duration.zero,
        curve: Curves.easeOutCubic,
        builder: (context, top, child) {
          return Transform.translate(offset: Offset(0, top), child: child);
        },
        child: AnimatedOpacity(
          opacity: transform.opacity * visibilityOpacity,
          duration: const Duration(milliseconds: 500),
          child: AnimatedScale(
            scale: transform.scale,
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topLeft,
            child: IgnorePointer(
              ignoring: visibilityOpacity == 0,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  context.read<PlayerModel>().seek(line.start);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: lineContent,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum _LineStatus { waiting, active, passed }

class _LineTransform {
  const _LineTransform({
    required this.top,
    required this.scale,
    required this.opacity,
    required this.blur,
    required this.status,
  });

  final double top;
  final double scale;
  final double opacity;
  final double blur;
  final _LineStatus status;

  _LineTransform copyWith({double? top}) {
    return _LineTransform(
      top: top ?? this.top,
      scale: scale,
      opacity: opacity,
      blur: blur,
      status: status,
    );
  }
}

/// 罗马音/翻译出现时的淡入上移（对应 Monet 的 opacity 0→1, y 8→0, 280ms）。
class _FadeSlideIn extends StatelessWidget {
  const _FadeSlideIn({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 8 * (1 - value)),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}
