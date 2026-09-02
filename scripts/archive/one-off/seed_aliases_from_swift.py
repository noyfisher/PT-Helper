"""
One-time port: extract the Swift `aliasMap` from ExerciseImageService.swift
(plus the Python mirror in fuzzy_match.py and, optionally, the Firestore
config/exerciseImageAliases doc), invert from alias→canonical to
canonical→[aliases], and merge the result into all_exercises_metadata.json
under each exercise's `aliases` array.

The Swift source is authoritative — Python is a mirror that may have drifted.
Both are read; entries are unioned. Firestore is opt-in via --include-firestore
because it requires a Firebase service-account credential (off by default so
the script runs cleanly in any environment).

Disambiguation guard: every alias canonical must exist as a key in
exercise_image_mapping.json. If the value chains through another alias
(intermediate alias), it is resolved recursively (depth ≤ 3). Unresolvable
aliases are skipped with a WARNING log line.

Usage:
    python scripts/seed_aliases_from_swift.py [--dry-run] [--include-firestore]
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
OUTPUT_DIR = SCRIPT_DIR / "output"
METADATA_FILE = OUTPUT_DIR / "all_exercises_metadata.json"
MAPPING_FILE = OUTPUT_DIR / "exercise_image_mapping.json"
SWIFT_FILE = (
    SCRIPT_DIR.parent
    / "ios" / "PT-Helper" / "PT-Helper" / "Services" / "ExerciseImageService.swift"
)


def parse_swift_alias_map(swift_path: Path) -> dict[str, str]:
    """Extract the `aliasMap` dictionary from ExerciseImageService.swift.

    Looks for the block starting at `private static let aliasMap: [String: String] = [`
    and ending at the matching closing `]`.
    """
    text = swift_path.read_text()
    start_marker = "private static let aliasMap: [String: String] = ["
    start = text.find(start_marker)
    if start < 0:
        raise RuntimeError(f"Could not find aliasMap in {swift_path}")
    # Walk forward to the matching `]` at column 4 (Swift indentation convention)
    rest = text[start + len(start_marker):]
    end = rest.find("\n    ]")
    if end < 0:
        raise RuntimeError("Could not find aliasMap closing bracket")
    body = rest[:end]
    # Each non-empty, non-comment line: "alias-key": "canonical-key",
    pattern = re.compile(r'"([^"]+)"\s*:\s*"([^"]+)"\s*,')
    aliases: dict[str, str] = {}
    for m in pattern.finditer(body):
        aliases[m.group(1)] = m.group(2)
    return aliases


def load_python_mirror() -> dict[str, str]:
    """Import ALIAS_MAP from scripts/fuzzy_match.py."""
    sys.path.insert(0, str(SCRIPT_DIR))
    try:
        from fuzzy_match import ALIAS_MAP  # type: ignore
    except ImportError:
        return {}
    return dict(ALIAS_MAP)


def load_firestore_aliases() -> dict[str, str]:
    """Load aliases from Firestore config/exerciseImageAliases (requires creds)."""
    try:
        from google.cloud import firestore  # type: ignore
    except ImportError:
        print("WARN: --include-firestore set but google-cloud-firestore not installed; skipping")
        return {}
    try:
        db = firestore.Client()
        doc = db.collection("config").document("exerciseImageAliases").get()
        if not doc.exists:
            print("WARN: Firestore config/exerciseImageAliases doc not found")
            return {}
        data = doc.to_dict() or {}
        return data.get("aliases", {})
    except Exception as exc:
        print(f"WARN: Firestore read failed ({exc}); skipping")
        return {}


def resolve_canonical(
    target: str,
    catalog_keys: set[str],
    alias_map: dict[str, str],
    depth: int = 0,
) -> str | None:
    """Resolve `target` to a key that exists in the catalog.

    If `target` is itself an alias, follow the chain up to depth 3.
    Returns None if no terminal canonical exists in the catalog.
    """
    if target in catalog_keys:
        return target
    if depth >= 3:
        return None
    next_target = alias_map.get(target)
    if next_target and next_target != target:
        return resolve_canonical(next_target, catalog_keys, alias_map, depth + 1)
    return None


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dry-run", action="store_true", help="Don't write to metadata file")
    parser.add_argument(
        "--include-firestore",
        action="store_true",
        help="Also fold in Firestore config/exerciseImageAliases (requires credentials)",
    )
    args = parser.parse_args()

    if not METADATA_FILE.exists():
        print(f"ERROR: {METADATA_FILE} does not exist", file=sys.stderr)
        return 1
    if not MAPPING_FILE.exists():
        print(f"ERROR: {MAPPING_FILE} does not exist (run rebuild_image_mapping.py first)")
        return 1
    if not SWIFT_FILE.exists():
        print(f"ERROR: {SWIFT_FILE} does not exist", file=sys.stderr)
        return 1

    swift_aliases = parse_swift_alias_map(SWIFT_FILE)
    python_aliases = load_python_mirror()
    firestore_aliases = load_firestore_aliases() if args.include_firestore else {}

    print(f"Swift aliasMap: {len(swift_aliases)} entries")
    print(f"Python ALIAS_MAP mirror: {len(python_aliases)} entries")
    print(f"Firestore aliases: {len(firestore_aliases)} entries")

    # Union — Swift wins on conflict (it's authoritative)
    merged: dict[str, str] = {}
    merged.update(firestore_aliases)
    merged.update(python_aliases)
    merged.update(swift_aliases)
    print(f"Merged unique aliases: {len(merged)}")

    catalog = json.loads(MAPPING_FILE.read_text())
    catalog_keys = set(catalog.keys())

    # Group by canonical, with disambiguation guard
    canonical_to_aliases: dict[str, set[str]] = {}
    skipped: list[tuple[str, str]] = []  # (alias, raw_target)
    for alias, raw_target in merged.items():
        canonical = resolve_canonical(raw_target, catalog_keys, merged)
        if canonical is None:
            skipped.append((alias, raw_target))
            continue
        # Don't add an alias that equals its canonical (no-op)
        if alias == canonical:
            continue
        canonical_to_aliases.setdefault(canonical, set()).add(alias)

    print(f"\nResolved: {sum(len(v) for v in canonical_to_aliases.values())} aliases "
          f"across {len(canonical_to_aliases)} canonical exercises")
    if skipped:
        print(f"Skipped (no terminal canonical in catalog): {len(skipped)}")
        for alias, target in skipped[:10]:
            print(f"  WARNING: '{alias}' → '{target}' not in catalog")
        if len(skipped) > 10:
            print(f"  ... (+{len(skipped) - 10} more)")

    # Merge into metadata file
    data = json.loads(METADATA_FILE.read_text())
    exercises = data.get("exercises", [])
    by_key = {e["normalized_filename"]: e for e in exercises}

    added = 0
    for canonical, aliases_set in canonical_to_aliases.items():
        entry = by_key.get(canonical)
        if entry is None:
            print(f"WARNING: catalog key '{canonical}' not in metadata — skipping")
            continue
        existing = set(entry.get("aliases", []) or [])
        new_set = sorted(existing | aliases_set)
        if new_set != sorted(existing):
            entry["aliases"] = new_set
            added += len(new_set) - len(existing)

    print(f"\nAliases added: {added}")
    print(f"Exercises with at least one alias after seed: "
          f"{sum(1 for e in exercises if e.get('aliases'))}")

    if args.dry_run:
        print("\n[DRY RUN] Not writing changes")
        return 0

    METADATA_FILE.write_text(json.dumps(data, indent=2) + "\n")
    print(f"\nWrote {METADATA_FILE.relative_to(SCRIPT_DIR.parent)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
