import 'package:flutter/services.dart';

/// 鸿蒙 Pen Kit 全局取色 MethodChannel 封装。
///
/// 与 ArkTS 侧 PenColorPickerChannel.ets 配对，通道名 'flow_muse/pen_color_picker'。
/// 调用 [pickColorAt] 启动系统全局取色 UI，返回用户选择的颜色（#rrggbb），
/// 用户取消、设备不支持或 API 错误时返回 null。
class PenColorPickerChannelOhos {
  const PenColorPickerChannelOhos();

  static const _channel = MethodChannel('flow_muse/pen_color_picker');

  /// 在屏幕坐标 [x]/[y] 处启动 Pen Kit 全局取色 UI。
  /// 返回 '#rrggbb' 或 null（取消/不支持/错误）。
  Future<String?> pickColorAt({double x = 0, double y = 0}) async {
    try {
      final result = await _channel.invokeMethod<String?>(
        'pickColorAt',
        {'x': x, 'y': y},
      );
      return result;
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }
}
