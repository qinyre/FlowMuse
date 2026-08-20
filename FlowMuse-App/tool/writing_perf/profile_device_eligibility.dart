Map<String, Object?> inspectFlutterDevices(
  Object? decoded,
  Object? reportedDeviceId,
) {
  Map<String, Object?>? detectedDevice;
  var supportedDeviceCount = 0;
  if (decoded is List && reportedDeviceId is String) {
    for (final item in decoded.whereType<Map>()) {
      final target = item['targetPlatform']?.toString().toLowerCase() ?? '';
      if (target.startsWith('android') ||
          target.startsWith('ios') ||
          target.startsWith('ohos')) {
        supportedDeviceCount++;
      }
      if (item['id'] == reportedDeviceId) {
        detectedDevice = Map<String, Object?>.from(item);
      }
    }
  }
  return {
    'detectedDeviceId': detectedDevice?['id'],
    'detectedDeviceName': detectedDevice?['name'],
    'detectedTargetPlatform': detectedDevice?['targetPlatform'],
    'detectedEmulator': detectedDevice?['emulator'],
    'supportedDeviceCount': supportedDeviceCount,
  };
}

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
