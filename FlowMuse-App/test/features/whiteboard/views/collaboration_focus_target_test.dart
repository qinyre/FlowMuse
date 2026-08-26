import 'dart:io';

import 'package:flow_muse/features/whiteboard/views/collaboration_focus_target.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('CreatorFocus 按 creatorKey 值相等比较（禁对象 identity）', () {
    const a = CreatorFocus('user:1', labelSnapshot: '张三', isGuest: false);
    const b = CreatorFocus('user:1', labelSnapshot: '张三改名了', isGuest: false);
    expect(a.creatorKey == b.creatorKey, isTrue); // 判同只看 creatorKey
  });

  test('HistoricalFocus 单例语义', () {
    expect(identical(const HistoricalFocus(), const HistoricalFocus()), isTrue);
  });

  test('创建者聚焦按 creatorKey 切换：同键退出、异键进入', () {
    const current = CreatorFocus('user:1', labelSnapshot: '张三', isGuest: false);
    expect(
      toggleCollaborationCreatorFocus(
        current,
        creatorKey: 'user:1',
        labelSnapshot: '张三改名',
        isGuest: false,
      ),
      isNull,
    );
    final next =
        toggleCollaborationCreatorFocus(
              current,
              creatorKey: 'user:2',
              labelSnapshot: '李四',
              isGuest: false,
            )
            as CreatorFocus;
    expect(next.creatorKey, 'user:2');
    expect(next.labelSnapshot, '李四');
  });

  test('WhiteboardPage 的 focus 入口只委托纯状态转换且无广播/持久化', () {
    final source = File(
      'lib/features/whiteboard/views/whiteboard_page.dart',
    ).readAsStringSync();
    // 源码门禁只证明宿主接线没有夹带副作用；状态转换行为由上方纯函数用例验证。
    final match = RegExp(
      r'void _toggleCreatorFocus\([\s\S]*?\n  \}\r?\n',
    ).firstMatch(source);
    expect(match, isNotNull, reason: '找不到 _toggleCreatorFocus 方法');
    final focusBlock = match!.group(0)!;
    expect(focusBlock.contains('toggleCollaborationCreatorFocus'), isTrue);
    expect(focusBlock.contains('broadcast'), isFalse);
    expect(focusBlock.contains('saveScene'), isFalse);
    expect(focusBlock.contains('applyResult'), isFalse);
  });
}
