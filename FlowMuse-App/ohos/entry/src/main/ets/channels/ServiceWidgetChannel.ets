import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { BusinessError } from '@kit.BasicServicesKit';
import { formBindingData, formProvider } from '@kit.FormKit';
import { FlutterEngine, MethodCall, MethodChannel, MethodResult } from '@ohos/flutter_ohos';

const STORE_NAME: string = 'recent_whiteboard_widget';
const SNAPSHOT_KEY: string = 'snapshot';
const FORM_IDS_KEY: string = 'form_ids';

interface Snapshot {
  noteId: string;
  title: string;
  updatedAt: number;
}

interface BindingPayload {
  appName: string;
  headline: string;
  detail: string;
  buttonText: string;
  buttonAction: string;
}

/**
 * Returns a Preferences instance accessible across processes.
 *
 * 关键修复：UIAbility 与 FormExtensionAbility 运行在不同进程，且各自的
 * ability context 解析出的 preferencesDir 不同（base/haps/<module>/preferences
 * vs base/preferences），导致两进程访问的不是同一个 Preferences 文件——
 * 主进程写的 snapshot 卡片进程永远读不到。改用 applicationContext 统一指向
 * base/preferences，确保两进程访问同一文件。
 *
 * 同时使用 GSKV 模式（API 18+）保证多进程并发读写安全。
 */
async function getStore(context: Context): Promise<preferences.Preferences> {
  const appContext = context.getApplicationContext();
  const gskvSupported = preferences.isStorageTypeSupported(preferences.StorageType.GSKV);
  const options: preferences.Options = gskvSupported
    ? { name: STORE_NAME, storageType: preferences.StorageType.GSKV }
    : { name: STORE_NAME };
  return await preferences.getPreferences(appContext, options);
}

export class ServiceWidgetChannel {
  private static channel: MethodChannel | null = null;
  private static pendingLaunchAction: string | null = null;

  private readonly context: Context;

  constructor(context: Context) {
    this.context = context;
  }

  register(flutterEngine: FlutterEngine): void {
    const channel = new MethodChannel(
      flutterEngine.getDartExecutor().getBinaryMessenger(),
      'flow_muse/service_widget'
    );
    ServiceWidgetChannel.channel = channel;
    channel.setMethodCallHandler({
      onMethodCall: (call: MethodCall, result: MethodResult): void => {
        if (call.method === 'updateLastWhiteboard') {
          void this.handleUpdate(call.args as Map<string, Object>, result);
          return;
        }
        if (call.method === 'takePendingLaunchAction') {
          result.success(ServiceWidgetChannel.pendingLaunchAction);
          ServiceWidgetChannel.pendingLaunchAction = null;
          return;
        }
        result.notImplemented();
      }
    });
  }

  static enqueueLaunchAction(action: string): void {
    ServiceWidgetChannel.pendingLaunchAction = action;
    ServiceWidgetChannel.channel?.invokeMethod('onLaunchActionEnqueued', null);
  }

  static async buildBindingPayload(context: Context): Promise<BindingPayload> {
    const store = await getStore(context);
    const raw = await store.get(SNAPSHOT_KEY, '') as string;
    console.info('[ServiceWidget] buildBindingPayload raw snapshot: ' + raw);
    if (!raw) {
      return {
        appName: 'FlowMuse',
        headline: '开始你的第一块白板',
        detail: '',
        buttonText: '立即创建',
        buttonAction: 'createNote'
      };
    }
    const snapshot = JSON.parse(raw) as Snapshot;
    console.info('[ServiceWidget] buildBindingPayload parsed: title=' + snapshot.title
      + ' updatedAt=' + snapshot.updatedAt);
    const detail = ServiceWidgetChannel.formatUpdatedAt(snapshot.updatedAt);
    return {
      appName: 'FlowMuse',
      headline: snapshot.title,
      detail,
      buttonText: '继续创作',
      buttonAction: 'resumeLastWhiteboard'
    };
  }

