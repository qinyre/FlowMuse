// tool/natural_media_spike/natural_media_seed_spike.dart
//
// T0 可删除原型：跨端确定性种子（计划 §3.3 协议级参考语义的逐字
// 实现）。T2 会把同一实现落进 lib/rendering/natural_media/
// deterministic_stroke_seed.dart 并配 VM/Chrome 固定向量门禁；本文件
// 只服务 spike，T0 收口时删除。
import 'dart:convert';

int mul32(int a, int b) {
  final au = a.toUnsigned(32);
  final bu = b.toUnsigned(32);
  final a0 = au & 0xffff;
  final a1 = au >>> 16;
  final b0 = bu & 0xffff;
  final b1 = bu >>> 16;
  final low = a0 * b0;
  final cross = ((a1 * b0 + a0 * b1) & 0xffff) << 16;
  return (low + cross).toUnsigned(32);
}

int fnv1a32(List<int> bytes) {
  var hash = 0x811c9dc5;
  for (final byte in bytes) {
    hash = mul32(hash ^ byte, 0x01000193);
  }
  return hash.toUnsigned(32);
}

int fmix32(int value) {
  var x = value.toUnsigned(32);
  x = (x ^ (x >>> 16)).toUnsigned(32);
  x = mul32(x, 0x85ebca6b);
  x = (x ^ (x >>> 13)).toUnsigned(32);
  x = mul32(x, 0xc2b2ae35);
  return (x ^ (x >>> 16)).toUnsigned(32);
}

int mix32(int seed, int edge, int ordinal, int channel) =>
    fmix32(fmix32(fmix32(seed ^ edge) ^ ordinal) ^ channel);

/// 自然介质 v2 笔画种子。
int strokeSeedOf(String strokeId) =>
    fnv1a32(utf8.encode('flowmuse-natural-media-v2|$strokeId'));

/// 种子 → [0,1) 确定随机小数（低 24 位 / 0x01000000）。
/// [salt] 区分同一粒子需要的多个独立随机数，禁止复用重叠位。
double rand01(int seed, int salt) =>
    (fmix32(seed ^ salt) & 0x00ffffff) / 0x01000000;
