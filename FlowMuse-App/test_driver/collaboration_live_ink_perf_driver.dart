import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';

import '../tool/writing_perf/profile_device_eligibility.dart';

Future<void> main() {
  return integrationDriver(
    timeout: const Duration(minutes: 50),
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
      if (report['measurementEligible'] != true) {
        throw StateError('Profile report is not eligible; raw report retained');
      }
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
  var deviceEvidence = <String, Object?>{};
  if (devices.exitCode == 0 && reportedDeviceId is String) {
    try {
      deviceEvidence = inspectFlutterDevices(
        jsonDecode(devices.stdout as String),
        reportedDeviceId,
      );
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
    ...deviceEvidence,
  };
}
