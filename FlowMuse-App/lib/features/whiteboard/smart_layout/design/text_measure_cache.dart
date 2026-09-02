import 'text_measure_result.dart';

/// 有界 LRU 文本测量缓存（任务 V3-300A）。
///
/// 键由 [TextMeasureAdapter] 构造（字体族前缀 + 全参数规范串）。
/// 语义：命中重排（LRU）、超容量逐出最久未用、`clear` 全量失效、
/// `invalidateFamily` 按字体族失效（字体异步加载完成后旧回退度量必须
/// 作废）。命中率/容量可观测，供测试与上限验证。
final class TextMeasureCache {
  /// 最大缓存条目数；超过后逐出最久未使用条目。
  final int capacity;

  final _entries = <String, TextMeasureResult>{};

  int _hits = 0;
  int _misses = 0;

  TextMeasureCache({this.capacity = 256}) : assert(capacity > 0, 'capacity 必须为正');

  /// 当前条目数。
  int get length => _entries.length;

  /// 命中次数（自实例创建起）。
  int get hits => _hits;

  /// 未命中次数（自实例创建起）。
  int get misses => _misses;

  /// 查询缓存；命中则刷新 LRU 位并计数。
  TextMeasureResult? lookup(String key) {
    final value = _entries.remove(key);
    if (value == null) {
      _misses++;
      return null;
    }
    _entries[key] = value;
    _hits++;
    return value;
  }

  /// 写入条目；容量满时先逐出最久未用条目（插入序即 LRU 序）。
  void store(String key, TextMeasureResult value) {
    _entries.remove(key);
    while (_entries.length >= capacity) {
      _entries.remove(_entries.keys.first);
    }
    _entries[key] = value;
  }

  /// 全量失效。
  void clear() => _entries.clear();

  /// 按字体族前缀失效：清除所有以 `family␟` 开头的键。
  /// 返回清除条数。
  int invalidateFamily(String fontFamily) {
    final prefix = '$fontFamily\u241f';
    final doomed = _entries.keys.where((k) => k.startsWith(prefix)).toList();
    for (final key in doomed) {
      _entries.remove(key);
    }
    return doomed.length;
  }
}
