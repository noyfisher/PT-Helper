"""
Generate inpainting masks for pilot exercises using MediaPipe Pose.

For each exercise, detects body landmarks on the start image and draws a
white mask around the body parts that move (per a per-exercise spec).
Also writes an overlay preview (start image with mask shown in red) so
the mask can be visually inspected before running inpainting.

Outputs per exercise in scripts/output/:
  {name}_mask.png          -- the mask itself (white = regenerate)
  {name}_mask_preview.png  -- start image with mask in red for visual check

Usage:
  python scripts/generate_masks.py                        # all 10 pilot
  python scripts/generate_masks.py --only chin-tucks,quad-sets
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

import cv2
import mediapipe as mp
import numpy as np

SCRIPT_DIR = Path(__file__).resolve().parent
OUTPUT_DIR = SCRIPT_DIR / "output"

# MediaPipe Pose landmark indices we care about
NOSE, L_EAR, R_EAR = 0, 7, 8
L_SHOULDER, R_SHOULDER = 11, 12
L_ELBOW, R_ELBOW = 13, 14
L_WRIST, R_WRIST = 15, 16
L_HIP, R_HIP = 23, 24
L_KNEE, R_KNEE = 25, 26
L_ANKLE, R_ANKLE = 27, 28
L_FOOT, R_FOOT = 31, 32


# For each exercise: list of (landmark_indices, thickness_px, extra_radius_px)
# The mask is drawn as thick lines connecting consecutive landmarks plus
# filled circles at each landmark.
#
# "side" indicates which side is working when ambiguous. 'both' covers both.
# MediaPipe's L_/R_ are from the subject's POV (their left shoulder = L_SHOULDER).
MASK_SPECS: dict[str, dict] = {
    # SUPINE -----------------------------------------------------------------
    "quad-sets": {
        # Working quadricep -- one thigh region. Cover both; user can refine.
        "segments": [
            [(L_HIP, L_KNEE)],
            [(R_HIP, R_KNEE)],
        ],
        "thickness": 140,
        "extra_radius": 60,
    },
    "straight-leg-raises": {
        # Lifting leg -- full length one side. Cover both; lifted leg will dominate.
        "segments": [
            [(L_HIP, L_KNEE), (L_KNEE, L_ANKLE), (L_ANKLE, L_FOOT)],
            [(R_HIP, R_KNEE), (R_KNEE, R_ANKLE), (R_ANKLE, R_FOOT)],
        ],
        "thickness": 110,
        "extra_radius": 60,
    },
    "heel-slides": {
        # Sliding leg -- whole leg, both sides to be safe
        "segments": [
            [(L_HIP, L_KNEE), (L_KNEE, L_ANKLE), (L_ANKLE, L_FOOT)],
            [(R_HIP, R_KNEE), (R_KNEE, R_ANKLE), (R_ANKLE, R_FOOT)],
        ],
        "thickness": 110,
        "extra_radius": 60,
    },
    # SIDE-LYING -------------------------------------------------------------
    "clamshells": {
        # Top leg -- thigh is what lifts. Cover both legs (top leg opens up)
        "segments": [
            [(L_HIP, L_KNEE), (L_KNEE, L_ANKLE)],
            [(R_HIP, R_KNEE), (R_KNEE, R_ANKLE)],
        ],
        "thickness": 120,
        "extra_radius": 60,
    },
    "side-lying-hip-abduction": {
        # Top leg -- full leg lifts
        "segments": [
            [(L_HIP, L_KNEE), (L_KNEE, L_ANKLE), (L_ANKLE, L_FOOT)],
            [(R_HIP, R_KNEE), (R_KNEE, R_ANKLE), (R_ANKLE, R_FOOT)],
        ],
        "thickness": 120,
        "extra_radius": 60,
    },
    # STANDING ---------------------------------------------------------------
    "standing-hip-abduction": {
        # One leg lifts sideways. Cover both full legs.
        "segments": [
            [(L_HIP, L_KNEE), (L_KNEE, L_ANKLE), (L_ANKLE, L_FOOT)],
            [(R_HIP, R_KNEE), (R_KNEE, R_ANKLE), (R_ANKLE, R_FOOT)],
        ],
        "thickness": 110,
        "extra_radius": 60,
    },
    "chin-tucks": {
        # Head + neck only -- very subtle retraction
        "segments": [
            [(NOSE, L_SHOULDER), (NOSE, R_SHOULDER)],
        ],
        "thickness": 140,
        "extra_radius": 80,
    },
    # PRONE ------------------------------------------------------------------
    "prone-knee-flexion": {
        # Lower leg bends up -- knee to foot, one side or both
        "segments": [
            [(L_KNEE, L_ANKLE), (L_ANKLE, L_FOOT)],
            [(R_KNEE, R_ANKLE), (R_ANKLE, R_FOOT)],
        ],
        "thickness": 130,
        "extra_radius": 80,
    },
    # SEATED -----------------------------------------------------------------
    "seated-knee-extension": {
        # Lower leg extends -- knee to foot
        "segments": [
            [(L_KNEE, L_ANKLE), (L_ANKLE, L_FOOT)],
            [(R_KNEE, R_ANKLE), (R_ANKLE, R_FOOT)],
        ],
        "thickness": 120,
        "extra_radius": 80,
    },
    # WRIST ------------------------------------------------------------------
    "wrist-curls": {
        # Forearm + hand
        "segments": [
            [(L_ELBOW, L_WRIST)],
            [(R_ELBOW, R_WRIST)],
        ],
        "thickness": 110,
        "extra_radius": 80,
    },
}


def detect_landmarks(image_bgr: np.ndarray) -> dict[int, tuple[int, int]] | None:
    """Run MediaPipe Pose, return {landmark_idx: (x_px, y_px)} or None."""
    h, w = image_bgr.shape[:2]
    mp_pose = mp.solutions.pose
    with mp_pose.Pose(
        static_image_mode=True,
        model_complexity=2,
        enable_segmentation=False,
        min_detection_confidence=0.3,
    ) as pose:
        rgb = cv2.cvtColor(image_bgr, cv2.COLOR_BGR2RGB)
        result = pose.process(rgb)
        if not result.pose_landmarks:
            return None
        lm = {}
        for i, p in enumerate(result.pose_landmarks.landmark):
            lm[i] = (int(p.x * w), int(p.y * h))
        return lm


def build_mask(
    image_shape: tuple[int, int],
    landmarks: dict[int, tuple[int, int]],
    spec: dict,
) -> np.ndarray:
    """Return a single-channel uint8 mask (0 or 255), with Gaussian-blurred edges."""
    h, w = image_shape
    mask = np.zeros((h, w), dtype=np.uint8)
    thickness = spec["thickness"]
    extra = spec["extra_radius"]

    for chain in spec["segments"]:
        for (a, b) in chain:
            if a not in landmarks or b not in landmarks:
                continue
            pa = landmarks[a]
            pb = landmarks[b]
            cv2.line(mask, pa, pb, 255, thickness=thickness, lineType=cv2.LINE_AA)
            cv2.circle(mask, pa, thickness // 2 + extra, 255, -1, cv2.LINE_AA)
            cv2.circle(mask, pb, thickness // 2 + extra, 255, -1, cv2.LINE_AA)

    # Feather edges with a blur, then threshold back to binary-ish (for FLUX)
    mask_blurred = cv2.GaussianBlur(mask, (41, 41), 0)
    # Keep grayscale; FLUX Fill handles soft masks
    return mask_blurred


def build_preview(start_bgr: np.ndarray, mask: np.ndarray) -> np.ndarray:
    """Overlay mask in red onto the start image for visual inspection."""
    overlay = start_bgr.copy()
    red = np.zeros_like(overlay)
    red[:, :, 2] = 255  # BGR -> red channel
    alpha = (mask.astype(np.float32) / 255.0)[..., None] * 0.55
    blended = overlay.astype(np.float32) * (1 - alpha) + red.astype(np.float32) * alpha
    return np.clip(blended, 0, 255).astype(np.uint8)


def process_one(name: str) -> tuple[str, str]:
    """Returns (name, status)."""
    start_path = OUTPUT_DIR / f"{name}.png"
    mask_path = OUTPUT_DIR / f"{name}_mask.png"
    preview_path = OUTPUT_DIR / f"{name}_mask_preview.png"

    if not start_path.exists():
        return name, f"missing start image {start_path.name}"
    spec = MASK_SPECS.get(name)
    if spec is None:
        return name, "no mask spec defined"

    image = cv2.imread(str(start_path))
    if image is None:
        return name, "cv2 failed to read start image"

    landmarks = detect_landmarks(image)
    if not landmarks:
        return name, "no pose landmarks detected"

    mask = build_mask(image.shape[:2], landmarks, spec)
    preview = build_preview(image, mask)

    cv2.imwrite(str(mask_path), mask)
    cv2.imwrite(str(preview_path), preview)
    return name, f"OK -> {mask_path.name}, {preview_path.name}"


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--only", help="Comma-separated subset")
    args = ap.parse_args()

    names = list(MASK_SPECS.keys())
    if args.only:
        names = [n.strip() for n in args.only.split(",") if n.strip()]

    for name in names:
        name, status = process_one(name)
        print(f"  {name}: {status}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
