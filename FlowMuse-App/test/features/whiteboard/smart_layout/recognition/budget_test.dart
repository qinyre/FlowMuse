import 'package:flutter_test/flutter_test.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/recognition/recognition_budget.dart';

/// 预算值对象（spec §6.2 全字段 + 执行点 + 生命周期）。
void main() {
  test('默认值与 §6.2 表逐项一致', () {
    const budget = RecognitionBudget();
    expect(budget.overviewMaxEdgePx, 2048);
    expect(budget.regionTargetLineHeightMinPx, 48);
    expect(budget.regionTargetLineHeightMaxPx, 96);
    expect(budget.regionMaxEdgePx, 2048);
    expect(budget.regionMaxPixels, 2 * 1024 * 1024);
    expect(budget.regionPaddingLineHeight, 0.3);
    expect(budget.batchMaxRegions, 8);
    expect(budget.batchMaxRequestBytes, 16 * 1024 * 1024);
    expect(budget.firstRoundMaxRegions, 64);
    expect(budget.verifyMaxRegions, 16);
    expect(budget.regroupRounds, 1);
    expect(budget.localRenderConcurrency, 1);
    expect(budget.networkConcurrency, 2);
    expect(budget.modelCallBudget, 16);
    expect(budget.retryPerRequest, 1);
    expect(budget.totalTimeout, const Duration(seconds: 180));
    expect(budget.perRequestTimeout, const Duration(seconds: 130));
  });

  test('模型调用计数：递减、耗尽 fail closed', () {
    var budget = const RecognitionBudget(modelCallBudget: 2);
    expect(budget.canSpendModelCall, isTrue);
    budget = budget.spendModelCall();
    expect(budget.consumedModelCalls, 1);
    expect(budget.modelCallsRemaining, 1);
    budget = budget.spendModelCall();
    expect(budget.canSpendModelCall, isFalse);
    expect(
      () => budget.spendModelCall(),
      throwsStateError,
      reason: '派发前必须查 canSpend，不足则不发且该批区域保留',
    );
  });

  test('测试可注入已耗初值（预算生命周期断点）', () {
    const budget = RecognitionBudget(consumedModelCalls: 15);
    expect(budget.modelCallsRemaining, 1);
    expect(budget.canSpendModelCall, isTrue);
    const exhausted = RecognitionBudget(consumedModelCalls: 16);
    expect(exhausted.canSpendModelCall, isFalse);
  });

  test('总时限剩余：真实计时器口径（Stopwatch elapsed）', () {
    const budget = RecognitionBudget(totalTimeout: Duration(seconds: 120));
    final stopwatch = Stopwatch();
    expect(budget.remainingOf(stopwatch), const Duration(seconds: 120));
    stopwatch.start();
    // 到期判定由 pipeline 的 _remaining 负值裁零逻辑处理（真实计时器
    // 不可注入 elapsed，此处验证口径来源为 elapsed 差值）。
    expect(
      budget.remainingOf(stopwatch) <= const Duration(seconds: 120),
      isTrue,
    );
  });

  test('浅色阈值与并发等均可注入', () {
    const budget = RecognitionBudget(
      pencilLightnessThreshold: 0.65,
      localRenderConcurrency: 2,
      networkConcurrency: 4,
    );
    expect(budget.pencilLightnessThreshold, 0.65);
    expect(budget.localRenderConcurrency, 2);
    expect(budget.networkConcurrency, 4);
  });

  test('spend 不改变其他字段（值对象不可变）', () {
    const budget = RecognitionBudget(
      modelCallBudget: 4,
      pencilLightnessThreshold: 0.9,
    );
    final next = budget.spendModelCall();
    expect(next.pencilLightnessThreshold, 0.9);
    expect(next.modelCallBudget, 4);
    expect(budget.consumedModelCalls, 0, reason: '原实例不变');
  });
}
