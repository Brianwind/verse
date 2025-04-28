import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:ui';
import 'dart:async';
import 'netease_api/netease_music_api.dart';
import 'player_model.dart';
import 'fluid_background.dart'; // 导入以使用ImageThemeColors类型

class LyricsView extends StatefulWidget {
  final String? songId;
  final ImageThemeColors? themeColors; // 添加主题颜色参数

  const LyricsView({super.key, this.songId, this.themeColors});

  @override
  State<LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends State<LyricsView> {
  bool _loading = false;
  String? _lyrics;
  Map<int, String> _parsedLyrics = {};
  int _currentLyricIndex = -1;
  StreamSubscription? _positionSubscription;

  // 歌词高度和状态属性
  final List<double> _lineHeights = [];
  double _containerHeight = 0;
  double _containerWidth = 0;
  bool _shouldTransit = true;
  double _currentLyricAlignmentPercentage = 50; // 居中位置百分比
  List<Map<String, dynamic>> _lineTransforms = [];
  bool _lyricFade = true; // 渐变效果
  bool _lyricZoom = true; // 缩放效果
  bool _lyricBlur = true; // 模糊效果

  // 滚动相关的属性
  bool _scrollingMode = false;
  int _scrollingFocusLine = 0;

  @override
  void initState() {
    super.initState();
    _fetchLyrics();

    // 监听播放进度以实现歌词滚动
    final player = Provider.of<PlayerModel>(context, listen: false);
    _positionSubscription = player.audioPlayer.positionStream.listen(
      _updateLyricPosition,
    );
  }

  @override
  void didUpdateWidget(LyricsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.songId != oldWidget.songId) {
      _fetchLyrics();
    }
  }

