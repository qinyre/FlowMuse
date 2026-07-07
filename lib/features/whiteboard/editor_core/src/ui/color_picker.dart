library;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'color_utils.dart';
import 'style_icon_painters.dart';

/// A small square color swatch.
class ColorSwatch extends StatelessWidget {
  final String color;
  final bool isSelected;
  final VoidCallback onTap;

  const ColorSwatch({
    super.key,
    required this.color,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final parsed = parseColor(color);
    final isTransparent = color == 'transparent';
    final isLight = !isTransparent && (parsed.r + parsed.g + parsed.b) > 1.8;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: isTransparent ? cs.surface : parsed,
          border: Border.all(
            color: isSelected
                ? cs.primary
                : (isLight || isTransparent)
                ? cs.outlineVariant
                : Colors.transparent,
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(4),
        ),
        child: isTransparent
            ? CustomPaint(painter: DiagonalLinePainter())
            : null,
      ),
    );
  }
}

/// The 6th swatch that shows the active color and opens a full palette popup.
class ColorPickerButton extends StatefulWidget {
  final String color;
  final bool isActive;
  final ValueChanged<String> onColorSelected;

  /// Callback for eyedropper pixel sampling; null hides the eyedropper button.
  final Future<ui.Image?> Function(Size canvasSize)? onRenderScene;

  /// Callback to sample a color from a pre-rendered image.
  final Future<String?> Function(ui.Image image, Offset position)?
  onSampleColor;

  /// Canvas size for eyedropper rendering.
  final Size? canvasSize;

  /// When true, the palette popup opens automatically on build.
  final bool autoOpen;

  /// Called when the auto-opened popup is shown (to clear the trigger flag).
  final VoidCallback? onAutoOpened;

  const ColorPickerButton({
    super.key,
    required this.color,
    required this.isActive,
    required this.onColorSelected,
    this.onRenderScene,
    this.onSampleColor,
    this.canvasSize,
    this.autoOpen = false,
    this.onAutoOpened,
  });

  static const paletteColors = [
    ['#f8f9fa', '#e9ecef', '#ced4da', '#868e96', '#343a40'],
    ['#fff5f5', '#ffc9c9', '#ff8787', '#fa5252', '#e03131'],
    ['#fff0f6', '#fcc2d7', '#f783ac', '#e64980', '#c2255c'],
    ['#f8f0fc', '#eebefa', '#da77f2', '#be4bdb', '#9c36b5'],
    ['#f3f0ff', '#d0bfff', '#9775fa', '#7950f2', '#6741d9'],
    ['#e7f5ff', '#a5d8ff', '#4dabf7', '#228be6', '#1971c2'],
    ['#e3fafc', '#99e9f2', '#3bc9db', '#15aabf', '#0c8599'],
    ['#e6fcf5', '#96f2d7', '#38d9a9', '#12b886', '#099268'],
    ['#ebfbee', '#b2f2bb', '#69db7c', '#40c057', '#2f9e44'],
    ['#fff9db', '#ffec99', '#ffd43b', '#fab005', '#f08c00'],
    ['#fff4e6', '#ffd8a8', '#ffa94d', '#fd7e14', '#e8590c'],
    ['#f8f1ee', '#eaddd7', '#d2bab0', '#a18072', '#846358'],
  ];

  @override
  State<ColorPickerButton> createState() => _ColorPickerButtonState();
}

class _ColorPickerButtonState extends State<ColorPickerButton> {
  OverlayEntry? _overlayEntry;

  @override
  void initState() {
    super.initState();
    if (widget.autoOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showPalettePopup();
      });
    }
  }

  @override
  void didUpdateWidget(ColorPickerButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.autoOpen && !oldWidget.autoOpen && _overlayEntry == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showPalettePopup();
      });
    }
  }

  @override
  void dispose() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final parsed = parseColor(widget.color);
    final isTransparent = widget.color == 'transparent';
    final isLight = !isTransparent && (parsed.r + parsed.g + parsed.b) > 1.8;
    return InkWell(
      onTap: _showPalettePopup,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: isTransparent ? cs.surface : parsed,
          border: Border.all(
            color: widget.isActive
                ? cs.primary
                : (isLight || isTransparent)
                ? cs.outlineVariant
                : cs.outlineVariant,
            width: widget.isActive ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(4),
        ),
        child: isTransparent
            ? CustomPaint(painter: DiagonalLinePainter())
            : null,
      ),
    );
  }

  void _showPalettePopup() {
    if (_overlayEntry != null) return;
    final renderBox = context.findRenderObject() as RenderBox;
    final offset = renderBox.localToGlobal(Offset.zero);
    final overlay = Overlay.of(context);

    _overlayEntry = OverlayEntry(
      builder: (ctx) => ColorPaletteOverlay(
        anchor: offset,
        currentColor: widget.color,
        onSelect: (c) {
          _removeOverlay();
          widget.onColorSelected(c);
        },
        onDismiss: _removeOverlay,
        onRenderScene: widget.onRenderScene,
        onSampleColor: widget.onSampleColor,
        canvasSize: widget.canvasSize,
      ),
    );
    overlay.insert(_overlayEntry!);
    widget.onAutoOpened?.call();
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }
}

