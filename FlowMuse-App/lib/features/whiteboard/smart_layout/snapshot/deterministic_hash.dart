import 'dart:convert';

// ---------------------------------------------------------------------------
// 跨端确定性 32 位混合（vendored 自 editor_core deterministic_stroke_seed.dart，
// 自然介质种子同款算法与公开测试向量；V3-101A canonical fingerprint 复用）。
//
// dart2js 陷阱：JS number 是 53 位尾数 double，`h * 16777619` 乘积可超 2^53，
// 低位在掩码前丢失；`&` 在 JS 侧是 ToInt32。所有 32 位乘法必须走 [mul32]
//（16 位拆分 + .toUnsigned(32)）；禁止裸大整数乘法、String.hashCode、
// Object.hash。修改算式等同修订指纹协议。
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
/// （公开规范向量，VM/Chrome 双跑核对）。
int fnv1a32(List<int> bytes) {
  var hash = 0x811c9dc5;
  for (final byte in bytes) {
    hash = mul32(hash ^ byte, 0x01000193);
  }
  return hash.toUnsigned(32);
}

String _hex32(int value) =>
    value.toUnsigned(32).toRadixString(16).padLeft(8, '0');

/// 双通道 64 位指纹（两个域分隔的 FNV-1a 32 车道拼成 16 个 hex 字符）。
/// 域前缀不同即可让两车道对相同负载产生独立结果。
String fingerprint64(String payload) {
  final a = fnv1a32(utf8.encode('flowmuse-smart-layout-v3-fp-a|$payload'));
  final b = fnv1a32(utf8.encode('flowmuse-smart-layout-v3-fp-b|$payload'));
  return '${_hex32(a)}${_hex32(b)}';
}
