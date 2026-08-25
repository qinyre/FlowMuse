import 'package:flow_muse/features/whiteboard/views/smart_layout_page_ranges.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SmartLayoutPageRangeParser', () {
    test('单页 3 → 索引 [2]', () {
      final result = SmartLayoutPageRangeParser.parse('3', 10);
      expect(result.isValid, isTrue);
      expect(result.pageIndexes, [2]);
    });

    test('范围 3-5 → 索引 [2,3,4]', () {
      final result = SmartLayoutPageRangeParser.parse('3-5', 10);
      expect(result.isValid, isTrue);
      expect(result.pageIndexes, [2, 3, 4]);
    });

    test('混合 3-5,7 → 索引 [2,3,4,6]', () {
      final result = SmartLayoutPageRangeParser.parse('3-5,7', 10);
      expect(result.isValid, isTrue);
      expect(result.pageIndexes, [2, 3, 4, 6]);
    });

    test('逗号列表 3,5,7 → 索引 [2,4,6]', () {
      final result = SmartLayoutPageRangeParser.parse('3,5,7', 10);
      expect(result.isValid, isTrue);
      expect(result.pageIndexes, [2, 4, 6]);
    });

    test('重复页自动去重且保持首次顺序', () {
      final result = SmartLayoutPageRangeParser.parse('3,3-4,4', 10);
      expect(result.isValid, isTrue);
      expect(result.pageIndexes, [2, 3]);
    });

    test('允许首尾空格', () {
      final result = SmartLayoutPageRangeParser.parse(' 3 , 5 ', 10);
      expect(result.isValid, isTrue);
      expect(result.pageIndexes, [2, 4]);
    });

    test('空输入报错', () {
      final result = SmartLayoutPageRangeParser.parse('', 10);
      expect(result.isValid, isFalse);
      expect(result.errorText, contains('如 3-5,7'));
    });

    test('非数字字符报错', () {
      final result = SmartLayoutPageRangeParser.parse('a3', 10);
      expect(result.isValid, isFalse);
    });

    test('起始大于结束报错', () {
      final result = SmartLayoutPageRangeParser.parse('5-3', 10);
      expect(result.isValid, isFalse);
      expect(result.errorText, contains('起始页不能大于结束页'));
    });

    test('页码超出范围报错', () {
      final result = SmartLayoutPageRangeParser.parse('11', 10);
      expect(result.isValid, isFalse);
      expect(result.errorText, contains('1-10'));
    });

    test('连续连字符（3--5）报错', () {
      final result = SmartLayoutPageRangeParser.parse('3--5', 10);
      expect(result.isValid, isFalse);
    });

    test('零页码报错', () {
      final result = SmartLayoutPageRangeParser.parse('0', 10);
      expect(result.isValid, isFalse);
    });

    test('空段（3,）报错', () {
      final result = SmartLayoutPageRangeParser.parse('3,', 10);
      expect(result.isValid, isFalse);
    });
  });
}
