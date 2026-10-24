import 'dart:math' as math;
import 'dart:ui';

import '../../editor_core/src/rendering/viewport_state.dart';
import '../models/collaborator_presence.dart';

/// Presence is untrusted; keep invalid or extreme coordinates out of rendering.
Rect? parseCollaborationBounds(Object? payload) {
  if (payload is! Map) return null;
  final values = [
    payload['x'],
    payload['y'],
    payload['width'],
    payload['height'],
  ];
  if (values.any((v) => v is! num || !v.isFinite || v.abs() > 1e9)) {
    return null;
  }
  final x = (values[0] as num).toDouble();
  final y = (values[1] as num).toDouble();
  final width = (values[2] as num).toDouble();
  final height = (values[3] as num).toDouble();
  if (width <= 0 || height <= 0) return null;
  return Rect.fromLTWH(x, y, width, height);
}

ViewportState? viewportForCollaborationBounds(Rect bounds, Size size) {
  if (!size.width.isFinite || !size.height.isFinite || size.isEmpty) {
    return null;
  }
  final zoom = math
      .min(size.width / bounds.width, size.height / bounds.height)
      .clamp(0.1, 30.0);
  return ViewportState(
    zoom: zoom,
    offset: bounds.center - Offset(size.width, size.height) / (2 * zoom),
  );
}

bool collaborationFollowWouldCycle({
  required String selfSocketId,
  required String targetSocketId,
  required Map<String, CollaboratorPresence> collaborators,
}) {
  final visited = <String>{selfSocketId};
  String? next = targetSocketId;
  while (next != null) {
    if (!visited.add(next)) return true;
    next = collaborators[next]?.followingSocketId;
  }
  return false;
}
