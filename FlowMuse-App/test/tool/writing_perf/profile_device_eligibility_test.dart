import 'package:flutter_test/flutter_test.dart';

import '../../../tool/writing_perf/profile_device_eligibility.dart';

void main() {
  test('只接受唯一、匹配且非模拟器的真机 Profile 报告', () {
    final report = <String, dynamic>{
      'measurementEligible': true,
      'buildMode': 'profile',
      'platform': 'android',
      'physicalDevice': true,
      'deviceId': 'device-a',
      'deviceClass': 'android-mid',
    };
    final host = <String, Object?>{
      'detectedDeviceId': 'device-a',
      'detectedTargetPlatform': 'android-arm64',
      'detectedEmulator': false,
      'supportedDeviceCount': 1,
      'gitDirty': false,
    };

    expect(isHostVerifiedProfileReport(report, host), isTrue);
    expect(
      isHostVerifiedProfileReport(report, {...host, 'detectedEmulator': true}),
      isFalse,
    );
    expect(
      isHostVerifiedProfileReport(report, {...host, 'supportedDeviceCount': 2}),
      isFalse,
    );
    expect(
      isHostVerifiedProfileReport(report, {
        ...host,
        'detectedDeviceId': 'device-b',
      }),
      isFalse,
    );
  });
}