  private static formatUpdatedAt(updatedAt: number): string {
    const now = new Date();
    const date = new Date(updatedAt);
    const hh = date.getHours().toString().padStart(2, '0');
    const mm = date.getMinutes().toString().padStart(2, '0');
    const todayStr = now.toDateString();
    const dateStr = date.toDateString();
    if (dateStr === todayStr) {
      return `最近白板 · 今天 ${hh}:${mm}`;
    }
    const yesterday = new Date(now);
    yesterday.setDate(yesterday.getDate() - 1);
    if (dateStr === yesterday.toDateString()) {
      return `最近白板 · 昨天 ${hh}:${mm}`;
    }
    const month = (date.getMonth() + 1).toString();
    const day = date.getDate().toString();
    return `最近白板 · ${month}月${day}日`;
  }

  static async rememberFormId(context: Context, formId: string): Promise<void> {
    const store = await getStore(context);
    const raw = await store.get(FORM_IDS_KEY, '[]') as string;
    const ids = JSON.parse(raw) as string[];
    if (!ids.includes(formId)) {
      ids.push(formId);
      await store.put(FORM_IDS_KEY, JSON.stringify(ids));
      await store.flush();
    }
  }

  static async removeFormId(context: Context, formId: string): Promise<void> {
    const store = await getStore(context);
    const raw = await store.get(FORM_IDS_KEY, '[]') as string;
    const ids = (JSON.parse(raw) as string[]).filter((id) => id !== formId);
    await store.put(FORM_IDS_KEY, JSON.stringify(ids));
    await store.flush();
  }

  static async updateFormById(context: Context, formId: string): Promise<void> {
    const payload = await ServiceWidgetChannel.buildBindingPayload(context);
    const formData = formBindingData.createFormBindingData(payload as object);
    await formProvider.updateForm(formId, formData);
  }

  private async handleUpdate(
    args: Map<string, Object>,
    result: MethodResult,
  ): Promise<void> {
    try {
      const noteId = args.get('noteId') as string;
      const title = args.get('title') as string;
      const updatedAtRaw = args.get('updatedAt') as string;
      console.info('[ServiceWidget] handleUpdate raw: noteId=' + noteId
        + ' title=' + title + ' updatedAt=' + updatedAtRaw);
      const snapshot: Snapshot = {
        noteId: noteId,
        title: title,
        // updatedAt 以字符串传输（避开鸿蒙 MethodChannel 对 int64 的 BigInt
        // 解码问题），这里用 parseInt 还原为毫秒时间戳。
        updatedAt: parseInt(updatedAtRaw, 10),
      };
      console.info('[ServiceWidget] handleUpdate snapshot: noteId=' + snapshot.noteId
        + ' title=' + snapshot.title + ' updatedAt=' + snapshot.updatedAt);
      const store = await getStore(this.context);
      await store.put(SNAPSHOT_KEY, JSON.stringify(snapshot));
      await store.flush();
      // 诊断：读回验证写入是否成功
      const verifyRaw = await store.get(SNAPSHOT_KEY, '') as string;
      console.info('[ServiceWidget] handleUpdate verify after write: ' + verifyRaw);
      // 主进程（UIAbility）通知 FormExtensionAbility 进程重新加载。reloadAllForms
      // 会回调该进程的 onUpdateForm，由它在自己的进程内读取 snapshot 并调 updateForm。
      let reloadResult = 'unknown';
      try {
        await formProvider.reloadAllForms(this.context as common.UIAbilityContext);
        reloadResult = 'reloadAllForms ok';
      } catch (e) {
        reloadResult = 'reloadAllForms failed: ' + (e as BusinessError).message;
        // 回退：遍历 form_ids 直接刷新（主进程调 updateForm 也被官方支持）。
        const rawIds = await store.get(FORM_IDS_KEY, '[]') as string;
        console.info('[ServiceWidget] handleUpdate fallback form_ids: ' + rawIds);
        const ids = JSON.parse(rawIds) as string[];
        await Promise.allSettled(ids.map((formId) => ServiceWidgetChannel.updateFormById(this.context, formId)));
        reloadResult += ' | fallback updated ' + ids.length + ' forms';
      }
      console.info('[ServiceWidget] handleUpdate done: ' + reloadResult);
      result.success(reloadResult);
    } catch (err) {
      result.error('SERVICE_WIDGET_UPDATE_FAILED', JSON.stringify(err as BusinessError), null);
    }
  }
}
