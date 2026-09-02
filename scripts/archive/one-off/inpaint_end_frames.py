"""
Pilot: generate end-frame images via FLUX Fill (inpainting).

Takes the already-QA-passed start image + a manually-drawn mask + the
exercise's end_pose_description, and asks FLUX Fill to regenerate only
the masked region. Scene, camera, clothing, non-moving body parts are
preserved from the start image.

Inputs per exercise (read from scripts/output/):
  {normalized_filename}.png       -- start image (must exist)
  {normalized_filename}_mask.png  -- manually-drawn mask (must exist)

Output:
  scripts/output/{normalized_filename}_end.png  -- inpainted end frame

Usage:
  python scripts/inpaint_end_frames.py --api-key $BFL_API_KEY
  python scripts/inpaint_end_frames.py --api-key $BFL_API_KEY --overwrite
  python scripts/inpaint_end_frames.py --only chin-tucks,quad-sets
"""

from __future__ import annotations

import argparse
import base64
import json
import subprocess
import sys
import time
from pathlib import Path

import requests

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
BFL_FILL_URL = "https://api.bfl.ai/v1/flux-pro-1.0-fill"
BFL_POLL_INTERVAL = 1.5       # seconds between status polls
BFL_POLL_MAX_ITERS = 120      # ~3 min max per image
RATE_LIMIT_DELAY = 8          # seconds between requests

SCRIPT_DIR = Path(__file__).resolve().parent
OUTPUT_DIR = SCRIPT_DIR / "output"
EXERCISE_LIST = SCRIPT_DIR / "exercise_list.json"

# 10 pilot exercises, diverse across body position and movement scale
PILOT_EXERCISES = [
    "quad-sets",                   # supine, subtle isometric
    "straight-leg-raises",         # supine, large
    "heel-slides",                 # supine, medium
    "clamshells",                  # side-lying, medium
    "side-lying-hip-abduction",    # side-lying, medium
    "standing-hip-abduction",      # standing, medium
    "chin-tucks",                  # standing, very subtle
    "prone-knee-flexion",          # prone, large
    "seated-knee-extension",       # seated, medium
    "wrist-curls",                 # subtle
]


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
def load_exercises() -> dict[str, dict]:
    with EXERCISE_LIST.open() as f:
        data = json.load(f)
    return {e["normalized_filename"]: e for e in data["exercises"]}


def get_api_key_from_keychain() -> str | None:
    """Try macOS Keychain fallback (service=BFL_API_KEY)."""
    try:
        result = subprocess.run(
            ["security", "find-generic-password", "-s", "BFL_API_KEY", "-w"],
            capture_output=True, text=True, timeout=5,
        )
        if result.returncode == 0:
            key = result.stdout.strip()
            if key:
                return key
    except (FileNotFoundError, subprocess.TimeoutExpired):
        pass
    return None


def file_to_base64(path: Path) -> str:
    return base64.b64encode(path.read_bytes()).decode("ascii")


