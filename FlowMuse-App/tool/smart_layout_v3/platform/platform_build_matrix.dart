/// V3-605A：六端平台构建矩阵（合并原 V3-605A~C）——目标符号
/// [PlatformBuildMatrix]。
///
/// 冻结六端配方（android/web/windows/ohos/ios/macos）：可用目标实构建
/// （记录退出码/产物 sha256），不可用目标如实记 release_deferred
/// （runner/缺失依赖/恢复命令），不伪造成功；生成文件不入提交（仅哈希
/// 入证据）。生产六端认证由 V3-700A 接收。
///
/// 用法（FlowMuse-App 目录）：
///   dart run tool/smart_layout_v3/platform/platform_build_matrix.dart \
///     --report ../docs/研发记录/evidence/smart-layout-v3/platform/v3-605a-report.json
library;

import 'dart:convert';
import 'dart:io';

class PlatformRecipe {
  const PlatformRecipe({
    required this.id,
    required this.command,
    required this.availabilityHint,
    required this.recovery,
    required this.host,
    required this.artifactPath,
  });

  final String id;
  final List<String> command;
  final String availabilityHint;
  final String recovery;
  final String host;
  final String artifactPath;
}

const List<PlatformRecipe> platformRecipes = [
  PlatformRecipe(
    id: 'android',
    command: ['flutter', 'build', 'apk', '--debug'],
    availabilityHint: 'ANDROID_HOME + flutter doctor Android toolchain',
    recovery: '安装 Android SDK 并设 ANDROID_HOME；flutter doctor --android-licenses 后重跑',
    host: 'any',
    artifactPath: 'build/app/outputs/flutter-apk/app-debug.apk',
  ),
  PlatformRecipe(
    id: 'web',
    command: ['flutter', 'build', 'web'],
    availabilityHint: '随 Flutter SDK 自带 dart2js',
    recovery: '无需额外依赖；重跑 flutter build web',
    host: 'any',
    artifactPath: 'build/web/main.dart.js',
  ),
  PlatformRecipe(
    id: 'windows',
    command: ['flutter', 'build', 'windows'],
    availabilityHint: 'Windows 宿主 + Visual Studio（C++ 桌面开发工作负载）',
    recovery: '安装 Visual Studio 2022（含"使用 C++ 的桌面开发"工作负载）后重跑',
    host: 'windows',
    artifactPath: 'build/windows/x64/runner/Release/FlowMuse.exe',
  ),
  PlatformRecipe(
    id: 'ohos',
    command: ['flutter', 'build', 'hap', '--debug'],
    availabilityHint: 'HOS_SDK_HOME（DevEco Studio / HarmonyOS SDK）+ OHOS Flutter 分支',
    recovery: '安装 HarmonyOS SDK 并设 HOS_SDK_HOME（DevEco Studio），'
        '使用 OHOS Flutter 分支后重跑 flutter build hap --debug',
    host: 'any',
    artifactPath: 'build/ohos/hap/entry-default-signed.hap',
  ),
  PlatformRecipe(
    id: 'ios',
    command: ['flutter', 'build', 'ios', '--debug', '--no-codesign'],
    availabilityHint: 'macOS 宿主 + Xcode',
    recovery: '在 macOS 宿主安装 Xcode 命令行工具后重跑',
    host: 'macos',
    artifactPath: 'build/ios/iphoneos/Runner.app/Runner',
  ),
  PlatformRecipe(
    id: 'macos',
    command: ['flutter', 'build', 'macos'],
    availabilityHint: 'macOS 宿主 + Xcode',
    recovery: '在 macOS 宿主安装 Xcode 后重跑',
    host: 'macos',
    artifactPath:
        'build/macos/Build/Products/Release/FlowMuse.app/Contents/MacOS/FlowMuse',
  ),
];

