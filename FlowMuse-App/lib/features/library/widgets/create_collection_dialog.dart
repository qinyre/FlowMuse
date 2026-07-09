import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../shared/widgets/app_spacing.dart';

// ---------------------------------------------------------------------------
// 封面数据
// ---------------------------------------------------------------------------

class CoverItem {
  const CoverItem({required this.id, required this.imageUrl, this.name = ''});

  final String id;
  final String imageUrl;
  final String name;
}

/// 占位实现，后续替换为真实 API
Future<List<CoverItem>> fetchCovers() async => const [];

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
  late final FocusNode _focusNode;
  late Color _selectedColor;
  bool _showEmptyTitleTip = false;

  String get _name => _controller.text.trim();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController()..addListener(_onTitleChanged);
    _focusNode = FocusNode();
    _selectedColor = widget.coverColors.first;
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onTitleChanged)
      ..dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onTitleChanged() {
    setState(() {});
  }

  void _create() {
    if (_name.isEmpty) {
      setState(() => _showEmptyTitleTip = true);
      Future<void>.delayed(const Duration(milliseconds: 1200), () {
        if (mounted) {
          setState(() => _showEmptyTitleTip = false);
        }
      });
      return;
    }
    Navigator.of(context).pop(
      CreateCollectionResult(name: _name, coverColor: _selectedColor),
    );
  }

  Future<void> _showCoverPicker() async {
    final selected = await showModalBottomSheet<CoverItem>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (context) => const _CoverPickerSheet(),
    );
    if (selected != null && mounted) {
      // 后续处理选中的封面图片
      debugPrint('Selected cover: ${selected.id} - ${selected.imageUrl}');
    }
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
                    onPressed: _create,
                    style: TextButton.styleFrom(
                      foregroundColor: colorScheme.primary,
                    ),
                    child: const Text('创建'),
                  ),
                ],
              ),
              const SizedBox(height: 30),
              Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  _CoverPreview(color: _selectedColor, icon: widget.icon),
                  AnimatedOpacity(
                    opacity: _showEmptyTitleTip ? 1 : 0,
                    duration: const Duration(milliseconds: 120),
                    child: const _InlineTip(text: '标题不能为空'),
                  ),
                ],
              ),
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
              const SizedBox(height: 14),
              // 选择更多封面按钮
              Center(
                child: OutlinedButton.icon(
                  onPressed: _showCoverPicker,
                  icon: const Icon(LucideIcons.images, size: 18),
                  label: const Text('选择更多封面'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF4F8F84),
                    side: const BorderSide(color: Color(0xFF4F8F84)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppSpacing.radius),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  ),
                ),
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
                focusNode: _focusNode,
                autofocus: true,
                keyboardType: TextInputType.text,
                maxLength: _maxTitleLength,
                maxLines: 1,
                cursorHeight: 18,
                inputFormatters: [
                  LengthLimitingTextInputFormatter(_maxTitleLength),
                ],
                textInputAction: TextInputAction.done,
                onTapAlwaysCalled: true,
                onTap: () {
                  if (!_focusNode.hasFocus) {
                    FocusScope.of(context).requestFocus(_focusNode);
                    return;
                  }
                  _focusNode.unfocus();
                  Future<void>.delayed(const Duration(milliseconds: 50), () {
                    if (context.mounted) {
                      FocusScope.of(context).requestFocus(_focusNode);
                    }
                  });
                },
                onSubmitted: (_) => _create(),
                textAlignVertical: TextAlignVertical.center,
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

class _InlineTip extends StatelessWidget {
  const _InlineTip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xD9353736),
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(
            color: Color(0x30000000),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        child: Text(
          text,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
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

// ---------------------------------------------------------------------------
// 封面选择弹窗
// ---------------------------------------------------------------------------

class _CoverPickerSheet extends StatefulWidget {
  const _CoverPickerSheet();

  @override
  State<_CoverPickerSheet> createState() => _CoverPickerSheetState();
}

class _CoverPickerSheetState extends State<_CoverPickerSheet> {
  List<CoverItem> _covers = const [];
  bool _loading = true;
  CoverItem? _selected;

  @override
  void initState() {
    super.initState();
    _loadCovers();
  }

  Future<void> _loadCovers() async {
    final covers = await fetchCovers();
    if (mounted) {
      setState(() {
        _covers = covers;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.3,
      maxChildSize: 0.85,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            // 顶部拖拽指示条
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 8),
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFD0D5D2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // 标题栏
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('取消', style: TextStyle(color: Color(0xFF4F8F84))),
                  ),
                  const Expanded(
                    child: Text(
                      '选择封面',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1F2624),
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(_selected),
                    child: const Text('确定', style: TextStyle(color: Color(0xFF4F8F84))),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFFE9EEEB)),
            // 内容区域
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: Color(0xFF4F8F84)))
                  : _covers.isEmpty
                      ? const Center(
                          child: Text(
                            '暂无更多封面',
                            style: TextStyle(color: Color(0xFF8A908D), fontSize: 15),
                          ),
                        )
                      : GridView.builder(
                          controller: scrollController,
                          padding: const EdgeInsets.all(20),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            crossAxisSpacing: 14,
                            mainAxisSpacing: 14,
                            childAspectRatio: 0.75,
                          ),
                          itemCount: _covers.length,
                          itemBuilder: (context, index) {
                            final cover = _covers[index];
                            final isSelected = _selected?.id == cover.id;
                            return GestureDetector(
                              onTap: () {
                                setState(() => _selected = cover);
                              },
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(AppSpacing.radius),
                                  border: Border.all(
                                    color: isSelected
                                        ? const Color(0xFF4F8F84)
                                        : const Color(0xFFE3E8E5),
                                    width: isSelected ? 2 : 1,
                                  ),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(AppSpacing.radius),
                                  child: Image.network(
                                    cover.imageUrl,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => const Center(
                                      child: Icon(LucideIcons.imageOff, color: Color(0xFF8A908D)),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ],
        );
      },
    );
  }
}
