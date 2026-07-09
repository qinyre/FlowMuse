import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_router.dart';
import '../view_models/account_view_model.dart';

class VerifyEmailPage extends ConsumerStatefulWidget {
  const VerifyEmailPage({super.key, required this.token});

  final String token;

  @override
  ConsumerState<VerifyEmailPage> createState() => _VerifyEmailPageState();
}

class _VerifyEmailPageState extends ConsumerState<VerifyEmailPage> {
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) {
      return;
    }
    _started = true;
    Future.microtask(_verify);
  }

  Future<void> _verify() async {
    if (widget.token.isEmpty) {
      return;
    }
    try {
      await ref
          .read(accountViewModelProvider.notifier)
          .verifyEmail(widget.token);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final account = ref.watch(accountViewModelProvider);
    final colorScheme = Theme.of(context).colorScheme;
    final success = account.isAuthenticated;

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
                  success ? Icons.verified_user : Icons.mark_email_read,
                  size: 48,
                  color: success ? colorScheme.primary : colorScheme.secondary,
                ),
                const SizedBox(height: 18),
                Text(
                  success ? '邮箱已验证' : '正在验证邮箱',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                Text(
                  account.error ??
                      (success ? '你已登录 FlowMuse。' : '请稍候，正在完成账号验证。'),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                FilledButton(
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
