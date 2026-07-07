import '../core/elements/elements.dart';
import '../core/math/math.dart';
import 'tool_result.dart';

/// Represents the current (possibly mixed) style values for the property panel.
///
/// A `null` value means the selected elements have mixed values for that
/// property. Text-specific properties are only populated when at least one
/// [TextElement] is selected.
class ElementStyle {
  final String? strokeColor;
  final String? backgroundColor;
  final double? strokeWidth;
  final StrokeStyle? strokeStyle;
  final FillStyle? fillStyle;
  final double? roughness;
  final double? opacity;
  final Roundness? roundness;

  /// True if any selected element has a non-null roundness.
  final bool hasRoundness;

  /// True if at least one selected element is a [TextElement],
  /// or if bound text elements are provided.
  final bool hasText;

  /// True if at least one selected element is an [ArrowElement].
  final bool hasArrows;

  /// True when selection includes shapes with bound text.
  final bool hasShapeBoundText;

  /// True when selection includes arrows with bound text.
  final bool hasArrowBoundText;

  // Text-only properties (null if no text elements or mixed):
  final double? fontSize;
  final String? fontFamily;
  final TextAlign? textAlign;
  final VerticalAlign? verticalAlign;

  // Arrow-only properties (null if no arrows or mixed):
  final ArrowType? arrowType;

  /// True if at least one selected element is a [LineElement] (including arrows).
  final bool hasLines;

  // Arrowhead properties (null = mixed across selected lines):
  final Arrowhead? startArrowhead;

  /// True when all selected lines have null startArrowhead.
  final bool startArrowheadNone;

  final Arrowhead? endArrowhead;

  /// True when all selected lines have null endArrowhead.
  final bool endArrowheadNone;

  /// True when all selected elements are closed-polygon LineElements (not arrows)
  /// with 3+ points.
  final bool canBreakPolygon;

  // Lock state (null if mixed):
  final bool? locked;

  const ElementStyle({
    this.strokeColor,
    this.backgroundColor,
    this.strokeWidth,
    this.strokeStyle,
    this.fillStyle,
    this.roughness,
    this.opacity,
    this.roundness,
    this.hasRoundness = false,
    this.hasText = false,
    this.hasArrows = false,
    this.hasShapeBoundText = false,
    this.hasArrowBoundText = false,
    this.hasLines = false,
    this.startArrowhead,
    this.startArrowheadNone = false,
    this.endArrowhead,
    this.endArrowheadNone = false,
    this.fontSize,
    this.fontFamily,
    this.textAlign,
    this.verticalAlign,
    this.arrowType,
    this.canBreakPolygon = false,
    this.locked,
  });

  ElementStyle copyWith({String? strokeColor, bool clearStrokeColor = false}) {
    return ElementStyle(
      strokeColor: clearStrokeColor ? null : (strokeColor ?? this.strokeColor),
      backgroundColor: backgroundColor,
      strokeWidth: strokeWidth,
      strokeStyle: strokeStyle,
      fillStyle: fillStyle,
      roughness: roughness,
      opacity: opacity,
      roundness: roundness,
      hasRoundness: hasRoundness,
      hasText: hasText,
      hasArrows: hasArrows,
      hasShapeBoundText: hasShapeBoundText,
      hasArrowBoundText: hasArrowBoundText,
      hasLines: hasLines,
      startArrowhead: startArrowhead,
      startArrowheadNone: startArrowheadNone,
      endArrowhead: endArrowhead,
      endArrowheadNone: endArrowheadNone,
      fontSize: fontSize,
      fontFamily: fontFamily,
      textAlign: textAlign,
      verticalAlign: verticalAlign,
      arrowType: arrowType,
      canBreakPolygon: canBreakPolygon,
      locked: locked,
    );
  }
}

