class WritingFeatureFlags {
  const WritingFeatureFlags({required this.layeredWetInk});

  final bool layeredWetInk;
}

const writingFeatureFlags = WritingFeatureFlags(
  layeredWetInk: bool.fromEnvironment(
    'FLOWMUSE_LAYERED_WET_INK',
    defaultValue: false,
  ),
);
