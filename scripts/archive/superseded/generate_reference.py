#!/usr/bin/env python3
"""
Generate the reference character image for PT Helper exercise illustrations.

Creates a consistent body model that will be used across all exercise images.
Run this ONCE, review the output, and keep the best result at:
    scripts/reference/character_reference.png

Usage:
    python generate_reference.py --api-key YOUR_BFL_API_KEY
    python generate_reference.py --api-key YOUR_KEY --variants 4
    python generate_reference.py --api-key YOUR_KEY --dry-run

Prerequisites:
    pip install requests Pillow
"""

import argparse
import base64
import json
import sys
import time
from io import BytesIO
from pathlib import Path

try:
    import requests
except ImportError:
    print("ERROR: requests package not installed.")
    print("Run: pip install requests Pillow")
    sys.exit(1)

try:
    from PIL import Image
except ImportError:
    print("ERROR: Pillow package not installed.")
    print("Run: pip install Pillow")
    sys.exit(1)

# ---------- Constants ----------

SCRIPT_DIR = Path(__file__).parent
REFERENCE_DIR = SCRIPT_DIR / "reference"
OUTPUT_PATH = REFERENCE_DIR / "character_reference.png"

BFL_API_URL = "https://api.bfl.ai/v1/flux-kontext-pro"
BFL_POLL_INTERVAL = 1.5

# This prompt defines the character that will appear in every exercise image.
# Change it here to alter the body model used across all exercises.
CHARACTER_PROMPT = (
    "Create a clean, professional digital illustration of a friendly humanoid robot "
    "standing in a neutral anatomical position (arms slightly away from the body, "
    "palms forward, feet shoulder-width apart). "
    "The robot has a sleek, modern design with smooth rounded joints and limbs that "
    "clearly mirror human anatomy — shoulders, elbows, wrists, hips, knees, ankles "
    "are all visible and articulated. The body is matte white and light gray with "
    "subtle blue accent lines along the joints and chest plate. "
    "The head is rounded with a simple friendly face — two soft glowing blue circular "
    "eyes and a slight smile line. The proportions match an athletic human build so "
    "exercise poses are easy to understand. "
    "\n\n"
    "Style: Modern semi-realistic fitness app illustration. Soft, even studio "
    "lighting on a plain white background. Smooth clean lines with subtle "
    "shading to show the robot's form and joint articulation. Polished and minimal "
    "— no text, no labels, no watermarks, no background elements. "
    "The figure is centered and shown from a front-facing view, full body "
    "visible from head to toe. Proper anatomical proportions throughout."
)


def generate_reference(api_key: str, seed: int = 42) -> bytes | None:
    """Generate a single reference character image via FLUX Kontext Pro."""
    headers = {
        "accept": "application/json",
        "x-key": api_key,
        "Content-Type": "application/json",
    }

    payload = {
        "prompt": CHARACTER_PROMPT,
        "aspect_ratio": "3:4",  # Portrait — shows full body well
        "output_format": "png",
        "safety_tolerance": 6,
        "seed": seed,
    }

    print(f"  Submitting generation request (seed={seed})...")
    resp = requests.post(BFL_API_URL, headers=headers, json=payload, timeout=30)

    if resp.status_code == 402:
        print("  ERROR: Insufficient BFL credits — add funds at https://dashboard.bfl.ai")
        return None

    resp.raise_for_status()
    data = resp.json()

    polling_url = data.get("polling_url")
    if not polling_url:
        rid = data.get("id")
        if rid:
            polling_url = f"https://api.bfl.ai/v1/get_result?id={rid}"
        else:
            print("  ERROR: No polling URL in response")
            return None

    print("  Waiting for generation...", end="", flush=True)
    for _ in range(120):
        time.sleep(BFL_POLL_INTERVAL)
        print(".", end="", flush=True)
        poll = requests.get(polling_url, headers=headers, timeout=30).json()
        status = poll.get("status", "Unknown")

        if status == "Ready":
            print(" done!")
            img_url = poll.get("result", {}).get("sample")
            if not img_url:
                print("  ERROR: Ready but no image URL")
                return None
            img_resp = requests.get(img_url, timeout=60)
            img_resp.raise_for_status()
            return img_resp.content

        if status in ("Error", "Failed"):
            print(f"\n  ERROR: {poll.get('error', status)}")
            return None

    print("\n  TIMEOUT waiting for generation")
    return None


def save_reference(image_data: bytes, filepath: Path) -> bool:
    """Save the reference image."""
    try:
        img = Image.open(BytesIO(image_data))
        if img.mode == "RGBA":
            bg = Image.new("RGB", img.size, (255, 255, 255))
            bg.paste(img, mask=img.split()[3])
            img = bg
        elif img.mode != "RGB":
            img = img.convert("RGB")
        img.save(filepath, "PNG", optimize=True)
        return True
    except Exception as e:
        print(f"  ERROR saving: {e}")
        return False


def main():
    parser = argparse.ArgumentParser(
        description="Generate the reference character image for PT Helper"
    )
    parser.add_argument(
        "--api-key", required=True,
        help="BFL (Black Forest Labs) API key",
    )
    parser.add_argument(
        "--variants", type=int, default=1,
        help="Number of variants to generate (default: 1). "
             "Each uses a different seed so you can pick the best.",
    )
    parser.add_argument(
        "--dry-run", action="store_true",
        help="Show the prompt without making API calls",
    )
    args = parser.parse_args()

    REFERENCE_DIR.mkdir(parents=True, exist_ok=True)

    print("=" * 60)
    print("  PT Helper — Reference Character Generator")
    print("=" * 60)
    print()
    print("Character prompt:")
    print("-" * 40)
    print(CHARACTER_PROMPT)
    print("-" * 40)
    print()

    if args.dry_run:
        print("[DRY RUN] Would generate reference image. No API calls made.")
        return

    seeds = [42, 123, 7, 2024, 99, 314, 256, 512]
    num = min(args.variants, len(seeds))

    for i in range(num):
        seed = seeds[i]
        suffix = f"_v{i + 1}" if num > 1 else ""
        filepath = REFERENCE_DIR / f"character_reference{suffix}.png"

        print(f"[{i + 1}/{num}] Generating variant (seed={seed})...")
        image_data = generate_reference(args.api_key, seed=seed)

        if image_data and save_reference(image_data, filepath):
            kb = filepath.stat().st_size / 1024
            print(f"  Saved: {filepath} ({kb:.0f} KB)")
        else:
            print(f"  FAILED to generate variant {i + 1}")

        if i < num - 1:
            time.sleep(2)

    print()
    print("=" * 60)
    print("  DONE")
    print("=" * 60)

    if num > 1:
        print(f"\n  Review the {num} variants in {REFERENCE_DIR}/")
        print(f"  Rename your favorite to: character_reference.png")
        print(f"  Then delete the others.")
    else:
        print(f"\n  Reference image saved to: {OUTPUT_PATH}")
        print("  Review it and re-generate with a different --variants count if needed.")

    print("\n  Next: python generate_exercise_images.py --api-key YOUR_KEY")


if __name__ == "__main__":
    main()
