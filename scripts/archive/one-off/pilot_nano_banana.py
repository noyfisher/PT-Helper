"""
Pilot: regenerate failing FLUX images using Gemini image generation
("Nano Banana Pro" = gemini-3-pro-image-preview).

Picks 6 score-1 FLUX failures covering diverse body positions, regenerates
each with Gemini's Pro image model, saves to scripts/output/nano_banana/,
and re-runs the same Gemini QA on the new images so scores are comparable.

Outputs per exercise:
  scripts/output/nano_banana/{name}.png    -- new image
  scripts/output/nano_banana/qa.json       -- QA scores

Usage:
  python scripts/pilot_nano_banana.py --api-key KEY
  python scripts/pilot_nano_banana.py --api-key KEY --only chin-tucks
  python scripts/pilot_nano_banana.py --api-key KEY --model gemini-2.5-flash-image-preview
"""
from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path

from google import genai
from google.genai import types
from PIL import Image

SCRIPT_DIR = Path(__file__).resolve().parent
OUTPUT_DIR = SCRIPT_DIR / "output"
NB_DIR = OUTPUT_DIR / "nano_banana"
METADATA = OUTPUT_DIR / "all_exercises_metadata.json"

PILOT = [
    "chin-tucks",               # standing, very subtle (user flagged)
    "cat-camel-stretch",        # quadruped
    "eccentric-hamstring-curls",# prone
    "dumbbell-goblet-squats",   # standing + equipment
    "ankle-inversion-eversion", # seated + equipment detail
    "isometric-quad-contraction",# supine
]

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


def generate_one(client: genai.Client, model: str, prompt: str) -> bytes | None:
    """Call Gemini image generation. Returns PNG bytes or None."""
    try:
        resp = client.models.generate_content(
            model=model,
            contents=prompt,
            config=types.GenerateContentConfig(
                response_modalities=["IMAGE"],
            ),
        )
    except Exception as e:
        print(f"    API ERROR: {e}")
        return None

    # Parse response: find inline_data in parts
    for cand in (resp.candidates or []):
        if not cand.content or not cand.content.parts:
            continue
        for part in cand.content.parts:
            inline = getattr(part, "inline_data", None)
            if inline and inline.data:
                return inline.data
    print(f"    No image bytes in response. Prompt feedback: {getattr(resp, 'prompt_feedback', None)}")
    return None


def qa_one(client: genai.Client, image_path: Path, ex: dict) -> dict:
    """Run the same 9-check QA we use elsewhere on a new image."""
    # Reuse the QA module's analyze function
    sys.path.insert(0, str(SCRIPT_DIR))
    from qa_exercise_images import analyze_image  # noqa

    # Ensure the QA helper can find a 'normalized_filename' etc
    result = analyze_image(client, image_path, ex)
    return json.loads(result.model_dump_json())


def load_metadata() -> dict[str, dict]:
    with METADATA.open() as f:
        data = json.load(f)
    return {e["normalized_filename"]: e for e in data["exercises"]}


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--api-key", required=True)
    ap.add_argument("--model", default="gemini-3-pro-image-preview",
                    help="Image gen model. Default: gemini-3-pro-image-preview (Nano Banana Pro). "
                         "Alt: gemini-2.5-flash-image-preview (Nano Banana).")
    ap.add_argument("--only", help="Comma-separated subset of pilot names")
    ap.add_argument("--no-qa", action="store_true", help="Skip QA after generation")
    args = ap.parse_args()

    NB_DIR.mkdir(parents=True, exist_ok=True)
    meta = load_metadata()

    targets = PILOT
    if args.only:
        targets = [n.strip() for n in args.only.split(",") if n.strip()]

    client = genai.Client(api_key=args.api_key)

    results = {}
    for idx, name in enumerate(targets, 1):
        print(f"\n[{idx}/{len(targets)}] {name} ({args.model})")
        ex = meta.get(name)
        if not ex:
            print(f"  SKIP: no metadata for {name}")
            continue

        prompt = build_prompt(ex)
        print(f"  prompt: {prompt[:160].replace(chr(10), ' ')}...")

        img_bytes = generate_one(client, args.model, prompt)
        if not img_bytes:
            print(f"  FAIL: no image returned")
            results[name] = {"generated": False}
            time.sleep(2)
            continue

        out_path = NB_DIR / f"{name}.png"
        out_path.write_bytes(img_bytes)
        print(f"  OK -> {out_path}")

        entry = {"generated": True, "path": str(out_path)}

        if not args.no_qa:
            # Run QA using the same prompt as qa_exercise_images.py.
            # analyze_image expects the image in OUTPUT_DIR/{normalized_filename}.png,
            # so copy to a temp location and patch the filename. Simpler: save with
            # a temp normalized_filename pointing at the nano_banana subdir by symlink.
            tmp_name = f"nb_{name}"
            tmp_path = OUTPUT_DIR / f"{tmp_name}.png"
            tmp_path.write_bytes(img_bytes)
            tmp_ex = dict(ex)
            tmp_ex["normalized_filename"] = tmp_name
            try:
                qa = qa_one(client, tmp_path, tmp_ex)
                entry["qa"] = qa
                print(f"  QA: pose_score={qa.get('pose_score')}, overall_pass={qa.get('overall_pass')}")
                if qa.get("pose_accuracy", {}).get("observation"):
                    print(f"     obs: {qa['pose_accuracy']['observation'][:200]}")
            finally:
                try:
                    tmp_path.unlink()
                except OSError:
                    pass

        results[name] = entry
        time.sleep(2)  # gentle rate limit

    summary_path = NB_DIR / "qa.json"
    summary_path.write_text(json.dumps(results, indent=2))
    print(f"\n  Summary saved to {summary_path}")

    # Side-by-side comparison table
    print("\n" + "=" * 80)
    print(f"{'Exercise':<30} {'FLUX score':>12} {'NanoBanana':>14}")
    print("-" * 80)
    flux_report = json.loads((OUTPUT_DIR / "qa_all_starts_report.json").read_text())
    for name in targets:
        flux_score = flux_report["results"].get(name, {}).get("pose_score", "?")
        nb = results.get(name, {}).get("qa", {}).get("pose_score", "-")
        gen = "ok" if results.get(name, {}).get("generated") else "fail"
        print(f"{name:<30} {str(flux_score):>12} {str(nb):>10}  [{gen}]")
    print("=" * 80)

    return 0


if __name__ == "__main__":
    sys.exit(main())
