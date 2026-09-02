"""Merge successfully-generated shuffle-discovery exercises into the canonical
all_exercises_metadata.json after generate_missing_images.py finishes.

For each entry in shuffle_image_gen_list.json:
- Check that the start PNG exists on disk
- If yes, append a new exercise to all_exercises_metadata.json["exercises"]
- Skip if normalized_filename already exists in canonical metadata

After merging, the caller should run rebuild_image_mapping.py to propagate
to exercise_image_mapping.json + iOS bundle.
"""
from __future__ import annotations

import json
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
OUTPUT_DIR = SCRIPT_DIR / "output"
METADATA = OUTPUT_DIR / "all_exercises_metadata.json"
GEN_LIST = OUTPUT_DIR / "shuffle_image_gen_list.json"


def main() -> int:
    md = json.loads(METADATA.read_text())
    gen = json.loads(GEN_LIST.read_text())

    by_key = {e["normalized_filename"]: e for e in md["exercises"]}
    existing_count = len(by_key)

    added = 0
    skipped_already_present = 0
    skipped_no_image = 0

    for ex in gen["exercises"]:
        key = ex["normalized_filename"]
        if key in by_key:
            skipped_already_present += 1
            continue
        png_path = OUTPUT_DIR / f"{key}.png"
        if not png_path.exists():
            skipped_no_image += 1
            continue
        # Build canonical-shaped entry
        entry = {
            "normalized_filename": key,
            "name": ex["name"],
            "category": ex.get("category") or "general",
            "target_area": ex.get("target_area") or "General",
            "body_position": ex.get("body_position") or "standing",
            "pose_description": ex.get("pose_description") or "",
            "end_pose_description": ex.get("end_pose_description") or "",
            "source": ex.get("source") or "shuffle_discovery",
        }
        md["exercises"].append(entry)
        added += 1

    METADATA.write_text(json.dumps(md, indent=2))
    print(f"Canonical metadata: {existing_count} → {len(md['exercises'])} (+{added})")
    print(f"  added:                    {added}")
    print(f"  skipped (already present): {skipped_already_present}")
    print(f"  skipped (no image yet):   {skipped_no_image}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
