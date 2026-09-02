/// V3-605A：跨端 smoke 套件——目标符号 [PlatformSmokeSuite]。
///
/// 入口→commit→undo→reopen 四段全真链（宿主 flutter test 形态，各平台
/// 同一套件）：
/// 1) 入口：真实 [MarkdrawController] + loadFromContent（真实 excalidraw
///    内容装载）；
/// 2) commit：真实 v3 patch（builder 全量不变量 + reducer 折叠）经
///    controller.applyResult(reduced.commitResult) 落地——与 compare-and-
///    commit（V3-502A）提交同通道；
/// 3) undo：controller.undo() 精确回提交前状态；
/// 4) reopen：serializeScene(excalidraw) → 新 controller.loadFromContent
///    重开——元素集与内容字段深度一致（版本域/index 装载规范化除外，
///    口径与 V3-600A 一致），SmartLayoutDocument 存活。
///
/// 证据：FLOWMUSE_GENERATE_V3_605A_EVIDENCE=1 一次性写入
/// evidence/platform/v3-605a-smoke.json；常规运行只读校验一致性。
library;

import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/patch/smart_layout_scene_patch_builder.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/reducer/smart_layout_scene_reducer.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/snapshot/scene_fingerprint.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/snapshot/scene_revision.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/snapshot/source_coverage_ledger.dart';

class SmokeStep {
  const SmokeStep(this.id, this.passed, this.detail);

  final String id;
  final bool passed;
  final String detail;

  Map<String, Object?> toJson() =>
      {'id': id, 'passed': passed, 'detail': detail};
}

class PlatformSmokeSuite {
  /// 运行四段 smoke；返回逐步结果。
  List<SmokeStep> run() {
    final steps = <SmokeStep>[];

    // ---- 1) 入口：真实控制器装载真实内容 ----
    final controller = MarkdrawController();
    controller.loadFromContent(_entryContent(), 'smoke.excalidraw');
    final entryScene = controller.editorState.scene;
    final entryIds = [
      for (final e in entryScene.activeElements) e.id.value,
    ]..sort();
    steps.add(SmokeStep(
      'entry-load',
      entryIds.join(',') == 'rect-1,text-1',
      '真实控制器 loadFromContent：active=${entryIds.length}',
    ));

    // ---- 2) commit：真实 v3 patch 经 applyResult（与 502A 提交通道）----
    final revision = SceneRevision(
      epoch: 0,
      revision: 1,
      fingerprint: SceneFingerprint.of(entryScene),
    );
    final ledger = SourceCoverageLedger.pending(const ['rect-1', 'text-1'])
        .markConsumed(const ['text-1'])
        .markPreserved(const ['rect-1']);
    final rect1 =
        entryScene.elements.firstWhere((e) => e.id.value == 'rect-1')
            as RectangleElement;
    final text1 =
        entryScene.elements.firstWhere((e) => e.id.value == 'text-1');
    // 装载路径会推进版本（绑定解析/文本边界重测 bump）——baseVersion
    // 一律取运行时实际值，不硬编码。
    final builder = SmartLayoutScenePatchBuilder(
      baseScene: entryScene,
      baseRevision: revision,
      sourceCoverage: ledger,
    )
      ..updateElement(
        rect1.copyWith(
          x: 50,
          y: 60,
          version: rect1.version + 1,
          versionNonce: 9001,
          updated: 7,
        ),
        baseVersion: rect1.version,
      )
      ..removeElement(
        'text-1',
        baseVersion: text1.version,
        versionNonce: 9002,
      )
      ..addElement(TextElement(
        id: const ElementId('sl3-smoke-1'),
        x: 50,
        y: 140,
        width: 200,
        height: 28,
        text: 'smoke 排版产物',
        fontSize: 20,
        fontFamily: 'Excalifont',
        seed: 900,
        versionNonce: 9003,
        updated: 7,
      ))
      ..replaceSmartLayoutDocument(
        SmartLayoutDocument(
          version: 1,
          generatedAt: 7,
          blocks: const [
            SmartLayoutBlock(
              id: 'b1',
              type: 'paragraph',
              text: 'smoke',
              order: 0,
              sourceIds: ['text-1'],
            ),
          ],
        ),
      );
    final patch = builder.build();
    final outcome = SmartLayoutSceneReducer.apply(
      base: entryScene,
      patch: patch,
    );
    if (outcome is! ReducedScene) {
      throw StateError('smoke patch 折叠失败: $outcome');
    }
    final reduced = outcome;
    final beforeCommitFingerprint = SceneFingerprint.of(entryScene);
    // 与 502A commitValidated 同序：先 pushHistory（提交前基线入栈）再
    // applyResult——undo 才能精确回基线。
    controller.pushHistory();
    controller.applyResult(reduced.commitResult);
    final committedScene = controller.editorState.scene;
    final committedIds = [
      for (final e in committedScene.activeElements) e.id.value,
    ]..sort();
    final commitOk = committedIds.join(',') == 'rect-1,sl3-smoke-1' &&
        committedScene.smartLayout != null &&
        SceneFingerprint.of(committedScene) != beforeCommitFingerprint;
    steps.add(SmokeStep(
      'commit-applyResult',
      commitOk,
      'v3 patch 经 502A 同通道提交：active=$committedIds '
      'doc=${committedScene.smartLayout != null}',
    ));

    // ---- 3) undo：精确回提交前 ----
    controller.undo();
    final undoneScene = controller.editorState.scene;
    final undoneOk = SceneFingerprint.of(undoneScene) ==
        beforeCommitFingerprint;
    steps.add(SmokeStep(
      'undo-restore',
      undoneOk,
      'undo 后 fingerprint 回到提交前',
    ));

    // ---- 4) reopen：序列化→新控制器重开 ----
    controller.redo();
    final content = controller.serializeScene(
      format: DocumentFormat.excalidraw,
    );
    final reopened = MarkdrawController();
    reopened.loadFromContent(content, 'smoke-reopen.excalidraw');
    final reopenedScene = reopened.editorState.scene;
    final reopenedIds = [
      for (final e in reopenedScene.activeElements) e.id.value,
    ]..sort();
    final idsOk = reopenedIds.join(',') == 'rect-1,sl3-smoke-1';

    // 内容字段等价（版本域三字段 + index 装载规范化排除——600A 口径）。
    var contentOk = idsOk;
    final expected = {
      for (final e in committedScene.activeElements) e.id.value: e,
    };
    if (idsOk) {
      for (final element in reopenedScene.activeElements) {
        final base = expected[element.id.value]!;
        final a = _project(ExcalidrawJsonCodec.elementToJson(base));
        final b = _project(ExcalidrawJsonCodec.elementToJson(element));
        if (a.toString() != b.toString()) {
          contentOk = false;
          steps.add(SmokeStep(
            'reopen-equiv-${element.id.value}',
            false,
            '$a vs $b',
          ));
        }
      }
    }
    final docOk = reopenedScene.smartLayout != null &&
        reopenedScene.smartLayout!.blocks.single.text == 'smoke';
    steps.add(SmokeStep(
      'reopen-equiv',
      contentOk && docOk,
      '重开元素集+内容字段深度一致（版本域/index 规范化除外）；'
      'document 存活=$docOk',
    ));

    controller.dispose();
    reopened.dispose();
    return steps;
  }

