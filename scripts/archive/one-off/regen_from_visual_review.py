"""
Regenerate failed images using visual_review_log.json notes as observations.

Unlike regen_with_auto_prompts.py (which uses QA-report observations that miss
variant-compliance failures), this script feeds the human-written visual review
note as the observation. The note describes exactly what went wrong.

For each failed image:
  1. Build a regen prompt using Gemini Flash (exercise + correct description + our note)
  2. Generate one image with NB Pro
  3. Save to {fname}_regen.png alongside the original (NO auto-install)
  4. Human reviews regen vs original separately and decides

Usage:
  python scripts/regen_from_visual_review.py --api-key KEY
  python scripts/regen_from_visual_review.py --api-key KEY --only dead-bug,external-rotation
  python scripts/regen_from_visual_review.py --api-key KEY --limit 5
"""
from __future__ import annotations

import argparse
import json
import signal
import sys
import time
from pathlib import Path

from google import genai
from google.genai import types


class _Timeout(Exception):
    pass


def _alarm_handler(signum, frame):
    raise _Timeout("API call timed out")


SCRIPT_DIR = Path(__file__).resolve().parent
OUTPUT_DIR = SCRIPT_DIR / "output"
METADATA = OUTPUT_DIR / "all_exercises_metadata.json"
VISUAL_LOG = OUTPUT_DIR / "visual_review_log.json"
GEN_MODEL = "gemini-3-pro-image-preview"

SUBJECT = (
    "An athletic young man with short dark hair, lean fit build, "
    "wearing a fitted light gray athletic t-shirt, dark navy compression "
    "shorts, white ankle socks, and gray athletic sneakers."
)

PROMPT_GEN_TEMPLATE = """You are a prompt engineer specializing in fitness exercise illustration generation.

Exercise: {name}
Target area: {target_area}
Body position: {body_position}

CORRECT start-position description:
\"\"\"{description}\"\"\"

The PREVIOUS image was visually reviewed by a human and FAILED with this specific reason:
\"\"\"{observation}\"\"\"

Your job: write an image-generation prompt for Nano Banana Pro that produces a CORRECT illustration.
Your prompt MUST:
1. Start with the character description: "{subject}"
2. Describe the EXACT correct pose in step-by-step detail. Be very explicit about
   the specific anatomical features the previous image got wrong (joint angles,
   limb positions, equipment placement, body orientation, support surfaces).
3. Include explicit ANTI-CUES naming what NOT to show (e.g., "Do NOT show both
   arms forward" or "Do NOT show both feet planted").
4. Specify the best camera angle to clearly show this exercise's distinguishing
   features (front, side, three-quarter, top-down, etc.).
5. End with: "Style: clean professional fitness illustration, soft even studio
   lighting, plain white background, no text or labels. Single figure centered,
   full body visible from head to toe."

Respond with ONLY the prompt text (no JSON, no commentary, no markdown).
Keep it under 300 words."""


def generate_prompt(client: genai.Client, ex: dict, observation: str) -> str | None:
    prompt = PROMPT_GEN_TEMPLATE.format(
        name=ex.get("name", ex.get("normalized_filename", "?")),
        target_area=ex.get("target_area", "?"),
        body_position=ex.get("body_position", "?"),
        description=(ex.get("pose_description") or "").strip(),
        observation=observation.strip(),
        subject=SUBJECT,
    )
    signal.alarm(60)
    try:
        resp = client.models.generate_content(
            model="gemini-2.5-flash",
            contents=prompt,
        )
    except _Timeout:
        print("    PROMPT-GEN TIMEOUT")
        return None
    except Exception as e:
        print(f"    PROMPT-GEN ERROR: {e}")
        return None
    finally:
        signal.alarm(0)
    return resp.text.strip() if resp.text else None


def generate_image(client: genai.Client, prompt: str) -> bytes | None:
    signal.alarm(120)
    try:
        resp = client.models.generate_content(
            model=GEN_MODEL,
            contents=prompt,
            config=types.GenerateContentConfig(response_modalities=["IMAGE"]),
        )
    except _Timeout:
        print("    IMG-GEN TIMEOUT")
        return None
    except Exception as e:
        print(f"    IMG-GEN ERROR: {e}")
        return None
    finally:
        signal.alarm(0)
    for cand in (resp.candidates or []):
        if cand.content and cand.content.parts:
            for p in cand.content.parts:
                d = getattr(p, "inline_data", None)
                if d and d.data:
                    return d.data
    return None


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--api-key", required=True)
    ap.add_argument("--only", help="Comma-separated subset of fnames")
    ap.add_argument("--limit", type=int, help="Cap number of images to regen")
    ap.add_argument("--suffix", default="_regen",
                    help="Filename suffix for regen output (default: _regen)")
    args = ap.parse_args()

    signal.signal(signal.SIGALRM, _alarm_handler)

    log = json.loads(VISUAL_LOG.read_text())
    meta_data = json.loads(METADATA.read_text())
    meta = {e["normalized_filename"]: e for e in meta_data["exercises"]}

    failed = {k: v for k, v in log["verdicts"].items() if v.get("status") == "failed"}
    if args.only:
        keep = {n.strip() for n in args.only.split(",")}
        failed = {k: v for k, v in failed.items() if k in keep}

    names = sorted(failed.keys())
    if args.limit:
        names = names[: args.limit]

    print(f"Regenerating {len(names)} images using visual review notes")
    print(f"Output suffix: {args.suffix}")
    print()

    client = genai.Client(api_key=args.api_key)
    rows = []

    for idx, name in enumerate(names, 1):
        ex = meta.get(name)
        verdict = failed[name]
        observation = verdict.get("note", "(no observation recorded)")

        print(f"[{idx}/{len(names)}] {name}")
        print(f"  obs: {observation[:100]}{'...' if len(observation) > 100 else ''}")

        if not ex:
            print("  SKIP: no metadata")
            rows.append((name, "no_metadata"))
            continue

        gen_prompt = generate_prompt(client, ex, observation)
        if not gen_prompt:
            print("  SKIP: prompt generation failed")
            rows.append((name, "prompt_fail"))
            continue
        print(f"  prompt ({len(gen_prompt)} chars)")

        img_bytes = generate_image(client, gen_prompt)
        if not img_bytes:
            print("  SKIP: image generation failed")
            rows.append((name, "gen_fail"))
            continue

        out_path = OUTPUT_DIR / f"{name}{args.suffix}.png"
        out_path.write_bytes(img_bytes)
        print(f"  WROTE {out_path.name} ({len(img_bytes)} bytes)")
        rows.append((name, "regen_saved"))

        time.sleep(2)

    print()
    print("=" * 60)
    print("SUMMARY")
    print("=" * 60)
    success = sum(1 for _, s in rows if s == "regen_saved")
    print(f"Saved: {success}/{len(rows)}")
    for name, status in rows:
        marker = "OK" if status == "regen_saved" else "FAIL"
        print(f"  [{marker:4}] {name}  ({status})")
    print()
    print(f"Regen images saved with suffix '{args.suffix}'.")
    print("Review them visually before installing.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
