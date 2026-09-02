#!/usr/bin/env python3
"""
Generate exercise animation GIFs using FLUX 2 Pro (end frames) + Pika Pikaframes (video).

Pipeline per exercise:
  1. Load existing start-position PNG from ../output/{name}.png
  2. Generate end-position frame via FLUX 2 Pro (BFL API) → output/end-frames/{name}_end.png
  3. Submit start + end images to Pika Pikaframes (fal.ai) → output/videos/{name}.mp4
  4. Convert MP4 → looping GIF → output/gifs/{name}_anim.gif

Usage:
    python generate.py --bfl-api-key KEY --fal-api-key KEY --exercises pilot
    python generate.py --bfl-api-key KEY --fal-api-key KEY --exercises bird-dog,clamshells
    python generate.py --fal-api-key KEY --exercises bird-dog --skip-end-frame
    python generate.py --dry-run
    python generate.py --bfl-api-key KEY --exercises bird-dog --step end-frame

Prerequisites:
    pip install -r requirements.txt
    ffmpeg must be on PATH (for MP4 → GIF conversion)
"""

import argparse
import json
import os
import subprocess
import sys
import time
from io import BytesIO
from pathlib import Path

try:
    import requests
except ImportError:
    print("ERROR: requests not installed. Run: pip install -r requirements.txt")
    sys.exit(1)

try:
    from PIL import Image
except ImportError:
    print("ERROR: Pillow not installed. Run: pip install -r requirements.txt")
    sys.exit(1)


# ---------- Paths ----------

SCRIPT_DIR = Path(__file__).parent
CONFIG_PATH = SCRIPT_DIR / "config.json"
PARENT_SCRIPTS_DIR = SCRIPT_DIR.parent
EXERCISE_LIST_PATH = PARENT_SCRIPTS_DIR / "exercise_list.json"
START_FRAMES_DIR = PARENT_SCRIPTS_DIR / "output"

OUTPUT_DIR = SCRIPT_DIR / "output"
END_FRAMES_DIR = OUTPUT_DIR / "end-frames"
VIDEOS_DIR = OUTPUT_DIR / "videos"
GIFS_DIR = OUTPUT_DIR / "gifs"


# ---------- Load config ----------

def load_config() -> dict:
    with open(CONFIG_PATH) as f:
        return json.load(f)


def load_exercise_list() -> list[dict]:
    with open(EXERCISE_LIST_PATH) as f:
        return json.load(f)["exercises"]


# ---------- BFL API constants ----------

BFL_API_URL = "https://api.bfl.ai/v1/flux-2-pro"
BFL_POLL_INTERVAL = 1.5
OUTPUT_SIZE = 1024

# Consistent character across all frames
CHARACTER_DESC = (
    "Short dark hair, lean fit build, wearing fitted light gray "
    "athletic t-shirt, dark navy compression shorts, white ankle "
    "socks, and gray athletic sneakers"
)

FLUX2_BODY_POSITIONS = {
    "supine": "lying flat on his back on the ground, face up, back touching the floor",
    "prone": "lying flat on his stomach on the ground, face down, chest and belly pressing into the floor, back facing up toward camera",
    "side_lying": "lying on his side on the ground",
    "quadruped": "on all fours with both hands and both knees on the floor in a tabletop position",
    "standing": "standing upright",
    "seated": "seated, sitting down",
    "kneeling": "kneeling on the ground",
    "foam_roller": "on the ground with a cylindrical foam roller",
    "wall_sit": "in a wall sit with back flat against a wall, knees bent at 90 degrees",
}

# Camera angle heuristics (from generate_exercise_images.py)
_SIDE_KEYWORDS = [
    "squat", "lunge", "deadlift", "plank", "push-up", "pushup",
    "bird dog", "cat-cow", "bridge", "superman", "step-up",
    "heel slide", "leg raise", "hamstring curl", "calf raise",
    "wall sit", "prone", "quadruped", "child", "cobra", "pike",
    "mountain climber", "burpee", "hip hinge", "good morning",
]
_THREE_QUARTER_KEYWORDS = [
    "row", "press", "curl", "extension", "rotation",
    "fly", "raise", "pull", "swing", "chop", "kickback",
    "woodchop", "farmer", "carry", "snatch", "clean",
]
_FRONT_KEYWORDS = [
    "stretch", "standing", "balance", "abduction", "adduction",
    "clamshell", "fire hydrant", "monster walk", "band walk",
    "shoulder shrug", "neck", "wrist", "hand", "finger",
    "ankle alphabet", "ankle circle", "jumping jack",
]


