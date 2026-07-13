import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/storage/recent_covers_repository.dart';
import '../../../shared/widgets/app_spacing.dart';

// ---------------------------------------------------------------------------
// 路由参数
// ---------------------------------------------------------------------------

class CreateCollectionParams {
  const CreateCollectionParams({
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
}

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

// ---------------------------------------------------------------------------
// 新建笔记本/标签页面
// ---------------------------------------------------------------------------

class CreateCollectionPage extends StatefulWidget {
  const CreateCollectionPage({super.key, required this.params});

  final CreateCollectionParams params;

  @override
  State<CreateCollectionPage> createState() => _CreateCollectionPageState();
}

class _CreateCollectionPageState extends State<CreateCollectionPage> {
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

  // 最近使用的封面
  List<RecentCoverItem> _recentCovers = [];
  bool _loadingRecent = true;

  String get _name => _controller.text.trim();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController()..addListener(_onTitleChanged);
    _focusNode = FocusNode();
    _selectedColor = widget.params.coverColors.first;
    _loadCovers();
    _loadRecentCovers();
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

    // 保存最近使用的封面
    if (_selectedCoverImage != null) {
      defaultRecentCoversRepository.addRecentCover(widget.params.coverCategory, 'image', _selectedCoverImage!);
    } else {
      defaultRecentCoversRepository.addRecentCover(widget.params.coverCategory, 'color', _selectedColor.toARGB32().toRadixString(16).padLeft(8, '0').substring(2));
    }

    context.pop(
      CreateCollectionResult(
        name: _name,
        coverColor: _selectedColor,
        coverImage: _selectedCoverImage,
      ),
    );
  }

  Future<void> _loadCovers() async {
    final covers = await fetchCovers(widget.params.coverCategory);
    if (mounted) {
      final themes = covers
          .map((c) => c.theme)
          .where((t) => t.isNotEmpty)
          .toSet()
          .toList();
      setState(() {
        _covers = covers;
        _themes = themes;
        _loading = false;
      });
    }
  }

  Future<void> _loadRecentCovers() async {
    final recent = await defaultRecentCoversRepository.getRecentCovers(widget.params.coverCategory);
    if (mounted) {
      setState(() {
        _recentCovers = recent;
        _loadingRecent = false;
      });
    }
  }

  Future<void> _clearRecentCovers() async {
    await defaultRecentCoversRepository.clearRecentCovers(widget.params.coverCategory);
    if (mounted) {
      setState(() {
        _recentCovers = [];
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      resizeToAvoidBottomInset: false,
      body: Padding(
        padding: EdgeInsets.only(
          top: MediaQuery.of(context).padding.top,
          left: AppSpacing.pageInset,
          right: AppSpacing.pageInset,
          bottom: AppSpacing.pageInset,
        ),
          child: Column(
            children: [
              // 顶部栏
              _TopBar(
                title: widget.params.title,
                onCancel: () => context.pop(),
                onCreate: _create,
              ),
              const SizedBox(height: 24),
              // 主要内容
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 左侧区域：预览 + 颜色选择（固定）
                    Expanded(
                      flex: 2,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // 封面预览
                            Center(
                              child: Stack(
                                alignment: Alignment.center,
                                clipBehavior: Clip.none,
                                children: [
                                  _CoverPreview(
                                    color: _selectedColor,
                                    icon: widget.params.icon,
                                    coverImage: _selectedCoverImage,
                                  ),
                                  AnimatedOpacity(
                                    opacity: _showEmptyTitleTip ? 1 : 0,
                                    duration: const Duration(milliseconds: 120),
                                    child: const _InlineTip(text: '标题不能为空'),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 24),
                            // 颜色选择
                            Center(
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    '封面模板',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: Theme.of(context).colorScheme.onSurface,
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  ...widget.params.coverColors.map(
                                    (color) => _ColorChoice(
                                      color: color,
                                      selected:
                                          color == _selectedColor &&
                                          _selectedCoverImage == null,
                                      onTap: () => setState(() {
                                        _selectedColor = color;
                                        _selectedCoverImage = null;
                                      }),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 20),
                            // 最近使用
                            if (!_loadingRecent) ...[
                              Row(
                                children: [
                                  Text(
                                    '最近使用',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                  const Spacer(),
                                  if (_recentCovers.isNotEmpty)
                                    GestureDetector(
                                      onTap: _clearRecentCovers,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Theme.of(context).colorScheme.surfaceContainer,
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          '清除',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w500,
                                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              if (_recentCovers.isEmpty)
                                Text(
                                  '新建成功后，此处会显示最近使用过的封面',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  ),
                                )
                              else
                                SizedBox(
                                  height: 64,
                                  child: ListView.separated(
                                    scrollDirection: Axis.horizontal,
                                    itemCount: _recentCovers.length,
                                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                                    itemBuilder: (context, index) {
                                      final item = _recentCovers[index];
                                      return _RecentCoverChip(
                                        item: item,
                                        onTap: () {
                                          setState(() {
                                            if (item.type == 'color') {
                                              _selectedColor = Color(int.parse('0xFF${item.value}', radix: 16));
                                              _selectedCoverImage = null;
                                            } else {
                                              _selectedCoverImage = item.value;
                                            }
                                          });
                                        },
                                      );
                                    },
                                  ),
                                ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    // 分割线
                  VerticalDivider(
                      width: 1,
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                    // 右侧区域：输入框 + 封面选择
                    Expanded(
                      flex: 3,
                      child: Column(
                        children: [
                          // 标题输入
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: TextField(
                              controller: _controller,
                              focusNode: _focusNode,
                              autofocus: true,
                              keyboardType: TextInputType.text,
                              maxLength: _maxTitleLength,
                              maxLines: 1,
                              cursorHeight: 16,
                              inputFormatters: [
                                LengthLimitingTextInputFormatter(
                                  _maxTitleLength,
                                ),
                              ],
                              textInputAction: TextInputAction.done,
                              onSubmitted: (_) => _create(),
                              textAlignVertical: TextAlignVertical.center,
                              decoration: InputDecoration(
                                counterText: '',
                                hintText: widget.params.hintText,
                                filled: true,
                                fillColor: Theme.of(context).colorScheme.surfaceContainer,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(
                                    AppSpacing.radius,
                                  ),
                                  borderSide: BorderSide.none,
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(
                                    AppSpacing.radius,
                                  ),
                                  borderSide: BorderSide.none,
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(
                                    AppSpacing.radius,
                                  ),
                                  borderSide: BorderSide(
                                    color: colorScheme.primary,
                                    width: 1.5,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          // 更多封面提示
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: 16),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                '更多封面',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          // 封面选择列表
                          Expanded(
                            child: _loading
                                ? Center(
                                    child: CircularProgressIndicator(
                                      color: Theme.of(context).colorScheme.primary,
                                    ),
                                  )
                                : _themes.isEmpty
                                    ? Center(
                                        child: Text(
                                          '暂无更多封面',
                                          style: TextStyle(
                                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                                            fontSize: 15,
                                          ),
                                        ),
                                      )
                                    : ListView.builder(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                        ),
                                        itemCount: _themes.length,
                                        itemBuilder: (context, index) {
                                          final theme = _themes[index];
                                          final themeCovers = _covers
                                              .where((c) => c.theme == theme)
                                              .toList();
                                          return Padding(
                                            padding: const EdgeInsets.only(
                                              bottom: 16,
                                            ),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  theme,
                                                  style: TextStyle(
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.w600,
                                                    color: Theme.of(context).colorScheme.onSurface,
                                                  ),
                                                ),
                                                const SizedBox(height: 8),
                                                Wrap(
                                                  spacing: 12,
                                                  runSpacing: 12,
                                                  children: themeCovers.map((item) {
                                                    final isSelected =
                                                        _selectedCoverImage ==
                                                            item.assetPath;
                                                    return GestureDetector(
                                                      onTap: () {
                                                        setState(() {
                                                          _selectedCoverImage =
                                                              item.assetPath;
                                                        });
                                                      },
                                                      child: Container(
                                                        width: 100,
                                                        height: 130,
                                                        decoration:
                                                            BoxDecoration(
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(
                                                            AppSpacing.radius,
                                                          ),
                                                          border: Border.all(
                                                            color: isSelected
                                                                ? colorScheme
                                                                    .primary
                                                                : colorScheme.outlineVariant,
                                                            width: isSelected
                                                                ? 2
                                                                : 1,
                                                          ),
                                                        ),
                                                        child: ClipRRect(
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(
                                                            AppSpacing.radius,
                                                          ),
                                                            child:
                                                                Image.asset(
                                                              item.assetPath,
                                                              fit: BoxFit.cover,
                                                              errorBuilder:
                                                                  (_, _, _) =>
                                                                      Center(
                                                                child: Icon(
                                                                  Icons
                                                                      .image_outlined,
                                                                  color: colorScheme.onSurfaceVariant,
                                                                ),
                                                              ),
                                                            ),
                                                          ),
                                                        ),
                                                      );
                                                    }).toList(),
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
            ],
          ),
        ),
    );
  }
}

// ---------------------------------------------------------------------------
// 顶部栏组件
// ---------------------------------------------------------------------------

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.title,
    required this.onCancel,
    required this.onCreate,
  });

  final String title;
  final VoidCallback onCancel;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Row(
          children: [
            TextButton(
              onPressed: onCancel,
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.primary,
                textStyle: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppSpacing.radius),
                ),
              ),
              child: const Text('取消'),
            ),
            const Spacer(),
            ElevatedButton(
              onPressed: () {
                FocusManager.instance.primaryFocus?.unfocus();
                onCreate();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
                textStyle: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
                elevation: 0,
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 10,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppSpacing.radius),
                ),
              ),
              child: const Text('创建'),
            ),
          ],
        ),
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurface,
                fontWeight: FontWeight.w700,
              ),
        ),
      ],
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
      width: 180,
      height: 240,
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
                      Color.alphaBlend(
                        Colors.white.withValues(alpha: 0.14),
                        color,
                      ),
                      color,
                      Color.alphaBlend(
                        Colors.black.withValues(alpha: 0.08),
                        color,
                      ),
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
                  child: Icon(
                    icon,
                    size: 28,
                    color: foreground.withValues(alpha: 0.8),
                  ),
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

// ---------------------------------------------------------------------------
// 最近使用封面组件
// ---------------------------------------------------------------------------

class _RecentCoverChip extends StatelessWidget {
  const _RecentCoverChip({
    required this.item,
    required this.onTap,
  });

  final RecentCoverItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isColor = item.type == 'color';
    final color = isColor ? Color(int.parse('0xFF${item.value}', radix: 16)) : null;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 58,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: const Color(0xFFE3E8E5),
            width: 1,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(7),
          child: isColor
              ? DecoratedBox(
                  decoration: BoxDecoration(color: color),
                )
              : Image.asset(
                  item.value,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const Center(
                    child: Icon(
                      Icons.image_outlined,
                      color: Color(0xFF8A908D),
                      size: 20,
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}
