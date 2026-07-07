library;

import 'package:flutter/material.dart';

/// Parses a hex color string (e.g. '#ff0000') or 'transparent' to a [Color].
Color parseColor(String hex) {
  if (hex == 'transparent') return Colors.transparent;
  final h = hex.replaceFirst('#', '');
  return Color(int.parse('ff$h', radix: 16));
}

/// Excalidraw canvas background presets (from packages/common/src/colors.ts).
const canvasBackgroundPresets = [
  '#ffffff', // white
  '#f8f9fa', // radix slate2
  '#f5faff', // radix blue2
  '#fffce8', // radix yellow2
  '#fdf8f6', // radix bronze2
];

/// Excalidraw Open Color palette — stroke uses saturated colors.
const strokeQuickPicks = [
  '#1e1e1e', // black
  '#e03131', // red
  '#40c057', // green
  '#228be6', // blue
  '#fab005', // yellow
];

/// Excalidraw Open Color palette — background uses pastel colors.
const backgroundQuickPicks = [
  'transparent',
  '#ffc9c9', // red light
  '#b2f2bb', // green light
  '#a5d8ff', // blue light
  '#ffec99', // yellow light
];
