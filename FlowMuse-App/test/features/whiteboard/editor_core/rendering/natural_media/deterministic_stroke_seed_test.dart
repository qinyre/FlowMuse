import 'dart:io';

import 'package:flow_muse/features/whiteboard/editor_core/src/rendering/natural_media/deterministic_stroke_seed.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../../../tool/natural_media_hash_web_check/hash_vectors.dart';

// ---------------------------------------------------------------------------
// §3.3 种子固定向量 + 源码门禁（计划 T2/T11）。
//
// 本文件必须同时在 VM 与 Chrome 实际执行：
//   flutter test test/features/whiteboard/editor_core/rendering/natural_media/deterministic_stroke_seed_test.dart
//   flutter test --platform chrome test/features/whiteboard/editor_core/rendering/natural_media/deterministic_stroke_seed_test.dart
//
// 向量来源：
//  - fnv1a32 空串/"a"/"abc"/"foobar" 为 FNV-1a 32 公开规范值；
//  - mul32/mix32 为 T2 协议自冻结值（二轮审查期间以 dart VM 与
//    dart2js+node 双跑逐值核对后固化），修改即修订协议。
// ---------------------------------------------------------------------------

void main() {
  group('冻结向量（与 node/V8 检查共用唯一样本源）', () {
    test('全部冻结向量在 VM 上逐值一致', () {
      // 向量清单在 tool/natural_media_hash_web_check/hash_vectors.dart
      // 单点维护：本测试（VM）与 dart2js+node（V8）跑同一组断言。
      // 跨端门禁命令（chrome 平台 flutter test 在本机 dwds 通道挂起，
      // 见计划 §12 已知降级）：
      //   powershell -File tool/natural_media_hash_web_check/run.ps1
      final failures = runFrozenVectorChecks();
      expect(failures, isEmpty, reason: failures.join('; '));
    });
  });

  group('rand01 与 channel 常量', () {
    test('rand01 ∈ [0,1) 且 salt 区分', () {
      for (final seed in [0, 1, 0x811c9dc5, 0xFFFFFFFF, 0x7FFFFFFF]) {
        for (final salt in [0x11, 0x22, 0x33]) {
          final v = rand01(seed, salt);
          expect(v, greaterThanOrEqualTo(0));
          expect(v, lessThan(1));
        }
      }
      expect(rand01(12345, 1), isNot(equals(rand01(12345, 2))));
    });

    test('channel 编号跨端冻结', () {
      expect(NaturalMediaChannel.base, 0);
      expect(NaturalMediaChannel.pencilLow, 1);
      expect(NaturalMediaChannel.pencilMedium, 2);
      expect(NaturalMediaChannel.pencilHeavy, 3);
      expect(NaturalMediaChannel.brushBody, 4);
      expect(NaturalMediaChannel.brushStrand, 5);
    });
  });

  group('源码门禁：禁止 hashCode/Object.hash/Random/裸 32 位乘法', () {
    test('natural_media 生产源码不含被禁模式', () {
      final dir = Directory(
        'lib/features/whiteboard/editor_core/src/rendering/natural_media',
      );
      expect(dir.existsSync(), isTrue);
      final banned = <RegExp>[
        RegExp(r'\.hashCode\b'),
        RegExp(r'\bObject\.hash\b'),
        RegExp(r'\bRandom\s*\('),
        RegExp(r'\*\s*0x[0-9a-fA-F]{5,}'), // 直接乘 ≥5 位十六进制常数
        RegExp(r'\*\s*16777619\b'),
      ];
      String stripComments(String source) {
        var out = source;
        out = out.replaceAll(RegExp('/\\*[\\s\\S]*?\\*/'), ' ');
        out = out.replaceAll(RegExp('//[^\n]*'), ' ');
        return out;
      }

      final offenders = <String>[];
      for (final file in dir.listSync(recursive: true)) {
        if (file is! File || !file.path.endsWith('.dart')) continue;
        // 只扫代码：注释里的教学性提及（如本文件解释为何禁用）不算
        // 违规；字符串字面量中的被禁串仍会被扫到（偏保守方向）。
        final source = stripComments(file.readAsStringSync());
        for (final pattern in banned) {
          if (pattern.hasMatch(source)) {
            offenders.add('${file.path} 命中 ${pattern.pattern}');
          }
        }
      }
      expect(
        offenders,
        isEmpty,
        reason: '种子相关代码禁止绕过 mul32 栈：${offenders.join('; ')}',
      );
    });
  });
}

/// 与 strokeSeedOf 同义的探针（utf8 前缀拼接后取 fnv1a32）。
int strokeSeedProbe(String strokeId) =>
    fnv1a32('flowmuse-natural-media-v2|$strokeId'.codeUnits);
