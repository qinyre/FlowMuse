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
          void this.handleUpdate(call.args as Record<string, Object>, result);
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
    const store = await preferences.getPreferences(context, STORE_NAME);
    const raw = await store.get(SNAPSHOT_KEY, '') as string;
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
    const store = await preferences.getPreferences(context, STORE_NAME);
    const raw = await store.get(FORM_IDS_KEY, '[]') as string;
    const ids = JSON.parse(raw) as string[];
    if (!ids.includes(formId)) {
      ids.push(formId);
      await store.put(FORM_IDS_KEY, JSON.stringify(ids));
      await store.flush();
    }
  }

  static async removeFormId(context: Context, formId: string): Promise<void> {
    const store = await preferences.getPreferences(context, STORE_NAME);
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
    args: Record<string, Object>,
    result: MethodResult,
  ): Promise<void> {
    try {
      const snapshot: Snapshot = {
        noteId: args['noteId'] as string,
        title: args['title'] as string,
        // updatedAt comes from Flutter's Dart side as float64 to avoid BigInt
        // encoding issues over MethodChannel (int64 is decoded as BigInt in
        // ArkTS which cannot be JSON.stringify'd). Number() handles both
        // number and any edge-case type the bridge might produce.
        updatedAt: Number(args['updatedAt'] as Object),
      };
      const store = await preferences.getPreferences(this.context, STORE_NAME);
      await store.put(SNAPSHOT_KEY, JSON.stringify(snapshot));
      await store.flush();
      const rawIds = await store.get(FORM_IDS_KEY, '[]') as string;
      const ids = JSON.parse(rawIds) as string[];
      await Promise.allSettled(ids.map((formId) => ServiceWidgetChannel.updateFormById(this.context, formId)));
      result.success(null);
    } catch (err) {
      result.error('SERVICE_WIDGET_UPDATE_FAILED', JSON.stringify(err as BusinessError), null);
    }
  }
}
