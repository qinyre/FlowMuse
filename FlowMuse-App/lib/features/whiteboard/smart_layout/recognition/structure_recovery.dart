library;

import 'dart:math' as math;
import 'dart:convert';

import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/recognition/recognition_models.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/recognition/recognition_pipeline.dart';
import '../snapshot/deterministic_hash.dart';
import '../snapshot/layout_page_snapshot.dart' show conservativeVisualBounds;

/// 结构恢复（spec §7）：本地规则优先；结构请求触发条件命中才发
///（至多一次）；模型只改角色/分组/顺序/层级，正文与几何一律本地值。

/// 本地规则阈值（值对象，可注入；spec §7）。
class StructurePolicy {
  const StructurePolicy({
    this.indentToleranceLineHeights = 0.6,
    this.levelStepLineHeights = 1.0,
    this.titleZoneRatio = 0.25,
    this.titleLineHeightRatio = 1.3,
    this.titleBodyGapRatio = 1.15,
    this.captionGapLineHeights = 1.0,
  });

  /// 左缘 x 缩进一致容差（×行高）。
  final double indentToleranceLineHeights;

  /// 每进一级的缩进差（≥ 该倍数×行高）。
  final double levelStepLineHeights;

  /// 标题候选须位于内容前 25% 纵向区间。
  final double titleZoneRatio;

  /// 局部行高 ≥ 该倍数×正文行高中位数。
  final double titleLineHeightRatio;

  /// 相邻正文落差 ≥ 该倍数。
  final double titleBodyGapRatio;

  /// 图注与目标间距 < 该倍数×行高。
  final double captionGapLineHeights;
}

/// 结构恢复产物（R6 语义适配输入）。
class StructureResult {
  const StructureResult({
    required this.units,
    required this.readingOrder,
    required this.roles,
    required this.listGroups,
    required this.captions,
    required this.warnings,
    required this.usedModel,
    this.modelRejected = false,
    this.conflictedUnitIds = const {},
  });

  /// 全部 unit（typed/ink/figure/preserved），含本地正文与几何（真值）。
  final List<RecognitionUnitInput> units;
  final List<String> readingOrder;

  /// unitId → 角色 wire 名（title/body/caption/listItem/other）。
  final Map<String, String> roles;
  final List<RecognitionListGroup> listGroups;
  final List<RecognitionCaption> captions;
  final List<String> warnings;

  /// 未消解的结构冲突，必须阻止该单元的自动转换。
  final Set<String> conflictedUnitIds;

  /// 是否发出过结构请求。
  final bool usedModel;

  /// 模型结果被拒/合并失败，回退本地保守结构。
  final bool modelRejected;
}

final RegExp _orderedNumberPattern = RegExp(r'^\d{1,3}[.、)）](?!\d)');
final RegExp _bulletPattern = RegExp(r'^[-•·](?![-•·])');
final RegExp _sentenceEndPattern = RegExp(r'[。！？；]$');

/// 结构恢复器：实现 [RecognitionStructureRecoverer]，由 pipeline 在
/// structuring 阶段调用。
class StructureRecovery implements RecognitionStructureRecoverer {
  const StructureRecovery({this.policy = const StructurePolicy()});

  final StructurePolicy policy;