  Future<void> _fetchLyrics() async {
    if (widget.songId == null) return;

    setState(() {
      _loading = true;
      _lyrics = null;
      _parsedLyrics = {};
    });

    try {
      final result = await NeteaseMusicApi().songLyric(widget.songId!);
      if (result.lrc?.lyric != null) {
        setState(() {
          _lyrics = result.lrc!.lyric;
          _parsedLyrics = _parseLyrics(_lyrics!);
        });
      } else {
        setState(() {
          _lyrics = null;
          _parsedLyrics = {};
        });
      }
    } catch (e) {
      debugPrint('获取歌词失败: $e');
      setState(() {
        _lyrics = null;
        _parsedLyrics = {};
      });
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  Map<int, String> _parseLyrics(String lyrics) {
    final Map<int, String> result = {};
    final lines = lyrics.split('\n');
    // 支持 [00:00.00]、[00:00:00]、[00:00.00-1]、[00:00:00-1] 等格式
    final RegExp pattern = RegExp(
      r'^\[(\d{2}):(\d{2})[\.:](\d{2,3})(?:-\d+)?\]\s*(.*)',
    );
    int lastTime = 0;
    for (final line in lines) {
      final match = pattern.firstMatch(line);
      if (match != null) {
        final minutes = int.parse(match.group(1)!);
        final seconds = int.parse(match.group(2)!);
        final milliseconds = int.parse(
          match.group(3)!.padRight(3, '0').substring(0, 3),
        );
        final content = match.group(4)?.trim() ?? '';
        final timeInMilliseconds =
            minutes * 60 * 1000 + seconds * 1000 + milliseconds;
        result[timeInMilliseconds] = content;
        lastTime = timeInMilliseconds;
      } else if (line.trim().isNotEmpty) {
        // 没有时间标签的行，顺延到上一个时间戳后10ms
        lastTime += 10;
        result[lastTime] = line.trim();
      }
    }
    return result;
  }

  void _updateLyricPosition(Duration position) {
    // 根据当前播放时间找到对应的歌词
    final currentTime = position.inMilliseconds;

    // 找到当前时间之前的最后一句歌词
    int? currentLyricTime;

    for (final time in _parsedLyrics.keys) {
      if (time <= currentTime &&
          (currentLyricTime == null || time > currentLyricTime)) {
        currentLyricTime = time;
      }
    }

    if (currentLyricTime != null) {
      final newIndex = _parsedLyrics.keys.toList().indexOf(currentLyricTime);
      if (newIndex != _currentLyricIndex) {
        setState(() {
          _currentLyricIndex = newIndex;
          _shouldTransit = true;
          if (!_scrollingMode) {
            _scrollingFocusLine = newIndex;
          }
        });

        // 不再使用 ScrollController 滚动，而是通过重新计算位置实现
        _recalculateLineTransforms();
      }
    }
  }

  // 计算行的高度
  void _measureLineHeights(BuildContext context) {
    if (_parsedLyrics.isEmpty) return;

    final sortedTimes = _parsedLyrics.keys.toList()..sort();
    _lineHeights.clear();

    // 估算每行高度，实际实现应该测量真实渲染高度
    for (final time in sortedTimes) {
      final lyric = _parsedLyrics[time]!;

      // 估算文本高度，这里简化处理
      final isCurrentLyric = sortedTimes.indexOf(time) == _currentLyricIndex;
      final fontSize = isCurrentLyric ? 30.0 : 28.0;

      // 简单估算高度 = 字体大小 + 上下内边距
      final height = fontSize + 24.0; // 上下各12的内边距
      _lineHeights.add(height);
    }
  }

  // 重新计算每行的变换信息
  void _recalculateLineTransforms() {
    if (_parsedLyrics.isEmpty) return;

    final sortedTimes = _parsedLyrics.keys.toList()..sort();
    _measureLineHeights(context);

    // 准备变换数据
    final newLineTransforms = List.generate(
      sortedTimes.length,
      (_) => <String, dynamic>{},
    );
    final space = 30.0 * 1.2; // 行间距

    // 计算当前行的位置
    int current = _scrollingMode ? _scrollingFocusLine : _currentLyricIndex;
    current = current.clamp(0, sortedTimes.length - 1);

    // 函数：根据与当前行的偏移计算缩放比例
    double scaleByOffset(int offset) {
      if (!_lyricZoom) return 1.0;
      offset = offset.abs();
      return offset <= 0 ? 1.0 : (1.0 - offset * 0.08).clamp(0.7, 1.0);
    }

    // 函数：根据与当前行的偏移计算不透明度
    double opacityByOffset(int offset) {
      if (!_lyricFade) return 1.0;
      offset = offset.abs();
      if (offset <= 1) return 1.0;
      return (1.0 - 0.25 * (offset - 1)).clamp(0.0, 1.0);
    }

    // 函数：根据与当前行的偏移计算模糊程度
    double blurByOffset(int offset) {
      if (!_lyricBlur) return 0.0;
      offset = offset.abs();
      if (offset == 0) return 0.0;
      // 计算模糊值，随着与当前行距离增加而增加
      return (offset * 1.5).clamp(0.0, 6.0);
    }

    // 计算当前行位置
    final currentLineTop =
        _containerHeight * (_currentLyricAlignmentPercentage / 100) -
        _lineHeights[current] / 2;

    // 设置当前行的变换
    newLineTransforms[current] = {
      'top': currentLineTop,
      'scale': 1.0,
      'opacity': 1.0,
      'blur': 0.0, // 当前行不添加模糊
      'delay': _shouldTransit ? 200 : 0, // 减少延迟时间，原为300
    };

    // 计算当前行之前的所有行
    double previousBottom = currentLineTop;
    for (int i = current - 1; i >= 0; i--) {
      final scale = scaleByOffset(current - i);
      final opacity = opacityByOffset(current - i);
      final blur = blurByOffset(current - i);
      final scaledHeight = _lineHeights[i] * scale;

      previousBottom -= (scaledHeight + space);

      newLineTransforms[i] = {
        'top': previousBottom,
        'scale': scale,
        'opacity': opacity,
        'blur': blur,
        'delay': _shouldTransit ? 200 + (current - i) * 30 : 0, // 减少延迟时间和递增值
      };
    }

    // 计算当前行之后的所有行
    double nextTop = currentLineTop + _lineHeights[current] + space;
    for (int i = current + 1; i < sortedTimes.length; i++) {
      final scale = scaleByOffset(i - current);
      final opacity = opacityByOffset(i - current);
      final blur = blurByOffset(i - current);

      newLineTransforms[i] = {
        'top': nextTop,
        'scale': scale,
        'opacity': opacity,
        'blur': blur,
        'delay': _shouldTransit ? 200 + (i - current) * 30 : 0, // 减少延迟时间和递增值
      };

      nextTop += _lineHeights[i] * scale + space;
    }

    // 只有当组件挂载时才更新状态
    if (mounted) {
      setState(() {
        _lineTransforms = newLineTransforms;
      });
    }
  }

  // 处理容器大小变化
  void _onContainerSizeChanged(Size size) {
    if (_containerHeight != size.height || _containerWidth != size.width) {
      _containerHeight = size.height;
      _containerWidth = size.width;
      _shouldTransit = false; // 大小变化时不需要过渡效果

      // 使用WidgetsBinding.instance.addPostFrameCallback
      // 确保在当前帧渲染完成后再更新状态
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _recalculateLineTransforms();
        }
      });
    }
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_lyrics == null) {
      return Center(
        child: Text(
          '暂无歌词',
          style: TextStyle(
            color:
                widget.themeColors?.textColor ??
                Theme.of(context).textTheme.bodyMedium?.color,
          ),
        ),
      );
    }

    final sortedTimes = _parsedLyrics.keys.toList()..sort();

    return LayoutBuilder(
      builder: (context, constraints) {
        _onContainerSizeChanged(
          Size(constraints.maxWidth, constraints.maxHeight),
        );

        return Container(
          height: double.infinity,
          decoration: BoxDecoration(
            color: Colors.transparent, // 将背景改为透明
            borderRadius: BorderRadius.circular(16),
          ),
          // 使用Stack替代ListView，采用绝对定位
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              for (int i = 0; i < sortedTimes.length; i++)
                _buildLyricLine(sortedTimes[i], i),
            ],
          ),
        );
      },
    );
  }

  // 构建单个歌词行
  Widget _buildLyricLine(int time, int index) {
    final lyric = _parsedLyrics[time]!;
    final isCurrentLyric = index == _currentLyricIndex;

    // 如果尚未计算变换，返回空容器
    if (_lineTransforms.isEmpty || index >= _lineTransforms.length) {
      return Container();
    }

    final transform = _lineTransforms[index];
    final blurValue = transform['blur'] as double? ?? 0.0;

    // 使用主题颜色
    final Color currentLyricColor =
        widget.themeColors?.textColor ?? Theme.of(context).colorScheme.primary;
    final Color normalLyricColor =
        widget.themeColors?.textColor.withOpacity(0.8) ??
        Theme.of(context).textTheme.bodyMedium?.color ??
        Colors.white70;

    return AnimatedPositioned(
      top: transform['top'] as double? ?? 0,
      left: 0,
      right: 0,
      duration: Duration(milliseconds: 500),
      curve: Curves.easeOutCubic,
      child: AnimatedOpacity(
        opacity: transform['opacity'] as double? ?? 1.0,
        duration: Duration(milliseconds: 500),
        child: AnimatedScale(
          scale: transform['scale'] as double? ?? 1.0,
          duration: Duration(milliseconds: 500),
          alignment: Alignment.centerLeft, // 设置缩放锚点为左侧中心
          child: GestureDetector(
            onTap: () {
              // 点击歌词跳转播放
              final player = Provider.of<PlayerModel>(context, listen: false);
              player.seek(Duration(milliseconds: time));
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              // 使用 ImageFiltered 添加高斯模糊效果
              child: ImageFiltered(
                imageFilter:
                    blurValue > 0
                        ? ImageFilter.blur(sigmaX: blurValue, sigmaY: blurValue)
                        : ImageFilter.blur(sigmaX: 0, sigmaY: 0),
                child: Text(
                  lyric,
                  style: TextStyle(
                    fontSize: isCurrentLyric ? 30 : 28,
                    fontWeight:
                        isCurrentLyric ? FontWeight.bold : FontWeight.normal,
                    color:
                        isCurrentLyric ? currentLyricColor : normalLyricColor,
                  ),
                  textAlign: TextAlign.left,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
