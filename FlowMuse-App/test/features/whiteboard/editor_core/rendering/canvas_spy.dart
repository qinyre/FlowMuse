import 'dart:typed_data';
import 'dart:ui';

/// test-only Canvas spy：转发真实 Canvas；分开统计几何 draw* 与
/// saveLayer（v4 §7.4），并记录 drawPath 的包围盒出现顺序（z 序证据：
/// 本仓库 RoughCanvasAdapter 的矩形经 rough generator 走 drawPath 而非
/// drawRect）。成员集按本仓库 SDK（Flutter 3.41-ohos / Dart 3.11）核对；
/// 若 SDK 升级后出现新抽象成员，按编译器提示补转发。
class SpyCanvas implements Canvas {
  SpyCanvas(this._inner);
  final Canvas _inner;

  int saveLayerCount = 0;
  int drawCallCount = 0;
  final List<Rect> pathOrder = [];
  final List<Rect?> saveLayerBounds = [];

  @override
  void saveLayer(Rect? bounds, Paint paint) {
    saveLayerCount++;
    saveLayerBounds.add(bounds);
    _inner.saveLayer(bounds, paint);
  }

  @override
  void drawPath(Path path, Paint paint) {
    drawCallCount++;
    pathOrder.add(path.getBounds());
    _inner.drawPath(path, paint);
  }

  void _count() => drawCallCount++;

  @override
  void drawRect(Rect rect, Paint paint) {
    _count();
    _inner.drawRect(rect, paint);
  }

  @override
  void drawPaint(Paint paint) {
    _count();
    _inner.drawPaint(paint);
  }

  @override
  void drawLine(Offset p1, Offset p2, Paint paint) {
    _count();
    _inner.drawLine(p1, p2, paint);
  }

  @override
  void drawRRect(RRect rrect, Paint paint) {
    _count();
    _inner.drawRRect(rrect, paint);
  }

  @override
  void drawDRRect(RRect outer, RRect inner, Paint paint) {
    _count();
    _inner.drawDRRect(outer, inner, paint);
  }

  @override
  void drawOval(Rect rect, Paint paint) {
    _count();
    _inner.drawOval(rect, paint);
  }

  @override
  void drawCircle(Offset c, double radius, Paint paint) {
    _count();
    _inner.drawCircle(c, radius, paint);
  }

  @override
  void drawArc(
    Rect rect,
    double startAngle,
    double sweepAngle,
    bool useCenter,
    Paint paint,
  ) {
    _count();
    _inner.drawArc(rect, startAngle, sweepAngle, useCenter, paint);
  }

  @override
  void drawImage(Image image, Offset offset, Paint paint) {
    _count();
    _inner.drawImage(image, offset, paint);
  }

  // 本 SDK 的 drawImageRect/drawImageNine 没有 blendMode 可选参数
  @override
  void drawImageRect(Image image, Rect src, Rect dst, Paint paint) {
    _count();
    _inner.drawImageRect(image, src, dst, paint);
  }

  @override
  void drawImageNine(Image image, Rect center, Rect dst, Paint paint) {
    _count();
    _inner.drawImageNine(image, center, dst, paint);
  }

  @override
  void drawPicture(Picture picture) {
    _count();
    _inner.drawPicture(picture);
  }

  @override
  void drawParagraph(Paragraph paragraph, Offset offset) {
    _count();
    _inner.drawParagraph(paragraph, offset);
  }

  @override
  void drawPoints(PointMode pointMode, List<Offset> points, Paint paint) {
    _count();
    _inner.drawPoints(pointMode, points, paint);
  }

  @override
  void drawRawPoints(PointMode pointMode, Float32List points, Paint paint) {
    _count();
    _inner.drawRawPoints(pointMode, points, paint);
  }

  @override
  void drawVertices(Vertices vertices, BlendMode blendMode, Paint paint) {
    _count();
    _inner.drawVertices(vertices, blendMode, paint);
  }

  // 本 SDK 的 drawAtlas blendMode 为可空
  @override
  void drawAtlas(
    Image atlas,
    List<RSTransform> transforms,
    List<Rect> rects,
    List<Color>? colors,
    BlendMode? blendMode,
    Rect? cullRect,
    Paint paint,
  ) {
    _count();
    _inner.drawAtlas(
      atlas,
      transforms,
      rects,
      colors,
      blendMode,
      cullRect,
      paint,
    );
  }

  @override
  void drawRawAtlas(
    Image atlas,
    Float32List rstTransforms,
    Float32List rects,
    Int32List? colors,
    BlendMode? blendMode,
    Rect? cullRect,
    Paint paint,
  ) {
    _count();
    _inner.drawRawAtlas(
      atlas,
      rstTransforms,
      rects,
      colors,
      blendMode,
      cullRect,
      paint,
    );
  }

  @override
  void drawShadow(
    Path path,
    Color color,
    double elevation,
    bool transparentOccluder,
  ) {
    _count();
    _inner.drawShadow(path, color, elevation, transparentOccluder);
  }

  @override
  void drawColor(Color color, BlendMode blendMode) {
    _count();
    _inner.drawColor(color, blendMode);
  }

  @override
  void drawRSuperellipse(RSuperellipse rsuperellipse, Paint paint) {
    _count();
    _inner.drawRSuperellipse(rsuperellipse, paint);
  }

  @override
  void save() => _inner.save();
  @override
  void restore() => _inner.restore();
  @override
  void restoreToCount(int count) => _inner.restoreToCount(count);
  @override
  int getSaveCount() => _inner.getSaveCount();
  @override
  void translate(double dx, double dy) => _inner.translate(dx, dy);
  @override
  void scale(double sx, [double? sy]) => _inner.scale(sx, sy);
  @override
  void rotate(double radians) => _inner.rotate(radians);
  @override
  void skew(double sx, double sy) => _inner.skew(sx, sy);
  @override
  void transform(Float64List matrix4) => _inner.transform(matrix4);
  @override
  Float64List getTransform() => _inner.getTransform();
  @override
  void clipRect(
    Rect rect, {
    ClipOp clipOp = ClipOp.intersect,
    bool doAntiAlias = true,
  }) => _inner.clipRect(rect, clipOp: clipOp, doAntiAlias: doAntiAlias);
  @override
  void clipRRect(RRect rrect, {bool doAntiAlias = true}) =>
      _inner.clipRRect(rrect, doAntiAlias: doAntiAlias);
  @override
  void clipPath(Path path, {bool doAntiAlias = true}) =>
      _inner.clipPath(path, doAntiAlias: doAntiAlias);
  @override
  void clipRSuperellipse(
    RSuperellipse rsuperellipse, {
    bool doAntiAlias = true,
  }) => _inner.clipRSuperellipse(rsuperellipse, doAntiAlias: doAntiAlias);
  @override
  Rect getDestinationClipBounds() => _inner.getDestinationClipBounds();
  @override
  Rect getLocalClipBounds() => _inner.getLocalClipBounds();
}