  @override
  Future<Object?> recover(RecognitionStructureInput input) async {
    // ---- 1. unit 构建（本地真值：正文与几何）----
    final units = buildUnits(input);

    // ---- 2. 本地规则：阅读顺序 / 角色 / 列表 / 图注 ----
    final local = _localStructure(units);

    // ---- 3. 结构请求触发表（§7，与 §6.1 复核触发表分离，至多一次）----
    final trigger = structureRequestTriggerOf(units, local, policy);
    if (trigger == null) {
      return local;
    }

    // ---- 4. 发一次结构请求（§3.4 wire；概览图可选，首版不携带）----
    final request = RecognitionStructureRequest(
      operationId: input.capture.operationId,
      requestId: 'struct-${input.capture.operationId}',
      pageId: input.capture.pageId,
      sceneRevision: input.capture.sceneRevision,
      contentFingerprint: input.capture.contentFingerprint,
      generation: input.capture.generation,
      units: units,
      textFingerprint: _textFingerprintOf(units),
    );
    final model = await input.sendStructureRequest(request);
    if (model == null) {
      // 验证失败/预算不足/取消外失败：回退本地保守结构（§7 末条）。
      return StructureResult(
        units: units,
        readingOrder: local.readingOrder,
        roles: local.roles,
        listGroups: local.listGroups,
        captions: local.captions,
        warnings: [...local.warnings, '结构请求未获有效结果（$trigger），回退本地保守结构'],
        usedModel: true,
        modelRejected: true,
      );
    }

    // ---- 5. 合并：模型只改角色/分组/顺序/层级；冲突未解标 uncertain 保留 ----
    return _merge(units, local, model);
  }

  /// 从识别产物与场景原生元素构建 unit 集。
  ///
  /// - ink：status=recognized/uncertain 的区域（正文=识别转写）；
  /// - preserved：unreadable/nonText/无结果的区域（unitId=native:<最小源>，
  ///   见 §1 命名空间——保留单元不进消费集合）与场景形状类元素；
  /// - typed：场景文本元素（绕过 OCR，§7.4）；
  /// - figure：场景图片元素。
  List<RecognitionUnitInput> buildUnits(RecognitionStructureInput input) {
    final units = <RecognitionUnitInput>[];
    final scene = input.capture.scene;
    // 区域成员覆盖集：识别链中资产失败等原因被丢弃分区的笔迹不属任何
    // 区域记录，但识别账本仍注册并保留它们——必须补保留障碍单元，
    // 否则语义文档块覆盖不了账本全集，候选链守恒断言 fail closed
    //（2026-09-18 真机：两个零长度墨点致 semantic-contract-broken）。
    final coveredSourceIds = <String>{
      for (final record in input.regionRecords) ...record.targetSourceIds,
    };
    for (final record in input.regionRecords) {
      final outcome = input.regionOutcomes[record.regionId];
      final isRecognized =
          outcome != null &&
          (outcome.status == RecognitionRegionStatus.recognized ||
              outcome.status == RecognitionRegionStatus.uncertain);
      if (isRecognized && (outcome.text ?? '').trim().isNotEmpty) {
        units.add(
          RecognitionUnitInput(
            unitId: 'ink:${record.regionId}',
            kind: RecognitionUnitKind.ink,
            text: outcome.text,
            bounds: record.bounds,
            lineHintHeight: record.localLineHeight > 0
                ? record.localLineHeight
                : record.bounds.height,
            roleHint: _roleHintOfText(outcome.text!),
          ),
        );
      } else {
        // 保留：整区域一个障碍单元。
        units.add(
          RecognitionUnitInput(
            unitId: 'native:${_minId(record.targetSourceIds)}',
            kind: RecognitionUnitKind.preserved,
            bounds: record.bounds,
          ),
        );
      }
    }
    for (final element in scene.activeElements) {
      // 背景元素（页面框/PDF 底图）不构成内容单元——与旧入口第 0 步
      // page-furniture 剥离同口径，语义适配同样排除其源。
      if (element.isCanvasPage || element.isPdfBackground) continue;
      if (element is TextElement) {
        units.add(
          RecognitionUnitInput(
            unitId: 'native:${element.id.value}',
            kind: RecognitionUnitKind.typed,
            text: element.text.isEmpty ? ' ' : element.text,
            bounds: RecognitionBounds(
              left: element.x,
              top: element.y,
              width: element.width,
              height: element.height,
            ),
            lineHintHeight: element.fontSize > 0
                ? element.fontSize * 1.25
                : element.height,
            roleHint: _roleHintOfText(element.text),
          ),
        );
      } else if (element is ImageElement) {
        units.add(
          RecognitionUnitInput(
            unitId: 'native:${element.id.value}',
            kind: RecognitionUnitKind.figure,
            bounds: RecognitionBounds(
              left: element.x,
              top: element.y,
              width: element.width,
              height: element.height,
            ),
          ),
        );
      } else if (element is FreedrawElement) {
        // 无区域覆盖的孤儿笔迹（资产失败丢弃分区等）：保留障碍单元。
        if (!coveredSourceIds.contains(element.id.value)) {
          final visual = conservativeVisualBounds(element);
          units.add(
            RecognitionUnitInput(
              unitId: 'native:${element.id.value}',
              kind: RecognitionUnitKind.preserved,
              bounds: RecognitionBounds(
                left: visual.left,
                top: visual.top,
                width: visual.width,
                height: visual.height,
              ),
            ),
          );
        }
      } else {
        units.add(
          RecognitionUnitInput(
            unitId: 'native:${element.id.value}',
            kind: RecognitionUnitKind.preserved,
            bounds: RecognitionBounds(
              left: element.x,
              top: element.y,
              width: element.width,
              height: element.height,
            ),
          ),
        );
      }
    }
    return List.unmodifiable(units);
  }

