import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../shared/widgets/app_spacing.dart';

// ---------------------------------------------------------------------------
// 封面数据
// ---------------------------------------------------------------------------

class CoverItem {
  const CoverItem({
    required this.id,
    required this.assetPath,
    this.name = '',
    this.theme = '',
  });

  final String id;
  final String assetPath;
  final String name;
  final String theme;
}

Future<List<CoverItem>> fetchCovers(String category) async {
  final raw = await rootBundle.loadString('assets/covers/manifest.json');
  final map = json.decode(raw) as Map<String, dynamic>;
  final items = (map[category] as List?) ?? [];
  return [
    for (final item in items)
      CoverItem(
        id: item['id'] as String,
        assetPath: 'assets/covers/$category/${item['file']}',
        name: (item['name'] as String?) ?? '',
        theme: (item['theme'] as String?) ?? '',
      ),
  ];
}

class CreateCollectionResult {
  const CreateCollectionResult({
    required this.name,
    required this.coverColor,
    this.coverImage,
  });

  final String name;
  final Color coverColor;
  final String? coverImage;
}

Future<CreateCollectionResult?> showCreateCollectionDialog({
  required BuildContext context,
  required String title,
  required String hintText,
  required IconData icon,
  required List<Color> coverColors,
  required String coverCategory,
}) {
  return showDialog<CreateCollectionResult>(
    context: context,
    builder: (context) => CreateCollectionDialog(
      title: title,
      hintText: hintText,
      icon: icon,
      coverColors: coverColors,
      coverCategory: coverCategory,
    ),
  );
}

// ---------------------------------------------------------------------------
// 新建笔记本/标签对话框
// ---------------------------------------------------------------------------

class CreateCollectionDialog extends StatefulWidget {
  const CreateCollectionDialog({
    super.key,
    required this.title,
    required this.hintText,
    required this.icon,
    required this.coverColors,
    required this.coverCategory,
  });

  final String title;
  final String hintText;
  final IconData icon;
  final List<Color> coverColors;
  final String coverCategory;

  @override
  State<CreateCollectionDialog> createState() => _CreateCollectionDialogState();
}

class _CreateCollectionDialogState extends State<CreateCollectionDialog> {
  static const _maxTitleLength = 60;

  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  late Color _selectedColor;
  String? _selectedCoverImage;
  bool _showEmptyTitleTip = false;

  // 封面数据
  List<CoverItem> _covers = const [];
  bool _loading = true;
  late List<String> _themes;
  final ScrollController _scrollController = ScrollController();
  final List<GlobalKey> _sectionKeys = [];
  int _selectedTab = 0;

