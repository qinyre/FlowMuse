/// The current input interaction mode, determining handle sizes and hit radii.
///
/// [pointer] is for mouse/trackpad (desktop) — smaller handles and tighter
/// hit radii. [touch] is for finger/stylus (mobile/tablet) — larger handles
/// and more generous hit radii for comfortable touch targets.
enum InteractionMode {
  /// Mouse or trackpad input — compact handles.
  pointer,

  /// Finger or stylus input — larger touch targets.
  touch,
}
