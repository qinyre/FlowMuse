library;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

/// Shows the keyboard shortcuts help dialog.
void showHelpDialog(BuildContext context) {
  final isMac = Theme.of(context).platform == TargetPlatform.macOS || kIsWeb;
  final mod = isMac ? 'Cmd' : 'Ctrl';
  showDialog<void>(
    context: context,
    builder: (ctx) => Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 600),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 8, 0),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Keyboard shortcuts',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(ctx).pop(),
                  ),
                ],
              ),
            ),
            const Divider(),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _helpSection(context, 'Tools', [
                      _shortcutRow(context, 'Hand', 'H'),
                      _shortcutRow(context, 'Select', '1 / V'),
                      _shortcutRow(context, 'Rectangle', '2 / R'),
                      _shortcutRow(context, 'Diamond', '3 / D'),
                      _shortcutRow(context, 'Ellipse', '4 / O'),
                      _shortcutRow(context, 'Arrow', '5 / A'),
                      _shortcutRow(context, 'Line', '6 / L'),
                      _shortcutRow(context, 'Freedraw', '7 / P'),
                      _shortcutRow(context, 'Text', '8 / T'),
                      _shortcutRow(context, 'Import image', '9'),
                      _shortcutRow(context, 'Eraser', '0 / E'),
                      _shortcutRow(context, 'Frame', 'F'),
                      _shortcutRow(context, 'Laser pointer', 'K'),
                      _shortcutRow(context, 'Lock tool', 'Q'),
                    ]),
                    const SizedBox(height: 16),
                    _helpSection(context, 'View', [
                      _shortcutRow(context, 'Zoom in', '$mod + +'),
                      _shortcutRow(context, 'Zoom out', '$mod + \u2212'),
                      _shortcutRow(context, 'Reset zoom', '$mod + 0'),
                      _shortcutRow(context, 'Zoom to fit', 'Shift + 1'),
                      _shortcutRow(context, 'Zoom to selection', 'Shift + 2'),
                      _shortcutRow(context, 'Page down / up', 'PgDn / PgUp'),
                      _shortcutRow(
                        context,
                        'Page left / right',
                        'Shift + PgDn / PgUp',
                      ),
                      _shortcutRow(context, 'Toggle grid', "$mod + '"),
                      _shortcutRow(context, 'Zen mode', 'Alt + Z'),
                      _shortcutRow(context, 'View mode', 'Alt + R'),
                      _shortcutRow(context, 'Toggle theme', 'Alt + Shift + D'),
                    ]),
                    const SizedBox(height: 16),
                    _helpSection(context, 'Editor', [
                      _shortcutRow(context, 'Undo', '$mod + Z'),
                      _shortcutRow(
                        context,
                        'Redo',
                        '$mod + Shift + Z / $mod + Y',
                      ),
                      _shortcutRow(context, 'Copy', '$mod + C'),
                      _shortcutRow(context, 'Paste', '$mod + V'),
                      _shortcutRow(context, 'Cut', '$mod + X'),
                      _shortcutRow(context, 'Duplicate', '$mod + D'),
                      _shortcutRow(context, 'Select all', '$mod + A'),
                      _shortcutRow(context, 'Delete', 'Del / Backspace'),
                      _shortcutRow(context, 'Group', '$mod + G'),
                      _shortcutRow(context, 'Ungroup', '$mod + Shift + G'),
                      _shortcutRow(
                        context,
                        'Lock / Unlock',
                        '$mod + Shift + L',
                      ),
                      _shortcutRow(context, 'Bring forward', '$mod + ]'),
                      _shortcutRow(
                        context,
                        'Bring to front',
                        '$mod + Shift + ]',
                      ),
                      _shortcutRow(context, 'Send backward', '$mod + ['),
                      _shortcutRow(context, 'Send to back', '$mod + Shift + ['),
                      _shortcutRow(context, 'Nudge', 'Arrows'),
                      _shortcutRow(context, 'Nudge 10px', 'Shift + Arrows'),
                      _shortcutRow(
                        context,
                        'Align left / right',
                        '$mod + Shift + \u2190 / \u2192',
                      ),
                      _shortcutRow(
                        context,
                        'Align top / bottom',
                        '$mod + Shift + \u2191 / \u2193',
                      ),
                      _shortcutRow(
                        context,
                        'Increase font size',
                        '$mod + Shift + >',
                      ),
                      _shortcutRow(
                        context,
                        'Decrease font size',
                        '$mod + Shift + <',
                      ),
                      _shortcutRow(context, 'Stroke color', 'S'),
                      _shortcutRow(context, 'Background color', 'G'),
                      _shortcutRow(context, 'Font picker', 'Shift + F'),
                      _shortcutRow(context, 'Flip horizontal', 'Shift + H'),
                      _shortcutRow(context, 'Flip vertical', 'Shift + V'),
                      _shortcutRow(context, 'Cycle shape', 'Tab'),
                      _shortcutRow(context, 'Copy as PNG', 'Shift + Alt + C'),
                      _shortcutRow(context, 'Copy style', '$mod + Alt + C'),
                      _shortcutRow(context, 'Paste style', '$mod + Alt + V'),
                      _shortcutRow(
                        context,
                        'Paste as text',
                        '$mod + Shift + V',
                      ),
                      _shortcutRow(context, 'Reset canvas', '$mod + Del'),
                      _shortcutRow(context, 'Edit link', '$mod + K'),
                      _shortcutRow(context, 'Finalize line', 'Enter'),
                      _shortcutRow(context, 'Create flowchart', '$mod + Arrow'),
                      _shortcutRow(
                        context,
                        'Navigate flowchart',
                        'Alt + Arrow',
                      ),
                      _shortcutRow(context, 'Find on canvas', '$mod + F'),
                      _shortcutRow(context, 'Deselect', 'Escape'),
                    ]),
                    const SizedBox(height: 16),
                    _helpSection(context, 'File', [
                      _shortcutRow(context, 'Open', '$mod + O'),
                      _shortcutRow(context, 'Save', '$mod + S'),
                      _shortcutRow(context, 'Save as', '$mod + Shift + S'),
                      _shortcutRow(context, 'Export PNG', '$mod + Shift + E'),
                    ]),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

Widget _helpSection(BuildContext context, String title, List<Widget> rows) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 8),
      ...rows,
    ],
  );
}

Widget _shortcutRow(BuildContext context, String description, String shortcut) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        Expanded(
          child: Text(description, style: const TextStyle(fontSize: 13)),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            shortcut,
            style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
          ),
        ),
      ],
    ),
  );
}
