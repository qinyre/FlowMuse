# -*- coding: utf-8 -*-
"""V3-002A 种子数据集确定性生成器（synthetic-seed-v1）。

可复算性契约：同版本 python 下重复运行本脚本必须产出字节级一致的
samples/*.scene.json 与 dataset-manifest.json（外层构建器会做双跑 hash 对比）。
每个样本：固定随机种子、固定参数规格（params_sha256 为规格 JSON 的 SHA-256）、
无时间戳/路径/环境量进入产物。
"""
import hashlib
import io
import json
import os
import random
import sys

sys.stdout.reconfigure(encoding="utf-8")

HERE = os.path.dirname(os.path.abspath(__file__))
DATASET_ROOT = os.path.dirname(HERE)

# 样本规格：特征覆盖 V3-002B 分层维度（内容类型/复杂度/整洁度/压力/已知失败）。
SAMPLE_SPECS = [
    {"id": "syn-seed-0001", "seed": 101, "content_kind": "handwritten_only", "stroke_count": 14,
     "flags": {"tidy_page": True}, "elements": {"strokes": 14, "text": 0, "shapes": 0}},
    {"id": "syn-seed-0002", "seed": 102, "content_kind": "handwritten_only", "stroke_count": 38,
     "flags": {"scattered_page": True}, "elements": {"strokes": 38, "text": 0, "shapes": 0}},
    {"id": "syn-seed-0003", "seed": 103, "content_kind": "mixed", "stroke_count": 22,
     "flags": {"has_images": True, "has_decorative_lines": True},
     "elements": {"strokes": 22, "text": 3, "shapes": 1, "images": 1, "decorative_lines": 2}},
    {"id": "syn-seed-0004", "seed": 104, "content_kind": "typed_only", "stroke_count": 0,
     "flags": {"long_form": True}, "elements": {"strokes": 0, "text": 6}},
    {"id": "syn-seed-0005", "seed": 105, "content_kind": "handwritten_only", "stroke_count": 55,
     "flags": {"pressure_stress": True, "has_groups": True},
     "elements": {"strokes": 55, "text": 0, "shapes": 0}},
    {"id": "syn-seed-0006", "seed": 106, "content_kind": "mixed", "stroke_count": 18,
     "flags": {"has_frames": True, "has_list": True},
     "elements": {"strokes": 18, "text": 4, "shapes": 2}},
    {"id": "syn-seed-0007", "seed": 107, "content_kind": "handwritten_only", "stroke_count": 26,
     "flags": {"has_locked_objects": True, "vertical_text_preserved": True},
     "elements": {"strokes": 26, "text": 0, "shapes": 1}},
    {"id": "syn-seed-0008", "seed": 108, "content_kind": "mixed", "stroke_count": 31,
     "flags": {"known_failure_page": True, "has_bindings": True},
     "elements": {"strokes": 31, "text": 2, "shapes": 1, "bindings": 1}},
]

ALL_FLAGS = [
    "has_images", "has_formula", "has_shapes", "has_groups", "has_frames", "has_bindings",
    "has_locked_objects", "has_decorative_lines", "has_list", "long_form",
    "vertical_text_preserved", "tidy_page", "scattered_page", "pressure_stress",
    "known_failure_page",
]


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def dump_json(obj) -> bytes:
    return (json.dumps(obj, ensure_ascii=False, indent=1) + "\n").encode("utf-8")


