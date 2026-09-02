"""
Merge exercise_list.json (190 curated) + stockpile all_exercises (717 discovered)
into a single unified metadata list scoped to whatever has an actual PNG on disk.

Output: scripts/output/all_exercises_metadata.json

Schema (per entry):
  normalized_filename : str
  name                : str
  category            : str
  target_area         : str
  body_position       : str
  pose_description    : str   (start position)
  end_pose_description: str
  source              : "curated" | "stockpile" | "image_only"

Usage:
  python scripts/build_unified_metadata.py
"""
from __future__ import annotations

import json
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
OUTPUT_DIR = SCRIPT_DIR / "output"
CURATED = SCRIPT_DIR / "exercise_list.json"
STOCKPILE = OUTPUT_DIR / "stockpile_progress.json"
OUT = OUTPUT_DIR / "all_exercises_metadata.json"


def list_start_images() -> set[str]:
    names = set()
    for p in OUTPUT_DIR.glob("*.png"):
        stem = p.stem
        if any(stem.endswith(sfx) for sfx in ("_end", "_mask", "_mask_preview", "_end_inpaint")):
            continue
        names.add(stem)
    return names


def load_curated() -> dict[str, dict]:
    with CURATED.open() as f:
        data = json.load(f)
    by_name = {}
    for e in data["exercises"]:
        by_name[e["normalized_filename"]] = {
            "normalized_filename": e["normalized_filename"],
            "name": e.get("name", ""),
            "category": e.get("category", ""),
            "target_area": e.get("target_area", ""),
            "body_position": e.get("body_position", ""),
            "pose_description": e.get("pose_description", ""),
            "end_pose_description": e.get("end_pose_description", ""),
            "source": "curated",
        }
    return by_name


def load_stockpile() -> dict[str, dict]:
    if not STOCKPILE.exists():
        return {}
    with STOCKPILE.open() as f:
        data = json.load(f)
    out = {}
    for key, ex in data.get("all_exercises", {}).items():
        img = ex.get("imageFileName") or key
        out[img] = {
            "normalized_filename": img,
            "name": ex.get("name", ""),
            "category": ex.get("category", ""),
            "target_area": ex.get("targetArea", ""),
            "body_position": ex.get("bodyPosition", ""),
            "pose_description": ex.get("startPoseDescription", ""),
            "end_pose_description": ex.get("endPoseDescription", ""),
            "source": "stockpile",
        }
    return out


def main() -> int:
    images = list_start_images()
    curated = load_curated()
    stockpile = load_stockpile()

    merged: dict[str, dict] = {}
    # Curated wins on conflict (richer, human-curated descriptions)
    for name, ex in stockpile.items():
        merged[name] = ex
    for name, ex in curated.items():
        merged[name] = ex

    # Filter to images that actually exist, and flag image-only
    output = []
    for name in sorted(images):
        if name in merged:
            output.append(merged[name])
        else:
            output.append({
                "normalized_filename": name,
                "name": name.replace("-", " ").title(),
                "category": "",
                "target_area": "",
                "body_position": "",
                "pose_description": "",
                "end_pose_description": "",
                "source": "image_only",
            })

    OUT.write_text(json.dumps({"exercises": output}, indent=2))

    # Summary
    by_source: dict[str, int] = {}
    missing_desc = 0
    for e in output:
        by_source[e["source"]] = by_source.get(e["source"], 0) + 1
        if not e["pose_description"]:
            missing_desc += 1
    print(f"Wrote {OUT} with {len(output)} entries")
    for src, n in sorted(by_source.items()):
        print(f"  {src}: {n}")
    print(f"Missing pose_description: {missing_desc}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
