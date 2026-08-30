import 'brush_type.dart';

/// 自然介质笔刷渲染版本（计划 §3.1，ADR-021 前置）。
///
/// - [classicV1]：既有 FreedrawRenderer 外观（缺失/非法值统一解释）；
/// - [naturalMediaV2]：铅笔/毛笔专用自然介质 renderer（T4/T5 落地）。
///
/// 版本只是渲染算法选择，不是权限或安全数据；外部 Excalidraw JSON
/// 可原样保留该字段。
enum BrushRenderVersion { classicV1, naturalMediaV2 }

const String brushRenderVersionCustomDataKey = 'brushRenderVersion';

/// v2 renderer family 仅对这两支笔有效，其他组合安全回退 v1。
const Set<BrushType> naturalMediaV2Brushes = {BrushType.pencil, BrushType.brushPen};

/// 从 customData.flowMuse 读取渲染版本。
///
/// 数值语义（跨 VM/dart2js 一致）：`value is num && value == 1/2` 判定，
/// 避免 `1.0 is int` 在两端不一致；缺失、字符串、bool、NaN/Infinity、
/// 未知数值等一律 classicV1——非法值不抛异常，安全回退。
BrushRenderVersion brushRenderVersionFromCustomData(
  Map<String, Object?>? customData,
) {
  final flowMuse = customData?[flowMuseCustomDataKey];
  Map? map;
  if (flowMuse is Map<String, Object?>) {
    map = flowMuse;
  } else if (flowMuse is Map) {
    map = flowMuse;
  }
  final value = map?[brushRenderVersionCustomDataKey];
  if (value is num) {
    if (value == 2) return BrushRenderVersion.naturalMediaV2;
    if (value == 1) return BrushRenderVersion.classicV1;
  }
  return BrushRenderVersion.classicV1;
}

/// 渲染分发用的有效版本：v2 只在 pencil/brushPen 上成立，非法
/// brush/version 组合回退 v1（计划 §3.2"非法组合安全回退"）。
BrushRenderVersion effectiveBrushRenderVersion(
  Map<String, Object?>? customData,
) {
  if (brushRenderVersionFromCustomData(customData) ==
      BrushRenderVersion.naturalMediaV2) {
    final brush = brushTypeFromCustomData(customData);
    if (!naturalMediaV2Brushes.contains(brush)) {
      return BrushRenderVersion.classicV1;
    }
  }
  return brushRenderVersionFromCustomData(customData);
}

/// 新建笔迹的默认渲染版本：pencil/brushPen 写 v2，其他笔写 v1
///（首版不落字段，见 customDataWithFreedrawRender）。
BrushRenderVersion defaultRenderVersionForNewStroke(BrushType brushType) {
  return naturalMediaV2Brushes.contains(brushType)
      ? BrushRenderVersion.naturalMediaV2
      : BrushRenderVersion.classicV1;
}
