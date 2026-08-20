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

  test('设备列表必须完整扫描，目标后的模拟器也计入歧义设备数', () {
    final evidence = inspectFlutterDevices([
      {
        'id': 'device-a',
        'name': 'phone',
        'targetPlatform': 'android-arm64',
        'emulator': false,
      },
      {
        'id': 'emulator-a',
        'name': 'emulator',
        'targetPlatform': 'android-x64',
        'emulator': true,
      },
      {
        'id': 'windows',
        'name': 'Windows',
        'targetPlatform': 'windows-x64',
        'emulator': false,
      },
    ], 'device-a');

    expect(evidence['detectedDeviceId'], 'device-a');
    expect(evidence['detectedEmulator'], isFalse);
    expect(evidence['supportedDeviceCount'], 2);
  });
}
