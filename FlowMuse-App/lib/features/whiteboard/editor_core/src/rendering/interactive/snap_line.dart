/// Orientation of a snap/alignment guide line.
enum SnapLineOrientation { horizontal, vertical }

/// A snap/alignment guide line drawn on the interactive overlay.
///
/// For horizontal lines, [position] is the y-coordinate and [start]/[end]
/// are the x-extent. For vertical lines, [position] is the x-coordinate
/// and [start]/[end] are the y-extent.
class SnapLine {
  final SnapLineOrientation orientation;
  final double position;
  final double start;
  final double end;

  const SnapLine({
    required this.orientation,
    required this.position,
    required this.start,
    required this.end,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SnapLine &&
          orientation == other.orientation &&
          position == other.position &&
          start == other.start &&
          end == other.end;

  @override
  int get hashCode => Object.hash(orientation, position, start, end);

  @override
  String toString() => 'SnapLine($orientation, pos=$position, $start..$end)';
}