/// Full-palette popup overlay with grid + transparent + hex input.
class ColorPaletteOverlay extends StatefulWidget {
  final Offset anchor;
  final String currentColor;
  final ValueChanged<String> onSelect;
  final VoidCallback onDismiss;

  /// Callback to render scene to an image for eyedropper; null hides button.
  final Future<ui.Image?> Function(Size canvasSize)? onRenderScene;

  /// Callback to sample a color from a pre-rendered image.
  final Future<String?> Function(ui.Image image, Offset position)?
  onSampleColor;

  /// Canvas size for eyedropper rendering.
  final Size? canvasSize;

  const ColorPaletteOverlay({
    super.key,
    required this.anchor,
    required this.currentColor,
    required this.onSelect,
    required this.onDismiss,
    this.onRenderScene,
    this.onSampleColor,
    this.canvasSize,
  });

  @override
  State<ColorPaletteOverlay> createState() => _ColorPaletteOverlayState();
}

class _ColorPaletteOverlayState extends State<ColorPaletteOverlay> {
  late final TextEditingController _hexController;

  // Eyedropper mode state
  bool _eyedropperActive = false;
  Offset? _cursorPosition;
  String? _previewColor;
  ui.Image? _cachedImage;

  @override
  void initState() {
    super.initState();
    _hexController = TextEditingController(
      text: widget.currentColor == 'transparent' ? '' : widget.currentColor,
    );
    HardwareKeyboard.instance.addHandler(_onHardwareKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onHardwareKey);
    _hexController.dispose();
    _cachedImage?.dispose();
    super.dispose();
  }

  bool get _hasEyedropper =>
      widget.onRenderScene != null &&
      widget.onSampleColor != null &&
      widget.canvasSize != null;

  Future<void> _activateEyedropper() async {
    if (!_hasEyedropper) return;
    final image = await widget.onRenderScene!(widget.canvasSize!);
    if (image == null || !mounted) return;
    setState(() {
      _cachedImage = image;
      _eyedropperActive = true;
      _previewColor = null;
      _cursorPosition = null;
    });
  }

  void _deactivateEyedropper() {
    _cachedImage?.dispose();
    setState(() {
      _cachedImage = null;
      _eyedropperActive = false;
      _previewColor = null;
      _cursorPosition = null;
    });
  }

  Future<void> _onPointerMove(Offset position) async {
    if (!_eyedropperActive || _cachedImage == null) return;
    setState(() => _cursorPosition = position);

    final color = await widget.onSampleColor!(_cachedImage!, position);
    if (!mounted || !_eyedropperActive) return;
    setState(() {
      _previewColor = color;
      if (color != null) {
        _hexController.text = color;
      }
    });
  }

  void _onPointerUp(Offset position) {
    if (!_eyedropperActive) return;
    final color = _previewColor;
    if (color != null) {
      _deactivateEyedropper();
      widget.onSelect(color);
    }
  }

  bool _onHardwareKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;

    if (event.logicalKey == LogicalKeyboardKey.escape) {
      if (_eyedropperActive) {
        _deactivateEyedropper();
        return true;
      }
    }

    if (event.logicalKey == LogicalKeyboardKey.keyI) {
      if (_hasEyedropper) {
        if (_eyedropperActive) {
          _deactivateEyedropper();
        } else {
          _activateEyedropper();
        }
        return true;
      }
    }

