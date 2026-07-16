/// 非鸿蒙平台桩实现，所有方法均为 no-op，返回 null。
class PenColorPickerChannelOhos {
  const PenColorPickerChannelOhos();

  Future<({String? color, bool unavailable})> pickColor() async =>
      (color: null, unavailable: true);
}