def _get_viewing_angle(name: str) -> str:
    lower = name.lower()
    if any(kw in lower for kw in _SIDE_KEYWORDS):
        return "side profile"
    if any(kw in lower for kw in _THREE_QUARTER_KEYWORDS):
        return "three-quarter (45-degree)"
    if any(kw in lower for kw in _FRONT_KEYWORDS):
        return "front-facing"
    return "three-quarter (45-degree)"


# ---------------------------------------------------------------------------
# End-position descriptions for pilot exercises
# These describe the END state of the movement (opposite of start frame)
# ---------------------------------------------------------------------------
END_POSITION_DESCRIPTIONS = {
    "wall-slides": {
        "description": (
            "Standing with back flat against a wall. Both arms are raised fully "
            "overhead with elbows straight, hands and forearms still touching the "
            "wall. Arms in a Y position above the head. Shoulders fully flexed. "
            "This is the top position of a wall slide exercise."
        ),
        "angle": "side profile",
    },
    "standing-hip-abduction": {
        "description": (
            "Standing upright on the left leg. The right leg is lifted straight "
            "out to the side at approximately 45 degrees from the body. The right "
            "knee is straight and locked. Torso remains upright, not leaning. "
            "Hands on hips for balance."
        ),
        "angle": "front-facing",
    },
    "pendulum-swings": {
        "description": (
            "Standing next to a table with the left hand resting on it for support. "
            "The upper body is bent forward at the hips at about 45 degrees. "
            "The right arm hangs freely and has swung forward to the front of "
            "its arc, extended in front of the body. The arm is completely relaxed."
        ),
        "angle": "side profile",
    },
    "bird-dog": {
        "description": (
            "On all fours in a tabletop position on the ground. The right arm "
            "is extended fully forward, parallel to the ground, pointing ahead. "
            "The left leg is extended fully backward, parallel to the ground, "
            "pointing behind. The back is flat and level. Core is engaged. "
            "Only the left hand and right knee remain on the ground."
        ),
        "angle": "side profile",
    },
    "clamshells": {
        "description": (
            "Lying on the left side on the ground. Both knees are bent at about "
            "45 degrees. Feet are stacked together and remain touching. The top "
            "(right) knee is lifted and opened up toward the ceiling at maximum "
            "abduction, like a clamshell opening. The hips remain stacked and "
            "do not rotate backward."
        ),
        "angle": "front-facing",
    },
    "straight-leg-raises": {
        "description": (
            "Lying flat on the back on the ground, face up. The left knee is bent "
            "with foot flat on the floor. The right leg is raised straight up to "
            "approximately 45 degrees from the floor with the knee fully locked "
            "and straight. The toes are pointed toward the ceiling. Arms rest "
            "at the sides."
        ),
        "angle": "side profile",
    },
    "seated-knee-extension": {
        "description": (
            "Seated on a chair or bench. The right leg is extended fully forward, "
            "straight and parallel to the floor. The knee is locked. The quadriceps "
            "muscle on the front of the thigh is visibly engaged. The left foot "
            "remains flat on the ground. Hands grip the sides of the seat."
        ),
        "angle": "side profile",
    },
    "seated-calf-raises": {
        "description": (
            "Seated on a chair or bench with feet on the ground. Both heels are "
            "lifted high off the ground, rising up onto the balls of the feet. "
            "The calf muscles are visibly contracted and engaged. Hands rest "
            "on the thighs. Knees are bent at 90 degrees."
        ),
        "angle": "side profile",
    },
    "chin-tucks": {
        "description": (
            "Standing upright facing forward. The chin is drawn fully backward "
            "and downward, creating a pronounced double chin. The head is "
            "retracted straight back, not tilted up or down. The neck is "
            "elongated at the back. Shoulders remain relaxed and down."
        ),
        "angle": "side profile",
    },
    "scapular-squeezes": {
        "description": (
            "Standing upright. The shoulder blades are squeezed maximally together "
            "behind the back. The chest is pushed forward and open. The shoulders "
            "are pulled back. Both arms are at the sides with elbows slightly bent. "
            "The upper back muscles are visibly engaged."
        ),
        "angle": "three-quarter (45-degree)",
    },
}

