import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart';
import 'download_model.dart';
import 'player_model.dart';

class SettingsPage extends StatefulWidget {
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

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final TextEditingController _downloadDirectoryController =
      TextEditingController();
  final FocusNode _downloadDirectoryFocusNode = FocusNode();
  String? _lastDownloadDirectory;
  bool _savingDownloadDirectory = false;

  @override
  void dispose() {
    _downloadDirectoryController.dispose();
    _downloadDirectoryFocusNode.dispose();
    super.dispose();
  }

  String _effectLabel(WindowEffect effect) {
    if (effect == WindowEffect.disabled) return '无效果';
    if (effect == WindowEffect.transparent) return '透明';
    if (effect == WindowEffect.acrylic) return '亚克力 (Acrylic)';
    if (effect == WindowEffect.mica) return '云母 (Mica)';
    if (effect == WindowEffect.tabbed) return '标签式云母 (Tabbed)';
    return effect.toString();
  }

  Future<void> _saveDownloadDirectory() async {
    final path = _downloadDirectoryController.text.trim();
    if (path.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('下载地址不能为空'),
          duration: Duration(seconds: 1),
        ),
      );
      return;
    }

    setState(() => _savingDownloadDirectory = true);
    try {
      await context.read<DownloadModel>().setDownloadDirectory(path);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('下载地址已保存'),
          duration: Duration(seconds: 1),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('保存下载地址失败: $e'),
          duration: const Duration(seconds: 2),
        ),
      );
    } finally {
      if (mounted) setState(() => _savingDownloadDirectory = false);
    }
  }

  Future<void> _resetDownloadDirectory() async {
    setState(() => _savingDownloadDirectory = true);
    try {
      await context.read<DownloadModel>().resetDownloadDirectory();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('已恢复默认下载地址'),
          duration: Duration(seconds: 1),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('恢复默认下载地址失败: $e'),
          duration: const Duration(seconds: 2),
        ),
      );
    } finally {
      if (mounted) setState(() => _savingDownloadDirectory = false);
    }
  }

  String _downloadStatusText(DownloadModel download) {
    if (download.status == DownloadQueueStatus.running) {
      final current = download.currentTask;
      final index = download.completedCount + 1;
      final total = download.totalCount;
      final name = current?.song.name ?? current?.fileName ?? '';
      return '正在下载 $index/$total${name.isNotEmpty ? ' · $name' : ''}';
    }

    if (download.status == DownloadQueueStatus.completed &&
        download.totalCount > 0) {
      final summary =
          '已完成: 成功 ${download.succeededCount}，跳过 ${download.skippedCount}，失败 ${download.failedCount}';
      final error = download.lastErrorMessage;
      if (download.failedCount > 0 && error != null && error.isNotEmpty) {
        return '$summary · $error';
      }
      return summary;
    }

    return '固定下载 320K MP3，同名文件会自动跳过';
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerModel>();
    final download = context.watch<DownloadModel>();
    final bottomPadding = player.currentSong != null ? 100.0 : 0.0;

    if (_lastDownloadDirectory != download.downloadDirectory &&
        !_downloadDirectoryFocusNode.hasFocus) {
      _downloadDirectoryController.text = download.downloadDirectory;
      _lastDownloadDirectory = download.downloadDirectory;
    }

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: EdgeInsets.only(bottom: bottomPadding),
        children: [
          ListTile(
            title: const Text('主题模式'),
            subtitle: Text(
              widget.themeMode == ThemeMode.system
                  ? '跟随系统'
                  : widget.themeMode == ThemeMode.light
                  ? '白天模式'
                  : '黑夜模式',
            ),
            trailing: DropdownButton<ThemeMode>(
              value: widget.themeMode,
              onChanged: (mode) {
                if (mode != null) widget.onThemeModeChanged(mode);
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
              '${_effectLabel(widget.windowEffect)}　·　Mica/Tabbed 需要 Windows 11',
            ),
            trailing: DropdownButton<WindowEffect>(
              value: widget.windowEffect,
              onChanged: (effect) {
                if (effect != null) widget.onWindowEffectChanged(effect);
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
          const Divider(height: 28),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
            child: Text(
              '歌曲下载地址',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _downloadDirectoryController,
                    focusNode: _downloadDirectoryFocusNode,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      isDense: true,
                      hintText: r'C:\Users\name\Desktop',
                    ),
                    onSubmitted: (_) => _saveDownloadDirectory(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed:
                      _savingDownloadDirectory ? null : _saveDownloadDirectory,
                  child:
                      _savingDownloadDirectory
                          ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                          : const Text('保存'),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed:
                      _savingDownloadDirectory ? null : _resetDownloadDirectory,
                  child: const Text('恢复默认'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              _downloadStatusText(download),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.62),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
