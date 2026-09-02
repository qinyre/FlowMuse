import 'dart:convert';

import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import 'deterministic_hash.dart';
import 'stable_element_identity.dart';

/// Scene 内容的 canonical fingerprint：跨端一致（VM/dart2js 同值）、
/// 与元素列表顺序无关、覆盖元素（含软删）、图片文件与 smartLayout 文档。
///
/// 只用于智能排版完整性校验（revision/CAS 前置检查），不替代协作 CAS，
/// 也不写入持久化协议——持久化一律使用协作既有字段。
class SceneFingerprint {
  const SceneFingerprint._(this.value);

  /// 16 个小写 hex 字符（双 32 位车道）。
  final String value;

  factory SceneFingerprint.of(Scene scene) {
    final payload = canonicalScenePayload(scene);
    return SceneFingerprint._(fingerprint64(payload));
  }

  @override
  bool operator ==(Object other) =>
      other is SceneFingerprint && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'SceneFingerprint($value)';
}

/// ImageFile 内容哈希缓存（ImageFile 不可变，Expando 按实例缓存整段
/// 内容哈希，避免每次指纹重算大图字节；随实例回收自动释放）。
final Expando<String> _fileHashCache = Expando<String>();

/// 数字的 canonical 文本形态：VM 与 dart2js 必须逐字节一致。
///
/// - 整数值（int 或整值 double）一律十进制整数形态（VM `(1.0).toString()`
///   是 "1.0"、dart2js 是 "1"，故显式整数化）；
/// - 0 与 -0.0 归一为 "0"；
/// - 非整值 double 用最短往返表示（两端语义一致）；
/// - NaN/Infinity 给出哨兵文本（正常 Scene 不应出现）。
@visibleForTesting
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
@visibleForTesting
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

/// 单个元素的 canonical 投影：复用 Excalidraw JSON 全字段序列化，
/// 按键排序+数字归一；元素间以 id（[StableElementIdentity]）排序保证
/// 与列表顺序无关。
@visibleForTesting
String canonicalElementPayload(Element element) =>
    canonicalValue(ExcalidrawJsonCodec.elementToJson(element));

String _canonicalFilePayload(String fileId, ImageFile file) {
  var contentHash = _fileHashCache[file];
  if (contentHash == null) {
    // FNV-1a 逐字节（ImageFile 不可变，Expando 缓存整段内容哈希避免
    // 每次指纹重算大图字节）。
    var h = 0x811c9dc5;
    for (final byte in file.bytes) {
      h = mul32(h ^ byte, 0x01000193);
    }
    contentHash = h.toUnsigned(32).toRadixString(16).padLeft(8, '0');
    _fileHashCache[file] = contentHash;
  }
  return '$fileId|${file.mimeType}|${file.bytes.length}|$contentHash';
}

/// 整个 Scene 的 canonical 负载（域分隔、元素按稳定 id 排序、文件按 id
/// 排序、smartLayout 文档全量 canonical 化）。
@visibleForTesting
String canonicalScenePayload(Scene scene) {
  final buffer = StringBuffer(
    'flowmuse-scene-v1|elements=${scene.elements.length}|',
  );
  final ordered = [...scene.elements]
    ..sort(
      (a, b) =>
          StableElementIdentity.of(a).compareTo(StableElementIdentity.of(b)),
    );
  var first = true;
  for (final element in ordered) {
    if (!first) buffer.write('~');
    first = false;
    buffer.write(canonicalElementPayload(element));
  }
  final fileIds = scene.files.keys.toList()..sort();
  buffer.write('|files=${fileIds.length}|');
  var fileFirst = true;
  for (final fileId in fileIds) {
    if (!fileFirst) buffer.write('~');
    fileFirst = false;
    buffer.write(_canonicalFilePayload(fileId, scene.files[fileId]!));
  }
  buffer.write('|doc=');
  buffer.write(
    scene.smartLayout == null
        ? '-'
        : canonicalValue(scene.smartLayout!.toJson()),
  );
  return buffer.toString();
}
