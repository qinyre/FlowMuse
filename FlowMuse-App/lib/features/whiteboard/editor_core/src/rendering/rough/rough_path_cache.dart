import 'package:rough_flutter/rough_flutter.dart';

/// LRU cache for rough_flutter [Drawable]s, keyed by element identity.
///
/// Avoids re-computing expensive rough shapes when an element hasn't changed.
/// Follows the same LRU pattern as [ImageElementCache].
class RoughPathCache {
  final int maxSize;

  // Key format: "elementId:hashCode"
  final Map<String, Drawable> _cache = {};
  final List<String> _lruOrder = [];

  RoughPathCache({this.maxSize = 200});

  /// Returns the cached [Drawable] for the given element, or null on miss.
  Drawable? get(String elementId, int elementHash) {
    final key = '$elementId:$elementHash';
    final drawable = _cache[key];
    if (drawable != null) {
      _touchLru(key);
    }
    return drawable;
  }

  /// Stores a [Drawable] for the given element.
  void put(String elementId, int elementHash, Drawable drawable) {
    final key = '$elementId:$elementHash';
    // Remove old entry for same elementId (different hash)
    _cache.keys
        .where((k) => k.startsWith('$elementId:') && k != key)
        .toList()
        .forEach((old) {
          _cache.remove(old);
          _lruOrder.remove(old);
        });
    _cache[key] = drawable;
    _lruOrder.add(key);
    _evictIfNeeded();
  }

  /// Number of cached drawables.
  int get length => _cache.length;

  /// Clears all cached entries.
  void clear() {
    _cache.clear();
    _lruOrder.clear();
  }

  void _touchLru(String key) {
    _lruOrder.remove(key);
    _lruOrder.add(key);
  }

  void _evictIfNeeded() {
    while (_cache.length > maxSize && _lruOrder.isNotEmpty) {
      final oldest = _lruOrder.removeAt(0);
      _cache.remove(oldest);
    }
  }
}
