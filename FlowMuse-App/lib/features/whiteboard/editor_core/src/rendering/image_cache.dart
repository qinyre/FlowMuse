import 'dart:ui' as ui;

import '../core/elements/elements.dart';

/// Decodes [ImageFile] bytes to [ui.Image] and caches results by fileId.
///
/// This is a rendering-layer concern — the core stores raw bytes, and
/// this cache provides the decoded GPU-ready images for painting.
///
/// 每个 fileId 的在途状态三选一：
/// - 无：无表条目且不在 `_cache`/`_failed` 中；
/// - 占位：经 [markDecoding] 标记但尚未启动解码；
/// - 在途：解码 Future 已启动，所有等待者共享同一 Future（同一 fileId
///   永不双解，避免旧 `ui.Image` 被第二次解码覆盖而泄漏）。
class ImageElementCache {
  final int maxSize;
  final int maxBytes;
  final Map<String, ui.Image> _cache = {};

  /// fileId → 解码状态：value 为 null 表示占位（已标记未启动），
  /// 非 null 表示在途解码 Future（由 [decodeAndWait]/[getImage] 启动，
  /// 供后续等待者共享）。
  final Map<String, Future<void>?> _decoding = {};
  final Set<String> _failed = {};
  final List<String> _lruOrder = [];
  bool _disposed = false;
  int _decodedCallbackPaused = 0;
  int _sizeBytes = 0;
  Map<String, ImageFile> _visibleFiles = const {};
  bool _decodingVisible = false;

  ImageElementCache({this.maxSize = 50, this.maxBytes = 96 * 1024 * 1024});

  bool get hasPendingVisibleImages =>
      _decodingVisible ||
      _visibleFiles.keys.any(
        (id) => !_cache.containsKey(id) && !_failed.contains(id),
      );

  /// Replaces queued screen requests; only one visible image decodes at a time.
  /// Scrolling past a page drops its request before it starts decoding.
  Map<String, ui.Image>? resolveVisible(Map<String, ImageFile> files) {
    if (_disposed) return null;
    _visibleFiles = files;
    _evictIfNeeded();
    final resolved = <String, ui.Image>{};
    for (final id in files.keys) {
      final image = _cache[id];
      if (image != null) {
        _touchLru(id);
        resolved[id] = image;
      }
    }
    if (!_decodingVisible && resolved.length < files.length) _decodeVisible();
    return resolved.isEmpty ? null : resolved;
  }

  Future<void> _decodeVisible() async {
    _decodingVisible = true;
    try {
      while (!_disposed) {
        MapEntry<String, ImageFile>? next;
        for (final entry in _visibleFiles.entries) {
          if (_cache.containsKey(entry.key) || _failed.contains(entry.key)) {
            continue;
          }
          // A region export owns placeholders until it starts or releases them.
          if (_decoding.containsKey(entry.key) &&
              _decoding[entry.key] == null) {
            continue;
          }
          next = entry;
          break;
        }
        if (next == null) break;
        await decodeAndWait(next.key, next.value);
      }
    } finally {
      _decodingVisible = false;
    }
  }

  /// Returns the cached image for [fileId], or null if not yet decoded.
  ///
  /// If the image is not cached, starts an async decode. Call this each
  /// paint frame — the image will appear once decoding completes.
  ui.Image? getImage(String fileId, ImageFile file) {
    if (_disposed) return null;
    final cached = _cache[fileId];
    if (cached != null) {
      _touchLru(fileId);
      return cached;
    }

    // Start async decode if not already in progress or previously failed.
    // 占位与在途均返回 null 且不重复启动解码：占位等待其所有者
    // （decodeAndWait）串行解码；在途解码完成后经 onImageDecoded 刷新。
    if (!_decoding.containsKey(fileId) && !_failed.contains(fileId)) {
      _decoding[fileId] = _decode(fileId, file);
    }

    return null;
  }

  /// 解码单张图片并等待完成，供可见图片队列与区域导出串行预热使用。
  ///
  /// - 命中 `_cache`/`_failed`：维持早退（本会话粘性语义不变）；
  /// - 命中占位：取得所有权，启动 `_decode` 并升级为在途 Future；
  /// - 命中在途：直接 await 共享的解码 Future，不产生第二次解码。
  Future<void> decodeAndWait(String fileId, ImageFile file) async {
    if (_disposed) return;
    if (_cache.containsKey(fileId) || _failed.contains(fileId)) return;
    final inFlight = _decoding[fileId];
    if (inFlight != null) {
      await inFlight;
      return;
    }
    final future = _decode(fileId, file);
    _decoding[fileId] = future;
    await future;
  }

  /// 同步批量标记 fileId 为"解码中",阻止 getImage 并发启动 _decode。
  /// 区域导出先占位，随后用 decodeAndWait 串行解码。
  ///
  /// 仅对"无状态"fileId 插入占位：已缓存/已失败沿用既有前置条件跳过
  /// （对已缓存 id 插占位会在 LRU 逐出后让 getImage 见占位返回 null，
  /// 图片永久空白）；已在途的条目不得覆盖（等待者须共享同一 Future）。
  void markDecoding(Iterable<String> fileIds) {
    for (final id in fileIds) {
      if (_cache.containsKey(id) || _failed.contains(id)) continue;
      if (_decoding[id] != null) continue;
      _decoding[id] = null;
    }
  }