/// Pure-logic class that reads selected elements and produces style state
/// and [ToolResult]s. No Flutter widgets — keeps it testable.
class PropertyPanelState {
  /// Extract the common style properties from a set of elements.
  ///
  /// Returns `null` for a property if elements have mixed values.
  /// Returns an all-null [ElementStyle] if [elements] is empty.
  static ElementStyle fromElements(
    List<Element> elements, {
    List<TextElement> boundTextElements = const [],
  }) {
    if (elements.isEmpty) {
      return const ElementStyle();
    }

    final first = elements.first;

    // Base properties — check if all elements share the same value.
    String? strokeColor = first.strokeColor;
    String? backgroundColor = first.backgroundColor;
    double? strokeWidth = first.strokeWidth;
    StrokeStyle? strokeStyle = first.strokeStyle;
    FillStyle? fillStyle = first.fillStyle;
    double? roughness = first.roughness;
    double? opacity = first.opacity;

    bool hasRoundness =
        first is RectangleElement ||
        first is DiamondElement ||
        (first is LineElement && first is! ArrowElement);
    Roundness? roundness = first.roundness;
    bool roundnessMixed = false;

    for (var i = 1; i < elements.length; i++) {
      final e = elements[i];
      if (strokeColor != null && e.strokeColor != strokeColor) {
        strokeColor = null;
      }
      if (backgroundColor != null && e.backgroundColor != backgroundColor) {
        backgroundColor = null;
      }
      if (strokeWidth != null && e.strokeWidth != strokeWidth) {
        strokeWidth = null;
      }
      if (strokeStyle != null && e.strokeStyle != strokeStyle) {
        strokeStyle = null;
      }
      if (fillStyle != null && e.fillStyle != fillStyle) {
        fillStyle = null;
      }
      if (roughness != null && e.roughness != roughness) {
        roughness = null;
      }
      if (opacity != null && e.opacity != opacity) {
        opacity = null;
      }
      if (e is RectangleElement ||
          e is DiamondElement ||
          (e is LineElement && e is! ArrowElement)) {
        hasRoundness = true;
      }
      if (!roundnessMixed && e.roundness != roundness) {
        roundness = null;
        roundnessMixed = true;
      }
    }

    // Arrow properties — only if at least one ArrowElement is present.
    final arrowElements = elements.whereType<ArrowElement>().toList();
    final hasArrows = arrowElements.isNotEmpty;
    ArrowType? arrowType;
    if (hasArrows) {
      arrowType = arrowElements.first.arrowType;
      for (var i = 1; i < arrowElements.length; i++) {
        if (arrowElements[i].arrowType != arrowType) {
          arrowType = null;
          break;
        }
      }
    }

    // Line/arrow arrowhead properties
    final lineElements = elements.whereType<LineElement>().toList();
    final hasLines = lineElements.isNotEmpty;
    Arrowhead? startArrowhead;
    bool startArrowheadNone = false;
    Arrowhead? endArrowhead;
    bool endArrowheadNone = false;
    if (hasLines) {
      final firstLine = lineElements.first;
      startArrowhead = firstLine.startArrowhead;
      startArrowheadNone = startArrowhead == null;
      endArrowhead = firstLine.endArrowhead;
      endArrowheadNone = endArrowhead == null;
      for (var i = 1; i < lineElements.length; i++) {
        final l = lineElements[i];
        if (startArrowhead != l.startArrowhead) {
          startArrowhead = null;
          startArrowheadNone = false;
        }
        if (endArrowhead != l.endArrowhead) {
          endArrowhead = null;
          endArrowheadNone = false;
        }
      }
    }

    // Text properties — from directly selected TextElements and bound text.
    final directTextElements = elements.whereType<TextElement>().toList();

    // Classify bound text by container type
    final shapeBoundText = <TextElement>[];
    final arrowBoundText = <TextElement>[];
    for (final bt in boundTextElements) {
      if (bt.containerId == null) continue;
      final container = elements.where((e) => e.id.value == bt.containerId);
      if (container.isEmpty) continue;
      if (container.first is ArrowElement) {
        arrowBoundText.add(bt);
      } else {
        shapeBoundText.add(bt);
      }
    }

    final hasShapeBoundText = shapeBoundText.isNotEmpty;
    final hasArrowBoundText = arrowBoundText.isNotEmpty;

    // All text elements contributing font size (direct + all bound)
    final allTextForFontSize = <TextElement>[
      ...directTextElements,
      ...shapeBoundText,
      ...arrowBoundText,
    ];
    // Text elements contributing full text props (direct + shape-bound)
    final allTextForFullProps = <TextElement>[
      ...directTextElements,
      ...shapeBoundText,
    ];

    final hasText = allTextForFontSize.isNotEmpty;

    double? fontSize;
    String? fontFamily;
    TextAlign? textAlign;
    VerticalAlign? verticalAlign;

    if (hasText) {
      // fontSize: merge from all (direct + shape-bound + arrow-bound)
      fontSize = allTextForFontSize.first.fontSize;
      for (var i = 1; i < allTextForFontSize.length; i++) {
        if (fontSize != null && allTextForFontSize[i].fontSize != fontSize) {
          fontSize = null;
        }
      }

      // fontFamily, textAlign, verticalAlign: merge from direct + shape-bound only
      if (allTextForFullProps.isNotEmpty) {
        fontFamily = allTextForFullProps.first.fontFamily;
        textAlign = allTextForFullProps.first.textAlign;
        verticalAlign = allTextForFullProps.first.verticalAlign;

        for (var i = 1; i < allTextForFullProps.length; i++) {
          final t = allTextForFullProps[i];
          if (fontFamily != null && t.fontFamily != fontFamily) {
            fontFamily = null;
          }
          if (textAlign != null && t.textAlign != textAlign) {
            textAlign = null;
          }
          if (verticalAlign != null && t.verticalAlign != verticalAlign) {
            verticalAlign = null;
          }
        }
      }
    }

    // Break polygon: true when all selected are non-arrow closed LineElements
    // with 3+ points.
    final pureLines = elements
        .whereType<LineElement>()
        .where((l) => l is! ArrowElement)
        .toList();
    final canBreakPolygon =
        pureLines.isNotEmpty &&
        pureLines.length == elements.length &&
        pureLines.every((l) => l.closed && l.points.length >= 3);

    // Locked property
    bool? locked = first.locked;
    for (var i = 1; i < elements.length; i++) {
      if (locked != null && elements[i].locked != locked) {
        locked = null;
        break;
      }
    }

    return ElementStyle(
      strokeColor: strokeColor,
      backgroundColor: backgroundColor,
      strokeWidth: strokeWidth,
      strokeStyle: strokeStyle,
      fillStyle: fillStyle,
      roughness: roughness,
      opacity: opacity,
      roundness: roundness,
      hasRoundness: hasRoundness,
      hasText: hasText,
      hasArrows: hasArrows,
      hasShapeBoundText: hasShapeBoundText,
      hasArrowBoundText: hasArrowBoundText,
      hasLines: hasLines,
      startArrowhead: startArrowhead,
      startArrowheadNone: startArrowheadNone,
      endArrowhead: endArrowhead,
      endArrowheadNone: endArrowheadNone,
      fontSize: fontSize,
      fontFamily: fontFamily,
      textAlign: textAlign,
      verticalAlign: verticalAlign,
      arrowType: arrowType,
      canBreakPolygon: canBreakPolygon,
      locked: locked,
    );
  }

