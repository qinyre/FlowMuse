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
  // --- v2 自然介质响应曲线与绘制常数（计划 §3.5；T4 冻结）---
  // 铅笔：压力主要控制石墨密度，宽度只随压力温和变化。宽度项取
  // 0.26（而非 spike 的 0.28）：理论轻重宽度比 1.18，给 N3 的 1.35
  // 门禁留 1px 法向扫描量化余量（T0 记录的提醒）。
  double pencilNaturalMediaLocalWidth(double base, double p) =>
      base * (0.82 + 0.26 * p.clamp(0.0, 1.0));

  double pencilNaturalMediaDensity(double p) =>
      0.18 + 0.72 * math.pow(p.clamp(0.0, 1.0), 0.85);

  // 毛笔：压力主要控制笔肚接触宽度；0.16 底保证轻压可见。
  // T5 追加可见下限 0.7px：p→0 时公式全宽仅 ~0.96px，斜向 AA 下会
  // 断成虚线（T5 视觉审查 S 曲线负压段实测），违反 §3.5"最低有效
  // 宽度仍可见"；下限只影响 p≲0.012 的极端轻压，不改变 N6 量程。
  static const double brushV2MinContactHalfWidth = 0.7;

  double brushNaturalMediaContactHalfWidth(double base, double p) => math.max(
    base * (0.16 + 1.34 * math.pow(p.clamp(0.0, 1.0), 0.72)) / 2,
    brushV2MinContactHalfWidth,
  );

  // --- 毛笔 v2 绘制常数（T0 spike 校准，T5 冻结；§3.7 要求与
  // elementVisualBounds 共用，禁止 renderer 与 bounds 各写一份）---

  /// 毫丝复合 Path 的绘制 alpha（主体方向性包络为不透明 1.0）。
  double get brushV2StrandAlpha => 0.50;

  /// 收笔楔形单位上限（× 尾缘接触半宽；公式 min(units, 6×drop)）。
  static const double brushV2TailTaperUnits = 4.0;

  /// 收笔楔形绝对上限（× base）：真实压力回放的出锋实测 ≤ ~1.55×base，
  /// 冻结 1.6，同时约束 elementVisualBounds 的侧向外扩。
  static const double brushV2TailTaperBaseCap = 1.6;

  /// 毛笔 v2 可视半宽：最大接触半宽 + 出锋上限 + AA 余量（teardrop
  /// 的 1.3×放大与 1.4×尾锋均已被出锋上限覆盖）。
  double brushV2VisualHalfWidth(double base) =>
      brushNaturalMediaContactHalfWidth(base, 1.0) +
      brushV2TailTaperBaseCap * base +
      2.0;

  // 铅笔 v2 绘制 alpha（T0 spike 校准，T4 冻结）：低透明连续基底 +
  // 三个密度桶颗粒各自恒定 alpha，压力→密度经颗粒间距表达。
  double get pencilV2BaseAlpha => 0.30;

  // --- 铅笔 v2 颗粒几何常数（T8：sampler 与 bounds 共用真源）---
  // 颗粒半长/半厚/法向散布的系数；NaturalMediaTuning 的默认值引用
  // 这里，渲染器与 elementVisualBounds 不得各自维护（§3.6）。
  static const double pencilV2ScatterRatio = 0.225;
  static const double pencilV2GrainHalfLenBase = 0.30;
  static const double pencilV2GrainHalfLenSpan = 0.22;
  static const double pencilV2GrainHalfThickBase = 0.10;
  static const double pencilV2GrainHalfThickAbs = 0.25;

  /// 铅笔 v2 可视半宽（解析上界，T8）：wobble 基底 1.15×半宽、颗粒
  /// 外缘（散布 + 半厚）与笔端沿切向外伸（半长 + 半厚）三者取大，
  /// 再加 AA 余量。
  double pencilV2VisualHalfWidth(double base) {
    final wMax = base * 1.08; // 0.82 + 0.26（宽度曲线满压）
    final baseSide = wMax / 2 * 1.15; // 基底 wobble 上界
    final grainSide =
        wMax * (pencilV2ScatterRatio + pencilV2GrainHalfThickBase) +
        pencilV2GrainHalfThickAbs;
    final endAlong =
        wMax * (pencilV2GrainHalfLenBase + pencilV2GrainHalfLenSpan) +
        wMax * pencilV2GrainHalfThickBase +
        pencilV2GrainHalfThickAbs;
    var half = baseSide > grainSide ? baseSide : grainSide;
    if (endAlong > half) half = endAlong;
    return half + 1.0; // AA
  }

  // channel 编号是协议级常量（rendering/natural_media/
  // deterministic_stroke_seed.dart 的 NaturalMediaChannel，跨端冻结）；
  // core 不反向 import rendering，故此处用字面值并对齐注释。
  double pencilV2GrainAlpha(int channel) => switch (channel) {
    1 => 0.20, // pencilLow
    2 => 0.28, // pencilMedium
    3 => 0.38, // pencilHeavy
    _ => 0.20,
  };

  static const double _kDefaultThinning = 0.5;
  static const double _kDefaultSmoothing = 0.5;
  static const double _kDefaultStreamline = 0.5;

  static BrushRenderProfile forType(BrushType type) => switch (type) {
    // 铅笔：半透明 + 低延迟跟手；纹理由 PencilShader/降级路径提供。
    // 铅笔：半透明 + 低延迟跟手；纹理由 PencilShader/降级路径提供。
    // 起笔 taper 因包内 runningLength<size 丢点，可见渐变需 ≥3×size。
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
      startTaperSizeFactor: 3,
      endTaperSizeFactor: 4,
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
    // 毛笔：强压感 + 明显收锋（起 4×size / 收 6×size 绝对距离；
    // <3×size 短笔由 startTaperDistance/endTaperDistance 门控关闭）。
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
      startTaperSizeFactor: 6,
      endTaperSizeFactor: 6,
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