  String get _name => _controller.text.trim();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController()..addListener(_onTitleChanged);
    _focusNode = FocusNode();
    _selectedColor = widget.coverColors.first;
    _loadCovers();
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onTitleChanged)
      ..dispose();
    _focusNode.dispose();
    _scrollController.dispose();
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
      CreateCollectionResult(
        name: _name,
        coverColor: _selectedColor,
        coverImage: _selectedCoverImage,
      ),
    );
  }

  Future<void> _loadCovers() async {
    final covers = await fetchCovers(widget.coverCategory);
    if (mounted) {
      final themes = covers.map((c) => c.theme).where((t) => t.isNotEmpty).toSet().toList();
      setState(() {
        _covers = covers;
        _themes = themes;
        _sectionKeys.clear();
        for (var i = 0; i < themes.length; i++) {
          _sectionKeys.add(GlobalKey());
        }
        _loading = false;
      });
    }
  }

  void _scrollToSection(int index) {
    setState(() => _selectedTab = index);
    final key = _sectionKeys[index];
    final context = key.currentContext;
    if (context != null) {
      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        alignment: 0.0,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Dialog(
      insetPadding: EdgeInsets.zero,
      shape: const RoundedRectangleBorder(),
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.dark.copyWith(
          statusBarColor: Colors.transparent,
          systemNavigationBarColor: Colors.white,
        ),
        child: Scaffold(
          backgroundColor: Colors.white,
          resizeToAvoidBottomInset: false,
          appBar: AppBar(
            backgroundColor: Colors.white,
            elevation: 0,
            leading: TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消', style: TextStyle(color: Color(0xFF8A908D))),
            ),
            title: Text(
              widget.title,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: Color(0xFF202523),
              ),
            ),
            centerTitle: true,
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: TextButton(
                  onPressed: _create,
                  style: TextButton.styleFrom(
                    backgroundColor: colorScheme.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  ),
                  child: const Text('创建', style: TextStyle(fontSize: 14)),
                ),
              ),
            ],
          ),
          body: SafeArea(
            child: Column(
              children: [
                // 顶部内容区：封面预览 + 标题输入
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 60, vertical: 24),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // 封面预览
                      Stack(
                        alignment: Alignment.center,
                        clipBehavior: Clip.none,
                        children: [
                          _CoverPreview(
                            color: _selectedColor,
                            icon: widget.icon,
                            coverImage: _selectedCoverImage,
                          ),
                          AnimatedOpacity(
                            opacity: _showEmptyTitleTip ? 1 : 0,
                            duration: const Duration(milliseconds: 120),
                            child: const _InlineTip(text: '标题不能为空'),
                          ),
                        ],
                      ),
                      const SizedBox(width: 20),
                      // 标题输入框
                      SizedBox(
                        width: 200,
                        child: TextField(
                          controller: _controller,
                          focusNode: _focusNode,
                          autofocus: true,
                          keyboardType: TextInputType.text,
                          maxLength: _maxTitleLength,
                          maxLines: 1,
                          cursorHeight: 16,
                          inputFormatters: [
                            LengthLimitingTextInputFormatter(_maxTitleLength),
                          ],
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _create(),
                          textAlignVertical: TextAlignVertical.center,
                          decoration: InputDecoration(
                            counterText: '',
                            hintText: widget.hintText,
                            filled: true,
                            fillColor: const Color(0xFFF5F7F6),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(AppSpacing.radius),
                              borderSide: BorderSide.none,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(AppSpacing.radius),
                              borderSide: BorderSide.none,
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(AppSpacing.radius),
                              borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: Color(0xFFE9EEEB)),
                // 封面模板 + 颜色选择
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        '封面模板',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF202523),
                        ),
                      ),
                      const SizedBox(width: 16),
                      ...widget.coverColors.map((color) => _ColorChoice(
                            color: color,
                            selected: color == _selectedColor && _selectedCoverImage == null,
                            onTap: () => setState(() {
                              _selectedColor = color;
                              _selectedCoverImage = null;
                            }),
                          )),
                    ],
                  ),
                ),
                const Divider(height: 1, color: Color(0xFFE9EEEB)),
                // Tab 栏 + 内容区域
                if (_loading)
                  const Expanded(
                    child: Center(child: CircularProgressIndicator(color: Color(0xFF4F8F84))),
                  )
                else if (_themes.isEmpty)
                  const Expanded(
                    child: Center(
                      child: Text(
                        '暂无更多封面',
                        style: TextStyle(color: Color(0xFF8A908D), fontSize: 15),
                      ),
                    ),
                  )
                else
                  Expanded(
                    child: Column(
                      children: [
                        Container(
                          height: 44,
                          margin: const EdgeInsets.symmetric(horizontal: 20),
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: _themes.length,
                            separatorBuilder: (_, _) => const SizedBox(width: 24),
                            itemBuilder: (context, index) {
                              final isSelected = _selectedTab == index;
                              return GestureDetector(
                                onTap: () => _scrollToSection(index),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      _themes[index],
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                                        color: isSelected
                                            ? const Color(0xFF4F8F84)
                                            : const Color(0xFF8A908D),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Container(
                                      height: 2,
                                      width: 20,
                                      decoration: BoxDecoration(
                                        color: isSelected
                                            ? const Color(0xFF4F8F84)
                                            : Colors.transparent,
                                        borderRadius: BorderRadius.circular(1),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 8),
                        // 内容区域 - 单页滚动，每个主题一行
                        Expanded(
                          child: ListView.builder(
                            controller: _scrollController,
                            padding: const EdgeInsets.only(bottom: 20),
                            itemCount: _themes.length,
                            itemBuilder: (context, index) {
                              final theme = _themes[index];
                              final themeCovers = _covers.where((c) => c.theme == theme).toList();
                              return Padding(
                                key: _sectionKeys[index],
                                padding: const EdgeInsets.only(top: 8),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 20),
                                      child: Text(
                                        theme,
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFF202523),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    SizedBox(
                                      height: 140,
                                      child: ListView.separated(
                                        padding: const EdgeInsets.symmetric(horizontal: 20),
                                        scrollDirection: Axis.horizontal,
                                        itemCount: themeCovers.length,
                                        separatorBuilder: (_, _) => const SizedBox(width: 12),
                                        itemBuilder: (context, index) {
                                          final item = themeCovers[index];
                                          final isSelected = _selectedCoverImage == item.assetPath;
                                          return GestureDetector(
                                            onTap: () {
                                              setState(() {
                                                _selectedCoverImage = item.assetPath;
                                              });
                                            },
                                            child: Container(
                                              width: 90,
                                              decoration: BoxDecoration(
                                                borderRadius: BorderRadius.circular(AppSpacing.radius),
                                                border: Border.all(
                                                  color: isSelected
                                                      ? colorScheme.primary
                                                      : const Color(0xFFE3E8E5),
                                                  width: isSelected ? 2 : 1,
                                                ),
                                              ),
                                              child: ClipRRect(
                                                borderRadius: BorderRadius.circular(AppSpacing.radius),
                                                child: Image.asset(
                                                  item.assetPath,
                                                  fit: BoxFit.cover,
                                                  errorBuilder: (_, _, _) => const Center(
                                                    child: Icon(
                                                      Icons.image_outlined,
                                                      color: Color(0xFF8A908D),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 封面预览组件
// ---------------------------------------------------------------------------

class _CoverPreview extends StatelessWidget {
  const _CoverPreview({
    required this.color,
    required this.icon,
    this.coverImage,
  });

  final Color color;
  final IconData icon;
  final String? coverImage;

  @override
  Widget build(BuildContext context) {
    final foreground =
        ThemeData.estimateBrightnessForColor(color) == Brightness.dark
        ? Colors.white
        : const Color(0xFF202523);

    return SizedBox(
      width: 90,
      height: 120,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppSpacing.radius),
        child: coverImage != null
            ? Image.asset(coverImage!, fit: BoxFit.cover)
            : DecoratedBox(
                decoration: BoxDecoration(
                  color: color,
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
                  child: Icon(icon, size: 28, color: foreground.withValues(alpha: 0.8)),
                ),
              ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 内联提示组件
// ---------------------------------------------------------------------------

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

// ---------------------------------------------------------------------------
// 颜色选择组件
// ---------------------------------------------------------------------------

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
