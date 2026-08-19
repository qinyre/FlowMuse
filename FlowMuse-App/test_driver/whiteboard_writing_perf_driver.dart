import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';

Future<void> main() {
  return integrationDriver(
    responseDataCallback: (data) async {
      final outputDirectory = Directory(
        Platform.environment['FLOWMUSE_PERF_OUTPUT_DIR'] ??
            '${Directory.current.path}${Platform.pathSeparator}build${Platform.pathSeparator}writing-perf',
      );
      await outputDirectory.create(recursive: true);
      final timestamp = DateTime.now().toUtc().toIso8601String().replaceAll(
        ':',
        '-',
      );
      final output = File(
        '${outputDirectory.path}${Platform.pathSeparator}writing-perf-$timestamp.json',
      );
      final report = <String, Object?>{
        if (data != null) ...Map<String, Object?>.from(data),
        'hostEvidence': await _hostEvidence(),
      };
      await output.writeAsString(
        const JsonEncoder.withIndent('  ').convert(report),
      );
      stdout.writeln('[FlowMuseWritingPerf] result=${output.absolute.path}');
    },
  );
}

Future<Map<String, Object?>> _hostEvidence() async {
  final sha = await Process.run('git', ['rev-parse', 'HEAD']);
  final status = await Process.run('git', ['status', '--porcelain']);
  return {
    'gitSha': sha.exitCode == 0 ? (sha.stdout as String).trim() : 'unknown',
    'gitDirty':
        status.exitCode != 0 || (status.stdout as String).trim().isNotEmpty,
    'capturedAtUtc': DateTime.now().toUtc().toIso8601String(),
    'hostOperatingSystem': Platform.operatingSystem,
    'hostOperatingSystemVersion': Platform.operatingSystemVersion,
  };
}
