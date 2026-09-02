import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../session/smart_layout_real_wiring.dart';
import '../session/smart_layout_session_state.dart';
import '../session/smart_layout_session_view_model.dart';
import 'smart_layout_session_view.dart';

/// V3 智能排版会话面板（V3-505C 真实入口宿主）：以独立容器注入真实
/// 依赖束（[SmartLayoutRealSessionScope.dependencies]，无 fake
/// provider），承载 [SmartLayoutSessionView]。
///
/// 必须用 [UncontrolledProviderScope] 承载手工 [ProviderContainer]，
/// 不能用嵌套 [ProviderScope] 的 `overrides`：Riverpod 3 把未声明
/// `dependencies` 的 provider 解析到根容器，嵌套 override 不生效——
/// deps 默认工厂抛 UnimplementedError 并被根容器缓存为错误态，面板
/// 整块渲染成 ErrorWidget（release 灰框）。手工容器是自己的根，
/// override 恒生效。
///
/// 非模态：无 showDialog/Navigator 弹层，关闭即卸载——面板销毁时
/// 手工容器随之 dispose，候选渲染资源由 ViewModel dispose 释放，
/// 不存在模态死锁或弹层残留。关闭前若会话在途则先取消（同步、
/// 不等待 future，零在途残留）。
class SmartLayoutSessionPanel extends StatefulWidget {
  const SmartLayoutSessionPanel({
    super.key,
    required this.scope,
    required this.onClose,
  });

  final SmartLayoutRealSessionScope scope;
  final VoidCallback onClose;

  @override
  State<SmartLayoutSessionPanel> createState() =>
      _SmartLayoutSessionPanelState();
}

class _SmartLayoutSessionPanelState extends State<SmartLayoutSessionPanel> {
  late final ProviderContainer _container;

  @override
  void initState() {
    super.initState();
    _container = ProviderContainer(
      overrides: [
        smartLayoutSessionDependenciesProvider.overrideWithValue(
          widget.scope.dependencies,
        ),
      ],
    );
  }

  @override
  void dispose() {
    _container.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(12),
      color: Theme.of(context).colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 16),
        child: UncontrolledProviderScope(
          container: _container,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _PanelHeader(onClose: widget.onClose),
              const SizedBox(height: 4),
              const SmartLayoutSessionView(),
            ],
          ),
        ),
      ),
    );
  }
}

class _PanelHeader extends ConsumerWidget {
  const _PanelHeader({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      children: [
        const Expanded(
          child: Text(
            '智能排版（v3 实时预览）',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        IconButton(
          tooltip: '关闭排版面板',
          onPressed: () {
            final phase =
                ref.read(smartLayoutSessionViewModelProvider).phase;
            if (phase == SmartLayoutSessionPhase.analyzing ||
                phase == SmartLayoutSessionPhase.reviewing ||
                phase == SmartLayoutSessionPhase.applying) {
              ref
                  .read(smartLayoutSessionViewModelProvider.notifier)
                  .cancel(reason: 'panel-closed');
            }
            onClose();
          },
          icon: const Icon(Icons.close),
        ),
      ],
    );
  }
}
