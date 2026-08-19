import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flow_muse/features/whiteboard/collaboration/models/live_ink_chunk.dart';
import 'package:flow_muse/features/whiteboard/collaboration/services/live_ink_sender.dart';

void main() {
  const style = LiveInkStyle(
    brushType: 'fountainPen',
    strokeColor: '#1e1e1e',
    strokeWidth: 2,
    opacity: 100,
  );

  LiveInkSender senderFor(List<LiveInkChunk> sent) {
    return LiveInkSender(
      emit: (chunk) async {
        sent.add(chunk);
      },
    )..start(strokeId: 'stroke-1', style: style);
  }

  for (final count in [1, 7, 8, 64, 65]) {
    test('emits a bounded tail for $count points', () async {
      final sent = <LiveInkChunk>[];
      final sender = senderFor(sent);

      sender.offer(_points(count));
      await _flushAsync();

      expect(sent, hasLength(1));
      expect(sent.single.startIndex, count > 64 ? count - 64 : 0);
      expect(sent.single.points, hasLength(count.clamp(0, 64)));
      expect(sent.single.points.last.x, count - 1);
    });
  }

  test(
    'covers three actual cycles and repeats each index at most 3 times',
    () async {
      final sent = <LiveInkChunk>[];
      final sender = senderFor(sent);

      for (var count = 1; count <= 20; count++) {
        sender.offer(_points(count));
        await _flushAsync();
      }

      final repetitions = <int, int>{};
      for (final chunk in sent) {
        for (final point in chunk.indexedPoints) {
          repetitions.update(
            point.index,
            (value) => value + 1,
            ifAbsent: () => 1,
          );
        }
      }
      expect(sent.map((chunk) => chunk.startIndex).take(4), [0, 0, 0, 1]);
      expect(repetitions.values.every((count) => count <= 3), isTrue);
      expect(
        repetitions.keys,
        containsAll(List.generate(20, (index) => index)),
      );
    },
  );

  test('keeps one in-flight send and replaces the pending candidate', () async {
    final firstDone = Completer<void>();
    final sent = <LiveInkChunk>[];
    final sender = LiveInkSender(
      emit: (chunk) {
        sent.add(chunk);
        return sent.length == 1 ? firstDone.future : Future<void>.value();
      },
    )..start(strokeId: 'stroke-1', style: style);

    sender.offer(_points(1));
    await _flushMicrotasks();
    sender.offer(_points(2));
    sender.offer(_points(4));

    expect(sender.inFlight, isTrue);
    expect(sender.hasPending, isTrue);
    expect(sent, hasLength(1));

    firstDone.complete();
    await _flushAsync();

    expect(sent, hasLength(2));
    expect(sent.last.points.last.x, 3);
  });

  test(
    'counts transport errors and still drains the newest pending send',
    () async {
      final sent = <LiveInkChunk>[];
      final sender = LiveInkSender(
        emit: (chunk) async {
          sent.add(chunk);
          if (sent.length == 1) throw StateError('offline');
        },
      )..start(strokeId: 'stroke-1', style: style);

      sender.offer(_points(1));
      sender.offer(_points(3));
      await _flushAsync();

      expect(sender.errorCount, 1);
      expect(sent, hasLength(2));
      expect(sent.last.points.last.x, 2);
    },
  );

  test('finish snapshots the final accepted point without waiting', () async {
    final firstDone = Completer<void>();
    final sent = <LiveInkChunk>[];
    final sender = LiveInkSender(
      emit: (chunk) {
        sent.add(chunk);
        return sent.length == 1 ? firstDone.future : Future<void>.value();
      },
    )..start(strokeId: 'stroke-1', style: style);

    sender.offer(_points(1));
    await _flushMicrotasks();
    sender.finish(_points(3));
    expect(sender.hasPending, isTrue);

    firstDone.complete();
    await _flushAsync();

    expect(sent.last.points.last.x, 2);
    expect(sender.active, isFalse);
  });

  test('cancel drops pending work and ignores an old completion', () async {
    final firstDone = Completer<void>();
    final sent = <LiveInkChunk>[];
    final sender = LiveInkSender(
      emit: (chunk) {
        sent.add(chunk);
        return firstDone.future;
      },
    )..start(strokeId: 'stroke-1', style: style);

    sender.offer(_points(1));
    await _flushMicrotasks();
    sender.offer(_points(3));
    sender.cancel();
    firstDone.complete();
    await _flushAsync();

    expect(sent, hasLength(1));
    expect(sender.active, isFalse);
    expect(sender.hasPending, isFalse);
  });

  test(
    'tail API keeps total emitted entries linear for a long stroke',
    () async {
      final sent = <LiveInkChunk>[];
      final sender = senderFor(sent);
      const total = 2000;

      for (var count = 1; count <= total; count++) {
        final start = count > 64 ? count - 64 : 0;
        sender.offerTail(
          totalCount: count,
          startIndex: start,
          points: _points(count).sublist(start),
        );
        await _flushAsync();
      }

      final emittedEntries = sent.fold<int>(
        0,
        (total, chunk) => total + chunk.points.length,
      );
      expect(emittedEntries, lessThanOrEqualTo(total * 3));
    },
  );
}

List<LiveInkPoint> _points(int count) {
  return List.generate(
    count,
    (index) => LiveInkPoint(x: index.toDouble(), y: index.toDouble()),
    growable: false,
  );
}

Future<void> _flushMicrotasks() => Future<void>.delayed(Duration.zero);

Future<void> _flushAsync() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}
