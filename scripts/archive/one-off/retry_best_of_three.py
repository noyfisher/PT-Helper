"""
Best-of-three retry for the remaining stuck <3 exercises.

Strategy:
  - For each stuck image, run the custom prompt (if defined) or generic prompt
    3 times. Each generation is non-deterministic so results vary.
  - QA each candidate, keep the best by pose_score.
  - Compare best candidate to current image's score (and to _nb_round1_backup
    if current is a round-2 regression) and install whichever wins.

Outputs:
  scripts/output/{name}.png                       -- best-of-three winner
  scripts/output/_best_of_three/{name}_v{1,2,3}.png -- all candidates for audit
"""
from __future__ import annotations

import argparse
import json
import shutil
import sys
import time
from pathlib import Path

from google import genai
from google.genai import types

SCRIPT_DIR = Path(__file__).resolve().parent
OUTPUT_DIR = SCRIPT_DIR / "output"
CAND_DIR = OUTPUT_DIR / "_best_of_three"
BACKUP_R1 = OUTPUT_DIR / "_nb_round1_backup"
METADATA = OUTPUT_DIR / "all_exercises_metadata.json"
QA_REPORT = OUTPUT_DIR / "qa_all_starts_report.json"
MODEL = "gemini-3-pro-image-preview"
N_SEEDS = 3

SUBJECT = (
    "An athletic young man with short dark hair, lean fit build, "
    "wearing a fitted light gray athletic t-shirt, dark navy compression "
    "shorts, white ankle socks, and gray athletic sneakers."
)
STYLE = (
    "Style: clean professional fitness illustration, soft even studio lighting, "
    "plain white background, no text or labels. Single figure centered, full "
    "body visible from head to toe. The pose must EXACTLY match what is described."
)

# Reuse custom prompts from the retry_stuck script
sys.path.insert(0, str(SCRIPT_DIR))
from retry_stuck_with_custom_prompts import CUSTOM  # noqa


def build_prompt(name: str, ex: dict, variation: int) -> str:
    if name in CUSTOM:
        pose = CUSTOM[name]
    else:
        pose = ex.get("pose_description", "") or "Follow standard form."

    # Small variation cues to diversify the three seeds
    angle_hints = [
        "Composition: balanced centered framing.",
        "Composition: slight three-quarter angle showing the body clearly.",
        "Composition: camera positioned for maximum clarity of the working body part.",
    ]
    hint = angle_hints[variation % len(angle_hints)]

    return (
        f"Clean professional fitness illustration.\n\n"
        f"Subject: {SUBJECT}\n\n"
        f"Exercise: {ex['name']}\n\n"
        f"Pose (follow EXACTLY):\n{pose}\n\n"
        f"{hint}\n\n{STYLE}"
    )


def generate(client: genai.Client, prompt: str) -> bytes | None:
    try:
        resp = client.models.generate_content(
            model=MODEL,
            contents=prompt,
            config=types.GenerateContentConfig(response_modalities=["IMAGE"]),
        )
    except Exception as e:
        print(f"      GEN ERROR: {e}")
        return None
    for cand in (resp.candidates or []):
        if cand.content and cand.content.parts:
            for p in cand.content.parts:
                d = getattr(p, "inline_data", None)
                if d and d.data:
                    return d.data
    return None


def qa_image(client: genai.Client, path: Path, ex: dict) -> dict:
    sys.path.insert(0, str(SCRIPT_DIR))
    from qa_exercise_images import analyze_image
    return json.loads(analyze_image(client, path, ex).model_dump_json())


def update_report(name: str, qa: dict) -> None:
    report = json.loads(QA_REPORT.read_text())
    report["results"][name] = qa
    total = len(report["results"])
    passed = sum(1 for v in report["results"].values() if v.get("overall_pass"))
    report["total_images"] = total
    report["passed"] = passed
    report["failed"] = total - passed
    QA_REPORT.write_text(json.dumps(report, indent=2))


def pick_stuck() -> list[str]:
    r = json.loads(QA_REPORT.read_text())
    return sorted(n for n, v in r["results"].items()
                  if v.get("pose_score") is not None
                  and v["pose_score"] < 3
                  and "API_ERROR" not in v.get("critical_failures", []))


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--api-key", required=True)
    ap.add_argument("--only", help="Comma-separated subset")
    ap.add_argument("--seeds", type=int, default=N_SEEDS)
    args = ap.parse_args()

    CAND_DIR.mkdir(parents=True, exist_ok=True)
    meta = {e["normalized_filename"]: e
            for e in json.loads(METADATA.read_text())["exercises"]}

    names = args.only.split(",") if args.only else pick_stuck()
    names = [n.strip() for n in names if n.strip()]

    client = genai.Client(api_key=args.api_key)

    rows = []
    for idx, name in enumerate(names, 1):
        ex = meta.get(name)
        if not ex:
            print(f"[{idx}/{len(names)}] {name}: no metadata, skip")
            continue

        old_qa = json.loads(QA_REPORT.read_text())["results"][name]
        old_score = old_qa.get("pose_score", 0) or 0
        print(f"\n[{idx}/{len(names)}] {name}  (current: {old_score}/5)")

        # Reference: round-1 backup, if exists
        r1_path = BACKUP_R1 / f"{name}.png"
        best_score = old_score
        best_bytes: bytes | None = None
        best_qa: dict | None = None
        best_variant = "current"

        for v in range(args.seeds):
            prompt = build_prompt(name, ex, v)
            img = generate(client, prompt)
            if not img:
                print(f"    v{v+1}: gen failed")
                time.sleep(1)
                continue
            cand_path = CAND_DIR / f"{name}_v{v+1}.png"
            cand_path.write_bytes(img)
            qa = qa_image(client, cand_path, ex)
            score = qa.get("pose_score") or 0
            print(f"    v{v+1}: score={score}/5")
            if score > best_score:
                best_score = score
                best_bytes = img
                best_qa = qa
                best_variant = f"v{v+1}"
            time.sleep(1)

        # Install winner if we beat the current image
        if best_bytes is not None:
            (OUTPUT_DIR / f"{name}.png").write_bytes(best_bytes)
            update_report(name, best_qa)
            print(f"  installed {best_variant} at score {best_score}")
        else:
            print(f"  kept current image (none of {args.seeds} beat {old_score})")

        rows.append((name, old_score, best_score, best_variant))
        time.sleep(1)

    print("\n" + "=" * 70)
    print("BEST-OF-THREE SUMMARY")
    print("=" * 70)
    improved = sum(1 for _, o, n, _ in rows if n > o)
    same = sum(1 for _, o, n, _ in rows if n == o)
    print(f"  Attempted: {len(rows)}   Improved: {improved}   Unchanged: {same}")
    print()
    print(f"{'Exercise':<42} {'old':>4} {'new':>4} {'winner':>10}")
    for n, o, nw, v in rows:
        arrow = "->" if nw > o else "=="
        print(f"{n:<42} {o:>4} {arrow} {nw:>2}  {v:>10}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
