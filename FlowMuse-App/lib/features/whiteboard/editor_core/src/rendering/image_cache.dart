import 'dart:ui' as ui;

import '../core/elements/elements.dart';

/// Decodes [ImageFile] bytes to [ui.Image] and caches results by fileId.
///
/// This is a rendering-layer concern — the core stores raw bytes, and
/// this cache provides the decoded GPU-ready images for painting.
class ImageElementCache {
  final int maxSize;
  final Map<String, ui.Image> _cache = {};
  final Set<String> _decoding = {};
  final Set<String> _failed = {};
  final List<String> _lruOrder = [];

  ImageElementCache({this.maxSize = 50});

  /// Returns the cached image for [fileId], or null if not yet decoded.
  ///
  /// If the image is not cached, starts an async decode. Call this each
  /// paint frame — the image will appear once decoding completes.
  ui.Image? getImage(String fileId, ImageFile file) {
    final cached = _cache[fileId];
    if (cached != null) {
      _touchLru(fileId);
      return cached;
    }

    // Start async decode if not already in progress or previously failed
    if (!_decoding.contains(fileId) && !_failed.contains(fileId)) {
      _decoding.add(fileId);
      _decode(fileId, file);
    }

    return null;
  }

  /// 串行解码单张图片并等待完成。供 loadScene 预热缓存使用,
  /// 避免 resolveImages 并发触发多张图片同时解码。
  Future<void> decodeAndWait(String fileId, ImageFile file) async {
    if (_cache.containsKey(fileId) || _failed.contains(fileId)) return;
    await _decode(fileId, file);
  }

  ui.Image? peek(String fileId) => _cache[fileId];

  /// Whether [fileId] has a decoded image in the cache.
  bool contains(String fileId) => _cache.containsKey(fileId);

  /// Pre-populates the cache with an already-decoded image.
  ///
  /// Use this when the caller has already decoded the image (e.g., during
  /// import to get dimensions) to avoid a redundant async decode.
  void putImage(String fileId, ui.Image image) {
    _cache[fileId] = image;
    _lruOrder.add(fileId);
    _evictIfNeeded();
  }

  /// Number of decoded images currently cached.
  int get length => _cache.length;

  /// Callback invoked when a new image finishes decoding.
  /// Set this to trigger a repaint (e.g., `setState`).
  void Function()? onImageDecoded;

  Future<void> _decode(String fileId, ImageFile file) async {
    try {
      final codec = await ui.instantiateImageCodec(file.bytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;

      _cache[fileId] = image;
      _lruOrder.add(fileId);
      _evictIfNeeded();
      onImageDecoded?.call();
    } catch (_) {
      // 解码失败(如并发内存压力):标记为失败避免无限重试,
      // 仍通知一次以便已成功的图片能渲染。
      _failed.add(fileId);
      onImageDecoded?.call();
    } finally {
      _decoding.remove(fileId);
    }
  }

  void _touchLru(String fileId) {
    _lruOrder.remove(fileId);
    _lruOrder.add(fileId);
  }

  void _evictIfNeeded() {
    while (_cache.length > maxSize && _lruOrder.isNotEmpty) {
      final oldest = _lruOrder.removeAt(0);
      final image = _cache.remove(oldest);
      image?.dispose();
    }
  }

  /// Disposes all cached images and resets state.
  void dispose() {
    for (final image in _cache.values) {
      image.dispose();
    }
    _cache.clear();
    _lruOrder.clear();
    _decoding.clear();
    _failed.clear();
  }
}
