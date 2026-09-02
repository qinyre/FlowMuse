import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:flow_muse/features/whiteboard/editor_core/src/core/elements/element_id.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/elements/text_element.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/rendering/text_renderer.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/design/smart_layout_design_tokens.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/design/text_measure_adapter.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/design/text_measure_cache.dart';

/// V3-300A 真实测量适配器测试：与真实 renderer 一致、边界语种覆盖
/// （CJK/长词/emoji/RTL/公式/widow-orphan/缺字体）、无估算无 ellipsis、
/// 缓存 key/失效/上限可测。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // 测试环境无网络：默认字体族 Nunito 走 GoogleFonts 路径，运行时抓取
  // 失败的异步错误会记到已完成用例头上；关闭抓取后回退字体度量，
  // 测量与 TextRenderer 一致性不受影响（两侧同一路径）。
  GoogleFonts.config.allowRuntimeFetching = false;

  TextMeasureAdapter newAdapter({TextMeasureCache? cache}) =>
      TextMeasureAdapter(cache: cache);

  test('与 TextRenderer.measure 一致（同构造路径：字体族×字号×宽度矩阵）', () {
    final adapter = newAdapter();
    const texts = <String>[
      'The quick brown fox jumps over the lazy dog',
      '智能排版把白板上的手写笔记整理成结构化文档',
      '混合 mixed 文本 with 中文 and English words',
    ];
    // GoogleFonts 族（如默认 Nunito）在测试环境无网络/无资产，异步抓取
    // 失败会记到已完成用例头上；其样式解析与 TextRenderer 共用同一
    // FontResolver.resolve 调用点，结构一致，矩阵改用两档 bundled 字体
    // 加一档未知回退覆盖三档解析路径。
    const families = <String>['Excalifont', 'Virgil', 'NoSuchFontXYZ'];
    const sizes = <double>[12, 20, 28];
    const widths = <double?>[null, 400, 120];
    for (final text in texts) {
      for (final family in families) {
        for (final size in sizes) {
          for (final maxWidth in widths) {
            final element = TextElement(
              id: ElementId('e-$family-$size-$maxWidth'),
              x: 0,
              y: 0,
              width: 100,
              height: 20,
              text: text,
              fontSize: size,
              fontFamily: family,
            );
            final (rw, rh) = TextRenderer.measure(element, maxWidth: maxWidth);
            final result = adapter.measure(
              text: text,
              fontFamily: family,
              fontSize: size,
              maxWidth: maxWidth,
            );
            expect(result.width, closeTo(rw, 1e-6),
                reason: '$family/$size/$maxWidth width');
            expect(result.height, closeTo(rh, 1e-6),
                reason: '$family/$size/$maxWidth height');
          }
        }
      }
    }
  });

  test('CJK 段落在目标宽度内换行，无溢出', () {
    final result = newAdapter().measure(
      text: '智能排版把白板上的手写笔记整理成结构化文档',
      fontFamily: 'Excalifont',
      fontSize: 20,
      maxWidth: 100,
    );
    expect(result.lineCount, greaterThan(1));
    expect(result.overflows, isFalse);
    expect(result.width, lessThanOrEqualTo(100 + 1e-6));
  });

  test('长词：引擎词内断行如实反映为多行且不溢出（与真实 renderer 一致）', () {
    final longWord = 'Donaudampfschifffahrtsgesellschaftskapitän' * 3;
    final result = newAdapter().measure(
      text: longWord,
      fontFamily: 'Excalifont',
      fontSize: 20,
      maxWidth: 50,
    );
    expect(result.lineCount, greaterThan(1), reason: '超长词被引擎词内断行');
    expect(result.overflows, isFalse);
    expect(result.width, lessThanOrEqualTo(50 + 1e-6));
  });

  test('原子簇超宽：单字素宽于目标宽度时如实溢出且宽度不截断', () {
    final result = newAdapter().measure(
      text: '密',
      fontFamily: 'Excalifont',
      fontSize: 100,
      maxWidth: 10,
    );
    expect(result.lineCount, 1, reason: '单字素无法断行');
    expect(result.width, greaterThan(10));
    expect(result.overflows, isTrue, reason: '放不下必须暴露而不是截断');
    final unbounded = newAdapter().measure(
      text: '密',
      fontFamily: 'Excalifont',
      fontSize: 100,
    );
    expect(result.width, closeTo(unbounded.width, 1e-6),
        reason: '原子簇宽度不被截断');
  });

  test('emoji：代理对与 ZWJ 序列可测量且不崩溃', () {
    final result = newAdapter().measure(
      text: '👨‍👩‍👧‍👦 family 👍🎉 emoji',
      fontFamily: 'Excalifont',
      fontSize: 20,
      maxWidth: 400,
    );
    expect(result.width, greaterThan(0));
    expect(result.height, greaterThan(0));
    expect(result.lineCount, greaterThanOrEqualTo(1));
    expect(result.overflows, isFalse);
  });

  test('RTL：阿拉伯与希伯来文本可测量并在目标宽度内换行', () {
    final rtl = newAdapter().measure(
      text: 'هذا نص باللغة العربية لقياس الاتجاه من اليمين إلى اليسار',
      fontFamily: 'Excalifont',
      fontSize: 20,
      maxWidth: 200,
      direction: ui.TextDirection.rtl,
    );
    expect(rtl.lineCount, greaterThan(1));
    expect(rtl.overflows, isFalse);
    final hebrew = newAdapter().measure(
      text: 'טקסט בעברית לבדיקת מדידה',
      fontFamily: 'Excalifont',
      fontSize: 20,
      maxWidth: 200,
      direction: ui.TextDirection.rtl,
    );
    expect(hebrew.width, greaterThan(0));
    expect(hebrew.overflows, isFalse);
  });

  test('公式符号：上标/求和/根号文本可测量', () {
    final result = newAdapter().measure(
      text: '∑xᵢ² = √3·π ≈ 5.441',
      fontFamily: 'Excalifont',
      fontSize: 20,
      maxWidth: 400,
    );
    expect(result.width, greaterThan(0));
    expect(result.lineCount, 1);
    expect(result.overflows, isFalse);
  });

  test('缺字体：未知字体族走系统回退，测量不抛异常', () {
    final result = newAdapter().measure(
      text: 'fallback text for missing font',
      fontFamily: 'DefinitelyNotARealFontFamily',
      fontSize: 20,
      maxWidth: 300,
    );
    expect(result.width, greaterThan(0));
    expect(result.height, greaterThan(0));
  });

  test('widow/orphan：行数暴露给规则判断，宽度变化改变行数', () {
    const text = 'one two three four five six seven eight';
    final wide = newAdapter().measure(
      text: text,
      fontFamily: 'Excalifont',
      fontSize: 20,
      maxWidth: 5000,
    );
    final narrow = newAdapter().measure(
      text: text,
      fontFamily: 'Excalifont',
      fontSize: 20,
      maxWidth: 100,
    );
    expect(wide.lineCount, 1);
    expect(narrow.lineCount, greaterThan(1));
    // 令牌携带孤行规则输入。
    expect(SmartLayoutDesignTokens.v1.widowOrphanMinLines, 2);
  });

  test('空文本为零尺寸；非法排版参数被拒绝', () {
    final adapter = newAdapter();
    final empty = adapter.measure(
      text: '',
      fontFamily: 'Excalifont',
      fontSize: 20,
    );
    expect(empty.width, 0);
    expect(empty.height, 0);
    expect(empty.lineCount, 0);
    expect(empty.overflows, isFalse);
    expect(
      () => adapter.measure(text: 'x', fontFamily: 'f', fontSize: 0),
      throwsArgumentError,
    );
    expect(
      () => adapter.measure(
        text: 'x',
        fontFamily: 'f',
        fontSize: 20,
        lineHeight: -1,
      ),
      throwsArgumentError,
    );
    expect(
      () => adapter.measure(text: 'x', fontFamily: 'f', fontSize: 20, maxWidth: -5),
      throwsArgumentError,
    );
  });

  test('lineHeight 缺省取令牌基线', () {
    final implicit = newAdapter().measure(
      text: 'default line height text',
      fontFamily: 'Excalifont',
      fontSize: 20,
    );
    final explicit = newAdapter().measure(
      text: 'default line height text',
      fontFamily: 'Excalifont',
      fontSize: 20,
      lineHeight: SmartLayoutDesignTokens.v1.lineHeight,
    );
    expect(implicit.height, closeTo(explicit.height, 1e-9));
    expect(implicit.width, closeTo(explicit.width, 1e-9));
  });

  group('缓存 key/失效/上限', () {
    test('同参命中缓存且结果与全新计算一致；参数变则未命中', () {
      final adapter = newAdapter();
      final first = adapter.measure(
        text: 'cache probe',
        fontFamily: 'Excalifont',
        fontSize: 20,
        maxWidth: 300,
      );
      expect(adapter.cache.misses, 1);
      expect(adapter.cache.hits, 0);
      final second = adapter.measure(
        text: 'cache probe',
        fontFamily: 'Excalifont',
        fontSize: 20,
        maxWidth: 300,
      );
      expect(adapter.cache.hits, 1);
      expect(second.width, closeTo(first.width, 1e-9));
      expect(second.height, closeTo(first.height, 1e-9));
      expect(second.lineCount, first.lineCount);
      // 字号变化 → 新键（未命中）。
      adapter.measure(
        text: 'cache probe',
        fontFamily: 'Excalifont',
        fontSize: 21,
        maxWidth: 300,
      );
      expect(adapter.cache.misses, 2);
      // 宽度变化 → 新键。
      adapter.measure(
        text: 'cache probe',
        fontFamily: 'Excalifont',
        fontSize: 20,
        maxWidth: 301,
      );
      expect(adapter.cache.misses, 3);
      // 方向变化 → 新键。
      adapter.measure(
        text: 'cache probe',
        fontFamily: 'Excalifont',
        fontSize: 20,
        maxWidth: 300,
        direction: ui.TextDirection.rtl,
      );
      expect(adapter.cache.misses, 4);
      // null 与 infinity 归一为同一键。
      adapter.measure(
        text: 'cache probe',
        fontFamily: 'Excalifont',
        fontSize: 20,
        maxWidth: null,
      );
      adapter.measure(
        text: 'cache probe',
        fontFamily: 'Excalifont',
        fontSize: 20,
        maxWidth: double.infinity,
      );
      expect(adapter.cache.misses, 5);
      expect(adapter.cache.hits, 2);
      // 全新适配器（无缓存）重算结果与缓存结果深度一致。
      final fresh = newAdapter().measure(
        text: 'cache probe',
        fontFamily: 'Excalifont',
        fontSize: 20,
        maxWidth: 300,
      );
      expect(fresh.width, closeTo(second.width, 1e-9));
      expect(fresh.height, closeTo(second.height, 1e-9));
      expect(fresh.lineCount, second.lineCount);
      expect(fresh.overflows, second.overflows);
    });

    test('LRU：超容量逐出最久未用，命中保护热条目', () {
      final adapter = newAdapter(cache: TextMeasureCache(capacity: 2));
      adapter.measure(text: 'a', fontFamily: 'F', fontSize: 20);
      adapter.measure(text: 'b', fontFamily: 'F', fontSize: 20);
      expect(adapter.cache.length, 2);
      // 命中 a（刷新 LRU 位）。
      adapter.measure(text: 'a', fontFamily: 'F', fontSize: 20);
      expect(adapter.cache.hits, 1);
      // 插入 c → 逐出 b（最久未用）。
      adapter.measure(text: 'c', fontFamily: 'F', fontSize: 20);
      expect(adapter.cache.length, 2);
      // a 仍在缓存（再次命中）；b 已被逐出（再测为未命中）。
      adapter.measure(text: 'a', fontFamily: 'F', fontSize: 20);
      expect(adapter.cache.hits, 2);
      adapter.measure(text: 'b', fontFamily: 'F', fontSize: 20);
      expect(adapter.cache.misses, 4);
    });

    test('clear 全量失效；invalidateFamily 只清目标字体族', () {
      final adapter = newAdapter();
      adapter.measure(text: 'x', fontFamily: 'F1', fontSize: 20);
      adapter.measure(text: 'y', fontFamily: 'F2', fontSize: 20);
      expect(adapter.cache.length, 2);
      expect(adapter.cache.invalidateFamily('F1'), 1);
      expect(adapter.cache.length, 1);
      adapter.measure(text: 'x', fontFamily: 'F1', fontSize: 20);
      expect(adapter.cache.length, 2);
      adapter.cache.clear();
      expect(adapter.cache.length, 0);
      adapter.measure(text: 'x', fontFamily: 'F1', fontSize: 20);
      expect(adapter.cache.length, 1);
    });
  });

  test('源码门禁：适配器禁止省略号截断/行数上限/字符数估算', () {
    final source = File(
      'lib/features/whiteboard/smart_layout/design/text_measure_adapter.dart',
    ).readAsStringSync();
    // 剥除注释行再匹配，防止文档说明自报（仓库既有源码门禁惯例）。
    final code = source
        .split('\n')
        .where((line) => !line.trimLeft().startsWith('//'))
        .join('\n');
    expect(code.contains('ellipsis'), isFalse);
    expect(code.contains('TextOverflow'), isFalse);
    expect(code.contains('maxLines'), isFalse);
    expect(code.contains('.length *'), isFalse,
        reason: '禁止字符数×系数估算宽度');
    expect(code.contains('TextPainter'), isTrue,
        reason: '必须走真实 TextPainter');
    expect(code.contains('FontResolver'), isTrue,
        reason: '必须复用编辑器 font resolver');
  });
}
