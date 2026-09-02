"""
Rebuild scripts/output/exercise_image_mapping.json from the actual PNGs on
disk, pulling metadata from all_exercises_metadata.json and stockpile_progress.json.
Also copies the result into the iOS Resources bundle.

One entry per start PNG (exercises that don't have a start image are skipped).
"""
from __future__ import annotations

import json
import shutil
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
OUTPUT_DIR = SCRIPT_DIR / "output"
MAPPING_FILE = OUTPUT_DIR / "exercise_image_mapping.json"
METADATA = OUTPUT_DIR / "all_exercises_metadata.json"
STOCKPILE = OUTPUT_DIR / "stockpile_progress.json"
IOS_MAPPING = (
    SCRIPT_DIR.parent / "ios" / "PT-Helper" / "COIL"
    / "Resources" / "exercise_image_mapping.json"
)

NON_START_SUFFIXES = ("_end", "_mask", "_mask_preview", "_contact_sheet")
NON_START_PREFIXES = ("_tmp_", "nb_")


def title_from_slug(slug: str) -> str:
    return slug.replace("-", " ").replace("_", " ").title()


def main() -> int:
    # 1) Every start PNG on disk
    start_pngs = sorted(
        p for p in OUTPUT_DIR.glob("*.png")
        if not any(p.stem.endswith(s) for s in NON_START_SUFFIXES)
        and not p.stem.startswith(NON_START_PREFIXES)
    )
    print(f"Start PNGs on disk: {len(start_pngs)}")

    # 2) End PNGs for pair metadata
    end_pngs = {p.stem.removesuffix("_end"): p.name for p in OUTPUT_DIR.glob("*_end.png")}
    if end_pngs:
        print(f"End PNGs on disk: {len(end_pngs)}")

    # 3) Metadata lookup: unified metadata + stockpile fallback
    meta_by: dict[str, dict] = {}
    if METADATA.exists():
        data = json.loads(METADATA.read_text())
        for e in data.get("exercises", []):
            meta_by[e["normalized_filename"]] = e
    if STOCKPILE.exists():
        stock = json.loads(STOCKPILE.read_text())
        for k, e in stock.get("all_exercises", {}).items():
            img_name = e.get("imageFileName") or k
            if img_name not in meta_by:
                meta_by[img_name] = {
                    "normalized_filename": img_name,
                    "name": e.get("name", title_from_slug(img_name)),
                    "category": e.get("category", "general"),
                    "target_area": e.get("targetArea", "General"),
                }

    mapping: dict[str, dict] = {}
    orphans: list[str] = []
    for p in start_pngs:
        key = p.stem
        m = meta_by.get(key)
        if m:
            entry = {
                "name": m.get("name", title_from_slug(key)),
                "filename": p.name,
                "category": m.get("category", "general"),
                "target_area": m.get("target_area") or m.get("targetArea", "General"),
            }
            if m.get("body_position"):
                entry["body_position"] = m["body_position"]
            aliases = m.get("aliases") or []
            if aliases:
                entry["aliases"] = sorted(set(aliases))
        else:
            orphans.append(key)
            entry = {
                "name": title_from_slug(key),
                "filename": p.name,
                "category": "general",
                "target_area": "General",
            }
        if key in end_pngs:
            entry["end_filename"] = end_pngs[key]
        mapping[key] = entry

    # Sort keys for stable diffs
    mapping = dict(sorted(mapping.items()))

    # Write to scripts/output
    MAPPING_FILE.write_text(json.dumps(mapping, indent=2))
    print(f"Wrote {len(mapping)} entries → {MAPPING_FILE.relative_to(SCRIPT_DIR.parent)}")

    # Sync to iOS Resources
    if IOS_MAPPING.parent.exists():
        shutil.copy2(MAPPING_FILE, IOS_MAPPING)
        print(f"Synced → {IOS_MAPPING.relative_to(SCRIPT_DIR.parent)}")
    else:
        print(f"WARN: iOS resource dir not found: {IOS_MAPPING.parent}")

    if orphans:
        print(f"\n{len(orphans)} PNGs had no metadata entry (synthetic titles used):")
        for o in orphans[:15]:
            print(f"  - {o}")
        if len(orphans) > 15:
            print(f"  ... (+{len(orphans)-15} more)")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
