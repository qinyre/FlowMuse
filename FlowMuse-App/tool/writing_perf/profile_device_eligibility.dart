bool isHostVerifiedProfileReport(
  Map<String, dynamic>? report,
  Map<String, Object?> host,
) {
  if (report == null || report['measurementEligible'] != true) return false;
  final platform = report['platform']?.toString().toLowerCase() ?? '';
  final detectedTarget =
      host['detectedTargetPlatform']?.toString().toLowerCase() ?? '';
  return report['buildMode'] == 'profile' &&
      report['physicalDevice'] == true &&
      report['deviceId'] is String &&
      (report['deviceId'] as String).isNotEmpty &&
      report['deviceClass'] is String &&
      (report['deviceClass'] as String).isNotEmpty &&
      report['deviceId'] == host['detectedDeviceId'] &&
      host['detectedEmulator'] == false &&
      host['supportedDeviceCount'] == 1 &&
      host['gitDirty'] == false &&
      const {'android', 'ios', 'ohos'}.contains(platform) &&
      detectedTarget.startsWith(platform);
}
