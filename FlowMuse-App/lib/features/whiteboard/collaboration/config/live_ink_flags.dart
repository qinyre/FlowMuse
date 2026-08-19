import '../../editor_core/src/config/writing_feature_flags.dart';

class LiveInkFlags {
  const LiveInkFlags({required this.layeredWetInk, required this.liveInkV2});

  final bool layeredWetInk;
  final bool liveInkV2;

  bool effectiveFor(int serverProtocolVersion) =>
      layeredWetInk && liveInkV2 && serverProtocolVersion >= 2;
}

const liveInkFlags = LiveInkFlags(
  layeredWetInk: layeredWetInkEnabled,
  liveInkV2: bool.fromEnvironment('FLOWMUSE_LIVE_INK_V2', defaultValue: false),
);