# ---------------------------------------------------------------------------
# FLUX Fill request + polling
# ---------------------------------------------------------------------------
def inpaint_one(
    *,
    api_key: str,
    start_b64: str,
    mask_b64: str,
    prompt: str,
    label: str,
) -> bytes | None:
    """
    POST to FLUX Fill and poll until ready. Returns image bytes or None.

    Pattern mirrors scripts/generate_exercise_images.py:544-600 but with
    the Fill-specific payload schema (image + mask).
    """
    payload = {
        "image": start_b64,
        "mask": mask_b64,
        "prompt": prompt,
        "steps": 50,
        "guidance": 60,
        "output_format": "png",
        "safety_tolerance": 6,
        "prompt_upsampling": False,
    }
    headers = {
        "accept": "application/json",
        "x-key": api_key,
        "Content-Type": "application/json",
    }

    max_retries = 3
    for attempt in range(max_retries):
        try:
            resp = requests.post(BFL_FILL_URL, headers=headers, json=payload, timeout=30)

            if resp.status_code == 402:
                print(f"  ERROR: Insufficient BFL credits -- https://dashboard.bfl.ai")
                return None
            if resp.status_code == 429:
                wait = 30 * (attempt + 1)
                print(f"  RATE LIMITED, waiting {wait}s (retry {attempt + 1}/{max_retries})")
                time.sleep(wait)
                continue
            if resp.status_code == 404:
                print(f"  ERROR 404: Fill endpoint not found at {BFL_FILL_URL}")
                print(f"  Response body: {resp.text[:300]}")
                return None

            resp.raise_for_status()
            data = resp.json()

            polling_url = data.get("polling_url")
            if not polling_url:
                rid = data.get("id")
                if rid:
                    polling_url = f"https://api.bfl.ai/v1/get_result?id={rid}"
                else:
                    print(f"  ERROR: No polling URL. Response: {data}")
                    continue

            for _ in range(BFL_POLL_MAX_ITERS):
                time.sleep(BFL_POLL_INTERVAL)
                poll = requests.get(polling_url, headers=headers, timeout=30).json()
                status = poll.get("status", "Unknown")

                if status == "Ready":
                    img_url = poll.get("result", {}).get("sample")
                    if not img_url:
                        print(f"  ERROR: Ready but no sample URL")
                        break
                    img_resp = requests.get(img_url, timeout=60)
                    img_resp.raise_for_status()
                    return img_resp.content

                if status in ("Error", "Failed", "Content Moderated", "Request Moderated"):
                    print(f"  ERROR from API: {status} -- {poll.get('error') or poll}")
                    break
            else:
                print(f"  TIMEOUT waiting for {label}")

        except requests.exceptions.RequestException as e:
            print(f"  REQUEST ERROR: {e}")

        if attempt < max_retries - 1:
            time.sleep(5)

    print(f"  FAILED after {max_retries} retries for {label}")
    return None


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--api-key", help="BFL API key (or stored in Keychain as BFL_API_KEY)")
    ap.add_argument("--overwrite", action="store_true",
                    help="Overwrite existing _end.png files (default: skip)")
    ap.add_argument("--only", help="Comma-separated subset of pilot names to run")
    args = ap.parse_args()

    api_key = args.api_key or get_api_key_from_keychain()
    if not api_key:
        print("ERROR: No BFL API key. Pass --api-key or store in Keychain (service=BFL_API_KEY)")
        return 2

    exercises = load_exercises()

    target_names = PILOT_EXERCISES
    if args.only:
        target_names = [n.strip() for n in args.only.split(",") if n.strip()]

    results = []
    for idx, name in enumerate(target_names, 1):
        print(f"\n[{idx}/{len(target_names)}] {name}")

        ex = exercises.get(name)
        if not ex:
            print(f"  SKIP: not found in exercise_list.json")
            results.append((name, "missing_metadata"))
            continue

        start_path = OUTPUT_DIR / f"{name}.png"
        mask_path = OUTPUT_DIR / f"{name}_mask.png"
        end_path = OUTPUT_DIR / f"{name}_end.png"

        if not start_path.exists():
            print(f"  SKIP: missing start image {start_path}")
            results.append((name, "missing_start"))
            continue
        if not mask_path.exists():
            print(f"  SKIP: missing mask {mask_path}")
            print(f"        Draw a mask (white = regenerate, black = keep) and save to {mask_path}")
            results.append((name, "missing_mask"))
            continue
        if end_path.exists() and not args.overwrite:
            print(f"  SKIP: {end_path.name} already exists (pass --overwrite to replace)")
            results.append((name, "exists"))
            continue

        end_prompt = ex.get("end_pose_description", "").strip()
        if not end_prompt:
            print(f"  SKIP: no end_pose_description in exercise_list.json")
            results.append((name, "missing_end_desc"))
            continue

        print(f"  Start: {start_path.name}")
        print(f"  Mask:  {mask_path.name}")
        print(f"  Prompt: {end_prompt[:120]}{'...' if len(end_prompt) > 120 else ''}")

        start_b64 = file_to_base64(start_path)
        mask_b64 = file_to_base64(mask_path)

        img_bytes = inpaint_one(
            api_key=api_key,
            start_b64=start_b64,
            mask_b64=mask_b64,
            prompt=end_prompt,
            label=name,
        )

        if img_bytes:
            end_path.write_bytes(img_bytes)
            print(f"  OK -> {end_path}")
            results.append((name, "ok"))
        else:
            print(f"  FAIL")
            results.append((name, "failed"))

        # Rate limit between requests
        if idx < len(target_names):
            time.sleep(RATE_LIMIT_DELAY)

    # Summary
    print("\n" + "=" * 60)
    print("PILOT SUMMARY")
    print("=" * 60)
    by_status: dict[str, list[str]] = {}
    for name, status in results:
        by_status.setdefault(status, []).append(name)
    for status, names in sorted(by_status.items()):
        print(f"  {status}: {len(names)}")
        for n in names:
            print(f"    - {n}")

    ok_count = len(by_status.get("ok", []))
    total = len(results)
    print(f"\nGenerated: {ok_count}/{total}")

    return 0 if ok_count > 0 else 1


if __name__ == "__main__":
    sys.exit(main())