# ---------------------------------------------------------------------------
# Start-position overrides for exercises where the original start frame is wrong.
# When present, generate.py will create a corrected start frame instead of
# using the one from ../output/.
# ---------------------------------------------------------------------------
START_POSITION_OVERRIDES = {
    "bird-dog": {
        "description": (
            "On all fours in a neutral tabletop position on the ground. "
            "Both hands are flat on the floor directly below the shoulders. "
            "Both knees are on the floor directly below the hips. The back "
            "is flat and level like a table. Head is in a neutral position "
            "looking down at the floor. No limbs are extended. All four "
            "points of contact are on the ground."
        ),
        "angle": "side profile",
    },
}

# Motion prompts for Pikaframes — describe the movement between frames
MOTION_PROMPTS = {
    "wall-slides": (
        "Smooth, controlled upward sliding motion of both arms along the wall, "
        "from a W shape at shoulder height to fully extended overhead in a Y shape, "
        "maintaining wall contact throughout. Slow, deliberate movement."
    ),
    "standing-hip-abduction": (
        "Controlled lifting of the right leg straight out to the side, keeping "
        "the knee locked and torso stable. Smooth lateral leg raise motion."
    ),
    "pendulum-swings": (
        "Gentle, relaxed swinging motion of the right arm from hanging straight "
        "down to swinging forward in a pendulum arc. The arm stays relaxed and "
        "gravity-driven. Natural, fluid motion."
    ),
    "bird-dog": (
        "Controlled, simultaneous extension of the right arm forward and left "
        "leg backward from a tabletop position. Smooth reaching motion while "
        "maintaining a flat, stable back. Core engaged throughout."
    ),
    "clamshells": (
        "Smooth opening of the top knee upward like a clamshell, rotating at "
        "the hip while keeping the feet together. Controlled hip external "
        "rotation movement."
    ),
    "straight-leg-raises": (
        "Controlled lifting of one straight leg upward from the ground to about "
        "45 degrees while lying on the back. Knee stays locked. Slow, deliberate "
        "upward motion."
    ),
    "seated-knee-extension": (
        "Smooth extension of the right leg from bent to fully straight while "
        "seated. The lower leg swings forward and up until parallel to the floor. "
        "Controlled quadriceps contraction."
    ),
    "seated-calf-raises": (
        "Both heels rising up from flat on the ground to maximum height on the "
        "balls of the feet while seated. Smooth upward motion of both heels "
        "simultaneously. Calf muscles contract."
    ),
    "chin-tucks": (
        "Subtle backward retraction of the chin straight back, creating a double "
        "chin. The head glides back without tilting up or down. Small, controlled "
        "movement of the head and neck."
    ),
    "scapular-squeezes": (
        "Shoulders pulling back and shoulder blades squeezing together behind "
        "the back. The chest opens forward. Controlled scapular retraction "
        "movement. Arms stay at the sides."
    ),
}


# ============================================================================
# Step 0: Generate corrected start-position frame (when original is wrong)
# ============================================================================

def _build_start_position_prompt(exercise: dict) -> str:
    """Build a FLUX 2 Pro prompt for a corrected start-position frame."""
    filename = exercise.get("normalized_filename", "")
    body_pos = exercise.get("body_position", "standing")

    override = START_POSITION_OVERRIDES.get(filename)
    if not override:
        return ""

    angle = override.get("angle", _get_viewing_angle(exercise["name"]))
    position_desc = FLUX2_BODY_POSITIONS.get(body_pos, "standing upright")

    subject_desc = (
        f"{CHARACTER_DESC}. "
        f"Body position: {position_desc}. "
        f"{override['description']}"
    )

    prompt_obj = {
        "scene": "Clean fitness studio with plain white background, no furniture, no equipment except what is described",
        "subjects": [
            {
                "type": "athletic young man",
                "description": subject_desc,
                "position": "centered, full body visible from head to toe",
            }
        ],
        "style": "Clean professional fitness illustration, digital art, soft even lighting",
        "lighting": "Soft, even studio lighting, no harsh shadows",
        "camera": {
            "angle": angle,
            "lens": "50mm",
            "f-number": "f/5.6",
        },
        "composition": "Single figure centered, full body visible, no text, no labels, no watermarks, no arrows, no annotations",
    }

    return json.dumps(prompt_obj)


