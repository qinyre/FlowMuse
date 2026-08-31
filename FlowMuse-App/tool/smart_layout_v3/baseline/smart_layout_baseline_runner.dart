/// 智能排版 v3 自动基线 runner（V3-003A）。
///
/// 用同一 runner 生成两条基线（no-op 与 v2 代表策略）的 Scene、PNG、指标、
/// 失败分类与资源数据：
/// - no_op：输出=输入（整洁页非劣的参照端点）；
/// - v2_naive_reflow：单列自上而下重排内容元素（text/shape/image），
///   笔迹/装饰线/绑定保持原位——这是 v2 行为特征的确定性代表策略，
///   不是生产 v2 输出的复刻（dev 线限制，报告如实声明）。
/// 失败分类按 failure-taxonomy 谓词的机器可执行子集（OOB/重叠/字符流丢失/
/// 源丢失）计；缺候选/崩溃/超时一律记 status=failed，绝不计作成功。
/// 确定性：同输入两次运行，逐样本 Scene/PNG/指标 hash 完全一致
///（资源数据单独记录，不进入确定性 hash）。
library;

import 'dart:convert';
import 'dart:io' show zlib;

import 'package:crypto/crypto.dart' as crypto;

class SmartLayoutBaselineRunner {
  const SmartLayoutBaselineRunner._();

  static const Set<String> policies = {'no_op', 'v2_naive_reflow'};
  static const Set<String> contentTypes = {'text', 'shape', 'image'};

  /// 对单个场景应用基线策略，返回输出场景（新对象，不改输入）。
  static Map<String, Object?> applyPolicy(String policy, Map<String, Object?> scene) {
    if (policy == 'no_op') {
      return jsonDecode(jsonEncode(scene)) as Map<String, Object?>;
    }
    if (policy != 'v2_naive_reflow') {
      throw ArgumentError('unknown policy: $policy');
    }
    final page = scene['page'] as Map<String, Object?>;
    final pageWidth = (page['width'] as num).toDouble();
    final content = <Map<String, Object?>>[];
    final passthrough = <Map<String, Object?>>[];
    for (final element in (scene['elements'] as List).cast<Map<String, Object?>>()) {
      if (contentTypes.contains(element['type'])) {
        content.add(jsonDecode(jsonEncode(element)) as Map<String, Object?>);
      } else {
        passthrough.add(element);
      }
    }

    int row(Map<String, Object?> e) {
      final b = (e['bbox'] as List).cast<num>();
      return ((b[1].toDouble() + b[3].toDouble() / 2) / 64).floor();
    }

    // 阅读序：与标注手册 R1 同式（行带、左缘、id）。
    content.sort((a, b) {
      final ra = row(a), rb = row(b);
      if (ra != rb) return ra.compareTo(rb);
      final xa = (a['bbox'] as List).cast<num>()[0].toDouble();
      final xb = (b['bbox'] as List).cast<num>()[0].toDouble();
      if (xa != xb) return xa.compareTo(xb);
      return (a['id'] as String).compareTo(b['id'] as String);
    });

    const margin = 24.0;
    const gap = 12.0; // 段间距（v2 代表参数，冻结于本策略定义）。
    var cursorY = margin;
    final maxW = pageWidth - margin * 2;
    for (final element in content) {
      final b = (element['bbox'] as List).cast<num>();
      final h = b[3].toDouble();
      final w = b[2].toDouble() > maxW ? maxW : b[2].toDouble();
      element['bbox'] = [margin, cursorY.round(), w.round(), h.round()];
      cursorY += h + gap;
    }
    return {
      'page': jsonDecode(jsonEncode(page)) as Map<String, Object?>,
      'elements': [...passthrough, ...content],
    };
  }

  /// 按分类账谓词的机器子集评测输出场景。
  static BaselineEvaluation evaluate(Map<String, Object?> input, Map<String, Object?> output) {
    final page = output['page'] as Map<String, Object?>;
    final pageW = (page['width'] as num).toDouble();
    final pageH = (page['height'] as num).toDouble();
    final inElements = (input['elements'] as List).cast<Map<String, Object?>>();
    final outElements = (output['elements'] as List).cast<Map<String, Object?>>();
    final outIds = outElements.map((e) => e['id'] as String).toSet();

    var lost = 0;
    for (final e in inElements) {
      if (!outIds.contains(e['id'] as String)) lost++;
    }
    final recall = inElements.isEmpty ? 1.0 : (inElements.length - lost) / inElements.length;

    String charsOf(Map<String, Object?> e) => e['x'] is String ? e['x'] as String : '';
    final inChars = <String, String>{
      for (final e in inElements)
        if (e['type'] == 'text') e['id'] as String: charsOf(e),
    };
    final outChars = <String, String>{
      for (final e in outElements)
        if (e['type'] == 'text') e['id'] as String: charsOf(e),
    };
    final typedLost = <String>[
      for (final entry in inChars.entries)
        if (outChars[entry.key] != entry.value) entry.key,
    ];

    var oob = 0;
    var overlapPairs = 0;
    final contentOut = outElements.where((e) => contentTypes.contains(e['type'])).toList();
    List<double> box(Map<String, Object?> e) =>
        (e['bbox'] as List).cast<num>().map((n) => n.toDouble()).toList();

    for (final e in contentOut) {
      final b = box(e);
      if (b[0] < 0 || b[1] < 0 || b[0] + b[2] > pageW || b[1] + b[3] > pageH) oob++;
    }
    for (var i = 0; i < contentOut.length; i++) {
      for (var j = i + 1; j < contentOut.length; j++) {
        final a = box(contentOut[i]), b = box(contentOut[j]);
        final w = _intersectionExtent(a[0], a[2], b[0], b[2]);
        final h = _intersectionExtent(a[1], a[3], b[1], b[3]);
        final inter = w * h;
        final smaller = (a[2] * a[3]) < (b[2] * b[3]) ? a[2] * a[3] : b[2] * b[3];
        if (smaller > 0 && inter / smaller > 0.02) overlapPairs++;
      }
    }

    final codes = <String>[];
    if (lost > 0) codes.add('C-SNAPSHOT-LOST-SOURCE');
    if (typedLost.isNotEmpty) codes.add('C-SNAPSHOT-TYPED-TEXT-LOST');
    if (oob > 0) codes.add('M-LAYOUT-OOB');
    if (overlapPairs > 0) codes.add('M-LAYOUT-OVERLAP');
    return BaselineEvaluation(
      sourceRecall: recall,
      lostCount: lost,
      typedTextLost: typedLost,
      oobCount: oob,
      overlapPairCount: overlapPairs,
      codes: codes,
      criticalCount: codes.where((c) => c.startsWith('C-')).length,
      majorCount: codes.where((c) => c.startsWith('M-')).length,
    );
  }

