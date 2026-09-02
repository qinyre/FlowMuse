# -*- coding: utf-8 -*-
"""V3-004B 变更审计演练：golden-ledger 校验器 + 篡改/未登记/非法 rubric 版本三类拒绝演示。
全部变异只发生在内存，不写回任何真实文件。输出 gates/G0/change-control-drill.json。"""
import copy
import hashlib
import json
import os

import canonical

REPO = r'D:\Program\HarmonyOS\FlowMuse-smart-layout-refactor'
LEDGER = os.path.join(REPO, 'docs', '研发记录', 'evidence', 'smart-layout-v3', 'gates', 'G0', 'golden-ledger.json')
OUT = LEDGER.replace('golden-ledger.json', 'change-control-drill.json')


def file_sha(path):
    return hashlib.sha256(open(os.path.join(REPO, path), 'rb').read()).hexdigest()


def canonical_sha(obj):
    return canonical.canonical_sha(obj)


def validate_entry(entry, file_override=None):
    """校验一个 ledger 条目：文件 hash 实测相等 + 版本/hash 字段齐全 + rubric 只允许 V3-000B v1.0.0
    + evaluation_spec 条目的 content_sha256 必须与磁盘文件内部声明一致（防冒充已登记版本）。
    file_override: {path: 假想文件字节 hash}，用于演练篡改场景。"""
    errors = []
    if not entry.get('version') or not entry.get('file_sha256') or not entry.get('approved_by'):
        errors.append('entry_fields_missing')
    actual = (file_override or {}).get(entry['path'], file_sha(entry['path']))
    if actual != entry['file_sha256']:
        errors.append('file_hash_mismatch')
    if entry.get('kind') == 'rubric' and entry.get('version') != '1.0.0':
        errors.append('rubric_version_not_allowed')
    if entry.get('kind') == 'evaluation_spec':
        on_disk = json.load(open(os.path.join(REPO, entry['path']), encoding='utf-8'))
        if entry.get('content_sha256') != on_disk.get('content_sha256'):
            errors.append('post_hoc_amendment')
    return errors


def validate_ledger(ledger, file_override=None):
    errors = []
    names = set()
    for e in ledger.get('entries', []):
        key = (e.get('kind'), e.get('name'), e.get('version'))
        if key in names:
            errors.append('duplicate_entry:%s' % str(key))
        names.add(key)
        for err in validate_entry(e, file_override):
            errors.append('%s/%s@%s:%s' % (e.get('kind'), e.get('name'), e.get('version'), err))
    return errors