def generate_start_frame(exercise: dict, api_key: str, *, dry_run: bool = False) -> bytes | None:
    """Generate a corrected start-position image for an exercise using FLUX 2 Pro."""
    name = exercise["name"]
    prompt = _build_start_position_prompt(exercise)

    if not prompt:
        print(f"  No start-position override for '{name}', using original")
        return None

    if dry_run:
        print(f"  [DRY RUN] Start-frame override prompt for: {name}")
        prompt_preview = json.loads(prompt)
        desc = prompt_preview["subjects"][0]["description"]
        print(f"    Description: {desc[:200]}...")
        return None

    seed = (hash(name) + 7777) % (2**32)  # Different seed from start and end
    print(f"  Generating corrected start frame via FLUX 2 Pro...", end="", flush=True)
    result = _call_bfl_api(prompt, api_key, seed=seed, label=f"{name} (start-fix)")
    if result:
        print(f" done ({len(result)} bytes)")
    return result


# ============================================================================
# Step 1: Generate end-position frame via FLUX 2 Pro
# ============================================================================

def _build_end_position_prompt(exercise: dict) -> str:
    """Build a FLUX 2 Pro prompt for the end-position of an exercise."""
    filename = exercise.get("normalized_filename", "")
    body_pos = exercise.get("body_position", "standing")
    name = exercise["name"]

    end_info = END_POSITION_DESCRIPTIONS.get(filename)
    if not end_info:
        print(f"  WARNING: No end-position description for '{filename}', skipping")
        return ""

    angle = end_info.get("angle", _get_viewing_angle(name))
    position_desc = FLUX2_BODY_POSITIONS.get(body_pos, "standing upright")

    subject_desc = (
        f"{CHARACTER_DESC}. "
        f"Body position: {position_desc}. "
        f"{end_info['description']}"
    )

    prompt_obj = {
        "scene": "Clean fitness studio with plain white background, no furniture, no equipment except what is described",
        "subjects": [
            {
                "type": "athletic young man",
                "description": subject_desc,
                "position": "centered, full body visible from head to toe",
            }
        ],
        "style": "Clean professional fitness illustration, digital art, soft even lighting",
        "lighting": "Soft, even studio lighting, no harsh shadows",
        "camera": {
            "angle": angle,
            "lens": "50mm",
            "f-number": "f/5.6",
        },
        "composition": "Single figure centered, full body visible, no text, no labels, no watermarks, no arrows, no annotations",
    }

    return json.dumps(prompt_obj)


def _call_bfl_api(
    prompt: str,
    api_key: str,
    *,
    seed: int | None = None,
    label: str = "",
) -> bytes | None:
    """Submit a FLUX 2 Pro generation request and poll for the result."""

    payload = {
        "prompt": prompt,
        "width": OUTPUT_SIZE,
        "height": OUTPUT_SIZE,
        "output_format": "png",
        "safety_tolerance": 5,
        "disable_pup": True,
    }
    if seed is not None:
        payload["seed"] = seed

    headers = {
        "accept": "application/json",
        "x-key": api_key,
        "Content-Type": "application/json",
    }

    max_retries = 3
    for attempt in range(max_retries):
        try:
            resp = requests.post(BFL_API_URL, headers=headers, json=payload, timeout=30)

            if resp.status_code == 402:
                print(f"\n  ERROR: Insufficient BFL credits — add funds at https://dashboard.bfl.ai")
                return None

            if resp.status_code == 429:
                wait = 30 * (attempt + 1)
                print(f"\n  RATE LIMITED, waiting {wait}s... (retry {attempt + 1}/{max_retries})")
                time.sleep(wait)
                continue

            resp.raise_for_status()
            data = resp.json()

            polling_url = data.get("polling_url")
            if not polling_url:
                rid = data.get("id")
                if rid:
                    polling_url = f"https://api.bfl.ai/v1/get_result?id={rid}"
                else:
                    print(f"\n  ERROR: No polling URL in API response")
                    continue

            for _ in range(120):
                time.sleep(BFL_POLL_INTERVAL)
                poll = requests.get(polling_url, headers=headers, timeout=30).json()
                status = poll.get("status", "Unknown")

                if status == "Ready":
                    img_url = poll.get("result", {}).get("sample")
                    if not img_url:
                        print(f"\n  ERROR: Ready but no image URL")
                        break
                    img_resp = requests.get(img_url, timeout=60)
                    img_resp.raise_for_status()
                    return img_resp.content

                if status in ("Error", "Failed"):
                    print(f"\n  ERROR from API: {poll.get('error', status)}")
                    break
            else:
                print(f"\n  TIMEOUT waiting for {label}")

        except requests.exceptions.RequestException as e:
            print(f"\n  ERROR: {e}")

        if attempt < max_retries - 1:
            time.sleep(5)

    print(f"\n  FAILED after {max_retries} retries for {label}")
    return None


