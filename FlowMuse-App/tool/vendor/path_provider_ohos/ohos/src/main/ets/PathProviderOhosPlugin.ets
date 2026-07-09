/*
 * Copyright (c) 2024 OpenHarmony Flutter Community.
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 *
 * HarmonyOS implementation of the path_provider Flutter plugin.
 * Handles MethodChannel calls on `plugins.flutter.io/path_provider` and
 * returns application sandbox directory paths.
 */

import common from '@ohos.app.ability.common';
import {
  FlutterPlugin,
  FlutterPluginBinding,
  Log,
  MethodCall,
  MethodCallHandler,
  MethodChannel,
  MethodResult,
} from '@ohos/flutter_ohos';

const TAG = "PathProviderOhosPlugin";
const CHANNEL_NAME = "plugins.flutter.io/path_provider";

export default class PathProviderOhosPlugin implements FlutterPlugin, MethodCallHandler {
  private channel: MethodChannel | null = null;
  private context: common.Context | null = null;

  getUniqueClassName(): string {
    return "PathProviderOhosPlugin";
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.context = binding.getApplicationContext();
    this.channel = new MethodChannel(
      binding.getBinaryMessenger(),
      CHANNEL_NAME
    );
    this.channel.setMethodCallHandler(this);
    Log.i(TAG, "PathProviderOhosPlugin attached to engine");
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    if (this.channel != null) {
      this.channel.setMethodCallHandler(null);
      this.channel = null;
    }
    this.context = null;
    Log.i(TAG, "PathProviderOhosPlugin detached from engine");
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    if (this.context == null) {
      result.error("NO_CONTEXT", "Application context is null", null);
      return;
    }

    switch (call.method) {
      case 'getTemporaryDirectory':
        result.success(this.context.tempDir);
        break;

      case 'getApplicationSupportDirectory':
        // filesDir is the closest equivalent to ApplicationSupportDirectory on HarmonyOS
        // It maps to /data/storage/el2/base/haps/<bundle>/files
        result.success(this.context.filesDir);
        break;

      case 'getApplicationDocumentsDirectory':
        // filesDir is also used for documents on HarmonyOS
        // since there's no separate documents concept in the app sandbox
        result.success(this.context.filesDir);
        break;

      case 'getApplicationCacheDirectory':
        result.success(this.context.cacheDir);
        break;

      case 'getLibraryDirectory':
        // HarmonyOS has no direct equivalent to Library directory.
        // Use filesDir as a fallback.
        result.success(this.context.filesDir);
        break;

      default:
        Log.w(TAG, `Method not implemented: ${call.method}`);
        result.notImplemented();
        break;
    }
  }
}
