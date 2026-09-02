import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';

import '../patch/smart_layout_scene_patch.dart';
import 'smart_layout_scene_reducer.dart';

/// 预览适配器（V3-501A）：Draft 场景的唯一入口——与最终提交共用
/// [SmartLayoutSceneReducer]，但只产出内存 Draft Scene，不触碰权威
/// Scene、History、revision 或协作状态（计划 §4.9：Draft 内候选切换/
/// 拖动/选择只改本地 patch，不改权威状态）。
///
/// 重放：同一 patch 可在写集完好（远端无关变更后）的新 base 上重新
/// 归约——Draft 可重放；写集冲突由 reducer 目标失配显式失败。
abstract final class SmartLayoutPreviewAdapter {
  /// 归约出 Draft（与提交同一条代码路径）。失败原样返回
  /// [SceneReduceFailure]，调用方按稳定码处置。
  static SmartLayoutSceneReduceOutcome draft({
    required Scene base,
    required SmartLayoutScenePatch patch,
  }) => SmartLayoutSceneReducer.apply(base: base, patch: patch);
}