def generate_end_frame(exercise: dict, api_key: str, *, dry_run: bool = False) -> bytes | None:
    """Generate the end-position image for an exercise using FLUX 2 Pro."""
    name = exercise["name"]
    prompt = _build_end_position_prompt(exercise)

    if not prompt:
        return None

    if dry_run:
        print(f"  [DRY RUN] End-frame prompt for: {name}")
        prompt_preview = json.loads(prompt)
        desc = prompt_preview["subjects"][0]["description"]
        print(f"    Description: {desc[:200]}...")
        return None

    seed = (hash(name) + 9999) % (2**32)  # Different seed from start frame
    print(f"  Generating end frame via FLUX 2 Pro...", end="", flush=True)
    result = _call_bfl_api(prompt, api_key, seed=seed, label=f"{name} (end)")
    if result:
        print(f" done ({len(result)} bytes)")
    return result


def save_image(image_data: bytes, filepath: Path) -> bool:
    """Save image data as a 1024x1024 optimized PNG."""
    try:
        filepath.parent.mkdir(parents=True, exist_ok=True)
        img = Image.open(BytesIO(image_data))
        img = img.resize((OUTPUT_SIZE, OUTPUT_SIZE), Image.Resampling.LANCZOS)
        if img.mode == "RGBA":
            bg = Image.new("RGB", img.size, (255, 255, 255))
            bg.paste(img, mask=img.split()[3])
            img = bg
        img.save(filepath, "PNG", optimize=True)
        return True
    except Exception as e:
        print(f"  ERROR saving image: {e}")
        return False


# ============================================================================
# Step 2: Submit to Pika Pikaframes via fal.ai
# ============================================================================

def submit_to_pikaframes(
    start_image_path: Path,
    end_image_path: Path,
    motion_prompt: str,
    fal_api_key: str,
    *,
    resolution: str = "720p",
    dry_run: bool = False,
) -> Path | None:
    """
    Submit start + end frame pair to Pika Pikaframes and download the MP4.

    Returns the path to the downloaded MP4, or None on failure.
    """
    exercise_name = start_image_path.stem  # e.g., "bird-dog"
    output_path = VIDEOS_DIR / f"{exercise_name}.mp4"

    if dry_run:
        print(f"  [DRY RUN] Would submit to Pikaframes:")
        print(f"    Start: {start_image_path}")
        print(f"    End:   {end_image_path}")
        print(f"    Motion: {motion_prompt[:100]}...")
        return None

    try:
        import fal_client
    except ImportError:
        print("  ERROR: fal-client not installed. Run: pip install fal-client")
        return None

    # Set fal.ai API key
    os.environ["FAL_KEY"] = fal_api_key

    print(f"  Uploading images to fal.ai...", end="", flush=True)
    try:
        start_url = fal_client.upload_file(str(start_image_path))
        end_url = fal_client.upload_file(str(end_image_path))
        print(f" done")
    except Exception as e:
        print(f"\n  ERROR uploading to fal.ai: {e}")
        return None

    print(f"  Submitting to Pikaframes...", end="", flush=True)
    try:
        result = fal_client.subscribe(
            "fal-ai/pika/v2.2/pikaframes",
            arguments={
                "image_urls": [start_url, end_url],
                "prompt": motion_prompt,
                "resolution": resolution,
            },
            with_logs=True,
            on_queue_update=lambda update: None,  # Suppress queue logs
        )
    except Exception as e:
        print(f"\n  ERROR from Pikaframes: {e}")
        return None

    # Download the video
    video_url = result.get("video", {}).get("url")
    if not video_url:
        print(f"\n  ERROR: No video URL in Pikaframes response")
        print(f"  Response: {json.dumps(result, indent=2)[:500]}")
        return None

    print(f" done")
    print(f"  Downloading MP4...", end="", flush=True)
    try:
        video_resp = requests.get(video_url, timeout=120)
        video_resp.raise_for_status()
        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_path.write_bytes(video_resp.content)
        size_kb = len(video_resp.content) / 1024
        print(f" done ({size_kb:.0f} KB)")
        return output_path
    except Exception as e:
        print(f"\n  ERROR downloading video: {e}")
        return None


