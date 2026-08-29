import 'dart:math' as math;
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

  /// 测试注入：替代 [FragmentProgram.fragmentShader] 的实例创建步骤，
  /// 用于断言实例创建失败会永久降级、不逐帧重试。
  @visibleForTesting
  static FragmentShader Function(FragmentProgram program)?
  instanceFactoryForTesting;

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
    try {
      final factory = instanceFactoryForTesting;
      return _instance ??= factory != null
          ? factory(program)
          : program.fragmentShader();
    } catch (e) {
      // 实例创建失败与 uniform 失败同入一条降级链：清空 program/
      // instance/uniforms 后 [acquire] 恒返回 null，绝不逐帧重试。
      disablePermanently(e);
      return null;
    }
  }

  /// 与 [acquire] 返回的同一实例绑定一次后复用；绑定失败按不可用降级
  /// （绘制路径走确定性颗粒），绝不让异常逃进绘制帧。
  static PencilShaderUniforms? uniforms() {
    final shader = acquire();
    if (shader == null) return null;
    try {
      return _uniforms ??= PencilShaderUniforms.bind(shader);
    } catch (e) {
      disablePermanently(e);
      debugPrint('PencilShader: uniform bind failed (${e.runtimeType})');
      return null;
    }
  }

  /// 运行时失败（加载后的实例创建、uniform 绑定/写入等任何引擎层异常）
  /// 的永久降级：清理实例与缓存，此后 [acquire]/[uniforms] 恒返回
  /// null，绘制走确定性颗粒路径，不再逐帧重试。
  static void disablePermanently(Object cause) {
    _loadFailed = true;
    _uniforms = null;
    _instance?.dispose();
    _instance = null;
    _program = null;
    debugPrint('PencilShader: runtime failure, fallback to grain path '
        '(${cause.runtimeType})');
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
    instanceFactoryForTesting = null;
  }
}

/// pencil.frag 的 uniform 槽位集合。
///
/// 按声明序下标绑定（setFloat），不按名：真机实测 Android 引擎产物
/// 未填充按名查找所需的 uniform 元数据（Web 正常），按名绑定抛
/// "No uniform named uColor" 并逐帧杀死整块画布。下标 = pencil.frag
/// 的 uniform 声明序：uColor(vec3) 占 0-2、uOpacity=3、uFreq=4——
/// 调整 shader 声明顺序必须同步修改此处。
class PencilShaderUniforms {
  PencilShaderUniforms._(this._shader)
    : _colorR = 0,
      _colorG = 1,
      _colorB = 2,
      _opacity = 3,
      _freq = 4;

  final FragmentShader _shader;
  final int _colorR;
  final int _colorG;
  final int _colorB;
  final int _opacity;
  final int _freq;

  static PencilShaderUniforms bind(FragmentShader shader) {
    return PencilShaderUniforms._(shader);
  }

  /// 写入 uniform（调用方随后立即 drawPath）。返回是否成功；任何引擎层
  /// 异常（如槽位越界）都判定该平台 shader 运行时不可用：永久清理实例
  /// 转入确定性颗粒降级并返回 false——异常绝不抛进绘制帧，也绝不逐帧
  /// 重试。
  bool apply(Color color, double alpha, double freq) {
    try {
      _shader
        ..setFloat(_colorR, color.r)
        ..setFloat(_colorG, color.g)
        ..setFloat(_colorB, color.b)
        ..setFloat(_opacity, alpha)
        ..setFloat(_freq, freq);
      return true;
    } catch (e) {
      PencilShader.disablePermanently(e);
      return false;
    }
  }
}

/// 铅笔纹理降级路径的确定性伪随机（issue #5 T5）。
///
/// 由首点坐标、笔宽与点序号派生，不依赖 Random/时间——同输入两次重绘
/// 逐笔一致；几何或宽度不同的笔迹纹理分布不同。
abstract final class PencilGrainHash {
  static double hash(double a, double b, double c, int index) {
    final x = a * 12.9898 + b * 78.233 + c * 37.719 + index * 3.717;
    final s = math.sin(x) * 43758.5453;
    return s - s.floorToDouble();
  }
}
