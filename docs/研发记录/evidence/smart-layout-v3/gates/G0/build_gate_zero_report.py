# -*- coding: utf-8 -*-
"""V3-004C：Gate 0 开发证据包构建器（确定性，可从空报告目录一条命令重建）。

用法（仓库根）：
  python docs/研发记录/evidence/smart-layout-v3/gates/G0/build_gate_zero_report.py
输出：同目录 gate-zero-report.json（无时间戳，双跑逐字节一致；退出码 0=全部引用可解析且 hash 相符）。
"""
import hashlib
import json
import os
import subprocess
import sys

REPO = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', '..', '..', '..', '..'))
ROOT = 'docs/研发记录/evidence/smart-layout-v3'


def sha(rel):
    p = os.path.join(REPO, rel)
    if not os.path.isfile(p):
        return None
    return hashlib.sha256(open(p, 'rb').read()).hexdigest()


def ref(rel, expected=None, note=''):
    h = sha(rel)
    return {
        'path': rel,
        'sha256': h,
        'expected_sha256': expected,
        'resolved': h is not None and (expected is None or h == expected),
        'note': note,
    }


def main():
    ev = 'docs/研发记录/evidence/smart-layout-v3'
    spec_dir = 'docs/研发记录/specs/smart-layout-v3'
    pool = ev + '/datasets/synthetic-pool-v2'
    tool = 'FlowMuse-App/tool/smart_layout_v3'

    bench_internal = json.load(open(os.path.join(REPO, tool, 'benchmark', 'benchmark-spec.json'), encoding='utf-8'))
    spec_internal = json.load(open(os.path.join(REPO, spec_dir, 'evaluation-spec.json'), encoding='utf-8'))
    ledger = json.load(open(os.path.join(REPO, ev, 'gates/G0/golden-ledger.json'), encoding='utf-8'))
    tbr = json.load(open(os.path.join(REPO, ev, 'baseline/ai-surrogate/three-baseline-report.json'), encoding='utf-8'))
    noop = json.load(open(os.path.join(REPO, ev, 'baseline/no-op/baseline-run.json'), encoding='utf-8'))
    v2 = json.load(open(os.path.join(REPO, ev, 'baseline/v2/baseline-run.json'), encoding='utf-8'))
    pman = json.load(open(os.path.join(REPO, pool + '/dataset-manifest.json'), encoding='utf-8'))

    components = {
        'rubric': ref(ev + '/tasks/V3-000B/artifacts/rubric.json',
                      '9408c03728adbbbfa91c72c1f605d4755a44641ec1e5aee804bc264c814e0060',
                      'AI 代理 rubric v1.0.0（V3-000B，双盲评 192/192 一致）'),
        'evaluation_spec': {
            **ref(spec_dir + '/evaluation-spec.json',
                  'e159862495f2b70116a38fbdd4a17e8f863ea16ae307b95d35a6617454210b1f',
                  'EvaluationSpec v1.0.0 预注册冻结（V3-004A，3 轮双盲 panel）'),
            'content_sha256': spec_internal['content_sha256'],
            'content_sha256_ok': spec_internal['content_sha256'] == '83dc663e5f7eee107c40f528df555a45e86a52c2a097bf4afa908171635ef303',
        },
        'benchmark_spec': {
            **ref(tool + '/benchmark/benchmark-spec.json',
                  'dbc00bc413ec02f80339ffd87a33dbc98d265c5518833a012da7ef9eb24be42f',
                  '基准口径 V3-001B（content_sha256=' + bench_internal['content_sha256'][:8] + '…）'),
            'content_sha256': bench_internal['content_sha256'],
        },
        'dataset_pool': ref(pool + '/dataset-manifest.json',
                            'd062a8e839da318cdb3edf29dc03009f3608bf27d332d08fa81d03d68b5a2158',
                            'synthetic-pool-v2 ' + str(len(pman['samples'])) + ' 样本（合成+许可，real_user_content 拒绝）'),
        'splits': {
            'development': {**ref(ev + '/datasets/splits/development/manifest.json',
                                  '1419710948c5199e332427185fda94c3d823d2c93e102d2004732099c9e2a63d'), 'n': 48},
            'validation': {**ref(ev + '/datasets/splits/validation/manifest.json',
                                 '152c9a0e1691c49ccb484f1eeba1250fd29d8769c957f10f4ea7bf1d4f18f983'), 'n': 18},
            'frozen_holdout': {**ref(ev + '/datasets/splits/frozen_holdout/manifest.json',
                                     '8d08d8028da86c94d72541e09f626d1014c5574d5b5f4359a81cbf6fb5e9739d'), 'n': 19},
        },
        'annotations_frozen_manifest': ref(ev + '/datasets/annotations/frozen-manifest.json',
                                           'afc4e451957d6bb703bc838926eff4954eb7dcad344c804d891b9187e04585a4',
                                           '冻结标签清单 v1.0.1（V3-002C，v1.0.0 作废记录在案）'),
        'baselines': {
            'no_op_run': {**ref(ev + '/baseline/no-op/baseline-run.json'), 'run_hash': noop.get('run_hash'), 'policy': 'no_op'},
            'v2_naive_reflow_run': {**ref(ev + '/baseline/v2/baseline-run.json'), 'run_hash': v2.get('run_hash'), 'policy': 'v2_naive_reflow'},
            'three_baseline_report': ref(ev + '/baseline/ai-surrogate/three-baseline-report.json',
                                         '8b8cf4158bb8d42a5911a020903f9ac3340f059cea6dbac488f22b0f2d4e61df',
                                         'AI surrogate 整理基线（V3-003B，双代理零分歧零重放失配，修改总数 '
                                         + str(tbr['layers']['overall']['ai_surrogate']['modification_count_total']) + '）'),
        },
        'golden_ledger': ref(ev + '/gates/G0/golden-ledger.json',
                             '6bf7ae7d69ac93a642138f428e7c1ac04d00292b5a82e5aee5ff751e804a6621',
                             str(len(ledger['entries'])) + ' 条目（rubric/evaluation-spec/three-baseline/frozen-manifest）'),
        'preregistration': ref(ev + '/gates/G0/preregistration.json',
                                note='EvaluationSpec 预注册记录（3 轮 panel+1 仲裁）'),
        'spec_validation': ref(ev + '/gates/G0/spec-validation.json', note='spec 40 项机器校验'),
        'decision_drill': ref(ev + '/tasks/V3-004B/artifacts/drill-report.json',
                              '6e370fa87bb464ab845ed1f3a2e6961bdf1698b910aa9cce07b450769b723ed1',
                              '决策程序四态演练（V3-004B）'),
        'change_control_drill': ref(ev + '/gates/G0/change-control-drill.json',
                                     'b5760517fddbf0bd274da8029ecf9f5d776fb8e3aa926b6aaa7685fe4e80e2f8',
                                     '变更审计演练（V3-004B）'),
    }

    def all_resolved(node):
        if isinstance(node, dict):
            if 'resolved' in node and 'path' in node:
                return node['resolved']
            return all(all_resolved(v) for v in node.values() if v is not None)
        return True

    resolved_ok = all_resolved(components) and components['evaluation_spec']['content_sha256_ok']

    report = {
        'schema_version': '1.0.0',
        'artifact': 'smart-layout-v3-gate-zero-report',
        'task': 'V3-004C',
        'gate': 'G0',
        'builder': 'gates/G0/build_gate_zero_report.py（本文件所在目录清空后可一条命令重建：python docs/研发记录/evidence/smart-layout-v3/gates/G0/build_gate_zero_report.py）',
        'status': 'frozen' if resolved_ok else 'broken',
        'components': components,
        'reproduction_commands': [
            {'component': 'dataset admission+split（V3-002A/B）',
             'command': 'cd FlowMuse-App && dart run tool/smart_layout_v3/dataset/split_cli.dart <in> <out>（详见 tasks/V3-002B/commands.json）'},
            {'component': '双盲标注/仲裁/冻结（V3-002C）',
             'command': 'cd FlowMuse-App && dart run tool/smart_layout_v3/dataset/annotation_cli.dart <a> <b> <rulings|-> <out>（详见 tasks/V3-002C/commands.json）'},
            {'component': 'no-op 与 v2 自动基线（V3-003A）',
             'command': 'cd FlowMuse-App && dart run tool/smart_layout_v3/baseline/baseline_cli.dart ../../docs/研发记录/evidence/smart-layout-v3/datasets/synthetic-pool-v2 <policy> <out_dir>（policy=no_op|v2_naive_reflow）'},
            {'component': 'AI surrogate 双代理整理+三基线并表（V3-003B）',
             'command': 'cd FlowMuse-App && dart run tool/smart_layout_v3/baseline/panel_cli.dart <evidence_root> <executor_run_id>'},
            {'component': 'spec 校验（V3-004A）',
             'command': 'python docs/研发记录/evidence/smart-layout-v3/tasks/V3-004B/artifacts/canonical.py（canonical 口径）+ gates/G0/spec-validation.json 40 checks'},
            {'component': '决策程序与变更审计演练（V3-004B）',
             'command': 'python docs/研发记录/evidence/smart-layout-v3/tasks/V3-004B/artifacts/drill_runner.py && python docs/研发记录/evidence/smart-layout-v3/tasks/V3-004B/artifacts/change_control_drill.py'},
            {'component': 'Gate 0 证据包（本文件）',
             'command': 'python docs/研发记录/evidence/smart-layout-v3/gates/G0/build_gate_zero_report.py'},
        ],
        'gate_decision': {
            'decision': 'development_gate_frozen',
            'authorizes': '继续 Phase 1+ 开发（G1 起按 evaluation-spec 预注册口径评估）',
            'does_not_authorize': '生产发布、应用商店上架、真实用户数据接入',
            'rationale': 'Phase 0 全部开发证据（rubric/spec/benchmark/数据集/三基线/变更控制）hash 可解析且互相钉定；三基线数字：no_op 47/85 违规、v2 11/85（dev split 7/48）、ai_surrogate 0/85',
        },
        'panel_disclosure': {
            'panel_type': 'ai_surrogate',
            'human_validation_performed': False,
            'disclosure': 'HUMAN_VALIDATION_NOT_PERFORMED',
            'statement': 'Gate 0 为 development Gate：全部证据由 AI 代理任务的机器校验、双盲 panel 与独立复审产生，不含真人验证；通过仅授权继续开发，不授权生产发布（生产发布需 V3-700A 外部批准包与 FINAL）。',
        },
    }

    out = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'gate-zero-report.json')
    with open(out, 'w', encoding='utf-8', newline='\n') as f:
        json.dump(report, f, ensure_ascii=False, indent=1)
        f.write('\n')
    print(json.dumps({'status': report['status'], 'output': 'gates/G0/gate-zero-report.json',
                      'sha256': hashlib.sha256(open(out, 'rb').read()).hexdigest()},
                     ensure_ascii=False))
    sys.exit(0 if resolved_ok else 2)


if __name__ == '__main__':
    main()
