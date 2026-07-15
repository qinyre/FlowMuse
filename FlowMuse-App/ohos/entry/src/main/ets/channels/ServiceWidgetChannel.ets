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
      const empty: BindingPayload = {
        appName: 'FlowMuse',
        headline: '开始你的第一块白板',
        detail: '最近白板',
        buttonText: '打开资料库'
      };
      return empty;
    }
    const snapshot = JSON.parse(raw) as Snapshot;
    const date = new Date(snapshot.updatedAt);
    const hh = date.getHours().toString().padStart(2, '0');
    const mm = date.getMinutes().toString().padStart(2, '0');
    const payload: BindingPayload = {
      appName: 'FlowMuse',
      headline: snapshot.title,
      detail: `最近白板 · ${hh}:${mm}`,
      buttonText: '继续创作'
    };
    return payload;
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
        updatedAt: args['updatedAt'] as number,
      };
      const store = await preferences.getPreferences(this.context, STORE_NAME);
      await store.put(SNAPSHOT_KEY, JSON.stringify(snapshot));
      await store.flush();
      const rawIds = await store.get(FORM_IDS_KEY, '[]') as string;
      const ids = JSON.parse(rawIds) as string[];
      for (const formId of ids) {
        await ServiceWidgetChannel.updateFormById(this.context, formId);
      }
      result.success(null);
    } catch (err) {
      result.error('SERVICE_WIDGET_UPDATE_FAILED', JSON.stringify(err as BusinessError), null);
    }
  }
}
