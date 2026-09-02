"""
End-frame fixes for fix run #2.
"""
import json
from pathlib import Path

OUT = Path(__file__).resolve().parent / "output"
META = OUT / "all_exercises_metadata.json"
CONSIST = OUT / "consistency_report.json"

FIXES = [
    (
        "internal-rotation",
        "Standing upright facing the camera. The right elbow remains FIRMLY TUCKED at the right side of the ribs (upper arm vertical). The right forearm has rotated INWARD across the front of the body — forearm now horizontal pointing across to the LEFT side of the body, hand near or just past the centerline of the torso (in front of the belly button). The band runs taut from the right hand to its anchor on the right (the band has been pulled across the body during the rotation). The left arm hangs at the side. CRITICAL: the elbow STAYS at the right ribs throughout — the upper arm does not move; only the forearm rotates inward. CRITICAL: this is a UNILATERAL rotation; the left arm hangs at the side and is NOT engaged.",
        "FAILURE: end frame shows both arms engaged or the elbow has lifted from the ribs. The end position requires the right elbow STILL pinned to the right side, with the forearm rotated inward across the body so the hand is near or just past the centerline. Left arm hangs at the side.",
        "FAILURE: end frame must show shoulder internal rotation completed — elbow pinned at side, forearm rotated inward across the body, band stretched from the side anchor across the front."
    ),
    (
        "isometric-shoulder-external-rotation",
        "Standing next to the wall in the same setup as the start. The right elbow remains BENT at 90 degrees and PINNED at the SIDE of the right ribs (waist height), with the right forearm horizontal pointing forward. The back of the right wrist is pressed firmly outward into the wall in sustained isometric contraction — visible muscle tension in the shoulder/rotator cuff. No visible body motion; this is a held isometric. The left arm hangs at the side. CRITICAL: the position is IDENTICAL to the start (this is an isometric hold) — elbow stays at the side at waist height, forearm horizontal forward, BACK of wrist on wall. NOT a raised arm against the wall.",
        "FAILURE: end frame shows the arm raised up high with the palm pressing the wall at head/shoulder height. The end position requires the same elbow-tucked-at-side waist-height isometric ER as the start (this is a held isometric).",
        "FAILURE: end frame must show held isometric ER — elbow pinned at side at waist height, forearm horizontal forward, BACK of wrist pressing into the wall. Position is identical to the start."
    ),
    (
        "lateral-side-lying-clam-shell",
        "Lying on the LEFT side. Hips remain BENT at approximately 45 degrees and the BOTTOM (left) knee remains BENT at 90 degrees. The TOP (right) knee has OPENED upward like a clamshell — the top knee is now lifted to a wide angle (approximately 70-90 degrees from the bottom knee) while the FEET REMAIN TOGETHER touching each other. The pelvis stays stacked vertically without rotating backward. The bottom arm supports the head; the top hand rests on the hip. CRITICAL: both knees STAY BENT at 90 degrees throughout — the legs are NOT extended. Extended legs depict a different exercise. CRITICAL: feet stay TOGETHER (touching) even as the top knee opens upward.",
        "FAILURE: end frame shows the legs extended (straight) instead of bent at 90 degrees, OR the feet have separated, OR the pelvis has rotated backward. The end position requires both knees still bent at 90, hips still at 45, feet still together touching, and only the TOP knee has opened upward like a clamshell.",
        "FAILURE: end frame must show clamshell opening — top knee lifted upward while both knees stay bent at 90 and feet stay together touching. Extended legs is wrong (different exercise)."
    ),
]


def main():
    meta = json.loads(META.read_text())
    by_name = {e["normalized_filename"]: e for e in meta["exercises"]}
    consist = json.loads(CONSIST.read_text())
    results = consist.get("results", {})

    updated_meta = 0
    updated_consist = 0
    for fname, new_end_desc, body_obs, move_obs in FIXES:
        if fname in by_name:
            by_name[fname]["end_pose_description"] = new_end_desc
            updated_meta += 1
        if fname in results:
            row = results[fname]
            row.setdefault("body_anchoring", {})
            row["body_anchoring"]["observation"] = body_obs
            row["body_anchoring"]["score"] = 0
            row["body_anchoring"]["passed"] = False
            row.setdefault("movement_logic", {})
            row["movement_logic"]["observation"] = move_obs
            row["movement_logic"]["score"] = 0
            row["movement_logic"]["passed"] = False
            row["overall_consistency_score"] = 0.0
            row["overall_pass"] = False
            row["critical_failures"] = ["body_anchoring", "movement_logic"]
            updated_consist += 1

    META.write_text(json.dumps(meta, indent=2))
    CONSIST.write_text(json.dumps(consist, indent=2))
    print(f"Updated metadata: {updated_meta}")
    print(f"Updated consistency: {updated_consist}")


if __name__ == "__main__":
    main()
