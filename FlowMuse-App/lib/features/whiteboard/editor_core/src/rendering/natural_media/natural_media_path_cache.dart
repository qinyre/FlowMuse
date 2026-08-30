import 'dart:ui' as ui;

// ---------------------------------------------------------------------------
// 自然介质 plan/Path 有界缓存（计划 T4-C，2026-08-30 同机实测触发：
// 1000 元素静态重绘 v2/v1 = 4.14 超过 1.20 门禁）。
//
// 只缓存整笔静态渲染（isComplete=true）的 Path。绕过两类调用：
// owned 分段/湿墨 owned-range（每帧几何随 owned 范围变化），以及
// isComplete=false 的整笔帧（本地湿墨逐帧追加几何——若入库，第二帧
// 命中首帧 Picture 会把活动笔迹冻结在第一帧，且每帧向 LRU 塞一次性
// Picture）。缓存键包含 element id、version、versionNonce、
// renderVersion、isComplete、strokeWidth 与
// [geometryVersion]（影响几何的 profile 曲线/常数版本，变更时 +1）。
// LRU 上限 [maxEntries]，带命中/未命中计数探针；编辑元素（version
// 或几何输入变化）产生新键，旧条目由 LRU 自然淘汰——不存在旧
// plan 回放。
// ---------------------------------------------------------------------------

class NaturalMediaPathCache {
  NaturalMediaPathCache._();

  /// 缓存条目上限（LRU）。须容纳验收口径的 1000 元素全量场景（512
  /// 会在该场景下每轮淘汰一半造成抖动）；Path 集为小对象，2048 条
  /// 有界上限的内存占用为 MB 量级。
  static const int maxEntries = 2048;

  /// 影响几何的 profile 版本：铅笔/毛笔曲线、颗粒常数、包络常数任何
  /// 变更时 +1。1：T4 冻结至盲测修复前；2：2026-08-30 盲测修复
  ///（毛笔 join 变宽梯形过渡 + 压力域扩张 brushV2PressureGain）。
  static const int geometryVersion = 2;

  static final _lru = <String, CachedNaturalMediaPaths>{};
  static int hitCount = 0;
  static int missCount = 0;

  static String keyFor({
    required String elementId,
    required int version,
    required int versionNonce,
    required int renderVersion,
    required bool isComplete,
    required double strokeWidth,
    required ui.Color strokeColor,
    required double opacity,
  }) =>
      // strokeColor/opacity 烘进缓存的 Picture（paint alpha），必须入键：
      // 同 id/version 若以不同透明度/颜色渲染（如选中态高亮），键不含
      // 它们会回放旧 alpha。strokeWidth 同理（DrawStyle 的全部绘制输入）。
      '$elementId|$version|$versionNonce|$renderVersion'
      '|${isComplete ? 1 : 0}|${strokeWidth.toStringAsFixed(4)}'
      '|${strokeColor.toARGB32()}|${opacity.toStringAsFixed(4)}'
      '|$geometryVersion';

  /// 查询（命中时提升 LRU 新鲜度）。
  static CachedNaturalMediaPaths? lookup(String key) {
    final cached = _lru[key];
    if (cached == null) {
      missCount++;
      return null;
    }
    // LinkedHashMap 重插即移到末尾（最新）。
    _lru.remove(key);
    _lru[key] = cached;
    hitCount++;
    return cached;
  }

  static void store(String key, CachedNaturalMediaPaths paths) {
    _lru[key] = paths;
    if (_lru.length > maxEntries) {
      _lru.remove(_lru.keys.first);
    }
  }

  /// 测试复位（不清计数则由调用方读后复位）。
  static void resetForTesting() {
    _lru.clear();
    hitCount = 0;
    missCount = 0;
  }

  static int get entryCount => _lru.length;
}

/// 一次整笔渲染的可复用产物。先缓存 Path 集（毫秒级构造成本的大头），
/// Path 重放（drawPath 录制）仍是多子路径的额外成本，故 miss 时同时
/// 录制恒等矩阵下的 ui.Picture，hit 直接 drawPicture 重放（v2 无
/// shader，缩放无关，重放语义与直绘一致）。Path 集保留给需要拆分
/// 消费的调用方（当前无——简化为 picture 单字段）。
class CachedNaturalMediaPaths {
  CachedNaturalMediaPaths({required ui.Picture picture}) : _picture = picture;

  final ui.Picture _picture;
  ui.Picture get picture => _picture;
}
