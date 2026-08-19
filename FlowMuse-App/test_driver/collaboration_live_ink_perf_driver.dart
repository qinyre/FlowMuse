import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';

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
      final report = <String, Object?>{
        if (data != null) ...Map<String, Object?>.from(data),
        'hostEvidence': {
          'gitSha': sha.exitCode == 0
              ? (sha.stdout as String).trim()
              : 'unknown',
          'gitDirty':
              status.exitCode != 0 ||
              (status.stdout as String).trim().isNotEmpty,
          'capturedAtUtc': DateTime.now().toUtc().toIso8601String(),
          'hostOperatingSystem': Platform.operatingSystem,
          'hostOperatingSystemVersion': Platform.operatingSystemVersion,
        },
      };
      await output.writeAsString(
        const JsonEncoder.withIndent('  ').convert(report),
      );
      stdout.writeln('[FlowMuseLiveInkPerf] result=${output.absolute.path}');
    },
  );
}
