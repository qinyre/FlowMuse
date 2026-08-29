import 'dart:ui';

import 'package:flow_muse/features/whiteboard/editor_core/src/rendering/rough/pencil_shader.dart';
import 'package:flutter_test/flutter_test.dart';

/// PencilShader 生命周期（Issue #5 T1 / A23）。
///
/// 说明：走真实 `FragmentProgram.fromAsset` 的用例依赖 flutter test 的
/// 资产构建（impellerc 编译 shaders 段产物到 unit_test_assets）——这本身
/// 就是 A22 的测试环境闭环证据。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    PencilShader.loader = FragmentProgram.fromAsset;
    PencilShader.resetForTesting();
  });

  test('并发 init 只加载一次', () async {
    // Given: 计数包装的真实 loader
    var loads = 0;
    PencilShader.loader = (assetKey) {
      loads++;
      return FragmentProgram.fromAsset(assetKey);
    };

    // When: 两个 init 并发
    await Future.wait([PencilShader.init(), PencilShader.init()]);

    // Then: 只加载一次；真实编译产物在 test 环境可加载（A22 闭环）
    expect(loads, 1);
    expect(
      PencilShader.isAvailable,
      isTrue,
      reason: 'shaders 段产物经 impellerc 编译后应可加载',
    );
  });

  test('加载失败后状态缓存，第二次 init 不重试', () async {
    // Given: 总是失败的 loader
    var loads = 0;
    PencilShader.loader = (assetKey) {
      loads++;
      throw StateError('load failed');
    };

    // When: 两次 init
    await PencilShader.init();
    await PencilShader.init();

    // Then: 只尝试一次，失败被缓存且不抛异常
    expect(loads, 1);
    expect(PencilShader.isAvailable, isFalse);
    expect(PencilShader.acquire(), isNull);
    expect(PencilShader.uniforms(), isNull);
  });

  test('成功后 acquire 复用同一实例，uniforms 按名绑定', () async {
    await PencilShader.init();

    final first = PencilShader.acquire();
    expect(first, isNotNull);
    expect(
      PencilShader.acquire(),
      same(first),
      reason: '应用生命周期内复用单实例，不得每元素 fragmentShader()',
    );

    final uniforms = PencilShader.uniforms();
    expect(uniforms, isNotNull);
    // 应用 uniform 不抛异常（按名绑定存在 uColor/uOpacity/uFreq）
    uniforms!.apply(const Color(0xFF336699), 0.68, 0.7);
  });

  test('resetForTesting 释放实例并回到未初始化态', () async {
    await PencilShader.init();
    expect(PencilShader.isAvailable, isTrue);

    PencilShader.resetForTesting();

    expect(PencilShader.isAvailable, isFalse);
    expect(PencilShader.acquire(), isNull);
    // 清态后可重新加载（真实 loader）
    await PencilShader.init();
    expect(PencilShader.isAvailable, isTrue);
  });
}