def compose_scene(spec: dict) -> dict:
    """由规格与种子确定性地合成一页场景（元素带 bbox 与稳定 id）。"""
    rng = random.Random(spec["seed"])
    page = {"width": 1240, "height": 1754}
    elements = []
    counters = {"stroke": 0, "text": 0, "shape": 0, "image": 0, "line": 0, "binding": 0}

    def add(kind: str, extra: dict) -> None:
        counters[kind] += 1
        x = rng.randint(40, 1000)
        y = rng.randint(40, 1600)
        w = rng.randint(60, 400)
        h = rng.randint(24, 200)
        elements.append({
            "id": f"{spec['id']}-{kind}-{counters[kind]:03d}",
            "type": kind if kind != "line" else "decorative_line",
            "bbox": [x, y, w, h],
            "rotation": rng.choice([0, 0, 0, 90]),
            **extra,
        })

    for _ in range(spec["elements"].get("strokes", 0)):
        add("stroke", {
            "points": [[rng.randint(0, 400), rng.randint(0, 300)] for _ in range(rng.randint(3, 12))],
            "pressure": [round(rng.uniform(0.1, 1.0), 3) for _ in range(4)],
        })
    for _ in range(spec["elements"].get("text", 0)):
        add("text", {"text_kind": "typed", "chars": f"段落{counters['text'] + 1}" * rng.randint(2, 5)})
    for _ in range(spec["elements"].get("shapes", 0)):
        add("shape", {"shape_kind": rng.choice(["rect", "ellipse"])})
    for _ in range(spec["elements"].get("images", 0)):
        add("image", {"asset_seed": rng.randint(1, 9999)})
    for _ in range(spec["elements"].get("decorative_lines", 0)):
        add("line", {"style": rng.choice(["dashed", "solid"])})
    for _ in range(spec["elements"].get("bindings", 0)):
        add("binding", {"target_kind": "text", "offset": [rng.randint(-20, 20), rng.randint(-20, 20)]})

    # 锁定对象：前 1/4 元素锁定（若有该标志）。
    if spec["flags"].get("has_locked_objects") and elements:
        for element in elements[: max(1, len(elements) // 4)]:
            element["locked"] = True
    return {"page": page, "elements": elements}


def build_features(spec: dict) -> dict:
    flags = {name: bool(spec["flags"].get(name, False)) for name in ALL_FLAGS}
    if flags["has_shapes"] is False and spec["elements"].get("shapes", 0) > 0:
        flags["has_shapes"] = True
    if flags["has_images"] is False and spec["elements"].get("images", 0) > 0:
        flags["has_images"] = True
    return {
        "content_kind": spec["content_kind"],
        "stroke_count": spec["stroke_count"],
        **flags,
    }


def main() -> None:
    samples_dir = os.path.join(DATASET_ROOT, "samples")
    os.makedirs(samples_dir, exist_ok=True)
    entries = []
    for spec in SAMPLE_SPECS:
        scene = compose_scene(spec)
        rel = f"samples/{spec['id']}.scene.json"
        scene_bytes = dump_json(scene)
        with io.open(os.path.join(DATASET_ROOT, rel), "wb") as f:
            f.write(scene_bytes)
        entries.append({
            "spec": spec,
            "rel": rel,
            "scene_sha256": sha256_bytes(scene_bytes),
            "params_sha256": sha256_bytes(dump_json(spec)),
        })

    samples = []
    for entry in entries:
        spec = entry["spec"]
        samples.append({
            "sample_id": spec["id"],
            "kind": "synthetic",
            "origin": {
                "generator": {
                    "name": "seed-scene-composer",
                    "version": "1.0.0",
                    "seed": spec["seed"],
                    "params_sha256": entry["params_sha256"],
                    "deterministic": True,
                },
                "generated_at_utc": "2026-08-31T00:00:00Z",
                "derivation_chain": [],
            },
            "rights": {
                "kind": "synthetic",
                "license": None,
                "forbidden_uses": [
                    "production_release_claims",
                    "human_validation_claims",
                    "training_external_models",
                ],
                "deletion": {
                    "policy_id": "regenerable-synthetic-v1",
                    "method": "regenerable_no_retention",
                    "reference": "docs/研发记录/evidence/smart-layout-v3/datasets/synthetic-seed-v1/tools/generate.py",
                },
            },
            "content": {"path": entry["rel"], "sha256": entry["scene_sha256"]},
            "features": build_features(spec),
        })

    manifest = {
        "schema_version": "1.0.0",
        "dataset_kind": "smart-layout-v3-dataset-manifest",
        "dataset": {
            "name": "synthetic-seed-v1",
            "version": "1.0.0",
            "generated_at_utc": "2026-08-31T00:00:00Z",
            "lane": "ai_synthetic_development",
            "admission_policy": {
                "admitted_kinds": ["synthetic", "licensed"],
                "rejected_kinds": ["real_user_content"],
                "rejection_directive": "real_user_content 保持隔离并推迟到 V3-700A 授权包（数据授权/脱敏/同意批准）",
            },
        },
        "samples": samples,
    }
    manifest_path = os.path.join(DATASET_ROOT, "dataset-manifest.json")
    with io.open(manifest_path, "wb") as f:
        f.write(dump_json(manifest))
    print(f"wrote {len(samples)} samples + manifest; manifest sha256={sha256_bytes(dump_json(manifest))}")


if __name__ == "__main__":
    main()