  static RecognitionRoleHint _roleHintOfText(String text) {
    if (_orderedNumberPattern.hasMatch(text) || _bulletPattern.hasMatch(text)) {
      return RecognitionRoleHint.listItem;
    }
    return RecognitionRoleHint.body;
  }

  // ---- 本地结构 ----

  StructureResult _localStructure(List<RecognitionUnitInput> units) {
    final order = _localReadingOrder(units);
    final textUnits = [
      for (final id in order) units.firstWhere((unit) => unit.unitId == id),
    ].where((unit) => unit.isTextUnit).toList();
    final roles = <String, String>{};
    final warnings = <String>[];

    // 列表检测（规则 1）。
    final groups = _detectListGroups(textUnits);
    final listMemberIds = <String>{};
    for (final group in groups) {
      listMemberIds.addAll(group.members);
    }
    for (final unit in textUnits) {
      if (listMemberIds.contains(unit.unitId)) {
        roles[unit.unitId] = 'listItem';
      } else {
        roles[unit.unitId] = 'body';
      }
    }

    // 标题检测（规则 2）。
    final titleUnit = _detectTitle(textUnits);
    if (titleUnit != null) {
      roles[titleUnit.unitId] = 'title';
    }

    // 图注检测（规则 3）。
    final captions = _detectCaptions(units);
    for (final caption in captions) {
      roles[caption.captionUnitId] = 'caption';
    }

    return StructureResult(
      units: units,
      readingOrder: order,
      roles: Map.unmodifiable(roles),
      listGroups: List.unmodifiable(groups),
      captions: List.unmodifiable(captions),
      warnings: List.unmodifiable(warnings),
      usedModel: false,
    );
  }

  /// 阅读顺序（本地）：按（行带，左缘）排序——行带 = top 按中位行高
  /// 量化，同带内按 x。
  List<String> _localReadingOrder(List<RecognitionUnitInput> units) {
    if (units.isEmpty) return const [];
    final lineHeight = _medianLineHeight(units);
    final sorted = [...units]
      ..sort((a, b) {
        final bandA = (a.bounds.top / lineHeight).floor();
        final bandB = (b.bounds.top / lineHeight).floor();
        if (bandA != bandB) return bandA.compareTo(bandB);
        return a.bounds.left.compareTo(b.bounds.left);
      });
    return [for (final unit in sorted) unit.unitId];
  }

  double _medianLineHeight(List<RecognitionUnitInput> units) {
    final heights = [
      for (final unit in units)
        unit.lineHintHeight ?? math.max(1.0, unit.bounds.height),
    ]..sort();
    if (heights.isEmpty) return 1.0;
    return heights[heights.length ~/ 2];
  }

