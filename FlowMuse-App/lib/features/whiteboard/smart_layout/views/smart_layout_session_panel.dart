import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../session/smart_layout_real_wiring.dart';
import '../session/smart_layout_session_state.dart';
import '../session/smart_layout_session_view_model.dart';
import 'smart_layout_session_view.dart';

/// V3 智能排版会话面板（V3-505C 真实入口宿主）：以独立
/// [ProviderScope] 注入真实依赖束（[SmartLayoutRealSessionScope.
/// dependencies]，无 fake provider），承载 [SmartLayoutSessionView]。
///
/// 非模态：无 showDialog/Navigator 弹层，关闭即卸载——面板销毁时
/// provider 作用域随之销毁，候选渲染资源由 ViewModel dispose 释放，
/// 不存在模态死锁或弹层残留。关闭前若会话在途则先取消（同步、
/// 不等待 future，零在途残留）。
class SmartLayoutSessionPanel extends StatelessWidget {
  const SmartLayoutSessionPanel({
    super.key,
    required this.scope,
    required this.onClose,
  });

  final SmartLayoutRealSessionScope scope;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(12),
      color: Theme.of(context).colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 16),
        child: ProviderScope(
          overrides: [
            smartLayoutSessionDependenciesProvider.overrideWithValue(
              scope.dependencies,
            ),
          ],
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _PanelHeader(onClose: onClose),
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
            final phase = ref
                .read(smartLayoutSessionViewModelProvider)
                .phase;
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
