"""
Regenerate start images that scored below a threshold using Nano Banana Pro.

Steps:
  1. Read qa_all_starts_report.json; pick exercises with pose_score below the
     threshold (default 3), excluding API_ERROR cases.
  2. Back up each existing FLUX image to scripts/output/_flux_backup/.
  3. Generate a new image with gemini-3-pro-image-preview.
  4. Re-run the same 9-check Gemini QA on the new image.
  5. Update qa_all_starts_report.json in place so review_starts_server.py
     picks up the new scores on its next refresh.

Usage:
  python scripts/regen_with_nano_banana.py --api-key KEY
  python scripts/regen_with_nano_banana.py --api-key KEY --threshold 4
  python scripts/regen_with_nano_banana.py --api-key KEY --limit 20   # try a small batch first
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
BACKUP_DIR = OUTPUT_DIR / "_flux_backup"
METADATA = OUTPUT_DIR / "all_exercises_metadata.json"
QA_REPORT = OUTPUT_DIR / "qa_all_starts_report.json"

MODEL = "gemini-3-pro-image-preview"

CHARACTER_DESC = (
    "An athletic young man with short dark hair, lean fit build. "
    "He is wearing a fitted light gray athletic t-shirt, dark navy "
    "compression shorts, white ankle socks, and gray athletic sneakers."
)


def build_prompt(ex: dict) -> str:
    name = ex["name"]
    pose_desc = ex.get("pose_description", "") or f"A {ex.get('category','fitness')} exercise."
    body_pos = ex.get("body_position", "standing")
    return (
        f"Clean professional fitness illustration of a physical therapy exercise.\n\n"
        f"Subject: {CHARACTER_DESC}\n\n"
        f"Exercise: {name}\n"
        f"Body position: {body_pos}\n"
        f"Pose: {pose_desc}\n\n"
        f"Style: clean digital illustration, soft even studio lighting, plain white background, "
        f"no furniture or equipment unless specified in the pose description. "
        f"Single figure centered, full body visible from head to toe. "
        f"No text, labels, watermarks, arrows, or annotations anywhere in the image. "
        f"The pose must exactly match the described position."
    )


def generate_image(client: genai.Client, prompt: str) -> bytes | None:
    try:
        resp = client.models.generate_content(
            model=MODEL,
            contents=prompt,
            config=types.GenerateContentConfig(response_modalities=["IMAGE"]),
        )
    except Exception as e:
        print(f"    GEN ERROR: {e}")
        return None
    for cand in (resp.candidates or []):
        if cand.content and cand.content.parts:
            for part in cand.content.parts:
                inline = getattr(part, "inline_data", None)
                if inline and inline.data:
                    return inline.data
    print(f"    No image bytes in response. Feedback: {getattr(resp, 'prompt_feedback', None)}")
    return None


def pick_targets(threshold: int) -> list[str]:
    report = json.loads(QA_REPORT.read_text())
    targets = []
    for name, res in report["results"].items():
        score = res.get("pose_score")
        if score is None:
            continue
        if "API_ERROR" in res.get("critical_failures", []):
            continue
        if score < threshold:
            targets.append((name, score))
    targets.sort(key=lambda x: x[1])  # lowest first
    return [n for n, _ in targets]


def qa_new_image(client: genai.Client, img_path: Path, ex: dict) -> dict:
    # Delay the import so a missing qa script doesn't block regen
    sys.path.insert(0, str(SCRIPT_DIR))
    from qa_exercise_images import analyze_image

    result = analyze_image(client, img_path, ex)
    return json.loads(result.model_dump_json())


def update_report(name: str, new_qa: dict) -> None:
    report = json.loads(QA_REPORT.read_text())
    report["results"][name] = new_qa
    # Recompute aggregate counts
    total = len(report["results"])
    passed = sum(1 for v in report["results"].values() if v.get("overall_pass"))
    report["total_images"] = total
    report["passed"] = passed
    report["failed"] = total - passed
    QA_REPORT.write_text(json.dumps(report, indent=2))


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--api-key", required=True)
    ap.add_argument("--threshold", type=int, default=3,
                    help="Regen images with pose_score below this (default: 3)")
    ap.add_argument("--limit", type=int, default=0,
                    help="Cap number of images to regen (0 = all matching)")
    ap.add_argument("--only", help="Comma-separated subset")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    BACKUP_DIR.mkdir(parents=True, exist_ok=True)

    if args.only:
        targets = [n.strip() for n in args.only.split(",") if n.strip()]
    else:
        targets = pick_targets(args.threshold)

    if args.limit > 0:
        targets = targets[: args.limit]

    print(f"Will regenerate {len(targets)} images (threshold <{args.threshold})")
    if args.dry_run:
        for n in targets:
            print(f"  {n}")
        return 0

    meta = {e["normalized_filename"]: e
            for e in json.loads(METADATA.read_text())["exercises"]}

    client = genai.Client(api_key=args.api_key)

    upgraded = unchanged = regressed = failed = 0
    rows = []

    for idx, name in enumerate(targets, 1):
        ex = meta.get(name)
        if not ex:
            print(f"[{idx}/{len(targets)}] {name}: no metadata, skip")
            failed += 1
            continue

        old_score = json.loads(QA_REPORT.read_text())["results"][name].get("pose_score")
        print(f"\n[{idx}/{len(targets)}] {name}  (was {old_score}/5)")

        src = OUTPUT_DIR / f"{name}.png"
        if src.exists():
            backup = BACKUP_DIR / f"{name}.png"
            if not backup.exists():
                shutil.copy2(src, backup)

        prompt = build_prompt(ex)
        img_bytes = generate_image(client, prompt)
        if not img_bytes:
            print(f"  generation FAILED")
            failed += 1
            time.sleep(2)
            continue

        src.write_bytes(img_bytes)
        print(f"  generated -> {src.name}")

        qa = qa_new_image(client, src, ex)
        new_score = qa.get("pose_score")
        pose_pass = qa.get("overall_pass")
        obs = qa.get("pose_accuracy", {}).get("observation", "")
        print(f"  new score: {new_score}/5, overall_pass={pose_pass}")
        if obs:
            print(f"    obs: {obs[:180]}")

        update_report(name, qa)
        rows.append((name, old_score, new_score))

        if new_score is None or old_score is None:
            pass
        elif new_score > old_score:
            upgraded += 1
        elif new_score < old_score:
            regressed += 1
        else:
            unchanged += 1

        time.sleep(2)  # gentle rate limit

    # Summary
    print("\n" + "=" * 72)
    print("REGEN SUMMARY")
    print("=" * 72)
    print(f"  Attempted:  {len(targets)}")
    print(f"  Upgraded:   {upgraded}")
    print(f"  Unchanged:  {unchanged}")
    print(f"  Regressed:  {regressed}")
    print(f"  Failed:     {failed}")
    print()
    print(f"{'Exercise':<40} {'old':>6} {'new':>6}")
    for name, old, new in rows:
        arrow = "->" if (new or 0) > (old or 0) else ("==" if (new or 0) == (old or 0) else "vv")
        print(f"{name:<40} {str(old):>6} {arrow} {str(new):>4}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
