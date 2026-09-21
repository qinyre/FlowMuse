import 'package:flutter_test/flutter_test.dart';
import 'package:flow_muse/features/whiteboard/collaboration/services/collaboration_activity_timer.dart';

void main() {
  testWidgets('持续写入只保持 active，闲置从最后一次输入计时，取消后可重入', (tester) async {
    var elapsed = Duration.zero;
    final states = <String>[];
    final timer = CollaborationActivityTimer(
      states.add,
      elapsed: () => elapsed,
    );
    addTearDown(timer.cancel);
    Future<void> wait(Duration duration) async {
      elapsed += duration;
      await tester.pump(duration);
    }

    timer.markActive();
    for (var i = 0; i < 120; i++) {
      await wait(const Duration(seconds: 1));
      timer.markActive();
    }
    expect(states, ['active']);
    await wait(const Duration(seconds: 59));
    expect(states, ['active']);
    await wait(const Duration(seconds: 1));
    expect(states, ['active', 'idle']);
    timer.markActive();
    await wait(const Duration(minutes: 1));
    expect(states, ['active', 'idle', 'active', 'idle']);
    await wait(const Duration(minutes: 4));
    expect(states.last, 'away');
    timer.markActive();
    timer.cancel();
    final before = states.length;
    await wait(const Duration(minutes: 6));
    expect(states.length, before);
    timer.markActive();
    expect(states.last, 'active');
    timer.cancel();
  });
}
