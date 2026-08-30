import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flow_muse/features/whiteboard/editor_core/src/core/elements/elements.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/math/math.dart';

import '../fixtures/brush_stroke_fixtures.dart';
import 'canvas_spy.dart';
import 'natural_media/natural_media_image_metrics.dart';

/// T0 测试纸支撑：fixture → 单元格布局 → 冻结底图契约渲染（一次绘制
/// 同时产出指标栅格、PNG 字节与 draw/saveLayer 结构计数）+ 问题编号
/// 清单（NOTES）。
///
/// 单元格布局规则（T0 冻结）：900×150，边距 60/30，缩放上限 3×
///（防止短点 fixture 被放大成巨点）；同一 fixture 的几何在所有行、
/// 版本与指标间完全一致。
const double kCellWidth = 900;
const double kCellHeight = 150;
const double kNominalWidth = 6.0;
const String kOutRoot = 'build/natural_media_baseline';

/// 把 fixture 归一化到单元格坐标（返回绝对点位）。
List<Point> fitFixtureToCell(BrushStrokeFixture f) {
  final xs = f.points.map((p) => p.x);
  final ys = f.points.map((p) => p.y);
  final minX = xs.reduce(math.min);
  final maxX = xs.reduce(math.max);
  final minY = ys.reduce(math.min);
  final maxY = ys.reduce(math.max);
  final spanX = math.max(maxX - minX, 1e-6);
  final spanY = math.max(maxY - minY, 1e-6);
  var scale = math.min((kCellWidth - 120) / spanX, (kCellHeight - 60) / spanY);
  scale = scale.clamp(0.0, 3.0);
  final dx = 60 + (kCellWidth - 120 - spanX * scale) / 2;
  final dy = 30 + (kCellHeight - 60 - spanY * scale) / 2;
  return [
    for (final p in f.points)
      Point(dx + (p.x - minX) * scale, dy + (p.y - minY) * scale),
  ];
}

/// 由绝对点位构造 freedraw 元素（生产不变量：points 相对元素原点）。
FreedrawElement placedElement(
  List<Point> placed,
  List<double> pressures,
  BrushType brush,
  String idSeed,
) {
  final xs = placed.map((p) => p.x);
  final ys = placed.map((p) => p.y);
  final minX = xs.reduce(math.min);
  final minY = ys.reduce(math.min);
  return FreedrawElement(
    id: ElementId('sheet-$idSeed'),
    x: minX,
    y: minY,
    width: xs.reduce(math.max) - minX,
    height: ys.reduce(math.max) - minY,
    points: [for (final p in placed) Point(p.x - minX, p.y - minY)],
    pressures: List<double>.from(pressures),
    simulatePressure: false,
    isComplete: true,
    customData: customDataWithFreedrawRender(null, brush),
    strokeWidth: kNominalWidth,
  );
}

/// 一次单元格渲染的全部产物。
class PlacedRender {
  const PlacedRender({
    required this.raster,
    required this.pngBytes,
    required this.drawCallCount,
    required this.saveLayerCount,
    required this.shaderPathCount,
  });

  final NaturalMediaRaster raster;
  final Uint8List pngBytes;
  final int drawCallCount;
  final int saveLayerCount;
  final int shaderPathCount;
}

/// 白底契约渲染 [placed] 轨迹；[repeat] 为同元素叠加次数（重复覆盖）。
/// SpyCanvas 转发的就是契约 paintScene，计数与像素同源。
Future<PlacedRender> renderPlaced(
  List<Point> placed,
  List<double> pressures,
  BrushType brush,
  String idSeed, {
  int repeat = 1,
}) async {
  final element = placedElement(placed, pressures, brush, idSeed);
  final elements = List<FreedrawElement>.filled(repeat, element);

  final recorder = ui.PictureRecorder();
  final spy = SpyCanvas(ui.Canvas(recorder));
  NaturalMediaSheetRenderer.paintScene(
    spy,
    ui.Size(kCellWidth, kCellHeight),
    elements,
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(kCellWidth.round(), kCellHeight.round());
  picture.dispose();
  final raster = await NaturalMediaRaster.fromImage(image);
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  if (png == null) {
    throw StateError('PNG 编码失败');
  }
  return PlacedRender(
    raster: raster,
    pngBytes: png.buffer.asUint8List(),
    drawCallCount: spy.drawCallCount,
    saveLayerCount: spy.saveLayerCount,
    shaderPathCount: spy.shaderPathCount,
  );
}

/// 单元格 PNG 落盘。
void writeCellPng(String path, PlacedRender render) {
  File(path).writeAsBytesSync(render.pngBytes);
}

/// 问题编号清单（P-01…）：铅笔与毛笔分组累积后一次写出。
final _notesBuffer = StringBuffer('''
# v1 当前视觉问题编号清单（T0 基线）

> 由 natural_media_visual_sheet_test.dart 自动生成；数字均为冻结口径
> 实测值。本清单是"当前问题被指标呈现"的存档，不是 v2 合格标准。

''');

void writeNotes({
  Map<String, Object?>? pencilMetrics,
  Map<String, Object?>? brushMetrics,
}) {
  if (pencilMetrics != null) {
    _notesBuffer.write('''
## 铅笔（v1）

- P-01 压力主要改变宽度而非浓度：轻/重压共同中心带 darkness 比
  ${_fmt(pencilMetrics['centerDarknessRatio'])}（N2 要求 v2 ≥ 1.35，v1 不达标 = 缺陷被检出）
- P-02 宽度随压力增长：轻/重中位有效宽度比 ${_fmt(pencilMetrics['widthRatio'])}
  （轻 ${_fmt(pencilMetrics['lightWidth'])}px → 重 ${_fmt(pencilMetrics['heavyWidth'])}px；N3 上限 1.35，v1 超限 = 缺陷被检出）
- P-03 边缘不规则度（T0 实测改判观察项）：轻压 RMS/局部宽度
  ${_fmt(pencilMetrics['lightEdgeIrregularityRms'])}，spike v2 原型 0.072——v1 高值来自喷枪式
  散点链（§2"喷枪"为不接受特征，属视觉判定项），"不规则度不足"未获指标支持；
  冻结下限 ${NaturalMediaFrozen.edgeIrregularityMinRms} 仅作 v2 防退化门（T4/T11 断言）
- P-04 颗粒周期性：轻压自相关峰 ${_fmt(pencilMetrics['lightAutocorrPeak'])}
  → ${pencilMetrics['lightAutocorrPeakVerdict']}（冻结上限 ${NaturalMediaFrozen.autocorrPeakMax}）

''');
  }
  if (brushMetrics != null) {
    _notesBuffer.write('''
## 毛笔（v1）

- P-05 固定对称 taper：无尾部降压横画在距尾 2×size 处宽度比
  ${_fmt(brushMetrics['noTailDropTailRatio'])}（N8 无降压口径要求 ≥ 0.70，v1 低于 = 缺陷被检出）
- P-06 有尾部降压的捺同位置宽度比 ${_fmt(brushMetrics['naTailRatio'])}（对照组记录）
- P-07 轻重宽度量程 ${_fmt(brushMetrics['brushWidthRatioP02P08'])}（N6 对照：v1 靠
  thinning=1.0 本就 ≥ 2.2，v2 不得低于该量程）

''');
  }
  Directory(kOutRoot).createSync(recursive: true);
  File('$kOutRoot/NOTES-v1.md').writeAsStringSync(_notesBuffer.toString());
}

String _fmt(Object? v) =>
    v is double ? v.toStringAsFixed(3) : (v?.toString() ?? 'n/a');
