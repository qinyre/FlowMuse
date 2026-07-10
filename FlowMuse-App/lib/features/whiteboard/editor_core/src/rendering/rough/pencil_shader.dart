import 'dart:ui';

import 'package:flutter/foundation.dart';

/// 铅笔纹理 Fragment Shader 管理器（参考 Saber pencil_shader.dart）。
///
/// 使用 FragmentProgram 在 GPU 上给铅笔笔画叠加纸张纹理噪点，
/// 实现类纸铅笔效果。
///
/// 注意：需要平台支持 dart:ui 的 FragmentProgram.fromAsset()。
/// 鸿蒙端可能不支持，此时 [init] 会抛异常，调用方应优雅降级。
abstract class PencilShader {
  static FragmentProgram? _program;

  /// 是否已成功加载 shader。
  static bool get isAvailable => _program != null;

  /// 加载 shader 程序。需在应用启动时调用一次。
  /// 鸿蒙端若不支持 FragmentProgram.fromAsset，会抛异常。
  static Future<void> init() async {
    if (_program != null) return;
    try {
      _program = await FragmentProgram.fromAsset('shaders/pencil.frag');
      debugPrint('PencilShader: loaded successfully');
    } catch (e) {
      debugPrint('PencilShader: unsupported on this platform ($e)');
    }
  }

  /// 创建一个新的 FragmentShader 实例。
  /// 如果平台不支持，返回 null。
  static FragmentShader? create() {
    return _program?.fragmentShader();
  }
}
