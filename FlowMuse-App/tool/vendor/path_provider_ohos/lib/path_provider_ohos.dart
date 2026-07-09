// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/services.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

/// The Ohos implementation of [PathProviderPlatform].
///
/// This class implements the `package:path_provider` functionality for Ohos.
class PathProviderOhos extends PathProviderPlatform {
  /// The method channel used to interact with the native platform.
  final MethodChannel _channel = const MethodChannel('plugins.flutter.io/path_provider');

  /// Registers this class as the default instance of [PathProviderPlatform].
  static void registerWith() {
    PathProviderPlatform.instance = PathProviderOhos();
  }

  @override
  Future<String?> getTemporaryPath() async {
    final String? path = await _channel.invokeMethod<String>('getTemporaryDirectory');
    return path;
  }

  @override
  Future<String?> getApplicationSupportPath() async {
    final String? path = await _channel.invokeMethod<String>('getApplicationSupportDirectory');
    return path;
  }

  @override
  Future<String?> getApplicationDocumentsPath() async {
    final String? path = await _channel.invokeMethod<String>('getApplicationDocumentsDirectory');
    return path;
  }

  @override
  Future<String?> getApplicationCachePath() async {
    final String? path = await _channel.invokeMethod<String>('getApplicationCacheDirectory');
    return path;
  }

  @override
  Future<String?> getLibraryPath() async {
    final String? path = await _channel.invokeMethod<String>('getLibraryDirectory');
    return path;
  }

  @override
  Future<String?> getExternalStoragePath() {
    throw UnsupportedError('Functionality not available on HarmonyOS');
  }

  @override
  Future<List<String>?> getExternalCachePaths() {
    throw UnsupportedError('Functionality not available on HarmonyOS');
  }

  @override
  Future<List<String>?> getExternalStoragePaths({StorageDirectory? type}) {
    throw UnsupportedError('Functionality not available on HarmonyOS');
  }

  @override
  Future<String?> getDownloadsPath() {
    throw UnsupportedError('Functionality not available on HarmonyOS');
  }
}