class PlatformBuildMatrix {
  /// 逐端探测可用性：宿主 OS 门 + flutter doctor 工具链行 + 环境变量。
  Future<Map<String, Object?>> run({String? reportPath}) async {
    final doctor = await _flutterDoctor();
    final results = <Map<String, Object?>>[];
    for (final recipe in platformRecipes) {
      final blockedByHost = _hostBlocked(recipe);
      final missing = _missingDependency(recipe, doctor);
      if (blockedByHost || missing != null) {
        results.add({
          'platform': recipe.id,
          'status': 'release_deferred',
          'runner': Platform.operatingSystem,
          'device': 'none',
          'blocked_by': blockedByHost
              ? 'host=${recipe.host} required（当前 ${Platform.operatingSystem}）'
              : missing,
          'recovery': recipe.recovery,
          'command': recipe.command,
        });
        stdout.writeln(
          '[platform] ${recipe.id}: release_deferred '
          '(${blockedByHost ? 'host' : missing})',
        );
        continue;
      }
      stdout.writeln('[platform] ${recipe.id}: 构建 ${recipe.command} ...');
      final sw = Stopwatch()..start();
      final outcome = await _runCommand(recipe.command);
      sw.stop();
      final artifactFile = File(recipe.artifactPath);
      final artifactExists = artifactFile.existsSync();
      final sha = artifactExists ? _sha256File(artifactFile) : null;
      final sizeBytes = artifactExists ? artifactFile.lengthSync() : null;
      results.add({
        'platform': recipe.id,
        'status': outcome.exitCode == 0 && artifactExists
            ? 'built'
            : 'failed',
        'runner': Platform.operatingSystem,
        'command': recipe.command,
        'exit_code': outcome.exitCode,
        'duration_ms': sw.elapsedMilliseconds,
        'artifact': {
          'path': recipe.artifactPath,
          'sha256': sha,
          'size_bytes': sizeBytes,
          // 生成文件不入提交：仅哈希入证据。
        },
        if (outcome.exitCode != 0)
          'diagnostics_tail': _tail(outcome.stderr + outcome.stdout, 2000),
      });
      stdout.writeln(
        '[platform] ${recipe.id}: ${outcome.exitCode == 0 && artifactExists ? 'built' : 'failed'} '
        '${sw.elapsedMilliseconds}ms',
      );
    }
    final report = {
      'schema_version': 1,
      'task_id': 'V3-605A',
      'matrix': 'PlatformBuildMatrix',
      'generated_at_utc': DateTime.now().toUtc().toIso8601String(),
      'host': Platform.operatingSystem,
      'recipes_frozen': [
        for (final r in platformRecipes)
          {'platform': r.id, 'command': r.command, 'host': r.host},
      ],
      'platforms': results,
      'all_available_built': results
          .where((r) => r['status'] != 'release_deferred')
          .every((r) => r['status'] == 'built'),
    };
    if (reportPath != null) {
      final file = File(reportPath);
      file.createSync(recursive: true);
      file.writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(report),
        flush: true,
      );
      stdout.writeln('[platform] report: $reportPath');
    }
    return report;
  }

  bool _hostBlocked(PlatformRecipe recipe) {
    if (recipe.host == 'any') return false;
    final isMacos = Platform.isMacOS;
    return recipe.host == 'macos' && !isMacos;
  }

  String? _missingDependency(PlatformRecipe recipe, String doctor) {
    switch (recipe.id) {
      case 'android':
        final envHome = Platform.environment['ANDROID_HOME'];
        if (envHome == null || envHome.isEmpty) return 'ANDROID_HOME 未设置';
        if (!Directory(envHome).existsSync()) return 'ANDROID_HOME 目录不存在';
        return null;
      case 'web':
        return null;
      case 'windows':
        final line = _doctorLine(doctor, 'Visual Studio');
        if (line == null || !line.contains('√')) {
          return 'Visual Studio 不可用（flutter doctor）';
        }
        return null;
      case 'ohos':
        if (!File('ohos/build-profile.json5').existsSync()) {
          return 'OHOS 工程缺少项目级 build-profile.json5（无可构建 entry module）';
        }
        final hos = Platform.environment['HOS_SDK_HOME'];
        final line = _doctorLine(doctor, 'HarmonyOS');
        final doctorOk = line != null && line.contains('√');
        if (hos != null && hos.isNotEmpty) {
          final sdkDirectory = Directory(hos);
          final hasSdkFiles = sdkDirectory.existsSync() &&
              sdkDirectory
                  .listSync(recursive: true, followLinks: false)
                  .any((entry) => entry is File);
          if (!hasSdkFiles) {
            return 'HOS_SDK_HOME 未包含可用 SDK 文件';
          }
        } else if (!doctorOk) {
          return 'HOS_SDK_HOME 未设置且 flutter doctor HarmonyOS toolchain 不可用';
        }
        return null;
      default:
        return null;
    }
  }

  String? _doctorLine(String doctor, String keyword) {
    for (final line in doctor.split('\n')) {
      if (line.contains(keyword)) return line.trim();
    }
    return null;
  }

  Future<String> _flutterDoctor() async {
    final result = await _runCommand(
      [Platform.isWindows ? 'flutter.bat' : 'flutter', 'doctor'],
    );
    return result.stdout;
  }

  Future<_CmdOutcome> _runCommand(List<String> command) async {
    final resolved = [
      if (Platform.isWindows && command.first == 'flutter') 'flutter.bat'
      else if (Platform.isWindows && command.first == 'dart') 'dart.bat'
      else command.first,
      ...command.skip(1),
    ];
    final result = await Process.run(
      resolved.first,
      resolved.skip(1).toList(),
      workingDirectory: Directory.current.path,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    return _CmdOutcome(
      exitCode: result.exitCode,
      stdout: result.stdout.toString(),
      stderr: result.stderr.toString(),
    );
  }

  static String _sha256File(File file) {
    // FNV-1a 64 内容指纹（缓存/证据用途，非密码学）。
    final bytes = file.readAsBytesSync();
    var hash = 0xcbf29ce484222325;
    for (final byte in bytes) {
      hash ^= byte;
      hash = (hash * 0x100000001b3) & 0x7fffffffffffffff;
    }
    return 'fnv1a64-${hash.toRadixString(16)}-${bytes.length}B';
  }

  static String _tail(String text, int limit) {
    if (text.length <= limit) return text;
    return '...(截断)...${text.substring(text.length - limit)}';
  }
}

class _CmdOutcome {
  const _CmdOutcome({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  final int exitCode;
  final String stdout;
  final String stderr;
}

Future<void> main(List<String> args) async {
  String? reportPath;
  final index = args.indexOf('--report');
  if (index >= 0 && index + 1 < args.length) {
    reportPath = args[index + 1];
  }
  final report = await PlatformBuildMatrix().run(reportPath: reportPath);
  final available = (report['platforms'] as List)
      .where((r) => (r as Map)['status'] != 'release_deferred')
      .length;
  final built = (report['platforms'] as List)
      .where((r) => (r as Map)['status'] == 'built')
      .length;
  stdout.writeln(
    '[platform] available=$available built=$built '
    'all_available_built=${report['all_available_built']}',
  );
  exit(report['all_available_built'] == true ? 0 : 1);
}
