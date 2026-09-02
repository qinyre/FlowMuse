# -*- coding: utf-8 -*-
"""V3-004B 决策演练 runner：5 个合成场景 → 通过/拒绝(×2)/数据不足/缺失 四态结论。
场景合成只依赖 evaluation-spec.json 的注册参数（n、margin、预算行），不复制常量。
输出 drill-report.json（无时间戳，双跑确定性）。"""
import hashlib
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from spec_decision import evaluate, load_spec, spec_hashes  # noqa: E402


def build_scenarios(spec):
    n = spec['denominators']['D_SAMPLES']['values']['development']
    sb = spec['benchmark_budget']['stage_budgets']
    snap = [b for b in sb if b['stage'] == 'snapshot'][0]
    peak = [b for b in sb if 'peak_rss_mb_max' in b][0]['peak_rss_mb_max']

    # 基础向量（确定性）：v2 在样本 5,11,17,23,29,35,41 违规；v3 在 29 违规（v2 子集；
    # 2/48 时 T2 的 bootstrap p≈0.0501 恰压 Holm α/1=0.05 线，取 1/48 使 pass 场景远离边界）
    v2_major_idx = {5, 11, 17, 23, 29, 35, 41}
    v3_major_idx = {29}
    ai_major_idx = set()

    def flags(idx):
        return [1 if i in idx else 0 for i in range(n)]

    def rubric(crit_idx, maj_idx):
        # 与失败计数负相关：无违规 4~5 分、每违规 −1 档（≥1 保底）
        vals = []
        for i in range(n):
            f = (1 if i in crit_idx else 0) + (1 if i in maj_idx else 0)
            vals.append(max(1, 5 - f))
        return vals

    crit_none = [0] * n
    v3_major = flags(v3_major_idx)
    ai_major = flags(ai_major_idx)
    v2_major = flags(v2_major_idx)

    base_system_pass = {
        'v3': {'critical': crit_none, 'major': v3_major, 'minor': [0] * n,
               'rubric_overall': rubric(set(), v3_major_idx)},
        'ai_surrogate': {'critical': crit_none, 'major': ai_major, 'minor': [0] * n,
                         'rubric_overall': rubric(set(), set())},
        'v2_naive_reflow': {'critical': crit_none, 'major': v2_major, 'minor': [0] * n,
                            'rubric_overall': rubric(set(), v2_major_idx)},
    }
    bench_ok = {'p50_ms': snap['p50_ms_max'] - 10, 'p95_ms': snap['p95_ms_max'] - 30,
                'peak_rss_mb': peak - 100, 'timeout': False,
                'budget': {'p50_ms_max': snap['p50_ms_max'], 'p95_ms_max': snap['p95_ms_max'],
                           'peak_rss_mb_max': peak}}
    inputs_ok = {'bench_env_hash_ok': True}

    # reject-critical：样本 7 出现 1 个 critical
    sys_crit = json.loads(json.dumps(base_system_pass))
    sys_crit['v3']['critical'][7] = 1
    sys_crit['v3']['rubric_overall'][7] = 1

    # reject-stat：v3 12/48 major（劣于 margin 路径）
    sys_stat = json.loads(json.dumps(base_system_pass))
    big = set(range(3, 51, 4))  # 12 个样本
    sys_stat['v3']['major'] = flags(big)
    sys_stat['v3']['rubric_overall'] = rubric(set(), big)

    # T6 退化分支：v3 全零失败码 → Spearman 无定义 → construct_check_indeterminate（仍可为 pass）
    sys_t6ind = json.loads(json.dumps(base_system_pass))
    sys_t6ind['v3']['rubric_overall'] = [5] * n

    return {
        'pass_expected': {
            'split': 'development', 'samples': n, 'system': base_system_pass,
            'bench': bench_ok, 'inputs': inputs_ok, 'expected_outcome': 'pass'},
        'pass_t6_indeterminate': {
            'split': 'development', 'samples': n, 'system': sys_t6ind,
            'bench': bench_ok, 'inputs': inputs_ok, 'expected_outcome': 'pass',
            'expected_t6_status': 'construct_check_indeterminate'},
        'reject_critical': {
            'split': 'development', 'samples': n, 'system': sys_crit,
            'bench': bench_ok, 'inputs': inputs_ok, 'expected_outcome': 'reject'},
        'reject_statistical': {
            'split': 'development', 'samples': n, 'system': sys_stat,
            'bench': bench_ok, 'inputs': inputs_ok, 'expected_outcome': 'reject'},
        'insufficient_samples': {
            'split': 'development', 'samples': n - 1, 'system': base_system_pass,
            'bench': bench_ok, 'inputs': inputs_ok, 'expected_outcome': 'insufficient'},
        'missing_env_rejected': {
            'split': 'development', 'samples': n, 'system': base_system_pass,
            'bench': None, 'inputs': {'bench_env_hash_ok': False}, 'expected_outcome': 'missing'},
    }


