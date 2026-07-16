import 'package:flutter/services.dart';

/// 鸿蒙 Pen Kit 全局取色 MethodChannel 封装。
///
/// 与 ArkTS 侧 PenColorPickerChannel.ets 配对，通道名 'flow_muse/pen_color_picker'。
/// 调用 [pickColor] 启动系统全局取色 UI，返回用户选择的颜色（#rrggbb）
/// 及是否需要降级到画布取色。
class PenColorPickerChannelOhos {
  const PenColorPickerChannelOhos();

  static const _channel = MethodChannel('flow_muse/pen_color_picker');

  /// 启动 Pen Kit 全局取色 UI。
  Future<({String? color, bool unavailable})> pickColor() async {
    try {
      final response = await _channel.invokeMapMethod<Object?, Object?>(
        'pickColor',
      );
      final status = response?['status'];
      final color = response?['color'];
      if (status == 'picked' &&
          color is String &&
          RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(color)) {
        return (color: color.toLowerCase(), unavailable: false);
      }
      return (color: null, unavailable: status == 'unavailable');
    } on MissingPluginException {
      return (color: null, unavailable: true);
    } on PlatformException {
      return (color: null, unavailable: false);
    }
  }
}