  /// Build [ToolResult]s that apply [style] to each element.
  ///
  /// Only non-null properties in [style] are applied. Returns a single
  /// [UpdateElementResult] for one element, or a [CompoundResult] for
  /// multiple elements.
  static ToolResult applyStyle(List<Element> elements, ElementStyle style) {
    final results = <ToolResult>[];

    for (final element in elements) {
      Element updated = element;

      // Apply text-specific properties first if applicable
      if (element is TextElement) {
        if (style.fontSize != null ||
            style.fontFamily != null ||
            style.textAlign != null ||
            style.verticalAlign != null) {
          updated = (updated as TextElement).copyWithText(
            fontSize: style.fontSize,
            fontFamily: style.fontFamily,
            textAlign: style.textAlign,
            verticalAlign: style.verticalAlign,
          );
        }
      }

      // Apply arrow-specific arrowType change
      if (element is ArrowElement && style.arrowType != null) {
        final arrow = element;
        final newType = style.arrowType!;
        final oldType = arrow.arrowType;

        if (newType.isElbow && !oldType.isElbow) {
          // Non-elbow → elbow: route points between first and last point
          final absFirst = Point(
            arrow.x + arrow.points.first.x,
            arrow.y + arrow.points.first.y,
          );
          final absLast = Point(
            arrow.x + arrow.points.last.x,
            arrow.y + arrow.points.last.y,
          );
          final routed = ElbowRouting.route(start: absFirst, end: absLast);
          // Compute proper bounding box from absolute routed points
          var minX = routed.first.x;
          var minY = routed.first.y;
          var maxX = routed.first.x;
          var maxY = routed.first.y;
          for (final p in routed) {
            if (p.x < minX) minX = p.x;
            if (p.y < minY) minY = p.y;
            if (p.x > maxX) maxX = p.x;
            if (p.y > maxY) maxY = p.y;
          }
          final relPoints = routed
              .map((p) => Point(p.x - minX, p.y - minY))
              .toList();
          updated = arrow
              .copyWithArrow(arrowType: newType)
              .copyWithLine(points: relPoints)
              .copyWith(
                x: minX,
                y: minY,
                width: maxX - minX,
                height: maxY - minY,
                angle: 0,
              );
        } else if (!newType.isElbow && oldType.isElbow) {
          // Elbow → non-elbow: simplify to just first and last point
          final simplifiedPoints = [arrow.points.first, arrow.points.last];
          updated = arrow
              .copyWithArrow(arrowType: newType)
              .copyWithLine(points: simplifiedPoints);
        } else {
          // Same category (sharp↔round or sharpElbow↔roundElbow): no point changes
          updated = arrow.copyWithArrow(arrowType: newType);
        }
      }

      // Break polygon: open the line and set background transparent.
      // Keep all points as-is so the last segment remains visible.
      if (style.canBreakPolygon &&
          element is LineElement &&
          element is! ArrowElement) {
        updated = (updated as LineElement)
            .copyWithLine(closed: false)
            .copyWith(backgroundColor: 'transparent');
      }

      // Apply arrowhead changes for line elements
      if (element is LineElement &&
          (style.startArrowhead != null ||
              style.startArrowheadNone ||
              style.endArrowhead != null ||
              style.endArrowheadNone)) {
        updated = (updated as LineElement).copyWithLine(
          startArrowhead: style.startArrowhead,
          clearStartArrowhead: style.startArrowheadNone,
          endArrowhead: style.endArrowhead,
          clearEndArrowhead: style.endArrowheadNone,
        );
      }

      // Apply base properties
      updated = updated.copyWith(
        strokeColor: style.strokeColor,
        backgroundColor: style.backgroundColor,
        strokeWidth: style.strokeWidth,
        strokeStyle: style.strokeStyle,
        fillStyle: style.fillStyle,
        roughness: style.roughness,
        opacity: style.opacity,
        roundness: style.roundness,
        clearRoundness: style.roundness == null && style.hasRoundness,
        locked: style.locked,
      );

      results.add(UpdateElementResult(updated));
    }

    if (results.length == 1) return results.first;
    return CompoundResult(results);
  }
}
