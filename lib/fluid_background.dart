import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:material_color_utilities/material_color_utilities.dart';

// 计算两个颜色之间的欧几里得距离的工具方法
double _calculateColorDistance(Color color1, Color color2) {
  double r = (color1.r - color2.r).toDouble();
  double g = (color1.g - color2.g).toDouble();
  double b = (color1.b - color2.b).toDouble();
  return (r * r + g * g + b * b);
}

// 返回给定颜色的较暗版本的工具方法
Color _darkenColor(Color color, double factor) {
  return Color.fromRGBO(
    (color.r * (1 - factor)).round(),
    (color.g * (1 - factor)).round(),
    (color.b * (1 - factor)).round(),
    1,
  );
}

// 提供从图片中提取的主题颜色
class ImageThemeColors {
  // 用于背景的颜色
  final List<Color> backgroundColors;

  // 用于文本的颜色 (tertiary)
  final Color textColor;

  // 主色调
  final Color primaryColor;

  // 次要色调
  final Color secondaryColor;

  // 表示颜色是否已成功提取
  final bool isValid;

  ImageThemeColors({
    required this.backgroundColors,
    required this.textColor,
    required this.primaryColor,
    required this.secondaryColor,
    this.isValid = true,
  });

  // 创建默认/回退主题颜色
  factory ImageThemeColors.fallback() {
    return ImageThemeColors(
      backgroundColors: [Colors.grey[800]!, Colors.grey[900]!, Colors.black],
      textColor: Colors.white,
      primaryColor: Colors.grey[500]!,
      secondaryColor: Colors.grey[700]!,
      isValid: false,
    );
  }
}

// 全局缓存，保存已处理过的URL对应的颜色列表
class _ColorCache {
  static final Map<String, ImageThemeColors> _cache = {};
  static final Map<String, Completer<ImageThemeColors>> _loadingCompleters = {};

  static ImageThemeColors? getThemeColors(String url) {
    return _cache[url];
  }

  static void setThemeColors(String url, ImageThemeColors colors) {
    _cache[url] = colors;

    // 如果有等待这个URL颜色的Completer，完成它
    if (_loadingCompleters.containsKey(url)) {
      _loadingCompleters[url]!.complete(colors);
      _loadingCompleters.remove(url);
    }
  }

  static bool hasThemeColors(String url) {
    return _cache.containsKey(url);
  }

  // 添加一个方法获取颜色或等待颜色加载完成
  static Future<ImageThemeColors> getThemeColorsAsync(String url) {
    // 如果颜色已经在缓存中，立即返回
    if (_cache.containsKey(url)) {
      return Future.value(_cache[url]!);
    }

    // 如果颜色正在加载中，返回相同的Completer
    if (_loadingCompleters.containsKey(url)) {
      return _loadingCompleters[url]!.future;
    }

    // 创建一个新的Completer
    final completer = Completer<ImageThemeColors>();
    _loadingCompleters[url] = completer;
    return completer.future;
  }

  // 预加载图片颜色
  static Future<void> preloadThemeColors(String url) async {
    if (_cache.containsKey(url) || _loadingCompleters.containsKey(url)) {
      return;
    }

    final completer = Completer<ImageThemeColors>();
    _loadingCompleters[url] = completer;

    // 在后台线程中提取颜色
    _extractThemeColors(url)
        .then((colors) {
          _cache[url] = colors;
          completer.complete(colors);
          _loadingCompleters.remove(url);
        })
        .catchError((error) {
          final fallbackColors = ImageThemeColors.fallback();
          _cache[url] = fallbackColors;
          completer.complete(fallbackColors);
          _loadingCompleters.remove(url);
        });
  }

