import 'package:flutter/material.dart';

import '../../../../shared/widgets/app_spacing.dart';

class CreateRoomDialog extends StatefulWidget {
  const CreateRoomDialog({super.key});

  @override
  State<CreateRoomDialog> createState() => _CreateRoomDialogState();
}

class _CreateRoomDialogState extends State<CreateRoomDialog> {
  int _limit = 0;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('创建协作房间'),
    scrollable: true,
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('将当前笔记白板同步到协作房间。拥有房间信息的人可以加入并一起编辑。'),
        const SizedBox(height: AppSpacing.sectionGap),
        DropdownButtonFormField<int>(
          initialValue: _limit,
          decoration: const InputDecoration(labelText: '在线人数上限'),
          items: [
            for (final limit in const [0, 2, 4, 8, 16, 32])
              DropdownMenuItem(
                value: limit,
                child: Text(limit == 0 ? '不限人数' : '$limit 人'),
              ),
          ],
          onChanged: (value) => setState(() => _limit = value ?? 0),
        ),
        const SizedBox(height: AppSpacing.controlGap),
        const Text('包含房主；同一账号的不同浏览器或设备分别计数。'),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () => Navigator.of(context).pop(_limit),
        child: const Text('创建房间'),
      ),
    ],
  );
}
