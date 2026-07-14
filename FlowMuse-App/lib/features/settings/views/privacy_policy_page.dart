import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../shared/widgets/app_spacing.dart';

/// A standalone, in-app privacy policy page.  Pushed from the privacy settings
/// section instead of opening an external URL, so it works fully offline and
/// needs no website.
class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: '返回',
          icon: const Icon(LucideIcons.chevronLeft),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            }
          },
        ),
        title: const Text('隐私政策'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.pageInset,
          AppSpacing.sectionGap,
          AppSpacing.pageInset,
          AppSpacing.pageInset,
        ),
        children: [
          Text(
            'FlowMuse 隐私政策',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '更新日期：2026 年 7 月',
            style: theme.textTheme.bodySmall?.copyWith(color: muted),
          ),
          const SizedBox(height: AppSpacing.sectionGap),
          _PolicySection(
            icon: LucideIcons.database,
            title: '我们收集哪些数据',
            body: 'FlowMuse 以本地优先为设计原则。你的白板内容、笔记本、标签、'
                '主题偏好均存储在本机的加密 SQLite 数据库中，我们默认不会主动'
                '收集你的笔记内容。',
          ),
          _PolicySection(
            icon: LucideIcons.users,
            title: '账户信息',
            body: '当你注册账户时，我们会保存你的邮箱地址、昵称和头像。密码经过'
                '单向哈希处理后存储，任何人（包括我们）都无法看到你的明文密码。',
          ),
          _PolicySection(
            icon: LucideIcons.lock,
            title: '协作与同步',
            body: '在多人协作场景下，白板场景数据会在协作者之间通过端到端加密'
                '通道（AES-GCM-128）实时同步。服务器仅作为加密数据的转发中继，'
                '无法解读任何场景内容。',
          ),
          _PolicySection(
            icon: LucideIcons.wifi,
            title: '权限用途',
            body: '· 网络访问（INTERNET）：用于账户登录与实时协作同步\n'
                '· 网络状态（GET_NETWORK_INFO，鸿蒙端）：用于检测当前网络连接状态\n'
                '· 文件读取（按需）：仅在你主动导入图片、PDF 或备份文件时使用',
          ),
          _PolicySection(
            icon: LucideIcons.shieldCheck,
            title: '数据安全',
            body: '我们采用业界标准的加密措施保护你的账户与传输数据。本地数据'
                '依赖操作系统的应用沙箱进行隔离，其他应用默认无法访问。',
          ),
          _PolicySection(
            icon: LucideIcons.share2,
            title: '数据共享',
            body: '我们不会将你的个人信息出售或出租给第三方。除法律法规要求或'
                '为提供核心功能所必需的服务商（如服务器托管）外，我们不会与任何'
                '第三方共享你的数据。',
          ),
          _PolicySection(
            icon: LucideIcons.userX,
            title: '你的权利',
            body: '你可以随时在「账户与协作」中修改昵称、头像或退出登录。如需'
                '彻底删除账户和相关数据，请通过应用内反馈渠道联系我们。',
          ),
          _PolicySection(
            icon: LucideIcons.pencil,
            title: '政策变更',
            body: '若本政策有重大调整，我们会在应用更新说明中予以提示。继续使用'
                '即视为你认可更新后的隐私政策。',
          ),
          const SizedBox(height: AppSpacing.sectionGap),
          Text(
            '如有疑问，请通过应用内「其他设置 → 帮助与反馈」与我们联系。',
            style: theme.textTheme.bodySmall?.copyWith(color: muted),
          ),
          const SizedBox(height: AppSpacing.pageInset),
        ],
      ),
    );
  }
}

class _PolicySection extends StatelessWidget {
  const _PolicySection({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sectionGap),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 20, color: theme.colorScheme.primary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  body,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: muted,
                    height: 1.6,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