  // 提取颜色并生成Material主题
  static Future<ImageThemeColors> _extractThemeColors(String url) async {
    try {
      final NetworkImage image = NetworkImage(url);

      // 先使用PaletteGenerator获取一组颜色
      final PaletteGenerator palette = await PaletteGenerator.fromImageProvider(
        image,
        size: const Size(100, 100),
        maximumColorCount: 20,
      );

      // 如果没有获取到颜色，返回默认颜色
      if (palette.paletteColors.isEmpty) {
        return ImageThemeColors.fallback();
      }

      // 创建背景颜色数组，直接使用从图片中提取的颜色
      final List<Color> backgroundColors = [];

      // 获取主色调用于主要显示和文字颜色的生成
      final dominantColor =
          palette.dominantColor?.color ?? palette.paletteColors.first.color;

      // 添加主色到背景颜色列表
      backgroundColors.add(dominantColor);

      // 从调色板中选择不同的颜色添加到背景列表
      // 尝试找到与主色有一定差异的颜色，以创建更丰富的渐变
      final otherColors =
          palette.paletteColors
              .map((e) => e.color)
              .where((color) {
                // 计算与主色的色差，选择差异适中的颜色
                double distance = _calculateColorDistance(color, dominantColor);
                return distance > 1000 && distance < 20000; // 适当的色差范围
              })
              .take(3) // 最多选择额外的3种颜色
              .toList();

      // 如果找到了其他合适的颜色，添加到背景列表
      if (otherColors.isNotEmpty) {
        backgroundColors.addAll(otherColors);
      } else {
        // 如果没有找到合适的其他颜色，添加主色的变体
        backgroundColors.add(_darkenColor(dominantColor, 0.2));
        backgroundColors.add(_darkenColor(dominantColor, 0.4));
      }

      // 确保背景颜色至少有3种
      while (backgroundColors.length < 3) {
        backgroundColors.add(_darkenColor(backgroundColors.last, 0.2));
      }

      // 使用Material Color Utilities生成文字颜色和辅助颜色
      final sourceColorARGB = _colorToARGB(dominantColor);
      final corePalette = CorePalette.of(sourceColorARGB);

      // 获取文字颜色 (tertiary) - 使用较亮的色调
      final textColor = Color(_argbToColorInt(corePalette.tertiary.get(80)));

      // 次要色调，用于强调元素
      final secondaryColor = Color(
        _argbToColorInt(corePalette.secondary.get(40)),
      );

      return ImageThemeColors(
        backgroundColors: backgroundColors,
        textColor: textColor,
        primaryColor: dominantColor,
        secondaryColor: secondaryColor,
      );
    } catch (e) {
      debugPrint('颜色提取错误: $e');
      return ImageThemeColors.fallback();
    }
  }

  // 将Flutter Color转换为ARGB int (Material Color Utilities格式)
  static int _colorToARGB(Color color) {
    return (255 << 24) | (color.red << 16) | (color.green << 8) | color.blue;
  }

  // 将ARGB int转回Flutter Color
  static int _argbToColorInt(int argb) {
    return Color.fromARGB(
      255,
      (argb >> 16) & 0xFF,
      (argb >> 8) & 0xFF,
      argb & 0xFF,
    ).value;
  }
}

class FluidBackground extends StatefulWidget {
  final String? imageUrl;
  final bool isPlaying;
  final bool staticMode;
  final Function(ImageThemeColors)? onThemeColorsExtracted;

  const FluidBackground({
    super.key,
    this.imageUrl,
    this.isPlaying = true,
    this.staticMode = true,
    this.onThemeColorsExtracted,
  });

  // 添加预加载静态方法
  static Future<void> preloadBackground(String? imageUrl) async {
    if (imageUrl != null && imageUrl.isNotEmpty) {
      await _ColorCache.preloadThemeColors(imageUrl);
    }
  }

  // 添加获取主题颜色的静态方法，供其他组件使用
  static Future<ImageThemeColors> getThemeColorsForImage(
    String? imageUrl,
  ) async {
    if (imageUrl == null || imageUrl.isEmpty) {
      return ImageThemeColors.fallback();
    }
    return await _ColorCache.getThemeColorsAsync(imageUrl);
  }

  @override
  State<FluidBackground> createState() => _FluidBackgroundState();
}

