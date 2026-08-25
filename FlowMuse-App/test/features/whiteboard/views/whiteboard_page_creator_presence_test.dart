import 'dart:io';

import 'package:flow_muse/features/whiteboard/views/whiteboard_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // WhiteboardPage 源码路径（测试工作目录 = FlowMuse-App/）
  final page = File('lib/features/whiteboard/views/whiteboard_page.dart');

  test('WhiteboardPage 源码包含 force 补发调用与 session 清理', () {
    final source = page.readAsStringSync();
    // 首加入 / 重连 / 新成员 三处 force 补发（Step 4.7 落地后成立）
    expect(
      RegExp(
        r'_broadcastIdleState\(_lastIdleState \?\? '
        r"'active', force: true\)",
      ).hasMatch(source),
      isTrue,
      reason: '必须存在绕过 idle 去重的强制补发调用',
    );
    expect(source.contains('force: true'), isTrue);
    // leave/end 清理 guest 会话（Step 4.4 落地后成立）
    expect(source.contains('_guestCreatorSessionId = null;'), isTrue);
  });

  test('newlyJoinedSocketIds 纯函数：单批多次加入返回全部新 socket', () {
    // 该函数为 whiteboard_page.dart 顶层公开函数
    expect(newlyJoinedSocketIds(const {}, const {'a', 'b'}), {'a', 'b'});
    expect(newlyJoinedSocketIds(const {'a'}, const {'a', 'b'}), {'b'});
    expect(newlyJoinedSocketIds(const {'a', 'b'}, const {'a', 'b'}), isEmpty);
    expect(
      newlyJoinedSocketIds(const {'a'}, const {'b'}),
      {'b'},
      reason: '同一批次中 a 离开且 b 加入时，b 仍是新增 socket，必须触发补发',
    );
  });
}
