import 'dart:math' as math;

import '../elements/elements.dart';
import '../math/math.dart';

/// An immutable collection of drawing elements with CRUD operations.
class Scene {
  final List<Element> _elements;
  final Map<String, ImageFile> files;

  Scene() : _elements = const [], files = const {};

  Scene._(List<Element> elements, [Map<String, ImageFile>? files])
    : _elements = List.unmodifiable(elements),
      files = files != null ? Map.unmodifiable(files) : const {};

  /// All elements in the scene (including soft-deleted).
  List<Element> get elements => _elements;

  /// Active (non-deleted) elements.
  List<Element> get activeElements =>
      _elements.where((e) => !e.isDeleted).toList();

  /// Elements ordered by fractional index (null index sorts last).
  List<Element> get orderedElements {
    final sorted = List<Element>.from(_elements);
    sorted.sort((a, b) {
      if (a.index == null && b.index == null) return 0;
      if (a.index == null) return 1;
      if (b.index == null) return -1;
      return a.index!.compareTo(b.index!);
    });
    return sorted;
  }

  /// Returns a new scene with the element added.
  Scene addElement(Element element) {
    return Scene._([..._elements, element], files);
  }

  /// Returns a new scene with the element removed by [id].
  Scene removeElement(ElementId id) {
    final filtered = _elements.where((e) => e.id != id).toList();
    if (filtered.length == _elements.length) return this;
    return Scene._(filtered, files);
  }

  /// Returns a new scene with the element replaced.
  /// The replacement element's version is automatically bumped.
  Scene updateElement(Element element) {
    final updated = _elements.map((e) {
      if (e.id == element.id) {
        return element.bumpVersion();
      }
      return e;
    }).toList();
    return Scene._(updated, files);
  }

  /// Finds an element by [id], or returns null.
  Element? getElementById(ElementId id) {
    for (final e in _elements) {
      if (e.id == id) return e;
    }
    return null;
  }

  /// Soft-deletes the element with the given [id].
  Scene softDeleteElement(ElementId id) {
    final updated = _elements.map((e) {
      if (e.id == id) return e.softDelete();
      return e;
    }).toList();
    return Scene._(updated, files);
  }

  /// Returns a new scene with the file added to the store.
  Scene addFile(String fileId, ImageFile file) {
    return Scene._(_elements.toList(), {...files, fileId: file});
  }

  /// Returns a new scene with the file removed from the store.
  Scene removeFile(String fileId) {
    final newFiles = Map<String, ImageFile>.of(files)..remove(fileId);
    return Scene._(_elements.toList(), newFiles);
  }

  /// Returns the bound text element whose [containerId] matches [parentId],
  /// or null if none exists.
  TextElement? findBoundText(ElementId parentId) {
    for (final e in _elements) {
      if (e.isDeleted) continue;
      if (e is TextElement && e.containerId == parentId.value) {
        return e;
      }
    }
    return null;
  }

  /// Returns the bounding box that encloses all active (non-deleted) elements,
  /// or null if there are no active elements.
  Bounds? sceneBounds() {
    Bounds? result;
    for (final e in _elements) {
      if (e.isDeleted) continue;
      final b = Bounds.fromLTWH(e.x, e.y, e.width, e.height);
      result = result == null ? b : result.union(b);
    }
    return result;
  }

  /// Returns the topmost active element whose bounding box contains [point],
  /// or null if no element is hit.
  ///
  /// Bound text elements (containerId != null) are skipped — hit the parent
  /// shape instead.
  /// Default hit tolerance for lines/arrows (in scene units).
  /// Matches Excalidraw's ~7px threshold.
  static const double _lineHitThreshold = 8.0;

  Element? getElementAtPoint(Point point) {
    final ordered = orderedElements.where((e) => !e.isDeleted).toList();
    // Iterate in reverse to find topmost (highest index) first.
    for (var i = ordered.length - 1; i >= 0; i--) {
      final e = ordered[i];
      // Skip bound text — users interact with the parent shape
      if (e is TextElement && e.containerId != null) continue;

      if (e is LineElement) {
        if (_isPointNearLine(point, e, _lineHitThreshold)) return e;
      } else {
        final bounds = Bounds.fromLTWH(e.x, e.y, e.width, e.height);
        if (bounds.containsPoint(point)) return e;
      }
    }
    return null;
  }

  /// Returns true if [point] is within [threshold] of any segment of [line].
  static bool _isPointNearLine(
    Point point,
    LineElement line,
    double threshold,
  ) {
    final pts = line.points;
    if (pts.isEmpty) return false;

    // For rotated lines, transform the test point into local space.
    var p = point;
    if (line.angle != 0.0) {
      final cx = line.x + line.width / 2;
      final cy = line.y + line.height / 2;
      final cos = math.cos(-line.angle);
      final sin = math.sin(-line.angle);
      final dx = point.x - cx;
      final dy = point.y - cy;
      p = Point(cx + dx * cos - dy * sin, cy + dx * sin + dy * cos);
    }

    // Single point — distance check.
    if (pts.length == 1) {
      final abs = Point(line.x + pts[0].x, line.y + pts[0].y);
      return p.distanceTo(abs) <= threshold;
    }

    // Check each segment.
    for (var i = 0; i < pts.length - 1; i++) {
      final a = Point(line.x + pts[i].x, line.y + pts[i].y);
      final b = Point(line.x + pts[i + 1].x, line.y + pts[i + 1].y);
      if (_distToSegment(p, a, b) <= threshold) return true;
    }
    return false;
  }

  /// Minimum distance from [p] to the line segment [a]-[b].
  static double _distToSegment(Point p, Point a, Point b) {
    final dx = b.x - a.x;
    final dy = b.y - a.y;
    final lengthSq = dx * dx + dy * dy;
    if (lengthSq == 0) return p.distanceTo(a);
    final t = ((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSq;
    final clamped = t.clamp(0.0, 1.0);
    final proj = Point(a.x + clamped * dx, a.y + clamped * dy);
    return p.distanceTo(proj);
  }
}
