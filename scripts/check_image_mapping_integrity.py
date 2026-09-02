"""
CI integrity check for the exercise image mapping.

Asserts:
1. Every key in exercise_image_mapping.json has a matching scripts/output/{key}.png.
2. Every "start" PNG (filtered by NON_START_* rules from rebuild_image_mapping.py)
   has a mapping entry.
3. iOS Resources copy is byte-identical to scripts/output/exercise_image_mapping.json.
4. Aliases are unique across the catalog (no two canonical exercises share an alias).
5. body_position is present on at least 95% of entries (catches the case where
   rebuild_image_mapping.py was accidentally skipped after a metadata change).
6. Every entry's `filename` equals "{key}.png".

Exits 1 on any mismatch with a diff report.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
OUTPUT_DIR = SCRIPT_DIR / "output"
MAPPING_FILE = OUTPUT_DIR / "exercise_image_mapping.json"
IOS_MAPPING = (
    SCRIPT_DIR.parent / "ios" / "PT-Helper" / "COIL"
    / "Resources" / "exercise_image_mapping.json"
)

NON_START_SUFFIXES = ("_end", "_mask", "_mask_preview", "_contact_sheet")
NON_START_PREFIXES = ("_tmp_", "nb_")

BODY_POSITION_THRESHOLD = 0.95


def main() -> int:
    failures: list[str] = []

    if not MAPPING_FILE.exists():
        print(f"FAIL: {MAPPING_FILE} not found", file=sys.stderr)
        return 1

    mapping = json.loads(MAPPING_FILE.read_text())
    print(f"Loaded {len(mapping)} mapping entries")

    # 1. Every key has a matching PNG
    missing_pngs = []
    for key in mapping:
        if not (OUTPUT_DIR / f"{key}.png").exists():
            missing_pngs.append(key)
    if missing_pngs:
        failures.append(f"{len(missing_pngs)} mapping keys have no matching PNG:")
        for k in missing_pngs[:10]:
            failures.append(f"  - {k}")
        if len(missing_pngs) > 10:
            failures.append(f"  ... (+{len(missing_pngs)-10} more)")

    # 2. Every start PNG has a mapping entry
    start_pngs = sorted(
        p for p in OUTPUT_DIR.glob("*.png")
        if not any(p.stem.endswith(s) for s in NON_START_SUFFIXES)
        and not p.stem.startswith(NON_START_PREFIXES)
    )
    orphan_pngs = [p.stem for p in start_pngs if p.stem not in mapping]
    if orphan_pngs:
        failures.append(f"{len(orphan_pngs)} PNGs have no mapping entry:")
        for k in orphan_pngs[:10]:
            failures.append(f"  - {k}")
        if len(orphan_pngs) > 10:
            failures.append(f"  ... (+{len(orphan_pngs)-10} more)")

    # 3. iOS Resources copy byte-identical
    if not IOS_MAPPING.exists():
        failures.append(f"iOS bundle missing: {IOS_MAPPING}")
    elif IOS_MAPPING.read_bytes() != MAPPING_FILE.read_bytes():
        failures.append(
            "iOS bundle copy differs from source-of-truth:\n"
            f"  Source: {MAPPING_FILE}\n"
            f"  iOS:    {IOS_MAPPING}\n"
            "  Fix: re-run `python scripts/rebuild_image_mapping.py`"
        )

    # 4. Aliases unique across catalog
    alias_owners: dict[str, list[str]] = {}
    for canonical, entry in mapping.items():
        for alias in entry.get("aliases") or []:
            alias_owners.setdefault(alias, []).append(canonical)
    duplicates = {a: owners for a, owners in alias_owners.items() if len(owners) > 1}
    if duplicates:
        failures.append(f"{len(duplicates)} aliases claimed by >1 canonical exercise:")
        for alias, owners in list(duplicates.items())[:10]:
            failures.append(f"  - '{alias}' → {owners}")

    # 5. body_position coverage threshold
    with_bp = sum(1 for v in mapping.values() if v.get("body_position"))
    coverage = with_bp / len(mapping) if mapping else 0
    print(f"body_position coverage: {with_bp}/{len(mapping)} ({coverage:.1%})")
    if coverage < BODY_POSITION_THRESHOLD:
        failures.append(
            f"body_position coverage {coverage:.1%} below {BODY_POSITION_THRESHOLD:.0%} threshold "
            f"({with_bp}/{len(mapping)}). Did rebuild_image_mapping.py run?"
        )

    # 6. filename == key.png invariant
    bad_filenames = [
        (k, v.get("filename"))
        for k, v in mapping.items()
        if v.get("filename") != f"{k}.png"
    ]
    if bad_filenames:
        failures.append(f"{len(bad_filenames)} entries violate filename == key.png:")
        for k, fn in bad_filenames[:10]:
            failures.append(f"  - {k} → {fn}")

    # Summary
    if failures:
        print("\nINTEGRITY FAILURES:")
        for line in failures:
            print(line)
        print(f"\nFAIL: {len([f for f in failures if not f.startswith('  ')])} category(s) failed")
        return 1

    print(
        f"\nPASS: {len(mapping)} entries, {with_bp} with body_position, "
        f"{sum(1 for v in mapping.values() if v.get('aliases'))} with aliases, "
        f"{sum(len(v.get('aliases', [])) for v in mapping.values())} total alias mappings"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