  /// 规则 1：阅读顺序上连续 ≥2 个文本单元，匹配编号（分隔符后不得紧跟
  /// 数字——排除 "1.2" 小数）或项目符号，且左缘 x 缩进一致（容差
  /// 0.6×行高）。编号连续是强证据；孤立的 "1.2" 不成列表。
  /// level 由缩进层级差（每 ≥1×行高差进一级）推导；子组首个成员的缩进带
  /// 对应最近上方父项。
  List<RecognitionListGroup> _detectListGroups(
    List<RecognitionUnitInput> textUnits,
  ) {
    // 1. 找编号/符号候选并按缩进带分桶。
    final candidates = <_ListCandidate>[];
    for (var i = 0; i < textUnits.length; i++) {
      final unit = textUnits[i];
      final text = unit.text ?? '';
      final number = _leadingNumber(text);
      final bullet = _bulletPattern.hasMatch(text);
      if (number == null && !bullet) continue;
      final lineHeight =
          unit.lineHintHeight ?? math.max(1.0, unit.bounds.height);
      candidates.add(
        _ListCandidate(
          index: i,
          unit: unit,
          number: number,
          bullet: bullet,
          lineHeight: lineHeight,
        ),
      );
    }
    if (candidates.length < 2) return const [];

    // 2. 连续段切分：阅读序相邻且缩进差 < 层级步进 × 行高 才可能同组；
    //    同段内缩进差 < 容差 × 行高 且编号连续（无序项除外）成组。
    final bands = <int>[];
    for (final candidate in candidates) {
      bands.add(candidate.indentBand);
    }
    final groups = <List<_ListCandidate>>[];
    var current = <_ListCandidate>[];
    for (final candidate in candidates) {
      if (current.isEmpty) {
        current.add(candidate);
        continue;
      }
      final last = current.last;
      final adjacent =
          candidate.index == last.index + 1 &&
          (candidate.unit.bounds.left - last.unit.bounds.left).abs() <
              policy.levelStepLineHeights *
                  math.max(candidate.lineHeight, last.lineHeight);
      if (!adjacent) {
        groups.add(current);
        current = <_ListCandidate>[candidate];
        continue;
      }
      current.add(candidate);
    }
    if (current.isNotEmpty) groups.add(current);

    final listGroups = <RecognitionListGroup>[];
    var groupIndex = 0;
    for (final group in groups) {
      // 同组条件：全部同缩进带（容差内）且（有序：编号连续或从 1 起；
      // 无序：符号开头）。单项不成组（顶层 ≥2）。
      final first = group.first;
      var sameBand = true;
      var numberingOk = true;
      for (var i = 0; i < group.length; i++) {
        final candidate = group[i];
        if ((candidate.unit.bounds.left - first.unit.bounds.left).abs() >
            policy.indentToleranceLineHeights * candidate.lineHeight) {
          sameBand = false;
          break;
        }
        if (first.number != null) {
          if (candidate.number == null) numberingOk = false;
        } else if (!candidate.bullet) {
          numberingOk = false;
        }
      }
      if (!sameBand || !numberingOk) continue;
      if (group.length < 2) continue;
      groupIndex++;
      final members = [for (final candidate in group) candidate.unit.unitId];
      final ordered = first.number != null;
      listGroups.add(
        RecognitionListGroup(
          groupId: 'g$groupIndex',
          members: members,
          level: 1,
          listType: ordered
              ? RecognitionListType.ordered
              : RecognitionListType.unordered,
          startNumber: ordered ? first.number : null,
        ),
      );
    }

    // 3. 嵌套：缩进带更深的组挂靠最近上方父项（level = 父 + 1）。
    RecognitionUnitInput? unitOf(String id) {
      for (final unit in textUnits) {
        if (unit.unitId == id) return unit;
      }
      return null;
    }

    final result = <RecognitionListGroup>[];
    for (var i = 0; i < listGroups.length; i++) {
      final group = listGroups[i];
      var level = 1;
      String? parentUnitId;
      final memberUnit = unitOf(group.members.first);
      final memberLeft = memberUnit?.bounds.left ?? 0;
      final memberLineHeight = memberUnit?.lineHintHeight ?? 1.0;
      for (var j = i - 1; j >= 0; j--) {
        final other = listGroups[j];
        final otherUnit = unitOf(other.members.first);
        if (otherUnit == null) continue;
        final indentDiff = memberLeft - otherUnit.bounds.left;
        if (indentDiff >=
            policy.levelStepLineHeights *
                math.max(memberLineHeight, otherUnit.lineHintHeight ?? 1.0)) {
          level = other.level + 1;
          // 父项 = 父组中最近上方（阅读序）的成员。
          parentUnitId = other.members.last;
          break;
        }
      }
      result.add(
        RecognitionListGroup(
          groupId: group.groupId,
          members: group.members,
          level: level,
          parentUnitId: parentUnitId,
          listType: group.listType,
          startNumber: group.startNumber,
        ),
      );
    }
    return result;
  }

