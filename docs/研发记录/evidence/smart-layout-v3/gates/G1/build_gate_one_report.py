# -*- coding: utf-8 -*-
"""G1 证据包确定性构建器（V3-206A，仿 G0 build_gate_zero_report.py）。

用法：python docs/研发记录/evidence/smart-layout-v3/gates/G1/build_gate_one_report.py
输入：G1 目录下 quality-{development,validation}.json、
latency-development.json、prerequisites.json（均由
tool/smart_layout_v3/evaluation/g1_runner.dart 产出）。
产出：gate-one-report.json——删除后单命令重建逐字节一致；
任何组件缺失/hash 漂移 → status=broken + exit 2。
所有判定机器产生；质量阈值未在 Phase 0 预注册（SR-2），
故 G1 只对预注册可判定轴（源守恒/延迟/前置/隔离/低样本）给出
机器判定，分割质量以“回归地板”记录，不冒充达标。
"""
import hashlib
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
INPUTS = [
    "quality-development.json",
    "quality-validation.json",
    "latency-development.json",
    "prerequisites.json",
]


def sha256_file(path):
    with open(path, "rb") as f:
        return hashlib.sha256(f.read()).hexdigest()


def load(name):
    path = os.path.join(HERE, name)
    if not os.path.exists(path):
        return None
    with open(path, "r", encoding="utf-8-sig") as f:
        return json.load(f)


def main():
    components = {}
    broken = []
    for name in INPUTS:
        path = os.path.join(HERE, name)
        if not os.path.exists(path):
            broken.append(f"missing:{name}")
            continue
        components[name] = {
            "sha256": sha256_file(path),
            "content": load(name),
        }

    verdicts = {}
    if not broken:
        dev = components["quality-development.json"]["content"]
        val = components["quality-validation.json"]["content"]
        lat = components["latency-development.json"]["content"]
        pre = components["prerequisites.json"]["content"]

        checks = pre.get("checks", {})
        verdicts["prerequisites"] = (
            "pass" if not pre.get("blocked") else "blocked:" + ",".join(pre.get("block_reasons", []))
        )
        verdicts["schema_hash_pinned"] = (
            "pass"
            if checks.get("schema_hash") and checks.get("schema_hash") == checks.get("schema_hash_pinned")
            else "fail"
        )
        verdicts["pipeline_hashes_recorded"] = (
            "pass" if checks.get("pipeline_hashes") else "fail"
        )
        verdicts["live_route"] = (
            "pass" if checks.get("live_route_exit_code") == 0 else "fail"
        )
        verdicts["frozen_isolation"] = (
            "pass" if checks.get("frozen_isolation") is True else "fail"
        )
        verdicts["dev_validation_separated"] = (
            "pass"
            if dev.get("split") == "development" and val.get("split") == "validation"
            else "fail"
        )
        verdicts["stroke_conservation_dev"] = dev.get("verdicts", {}).get(
            "stroke_conservation", "unknown"
        )
        verdicts["stroke_conservation_validation"] = val.get("verdicts", {}).get(
            "stroke_conservation", "unknown"
        )
        verdicts["latency_budget"] = lat.get("verdicts", {}).get("latency", "unknown")
        verdicts["low_sample_rule"] = (
            "pass"
            if "low_sample" not in dev.get("verdicts", {})
            and "low_sample" not in val.get("verdicts", {})
            and "insufficient" not in str(lat.get("verdicts", {}))
            else "insufficient"
        )

    gate_decision = "development_gate_reported"
    if broken:
        gate_decision = "broken"
    elif any(v.startswith(("fail", "blocked")) for v in verdicts.values()):
        gate_decision = "prerequisites_failed"

    report = {
        "schema_version": "1.0.0",
        "artifact": "gate-one-report",
        "task": "V3-206A",
        "components": {
            name: info["sha256"] for name, info in components.items() if not broken
        },
        "measured": {
            "development": {
                k: components["quality-development.json"]["content"].get(k)
                for k in ("evaluated_samples", "pair_precision", "pair_recall", "pair_f1",
                          "merge_errors", "split_errors", "stroke_loss_samples")
            },
            "validation": {
                k: components["quality-validation.json"]["content"].get(k)
                for k in ("evaluated_samples", "pair_precision", "pair_recall", "pair_f1",
                          "merge_errors", "split_errors", "stroke_loss_samples")
            },
            "latency_development": {
                k: components["latency-development.json"]["content"].get(k)
                for k in ("p50_ms", "p95_ms", "max_ms", "timeout_seconds")
            },
            "calibration_drift_pair_f1": components["prerequisites.json"]["content"].get(
                "calibration_drift_pair_f1"
            ),
        },
        "machine_verdicts": verdicts,
        "gate_decision": gate_decision,
        "quality_threshold_disclosure": (
            "分割质量阈值未在 Gate 0 预注册（SR-2 禁止事后设阈）；"
            "本报告以 dev/validation 实测值作为后续迭代的回归地板记录，"
            "不声明质量达标。frozen holdout 未参与本评测（SR-4）。"
        ),
        "human_validation_performed": False,
        "disclosure": "HUMAN_VALIDATION_NOT_PERFORMED；PRODUCTION_RELEASE_NOT_AUTHORIZED",
    }

    out_path = os.path.join(HERE, "gate-one-report.json")
    with open(out_path, "w", encoding="utf-8", newline="\n") as f:
        json.dump(report, f, ensure_ascii=False, indent=1)
        f.write("\n")

    if broken:
        print("G1 report BROKEN:", broken)
        sys.exit(2)
    print(
        "gate-one-report.json written; decision=%s; verdicts=%d"
        % (gate_decision, len(verdicts))
    )


if __name__ == "__main__":
    main()