# ============================================================================
# Step 3: Convert MP4 → looping GIF
# ============================================================================

def convert_mp4_to_gif(
    mp4_path: Path,
    gif_path: Path,
    *,
    fps: int = 10,
    max_width: int = 512,
    dry_run: bool = False,
) -> bool:
    """Convert MP4 to an optimized looping GIF using ffmpeg."""

    if dry_run:
        print(f"  [DRY RUN] Would convert {mp4_path.name} → {gif_path.name} ({fps}fps, {max_width}px)")
        return True

    gif_path.parent.mkdir(parents=True, exist_ok=True)

    # Two-pass ffmpeg for optimized GIF: generate palette, then use it
    palette_path = mp4_path.parent / f"{mp4_path.stem}_palette.png"

    print(f"  Converting MP4 → GIF ({fps}fps, {max_width}px)...", end="", flush=True)
    try:
        # Pass 1: Generate optimal color palette
        palette_cmd = [
            "ffmpeg", "-y", "-i", str(mp4_path),
            "-vf", f"fps={fps},scale={max_width}:-1:flags=lanczos,palettegen=stats_mode=diff",
            str(palette_path),
        ]
        subprocess.run(palette_cmd, capture_output=True, check=True, timeout=60)

        # Pass 2: Generate GIF using palette
        gif_cmd = [
            "ffmpeg", "-y", "-i", str(mp4_path), "-i", str(palette_path),
            "-lavfi", f"fps={fps},scale={max_width}:-1:flags=lanczos [x]; [x][1:v] paletteuse=dither=bayer:bayer_scale=5",
            "-loop", "0",  # Loop forever
            str(gif_path),
        ]
        subprocess.run(gif_cmd, capture_output=True, check=True, timeout=60)

        # Clean up palette
        palette_path.unlink(missing_ok=True)

        size_kb = gif_path.stat().st_size / 1024
        print(f" done ({size_kb:.0f} KB)")
        return True

    except FileNotFoundError:
        print(f"\n  ERROR: ffmpeg not found. Install with: brew install ffmpeg")
        return False
    except subprocess.CalledProcessError as e:
        print(f"\n  ERROR: ffmpeg failed: {e.stderr.decode()[:200]}")
        return False
    except subprocess.TimeoutExpired:
        print(f"\n  ERROR: ffmpeg timed out")
        return False
    finally:
        palette_path.unlink(missing_ok=True)


# ============================================================================
# Main pipeline
# ============================================================================

