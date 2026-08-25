import 'package:flutter/foundation.dart';

/// 页码范围解析：支持 "3-5,7"（第 3 到 5 页和第 7 页）、"3,5"、"3-5"。
/// 页码为 1 基（与页面 index+1 对应）；范围内部检查 a<=b、1<=n<=pageCount，重复自动去重（保持首次出现顺序）。
@immutable
class SmartLayoutPageRangeResult {
  const SmartLayoutPageRangeResult({
    required this.pageIndexes,
    this.error,
  });

  /// 解析后的页索引（0 基，升序、去重、已校验在 [0, pageCount) 内）。
  final List<int> pageIndexes;

  /// 非空表示解析失败（此时 pageIndexes 为空）。
  final String? error;

  bool get isValid => error == null;

  /// 供输入框展示的错误提示；成功时为空串。
  String get errorText => error ?? '';
}

class SmartLayoutPageRangeParser {
  const SmartLayoutPageRangeParser._();

  /// 解析 [input]；[pageCount] 为当前笔记页数（≥1）。
  static SmartLayoutPageRangeResult parse(String input, int pageCount) {
    if (pageCount <= 0) {
      return const SmartLayoutPageRangeResult(
        pageIndexes: [],
        error: '当前笔记没有页面',
      );
    }
    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      return const SmartLayoutPageRangeResult(
        pageIndexes: [],
        error: '请输入页码范围，如 3-5,7',
      );
    }
    final seen = <int>{};
    final indexes = <int>[];
    for (final rawPart in trimmed.split(',')) {
      final part = rawPart.trim();
      if (part.isEmpty) {
        return const SmartLayoutPageRangeResult(
          pageIndexes: [],
          error: '页码范围格式不正确，示例：3-5,7',
        );
      }
      final dashIndex = part.indexOf('-');
      final int start;
      final int end;
      if (dashIndex < 0) {
        final parsed = _parseInt(part);
        if (parsed == null) {
          return const SmartLayoutPageRangeResult(
            pageIndexes: [],
            error: '页码范围只能包含数字、逗号和连字符，示例：3-5,7',
          );
        }
        start = parsed;
        end = parsed;
      } else {
        if (dashIndex == 0 || dashIndex == part.length - 1) {
          return const SmartLayoutPageRangeResult(
            pageIndexes: [],
            error: '连续页面请写"开始-结束"，如 3-5',
          );
        }
        if (part.indexOf('-', dashIndex + 1) >= 0) {
          return const SmartLayoutPageRangeResult(
            pageIndexes: [],
            error: '连续页面只能包含一个连字符，如 3-5',
          );
        }
        final startParsed = _parseInt(part.substring(0, dashIndex));
        final endParsed = _parseInt(part.substring(dashIndex + 1));
        if (startParsed == null || endParsed == null) {
          return const SmartLayoutPageRangeResult(
            pageIndexes: [],
            error: '页码范围只能包含数字、逗号和连字符，示例：3-5,7',
          );
        }
        start = startParsed;
        end = endParsed;
      }
      if (start < 1 || end < 1 || start > pageCount || end > pageCount) {
        return SmartLayoutPageRangeResult(
          pageIndexes: [],
          error: '页码超出范围（1-$pageCount）',
        );
      }
      if (start > end) {
        return const SmartLayoutPageRangeResult(
          pageIndexes: [],
          error: '连续页面起始页不能大于结束页，如 3-5',
        );
      }
      for (var page = start; page <= end; page++) {
        if (seen.add(page)) {
          indexes.add(page - 1);
        }
      }
    }
    if (indexes.isEmpty) {
      return const SmartLayoutPageRangeResult(
        pageIndexes: [],
        error: '请输入页码范围，如 3-5,7',
      );
    }
    return SmartLayoutPageRangeResult(pageIndexes: indexes);
  }

  static int? _parseInt(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    // 只允许纯数字（负号/小数点/空白分隔都不接受）
    for (final rune in trimmed.codeUnits) {
      if (rune < 0x30 || rune > 0x39) return null;
    }
    return int.tryParse(trimmed);
  }
}
