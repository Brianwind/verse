import 'dart:async';
import 'package:flutter/foundation.dart';
// import 'package:smtc_windows/smtc_windows.dart';
import 'constants/platform.dart';
import 'player_model.dart';
import 'netease_api/src/api/play/bean.dart';

/// 专为 Windows 平台实现的 System Media Transport Controls (SMTC) 服务类
/// 该类只在 Windows 平台上运行，其他平台上将是一个空壳
class WindowsSmtcService {
  // SMTCWindows? _smtc;
  PlayerModel? _playerModel;
  StreamSubscription? _buttonPressSubscription;

  // 单例模式
  static WindowsSmtcService? _instance;
  static WindowsSmtcService get instance {
    _instance ??= WindowsSmtcService._();
    return _instance!;
  }

  WindowsSmtcService._();

  /// 初始化 SMTC 服务
  /// 只在 Windows 平台上进行实际初始化
  static Future<void> initialize() async {
    if (PlatformUtils.isWindows) {
      debugPrint('初始化 Windows SMTC 服务 (已禁用)');
    }
  }

  /// 绑定播放器模型，监听播放器状态变化
  void attachPlayer(PlayerModel playerModel) {
    if (!PlatformUtils.isWindows) return;

    _playerModel = playerModel;
    debugPrint('Windows SMTC attachPlayer (已禁用)');
  }
}
