import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';

import '../tool/writing_perf/profile_device_eligibility.dart';

Future<void> main() {
  return integrationDriver(
    responseDataCallback: (data) async {
      final directory = Directory(
        Platform.environment['FLOWMUSE_PERF_OUTPUT_DIR'] ??
            '${Directory.current.path}${Platform.pathSeparator}build${Platform.pathSeparator}writing-perf',
      );
      await directory.create(recursive: true);
      final timestamp = DateTime.now().toUtc().toIso8601String().replaceAll(
        ':',
        '-',
      );
      final output = File(
        '${directory.path}${Platform.pathSeparator}collaboration-live-ink-$timestamp.json',
      );
      final sha = await Process.run('git', ['rev-parse', 'HEAD']);
      final status = await Process.run('git', ['status', '--porcelain']);
      final hostEvidence = await _hostEvidence(data, sha, status);
      final report = <String, Object?>{
        if (data != null) ...Map<String, Object?>.from(data),
        'measurementEligible': isHostVerifiedProfileReport(data, hostEvidence),
        'hostEvidence': hostEvidence,
      };
      await output.writeAsString(
        const JsonEncoder.withIndent('  ').convert(report),
      );
      stdout.writeln('[FlowMuseLiveInkPerf] result=${output.absolute.path}');
    },
  );
}

Future<Map<String, Object?>> _hostEvidence(
  Map<String, dynamic>? report,
  ProcessResult sha,
  ProcessResult status,
) async {
  final devices = await Process.run('flutter', ['devices', '--machine']);
  final reportedDeviceId = report?['deviceId'];
  Map<String, Object?>? detectedDevice;
  var supportedDeviceCount = 0;
  if (devices.exitCode == 0 && reportedDeviceId is String) {
    try {
      final decoded = jsonDecode(devices.stdout as String);
      if (decoded is List) {
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
    } on FormatException {
      // 缺失字段会使 measurementEligible=false，并保留原始报告供诊断。
    }
  }
  return {
    'gitSha': sha.exitCode == 0 ? (sha.stdout as String).trim() : 'unknown',
    'gitDirty':
        status.exitCode != 0 || (status.stdout as String).trim().isNotEmpty,
    'capturedAtUtc': DateTime.now().toUtc().toIso8601String(),
    'hostOperatingSystem': Platform.operatingSystem,
    'hostOperatingSystemVersion': Platform.operatingSystemVersion,
    'detectedDeviceId': detectedDevice?['id'],
    'detectedTargetPlatform': detectedDevice?['targetPlatform'],
    'detectedEmulator': detectedDevice?['emulator'],
    'supportedDeviceCount': supportedDeviceCount,
  };
}
