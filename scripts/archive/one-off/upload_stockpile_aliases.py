#!/usr/bin/env python3
"""
Upload stockpile_alias_map.json into Firestore config/exerciseImageAliases.

Merges with any aliases already present (prior migration kept them alive).
The iOS ExerciseImageService reads this doc and overlays it on its hardcoded
aliasMap at runtime — no app update needed.

Usage:
  python scripts/upload_stockpile_aliases.py --dry-run     # default; shows what would merge
  python scripts/upload_stockpile_aliases.py --apply       # actually write
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import firebase_admin
from firebase_admin import credentials, firestore

ROOT = Path(__file__).resolve().parent.parent
ALIAS_MAP_FILE = ROOT / "scripts" / "output" / "stockpile_alias_map.json"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true", help="Write to Firestore (default: dry-run)")
    ap.add_argument("--service-account", help="Path to Firebase service account JSON (optional; else ADC)")
    args = ap.parse_args()

    new_aliases: dict[str, str] = json.loads(ALIAS_MAP_FILE.read_text())
    print(f"Local stockpile alias map: {len(new_aliases)} entries")

    # Init Firebase (needed even for dry-run to fetch current state).
    if args.service_account:
        firebase_admin.initialize_app(credentials.Certificate(args.service_account))
    else:
        firebase_admin.initialize_app()
    db = firestore.client()

    doc_ref = db.collection("config").document("exerciseImageAliases")
    existing_doc = doc_ref.get()
    existing: dict[str, str] = {}
    if existing_doc.exists:
        existing = (existing_doc.to_dict() or {}).get("aliases", {}) or {}
    print(f"Firestore currently holds: {len(existing)} aliases")

    overwrites = {k: (existing[k], v) for k, v in new_aliases.items() if k in existing and existing[k] != v}
    additions = {k: v for k, v in new_aliases.items() if k not in existing}
    noops = len(new_aliases) - len(overwrites) - len(additions)

    print(f"  additions:  {len(additions)}")
    print(f"  overwrites: {len(overwrites)}  (existing value will change)")
    print(f"  no-ops:     {noops}  (same value already there)")
    if overwrites:
        print("  --- overwrites detail ---")
        for k, (old, new) in overwrites.items():
            print(f"    {k}: {old} -> {new}")

    if not args.apply:
        print("\nDry-run. Pass --apply to write.")
        return 0

    merged = {**existing, **new_aliases}
    doc_ref.set({
        "aliases": merged,
        "updatedAt": firestore.SERVER_TIMESTAMP,
        "source": "stockpile_dedupe",
        "count": len(merged),
    }, merge=True)
    print(f"\nWrote {len(merged)} total aliases to config/exerciseImageAliases.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
