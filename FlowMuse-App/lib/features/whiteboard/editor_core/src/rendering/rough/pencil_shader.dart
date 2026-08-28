import 'dart:ui';

import 'package:flutter/foundation.dart';

/// 铅笔纹理 Fragment Shader 管理器（参考 Saber pencil_shader.dart）。
///
/// 三态生命周期：
/// - 未初始化：[init] 尚未被调用；
/// - 可用：`shaders/pencil.frag`（经 flutter.shaders 注册，构建期由
///   impellerc 编译）加载成功；
/// - 不可用：加载失败且结果已缓存，重复 init 不会重试。
///
/// 实例策略：应用生命周期内只创建一个 [FragmentShader]，绘制时更新
/// uniform 后立即 drawPath（engine 逐 draw 快照 uniform，单实例跨元素
/// 安全）。[FragmentProgram] 无公开 dispose，由引擎 registry 持有至
/// shutdown，不做无意义的"释放"。
abstract class PencilShader {
  static FragmentProgram? _program;
  static bool _loadFailed = false;
  static Future<void>? _pending;
  static FragmentShader? _instance;
  static PencilShaderUniforms? _uniforms;

  /// 资产加载器；测试注入替身以断言并发 init 单次加载等生命周期行为。
  @visibleForTesting
  static Future<FragmentProgram> Function(String assetKey) loader =
      FragmentProgram.fromAsset;

  /// 是否已成功加载 shader（未初始化与失败都返回 false）。
  static bool get isAvailable => _program != null;

  /// 加载 shader 程序。应用启动时调用一次；并发调用只加载一次，
  /// 失败结果同样被缓存。任何平台失败都不抛异常（调用方无需兜底）。
  static Future<void> init() {
    if (_program != null || _loadFailed) return Future<void>.value();
    return _pending ??= _load().whenComplete(() => _pending = null);
  }

  static Future<void> _load() async {
    try {
      _program = await loader('shaders/pencil.frag');
      debugPrint('PencilShader: loaded successfully');
    } catch (e) {
      _loadFailed = true;
      // 日志只记状态与错误类型，不输出资产路径或绘制内容。
      debugPrint(
        'PencilShader: unavailable on this platform (${e.runtimeType})',
      );
    }
  }

  /// 返回应用生命周期内复用的绘制实例；不可用时返回 null。
  /// 每次绘制前先经 [uniforms] 更新 uniform，再立即 drawPath。
  static FragmentShader? acquire() {
    final program = _program;
    if (program == null) return null;
    return _instance ??= program.fragmentShader();
  }

  /// 按名绑定的 uniform 槽位（对 uniform 重排序免疫）。
  /// 与 [acquire] 返回的同一实例绑定一次后复用。
  static PencilShaderUniforms? uniforms() {
    final shader = acquire();
    if (shader == null) return null;
    return _uniforms ??= PencilShaderUniforms.bind(shader);
  }

  /// 测试结束释放：dispose 绘制实例并回到未初始化态。
  /// 不（也无法）释放 FragmentProgram 本体。
  @visibleForTesting
  static void resetForTesting() {
    _uniforms = null;
    _instance?.dispose();
    _instance = null;
    _program = null;
    _loadFailed = false;
    _pending = null;
  }
}

/// pencil.frag 的 uniform 槽位集合（按名绑定，见 SDK UniformFloatSlot）。
class PencilShaderUniforms {
  PencilShaderUniforms._({
    required UniformFloatSlot colorR,
    required UniformFloatSlot colorG,
    required UniformFloatSlot colorB,
    required UniformFloatSlot opacity,
    required UniformFloatSlot freq,
  }) : _colorR = colorR,
       _colorG = colorG,
       _colorB = colorB,
       _opacity = opacity,
       _freq = freq;

  final UniformFloatSlot _colorR;
  final UniformFloatSlot _colorG;
  final UniformFloatSlot _colorB;
  final UniformFloatSlot _opacity;
  final UniformFloatSlot _freq;

  static PencilShaderUniforms bind(FragmentShader shader) {
    return PencilShaderUniforms._(
      colorR: shader.getUniformFloat('uColor', 0),
      colorG: shader.getUniformFloat('uColor', 1),
      colorB: shader.getUniformFloat('uColor', 2),
      opacity: shader.getUniformFloat('uOpacity', 0),
      freq: shader.getUniformFloat('uFreq', 0),
    );
  }

  /// [color] 的 alpha 已包含元素 opacity 与笔刷 opacityScale；
  /// 输出保持预乘 alpha。
  void apply(Color color, double alpha, double freq) {
    _colorR.set(color.r);
    _colorG.set(color.g);
    _colorB.set(color.b);
    _opacity.set(alpha);
    _freq.set(freq);
  }
}