  /// 规则 2：标题四证据——内容前 25% 纵向区间、局部行高 ≥1.3×正文行高
  /// 中位数、单行且无句末标点（。！？；）、相邻正文落差 ≥1.15×；
  /// 任一不满足一律 body。
  RecognitionUnitInput? _detectTitle(List<RecognitionUnitInput> textUnits) {
    if (textUnits.isEmpty) return null;
    var pageTop = double.infinity;
    var pageBottom = double.negativeInfinity;
    for (final unit in textUnits) {
      pageTop = math.min(pageTop, unit.bounds.top);
      pageBottom = math.max(pageBottom, unit.bounds.top + unit.bounds.height);
    }
    final zone = pageTop + (pageBottom - pageTop) * policy.titleZoneRatio;
    RecognitionUnitInput? best;
    for (final unit in textUnits) {
      if (unit.bounds.top > zone) continue;
      final text = unit.text ?? '';
      if (text.contains('\n')) continue;
      if (_sentenceEndPattern.hasMatch(text.trim())) continue;
      final lineHeight =
          unit.lineHintHeight ?? math.max(1.0, unit.bounds.height);
      // 中位数排除候选自身：候选自身的大行高不得抬高自己的门槛。
      final othersMedian = _medianLineHeight(
        textUnits.where((other) => other.unitId != unit.unitId).toList(),
      );
      if (lineHeight < policy.titleLineHeightRatio * othersMedian) {
        continue;
      }
      // 相邻正文落差：最近下方文本单元行高显著更小。
      RecognitionUnitInput? bodyBelow;
      for (final other in textUnits) {
        if (other.unitId == unit.unitId) continue;
        if (other.bounds.top >= unit.bounds.top + unit.bounds.height &&
            _horizontalOverlap(unit.bounds, other.bounds) &&
            (bodyBelow == null || other.bounds.top < bodyBelow.bounds.top)) {
          bodyBelow = other;
        }
      }
      if (bodyBelow == null) continue;
      final bodyLineHeight =
          bodyBelow.lineHintHeight ?? math.max(1.0, bodyBelow.bounds.height);
      if (lineHeight < policy.titleBodyGapRatio * bodyLineHeight) continue;
      if (best == null || unit.bounds.top < best.bounds.top) {
        best = unit;
      }
    }
    return best;
  }

  bool _horizontalOverlap(RecognitionBounds a, RecognitionBounds b) {
    return a.left < b.left + b.width && b.left < a.left + a.width;
  }