  /// 释放仍处于占位（未取得解码所有权）的标记。
  ///
  /// [markDecoding] 批量占位后若中途放弃（异常/提前退出），残留占位会让
  /// [getImage] 对该 fileId 永远返回 null，本会话图片不再渲染——调用方
  /// 必须在放弃路径上释放。已在途或已离开在途表的 fileId 不受影响。
  void releaseDecodingPlaceholders(Iterable<String> fileIds) {
    for (final id in fileIds) {
      if (_decoding[id] == null) {
        _decoding.remove(id);
      }
    }
  }

  ui.Image? peek(String fileId) => _cache[fileId];

  /// Whether [fileId] has a decoded image in the cache.
  bool contains(String fileId) => _cache.containsKey(fileId);

  /// Pre-populates the cache with an already-decoded image.
  ///
  /// Use this when the caller has already decoded the image (e.g., during
  /// import to get dimensions) to avoid a redundant async decode.
  void putImage(String fileId, ui.Image image) {
    if (_disposed) {
      image.dispose();
      return;
    }
    final previous = _cache[fileId];
    if (identical(previous, image)) return;
    if (previous != null) {
      _sizeBytes -= previous.width * previous.height * 4;
      previous.dispose();
    }
    _cache[fileId] = image;
    _sizeBytes += image.width * image.height * 4;
    _touchLru(fileId);
    _evictIfNeeded();
  }

  /// Number of decoded images currently cached.
  int get length => _cache.length;

  int get sizeBytes => _sizeBytes;

  /// Callback invoked when a new image finishes decoding.
  /// Set this to trigger a repaint (e.g., `setState`).
  ///
  /// Suppressed while any [pauseDecodedCallback] is active.
  void Function()? onImageDecoded;

  /// Temporarily suspends [onImageDecoded] invocation (nestable counter).
  ///
  /// Use this around batch prewarm loops that finish with a single repaint,
  /// avoiding per-decode repaint storms. Implemented as a counter instead of
  /// saving/restoring the callback field: overlapping pause windows must not
  /// clobber one another — with save/restore, the later starter captures the
  /// earlier starter's suspended value and can restore it over the owner's
  /// real callback, permanently silencing decode-completion repaints.
  void pauseDecodedCallback() {
    _decodedCallbackPaused++;
  }

  /// Ends one [pauseDecodedCallback]; finished decodes invoke
  /// [onImageDecoded] again once every pause has been resumed.
  void resumeDecodedCallback() {
    if (_decodedCallbackPaused > 0) {
      _decodedCallbackPaused--;
    }
  }

  void _notifyDecoded() {
    if (_decodedCallbackPaused == 0) {
      onImageDecoded?.call();
    }
  }

  Future<void> _decode(String fileId, ImageFile file) async {
    ui.Codec? codec;
    try {
      codec = await ui.instantiateImageCodec(file.bytes);
      final frame = await codec.getNextFrame();
      // 帧一旦取得编解码器即可释放：不释放会每次解码泄漏一个 Codec
      // 句柄直至 GC 兜底（最终审查跟进项）。
      codec.dispose();
      codec = null;
      final image = frame.image;

      if (_disposed) {
        // dispose() 发生在解码期间：产物无处安放，立即释放防泄漏。
        image.dispose();
        return;
      }

      putImage(fileId, image);
      _notifyDecoded();
    } catch (_) {
      if (_disposed) {
        // 与成功路径的 disposed 早退对称：缓存已弃用，不再回填状态或通知。
        return;
      }
      // 解码失败(如并发内存压力):先记 _failed 再正常 complete 共享
      // Future(不以异常 complete,保住静默失败 + peek 复核契约与
      // 多等待者语义),标记为失败避免无限重试,
      // 仍通知一次以便已成功的图片能渲染。
      _failed.add(fileId);
      _notifyDecoded();
    } finally {
      // instantiate 成功但取帧抛错时补释放；正常路径上已被置空。
      codec?.dispose();
      _decoding.remove(fileId);
    }
  }

  void _touchLru(String fileId) {
    _lruOrder.remove(fileId);
    _lruOrder.add(fileId);
  }

  void _evictIfNeeded() {
    while (_cache.length > maxSize || _sizeBytes > maxBytes) {
      final index = _lruOrder.indexWhere(
        (id) => !_visibleFiles.containsKey(id),
      );
      // ponytail: the visible working set may exceed the soft budget; keep it
      // intact to avoid flicker. Use resolution tiers if measured memory needs it.
      if (index < 0) break;
      final oldest = _lruOrder.removeAt(index);
      final image = _cache.remove(oldest);
      if (image != null) {
        _sizeBytes -= image.width * image.height * 4;
        image.dispose();
      }
    }
  }

  /// Disposes all cached images and resets state.
  void dispose() {
    _disposed = true;
    for (final image in _cache.values) {
      image.dispose();
    }
    _cache.clear();
    _visibleFiles = const {};
    _sizeBytes = 0;
    _lruOrder.clear();
    _decoding.clear();
    _failed.clear();
    _decodedCallbackPaused = 0;
  }
}
