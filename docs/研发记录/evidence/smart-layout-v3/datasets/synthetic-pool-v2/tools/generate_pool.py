# -*- coding: utf-8 -*-
"""V3-002B 分层样本池确定性生成器（synthetic-pool-v2）。

分层轴：scene_family × content_kind × complexity(笔画带) × platform_profile。
派生变体与基样本通过 derivation_chain 连接（供隔离组件归并测试）；
同族变体复用基样本的生成身份键的一部分（seed 派生），但不伪造许可或真实内容。
重复运行必须字节级一致（无时间戳/环境量入产物）。
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

FAMILIES = ["meeting-notes", "brainstorm-board", "annotated-diagram", "typed-report"]
PLATFORMS = {"desktop": (1240, 1754), "mobile": (720, 1280), "web": (1440, 900)}
COMPLEXITY = {"none": 0, "low": 8, "medium": 24, "high": 56}

# 单元格裁剪（内容矛盾组合跳过，并在 pool-coverage.json 中登记）。
SKIP_RULES = [
    {"family": "brainstorm-board", "content_kind": "typed_only",
     "reason": "白板头脑风暴以手写为主，typed_only 与场景族定义矛盾"},
    {"family": "typed-report", "content_kind": "handwritten_only",
     "reason": "打字报告场景族不含纯手写单元"},
    {"family": "annotated-diagram", "content_kind": "typed_only", "complexity": "none",
     "reason": "图解标注至少需要标注笔迹，complexity=none 矛盾"},
]
# typed-report 的复杂度以文本块数量承载：strokes=0 时 complexity 用文本块带替代。
TEXT_COMPLEXITY = {"none": 2, "low": 4, "medium": 8, "high": 14}

ALL_FLAGS = [
    "has_images", "has_formula", "has_shapes", "has_groups", "has_frames", "has_bindings",
    "has_locked_objects", "has_decorative_lines", "has_list", "long_form",
    "vertical_text_preserved", "tidy_page", "scattered_page", "pressure_stress",
    "known_failure_page",
]
FAMILY_FLAGS = {
    "meeting-notes": {"has_list": True, "tidy_page": True},
    "brainstorm-board": {"scattered_page": True, "has_groups": True},
    "annotated-diagram": {"has_shapes": True, "has_images": True, "has_decorative_lines": True},
    "typed-report": {"long_form": True},
}


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def dump_json(obj) -> bytes:
    return (json.dumps(obj, ensure_ascii=False, indent=1) + "\n").encode("utf-8")


def content_kinds_for(family: str):
    if family == "meeting-notes":
        return ["handwritten_only", "mixed"]
    if family == "brainstorm-board":
        return ["handwritten_only"]
    if family == "annotated-diagram":
        return ["mixed"]
    return ["typed_only", "mixed"]  # typed-report


def is_skipped(family: str, kind: str, complexity: str) -> str | None:
    for rule in SKIP_RULES:
        if rule["family"] == family and rule["content_kind"] == kind:
            if "complexity" not in rule or rule["complexity"] == complexity:
                return rule["reason"]
    if kind == "typed_only" and complexity != "none" and complexity != "low":
        return "typed_only 只有少量签名/批注笔迹，medium/high 笔画带与内容类型矛盾"
    if kind != "typed_only" and complexity == "none":
        return "含手写内容的单元 complexity=none 矛盾"
    return None


def compose_scene(spec: dict) -> dict:
    rng = random.Random(spec["seed"])
    width, height = PLATFORMS[spec["platform_profile"]]
    page = {"width": width, "height": height}
    elements = []
    counters = {"stroke": 0, "text": 0, "shape": 0, "image": 0, "line": 0, "binding": 0}

    def add(kind: str, extra: dict) -> None:
        counters[kind] += 1
        x = rng.randint(20, max(21, width - 120))
        y = rng.randint(20, max(21, height - 120))
        w = rng.randint(40, max(41, width // 3))
        h = rng.randint(18, max(19, height // 8))
        element = {
            "id": f"{spec['id']}-{kind}-{counters[kind]:03d}",
            "type": kind if kind != "line" else "decorative_line",
            "bbox": [x, y, w, h],
            "rotation": rng.choice([0, 0, 0, 90]),
        }
        element.update(extra)
        elements.append(element)

    stroke_count = spec["stroke_count"]
    if spec["content_kind"] == "typed_only":
        # 少量签名/批注笔迹（low）或无（none）。
        stroke_count = 0 if spec["complexity"] == "none" else 3
    for _ in range(stroke_count):
        add("stroke", {
            "points": [[rng.randint(0, 400), rng.randint(0, 300)] for _ in range(rng.randint(3, 12))],
            "pressure": [round(rng.uniform(0.1, 1.0), 3) for _ in range(4)],
        })
    text_blocks = TEXT_COMPLEXITY[spec["complexity"]] if spec["content_kind"] in ("typed_only", "mixed") else 0
    for _ in range(text_blocks):
        add("text", {"text_kind": "typed", "chars": f"段落{counters['text'] + 1}" * rng.randint(2, 5)})
    if spec["family"] == "annotated-diagram":
        for _ in range(2):
            add("shape", {"shape_kind": rng.choice(["rect", "ellipse"])})
        add("image", {"asset_seed": rng.randint(1, 9999)})
        for _ in range(2):
            add("line", {"style": rng.choice(["dashed", "solid"])})
    if spec["family"] == "brainstorm-board":
        add("shape", {"shape_kind": "rounded_rect"})
    # 派生变体的增量：追加一个带绑定标记的批注块。
    if spec.get("variant_of"):
        add("binding", {"target_kind": "text", "offset": [rng.randint(-20, 20), rng.randint(-20, 20)]})
    return {"page": page, "elements": elements}


def base_flags(spec: dict) -> dict:
    flags = {name: False for name in ALL_FLAGS}
    flags.update(FAMILY_FLAGS[spec["family"]])
    if spec["content_kind"] == "mixed":
        flags["has_images"] = flags["has_images"] or spec["family"] == "annotated-diagram"
    if spec.get("variant_of"):
        flags["has_bindings"] = True
    if spec["platform_profile"] == "mobile":
        flags["pressure_stress"] = spec["complexity"] == "high"
    if spec["family"] == "meeting-notes" and spec["complexity"] == "high":
        flags["known_failure_page"] = True
    return flags


def make_sample(spec: dict, scene_sha: str, params_sha: str, variant_of: str | None) -> dict:
    return {
        "sample_id": spec["id"],
        "kind": "synthetic",
        "scene_family": spec["family"],
        "platform_profile": spec["platform_profile"],
        "origin": {
            "generator": {
                "name": "stratified-scene-composer",
                "version": "1.0.0",
                "seed": spec["seed"],
                "params_sha256": params_sha,
                "deterministic": True,
            },
            "generated_at_utc": "2026-08-31T00:00:00Z",
            "derivation_chain": [variant_of] if variant_of else [],
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
                "reference": "docs/研发记录/evidence/smart-layout-v3/datasets/synthetic-pool-v2/tools/generate_pool.py",
            },
        },
        "content": {"path": f"samples/{spec['id']}.scene.json", "sha256": scene_sha},
        "features": {
            "content_kind": spec["content_kind"],
            "stroke_count": 0 if spec["content_kind"] == "typed_only" else spec["stroke_count"],
            **base_flags(spec),
        },
    }


def main() -> None:
    samples_dir = os.path.join(DATASET_ROOT, "samples")
    os.makedirs(samples_dir, exist_ok=True)
    samples = []
    skipped = []
    seed_counter = 1000
    seen_seeds = {}
    for family in FAMILIES:
        for kind in content_kinds_for(family):
            for complexity in COMPLEXITY:
                reason = is_skipped(family, kind, complexity)
                if reason:
                    skipped.append({
                        "family": family, "content_kind": kind, "complexity": complexity,
                        "reason": reason,
                    })
                    continue
                for platform in PLATFORMS:
                    seed_counter += 1
                    stem = f"syn-p2-{family[:4]}-{kind[:4]}-{complexity[:3]}-{platform[:3]}"
                    spec = {
                        "id": f"{stem}-{seed_counter}",
                        "family": family,
                        "content_kind": kind,
                        "complexity": complexity,
                        "platform_profile": platform,
                        "stroke_count": COMPLEXITY[complexity],
                        "seed": seed_counter,
                    }
                    scene = compose_scene(spec)
                    scene_bytes = dump_json(scene)
                    with io.open(os.path.join(DATASET_ROOT, f"samples/{spec['id']}.scene.json"), "wb") as f:
                        f.write(scene_bytes)
                    samples.append(make_sample(
                        spec, sha256_bytes(scene_bytes), sha256_bytes(dump_json(spec)), None))
                    # 派生变体：desktop 与 mobile 单元各派生一个（连接隔离组件）。
                    if platform in ("desktop", "mobile"):
                        seed_counter += 1
                        variant_spec = {
                            **spec,
                            "id": f"{stem}-v-{seed_counter}",
                            "seed": seed_counter,
                            "variant_of": spec["id"],
                        }
                        variant_scene = compose_scene(variant_spec)
                        variant_bytes = dump_json(variant_scene)
                        with io.open(
                            os.path.join(DATASET_ROOT, f"samples/{variant_spec['id']}.scene.json"), "wb"
                        ) as f:
                            f.write(variant_bytes)
                        samples.append(make_sample(
                            variant_spec, sha256_bytes(variant_bytes),
                            sha256_bytes(dump_json(variant_spec)), spec["id"]))
                    # 身份键去重防线：生成器名+seed+params 必须唯一（否则隔离规则误并）。
                    key = f"stratified-scene-composer|{spec['seed']}|{sha256_bytes(dump_json(spec))}"
                    assert key not in seen_seeds, f"duplicate generator identity: {key}"
                    seen_seeds[key] = spec["id"]

    manifest = {
        "schema_version": "1.0.0",
        "dataset_kind": "smart-layout-v3-dataset-manifest",
        "dataset": {
            "name": "synthetic-pool-v2",
            "version": "1.0.0",
            "generated_at_utc": "2026-08-31T00:00:00Z",
            "lane": "ai_synthetic_development",
            "split": "pooled",
            "admission_policy": {
                "admitted_kinds": ["synthetic", "licensed"],
                "rejected_kinds": ["real_user_content"],
                "rejection_directive": "real_user_content 保持隔离并推迟到 V3-700A 授权包（数据授权/脱敏/同意批准）",
            },
        },
        "samples": samples,
    }
    with io.open(os.path.join(DATASET_ROOT, "dataset-manifest.json"), "wb") as f:
        f.write(dump_json(manifest))
    with io.open(os.path.join(DATASET_ROOT, "pool-coverage.json"), "wb") as f:
        f.write(dump_json({
            "schema_version": "1.0.0",
            "artifact": "dataset-pool-coverage",
            "task": "V3-002B",
            "axes": {
                "scene_family": FAMILIES,
                "content_kind": ["handwritten_only", "typed_only", "mixed"],
                "complexity_band": list(COMPLEXITY),
                "platform_profile": list(PLATFORMS),
            },
            "sample_count": len(samples),
            "skipped_cells": skipped,
            "derivation_variants": sum(1 for s in samples if s["origin"]["derivation_chain"]),
        }))
    print(f"wrote {len(samples)} samples ({len(skipped)} skipped cells); "
          f"manifest sha256={sha256_bytes(dump_json(manifest))}")


if __name__ == "__main__":
    main()
