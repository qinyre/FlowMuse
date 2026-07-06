import 'package:flutter/material.dart';

void main() {
  runApp(const FlowMuseApp());
}

class FlowMuseApp extends StatelessWidget {
  const FlowMuseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FlowMuse',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF66B7A8),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFFAFCFA),
        fontFamily: 'serif',
      ),
      home: const LibraryHomePage(),
    );
  }
}

enum LibraryFilter { all, notes, pdf }

class NotebookItem {
  const NotebookItem({
    required this.title,
    required this.date,
    required this.kind,
    required this.palette,
    this.subtitle,
  });

  final String title;
  final String date;
  final LibraryFilter kind;
  final List<Color> palette;
  final String? subtitle;
}

class LibraryHomeViewModel extends ChangeNotifier {
  LibraryFilter _selectedFilter = LibraryFilter.all;

  LibraryFilter get selectedFilter => _selectedFilter;

  final List<NotebookItem> notebooks = const [
    NotebookItem(
      title: '操作系统',
      date: '2026/06/26',
      kind: LibraryFilter.notes,
      palette: [Color(0xFF8DB6C9), Color(0xFFE8F5F3), Color(0xFF5D86A1)],
      subtitle: '操作系统概念',
    ),
    NotebookItem(
      title: 'LectureNotes',
      date: '2026/05/28',
      kind: LibraryFilter.pdf,
      palette: [Color(0xFFF8F8F4), Color(0xFFD9B48F), Color(0xFF2E2B28)],
    ),
    NotebookItem(
      title: '量子计算',
      date: '2026/05/16',
      kind: LibraryFilter.notes,
      palette: [Color(0xFF2E5872), Color(0xFFEAF1F0), Color(0xFF8CB7C6)],
    ),
    NotebookItem(
      title: '小说',
      date: '2026/04/23',
      kind: LibraryFilter.notes,
      palette: [Color(0xFF8CBDB5), Color(0xFFE7F6E8), Color(0xFF628F8A)],
    ),
    NotebookItem(
      title: '草稿本',
      date: '2026/04/03',
      kind: LibraryFilter.notes,
      palette: [Color(0xFFF7F7F4), Color(0xFFD6D6D0), Color(0xFF313534)],
    ),
    NotebookItem(
      title: '软件工程',
      date: '2026/03/05',
      kind: LibraryFilter.notes,
      palette: [Color(0xFFE9993F), Color(0xFF60A7C8), Color(0xFFFFCA5E)],
    ),
    NotebookItem(
      title: '未命名笔记',
      date: '2026/03/04',
      kind: LibraryFilter.notes,
      palette: [Color(0xFFFBFAF7), Color(0xFFE6E4DD), Color(0xFF1F2424)],
    ),
    NotebookItem(
      title: '算法设计 喻丹丹',
      date: '2026/03/02',
      kind: LibraryFilter.notes,
      palette: [Color(0xFF9CA2E6), Color(0xFFF5F2EB), Color(0xFF5E6484)],
    ),
  ];

  List<NotebookItem> get visibleNotebooks {
    if (_selectedFilter == LibraryFilter.all) {
      return notebooks;
    }
    return notebooks.where((item) => item.kind == _selectedFilter).toList();
  }

  void selectFilter(LibraryFilter filter) {
    if (_selectedFilter == filter) {
      return;
    }
    _selectedFilter = filter;
    notifyListeners();
  }
}

class LibraryHomePage extends StatefulWidget {
  const LibraryHomePage({super.key});

  @override
  State<LibraryHomePage> createState() => _LibraryHomePageState();
}

