import 'dart:ui' as ui;

import '../../core/elements/elements.dart';
import '../../core/math/math.dart';
import '../rough/draw_style.dart';
import 'directional_brush_envelope.dart';
import 'natural_media_path_cache.dart';
import 'natural_media_stroke_sampler.dart';

// ---------------------------------------------------------------------------
// 毛笔 v2 渲染器（计划 §3.7，T5）：消费共享采样 plan 的方向性软头毛笔。
//
// 结构契约：每元素主要 drawPath ≤2（主体方向性包络 + 可选毫丝复合
// Path）、saveLayer = 0、不申请 shader；几何与种子全部来自
// NaturalMediaStrokeSampler（四条渲染链共用真源），渲染器只做
// "plan → DirectionalBrushEnvelope → drawPath"，不重新推导几何。
// ---------------------------------------------------------------------------

class BrushPenStrokeRendererV2 {
  BrushPenStrokeRendererV2._();

  /// plan 构建计数探针（T5 验收：证明普通静态重绘的实际构造成本；
  /// 本任务默认不新增静态缓存）。
  static int planBuildCount = 0;

  /// 测试用复位。
  static void resetPlanBuildCountForTest() => planBuildCount = 0;

  /// 远端湿墨分段渲染：owned 边范围 + 全局索引偏移 + 起收所有权
  ///（§3.4；中段分块不带起收帽，边界由 join 与终点顶点衔接）。
  static void draw(
    ui.Canvas canvas,
    FreedrawElement element,
    DrawStyle style, {
    int? ownedEdgeStart,
    int? ownedEdgeEndExclusive,
    int edgeIndexOffset = 0,
    bool ownsStrokeHead = true,
    bool ownsStrokeTail = true,
  }) {
    final profile = BrushRenderProfile.forType(BrushType.brushPen);
    final abs = [
      for (final p in element.points) Point(p.x + element.x, p.y + element.y),
    ];
    // T4-C 条件缓存：整笔静态渲染复用 Path。绕过：owned 分段与起收
    // 所有权让渡的调用（远端湿墨），以及 isComplete=false 的本地湿墨
    // 帧（几何逐帧追加，入缓存会命中首帧 Picture 冻结活动笔迹；与
    // 铅笔渲染器同判据，详见其注释）。
    final useCache =
        ownedEdgeStart == null &&
        ownsStrokeHead &&
        ownsStrokeTail &&
        element.isComplete;
    final cacheKey = useCache
        ? NaturalMediaPathCache.keyFor(
            elementId: element.id.value,
            version: element.version,
            versionNonce: element.versionNonce,
            renderVersion: BrushRenderVersion.naturalMediaV2.index,
            isComplete: element.isComplete,
            strokeWidth: style.strokeWidth,
            strokeColor: style.strokeColor,
            opacity: style.opacity,
          )
        : null;
    final cached = cacheKey == null
        ? null
        : NaturalMediaPathCache.lookup(cacheKey);
    if (cached != null) {
      canvas.drawPicture(cached.picture);
      return;
    }

    planBuildCount++;
    final plan = NaturalMediaStrokeSampler.sample(
      strokeId: element.id.value,
      points: abs,
      pressures: element.pressures,
      strokeWidth: style.strokeWidth,
      brushType: BrushType.brushPen,
      isComplete: element.isComplete,
      ownedEdgeStart: ownedEdgeStart,
      ownedEdgeEndExclusive: ownedEdgeEndExclusive,
      edgeIndexOffset: edgeIndexOffset,
    );

    final paths = DirectionalBrushEnvelope.build(
      plan,
      style.strokeWidth,
      isComplete: element.isComplete,
      ownsStrokeHead: ownsStrokeHead,
      ownsStrokeTail: ownsStrokeTail,
    );
    if (useCache) {
      // miss：恒等矩阵画布录制一次 Picture（主体 + 毫丝），存缓存后
      // 立即 drawPicture 重放——miss 与命中像素逐字节一致（同一
      // Picture 对象），也避免直绘/录制两份分支漂移。
      final recorder = ui.PictureRecorder();
      final cached = ui.Canvas(recorder);
      cached.drawPath(paths.body, _paint(style, 1.0));
      if (paths.hasStrands) {
        // 毫丝是开放线段：fill 语义下零面积不可见（T9 修正），按描边
        // 细线渲染（round cap，~0.8px，与 SVG stroke 同口径）。
        cached.drawPath(
          paths.strands,
          _paint(style, profile.brushV2StrandAlpha)
            ..style = ui.PaintingStyle.stroke
            ..strokeWidth = 0.8
            ..strokeCap = ui.StrokeCap.round,
        );
      }
      final picture = recorder.endRecording();
      NaturalMediaPathCache.store(
        cacheKey!,
        CachedNaturalMediaPaths(picture: picture),
      );
      canvas.drawPicture(picture);
      return;
    }
    canvas.drawPath(paths.body, _paint(style, 1.0));
    if (paths.hasStrands) {
      canvas.drawPath(
        paths.strands,
        _paint(style, profile.brushV2StrandAlpha)
          ..style = ui.PaintingStyle.stroke
          ..strokeWidth = 0.8
          ..strokeCap = ui.StrokeCap.round,
      );
    }
  }

  static ui.Paint _paint(DrawStyle style, double alpha) => ui.Paint()
    ..color = style.strokeColor.withValues(
      alpha: style.strokeColor.a * alpha * style.opacity,
    );
}
