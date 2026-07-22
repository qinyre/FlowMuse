import { common, Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { FlutterEngine, MethodCall, MethodChannel, MethodResult } from '@ohos/flutter_ohos';

type LaunchArgs = Map<string, Object>;

/**
 * 拉起系统浏览器或邮件应用。
 *
 * 背景:url_launcher 上游未提供鸿蒙实现(url_launcher_ohos 不在依赖中),
 * 直接调 launchUrl 会抛 MissingPluginException。这里按 HarmonyOS 官方指南
 * 用 startAbility + Want 实现等价能力:
 *   - http/https → action: ohos.want.action.viewData,系统浏览器接管
 *   - mailto     → action: ohos.want.action.sendToData,系统邮件应用接管
 * 参考:harmonyos-guides/应用间跳转/拉起指定类型的应用/start-email-apps-by-mailto.md
 */
export class UrlLauncherChannel {
  private readonly context: Context;

  constructor(context: Context) {
    this.context = context;
  }

  register(flutterEngine: FlutterEngine): void {
    const channel = new MethodChannel(
      flutterEngine.getDartExecutor().getBinaryMessenger(),
      'flow_muse/url_launcher'
    );
    channel.setMethodCallHandler({
      onMethodCall: (call: MethodCall, result: MethodResult): void => {
        if (call.method !== 'launchUrl') {
          result.notImplemented();
          return;
        }
        const uri = (call.args as LaunchArgs).get('uri') as string;
        if (uri === undefined || uri.length === 0) {
          result.success(false);
          return;
        }
        this.launch(uri)
          .then((ok: boolean) => result.success(ok))
          .catch((error: BusinessError) => {
            console.error(`UrlLauncher failed: ${error.code} ${error.message}`);
            result.success(false);
          });
      }
    });
  }

  private async launch(uri: string): Promise<boolean> {
    const lower = uri.toLowerCase();
    const want: Want = lower.startsWith('mailto:')
      ? { action: 'ohos.want.action.sendToData', uri: uri }
      : { action: 'ohos.want.action.viewData', uri: uri };
    const ctx = this.context as common.UIAbilityContext;
    try {
      await ctx.startAbility(want);
      return true;
    } catch (error) {
      // 若是显式拉起失败,退到 openLink 兜底(API 12+ 推荐路径)。
      const e = error as BusinessError;
      console.warn(`startAbility fallback to openLink: ${e.code} ${e.message}`);
      try {
        await ctx.openLink(uri, { appLinkingOnly: false });
        return true;
      } catch (e2) {
        const be = e2 as BusinessError;
        console.error(`openLink also failed: ${be.code} ${be.message}`);
        return false;
      }
    }
  }
}