class _LibraryHomePageState extends State<LibraryHomePage> {
  late final LibraryHomeViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = LibraryHomeViewModel();
  }

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  void _openWhiteboard({String title = '未命名白板'}) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => WhiteboardPlaceholderPage(title: title),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _viewModel,
      builder: (context, _) {
        return Scaffold(
          body: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 820;
                return Row(
                  children: [
                    if (!compact) const LibrarySidebar(),
                    Expanded(
                      child: LibraryContent(
                        compact: compact,
                        viewModel: _viewModel,
                        onCreate: () => _openWhiteboard(),
                        onOpenNotebook: (item) => _openWhiteboard(
                          title: item.title,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class LibrarySidebar extends StatelessWidget {
  const LibrarySidebar({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 300,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFF2FBF8), Color(0xFFE4F5F1)],
        ),
        border: Border(right: BorderSide(color: Color(0xFFE0ECE8))),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 24, 28, 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: const [
                _ProBadge(),
                Icon(Icons.view_sidebar_outlined),
                Icon(Icons.settings_outlined),
                Icon(Icons.storefront_outlined),
              ],
            ),
          ),
          const _SearchRow(),
          const SizedBox(height: 18),
          const _SidebarItem(
            icon: Icons.edit_note_outlined,
            label: '全部笔记',
            selected: true,
            trailing: Icons.keyboard_arrow_down,
          ),
          const _SidebarItem(
            icon: Icons.folder_off_outlined,
            label: '未分类',
            count: '10',
          ),
          const _SidebarItem(
            icon: Icons.tag_outlined,
            label: '未标签',
            count: '10',
          ),
          const _SidebarItem(icon: Icons.delete_outline, label: '回收站'),
          const Divider(height: 28, color: Color(0xFFDCE9E5)),
          const _SidebarItem(
            icon: Icons.folder_outlined,
            label: '文件夹',
            count: '暂无文件夹',
            action: Icons.add_circle_outline,
          ),
          const _SidebarItem(
            icon: Icons.numbers_outlined,
            label: '标签',
            count: '暂无标签',
            action: Icons.add_circle_outline,
          ),
          const Spacer(),
          const SizedBox(height: 180, child: _MountainScene()),
        ],
      ),
    );
  }
}

class LibraryContent extends StatelessWidget {
  const LibraryContent({
    super.key,
    required this.compact,
    required this.viewModel,
    required this.onCreate,
    required this.onOpenNotebook,
  });

  final bool compact;
  final LibraryHomeViewModel viewModel;
  final VoidCallback onCreate;
  final ValueChanged<NotebookItem> onOpenNotebook;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(compact ? 20 : 36, 30, compact ? 20 : 36, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _LibraryHeader(compact: compact),
          const SizedBox(height: 36),
          _FilterTabs(viewModel: viewModel),
          const SizedBox(height: 34),
          Expanded(
            child: GridView.builder(
              itemCount: viewModel.visibleNotebooks.length + 1,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: compact ? 2 : 3,
                mainAxisExtent: 310,
                crossAxisSpacing: compact ? 28 : 54,
                mainAxisSpacing: 44,
              ),
              itemBuilder: (context, index) {
                if (index == 0) {
                  return CreateNotebookCard(onTap: onCreate);
                }
                final item = viewModel.visibleNotebooks[index - 1];
                return NotebookCard(
                  item: item,
                  onTap: () => onOpenNotebook(item),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _LibraryHeader extends StatelessWidget {
  const _LibraryHeader({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (compact)
          IconButton(
            tooltip: '菜单',
            onPressed: () {},
            icon: const Icon(Icons.menu),
          ),
        Text(
          '全部笔记',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: const Color(0xFF1F2624),
          ),
        ),
        const Spacer(),
        const _HeaderIcon(icon: Icons.grid_view_rounded),
        const SizedBox(width: 16),
        const _HeaderIcon(icon: Icons.sort_rounded),
        const SizedBox(width: 16),
        const _HeaderIcon(icon: Icons.check_box_outlined),
      ],
    );
  }
}

class _FilterTabs extends StatelessWidget {
  const _FilterTabs({required this.viewModel});

  final LibraryHomeViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _FilterTab(
          label: '全部',
          selected: viewModel.selectedFilter == LibraryFilter.all,
          onTap: () => viewModel.selectFilter(LibraryFilter.all),
        ),
        _FilterTab(
          label: '笔记',
          selected: viewModel.selectedFilter == LibraryFilter.notes,
          onTap: () => viewModel.selectFilter(LibraryFilter.notes),
        ),
        _FilterTab(
          label: 'PDF',
          selected: viewModel.selectedFilter == LibraryFilter.pdf,
          onTap: () => viewModel.selectFilter(LibraryFilter.pdf),
        ),
      ],
    );
  }
}