  bool allPassed(List<SmokeStep> steps) => steps.every((s) => s.passed);

  /// 内容等价投影：剥离版本域三字段与 index（装载规范化，600A 口径）。
  static Map<String, Object?> _project(Map<String, dynamic> json) {
    const excluded = {'version', 'versionNonce', 'updated', 'index'};
    return {
      for (final entry in json.entries)
        if (!excluded.contains(entry.key)) entry.key: entry.value,
    };
  }

  /// 真实入口内容（与 600A legacy fixture 同源的精简版）。
  static String _entryContent() => '''
{
  "type": "excalidraw",
  "version": 2,
  "source": "https://excalidraw.com",
  "appState": {"viewBackgroundColor": "#f8f9fa"},
  "files": {},
  "elements": [
    {
      "id": "rect-1", "type": "rectangle",
      "x": 10, "y": 10, "width": 120, "height": 80, "angle": 0,
      "strokeColor": "#1e1e1e", "backgroundColor": "transparent",
      "fillStyle": "solid", "strokeWidth": 2, "strokeStyle": "solid",
      "roughness": 1, "opacity": 100, "roundness": null,
      "seed": 101, "version": 1, "versionNonce": 33,
      "isDeleted": false, "groupIds": [], "frameId": null,
      "boundElements": null, "updated": 1, "link": null, "locked": false,
      "index": "a1"
    },
    {
      "id": "text-1", "type": "text",
      "x": 12, "y": 30, "width": 116, "height": 25, "angle": 0,
      "text": "smoke 文本", "fontSize": 20, "fontFamily": 5,
      "textAlign": "left", "verticalAlign": "top",
      "containerId": null, "lineHeight": 1.25, "autoResize": true,
      "originalText": "smoke 文本",
      "strokeColor": "#1e1e1e", "backgroundColor": "transparent",
      "fillStyle": "solid", "strokeWidth": 2, "strokeStyle": "solid",
      "roughness": 1, "opacity": 100, "roundness": null,
      "seed": 103, "version": 1, "versionNonce": 34,
      "isDeleted": false, "groupIds": [], "frameId": null,
      "boundElements": null, "updated": 1, "link": null, "locked": false,
      "index": "a2"
    }
  ]
}
''';
}
