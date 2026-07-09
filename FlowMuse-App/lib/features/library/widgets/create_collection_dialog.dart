import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../shared/widgets/app_spacing.dart';

class CreateCollectionResult {
  const CreateCollectionResult({
    required this.name,
    required this.coverColor,
  });

  final String name;
  final Color coverColor;
}

Future<CreateCollectionResult?> showCreateCollectionDialog({
  required BuildContext context,
  required String title,
  required String hintText,
  required IconData icon,
  required List<Color> coverColors,
}) {
  return showDialog<CreateCollectionResult>(
    context: context,
    builder: (context) => CreateCollectionDialog(
      title: title,
      hintText: hintText,
      icon: icon,
      coverColors: coverColors,
    ),
  );
}

class CreateCollectionDialog extends StatefulWidget {
  const CreateCollectionDialog({
    super.key,
    required this.title,
    required this.hintText,
    required this.icon,
    required this.coverColors,
  });

  final String title;
  final String hintText;
  final IconData icon;
  final List<Color> coverColors;

  @override
  State<CreateCollectionDialog> createState() => _CreateCollectionDialogState();
}

class _CreateCollectionDialogState extends State<CreateCollectionDialog> {
  static const _maxTitleLength = 60;

  late final TextEditingController _controller;
  late Color _selectedColor;

  String get _name => _controller.text.trim();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController()..addListener(_onTitleChanged);
    _selectedColor = widget.coverColors.first;
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onTitleChanged)
      ..dispose();
    super.dispose();
  }

  void _onTitleChanged() {
    setState(() {});
  }

  void _create() {
    if (_name.isEmpty) {
      return;
    }
    Navigator.of(context).pop(
      CreateCollectionResult(name: _name, coverColor: _selectedColor),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radius),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 16, 22, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF8A908D),
                    ),
                    child: const Text('取消'),
                  ),
                  Expanded(
                    child: Text(
                      widget.title,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF202523),
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _name.isEmpty ? null : _create,
                    style: TextButton.styleFrom(
                      foregroundColor: colorScheme.primary,
                      disabledForegroundColor: colorScheme.onSurface
                          .withValues(alpha: 0.32),
                    ),
                    child: const Text('创建'),
                  ),
                ],
              ),
              const SizedBox(height: 30),
              _CoverPreview(color: _selectedColor, icon: widget.icon),
              const SizedBox(height: 20),
              Wrap(
                spacing: 14,
                children: [
                  for (final color in widget.coverColors)
                    _ColorChoice(
                      color: color,
                      selected: color == _selectedColor,
                      onTap: () => setState(() => _selectedColor = color),
                    ),
                ],
              ),
              const SizedBox(height: 26),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  '${_controller.text.length} / $_maxTitleLength',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF6C746F),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _controller,
                autofocus: true,
                maxLength: _maxTitleLength,
                inputFormatters: [
                  LengthLimitingTextInputFormatter(_maxTitleLength),
                ],
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _create(),
                decoration: InputDecoration(
                  counterText: '',
                  hintText: widget.hintText,
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.radius),
                    borderSide: BorderSide(
                      color: colorScheme.primary.withValues(alpha: 0.72),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.radius),
                    borderSide: BorderSide(color: colorScheme.primary, width: 2),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CoverPreview extends StatelessWidget {
  const _CoverPreview({required this.color, required this.icon});

  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final foreground =
        ThemeData.estimateBrightnessForColor(color) == Brightness.dark
        ? Colors.white
        : const Color(0xFF202523);

    return SizedBox(
      width: 108,
      height: 136,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(AppSpacing.radius),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color.alphaBlend(Colors.white.withValues(alpha: 0.14), color),
              color,
              Color.alphaBlend(Colors.black.withValues(alpha: 0.08), color),
            ],
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x185A625F),
              blurRadius: 14,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Center(
          child: Icon(icon, size: 34, color: foreground.withValues(alpha: 0.8)),
        ),
      ),
    );
  }
}

class _ColorChoice extends StatelessWidget {
  const _ColorChoice({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return InkResponse(
      onTap: onTap,
      radius: 18,
      child: Container(
        width: 24,
        height: 24,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? primary : Colors.transparent,
            width: 2,
          ),
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
      ),
    );
  }
}
