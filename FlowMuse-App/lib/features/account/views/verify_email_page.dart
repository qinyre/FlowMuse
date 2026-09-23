import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_router.dart';
import '../view_models/account_view_model.dart';

class VerifyEmailPage extends ConsumerStatefulWidget {
  const VerifyEmailPage({super.key, required this.token, this.binding = false});

  final String token;
  final bool binding;

  @override
  ConsumerState<VerifyEmailPage> createState() => _VerifyEmailPageState();
}

class _VerifyEmailPageState extends ConsumerState<VerifyEmailPage> {
  bool _busy = false;
  bool _success = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Binding requires a deliberate click, so mail link scanners cannot confirm it.
    if (!widget.binding) Future.microtask(_verify);
  }

  Future<void> _verify() async {
    if (!mounted || _busy) return;
    if (widget.token.isEmpty) {
      setState(() => _error = '验证链接不完整，请重新发送验证邮件');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (widget.binding) {
        // This proves email ownership only. Never replace this browser's session.
        await ref
            .read(accountRepositoryProvider)
            .verifyEmailBinding(widget.token);
      } else {
        await ref
            .read(accountViewModelProvider.notifier)
            .verifyEmail(widget.token);
      }
      if (mounted) setState(() => _success = true);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(
                  _success ? Icons.verified_user : Icons.mark_email_read,
                  size: 48,
                  color: colorScheme.primary,
                ),
                const SizedBox(height: 18),
                Text(
                  _success ? '邮箱已验证' : (_busy ? '正在验证邮箱' : '确认邮箱'),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                Text(
                  _error ??
                      (_success
                          ? (widget.binding
                                ? '请回到发起绑定的 FlowMuse App，设置密码并完成绑定。'
                                : '你已登录 FlowMuse。')
                          : (widget.binding
                                ? '确认将此邮箱用于你刚刚在 FlowMuse 发起的绑定操作。若不是你本人操作，请关闭此页面。'
                                : '请稍候，正在完成账号验证。')),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                if (!_success && (!_busy || widget.binding))
                  FilledButton(
                    onPressed: _busy ? null : _verify,
                    child: Text(
                      _busy ? '验证中' : (widget.binding ? '确认此邮箱' : '重试'),
                    ),
                  ),
                if (!widget.binding)
                  TextButton(
                    onPressed: () => context.go(AppRoutes.library),
                    child: const Text('进入 FlowMuse'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