def main():
    spec = load_spec()
    scenarios = build_scenarios(spec)
    runs = []
    all_match = True
    for name, sc in scenarios.items():
        expected = sc.pop('expected_outcome')
        expected_t6 = sc.pop('expected_t6_status', None)
        result = evaluate(sc, spec)
        match = result['outcome'] == expected
        if expected_t6 is not None:
            match = match and result['tests'].get('T6', {}).get('status') == expected_t6
        all_match = all_match and match
        runs.append({'scenario': name, 'expected_outcome': expected,
                     'expected_t6_status': expected_t6,
                     'actual_outcome': result['outcome'], 'match': match,
                     'tests': result['tests'], 'error_codes': result['error_codes']})

    report = {
        'schema_version': '1.0.0',
        'artifact': 'evaluation-spec-decision-drill',
        'task': 'V3-004B',
        'driver': {
            'implementation': 'tasks/V3-004B/artifacts/spec_decision.py（python 参考实现；Dart EvaluationSpec/GateZeroEvaluator 消费方按 manifest 归属后续任务）',
            'spec_content_sha256': spec['content_sha256'],
            'spec_file_sha256': spec_hashes()['file_sha256'],
            'bootstrap': spec['confidence_intervals']['paired_diff'],
            'prng': spec['confidence_intervals']['prng'],
            'stream_order': 'E1→E2→E3→T6（同一 splitmix64 流不重置）',
            'holm_family': spec['multiple_comparisons']['family_F1_members'],
        },
        'outcome_taxonomy': {
            'pass': 'T1 硬规则 ∧ F1(Holm) ∧ T5 预算 全部成立',
            'reject': '进入统计但任一不成立（critical>0 / Holm 或点估计失败 / 预算超限）',
            'insufficient': '输入可载入但注册前提不成立（样本数≠D_SAMPLES 登记值等）',
            'missing': '必需输入缺失或被 RR-1~6 拒绝（无统计；error_codes 记录 RR 码）',
        },
        'runs': runs,
        'status': 'passed' if all_match else 'failed',
        'disclosure': {
            'panel_type': 'ai_synthetic',
            'human_validation_performed': False,
            'disclosure': 'HUMAN_VALIDATION_NOT_PERFORMED',
            'statement': '本演练全部使用合成结果，仅验证 EvaluationSpec 决策程序的四态结论与注册规则执行；不构成任何系统真实评估结论。T6 相关性为 score–AI-surrogate 失败计数相关性（合成数据演练），不得外推为 score-human 相关性；真实相关性按 spec 属 G3 报告。',
        },
    }
    out = os.path.join(HERE, 'drill-report.json')
    with open(out, 'w', encoding='utf-8', newline='\n') as f:
        json.dump(report, f, ensure_ascii=False, indent=1)
        f.write('\n')
    print(json.dumps({'status': report['status'],
                      'outcomes': {r['scenario']: r['actual_outcome'] for r in runs},
                      'drill_report_sha256': hashlib.sha256(open(out, 'rb').read()).hexdigest()},
                     ensure_ascii=False))


if __name__ == '__main__':
    main()
