import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'dart:async';
import 'netease_api/src/netease_api.dart';
import 'netease_api/src/api/login/bean.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _pwdController = TextEditingController();
  bool _loading = false;
  late final StreamSubscription _loginSub;

  @override
  void initState() {
    super.initState();
    _loginSub = NeteaseMusicApi().usc.listenLoginState((_, __) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _loginSub.cancel();
    super.dispose();
  }

  void _login() async {
    setState(() => _loading = true);
    try {
      final info = await NeteaseMusicApi().loginCellPhone(
        _phoneController.text.trim(),
        _pwdController.text.trim(),
      );
      if (info.code == 200 && NeteaseMusicApi().usc.isLogined) {
        // 登录成功后，刷新并显示最新用户信息
        await NeteaseMusicApi().loginAccountInfo();
        setState(() {});
      } else {
        _showError('登录失败: ${info.code} ${info.msg}');
        return;
      }
    } catch (e) {
      _showError('登录异常: $e');
      return;
    } finally {
      setState(() => _loading = false);
    }
  }

  void _qrLogin() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _QrLoginDialog(onLogin: () => Navigator.of(ctx).pop()),
    );
  }

  void _showError(String msg) {
    showDialog(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('错误'),
            content: Text(msg),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('确定'),
              ),
            ],
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLogined = NeteaseMusicApi().usc.isLogined;
    final profile = NeteaseMusicApi().usc.accountInfo?.profile;

    if (isLogined && profile != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 40,
              backgroundImage:
                  profile.avatarUrl != null
                      ? NetworkImage(profile.avatarUrl!)
                      : null,
              child:
                  profile.avatarUrl == null
                      ? const Icon(Icons.person, size: 40)
                      : null,
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
          ],
        ),
      );
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _phoneController,
              decoration: const InputDecoration(labelText: '手机号'),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _pwdController,
              decoration: const InputDecoration(labelText: '密码'),
              obscureText: true,
            ),
            const SizedBox(height: 24),
            _loading
                ? const CircularProgressIndicator()
                : Column(
                  children: [
                    ElevatedButton(onPressed: _login, child: const Text('登录')),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: _qrLogin,
                      child: const Text('二维码登录'),
                    ),
                  ],
                ),
          ],
        ),
      ),
    );
  }
}

class _QrLoginDialog extends StatefulWidget {
  final VoidCallback onLogin;
  const _QrLoginDialog({required this.onLogin});

  @override
  State<_QrLoginDialog> createState() => _QrLoginDialogState();
}

class _QrLoginDialogState extends State<_QrLoginDialog> {
  String? _qrUrl;
  String? _qrKey;
  String? _errMsg;
  bool _loading = true;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _startQr();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _startQr() async {
    setState(() {
      _loading = true;
      _errMsg = null;
    });
    try {
      final keyBean = await NeteaseMusicApi().loginQrCodeKey();
      final key = keyBean.unikey;
      final url = NeteaseMusicApi().loginQrCodeUrl(key);
      setState(() {
        _qrKey = key;
        _qrUrl = url;
        _loading = false;
      });
      _pollStatus(key);
    } catch (e) {
      setState(() {
        _errMsg = '二维码获取失败: $e';
        _loading = false;
      });
    }
  }

  void _pollStatus(String key) async {
    while (!_disposed) {
      await Future.delayed(const Duration(seconds: 1));
      try {
        final status = await NeteaseMusicApi().loginQrCodeCheck(key);
        if (status.code == 803) {
          await NeteaseMusicApi().loginAccountInfo();
          widget.onLogin();
          break;
        } else if (status.code == 800) {
          setState(() => _errMsg = '二维码已过期');
          break;
        } else if (status.code == 802) {
          // 已扫码，等待确认
          setState(() => _errMsg = '请在手机上确认登录');
        } else {
          setState(() => _errMsg = null);
        }
      } catch (e) {
        setState(() => _errMsg = '状态检查失败: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('二维码登录'),
      content: SizedBox(
        width: 220,
        child:
            _loading
                ? const Center(child: CircularProgressIndicator())
                : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_qrUrl != null)
                      SizedBox(
                        width: 180,
                        height: 180,
                        child: QrImageView(
                          data: _qrUrl!,
                          version: QrVersions.auto,
                          size: 180,
                        ),
                      ),
                    if (_errMsg != null) ...[
                      const SizedBox(height: 12),
                      Text(_errMsg!, style: const TextStyle(color: Colors.red)),
                    ],
                  ],
                ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        if (!_loading && _errMsg == '二维码已过期')
          TextButton(onPressed: _startQr, child: const Text('重新获取')),
      ],
    );
  }
}
