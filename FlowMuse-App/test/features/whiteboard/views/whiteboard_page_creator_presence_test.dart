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

  test('聚焦通知仅在空态翻转时重建（源码门禁，评审 P1 修复）', () {
    final source = page.readAsStringSync();
    final match = RegExp(
      'void _onControllerNotifyForFocus\\([\\s\\S]*?\\n  \\}\\r?\\n',
    ).firstMatch(source);
    expect(match, isNotNull, reason: '找不到 _onControllerNotifyForFocus 方法');
    final block = match!.group(0)!;
    expect(
      block.contains('_lastFocusEmpty'),
      isTrue,
      reason: '必须用空态缓存对比，而非每次通知都重建',
    );
    final guardIndex = block.indexOf('_lastFocusEmpty != empty');
    final setStateIndex = block.indexOf('setState(');
    expect(guardIndex, greaterThanOrEqualTo(0), reason: '缺少空态翻转守卫');
    expect(
      setStateIndex,
      greaterThan(guardIndex),
      reason: 'setState 必须位于"空态翻转"守卫之后，禁止高频通知整页重建',
    );
  });
}
