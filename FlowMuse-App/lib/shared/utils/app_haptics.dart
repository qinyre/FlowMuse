import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 统一触感反馈入口。
///
/// 语义命名而不是强度命名：调用方表达「这是什么时刻」，强度由这里集中决定，
/// 以后调整全局手感只改一处。桌面与 Web 平台上 [HapticFeedback] 本身是空操作，
/// 不需要调用方判断平台。
class AppHaptics {
  const AppHaptics._();

  /// 弹出面板/下拉展开。
  static Future<void> panelOpen() => _feedback(HapticFeedback.lightImpact);

  /// 在面板/列表中选中一个选项。
  static Future<void> selection() => _feedback(HapticFeedback.selectionClick);

  static Future<void> _feedback(Future<void> Function() feedback) async {
    try {
      await feedback();
    } on Exception catch (error) {
      // 触感属于辅助能力，插件缺失或系统拒绝时仍应允许菜单操作。
      debugPrint(
        '[FlowMuseCreateNote] haptics unavailable: ${error.runtimeType}',
      );
    }
  }
}
