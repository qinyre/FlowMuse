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
                      '键盘快捷键',
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
                    _helpSection(context, '工具', [
                      _shortcutRow(context, '抓手', 'H'),
                      _shortcutRow(context, '选择', '1 / V'),
                      _shortcutRow(context, '矩形', '2 / R'),
                      _shortcutRow(context, '菱形', '3 / D'),
                      _shortcutRow(context, '椭圆', '4 / O'),
                      _shortcutRow(context, '箭头', '5 / A'),
                      _shortcutRow(context, '直线', '6 / L'),
                      _shortcutRow(context, '自由绘制', '7 / P'),
                      _shortcutRow(context, '文字', '8 / T'),
                      _shortcutRow(context, '导入图片', '9'),
                      _shortcutRow(context, '橡皮擦', '0 / E'),
                      _shortcutRow(context, '画框', 'F'),
                      _shortcutRow(context, '激光笔', 'K'),
                      _shortcutRow(context, '锁定当前工具', 'Q'),
                    ]),
                    const SizedBox(height: 16),
                    _helpSection(context, '视图', [
                      _shortcutRow(context, '放大', '$mod + +'),
                      _shortcutRow(context, '缩小', '$mod + \u2212'),
                      _shortcutRow(context, '重置缩放', '$mod + 0'),
                      _shortcutRow(context, '缩放至适应', 'Shift + 1'),
                      _shortcutRow(context, '缩放至所选内容', 'Shift + 2'),
                      _shortcutRow(context, '向下 / 向上翻页', 'PgDn / PgUp'),
                      _shortcutRow(context, '向左 / 向右翻页', 'Shift + PgDn / PgUp'),
                      _shortcutRow(context, '切换网格', "$mod + '"),
                      _shortcutRow(context, '专注模式', 'Alt + Z'),
                      _shortcutRow(context, '查看模式', 'Alt + R'),
                      _shortcutRow(context, '切换主题', 'Alt + Shift + D'),
                    ]),
                    const SizedBox(height: 16),
                    _helpSection(context, '编辑', [
                      _shortcutRow(context, '撤销', '$mod + Z'),
                      _shortcutRow(
                        context,
                        '重做',
                        '$mod + Shift + Z / $mod + Y',
                      ),
                      _shortcutRow(context, '复制', '$mod + C'),
                      _shortcutRow(context, '粘贴', '$mod + V'),
                      _shortcutRow(context, '剪切', '$mod + X'),
                      _shortcutRow(context, '复制副本', '$mod + D'),
                      _shortcutRow(context, '全选', '$mod + A'),
                      _shortcutRow(context, '删除', 'Del / Backspace'),
                      _shortcutRow(context, '组合', '$mod + G'),
                      _shortcutRow(context, '取消组合', '$mod + Shift + G'),
                      _shortcutRow(context, '锁定 / 解锁', '$mod + Shift + L'),
                      _shortcutRow(context, '上移一层', '$mod + ]'),
                      _shortcutRow(context, '置于顶层', '$mod + Shift + ]'),
                      _shortcutRow(context, '下移一层', '$mod + ['),
                      _shortcutRow(context, '置于底层', '$mod + Shift + ['),
                      _shortcutRow(context, '微移', 'Arrows'),
                      _shortcutRow(context, '微移 10px', 'Shift + Arrows'),
                      _shortcutRow(
                        context,
                        '左 / 右对齐',
                        '$mod + Shift + \u2190 / \u2192',
                      ),
                      _shortcutRow(
                        context,
                        '顶部 / 底部对齐',
                        '$mod + Shift + \u2191 / \u2193',
                      ),
                      _shortcutRow(context, '增大字号', '$mod + Shift + >'),
                      _shortcutRow(context, '减小字号', '$mod + Shift + <'),
                      _shortcutRow(context, '描边颜色', 'S'),
                      _shortcutRow(context, '背景颜色', 'G'),
                      _shortcutRow(context, '字体选择', 'Shift + F'),
                      _shortcutRow(context, '水平翻转', 'Shift + H'),
                      _shortcutRow(context, '垂直翻转', 'Shift + V'),
                      _shortcutRow(context, '切换形状', 'Tab'),
                      _shortcutRow(context, '复制为 PNG', 'Shift + Alt + C'),
                      _shortcutRow(context, '复制样式', '$mod + Alt + C'),
                      _shortcutRow(context, '粘贴样式', '$mod + Alt + V'),
                      _shortcutRow(context, '粘贴为文本', '$mod + Shift + V'),
                      _shortcutRow(context, '重置画布', '$mod + Del'),
                      _shortcutRow(context, '编辑链接', '$mod + K'),
                      _shortcutRow(context, '完成直线', 'Enter'),
                      _shortcutRow(context, '创建流程图', '$mod + Arrow'),
                      _shortcutRow(context, '导航流程图', 'Alt + Arrow'),
                      _shortcutRow(context, '在画布中查找', '$mod + F'),
                      _shortcutRow(context, '取消选择', 'Escape'),
                    ]),
                    const SizedBox(height: 16),
                    _helpSection(context, '文件', [
                      _shortcutRow(context, '打开', '$mod + O'),
                      _shortcutRow(context, '保存', '$mod + S'),
                      _shortcutRow(context, '另存为', '$mod + Shift + S'),
                      _shortcutRow(context, '导出 PNG', '$mod + Shift + E'),
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