  static double _intersectionExtent(double a0, double aSpan, double b0, double bSpan) {
    final lo = a0 > b0 ? a0 : b0;
    final hi = (a0 + aSpan) < (b0 + bSpan) ? (a0 + aSpan) : (b0 + bSpan);
    return hi > lo ? hi - lo : 0.0;
  }

  /// 把输出场景栅格化为确定性灰度 PNG（覆盖格 0x00，空白 0xFF）。
  static List<int> rasterizePng(Map<String, Object?> scene, {int scale = 8}) {
    final page = scene['page'] as Map<String, Object?>;
    final w = (((page['width'] as num) / scale).ceil()).clamp(1, 4096);
    final h = (((page['height'] as num) / scale).ceil()).clamp(1, 4096);
    final pixels = List<int>.filled(w * h, 0xFF);
    for (final e in (scene['elements'] as List).cast<Map<String, Object?>>()) {
      final b = (e['bbox'] as List).cast<num>().map((n) => n.toDouble()).toList();
      final x0 = (b[0] / scale).ceil().clamp(0, w - 1);
      final x1 = ((b[0] + b[2]) / scale).floor().clamp(0, w - 1);
      final y0 = (b[1] / scale).ceil().clamp(0, h - 1);
      final y1 = ((b[1] + b[3]) / scale).floor().clamp(0, h - 1);
      for (var y = y0; y <= y1; y++) {
        for (var x = x0; x <= x1; x++) {
          pixels[y * w + x] = 0x00;
        }
      }
    }
    return PngEncoder.encodeGray8(w, h, pixels);
  }

  static String sha256Of(List<int> bytes) => crypto.sha256.convert(bytes).toString();

  static String canonicalSceneSha256(Map<String, Object?> scene) =>
      sha256Of(utf8.encode(jsonEncode(scene)));
}

class BaselineEvaluation {
  const BaselineEvaluation({
    required this.sourceRecall,
    required this.lostCount,
    required this.typedTextLost,
    required this.oobCount,
    required this.overlapPairCount,
    required this.codes,
    required this.criticalCount,
    required this.majorCount,
  });
  final double sourceRecall;
  final int lostCount;
  final List<String> typedTextLost;
  final int oobCount;
  final int overlapPairCount;
  final List<String> codes;
  final int criticalCount;
  final int majorCount;

  Map<String, Object?> toJson() => {
        'source_recall': sourceRecall,
        'lost_count': lostCount,
        'typed_text_lost': typedTextLost,
        'oob_count': oobCount,
        'overlap_pair_count': overlapPairCount,
        'failure_codes': codes,
        'critical_count': criticalCount,
        'major_count': majorCount,
      };
}

/// 最小确定性灰度 PNG 编码器（IHDR+IDAT+IEND，filter=0，zlib 由 dart:io 提供）。
class PngEncoder {
  static List<int> encodeGray8(int width, int height, List<int> pixels) {
    final ihdr = <int>[
      ..._u32(width), ..._u32(height),
      8, // bit depth
      0, // color type: grayscale
      0, 0, 0, // compression, filter, interlace
    ];
    final raw = <int>[];
    for (var y = 0; y < height; y++) {
      raw.add(0); // filter: none
      raw.addAll(pixels.sublist(y * width, y * width + width));
    }
    final out = <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
    out.addAll(_chunk('IHDR', ihdr));
    out.addAll(_chunk('IDAT', zlib.encode(raw)));
    out.addAll(_chunk('IEND', const []));
    return out;
  }

  static List<int> _chunk(String type, List<int> data) => [
        ..._u32(data.length),
        ...type.codeUnits,
        ...data,
        ..._u32(_crc32(type.codeUnits, data)),
      ];

  static List<int> _u32(int v) => [(v >> 24) & 0xff, (v >> 16) & 0xff, (v >> 8) & 0xff, v & 0xff];

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
}