def main():
    ledger = json.load(open(LEDGER, encoding='utf-8'))
    runs = []

    # 1. 现状校验：全部条目与磁盘一致
    base_errors = validate_ledger(ledger)
    runs.append({'drill': 'ledger_baseline_validation', 'expected': 'valid',
                 'actual': 'valid' if not base_errors else base_errors,
                 'pass': not base_errors})

    # 2. 篡改演示：golden 文件内容一字段之差 → hash 变 → ledger 拒绝
    golden_path = [e for e in ledger['entries'] if e['kind'] == 'golden'][0]['path']
    original = json.load(open(os.path.join(REPO, golden_path), encoding='utf-8'))
    tampered = copy.deepcopy(original)
    tampered['layers'] = {'tampered': True}
    tampered_bytes = json.dumps(tampered, ensure_ascii=False, indent=1).encode('utf-8')
    tampered_hash = hashlib.sha256(tampered_bytes).hexdigest()
    errs = validate_ledger(ledger, file_override={golden_path: tampered_hash})
    hash_changed = tampered_hash != file_sha(golden_path)
    runs.append({'drill': 'golden_tamper_detection', 'path': golden_path,
                 'original_sha256': file_sha(golden_path)[:16],
                 'tampered_sha256': tampered_hash[:16],
                 'hash_changed': hash_changed,
                 'ledger_rejected': any('file_hash_mismatch' in e for e in errs),
                 'pass': hash_changed and any('file_hash_mismatch' in e for e in errs)})

    # 3. spec 变异演示：margin 0.10→0.12 → content_sha256 变 → 不可冒充已登记版本
    spec_entry = [e for e in ledger['entries'] if e['kind'] == 'evaluation_spec'][0]
    spec_path = spec_entry['path']
    spec = json.load(open(os.path.join(REPO, spec_path), encoding='utf-8'))
    mutated = copy.deepcopy(spec)
    for t in mutated['noninferiority_thresholds']:
        if t['test'] == 'T2':
            t['margin_rd'] = 0.12
    mutated_hash = canonical_sha({k: v for k, v in mutated.items() if k != 'content_sha256'})
    registered_hash = spec['content_sha256']
    # 未登记的新 content_sha256 硬套旧 version 1.0.0 → 校验器与磁盘内部声明比对后真实拒绝（post_hoc_amendment）
    fake_entry = copy.deepcopy(spec_entry)
    fake_entry['content_sha256'] = mutated_hash  # 保留 version 1.0.0 不变
    errs = validate_entry(fake_entry)
    runs.append({'drill': 'spec_mutation_detection', 'path': spec_path,
                 'registered_content_sha256': registered_hash[:16],
                 'mutated_content_sha256': mutated_hash[:16],
                 'hash_changed': mutated_hash != registered_hash,
                 'ledger_rejected': 'post_hoc_amendment' in errs,
                 'pass': mutated_hash != registered_hash and 'post_hoc_amendment' in errs})

    # 4. 非法 rubric 版本演示：v1.0.1 → policy 拒绝
    rubric_entry = copy.deepcopy([e for e in ledger['entries'] if e['kind'] == 'rubric'][0])
    rubric_entry['version'] = '1.0.1'
    errs = validate_entry(rubric_entry)
    runs.append({'drill': 'rubric_version_gate', 'attempted_version': '1.0.1',
                 'rejected': 'rubric_version_not_allowed' in errs,
                 'pass': 'rubric_version_not_allowed' in errs})

    # 5. 未审批条目演示：缺 approved_by → 拒绝
    no_approval = copy.deepcopy(spec_entry)
    no_approval.pop('approved_by')
    errs = validate_entry(no_approval)
    runs.append({'drill': 'unapproved_entry_gate', 'rejected': 'entry_fields_missing' in errs,
                 'pass': 'entry_fields_missing' in errs})

    ok = all(r['pass'] for r in runs)
    report = {
        'schema_version': '1.0.0',
        'artifact': 'golden-change-control-drill',
        'task': 'V3-004B',
        'ledger': {'path': 'gates/G0/golden-ledger.json',
                   'file_sha256': file_sha('docs/研发记录/evidence/smart-layout-v3/gates/G0/golden-ledger.json'),
                   'entries': len(ledger['entries'])},
        'acceptance_mapping': {
            '任何 spec/rubric/golden 变化都会改 hash': 'drill 2/3：golden 一字段之差与 spec margin 一字之差均实测改变 hash 且被 ledger 拒绝',
            '只引用 V3-000B rubric 版本': 'drill 4：rubric v1.0.1 登记被 policy 拒绝（仅允许 9408c037@1.0.0）',
            'golden 审批': 'drill 5：无 approved_by 的条目拒绝；既有条目审批记录指回 V3-000B/004A/003B/002C 任务证据',
        },
        'runs': runs,
        'status': 'passed' if ok else 'failed',
        'disclosure': {
            'panel_type': 'ai_synthetic',
            'human_validation_performed': False,
            'disclosure': 'HUMAN_VALIDATION_NOT_PERFORMED',
            'statement': '全部审批记录均指回 AI 代理任务的 panel/复审证据；不含真人审批。',
        },
    }
    with open(OUT, 'w', encoding='utf-8', newline='\n') as f:
        json.dump(report, f, ensure_ascii=False, indent=1)
        f.write('\n')
    print(json.dumps({'status': report['status'],
                      'ledger_sha256': report['ledger']['file_sha256'][:16],
                      'drills': {r['drill']: r['pass'] for r in runs}}, ensure_ascii=False))


if __name__ == '__main__':
    main()