def process_exercise(
    exercise: dict,
    config: dict,
    *,
    bfl_api_key: str | None = None,
    fal_api_key: str | None = None,
    skip_end_frame: bool = False,
    skip_existing: bool = False,
    step: str | None = None,
    dry_run: bool = False,
) -> dict:
    """
    Run the full pipeline for a single exercise.

    Returns a status dict with keys: name, end_frame, video, gif, error
    """
    name = exercise["name"]
    filename = exercise.get("normalized_filename", "")

    result = {"name": name, "filename": filename, "start_frame": None, "end_frame": None, "video": None, "gif": None, "error": None}

    # Corrected start frames go into our output dir; fallback to original
    corrected_start_path = OUTPUT_DIR / "start-frames" / f"{filename}.png"
    original_start_path = START_FRAMES_DIR / f"{filename}.png"
    start_frame_path = corrected_start_path if corrected_start_path.exists() else original_start_path
    end_frame_path = END_FRAMES_DIR / f"{filename}_end.png"
    video_path = VIDEOS_DIR / f"{filename}.mp4"
    gif_path = GIFS_DIR / f"{filename}_anim.gif"

    # --- Step 0: Corrected start frame (if override exists) ---
    has_override = filename in START_POSITION_OVERRIDES
    run_start_frame = step in (None, "start-frame") and has_override

    if run_start_frame:
        if skip_existing and corrected_start_path.exists():
            print(f"  Corrected start frame exists, skipping")
            result["start_frame"] = str(corrected_start_path)
            start_frame_path = corrected_start_path
        elif not bfl_api_key and not dry_run:
            result["error"] = "No BFL API key provided for start-frame generation"
            print(f"  ERROR: {result['error']}")
            return result
        else:
            image_data = generate_start_frame(exercise, bfl_api_key or "", dry_run=dry_run)
            if image_data:
                corrected_start_path.parent.mkdir(parents=True, exist_ok=True)
                if save_image(image_data, corrected_start_path):
                    result["start_frame"] = str(corrected_start_path)
                    start_frame_path = corrected_start_path
                else:
                    result["error"] = "Failed to save corrected start frame"
                    return result
            elif not dry_run:
                result["error"] = "Failed to generate corrected start frame"
                return result

            if not dry_run:
                rate_limit = config.get("bfl_rate_limit_seconds", 8)
                print(f"  Waiting {rate_limit}s (BFL rate limit)...")
                time.sleep(rate_limit)

    if step == "start-frame":
        return result

    # Check start frame exists (original or corrected)
    if not start_frame_path.exists():
        msg = f"Start frame not found: {start_frame_path}"
        print(f"  SKIP: {msg}")
        result["error"] = msg
        return result

    # Check if final GIF already exists
    if skip_existing and gif_path.exists() and step is None:
        print(f"  SKIP: GIF already exists")
        result["gif"] = str(gif_path)
        return result

    # --- Step 1: End frame ---
    run_end_frame = step in (None, "end-frame")
    if run_end_frame and not skip_end_frame:
        if skip_existing and end_frame_path.exists():
            print(f"  End frame exists, skipping generation")
            result["end_frame"] = str(end_frame_path)
        elif not bfl_api_key and not dry_run:
            result["error"] = "No BFL API key provided for end-frame generation"
            print(f"  ERROR: {result['error']}")
            return result
        else:
            image_data = generate_end_frame(exercise, bfl_api_key or "", dry_run=dry_run)
            if image_data:
                if save_image(image_data, end_frame_path):
                    result["end_frame"] = str(end_frame_path)
                else:
                    result["error"] = "Failed to save end frame"
                    return result
            elif not dry_run:
                result["error"] = "Failed to generate end frame"
                return result

            # Rate limit between BFL calls
            if not dry_run:
                rate_limit = config.get("bfl_rate_limit_seconds", 8)
                print(f"  Waiting {rate_limit}s (BFL rate limit)...")
                time.sleep(rate_limit)
    elif skip_end_frame or (step and step != "end-frame"):
        if end_frame_path.exists():
            result["end_frame"] = str(end_frame_path)
        elif step != "end-frame":
            print(f"  WARNING: End frame not found at {end_frame_path}")

    if step == "end-frame":
        return result

    # --- Step 2: Pikaframes video ---
    run_video = step in (None, "video")
    if run_video:
        if not end_frame_path.exists() and not dry_run:
            result["error"] = f"End frame not found: {end_frame_path}"
            print(f"  ERROR: {result['error']}")
            return result

        if skip_existing and video_path.exists():
            print(f"  Video exists, skipping Pikaframes")
            result["video"] = str(video_path)
        elif not fal_api_key and not dry_run:
            result["error"] = "No fal.ai API key provided"
            print(f"  ERROR: {result['error']}")
            return result
        else:
            motion_prompt = MOTION_PROMPTS.get(filename, "")
            if not motion_prompt:
                result["error"] = f"No motion prompt for '{filename}'"
                print(f"  ERROR: {result['error']}")
                return result

            mp4 = submit_to_pikaframes(
                start_frame_path,
                end_frame_path,
                motion_prompt,
                fal_api_key or "",
                resolution=config.get("pikaframes_resolution", "720p"),
                dry_run=dry_run,
            )
            if mp4:
                result["video"] = str(mp4)
            elif not dry_run:
                result["error"] = "Failed to generate video"
                return result

    if step == "video":
        return result

    # --- Step 3: GIF conversion ---
    run_gif = step in (None, "gif")
    if run_gif:
        if not video_path.exists() and not dry_run:
            result["error"] = f"Video not found: {video_path}"
            print(f"  ERROR: {result['error']}")
            return result

        success = convert_mp4_to_gif(
            video_path,
            gif_path,
            fps=config.get("gif_fps", 10),
            max_width=config.get("gif_max_width", 512),
            dry_run=dry_run,
        )
        if success and not dry_run:
            result["gif"] = str(gif_path)
        elif not success and not dry_run:
            result["error"] = "Failed to convert MP4 to GIF"

    return result