  /// 规则 3：文本单元紧邻 figure/preserved（同一缩进带、间距 <1 行高）且
  /// 以 图/注/Fig 类起始词开头 → caption 候选；无唯一明确目标不入关系。
  List<RecognitionCaption> _detectCaptions(List<RecognitionUnitInput> units) {
    final captions = <RecognitionCaption>[];
    final figureUnits = units
        .where(
          (unit) =>
              unit.kind == RecognitionUnitKind.figure ||
              unit.kind == RecognitionUnitKind.preserved,
        )
        .toList();
    for (final unit in units) {
      if (!unit.isTextUnit) continue;
      final text = (unit.text ?? '').trim();
      if (!_captionStartPattern.hasMatch(text)) continue;
      final lineHeight =
          unit.lineHintHeight ?? math.max(1.0, unit.bounds.height);
      final targets = <RecognitionUnitInput>[];
      for (final figure in figureUnits) {
        final gap = _gap(unit.bounds, figure.bounds);
        if (gap < policy.captionGapLineHeights * lineHeight &&
            _horizontalOverlap(unit.bounds, figure.bounds)) {
          targets.add(figure);
        }
      }
      // 唯一目标：取最近的一个；无目标或多目标歧义不入关系。
      if (targets.length == 1) {
        captions.add(
          RecognitionCaption(
            captionUnitId: unit.unitId,
            targetUnitId: targets.single.unitId,
          ),
        );
      }
    }
    return captions;
  }

  static final RegExp _captionStartPattern = RegExp(r'^(图|注|Fig|Figure)');

  double _gap(RecognitionBounds a, RecognitionBounds b) {
    final dx = math.max(
      0.0,
      math.max(a.left - (b.left + b.width), b.left - (a.left + a.width)),
    );
    final dy = math.max(
      0.0,
      math.max(a.top - (b.top + b.height), b.top - (a.top + a.height)),
    );
    if (dx == 0 && dy == 0) return 0;
    return math.sqrt(dx * dx + dy * dy);
  }

  // ---- 触发表（§7；与复核触发表分离）----

  /// 结构请求触发条件（任一命中才发，至多一次）。
  String? structureRequestTriggerOf(
    List<RecognitionUnitInput> units,
    StructureResult local,
    StructurePolicy policy,
  ) {
    // 1. 候选列表组 >1 且归属歧义（存在可能属于多个组的文本单元缩进带）。
    if (local.listGroups.length > 1) {
      final ambiguous = _hasAmbiguousGroupMembership(units, local, policy);
      if (ambiguous) return 'listGroupAmbiguity';
    }
    // 2. 多栏重叠判定不一致（文本单元包围盒嵌套——同行并排属正常，
    //    一段文字框完整包含另一段才是布局矛盾）。
    for (var i = 0; i < units.length; i++) {
      for (var j = i + 1; j < units.length; j++) {
        if (!units[i].isTextUnit || !units[j].isTextUnit) continue;
        if (_contains(units[i].bounds, units[j].bounds) ||
            _contains(units[j].bounds, units[i].bounds)) {
          return 'columnOverlapInconsistency';
        }
      }
    }
    // 3. caption 候选无唯一目标（以 图/注/Fig 开头但本地未建立关系的）。
    for (final unit in units) {
      if (!unit.isTextUnit) continue;
      final text = (unit.text ?? '').trim();
      if (!_captionStartPattern.hasMatch(text)) continue;
      final linked = local.captions.any(
        (caption) => caption.captionUnitId == unit.unitId,
      );
      if (!linked) return 'captionWithoutUniqueTarget';
    }
    // 4. 图文相邻关系冲突（同一 figure 被多个 caption 候选最近匹配）。
    final targetCount = <String, int>{};
    for (final caption in local.captions) {
      targetCount[caption.targetUnitId] =
          (targetCount[caption.targetUnitId] ?? 0) + 1;
    }
    for (final count in targetCount.values) {
      if (count > 1) return 'figureCaptionConflict';
    }
    return null;
  }

