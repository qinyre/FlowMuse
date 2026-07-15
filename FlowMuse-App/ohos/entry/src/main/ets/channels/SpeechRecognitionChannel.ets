import { abilityAccessCtrl } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { speechRecognizer } from '@kit.CoreSpeechKit';
import { FlutterEngine, MethodCall, MethodChannel, MethodResult } from '@ohos/flutter_ohos';

type SpeechArgs = Map<string, ESObject>;

export class SpeechRecognitionChannel {
  private readonly context: Context;
  private channel: MethodChannel | null = null;
  private engine: speechRecognizer.SpeechRecognitionEngine | undefined = undefined;
  private generation: number = 0;
  private sessionId: string = '';
  private lastResult: string = '';

  constructor(context: Context) {
    this.context = context;
  }

  register(flutterEngine: FlutterEngine): void {
    this.channel = new MethodChannel(
      flutterEngine.getDartExecutor().getBinaryMessenger(),
      'flow_muse/speech_recognition'
    );
    this.channel.setMethodCallHandler({
      onMethodCall: (call: MethodCall, result: MethodResult): void => {
        const args = call.args as SpeechArgs;
        if (call.method === 'isAvailable') {
          result.success(true);
          return;
        }
        if (call.method === 'start') {
          const generation = (args?.get('generation') as number | undefined) ?? 0;
          const locale = (args?.get('locale') as string | undefined) ?? 'zh-CN';
          this.start(generation, locale)
            .then(() => result.success(null))
            .catch((error: BusinessError) => {
              this.sendError(generation, this.mapError(error.code, error.message), error.message ?? '');
              result.success(null);
            });
          return;
        }
        if (call.method === 'stop') {
          const generation = (args?.get('generation') as number | undefined) ?? 0;
          if (generation === this.generation && this.sessionId.length > 0) {
            this.engine?.finish(this.sessionId);
          }
          result.success(null);
          return;
        }
        if (call.method === 'cancel') {
          const generation = (args?.get('generation') as number | undefined) ?? 0;
          if (generation === this.generation) {
            this.release(true);
          }
          result.success(null);
          return;
        }
        if (call.method === 'dispose') {
          this.release(true);
          result.success(null);
          return;
        }
        result.notImplemented();
      }
    });
  }

  private async start(generation: number, locale: string): Promise<void> {
    this.release(true);
    this.generation = generation;
    this.sessionId = `flowmuse-${generation}-${Date.now()}`;
    this.lastResult = '';
    this.sendState(generation, 'starting');
    const permission = await abilityAccessCtrl.createAtManager().requestPermissionsFromUser(
      this.context,
      ['ohos.permission.MICROPHONE']
    );
    if (permission.authResults.length === 0 || permission.authResults[0] !== 0) {
      this.sendError(generation, 'permissionDenied', '麦克风权限被拒绝');
      return;
    }
    if (generation !== this.generation) {
      return;
    }
    this.engine = await this.createEngine(locale);
    this.setListener(generation);
    const audioInfo: speechRecognizer.AudioInfo = {
      audioType: 'pcm',
      sampleRate: 16000,
      soundChannel: 1,
      sampleBit: 16
    };
    const extraParams: Record<string, Object> = {
      'recognitionMode': 0,
      'vadBegin': 2000,
      'vadEnd': 3000,
      'maxAudioDuration': 60000
    };
    const startParams: speechRecognizer.StartParams = {
      sessionId: this.sessionId,
      audioInfo: audioInfo,
      extraParams: extraParams
    };
    this.engine.startListening(startParams);
  }

  private createEngine(locale: string): Promise<speechRecognizer.SpeechRecognitionEngine> {
    const extraParams: Record<string, Object> = {
      'locate': 'CN',
      'recognizerMode': 'short'
    };
    const params: speechRecognizer.CreateEngineParams = {
      language: locale,
      online: 1,
      extraParams: extraParams
    };
    return new Promise((resolve, reject) => {
      speechRecognizer.createEngine(
        params,
        (error: BusinessError, engine: speechRecognizer.SpeechRecognitionEngine) => {
          if (error) {
            reject(error);
          } else {
            resolve(engine);
          }
        }
      );
    });
  }

  private setListener(generation: number): void {
    const listener: speechRecognizer.RecognitionListener = {
      onStart: (): void => this.sendState(generation, 'listening'),
      onEvent: (): void => {},
      onResult: (_sessionId: string, result: speechRecognizer.SpeechRecognitionResult): void => {
        if (generation !== this.generation) {
          return;
        }
        const text = result.result?.trim() ?? '';
        if (text.length === 0) {
          return;
        }
        this.lastResult = text;
        this.sendResult(generation, text, false);
      },
      onComplete: (): void => {
        if (generation !== this.generation) {
          return;
        }
        if (this.lastResult.length > 0) {
          this.sendResult(generation, this.lastResult, true);
        }
        this.sendState(generation, 'idle');
        this.release(false);
      },
      onError: (_sessionId: string, code: number, message: string): void => {
        if (generation !== this.generation) {
          return;
        }
        this.sendError(generation, this.mapError(code, message), message);
        this.release(false);
      }
    };
    this.engine?.setListener(listener);
  }

  private release(cancel: boolean): void {
    if (cancel && this.sessionId.length > 0) {
      try {
        this.engine?.cancel(this.sessionId);
      } catch (error) {
        console.error(`Speech cancel failed: ${error}`);
      }
    }
    try {
      this.engine?.shutdown();
    } catch (error) {
      console.error(`Speech shutdown failed: ${error}`);
    }
    this.engine = undefined;
    this.sessionId = '';
    this.lastResult = '';
  }

  private sendState(generation: number, state: string): void {
    if (generation !== this.generation) {
      return;
    }
    this.channel?.invokeMethod('onState', new Map<string, Object>([
      ['state', state],
      ['generation', generation]
    ]));
  }

  private sendResult(generation: number, text: string, isFinal: boolean): void {
    if (generation !== this.generation) {
      return;
    }
    this.channel?.invokeMethod('onResult', new Map<string, Object>([
      ['text', text],
      ['final', isFinal],
      ['generation', generation]
    ]));
  }

  private sendError(generation: number, code: string, message: string): void {
    if (generation !== this.generation) {
      return;
    }
    this.channel?.invokeMethod('onError', new Map<string, Object>([
      ['code', code],
      ['message', message],
      ['generation', generation]
    ]));
  }

  private mapError(code: number, message: string): string {
    if (code === 201 || message.toLowerCase().includes('permission')) {
      return 'permissionDenied';
    }
    if (code === 1002200006) {
      return 'busy';
    }
    if (code === 1002200001 || code === 1002200008) {
      return 'unavailable';
    }
    return 'unknown';
  }
}