def main():
    parser = argparse.ArgumentParser(
        description="Generate exercise animation GIFs using FLUX 2 Pro + Pika Pikaframes"
    )
    parser.add_argument("--bfl-api-key", help="BFL API key for FLUX 2 Pro end-frame generation")
    parser.add_argument("--fal-api-key", help="fal.ai API key for Pika Pikaframes")
    parser.add_argument(
        "--exercises", default="pilot",
        help='Comma-separated exercise names or "pilot" for the default 10 (default: pilot)',
    )
    parser.add_argument("--skip-end-frame", action="store_true", help="Skip end-frame generation, use existing")
    parser.add_argument("--skip-existing", action="store_true", help="Skip exercises with existing output")
    parser.add_argument(
        "--step", choices=["start-frame", "end-frame", "video", "gif"],
        help="Run only a specific pipeline step",
    )
    parser.add_argument("--dry-run", action="store_true", help="Print prompts without making API calls")
    args = parser.parse_args()

    config = load_config()
    exercises = load_exercise_list()

    # Build exercise name → metadata lookup
    exercise_map = {ex["normalized_filename"]: ex for ex in exercises}

    # Resolve which exercises to process
    if args.exercises == "pilot":
        target_names = config["pilot_exercises"]
    else:
        target_names = [n.strip() for n in args.exercises.split(",")]

    # Validate exercises exist
    targets = []
    for name in target_names:
        if name in exercise_map:
            targets.append(exercise_map[name])
        else:
            print(f"WARNING: Exercise '{name}' not found in exercise_list.json, skipping")

    if not targets:
        print("ERROR: No valid exercises to process")
        sys.exit(1)

    # Ensure output dirs exist
    for d in [END_FRAMES_DIR, VIDEOS_DIR, GIFS_DIR]:
        d.mkdir(parents=True, exist_ok=True)

    # Validate required API keys
    if not args.dry_run:
        if not args.skip_end_frame and args.step in (None, "end-frame") and not args.bfl_api_key:
            print("ERROR: --bfl-api-key required for end-frame generation (or use --skip-end-frame)")
            sys.exit(1)
        if args.step in (None, "video") and not args.fal_api_key:
            print("ERROR: --fal-api-key required for Pikaframes video generation")
            sys.exit(1)

    # Process exercises
    mode = "DRY RUN" if args.dry_run else "LIVE"
    step_label = f" (step: {args.step})" if args.step else ""
    print(f"\n{'='*60}")
    print(f"Exercise Animation Pilot — {mode}{step_label}")
    print(f"Processing {len(targets)} exercises")
    print(f"{'='*60}\n")

    results = []
    for i, exercise in enumerate(targets):
        name = exercise["name"]
        filename = exercise.get("normalized_filename", "")
        print(f"[{i+1}/{len(targets)}] {name} ({filename})")

        result = process_exercise(
            exercise,
            config,
            bfl_api_key=args.bfl_api_key,
            fal_api_key=args.fal_api_key,
            skip_end_frame=args.skip_end_frame,
            skip_existing=args.skip_existing,
            step=args.step,
            dry_run=args.dry_run,
        )
        results.append(result)
        print()

    # Summary
    print(f"{'='*60}")
    print("SUMMARY")
    print(f"{'='*60}")
    succeeded = [r for r in results if not r["error"]]
    failed = [r for r in results if r["error"]]

    for r in results:
        status = "OK" if not r["error"] else f"FAIL: {r['error']}"
        print(f"  {r['name']}: {status}")

    print(f"\nTotal: {len(succeeded)}/{len(results)} succeeded")
    if failed:
        print(f"Failed: {', '.join(r['name'] for r in failed)}")

    # Save results log
    log_path = OUTPUT_DIR / "generation-log.json"
    with open(log_path, "w") as f:
        json.dump(results, f, indent=2)
    print(f"\nResults saved to: {log_path}")


if __name__ == "__main__":
    main()
