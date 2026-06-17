import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'auth_model.dart';
import 'constants/image_request.dart';
import 'netease_api/src/netease_api.dart';
import 'player_model.dart';

class LoginPage extends StatelessWidget {
  const LoginPage({super.key});

  Future<void> _logout(BuildContext context) async {
    final auth = context.read<AuthModel>();
    final player = context.read<PlayerModel>();

    await player.clearSessionState();
    await auth.logout();

    if (!context.mounted) return;
    final error = auth.errorMessage;
    if (error != null && error.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error), duration: const Duration(seconds: 2)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthModel>();
    final profile = auth.accountInfo?.profile;
    final avatarUrl = normalizeImageUrl(
      profile?.avatarUrl,
      neteaseImageSize: 160,
    );

    if (auth.isLoggedIn && profile != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipOval(
              child: SizedBox(
                width: 80,
                height: 80,
                child:
                    avatarUrl != null
                        ? CachedNetworkImage(
                          imageUrl: avatarUrl,
                          httpHeaders: imageHeadersFor(avatarUrl),
                          fit: BoxFit.cover,
                          placeholder: (_, __) => const _AvatarFallback(),
                          errorWidget: (_, __, ___) => const _AvatarFallback(),
                        )
                        : const _AvatarFallback(),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              profile.nickname ?? '未知用户',
              style: const TextStyle(fontSize: 20),
            ),
            const SizedBox(height: 8),
            if (profile.signature != null && profile.signature!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text(
                  '签名: ${profile.signature!}',
                  style: const TextStyle(fontSize: 14, color: Colors.grey),
                ),
              ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: auth.isBusy ? null : () => _logout(context),
              icon:
                  auth.isBusy
                      ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                      : const Icon(Icons.logout),
              label: const Text('退出登录'),
            ),
          ],
        ),
      );
    }

    return const Center(
      child: Padding(padding: EdgeInsets.all(24), child: _QrLoginPanel()),
    );
  }
}

class _AvatarFallback extends StatelessWidget {
  const _AvatarFallback();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Icon(
        Icons.person,
        size: 40,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}

class _QrLoginPanel extends StatefulWidget {
  const _QrLoginPanel();

  @override
  State<_QrLoginPanel> createState() => _QrLoginPanelState();
}

class _QrLoginPanelState extends State<_QrLoginPanel> {
  String? _qrUrl;
  String? _qrKey;
  String? _message;
  bool _loading = true;
  bool _checking = false;
  bool _expired = false;
  bool _isError = false;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _startQr();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _startQr() async {
    _pollTimer?.cancel();
    setState(() {
      _qrUrl = null;
      _qrKey = null;
      _message = null;
      _loading = true;
      _checking = false;
      _expired = false;
      _isError = false;
    });

    try {
      final keyBean = await NeteaseMusicApi().loginQrCodeKey();
      final key = keyBean.unikey;
      final url = NeteaseMusicApi().loginQrCodeUrl(key);

      if (!mounted) return;
      setState(() {
        _qrKey = key;
        _qrUrl = url;
        _loading = false;
      });
      _pollTimer = Timer.periodic(
        const Duration(seconds: 1),
        (_) => _checkStatus(),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _message = '二维码获取失败: $e';
        _loading = false;
        _expired = true;
        _isError = true;
      });
    }
  }

  Future<void> _checkStatus() async {
    final key = _qrKey;
    if (_checking || key == null || _expired) return;

    _checking = true;
    try {
      final status = await NeteaseMusicApi().loginQrCodeCheck(key);
      if (!mounted) return;

      if (status.code == 803) {
        _pollTimer?.cancel();
        setState(() {
          _message = '登录成功，正在加载账号信息...';
          _isError = false;
        });
        await NeteaseMusicApi().loginAccountInfo();
      } else if (status.code == 800) {
        _pollTimer?.cancel();
        setState(() {
          _message = '二维码已过期';
          _expired = true;
          _isError = true;
        });
      } else if (status.code == 802) {
        setState(() {
          _message = '请在手机上确认登录';
          _isError = false;
        });
      } else {
        setState(() {
          _message = null;
          _isError = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _message = '状态检查失败: $e';
        _isError = true;
      });
    } finally {
      _checking = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('扫码登录', style: TextStyle(fontSize: 22)),
        const SizedBox(height: 20),
        SizedBox(
          width: 220,
          height: 220,
          child:
              _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _qrUrl != null
                  ? Center(
                    child: QrImageView(
                      data: _qrUrl!,
                      version: QrVersions.auto,
                      size: 200,
                    ),
                  )
                  : const Center(child: Icon(Icons.qr_code_2, size: 80)),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 24,
          child:
              _message == null
                  ? const SizedBox.shrink()
                  : Text(
                    _message!,
                    style: TextStyle(
                      color:
                          _isError
                              ? Theme.of(context).colorScheme.error
                              : Theme.of(context).colorScheme.primary,
                    ),
                  ),
        ),
        const SizedBox(height: 16),
        if (_expired)
          OutlinedButton.icon(
            onPressed: _startQr,
            icon: const Icon(Icons.refresh),
            label: const Text('重新获取'),
          ),
      ],
    );
  }
}
