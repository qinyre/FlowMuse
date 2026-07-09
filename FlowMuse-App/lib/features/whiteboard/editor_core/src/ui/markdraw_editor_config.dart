library;

import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart'
    show CanvasLayout, CanvasLayoutType, ElementStyle, ToolType;

import 'color_utils.dart' as color_utils;

/// Immutable configuration for [MarkdrawEditor] appearance and behavior.
class MarkdrawEditorConfig {
  const MarkdrawEditorConfig({
    this.tools,
    this.initialBackground = '#ffffff',
    this.initialLayout = const CanvasLayout(type: CanvasLayoutType.unbounded),
    this.initialStyle = const ElementStyle(),
    this.showToolbar = true,
    this.showPropertyPanel = true,
    this.showZoomControls = true,
    this.showHelpButton = true,
    this.showLibraryPanel = true,
    this.showMarkdownButton = true,
    this.showMenu = true,
    this.compactBreakpoint = 600.0,
    this.minZoom = 0.1,
    this.maxZoom = 30.0,
    this.zoomStep = 0.1,
    this.canvasBackgroundPresets = color_utils.canvasBackgroundPresets,
    this.strokeColorPresets = color_utils.strokeQuickPicks,
    this.backgroundColorPresets = color_utils.backgroundQuickPicks,
    this.onLinkOpen,
  });

  /// Which tools to show in the toolbar. Defaults to all tools if null.
  final List<ToolType>? tools;

  /// Initial canvas background color (hex string).
  final String initialBackground;

  /// Initial canvas layout mode and page template.
  final CanvasLayout initialLayout;

  /// Initial default style for new elements.
  final ElementStyle initialStyle;

  /// Whether to show the toolbar.
  final bool showToolbar;

  /// Whether to show the property panel.
  final bool showPropertyPanel;

  /// Whether to show the zoom controls.
  final bool showZoomControls;

  /// Whether to show the help button.
  final bool showHelpButton;

  /// Whether to show the library panel.
  final bool showLibraryPanel;

  /// Whether to show the markdown split-pane toggle button in the toolbar.
  final bool showMarkdownButton;

  /// Whether to show the menu.
  final bool showMenu;

  /// Width breakpoint for compact (mobile) layout.
  final double compactBreakpoint;

  /// Minimum zoom level.
  final double minZoom;

  /// Maximum zoom level.
  final double maxZoom;

  /// Zoom step for zoom in/out buttons.
  final double zoomStep;

  /// Canvas background color presets.
  final List<String> canvasBackgroundPresets;

  /// Stroke color presets for the property panel.
  final List<String> strokeColorPresets;

  /// Background color presets for the property panel.
  final List<String> backgroundColorPresets;

  /// Called when the user follows an external link (not an element link).
  /// Wire this to url_launcher in the example app.
  final void Function(String url)? onLinkOpen;
}
