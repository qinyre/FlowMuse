import 'dart:convert';

/// 数字的 canonical 文本形态：VM 与 dart2js 必须逐字节一致。
///
/// - 整数值（int 或整值 double）一律十进制整数形态（VM `(1.0).toString()`
///   是 "1.0"、dart2js 是 "1"，故显式整数化）；
/// - 0 与 -0.0 归一为 "0"；
/// - 非整值 double 用最短往返表示（两端语义一致）；
/// - NaN/Infinity 给出哨兵文本（正常 Scene 不应出现）。
String canonicalNum(num v) {
  if (v.isNaN) return 'NaN';
  if (v.isInfinite) return v.isNegative ? '-Inf' : 'Inf';
  if (v == 0) return '0';
  if (v is int) return v.toString();
  final d = v as double;
  if (d == d.truncateToDouble() && d.abs() < 1e15) {
    return d.truncateToDouble().toInt().toString();
  }
  return d.toString();
}

/// 任意 JSON 形值的 canonical 文本：Map 键排序、List 保序、数字/字符串归一。
/// 字符串经 [jsonEncode] 转义，保证分隔符不可注入。
String canonicalValue(Object? value) {
  if (value == null) return 'null';
  if (value is bool) return value.toString();
  if (value is num) return canonicalNum(value);
  if (value is String) return jsonEncode(value);
  if (value is Map) {
    final keys = value.keys.map((k) => k.toString()).toList()..sort();
    final buffer = StringBuffer('{');
    var first = true;
    for (final key in keys) {
      if (!first) buffer.write(',');
      first = false;
      buffer
        ..write(jsonEncode(key))
        ..write(':')
        ..write(canonicalValue(value[key]));
    }
    buffer.write('}');
    return buffer.toString();
  }
  if (value is Iterable) {
    final buffer = StringBuffer('[');
    var first = true;
    for (final item in value) {
      if (!first) buffer.write(',');
      first = false;
      buffer.write(canonicalValue(item));
    }
    buffer.write(']');
    return buffer.toString();
  }
  throw ArgumentError.value(value, 'value', '不可 canonical 化的类型');
}
