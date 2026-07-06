import 'package:flutter_test/flutter_test.dart';
import 'package:flow_muse/features/whiteboard/collaboration/models/collaborative_element.dart';
import 'package:flow_muse/features/whiteboard/collaboration/services/scene_reconciler.dart';
import 'package:flow_muse/features/whiteboard/models/whiteboard_element.dart';

void main() {
  CollaborativeElement element({
    required String id,
    required int version,
    required int nonce,
    required String index,
    bool deleted = false,
    int updatedAt = 1000,
  }) {
    return CollaborativeElement(
      id: id,
      type: WhiteboardElementType.rectangle,
      version: version,
      versionNonce: nonce,
      updatedAt: updatedAt,
      fractionalIndex: index,
      isDeleted: deleted,
      data: const {'x': 10, 'y': 20},
    );
  }

  test('keeps the newer local element when local version is higher', () {
    final reconciler = SceneReconciler(now: () => DateTime(2026, 1, 1));

    final result = reconciler.reconcile(
      localElements: [element(id: 'a', version: 3, nonce: 7, index: 'b')],
      remoteElements: [element(id: 'a', version: 2, nonce: 1, index: 'a')],
    );

    expect(result.single.version, 3);
    expect(result.single.versionNonce, 7);
  });

  test('uses version nonce as deterministic tie breaker', () {
    final reconciler = SceneReconciler(now: () => DateTime(2026, 1, 1));

    final result = reconciler.reconcile(
      localElements: [element(id: 'a', version: 5, nonce: 3, index: 'b')],
      remoteElements: [element(id: 'a', version: 5, nonce: 9, index: 'a')],
    );

    expect(result.single.versionNonce, 3);
  });

  test('orders merged elements by fractional index', () {
    final reconciler = SceneReconciler(now: () => DateTime(2026, 1, 1));

    final result = reconciler.reconcile(
      localElements: [element(id: 'local', version: 1, nonce: 1, index: 'z')],
      remoteElements: [element(id: 'remote', version: 1, nonce: 1, index: 'a')],
    );

    expect(result.map((item) => item.id), ['remote', 'local']);
  });

  test('breaks duplicate fractional index ties by element id', () {
    final reconciler = SceneReconciler(now: () => DateTime(2026, 1, 1));

    final result = reconciler.reconcile(
      localElements: [element(id: 'b', version: 1, nonce: 1, index: 'a0')],
      remoteElements: [element(id: 'a', version: 1, nonce: 1, index: 'a0')],
    );

    expect(result.map((item) => item.id), ['a', 'b']);
  });

  test('computes Excalidraw-compatible scene version and nonce hash', () {
    final reconciler = SceneReconciler(now: () => DateTime(2026, 1, 1));
    final elements = [
      element(id: 'a', version: 2, nonce: 3, index: 'a0'),
      element(id: 'b', version: 5, nonce: 7, index: 'a1'),
    ];

    expect(reconciler.getSceneVersion(elements), 7);
    expect(reconciler.hashElementsVersion(elements), 5860015);
  });

  test('filters old deleted elements from syncable payload', () {
    final now = DateTime(2026, 1, 2);
    final reconciler = SceneReconciler(now: () => now);

    final syncable = reconciler.getSyncableElements([
      element(
        id: 'fresh-delete',
        version: 1,
        nonce: 1,
        index: 'a',
        deleted: true,
        updatedAt: now
            .subtract(const Duration(hours: 12))
            .millisecondsSinceEpoch,
      ),
      element(
        id: 'old-delete',
        version: 1,
        nonce: 1,
        index: 'b',
        deleted: true,
        updatedAt: now.subtract(const Duration(days: 2)).millisecondsSinceEpoch,
      ),
    ]);

    expect(syncable.map((item) => item.id), ['fresh-delete']);
  });
}
