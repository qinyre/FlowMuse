import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/painting.dart';

import '../../editor_core/src/rendering/font_resolver.dart';
import 'smart_layout_design_tokens.dart';
import 'text_measure_cache.dart';
import 'text_measure_result.dart';

export 'text_measure_result.dart';

/// 真实文本测量适配器（任务 V3-300A，计划书 §4.7）。
///
/// 必须经编辑器真实 `TextPainter` + `FontResolver` 在目标宽度测量，
/// 与 `TextRenderer.buildTextPainter` 采用同一构造路径（同
/// `FontResolver.resolve` 基样式、同 TextSpan/textAlign/textDirection
/// 配置），一致性由对照测试核对宽度/高度保障。
/// 禁止字符数估算、禁止 ellipsis/maxLines 掩盖溢出（源码门禁测试拦截）。
///
/// 对齐不参与测量：left/center/right 不改变宽度/高度/行数，故不设参数；
/// 文本方向影响 bidi 基向，参数默认 ltr 与 `TextRenderer` 现行为一致，
/// 调用方对 RTL 语义块应显式传 [ui.TextDirection.rtl]。
class TextMeasureAdapter {
  final SmartLayoutDesignTokens tokens;

  /// 测量缓存；容量/失效可测（见 [TextMeasureCache]）。
  final TextMeasureCache cache;

  TextMeasureAdapter({
    this.tokens = SmartLayoutDesignTokens.v1,
    TextMeasureCache? cache,
  }) : cache = cache ?? TextMeasureCache();

  /// 缓存键：字体族前缀（供按族失效）+ 全参数规范串。
  /// 任何影响结果的参数都进键；null/∞ 的 maxWidth 归一为 `inf`。
  @visibleForTesting
  String cacheKey({
    required String text,
    required double fontSize,
    required double lineHeight,
    required String fontFamily,
    required double maxWidth,
    required ui.TextDirection direction,
  }) {
    final widthKey = maxWidth.isFinite ? maxWidth.toString() : 'inf';
    return '$fontFamily\u241f$fontSize\u241f$lineHeight\u241f$widthKey'
        '\u241f${direction.name}\u241f$text';
  }

  /// 在目标宽度 [maxWidth]（null = 不限宽）下测量 [text]。
  ///
  /// [fontSize] 必须为正有限值；[lineHeight] 缺省取令牌基线（1.25），
  /// 传非正值抛 [ArgumentError]——测量不接受无意义的排版参数。
  TextMeasureResult measure({
    required String text,
    required String fontFamily,
    required double fontSize,
    double? lineHeight,
    double? maxWidth,
    ui.TextDirection direction = ui.TextDirection.ltr,
  }) {
    _checkFinitePositive(fontSize, 'fontSize');
    final effectiveLineHeight = lineHeight ?? tokens.lineHeight;
    _checkFinitePositive(effectiveLineHeight, 'lineHeight');
    final bounded = maxWidth ?? double.infinity;
    if (bounded.isNaN) {
      throw ArgumentError.value(maxWidth, 'maxWidth', '必须为有限正数或 null');
    }
    if (bounded.isFinite && bounded <= 0) {
      throw ArgumentError.value(maxWidth, 'maxWidth', '必须为有限正数或 null');
    }
    if (text.isEmpty) return TextMeasureResult.empty;

    final key = cacheKey(
      text: text,
      fontSize: fontSize,
      lineHeight: effectiveLineHeight,
      fontFamily: fontFamily,
      maxWidth: bounded,
      direction: direction,
    );
    final cached = cache.lookup(key);
    if (cached != null) return cached;

    // 与 TextRenderer.buildTextPainter 相同的构造路径：颜色不参与度量，
    // 取不透明黑；基样式仅 fontSize/height，字体族交给 FontResolver。
    final style = FontResolver.resolve(
      fontFamily,
      baseStyle: TextStyle(
        color: const Color(0xFF000000),
        fontSize: fontSize,
        height: effectiveLineHeight,
      ),
    );
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textAlign: TextAlign.left,
      textDirection: direction,
    );
    try {
      painter.layout(maxWidth: bounded);
      var widestLine = 0.0;
      var lineCount = 0;
      for (final line in painter.computeLineMetrics()) {
        lineCount++;
        // LineMetrics.width：本行最左字形左缘到最右字形右缘（不含行尾
        // 空白），与 painter.width（可含尾随空白）互补做溢出判定。
        widestLine = math.max(widestLine, line.width);
      }
      // TextPainter.width 会被 maxWidth 钳制（约束值即返回值），真实最宽
      // 行宽在 LineMetrics.width；两者取大才是诚实宽度——原子簇过宽时
      // 如实暴露而不是跟随钳制值假装放得下。
      final width = math.max(painter.width, widestLine);
      final result = TextMeasureResult(
        width: width,
        height: painter.height,
        lineCount: lineCount,
        maxWidth: bounded,
        overflows: bounded.isFinite && width > bounded + _overflowEpsilon,
      );
      cache.store(key, result);
      return result;
    } finally {
      painter.dispose();
    }
  }

  /// 溢出判定容差：布局舍入在 1e-6 量级内不算溢出。
  static const double _overflowEpsilon = 1e-6;

  static void _checkFinitePositive(double value, String name) {
    if (value.isNaN || !value.isFinite || value <= 0) {
      throw ArgumentError.value(value, name, '必须为有限正数');
    }
  }
}
