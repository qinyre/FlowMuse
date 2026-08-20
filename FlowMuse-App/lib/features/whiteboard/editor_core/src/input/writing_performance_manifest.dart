class WritingPerformanceFixtureSpec {
  const WritingPerformanceFixtureSpec({
    required this.hash,
    required this.durationSeconds,
    required this.acceptedSamplesPerStroke,
  });

  final String hash;
  final int durationSeconds;
  final int acceptedSamplesPerStroke;
}

const writingPerformanceFixtures = <String, WritingPerformanceFixtureSpec>{
  'quick_zigzag': WritingPerformanceFixtureSpec(
    hash: '99d4859fdaa7e814a33937986a4ebb724ca1da0c6d7252b5c07de3e0796b4794',
    durationSeconds: 60,
    acceptedSamplesPerStroke: 42,
  ),
  'long_curve_pressure': WritingPerformanceFixtureSpec(
    hash: 'dcb0d26d1eb72feeb2333b5096b576b6ca423dae73a9769de03b322673d476d6',
    durationSeconds: 30,
    acceptedSamplesPerStroke: 122,
  ),
};

const writingSceneFixtureHashes = <int, String>{
  100: '37070b555c419438b0bbadc6eee84fdb11a8a1aed08d54f66425f61344bf6e40',
  1000: 'f84da895020fcdec79dcaeb18d7a1ea2202ca113d2ae05623140f6f0dcdcb315',
  5000: '257642176505a828d17086a1b31be8b8b34682105c5184bcbe43d726d1e5e43f',
};

int frozenEventToPaintTargetMicros(int refreshHz) {
  if (refreshHz >= 55 && refreshHz <= 65) return 33000;
  if (refreshHz >= 100 && refreshHz <= 165) {
    return (1000000 / refreshHz).ceil();
  }
  return 0;
}
