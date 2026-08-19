class WritingFeatureFlags {
  const WritingFeatureFlags({required this.layeredWetInk});

  final bool layeredWetInk;
}

const layeredWetInkEnabled = bool.fromEnvironment(
  'FLOWMUSE_LAYERED_WET_INK',
  defaultValue: false,
);

const writingFeatureFlags = WritingFeatureFlags(
  layeredWetInk: layeredWetInkEnabled,
);
