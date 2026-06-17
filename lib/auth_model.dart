import 'dart:async';

import 'package:flutter/foundation.dart';

import 'netease_api/src/api/login/bean.dart';
import 'netease_api/src/netease_api.dart';

class AuthModel extends ChangeNotifier {
  late final StreamSubscription _loginSubscription;

  bool _isLoggedIn = NeteaseMusicApi().usc.isLogined;
  NeteaseAccountInfoWrap? _accountInfo = NeteaseMusicApi().usc.accountInfo;
  bool _isBusy = false;
  String? _errorMessage;

  AuthModel() {
    _loginSubscription = NeteaseMusicApi().usc.listenLoginState((state, info) {
      _isLoggedIn = state == LoginState.Logined;
      _accountInfo = info;
      notifyListeners();
    });
  }

  bool get isLoggedIn => _isLoggedIn;
  NeteaseAccountInfoWrap? get accountInfo => _accountInfo;
  bool get isBusy => _isBusy;
  String? get errorMessage => _errorMessage;

  Future<void> refreshAccountInfo() async {
    _setBusy(true);
    _errorMessage = null;
    try {
      final info = await NeteaseMusicApi().loginAccountInfo();
      _accountInfo = info;
      _isLoggedIn = NeteaseMusicApi().usc.isLogined;
    } catch (e) {
      _errorMessage = '刷新账号信息失败: $e';
    } finally {
      _setBusy(false);
    }
  }

  Future<void> logout() async {
    _setBusy(true);
    _errorMessage = null;
    try {
      await NeteaseMusicApi().logout();
    } catch (e) {
      _errorMessage = '远端退出失败，已清除本地登录状态: $e';
      await NeteaseMusicApi().usc.onLogout();
    } finally {
      _isLoggedIn = NeteaseMusicApi().usc.isLogined;
      _accountInfo = NeteaseMusicApi().usc.accountInfo;
      _setBusy(false);
    }
  }

  void _setBusy(bool value) {
    if (_isBusy == value) return;
    _isBusy = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _loginSubscription.cancel();
    super.dispose();
  }
}
