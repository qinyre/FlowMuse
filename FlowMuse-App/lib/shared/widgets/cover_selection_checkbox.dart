import 'package:flutter/material.dart';

class CoverSelectionCheckbox extends StatelessWidget {
  const CoverSelectionCheckbox({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final bool selected;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Checkbox(
      value: selected,
      onChanged: (_) => onChanged(),
      shape: const CircleBorder(),
    );
  }
}
