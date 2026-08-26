import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../elements/elements.dart';

import 'smart_layout_content.dart';
import 'smart_layout_document.dart';
import 'smart_layout_plan.dart';

/// 版式模板：消费结构层内容（SmartLayoutContent），产出本页排版计划。
/// 确定性契约：同一 content + ctx 永远产出同一 plan；坐标全部由模板计算，
/// AI 只负责风格与角色（方案二）。
abstract class SmartLayoutTemplate {
  String get id;

  SmartLayoutPlan? layout(SmartLayoutContent content, SmartLayoutTemplateContext ctx);
}

/// 模板运行上下文（控制器装配；承载 all-or-nothing 与导出所需信息）。
@immutable
class SmartLayoutTemplateContext {
  const SmartLayoutTemplateContext({
    required this.response,
    required this.excludedIds,
    required this.failures,
    required this.removeIds,
    required this.failedStrokeIds,
    required this.removalRects,
    required this.failureRects,
  });

  final SmartLayoutResponse response;
  final Set<ElementId> excludedIds;
  final List<SmartLayoutFailureInfo> failures;
  final List<ElementId> removeIds;
  final List<ElementId> failedStrokeIds;
  final List<Rect> removalRects;
  final List<Rect> failureRects;
}
