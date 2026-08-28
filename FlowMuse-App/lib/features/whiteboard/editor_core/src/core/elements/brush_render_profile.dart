import 'dart:math' as math;

import 'brush_type.dart';

/// 端帽形态：round（圆头）/ flat（平头截面）。
enum BrushCapStyle { round, flat }

/// 最终合成模式：sourceOver（常规）/ darken（荧光笔叠加加深）。
///
/// 仅描述最终合成，不允许内部隐式创建 saveLayer。
enum BrushCompositeMode { sourceOver, darken }

/// 笔迹段的 taper 角色。
///
/// 远端湿墨按 64 点冻结块+尾段逐段独立 getStroke，若每段都按整笔施加
/// taper，毛笔会在每个段边界周期性收针。分段规则（issue #5 计划 §6.1）：
/// - full：整笔渲染（本地湿墨、静态元素、SVG）；
/// - headOnly：包含笔迹起点的远端冻结首块/首段（只有起笔 taper）；
/// - tailOnly：远端最新尾段（只有收笔 taper，跟随对端笔尖）；
/// - none：其余中间段（无 taper）。
/// 整笔尚在尾段（无任何冻结块、可见 tail 含 index 0）时该尾段用 full。
enum FreedrawTaperPhase { full, headOnly, tailOnly, none }

/// 五种笔刷的渲染描述单一真源。
///
/// Raster、SVG、湿墨边界计算、命中/导出边界都读取本类；配置层只保存
/// 无状态常量，shader 可用性、Path 缓存、Paint 等运行时对象不得放入。
///
/// 压力烘焙等价性前提：perfect_freehand 的半径公式为
/// `size × easing(0.5 + thinning×(pressure−0.5))`，[encodePressure] 与
/// “渲染时用 maxThinning”的等价性仅在 easing = identity（包默认，
/// 本项目从不传非默认 easing）下成立。禁止给 StrokeOptions 传自定义
/// easing，否则历史笔迹会静默漂移。
final class BrushRenderProfile {
  const BrushRenderProfile({
    required this.sizeScale,
    required this.opacityScale,
    required this.thinningBase,
    required this.thinningSpan,
    required this.simulatedThinning,
    required this.smoothing,
    required this.streamline,
    required this.pressureEnabled,
    required this.forceSimulatePressure,
    required this.startTaperSizeFactor,
    required this.endTaperSizeFactor,
    required this.capStyle,
    required this.compositeMode,
    required this.usesPencilTexture,
  });

  /// strokeWidth → perfect_freehand size（直径）的倍率。
  final double sizeScale;

  /// 颜色 alpha 倍率（笔刷固有透明度）。
  final double opacityScale;

  /// 真实压感有效 thinning = thinningBase + thinningSpan × sensitivity。
  final double thinningBase;
  final double thinningSpan;

  /// 无真实压力（模拟压感）时的唯一 thinning；圆珠笔/荧光笔必须为 0
  /// （包内 thinning=0 时半径恒 size/2，速度不影响宽度）。
  final double simulatedThinning;

  final double smoothing;
  final double streamline;

  /// 真实压感是否生效（圆珠笔/荧光笔为 false，忽略输入压力）。
  final bool pressureEnabled;

  /// 无可信压力时是否使用速度模拟。
  final bool forceSimulatePressure;

  /// 起笔 taper 距离 = 因子 × size；0 = 无起笔 taper。
  /// 换算用 size 取 renderSize(strokeWidth)（sizeScale 之后、1.0 下限之后）。
  final double startTaperSizeFactor;

  /// 收笔 taper 距离 = 因子 × size；0 = 无收笔 taper。
  final double endTaperSizeFactor;

  final BrushCapStyle capStyle;
  final BrushCompositeMode compositeMode;

  /// 是否使用铅笔纹理（只表示“可使用”，不保证 shader 可用）。
  final bool usesPencilTexture;

  /// perfect_freehand 包默认（stroke_options.dart：0.5/0.5/0.5），
  /// 钢笔保持既有默认手感。
  static const double _kDefaultThinning = 0.5;
  static const double _kDefaultSmoothing = 0.5;
  static const double _kDefaultStreamline = 0.5;

