# -*- coding: utf-8 -*-
"""V3-004B：EvaluationSpec 决策程序的可执行演练（python 参考实现）。

严格由 docs/研发记录/specs/smart-layout-v3/evaluation-spec.json 驱动：指标/阈值/规则
全部运行时读取，不复制常量。结论四态：
  pass        — T1 硬规则 ∧ F1 族(Holm) ∧ T5 预算 全部成立
  reject      — 进入统计但任一不成立（含 critical>0）
  insufficient— 输入可载入但注册前提不成立（样本数≠D_SAMPLES、无评分样本等）
  missing     — 必需输入缺失或被 RR-1~6 拒绝（无统计，error_code 列出）
"""
import hashlib
import json
import os

REPO = r'D:\Program\HarmonyOS\FlowMuse-smart-layout-refactor'
SPEC_PATH = os.path.join(REPO, 'docs', '研发记录', 'specs', 'smart-layout-v3', 'evaluation-spec.json')


def load_spec():
    with open(SPEC_PATH, encoding='utf-8') as f:
        return json.load(f)


class SplitMix64:
    """spec.confidence_intervals.prng 规定：splitmix64(seed=20260831)。"""

    def __init__(self, seed):
        self.state = seed & 0xFFFFFFFFFFFFFFFF

    def next_uint64(self):
        self.state = (self.state + 0x9E3779B97F4A7C15) & 0xFFFFFFFFFFFFFFFF
        z = self.state
        z = ((z ^ (z >> 30)) * 0xBF58476D1CE4E5B9) & 0xFFFFFFFFFFFFFFFF
        z = ((z ^ (z >> 27)) * 0x94D049BB133111EB) & 0xFFFFFFFFFFFFFFFF
        return z ^ (z >> 31)

    def next_float(self):
        return self.next_uint64() / 2.0 ** 64


def bootstrap_diff(diffs, b, lower_side, threshold, prng):
    """配对差 bootstrap：返回 (point_est, p_one_sided)。
    lower_side=True: H1 为 diff<threshold（lower_better），p=P(diff_boot>=threshold)。
    lower_side=False: H1 为 diff>threshold（higher_better），p=P(diff_boot<=threshold)。"""
    n = len(diffs)
    if n == 0:
        raise ValueError('no samples')
    point = sum(diffs) / n
    if all(d == diffs[0] for d in diffs):
        boot = [diffs[0]] * b  # 退化：经验分布全常数 → CI=[c,c]（spec degenerate 条款）
    else:
        boot = []
        for _ in range(b):
            s = 0.0
            for _ in range(n):
                s += diffs[prng.next_uint64() % n]
            boot.append(s / n)
    if lower_side:
        p = sum(1 for x in boot if x >= threshold) / b
    else:
        p = sum(1 for x in boot if x <= threshold) / b
    return point, p


def ranks(values):
    """平均秩（Spearman 并列处理）。"""
    order = sorted(range(len(values)), key=lambda i: values[i])
    r = [0.0] * len(values)
    i = 0
    while i < len(order):
        j = i
        while j + 1 < len(order) and values[order[j + 1]] == values[order[i]]:
            j += 1
        avg = (i + j) / 2.0 + 1.0
        for k in range(i, j + 1):
            r[order[k]] = avg
        i = j + 1
    return r


def pearson(a, b):
    n = len(a)
    ma, mb = sum(a) / n, sum(b) / n
    cov = sum((x - ma) * (y - mb) for x, y in zip(a, b))
    va = sum((x - ma) ** 2 for x in a) ** 0.5
    vb = sum((y - mb) ** 2 for y in b) ** 0.5
    if va == 0 or vb == 0:
        return None  # 并列常数 → 无定义
    return cov / (va * vb)


def spearman(a, b):
    return pearson(ranks(a), ranks(b))