  bool _hasAmbiguousGroupMembership(
    List<RecognitionUnitInput> units,
    StructureResult local,
    StructurePolicy policy,
  ) {
    // 归属歧义：非列表成员的文本单元落在两个组的缩进带之间。
    final memberIds = {for (final group in local.listGroups) ...group.members};
    final byId = {for (final unit in units) unit.unitId: unit};
    final groupLefts = <double>[];
    for (final group in local.listGroups) {
      final unit = byId[group.members.first];
      if (unit != null) groupLefts.add(unit.bounds.left);
    }
    if (groupLefts.length < 2) return false;
    groupLefts.sort();
    for (final unit in units) {
      if (!unit.isTextUnit || memberIds.contains(unit.unitId)) continue;
      for (var i = 0; i + 1 < groupLefts.length; i++) {
        if (unit.bounds.left > groupLefts[i] &&
            unit.bounds.left < groupLefts[i + 1]) {
          return true;
        }
      }
    }
    return false;
  }

  bool _contains(RecognitionBounds outer, RecognitionBounds inner) {
    return outer.left <= inner.left &&
        inner.left + inner.width <= outer.left + outer.width &&
        outer.top <= inner.top &&
        inner.top + inner.height <= outer.top + outer.height &&
        inner.width < outer.width &&
        inner.height < outer.height;
  }

  // ---- 合并（§7 末段）----

  /// 模型只改角色/分组/顺序/层级；正文与几何一律本地（units 保持本地
  /// 实例）。模型分组/图注引用的 id 必须存在（DTO 已校验）；冲突未解
  ///（模型把本地标题改成 body 且给出 other 等）保留本地并记警告。
  StructureResult _merge(
    List<RecognitionUnitInput> units,
    StructureResult local,
    RecognitionStructureResponse model,
  ) {
    final warnings = <String>[...local.warnings];
    final conflicts = <String>{...local.conflictedUnitIds};
    final roles = <String, String>{};
    for (final entry in model.roles) {
      roles[entry.unitId] = entry.role.wireName;
    }
    // 角色合并：模型 other 与本地 title 冲突 → 保留本地（标 uncertain）。
    for (final entry in local.roles.entries) {
      final modelRole = roles[entry.key];
      if (modelRole == 'other' && entry.value != 'other') {
        roles[entry.key] = entry.value;
        conflicts.add(entry.key);
        warnings.add('角色冲突保留本地（${entry.key}: ${entry.value}）');
      }
    }
    return StructureResult(
      units: units,
      readingOrder: model.readingOrder,
      roles: Map.unmodifiable(roles),
      listGroups: model.listGroups,
      captions: model.captions,
      warnings: List.unmodifiable(warnings),
      conflictedUnitIds: Set.unmodifiable(conflicts),
      usedModel: true,
    );
  }

  String _textFingerprintOf(List<RecognitionUnitInput> units) {
    // 复用 VM/dart2js 一致的双 32 位车道；JSON 保留单元边界与完整 ID。
    return fingerprint64(
      jsonEncode([
        for (final unit in units) [unit.unitId, unit.text],
      ]),
    );
  }
}

int? _leadingNumber(String text) {
  final match = _orderedNumberPattern.firstMatch(text);
  if (match == null) return null;
  return int.tryParse(match.group(0)!.substring(0, match.group(0)!.length - 1));
}

String _minId(List<String> ids) {
  var min = ids.first;
  for (final id in ids) {
    if (id.compareTo(min) < 0) min = id;
  }
  return min;
}

class _ListCandidate {
  _ListCandidate({
    required this.index,
    required this.unit,
    required this.number,
    required this.bullet,
    required this.lineHeight,
  });

  final int index;
  final RecognitionUnitInput unit;
  final int? number;
  final bool bullet;
  final double lineHeight;

  int get indentBand => (unit.bounds.left / lineHeight).floor();
}
