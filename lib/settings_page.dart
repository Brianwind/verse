import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart';
import 'player_model.dart';

class SettingsPage extends StatelessWidget {
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final WindowEffect windowEffect;
  final ValueChanged<WindowEffect> onWindowEffectChanged;

  const SettingsPage({
    super.key,
    required this.themeMode,
    required this.onThemeModeChanged,
    required this.windowEffect,
    required this.onWindowEffectChanged,
  });

  String _effectLabel(WindowEffect effect) {
    if (effect == WindowEffect.disabled) return '无效果';
    if (effect == WindowEffect.transparent) return '透明';
    if (effect == WindowEffect.acrylic) return '亚克力 (Acrylic)';
    if (effect == WindowEffect.mica) return '云母 (Mica)';
    if (effect == WindowEffect.tabbed) return '标签式云母 (Tabbed)';
    return effect.toString();
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerModel>();
    final bottomPadding = player.currentSong != null ? 100.0 : 0.0;

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: EdgeInsets.only(bottom: bottomPadding),
        children: [
          ListTile(
            title: const Text('主题模式'),
            subtitle: Text(
              themeMode == ThemeMode.system
                  ? '跟随系统'
                  : themeMode == ThemeMode.light
                  ? '白天模式'
                  : '黑夜模式',
            ),
            trailing: DropdownButton<ThemeMode>(
              value: themeMode,
              onChanged: (mode) {
                if (mode != null) onThemeModeChanged(mode);
              },
              items: const [
                DropdownMenuItem(value: ThemeMode.system, child: Text('跟随系统')),
                DropdownMenuItem(value: ThemeMode.light, child: Text('白天模式')),
                DropdownMenuItem(value: ThemeMode.dark, child: Text('黑夜模式')),
              ],
            ),
          ),
          ListTile(
            title: const Text('窗口效果'),
            subtitle: Text(
              '${_effectLabel(windowEffect)}　·　Mica/Tabbed 需要 Windows 11',
            ),
            trailing: DropdownButton<WindowEffect>(
              value: windowEffect,
              onChanged: (effect) {
                if (effect != null) onWindowEffectChanged(effect);
              },
              items: [
                DropdownMenuItem(
                  value: WindowEffect.disabled,
                  child: Text('无'),
                ),
                DropdownMenuItem(
                  value: WindowEffect.transparent,
                  child: Text('透明'),
                ),
                DropdownMenuItem(
                  value: WindowEffect.acrylic,
                  child: Text('亚克力 (Acrylic)'),
                ),
                DropdownMenuItem(
                  value: WindowEffect.mica,
                  child: Text('云母 (Mica)'),
                ),
                DropdownMenuItem(
                  value: WindowEffect.tabbed,
                  child: Text('标签式云母 (Tabbed)'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