  static BrushRenderProfile forType(BrushType type) => switch (type) {
    // 铅笔：半透明 + 低延迟跟手；纹理由 PencilShader/降级路径提供。
    BrushType.pencil => const BrushRenderProfile(
      sizeScale: 0.82,
      opacityScale: 0.68,
      thinningBase: 0.0,
      thinningSpan: 0.45,
      simulatedThinning: 0.32,
      smoothing: 0.2,
      streamline: 0.15,
      pressureEnabled: true,
      forceSimulatePressure: false,
      startTaperSizeFactor: 0,
      endTaperSizeFactor: 0,
      capStyle: BrushCapStyle.round,
      compositeMode: BrushCompositeMode.sourceOver,
      usesPencilTexture: true,
    ),
    // 圆珠笔：细、恒宽（真实与模拟 thinning 均为 0）、圆头。
    BrushType.ballpoint => const BrushRenderProfile(
      sizeScale: 0.72,
      opacityScale: 1.0,
      thinningBase: 0.0,
      thinningSpan: 0.0,
      simulatedThinning: 0.0,
      smoothing: 0.62,
      streamline: 0.52,
      pressureEnabled: false,
      forceSimulatePressure: false,
      startTaperSizeFactor: 0,
      endTaperSizeFactor: 0,
      capStyle: BrushCapStyle.round,
      compositeMode: BrushCompositeMode.sourceOver,
      usesPencilTexture: false,
    ),
    // 钢笔（默认）：保留既有压感响应 0.05 + 0.9×sensitivity。
    BrushType.fountainPen => const BrushRenderProfile(
      sizeScale: 1.0,
      opacityScale: 1.0,
      thinningBase: 0.05,
      thinningSpan: 0.9,
      simulatedThinning: _kDefaultThinning,
      smoothing: _kDefaultSmoothing,
      streamline: _kDefaultStreamline,
      pressureEnabled: true,
      forceSimulatePressure: false,
      startTaperSizeFactor: 0,
      endTaperSizeFactor: 0,
      capStyle: BrushCapStyle.round,
      compositeMode: BrushCompositeMode.sourceOver,
      usesPencilTexture: false,
    ),
    // 毛笔：强压感 + 明显收锋（taper 距离在 T3 启用）。
    BrushType.brushPen => const BrushRenderProfile(
      sizeScale: 1.15,
      opacityScale: 1.0,
      thinningBase: 0.0,
      thinningSpan: 1.0,
      simulatedThinning: 0.82,
      smoothing: 0.58,
      streamline: 0.42,
      pressureEnabled: true,
      forceSimulatePressure: false,
      startTaperSizeFactor: 0,
      endTaperSizeFactor: 0,
      capStyle: BrushCapStyle.round,
      compositeMode: BrushCompositeMode.sourceOver,
      usesPencilTexture: false,
    ),
    // 荧光笔：特粗、恒宽、半透明、平头、叠加加深（darken 在 T4 启用）。
    BrushType.highlighter => const BrushRenderProfile(
      sizeScale: 4.2,
      opacityScale: 0.30,
      thinningBase: 0.0,
      thinningSpan: 0.0,
      simulatedThinning: 0.0,
      smoothing: 0.72,
      streamline: 0.58,
      pressureEnabled: false,
      forceSimulatePressure: true,
      startTaperSizeFactor: 0,
      endTaperSizeFactor: 0,
      capStyle: BrushCapStyle.flat,
      compositeMode: BrushCompositeMode.darken,
      usesPencilTexture: false,
    ),
  };

  /// profile 最大 thinning（pressureEncoding=1 渲染时的固定 thinning）。
  double get maxThinning => thinningBase + thinningSpan;

  /// 指定灵敏度下的真实压感有效 thinning。
  double effectiveThinning(double sensitivity) =>
      thinningBase + thinningSpan * sensitivity.clamp(0.0, 1.0);

  /// 创建时把灵敏度烘焙进 pressure 值（结果钳制 0~1）。
  ///
  /// 渲染端用 [maxThinning] + 已编码 pressure 可逐点复现
  /// [effectiveThinning] + 原始 pressure 的半径（easing=identity 前提）。
  /// 钳制是承重的：浮点 1-ulp 上溢会让 LiveInPoint.fromJson 直接 throw。
  /// maxThinning 为 0（恒宽笔型）时恒返回 0.5 中性压力。
  double encodePressure(double rawPressure, double sensitivity) {
    final max = maxThinning;
    if (max <= 0) return 0.5;
    final k = effectiveThinning(sensitivity) / max;
    return (0.5 + k * (rawPressure.clamp(0.0, 1.0) - 0.5)).clamp(0.0, 1.0);
  }

  /// 旧元素（无 pressureEncoding 标记）渲染时使用的确定性灵敏度：
  /// 对应笔刷的出厂默认，禁止读取当前控制器/适配器状态。
  double legacySensitivity(BrushType type) =>
      BrushState.defaults[type]!.pressureSensitivity;

  /// 渲染 size（直径）：sizeScale 之后、1.0 下限之后。taper 距离与
  /// “<3×size 禁用 taper”门控的 size 都必须与此同源。
  double renderSize(double strokeWidth) =>
      math.max(strokeWidth * sizeScale, 1.0);

  /// 起笔 taper 绝对距离；profile 未启用或原始折线过短（<3×size）时为 0。
  double startTaperDistance(double strokeWidth, double rawPolylineLength) {
    if (startTaperSizeFactor <= 0) return 0;
    final size = renderSize(strokeWidth);
    if (rawPolylineLength < 3 * size) return 0;
    return startTaperSizeFactor * size;
  }

  /// 收笔 taper 绝对距离；规则同 [startTaperDistance]。
  double endTaperDistance(double strokeWidth, double rawPolylineLength) {
    if (endTaperSizeFactor <= 0) return 0;
    final size = renderSize(strokeWidth);
    if (rawPolylineLength < 3 * size) return 0;
    return endTaperSizeFactor * size;
  }

  /// 保守最大可见半径（中心线到可见边缘），含抗锯齿与铅笔纹理余量。
  ///
  /// 派生：perfect_freehand 最大半径 = size × (0.5 + thinning×0.5)，
  /// 取真实/模拟 thinning 的较大者；荧光笔平头截面同一半径。
  /// Scene 命中、sceneBounds、导出边界、湿墨 dim 层共用本值。
  double visualHalfWidth(double strokeWidth) {
    final size = renderSize(strokeWidth);
    final maxThinningForWidth = math.max(maxThinning, simulatedThinning);
    return size * (0.5 + maxThinningForWidth * 0.5) + 2.0;
  }
}
