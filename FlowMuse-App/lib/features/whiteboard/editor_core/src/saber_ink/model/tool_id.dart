/// Saber-compatible tool identifiers used by FlowMuse ink strokes.
///
/// Values follow Saber IDs where possible so imported Saber-derived stroke
/// data can be recognized without a compatibility shim.
enum SaberToolId {
  fountainPen('fountainPen'),
  ballpointPen('ballpointPen'),
  pencil('Pencil'),
  highlighter('Highlighter'),
  shapePen('ShapePen'),
  laserPointer('LaserPointer');

  const SaberToolId(this.id);

  final String id;

  static SaberToolId parse(
    String? value, {
    SaberToolId fallback = SaberToolId.fountainPen,
  }) {
    return switch (value) {
      'Pen' || 'fountainPen' || 'fountain-pen' => SaberToolId.fountainPen,
      'ballpointPen' || 'ballpoint' => SaberToolId.ballpointPen,
      'Pencil' || 'pencil' => SaberToolId.pencil,
      'Highlighter' || 'highlighter' => SaberToolId.highlighter,
      'ShapePen' || 'shapePen' || 'shape-pen' => SaberToolId.shapePen,
      'LaserPointer' || 'laserPointer' || 'laser' => SaberToolId.laserPointer,
      _ => fallback,
    };
  }
}
