import 'dart:convert';

/// 智能排版 v3 确定性执行环境契约（V3-001A）。
///
/// 与 fixture-manifest.schema.json 的 `definitions.deterministic_environment`
/// 一一对应：DPR、locale、时区、固定时钟、随机种子、字体哈希、目标平台与
/// 离线回放网络模式。V3-001B 在此契约上实现规范化与 benchmark hash。
class DeterministicExecutionEnvironment {
  const DeterministicExecutionEnvironment({
    required this.dpr,
    required this.locale,
    required this.timezone,
    required this.fixedClockUtc,
    required this.randomSeed,
    required this.fonts,
    required this.platform,
    required this.networkMode,
  });

  factory DeterministicExecutionEnvironment.fromJson(Map<String, Object?> json) {
    final clock = json['clock'] as Map<String, Object?>?;
    if (clock == null) {
      throw const FormatException('environment.clock is required');
    }
    return DeterministicExecutionEnvironment(
      dpr: json['dpr'] as double,
      locale: json['locale'] as String,
      timezone: json['timezone'] as String,
      fixedClockUtc: clock['fixed_at_utc'] as String,
      randomSeed: json['random_seed'] as int,
      fonts: [
        for (final font in json['fonts'] as List<Object?>)
          EnvironmentFont(
            family: (font as Map<String, Object?>)['family'] as String,
            file: font['file'] as String,
            sha256: font['sha256'] as String,
          ),
      ],
      platform: json['platform'] as String,
      networkMode: json['network_mode'] as String,
    );
  }

  /// 设备像素比；renderer 与 golden 必须使用同一值。
  final double dpr;

  /// BCP-47 locale，影响字体回退与排版。
  final String locale;

  /// IANA 时区名。
  final String timezone;

  /// 固定时钟的 UTC 时刻；确定性 runner 禁止读取真实时钟。
  final String fixedClockUtc;

  /// 随机种子；所有随机源必须由此种子派生。
  final int randomSeed;

  /// 固定字体集合（文件 + SHA-256），跨端渲染一致的前提。
  final List<EnvironmentFont> fonts;

  /// 目标平台：android/ios/macos/windows/web/ohos。
  final String platform;

  /// 网络模式；契约只允许 offline_replay。
  final String networkMode;

  /// 参与 V3-001B 环境 hash 的规范化字段序列。
  List<Object?> get identityFields => [
        dpr,
        locale,
        timezone,
        fixedClockUtc,
        randomSeed,
        [
          for (final font in fonts) [font.family, font.file, font.sha256],
        ],
        platform,
        networkMode,
      ];

  Map<String, Object?> toJson() => {
        'dpr': dpr,
        'locale': locale,
        'timezone': timezone,
        'clock': {'mode': 'fixed', 'fixed_at_utc': fixedClockUtc},
        'random_seed': randomSeed,
        'fonts': [
          for (final font in fonts) {'family': font.family, 'file': font.file, 'sha256': font.sha256},
        ],
        'platform': platform,
        'network_mode': networkMode,
      };

  @override
  bool operator ==(Object other) =>
      other is DeterministicExecutionEnvironment && jsonEncode(other.toJson()) == jsonEncode(toJson());

  @override
  int get hashCode => jsonEncode(toJson()).hashCode;

  @override
  String toString() => 'DeterministicExecutionEnvironment(${jsonEncode(toJson())})';
}

class EnvironmentFont {
  const EnvironmentFont({required this.family, required this.file, required this.sha256});

  final String family;
  final String file;
  final String sha256;
}
