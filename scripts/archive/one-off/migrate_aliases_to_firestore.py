#!/usr/bin/env python3
"""
One-time migration: upload the hardcoded alias map from
ExerciseImageService.swift to Firestore config/exerciseImageAliases.

Usage:
  python migrate_aliases_to_firestore.py --service-account path/to/key.json
  python migrate_aliases_to_firestore.py  # uses Application Default Credentials
"""

import argparse
import sys

import firebase_admin
from firebase_admin import credentials, firestore

from fuzzy_match import ALIAS_MAP


def main():
    parser = argparse.ArgumentParser(description="Migrate exercise image aliases to Firestore")
    parser.add_argument("--service-account", help="Path to Firebase service account JSON")
    parser.add_argument("--dry-run", action="store_true", help="Print aliases without writing to Firestore")
    args = parser.parse_args()

    print(f"Alias map contains {len(ALIAS_MAP)} entries")

    if args.dry_run:
        for k, v in sorted(ALIAS_MAP.items()):
            print(f"  {k} → {v}")
        print(f"\nDry run: {len(ALIAS_MAP)} aliases would be written to Firestore config/exerciseImageAliases")
        return

    # Initialize Firebase
    if args.service_account:
        cred = credentials.Certificate(args.service_account)
        firebase_admin.initialize_app(cred)
    else:
        firebase_admin.initialize_app()

    db = firestore.client()

    # Write aliases to Firestore (merge to preserve any auto-added aliases)
    doc_ref = db.collection("config").document("exerciseImageAliases")

    # Firestore has a 1MB document limit; our alias map is ~30KB so we're fine
    doc_ref.set(
        {
            "aliases": ALIAS_MAP,
            "updatedAt": firestore.SERVER_TIMESTAMP,
            "source": "migration_from_swift",
            "count": len(ALIAS_MAP),
        },
        merge=True,
    )

    print(f"Successfully migrated {len(ALIAS_MAP)} aliases to Firestore config/exerciseImageAliases")


if __name__ == "__main__":
    main()
