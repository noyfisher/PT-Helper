"""
Install reviewed regen winners.

For each fname in the input list:
  1. Back up the current image to scripts/output/_regen_backup/{fname}.png
  2. Replace it with {fname}_regen.png
  3. Update visual_review_log.json verdict to "passed" with a regen note
  4. Optionally remove the _regen file (keep by default for traceability)

Usage:
  python scripts/install_regen_winners.py --winners dead-bug,external-rotation
  python scripts/install_regen_winners.py --winners-file /tmp/winners.txt
"""
from __future__ import annotations

import argparse
import json
import shutil
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
OUTPUT_DIR = SCRIPT_DIR / "output"
BACKUP_DIR = OUTPUT_DIR / "_regen_backup"
VISUAL_LOG = OUTPUT_DIR / "visual_review_log.json"


def main() -> int:
    ap = argparse.ArgumentParser()
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument("--winners", help="Comma-separated fnames to install")
    g.add_argument("--winners-file", help="File with one fname per line")
    ap.add_argument("--note", default="Regen verified visually; replaces failed image.",
                    help="Note for the updated verdict")
    ap.add_argument("--keep-regen", action="store_true",
                    help="Keep the *_regen.png file after install (default: removes it)")
    args = ap.parse_args()

    if args.winners:
        names = [n.strip() for n in args.winners.split(",") if n.strip()]
    else:
        names = [
            line.strip()
            for line in Path(args.winners_file).read_text().splitlines()
            if line.strip() and not line.startswith("#")
        ]

    if not names:
        print("No winners specified")
        return 1

    BACKUP_DIR.mkdir(parents=True, exist_ok=True)
    log = json.loads(VISUAL_LOG.read_text())

    rows = []
    for name in names:
        orig = OUTPUT_DIR / f"{name}.png"
        regen = OUTPUT_DIR / f"{name}_regen.png"

        if not regen.exists():
            print(f"  [{name}] SKIP — no regen file at {regen.name}")
            rows.append((name, "no_regen"))
            continue

        if orig.exists():
            backup = BACKUP_DIR / f"{name}.png"
            if not backup.exists():
                shutil.copy2(orig, backup)
                print(f"  [{name}] backed up original to _regen_backup/")

        shutil.copy2(regen, orig)
        if not args.keep_regen:
            regen.unlink()

        if name in log["verdicts"]:
            log["verdicts"][name]["status"] = "passed"
            log["verdicts"][name]["note"] = args.note
            log["verdicts"][name]["regen_installed"] = True

        print(f"  [{name}] INSTALLED")
        rows.append((name, "installed"))

    VISUAL_LOG.write_text(json.dumps(log, indent=2))

    installed = sum(1 for _, s in rows if s == "installed")
    print()
    print(f"Installed {installed}/{len(rows)} winners. visual_review_log.json updated.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
