import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'player_model.dart';

class SettingsPage extends StatelessWidget {
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;

  const SettingsPage({
    super.key,
    required this.themeMode,
    required this.onThemeModeChanged,
  });

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
        ],
      ),
    );
  }
}