class _FluidBackgroundState extends State<FluidBackground>
    with SingleTickerProviderStateMixin {
  ImageThemeColors? _themeColors;
  bool _imageReady = false;
  bool _isLoading = false;
  NetworkImage? _backgroundImage;
  Completer<void>? _loadingCompleter;

  @override
  void initState() {
    super.initState();

    // 加载图像和颜色
    if (widget.imageUrl != null && widget.imageUrl!.isNotEmpty) {
      _processImageUrl(widget.imageUrl!);
    }
  }

  @override
  void didUpdateWidget(FluidBackground oldWidget) {
    super.didUpdateWidget(oldWidget);

    // 当图片URL改变时，重新加载图像和颜色
    if (oldWidget.imageUrl != widget.imageUrl &&
        widget.imageUrl != null &&
        widget.imageUrl!.isNotEmpty) {
      _processImageUrl(widget.imageUrl!);
    }
  }

  void _processImageUrl(String url) {
    if (_ColorCache.hasThemeColors(url)) {
      // 如果缓存中已有该URL的颜色信息，直接使用
      final cachedColors = _ColorCache.getThemeColors(url);
      setState(() {
        _themeColors = cachedColors;
        _imageReady = true;
      });

      // 使用Future.microtask确保在构建完成后再通知父组件
      if (widget.onThemeColorsExtracted != null && cachedColors != null) {
        Future.microtask(() {
          if (mounted) {
            widget.onThemeColorsExtracted!(cachedColors);
          }
        });
      }
    } else {
      // 否则加载图片并提取颜色
      _backgroundImage = NetworkImage(url);
      _loadImageAndColors();
    }
  }

  // 加载图像和生成颜色
  Future<void> _loadImageAndColors() async {
    if (widget.imageUrl == null ||
        widget.imageUrl!.isEmpty ||
        _backgroundImage == null)
      return;

    // 防止重复加载
    if (_isLoading) {
      return _loadingCompleter?.future;
    }

    _isLoading = true;
    _loadingCompleter = Completer<void>();

    // 先显示占位背景
    setState(() {
      _imageReady = false;
    });

    try {
      // 尝试从缓存中获取颜色或等待颜色加载完成
      final themeColors = await _ColorCache.getThemeColorsAsync(
        widget.imageUrl!,
      );

      if (mounted) {
        setState(() {
          _themeColors = themeColors;
          _imageReady = true;
        });

        // 通知父组件颜色已更新(使用microtask确保在构建完成后执行)
        if (widget.onThemeColorsExtracted != null) {
          Future.microtask(() {
            if (mounted) {
              widget.onThemeColorsExtracted!(themeColors);
            }
          });
        }
      }
    } catch (e) {
      debugPrint('加载背景颜色时出错: $e');

      // 出错时使用默认颜色方案
      if (mounted) {
        final fallbackColors = ImageThemeColors.fallback();
        setState(() {
          _themeColors = fallbackColors;
          _imageReady = true;
        });

        // 通知父组件使用了默认颜色(使用microtask确保在构建完成后执行)
        if (widget.onThemeColorsExtracted != null) {
          Future.microtask(() {
            if (mounted) {
              widget.onThemeColorsExtracted!(fallbackColors);
            }
          });
        }
      }
    } finally {
      _isLoading = false;
      _loadingCompleter?.complete();
    }

    return _loadingCompleter?.future;
  }

  @override
  Widget build(BuildContext context) {
    // 如果没有图像URL，则显示默认背景
    if (widget.imageUrl == null || widget.imageUrl!.isEmpty) {
      return Container(color: Theme.of(context).scaffoldBackgroundColor);
    }

    // 优化：先用默认背景色渲染，等图片和主题色异步加载完成后再渐变切换
    final themeColors = _themeColors ?? ImageThemeColors.fallback();
    return Stack(
      fit: StackFit.expand,
      children: [
        // 渐变背景色层，先渲染，保证不卡顿
        AnimatedContainer(
          duration: const Duration(milliseconds: 400),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: themeColors.backgroundColors,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        // 封面图背景 - 使用CachedNetworkImage替代Image.network
        AnimatedOpacity(
          duration: const Duration(milliseconds: 400),
          opacity: _imageReady ? 1.0 : 0.0,
          child: CachedNetworkImage(
            imageUrl: widget.imageUrl!,
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
            placeholder: (context, url) => Container(),
            errorWidget:
                (context, url, error) => Container(color: Colors.black),
            // 使用memoryCacheWidth设置缓存宽度，优化内存使用
            memCacheWidth: 800,
          ),
        ),
        // 高斯模糊层 - 使用低精度更快的模糊减少计算量
        Positioned.fill(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 64, sigmaY: 64), // 降低模糊半径提高性能
            child: Container(color: Colors.black.withOpacity(0.3)),
          ),
        ),
      ],
    );
  }
}

// 提供一个简单的包装器用于创建背景
class FluidBackgroundWrapper extends StatelessWidget {
  final Widget child;
  final String? imageUrl;
  final bool isPlaying;
  final bool staticMode;
  final Function(ImageThemeColors)? onThemeColorsExtracted;

  const FluidBackgroundWrapper({
    Key? key,
    required this.child,
    this.imageUrl,
    this.isPlaying = true,
    this.staticMode = true,
    this.onThemeColorsExtracted,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // 背景层
        FluidBackground(
          imageUrl: imageUrl,
          isPlaying: isPlaying,
          staticMode: staticMode,
          onThemeColorsExtracted: onThemeColorsExtracted,
        ),

        // 内容层
        child,
      ],
    );
  }
}
