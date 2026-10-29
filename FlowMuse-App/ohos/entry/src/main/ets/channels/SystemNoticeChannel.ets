import { common, Want, wantAgent, WantAgent } from '@kit.AbilityKit';
import { notificationManager } from '@kit.NotificationKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { FlutterEngine, MethodCall, MethodChannel, MethodResult } from '@ohos/flutter_ohos';

export class SystemNoticeChannel {
  private static channel: MethodChannel | undefined;
  private static pending: string | undefined;
  private static ready: boolean = false;
  private ids: Map<string, number> = new Map<string, number>();
  private nextId: number = 1000000;
  private readonly context: common.UIAbilityContext;

  constructor(context: common.UIAbilityContext) {
    this.context = context;
  }

  register(engine: FlutterEngine): void {
    const channel = new MethodChannel(engine.getDartExecutor().getBinaryMessenger(), 'flow_muse/system_notice');
    SystemNoticeChannel.channel = channel;
    channel.setMethodCallHandler({
      onMethodCall: (call: MethodCall, result: MethodResult): void => {
        this.handle(call, result);
      }
    });
  }

  static enqueueWant(want: Want): void {
    const target = want.parameters?.flowMuseSystemNotice;
    if (typeof target !== 'string' || target.length > 1024) return;
    if (SystemNoticeChannel.ready) {
      SystemNoticeChannel.channel?.invokeMethod('onTap', target);
    } else {
      SystemNoticeChannel.pending = target;
    }
  }

  private async handle(call: MethodCall, result: MethodResult): Promise<void> {
    try {
      if (call.method === 'permission' || call.method === 'requestPermission') {
        if (call.method === 'requestPermission' && !await notificationManager.isNotificationEnabled()) {
          try {
            await notificationManager.requestEnableNotification(this.context);
          } catch (error) {
            if ((error as BusinessError).code !== 1600004) throw error;
          }
        }
        result.success(await notificationManager.isNotificationEnabled() ? 'granted' : 'denied');
      } else if (call.method === 'takePending') {
        SystemNoticeChannel.ready = true;
        const target = SystemNoticeChannel.pending;
        SystemNoticeChannel.pending = undefined;
        result.success(target ?? null);
      } else if (call.method === 'show') {
        await this.show(call.args as Map<string, Object>);
        result.success(null);
      } else if (call.method === 'cancel') {
        const tag = call.args as string;
        const id = this.ids.get(tag);
        if (id !== undefined) {
          await notificationManager.cancel(id);
          this.ids.delete(tag);
        }
        result.success(null);
      } else if (call.method === 'clear') {
        // This channel is currently the app's only notification publisher.
        await notificationManager.cancelAll();
        this.ids.clear();
        result.success(null);
      } else {
        result.notImplemented();
      }
    } catch (_error) {
      result.error('notification_unavailable', 'System notification unavailable', null);
    }
  }

  private async show(args: Map<string, Object>): Promise<void> {
    const tag = args.get('tag') as string;
    const target = args.get('target') as string;
    const title = args.get('title') as string;
    const body = args.get('body') as string;
    const expiry = args.get('expiresAt') as number;
    if (typeof tag !== 'string' || tag.length > 300 || typeof target !== 'string' || target.length > 1024 ||
      typeof title !== 'string' || title.length > 300 || typeof body !== 'string' || body.length > 1000 ||
      !Number.isSafeInteger(expiry) || expiry <= Date.now() || !await notificationManager.isNotificationEnabled()) {
      throw new Error('Notification unavailable');
    }
    const id = this.ids.get(tag) ?? ++this.nextId;
    this.ids.set(tag, id);
    const info: wantAgent.WantAgentInfo = {
      wants: [{
        bundleName: this.context.abilityInfo.bundleName,
        abilityName: this.context.abilityInfo.name,
        parameters: { flowMuseSystemNotice: target }
      }],
      actionType: wantAgent.OperationType.START_ABILITY,
      requestCode: id,
      actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG, wantAgent.WantAgentFlags.CONSTANT_FLAG]
    };
    const click = await new Promise<WantAgent>((resolve, reject) => {
      wantAgent.getWantAgent(info, (error: BusinessError, value: WantAgent) => {
        if (error) reject(new Error('Notification click unavailable'));
        else resolve(value);
      });
    });
    const request: notificationManager.NotificationRequest = {
      id: id,
      wantAgent: click,
      content: {
        notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
        normal: { title: title, text: body, additionalText: 'FlowMuse' }
      }
    };
    await notificationManager.publish(request);
  }

  dispose(): void {
    SystemNoticeChannel.ready = false;
    SystemNoticeChannel.channel?.setMethodCallHandler(null);
    SystemNoticeChannel.channel = undefined;
  }
}
