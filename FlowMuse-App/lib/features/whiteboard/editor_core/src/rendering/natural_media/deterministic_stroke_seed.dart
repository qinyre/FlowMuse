import 'dart:convert';

// ---------------------------------------------------------------------------
// 跨端确定性种子（计划 §3.3，协议级参考语义的正式落地）。
//
// dart2js 陷阱：JS number 是 53 位尾数 double，`h * 16777619` 的乘积
// 可超过 2^53，低位在掩码前已丢失；`&` 在 JS 侧是 ToInt32（带符号）。
// 因此所有 32 位混合乘法必须走 [mul32]（16 位拆分 + `.toUnsigned(32)`），
// 禁止裸大整数乘法、`String.hashCode`、`Object.hash` 与默认 `Random`
//（deterministic_stroke_seed_test.dart 的源码门禁持续拦截）。
//
// 本文件是 Canvas / 本地湿墨 / 远端湿墨 / SVG 四条链路与 .markdraw
// 往返的唯一种子来源；修改任何算式等同修订协议，必须同步固定向量。
// ---------------------------------------------------------------------------

/// 32 位模乘：a·b mod 2^32，16 位拆分保证 VM 与 dart2js 逐位一致。
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

/// FNV-1a 32：空串 = 0x811c9dc5（偏移基），"abc" = 0x1a47e90b
///（公开规范向量，VM/Chrome 双跑核对）。
int fnv1a32(List<int> bytes) {
  var hash = 0x811c9dc5;
  for (final byte in bytes) {
    hash = mul32(hash ^ byte, 0x01000193);
  }
  return hash.toUnsigned(32);
}

/// murmur3 fmix32 终混。
int fmix32(int value) {
  var x = value.toUnsigned(32);
  x = (x ^ (x >>> 16)).toUnsigned(32);
  x = mul32(x, 0x85ebca6b);
  x = (x ^ (x >>> 13)).toUnsigned(32);
  x = mul32(x, 0xc2b2ae35);
  return (x ^ (x >>> 16)).toUnsigned(32);
}

/// 采样级混合：一个 primitive 的种子由（笔画种子, edge, ordinal,
/// channel）唯一决定，与分块级别、到达顺序、运行时无关。
int mix32(int seed, int edge, int ordinal, int channel) =>
    fmix32(fmix32(fmix32(seed ^ edge) ^ ordinal) ^ channel);

/// 自然介质 v2 笔画种子：utf8("flowmuse-natural-media-v2|" + strokeId)。
/// 不使用当前时间、房间/用户 id，也不依赖分块级别。
int strokeSeedOf(String strokeId) =>
    fnv1a32(utf8.encode('flowmuse-natural-media-v2|$strokeId'));

/// 种子 → [0,1) 确定随机小数（低 24 位 / 0x01000000）。
/// [salt] 区分同一粒子需要的多个独立随机数，禁止复用重叠位。
double rand01(int seed, int salt) =>
    (fmix32(seed ^ salt) & 0x00ffffff) / 0x01000000;

/// 自然介质 primitive 通道编号（计划 §3.4，跨端协议级常量）。
///
/// key 三元组 (edgeStartIndex, sampleOrdinal, channel) 唯一确定一个
/// primitive；交界处 join 归较后 edge 拥有。
abstract final class NaturalMediaChannel {
  static const int base = 0;
  static const int pencilLow = 1;
  static const int pencilMedium = 2;
  static const int pencilHeavy = 3;
  static const int brushBody = 4;
  static const int brushStrand = 5;
}
