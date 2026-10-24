import 'dart:ui';

import 'package:flow_muse/features/whiteboard/collaboration/models/collaborator_presence.dart';
import 'package:flow_muse/features/whiteboard/collaboration/services/collaboration_viewport.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('远端视口拒绝缺失、非法、非有限和极端尺寸', () {
    expect(parseCollaborationBounds(null), isNull);
    for (final value in [null, '1', double.nan, double.infinity, 1e10]) {
      expect(
        parseCollaborationBounds({
          'x': value,
          'y': 0,
          'width': 100,
          'height': 100,
        }),
        isNull,
      );
    }
    for (final value in [0, -1, double.nan, double.infinity]) {
      expect(
        parseCollaborationBounds({
          'x': 0,
          'y': 0,
          'width': value,
          'height': 100,
        }),
        isNull,
      );
    }
    expect(
      parseCollaborationBounds({
        'x': -20,
        'y': 30,
        'width': 100,
        'height': 200,
      }),
      const Rect.fromLTWH(-20, 30, 100, 200),
    );
  });

  test('不同宽高的设备完整显示远端区域并保留中心', () {
    const bounds = Rect.fromLTWH(100, 200, 800, 600);
    final viewport = viewportForCollaborationBounds(
      bounds,
      const Size(360, 720),
    )!;
    expect(viewport.zoom, closeTo(0.45, 1e-9));
    expect(viewport.screenToScene(const Offset(180, 360)), bounds.center);
    expect(
      viewport.visibleRect(const Size(360, 720)).contains(bounds.topLeft),
      isTrue,
    );
    expect(viewportForCollaborationBounds(bounds, Size.zero), isNull);
    expect(
      viewportForCollaborationBounds(bounds, const Size(double.infinity, 1)),
      isNull,
    );
  });

  test('极小或极大区域限制缩放，中心保持有限', () {
    for (final bounds in [
      const Rect.fromLTWH(100, 200, 1e-100, 1e-100),
      const Rect.fromLTWH(-1e8, -1e8, 1e9, 1e9),
    ]) {
      final viewport = viewportForCollaborationBounds(
        bounds,
        const Size(800, 600),
      )!;
      expect(viewport.zoom, inInclusiveRange(0.1, 30));
      expect(
        viewport.offset.dx.isFinite && viewport.offset.dy.isFinite,
        isTrue,
      );
    }
  });

  test('跟随拒绝直接、自身、间接及远端已有循环', () {
    final collaborators = {
      'a': const CollaboratorPresence(socketId: 'a', followingSocketId: 'b'),
      'b': const CollaboratorPresence(socketId: 'b', followingSocketId: 'self'),
      'c': const CollaboratorPresence(socketId: 'c', followingSocketId: 'd'),
      'd': const CollaboratorPresence(socketId: 'd', followingSocketId: 'c'),
      'free': const CollaboratorPresence(socketId: 'free'),
    };
    for (final target in ['self', 'a', 'b', 'c']) {
      expect(
        collaborationFollowWouldCycle(
          selfSocketId: 'self',
          targetSocketId: target,
          collaborators: collaborators,
        ),
        isTrue,
      );
    }
    expect(
      collaborationFollowWouldCycle(
        selfSocketId: 'self',
        targetSocketId: 'free',
        collaborators: collaborators,
      ),
      isFalse,
    );
  });
}
