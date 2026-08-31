import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';

import 'smart_layout_editor_gateway.dart';
import 'smart_layout_http_gateway.dart';

/// 智能排版 v3 对页面层的唯一公开入口：只暴露两个 gateway，
/// 页面与后续 session/view model 不直接触碰 editor 或 HTTP 细节。
class SmartLayoutPublicEntry {
  SmartLayoutPublicEntry({required this.editor, required this.http});

  /// 从既有控制器与服务器地址组装入口；[post] 供测试注入 fake 传输。
  factory SmartLayoutPublicEntry.fromEditor({
    required MarkdrawController controller,
    required Uri serverUri,
    SmartLayoutHttpPost? post,
  }) {
    return SmartLayoutPublicEntry(
      editor: SmartLayoutEditorGateway(controller),
      http: SmartLayoutHttpGateway(serverUri: serverUri, post: post),
    );
  }

  final SmartLayoutEditorGateway editor;
  final SmartLayoutHttpGateway http;

  bool _disposed = false;

  bool get isDisposed => _disposed;

  /// 释放入口；释放后不可再使用（session 生命周期归 V3-106A）。
  void dispose() {
    if (_disposed) return;
    _disposed = true;
  }
}