def evaluate(results, spec=None):
    """results 结构：
    {
      "split": "development",
      "samples": n,
      "system": {"v3": {"critical": [..n], "major": [..n], "rubric_overall": [..n]},
                  "ai_surrogate": {...}, "v2_naive_reflow": {...}},
      "bench": {"env_ok": bool, "p50_ms": ..., "p95_ms": ..., "peak_rss_mb": ..., "budget": {...}} | null,
      "inputs": {"bench_env_hash_ok": bool}
    }
    返回 {"outcome": ..., "tests": {...}, "error_codes": [...]}"""
    if spec is None:
        spec = load_spec()
    rng_seed = int(spec['confidence_intervals']['paired_diff'].split('seed=')[1].split('，')[0])
    b = int(spec['confidence_intervals']['paired_diff'].split('B=')[1].split('，')[0])
    error_codes = []

    # ---- RR-3/RR-4/missing 前置 ----
    if not results.get('inputs', {}).get('bench_env_hash_ok', False):
        error_codes.append('benchmark_environment_mismatch')
    n_reg = spec['denominators']['D_SAMPLES']['values'][results.get('split', 'development')]
    if results.get('samples') != n_reg:
        error_codes.append('denominator_not_fixed')
    sys_res = results.get('system')
    if not sys_res or not all(k in sys_res for k in ('v3', 'ai_surrogate', 'v2_naive_reflow')):
        error_codes.append('metric_not_registered')

    # T6 输入（构念效度）缺 rubric 向量时也按 insufficient 处理；
    # 对照系（ai/v2）缺任一必需向量 → 程序输入不完整 → missing（守卫先于 KeyError）
    v3 = (sys_res or {}).get('v3') or {}
    ai = (sys_res or {}).get('ai_surrogate') or {}
    v2 = (sys_res or {}).get('v2_naive_reflow') or {}
    required = ('critical', 'major', 'rubric_overall')
    if any(k not in v3 or len(v3.get(k, [])) == 0 for k in required):
        error_codes.append('evaluation_inputs_missing')
    if any(k not in s or len(s.get(k, [])) == 0 for s in (ai, v2) for k in ('major', 'rubric_overall')):
        error_codes.append('evaluation_inputs_missing')

    if error_codes:
        missing_like = any(c in ('benchmark_environment_mismatch', 'metric_not_registered',
                                 'evaluation_inputs_missing') for c in error_codes)
        return {
            'outcome': 'missing' if missing_like else 'insufficient',
            'tests': {},
            'error_codes': sorted(set(error_codes)),
        }
    if results['samples'] != n_reg:
        return {'outcome': 'insufficient', 'tests': {}, 'error_codes': ['denominator_not_fixed']}

    n = results['samples']
    tests = {}
    # ---- T1 硬规则（先于一切统计）----
    crit_total = sum(1 for c in v3['critical'] if c)
    tests['T1'] = {'family': 'hard_rule', 'critical_total': crit_total, 'pass': crit_total == 0}

    # ---- F1 族（bootstrap 流序：E1→E2→E3，同 PRNG 不重置）----
    prng = SplitMix64(rng_seed)
    ni = {x['test']: x for x in spec['noninferiority_thresholds']}
    sup = {x['test']: x for x in spec['superiority_thresholds']}

    maj_v3 = [1 if m else 0 for m in v3['major']]
    maj_ai = [1 if m else 0 for m in ai['major']]
    maj_v2 = [1 if m else 0 for m in v2['major']]
    d_ai = [a - b_ for a, b_ in zip(maj_v3, maj_ai)]
    d_v2 = [a - b_ for a, b_ in zip(maj_v3, maj_v2)]
    d_rb = [a - b_ for a, b_ in zip(v3['rubric_overall'], ai['rubric_overall'])]

    margin2 = float(ni['T2']['margin_rd'])
    p_est_e1, p2 = bootstrap_diff(d_ai, b, True, margin2, prng)
    tests['T2'] = {'family': 'F1', 'estimand': 'E1', 'point': p_est_e1, 'p': p2,
                   'point_ok': p_est_e1 < margin2}
    boundary4 = float(sup['T4']['boundary'])  # 优效边界读自 spec（当前=0）
    _, p4 = bootstrap_diff(d_v2, b, True, boundary4, prng)  # H1: RD<boundary → lower_side
    rd_v2 = sum(d_v2) / n
    tests['T4'] = {'family': 'F1', 'estimand': 'E2', 'point': rd_v2, 'p': p4,
                   'point_ok': rd_v2 < boundary4}
    margin3 = float(ni['T3']['margin_mean'])
    p_est_e3, p3 = bootstrap_diff(d_rb, b, False, margin3, prng)
    tests['T3'] = {'family': 'F1', 'estimand': 'E3', 'point': p_est_e3, 'p': p3,
                   'point_ok': p_est_e3 > margin3}

    # Holm（F1，单侧 α 从 spec 校正条款解析：当前 '族错误率 α=0.05（单侧）'）
    import re as _re
    alpha = float(_re.search(r'α=([0-9.]+)', spec['multiple_comparisons']['correction']).group(1))
    f1 = [(tid, tests[tid]['p']) for tid in ('T2', 'T3', 'T4')]
    f1_sorted = sorted(f1, key=lambda x: x[1])
    m = len(f1_sorted)
    holm_pass = {}
    for k, (tid, p) in enumerate(f1_sorted):
        holm_pass[tid] = p < alpha / (m - k + 1 - 1)  # α/(m-k+1)，k 从 0 起
    # Holm step-down：一旦失败，其后全部失败
    failed = False
    for tid, _ in f1_sorted:
        if failed or not holm_pass[tid]:
            holm_pass[tid] = False
            failed = True
    for tid, p in f1:
        tests[tid]['holm_pass'] = holm_pass[tid]
        tests[tid]['established'] = bool(holm_pass[tid] and tests[tid]['point_ok'])

    # ---- T5 预算（确定性）----
    bench = results.get('bench')
    t5_ok = bench is not None and all([
        bench.get('p50_ms', float('inf')) <= bench['budget']['p50_ms_max'],
        bench.get('p95_ms', float('inf')) <= bench['budget']['p95_ms_max'],
        bench.get('peak_rss_mb', float('inf')) <= bench['budget']['peak_rss_mb_max'],
        bench.get('timeout', False) is False,
    ])
    tests['T5'] = {'family': 'perf', 'pass': bool(t5_ok)}

    # ---- T6 构念效度（PRNG 流位于 E1/E2/E3 之后）----
    fail_counts = [c + m_ + mi_ for c, m_, mi_ in
                   zip([1 if x else 0 for x in v3['critical']],
                       [1 if x else 0 for x in v3['major']],
                       [1 if x else 0 for x in v3.get('minor', [0] * n)])]
    rho = spearman(v3['rubric_overall'], fail_counts)
    if rho is None or all(x == fail_counts[0] for x in fail_counts):
        tests['T6'] = {'family': 'construct', 'status': 'construct_check_indeterminate',
                       'note': '失败码计数全并列（如全 0）→ ρ 无定义（spec degenerate 条款）'}
    else:
        boots = []
        idx = list(range(n))
        for _ in range(b):
            smp = [idx[prng.next_uint64() % n] for _ in range(n)]
            r = spearman([v3['rubric_overall'][i] for i in smp], [fail_counts[i] for i in smp])
            if r is not None:
                boots.append(r)
        p6 = sum(1 for x in boots if x >= 0) / len(boots) if boots else 1.0
        tests['T6'] = {'family': 'construct', 'rho': rho, 'p': p6,
                       'supported': bool(p6 < alpha and rho < 0),
                       'status': 'supported' if (p6 < alpha and rho < 0) else 'caveat'}

    outcome = 'pass' if (tests['T1']['pass'] and all(tests[t]['established'] for t in ('T2', 'T3', 'T4'))
                         and tests['T5']['pass']) else 'reject'
    return {'outcome': outcome, 'tests': tests, 'error_codes': []}


def spec_hashes():
    with open(SPEC_PATH, 'rb') as f:
        return {'file_sha256': hashlib.sha256(f.read()).hexdigest(),
                'content_sha256': load_spec()['content_sha256']}


if __name__ == '__main__':
    print(json.dumps(spec_hashes(), ensure_ascii=False))
