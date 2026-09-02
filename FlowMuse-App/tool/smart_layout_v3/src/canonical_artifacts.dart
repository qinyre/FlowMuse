import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;

/// 规范化产物与稳定哈希（V3-001B）。
///
/// 跨运行、跨进程一致的产物哈希必须建立在规范化表示上：
/// - JSON：递归键排序、无空白、数字经规范格式化（整数不带 .0，双精度按
///   最短往返表示），剥离易变键（时间戳/随机数）；
/// - PNG：只保留关键 chunk（IHDR/PLTE/tEXt 之外的 PLTE 系列与 IDAT/IEND），
///   丢弃携带时间戳与元数据的辅助 chunk（tIME/tEXt/iTXt/zTXt/hIST 等），
///   再对 chunk 序列重新序列化哈希，使编码器注入的元数据不影响哈希。
class CanonicalArtifacts {
  /// 需要从规范化 JSON 中剥离的易变键（相对键名，任意层级）。
  static const Set<String> volatileKeys = {
    'generated_at_utc',
    'recorded_at_utc',
    'updated_at_utc',
    'created_at',
    'timestamp',
    'wall_clock',
  };

  static String canonicalJson(Object? value) {
    final buffer = StringBuffer();
    _writeCanonical(value, buffer);
    return buffer.toString();
  }

  static String canonicalJsonSha256(Object? value, {bool stripVolatile = true}) {
    return _sha256(canonicalJson(stripVolatile ? _stripVolatile(value) : value));
  }

  static void _writeCanonical(Object? value, StringBuffer buffer) {
    if (value is Map) {
      final keys = value.keys.map((k) => k.toString()).toList()..sort();
      buffer.write('{');
      for (var i = 0; i < keys.length; i++) {
        if (i > 0) buffer.write(',');
        buffer.write('"${_escape(keys[i])}":');
        _writeCanonical(value[keys[i]], buffer);
      }
      buffer.write('}');
    } else if (value is List) {
      buffer.write('[');
      for (var i = 0; i < value.length; i++) {
        if (i > 0) buffer.write(',');
        _writeCanonical(value[i], buffer);
      }
      buffer.write(']');
    } else if (value is String) {
      buffer.write('"${_escape(value)}"');
    } else if (value is bool || value == null) {
      buffer.write(value.toString());
    } else if (value is num) {
      buffer.write(_formatNumber(value));
    } else {
      throw FormatException('不可规范化类型：${value.runtimeType}');
    }
  }

  /// 数字规范格式：整数无小数点；双精度用最短往返表示，保证同一数值跨运行
  /// 字节一致（Dart double.toString 即最短往返表示，且不依赖 locale）。
  static String _formatNumber(num value) {
    if (value is int) return value.toString();
    if (value == value.roundToDouble() && value.abs() < 1e15) {
      return value.toInt().toString();
    }
    return value.toString();
  }

  static String _escape(String raw) {
    var out = raw.replaceAll('\\', '\\\\').replaceAll('"', '\\"');
    final control = RegExp(r'[\x00-\x1f]');
    out = out.replaceAllMapped(control, (m) => '\\u${m[0]!.codeUnitAt(0).toRadixString(16).padLeft(4, '0')}');
    return out;
  }

  static Object? _stripVolatile(Object? value) {
    if (value is Map) {
      return {
        for (final entry in value.entries)
          if (!volatileKeys.contains(entry.key.toString())) entry.key.toString(): _stripVolatile(entry.value),
      };
    }
    if (value is List) {
      return [for (final item in value) _stripVolatile(item)];
    }
    return value;
  }

  static const List<int> _pngSignature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

  /// PNG 关键 chunk 白名单（大小写敏感，PNG 规范）。
  static const Set<String> _pngCriticalChunks = {'IHDR', 'PLTE', 'IDAT', 'IEND', 'tRNS', 'gAMA', 'cHRM', 'sRGB', 'iCCP'};

  /// 规范化 PNG：校验签名，只保留白名单 chunk 按原序重排（IHDR 首、IEND 尾），
  /// 返回规范化字节流；对相同像素与颜色配置跨运行稳定。
  static List<int> canonicalPng(List<int> bytes) {
    if (bytes.length < 8 || !_bytesEqual(bytes.sublist(0, 8), _pngSignature)) {
      throw const FormatException('not a PNG: signature mismatch');
    }
    final kept = <MapEntry<String, List<int>>>[];
    var offset = 8;
    while (offset + 8 <= bytes.length) {
      final length = (bytes[offset] << 24) | (bytes[offset + 1] << 16) | (bytes[offset + 2] << 8) | bytes[offset + 3];
      final type = String.fromCharCodes(bytes.sublist(offset + 4, offset + 8));
      final dataStart = offset + 8;
      final dataEnd = dataStart + length;
      if (dataEnd + 4 > bytes.length) {
        throw const FormatException('not a PNG: truncated chunk');
      }
      if (_pngCriticalChunks.contains(type)) {
        kept.add(MapEntry(type, bytes.sublist(dataStart, dataEnd)));
      }
      offset = dataEnd + 4;
    }
    if (kept.isEmpty || kept.first.key != 'IHDR' || kept.last.key != 'IEND') {
      throw const FormatException('not a PNG: missing IHDR/IEND');
    }
    final out = <int>[..._pngSignature];
    for (final chunk in kept) {
      final data = chunk.value;
      _writeUint32(out, data.length);
      out.addAll(chunk.key.codeUnits);
      out.addAll(data);
      _writeUint32(out, _crc32(chunk.key.codeUnits, data));
    }
    return out;
  }

  static String canonicalPngSha256(List<int> bytes) => crypto.sha256.convert(canonicalPng(bytes)).toString();

  static bool _bytesEqual(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static void _writeUint32(List<int> out, int value) {
    out..add((value >> 24) & 0xff)..add((value >> 16) & 0xff)..add((value >> 8) & 0xff)..add(value & 0xff);
  }

  static final List<int> _crcTable = _buildCrcTable();

  static List<int> _buildCrcTable() {
    final table = List<int>.filled(256, 0);
    for (var n = 0; n < 256; n++) {
      var c = n;
      for (var k = 0; k < 8; k++) {
        c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1);
      }
      table[n] = c;
    }
    return table;
  }

  static int _crc32(List<int> typeBytes, List<int> data) {
    var crc = 0xFFFFFFFF;
    for (final byte in typeBytes) {
      crc = _crcTable[(crc ^ byte) & 0xff] ^ (crc >> 8);
    }
    for (final byte in data) {
      crc = _crcTable[(crc ^ byte) & 0xff] ^ (crc >> 8);
    }
    return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
  }

  static String _sha256(String text) => crypto.sha256.convert(utf8.encode(text)).toString();
}
