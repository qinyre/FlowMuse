import '../../core/math/math.dart';

/// The type of resize or rotation handle on a selection overlay.
enum HandleType {
  topLeft,
  topCenter,
  topRight,
  middleLeft,
  middleRight,
  bottomLeft,
  bottomCenter,
  bottomRight,
  rotation,
}

/// A handle at a specific position in scene coordinates.
class Handle {
  final HandleType type;
  final Point position;

  const Handle({required this.type, required this.position});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Handle && type == other.type && position == other.position;

  @override
  int get hashCode => Object.hash(type, position);

  @override
  String toString() => 'Handle($type, $position)';
}
