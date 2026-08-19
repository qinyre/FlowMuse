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
      await output.writeAsString(
        const JsonEncoder.withIndent('  ').convert(data ?? const {}),
      );
      stdout.writeln('[FlowMuseWritingPerf] result=${output.absolute.path}');
    },
  );
}