    return false;
  }

  @override
  Widget build(BuildContext context) {
    const swatchSize = 24.0;
    const spacing = 3.0;
    const cols = 5;
    const rows = 12;
    const popupWidth = cols * (swatchSize + spacing) + spacing + 24;
    const popupHeight = (rows + 1) * (swatchSize + spacing) + spacing + 60;

    final screen = MediaQuery.of(context).size;
    var left = widget.anchor.dx - popupWidth / 2 + 14;
    var top = widget.anchor.dy + 34;
    if (left + popupWidth > screen.width - 8) {
      left = screen.width - popupWidth - 8;
    }
    if (left < 8) left = 8;
    if (top + popupHeight > screen.height - 8) {
      top = widget.anchor.dy - popupHeight - 4;
    }

    return Stack(
      children: [
        // Dismiss backdrop / eyedropper capture layer
        if (_eyedropperActive)
          Positioned.fill(
            child: MouseRegion(
              cursor: SystemMouseCursors.precise,
              onHover: (e) => _onPointerMove(e.position),
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerMove: (e) => _onPointerMove(e.position),
                onPointerDown: (e) => _onPointerMove(e.position),
                onPointerUp: (e) => _onPointerUp(e.position),
                child: const SizedBox.expand(),
              ),
            ),
          )
        else
          Positioned.fill(
            child: GestureDetector(
              onTap: widget.onDismiss,
              behavior: HitTestBehavior.opaque,
              child: const SizedBox.expand(),
            ),
          ),

        // Palette popup
        Positioned(
          left: left,
          top: top,
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: popupWidth,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  InkWell(
                    onTap: () => widget.onSelect('transparent'),
                    borderRadius: BorderRadius.circular(4),
                    child: Container(
                      width: swatchSize,
                      height: swatchSize,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        border: Border.all(
                          color: widget.currentColor == 'transparent'
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.outlineVariant,
                          width: widget.currentColor == 'transparent' ? 2 : 1,
                        ),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: CustomPaint(painter: DiagonalLinePainter()),
                    ),
                  ),
                  const SizedBox(height: 4),
                  for (final row in ColorPickerButton.paletteColors)
                    Padding(
                      padding: const EdgeInsets.only(bottom: spacing),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final hex in row)
                            Padding(
                              padding: const EdgeInsets.only(right: spacing),
                              child: _buildGridSwatch(hex, swatchSize),
                            ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 4),
                  _buildHexInputRow(),
                ],
              ),
            ),
          ),
        ),

        // Eyedropper color preview swatch following cursor
        if (_eyedropperActive &&
            _cursorPosition != null &&
            _previewColor != null)
          Positioned(
            left: _cursorPosition!.dx + 20,
            top: _cursorPosition!.dy + 20,
            child: IgnorePointer(
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: parseColor(_previewColor!),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x40000000),
                      blurRadius: 8,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildHexInputRow() {
    return SizedBox(
      height: 32,
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _hexController,
              decoration: InputDecoration(
                labelText: 'Hex color',
                hintText: '#rrggbb',
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 6,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              style: const TextStyle(fontSize: 13),
              onSubmitted: (value) {
                final hex = value.trim();
                if (_isValidHex(hex)) {
                  widget.onSelect(hex);
                }
              },
            ),
          ),
          if (_hasEyedropper) ...[
            const SizedBox(width: 4),
            _buildEyedropperButton(),
          ],
        ],
      ),
    );
  }

  Widget _buildEyedropperButton() {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () {
        if (_eyedropperActive) {
          _deactivateEyedropper();
        } else {
          _activateEyedropper();
        }
      },
      borderRadius: BorderRadius.circular(4),
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: _eyedropperActive ? cs.primaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Icon(
          Icons.colorize,
          size: 16,
          color: _eyedropperActive ? cs.onPrimaryContainer : cs.onSurface,
        ),
      ),
    );
  }

  Widget _buildGridSwatch(String hex, double size) {
    final cs = Theme.of(context).colorScheme;
    final parsed = parseColor(hex);
    final isLight = (parsed.r + parsed.g + parsed.b) > 1.8;
    final isSelected = widget.currentColor.toLowerCase() == hex.toLowerCase();
    return InkWell(
      onTap: () => widget.onSelect(hex),
      borderRadius: BorderRadius.circular(3),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: parsed,
          border: Border.all(
            color: isSelected
                ? cs.primary
                : isLight
                ? cs.outlineVariant
                : Colors.transparent,
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(3),
        ),
      ),
    );
  }

  bool _isValidHex(String value) {
    final hex = value.startsWith('#') ? value.substring(1) : value;
    if (hex.length != 6) return false;
    return int.tryParse(hex, radix: 16) != null;
  }
}
