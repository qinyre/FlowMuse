// tool/natural_media_hash_web_check/hash_vectors.dart
//
// §3.3 种子冻结向量的唯一样本源（纯 Dart、无 Flutter 依赖）：
//  - deterministic_stroke_seed_test.dart（VM）从这里读取向量断言；
//  - main.dart 经 dart2js 编译后由 node（V8）执行同一断言集
//   （Chrome 平台 flutter test 在本机 dwds 通道挂起，见计划 §12
//    已知降级记录；T12 Web Profile 仍会在真实 Chrome 上跑整应用）。
//
// 向量来源：fnv1a32 为 FNV-1a 32 公开规范值；mul32/mix32 为协议
// 自冻结值（二轮审查期间 dart VM 与 dart2js+node 双跑核对后固化）。
// 修改任何向量 = 修订协议。
import 'package:flow_muse/features/whiteboard/editor_core/src/rendering/natural_media/deterministic_stroke_seed.dart';

/// 一次向量断言；返回失败描述（空列表 = 全部通过）。
List<String> runFrozenVectorChecks() {
  final failures = <String>[];
  void check(String name, Object actual, Object expected) {
    if (actual != expected) {
      failures.add('$name: expected=$expected actual=$actual');
    }
  }

  // fnv1a32 公开规范向量。
  check('fnv1a32(empty)', fnv1a32(const []), 0x811c9dc5);
  check('fnv1a32(a)', fnv1a32('a'.codeUnits), 0xe40c292c);
  check('fnv1a32(abc)', fnv1a32('abc'.codeUnits), 0x1a47e90b);
  check('fnv1a32(foobar)', fnv1a32('foobar'.codeUnits), 0xbf9cf968);

  // mul32：bit31 两侧与全 1（模 2^32 数学正确值）。
  check('mul32(ff*ff)', mul32(0xFFFFFFFF, 0xFFFFFFFF), 1);
  check('mul32(ff*fnvPrime)', mul32(0xFFFFFFFF, 0x01000193), 0xfefffe6d);
  check(
    'mul32(commutative)',
    mul32(0x12345678, 0x9ABCDEF0),
    mul32(0x9ABCDEF0, 0x12345678),
  );
  check('mul32(zero)', mul32(0, 0xDEADBEEF), 0);
  check('mul32(identity)', mul32(1, 0xDEADBEEF), 0xDEADBEEF);

  // fmix32 / mix32 协议冻结向量（含 bit31 置位、最大合法 edge/ordinal）。
  check('fmix32(0)', fmix32(0), 0);
  check('mix32(seed-empty)', mix32(0x811c9dc5, 16383, 4095, 5), 0xe263ff16);
  check('mix32(seed-empty,0)', mix32(0x811c9dc5, 0, 0, 0), 0x8b4eccd8);
  check('mix32(bit31)', mix32(0xFFFFFFFF, 16383, 4095, 5), 0x16ab336e);
  check('mix32(seed-abc)', mix32(0x1a47e90b, 16383, 4095, 5), 0xa525cdda);
  check('mix32(seed-abc,0)', mix32(0x1a47e90b, 0, 0, 0), 0xcc41ce57);
  check('strokeSeed(elm-9f3k2)', strokeSeedOf('elm-9f3k2'), 0xa64248ad);
  check('mix32(seed-elm)', mix32(0xa64248ad, 16383, 4095, 5), 0xe6510bb6);
  check('mix32(seed-elm,0)', mix32(0xa64248ad, 0, 0, 0), 0x76c6f954);
  check('strokeSeed(120x)', strokeSeedOf('x' * 120), 0xb491db93);
  check('mix32(seed-long)', mix32(0xb491db93, 16383, 4095, 5), 0x85558b6b);
  check('mix32(seed-long,0)', mix32(0xb491db93, 0, 0, 0), 0x4dfd8462);

  // 非 ASCII 路径（code point 与 utf8 字节各自冻结）。
  check('fnv1a32(cjk-runes)', fnv1a32('铅笔'.runes.toList()), 0x77040f7c);
  check(
    'fnv1a32(cjk-utf8bytes)',
    fnv1a32(const [0xe9, 0x93, 0x85, 0xe7, 0xac, 0x94]),
    0xfaa0d3fd,
  );
  check(
    'strokeSeedOf(utf8-prefix)',
    strokeSeedOf('abc'),
    fnv1a32('flowmuse-natural-media-v2|abc'.codeUnits),
  );

  // rand01 值域与 salt 区分。
  for (final seed in [0, 1, 0x811c9dc5, 0xFFFFFFFF, 0x7FFFFFFF]) {
    for (final salt in [0x11, 0x22, 0x33]) {
      final v = rand01(seed, salt);
      if (!(v >= 0 && v < 1)) {
        failures.add('rand01($seed,$salt) out of [0,1): $v');
      }
    }
  }
  if (rand01(12345, 1) == rand01(12345, 2)) {
    failures.add('rand01 salt 未区分');
  }
  return failures;
}