class _FilterTab extends StatelessWidget {
  const _FilterTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(right: 34),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                color: selected ? const Color(0xFF5EAFA0) : const Color(0xFF151918),
                fontSize: 16,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
            const SizedBox(height: 12),
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: selected ? 56 : 0,
              height: 2,
              color: const Color(0xFF5EAFA0),
            ),
          ],
        ),
      ),
    );
  }
}

class CreateNotebookCard extends StatelessWidget {
  const CreateNotebookCard({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Column(
        children: [
          Expanded(
            child: CustomPaint(
              painter: _DashedBorderPainter(),
              child: const Center(
                child: Icon(Icons.add, size: 46, color: Color(0xFF5EAFA0)),
              ),
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            '新建',
            style: TextStyle(
              color: Color(0xFF5EAFA0),
              fontSize: 17,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '轻点两下，创建快捷笔记',
            style: TextStyle(color: Color(0xFFB4BCB8), fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class NotebookCard extends StatelessWidget {
  const NotebookCard({super.key, required this.item, required this.onTap});

  final NotebookItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Column(
        children: [
          Expanded(child: NotebookCover(item: item)),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  item.title,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF222725),
                    fontSize: 17,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.keyboard_arrow_down,
                color: Color(0xFF555C59),
                size: 20,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            item.date,
            style: const TextStyle(color: Color(0xFFA3AAA6), fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class NotebookCover extends StatelessWidget {
  const NotebookCover({super.key, required this.item});

  final NotebookItem item;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 0.78,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          boxShadow: const [
            BoxShadow(
              blurRadius: 12,
              offset: Offset(0, 8),
              color: Color(0x1F5A625F),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: CustomPaint(
            painter: _NotebookCoverPainter(item.palette),
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                children: [
                  Text(
                    item.kind == LibraryFilter.pdf ? 'PDF' : 'NOTEBOOK',
                    style: TextStyle(
                      color: item.palette.last.withAlpha(220),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (item.subtitle != null)
                    Text(
                      item.subtitle!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: item.palette.last,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  const Spacer(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class WhiteboardPlaceholderPage extends StatelessWidget {
  const WhiteboardPlaceholderPage({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFDFDFB),
      body: SafeArea(
        child: Stack(
          children: [
            Positioned(
              left: 24,
              top: 22,
              child: _FloatingToolButton(
                tooltip: '返回',
                icon: Icons.arrow_back,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            const Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: EdgeInsets.only(top: 22),
                child: _WhiteboardToolbar(),
              ),
            ),
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: const Color(0xFF2B302E),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    '白板工作台',
                    style: TextStyle(color: Color(0xFF8E9692), fontSize: 16),
                  ),
                ],
              ),
            ),
            const Positioned(
              left: 24,
              bottom: 24,
              child: _ZoomControls(),
            ),
          ],
        ),
      ),
    );
  }
}

class _WhiteboardToolbar extends StatelessWidget {
  const _WhiteboardToolbar();

  @override
  Widget build(BuildContext context) {
    const tools = [
      Icons.lock_open_outlined,
      Icons.pan_tool_outlined,
      Icons.near_me_outlined,
      Icons.crop_square_outlined,
      Icons.circle_outlined,
      Icons.arrow_forward,
      Icons.edit_outlined,
      Icons.text_fields,
      Icons.image_outlined,
    ];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE8E8E4)),
        boxShadow: const [
          BoxShadow(
            blurRadius: 18,
            offset: Offset(0, 8),
            color: Color(0x175A625F),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final icon in tools)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Icon(icon, size: 22, color: const Color(0xFF202523)),
            ),
        ],
      ),
    );
  }
}

class _ZoomControls extends StatelessWidget {
  const _ZoomControls();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFEDEEF5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.remove, size: 18),
            SizedBox(width: 28),
            Text('100%', style: TextStyle(fontSize: 16)),
            SizedBox(width: 28),
            Icon(Icons.add, size: 18),
          ],
        ),
      ),
    );
  }
}

class _FloatingToolButton extends StatelessWidget {
  const _FloatingToolButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton.filledTonal(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon),
      style: IconButton.styleFrom(
        backgroundColor: const Color(0xFFEDEEF5),
        foregroundColor: const Color(0xFF202523),
        fixedSize: const Size(56, 56),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}

class _HeaderIcon extends StatelessWidget {
  const _HeaderIcon({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: '工具',
      onPressed: () {},
      icon: Icon(icon, color: const Color(0xFF141816)),
    );
  }
}

class _SearchRow extends StatelessWidget {
  const _SearchRow();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 28),
      child: Row(
        children: [
          Icon(Icons.search, size: 30, color: Color(0xFF1F2624)),
          SizedBox(width: 16),
          Text(
            '搜索',
            style: TextStyle(fontSize: 20, color: Color(0xFF1F2624)),
          ),
        ],
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.icon,
    required this.label,
    this.selected = false,
    this.count,
    this.trailing,
    this.action,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final String? count;
  final IconData? trailing;
  final IconData? action;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
      color: selected ? const Color(0xFFE3F5F0) : Colors.transparent,
      child: Row(
        children: [
          Icon(icon, color: selected ? const Color(0xFF5EAFA0) : const Color(0xFF252C2A)),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 17,
                color: selected ? const Color(0xFF5EAFA0) : const Color(0xFF252C2A),
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
          if (action != null) ...[
            Icon(action, color: const Color(0xFF5EAFA0), size: 18),
            const SizedBox(width: 24),
          ],
          if (count != null)
            Text(
              count!,
              style: const TextStyle(color: Color(0xFFADB6B2), fontSize: 14),
            ),
          if (trailing != null)
            Icon(trailing, color: const Color(0xFF5D6662), size: 20),
        ],
      ),
    );
  }
}

class _ProBadge extends StatelessWidget {
  const _ProBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFFF8F6EE),
        border: Border.all(color: const Color(0xFFE7DAC7)),
      ),
      child: const Center(
        child: Text(
          'PRO',
          style: TextStyle(
            color: Color(0xFFC0A779),
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF5EAFA0)
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke;
    const dash = 7.0;
    const gap = 7.0;
    final rect = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(8));
    final path = Path()..addRRect(rect);
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        canvas.drawPath(metric.extractPath(distance, distance + dash), paint);
        distance += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _NotebookCoverPainter extends CustomPainter {
  const _NotebookCoverPainter(this.palette);

  final List<Color> palette;

  @override
  void paint(Canvas canvas, Size size) {
    final base = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [palette.first, palette[1]],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, base);

    final foldPaint = Paint()..color = palette.last.withAlpha(190);
    final palePaint = Paint()..color = Colors.white.withAlpha(120);

    final lower = Path()
      ..moveTo(0, size.height * 0.66)
      ..lineTo(size.width, size.height * 0.44)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(lower, palePaint);

    final accent = Path()
      ..moveTo(size.width * 0.28, size.height)
      ..lineTo(size.width * 0.58, size.height * 0.52)
      ..lineTo(size.width * 0.84, size.height)
      ..close();
    canvas.drawPath(accent, foldPaint);

    final linePaint = Paint()
      ..color = Colors.white.withAlpha(130)
      ..strokeWidth = 1;
    for (var i = 0; i < 4; i++) {
      final y = size.height * 0.22 + i * 18;
      canvas.drawLine(
        Offset(size.width * 0.22, y),
        Offset(size.width * 0.78, y),
        linePaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _NotebookCoverPainter oldDelegate) {
    return oldDelegate.palette != palette;
  }
}

class _MountainScene extends StatelessWidget {
  const _MountainScene();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _MountainPainter(), child: const SizedBox.expand());
  }
}

class _MountainPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final sky = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0x00E4F5F1), Color(0xFFB9DDD5)],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, sky);

    void drawRidge(Color color, double base, List<double> peaks) {
      final path = Path()..moveTo(0, size.height);
      path.lineTo(0, size.height * base);
      for (var i = 0; i < peaks.length; i++) {
        final x = size.width * (i / (peaks.length - 1));
        path.lineTo(x, size.height * peaks[i]);
      }
      path.lineTo(size.width, size.height);
      path.close();
      canvas.drawPath(path, Paint()..color = color);
    }

    drawRidge(const Color(0xFF80B9AF), 0.72, [0.72, 0.68, 0.7, 0.62, 0.67]);
    drawRidge(const Color(0xFF5C9C92), 0.82, [0.82, 0.76, 0.8, 0.73, 0.79]);
    drawRidge(const Color(0xFF2F5E5A), 0.93, [0.93, 0.88, 0.9, 0.84, 0.89]);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
