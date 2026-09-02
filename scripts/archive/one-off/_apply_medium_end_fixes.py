"""
Strengthen end_pose_descriptions for the 7 corrected MEDIUM-tier exercises and
seed consistency_report.json with real failure observations so
regen_end_frames_with_corrections.py has a real signal.

Pattern mirrors _apply_end_frame_fixes.py from the HIGH tier.
"""
import json
from pathlib import Path

OUT = Path(__file__).resolve().parent / "output"
META = OUT / "all_exercises_metadata.json"
CONSIST = OUT / "consistency_report.json"

# (normalized_filename, new_end_pose_description, body_anchoring_obs, movement_logic_obs)
FIXES = [
    (
        "band-external-rotation",
        "Seated upright on a bench. The right elbow remains firmly TUCKED AGAINST the right ribs (upper arm vertical, elbow glued to the side). The right forearm has rotated OUTWARD against the band's resistance: forearm now points to the RIGHT side of the body (away from the centerline), still parallel to the ground, hand outside the line of the right hip. The band runs taut from the right hand back across the front of the body to the LEFT-side anchor. The left hand or anchor remains on the LEFT side of the body. CRITICAL: the elbow STAYS at the right side of the ribs throughout — the upper arm does not move; only the forearm rotates outward in an arc. CRITICAL: this is NOT a band pull-apart — both arms are not symmetrically out to the sides.",
        "FAILURE: end frame shows both arms extended outward symmetrically like a band pull-apart, OR the working elbow has lifted away from the ribs. The end position requires the right elbow STILL pinned to the right side of the body, with ONLY the right forearm rotated outward to the right side — the left hand or anchor stays on the LEFT side of the body.",
        "FAILURE: end frame must show pure shoulder external rotation — elbow stays glued to the right ribs, forearm has rotated outward to the right side, band pulled across the front of the body from a left-side anchor. Pull-apart-like symmetric arms is wrong."
    ),
    (
        "banded-copenhagen-adductor-exercise",
        "Held side-plank with the bottom (working) leg lifted. The body remains rotated onto the right side, supported on the right forearm with hips STACKED vertically (left hip directly above right hip). The TOP (left) leg's shin/ankle remains on the elevated bench at hip height. The BOTTOM (right) leg has LIFTED upward toward the top leg against the band's resistance — the right inner thigh visibly contracts and the right foot is now several inches above the floor, moving toward the left ankle. The band stretches around both legs above the knees. CRITICAL: this is still a SIDE plank (chest faces wall, hips stacked vertically), NOT a front plank.",
        "FAILURE: end frame shows a front plank (face-down) instead of a held side plank. The end position requires the same side-lying side-plank as the start, with the bottom (working) leg lifted upward toward the elevated top leg.",
        "FAILURE: end frame must show side-plank held with the BOTTOM leg lifted toward the top leg (adductor contraction). Front plank is wrong base position."
    ),
    (
        "banded-external-rotation-90-90",
        "Standing upright. The right shoulder remains ABDUCTED at 90 degrees (upper arm horizontal pointing out to the right at shoulder height). The right elbow remains BENT at 90 degrees. The forearm has ROTATED UPWARD against the band — forearm now points STRAIGHT UP toward the ceiling, hand above the elbow, making a vertical L-SHAPE with the upper arm. The band runs taut from the right hand to the side anchor at shoulder height. CRITICAL: the upper arm STAYS horizontal at shoulder height — only the forearm rotates upward. The elbow does NOT drop and the arm does NOT extend straight.",
        "FAILURE: end frame shows the arm fully extended (straight) or the elbow has dropped. The end position requires the upper arm still horizontal at shoulder height (90 degrees abduction) AND the elbow still bent at 90 degrees, with the forearm now rotated upward to point at the ceiling — a VERTICAL L-shape.",
        "FAILURE: end frame must preserve the 90/90 setup with the forearm rotated upward — upper arm horizontal at shoulder, elbow at 90, forearm pointing straight up. Straight arm or dropped elbow is wrong."
    ),
    (
        "banded-hip-internal-rotation",
        "Seated upright on the bench. The right knee remains stationary (still bent at 90 degrees, thigh forward). The right FOOT has rotated INWARD toward the left foot (the toes/forefoot have swung medially while the heel stays roughly in place), pulling against the visible band that loops around both feet. The left foot remains stationary as the anchor. The band is clearly visible and stretched between the two feet. CRITICAL: the rotation happens at the HIP — the entire shin and foot pivot inward as a unit; the knee does not buckle or move sideways. CRITICAL: the resistance band MUST be visible, looped around both feet.",
        "FAILURE: end frame is missing the visible resistance band, OR the rotation is happening at the knee/ankle rather than the hip, OR the foot has not actually moved. The end position requires the right foot rotated inward (toes swung toward the left foot) while the left foot stays planted — and the band must be clearly visible looped around both feet.",
        "FAILURE: end frame must show the right foot rotated inward (medial rotation of the hip) with the band visibly stretched between the two feet."
    ),
    (
        "doorway-pec-stretch-rotation",
        "Standing in a doorway with the right side of the chest near the doorframe. The right arm remains in the goal-post / L-shape: shoulder abducted to 90 degrees, elbow bent at 90 degrees, forearm vertical with palm and forearm pressed flat against the doorframe edge. The torso has now ROTATED to the LEFT (away from the raised right arm), pulling the right pec across the chest into a deeper stretch. The right foot is stepped forward through the doorway. CRITICAL: the elbow stays bent at 90 degrees — the L-shape arm geometry is preserved throughout the rotation. The doorframe is visible.",
        "FAILURE: end frame shows the arm fully extended (elbow straight) against a flat wall instead of the goal-post L-shape against a doorframe, OR the torso has not rotated to deepen the stretch. The end position requires the same elbow-bent goal-post arm against the doorframe AND a clear torso rotation away from the raised arm.",
        "FAILURE: end frame must show torso rotation away from the raised arm with the goal-post L-shape arm geometry preserved against the doorframe."
    ),
    (
        "foam-roller-quad",
        "Prone on a forearm plank. Both forearms remain flat on the floor with elbows bent 90 degrees under the shoulders. The foam roller has now rolled TOWARD THE HIPS — it is positioned at the TOP of the thighs, near the hip flexor crease (just below the pelvis). The body has shifted slightly forward to bring the roller to the hip-flexor end of the quads. The shins extend straight back behind the roller. CRITICAL: still on FOREARMS (not hands); the foam roller is at the upper thigh / hip flexor zone, NOT under the shins or knees.",
        "FAILURE: end frame shows a high plank with hands on the floor (instead of forearm plank), OR the foam roller is positioned at the shins/knees rather than the upper thighs / hip-flexor crease.",
        "FAILURE: end frame must show foam roller rolled up to the hip-flexor end of the quads while still on a forearm plank — moving from above the kneecap up toward the hip flexors."
    ),
    (
        "forearm-rotation-band",
        "Seated upright. The right elbow remains bent at 90 degrees with the upper arm tucked against the right ribs. The right forearm is still horizontal pointing forward, but the WRIST has now rotated so the palm faces UP (supinated) — the back of the hand is now down and the band has been twisted slightly by the supinating wrist motion. The band still runs vertically downward from the hand to its anchor. CRITICAL: the elbow STAYS pinned to the right side of the ribs — the only thing that has moved is the wrist/forearm rotating from palm-down to palm-up.",
        "FAILURE: end frame shows the arm extended forward or the elbow has lifted from the ribs. The end position requires the elbow still pinned to the side of the body, the forearm still horizontal forward — only the wrist has rotated from palm-down to palm-up.",
        "FAILURE: end frame must show the same tucked-elbow position with only the forearm rotated to palm-up (supinated). Straight extended arm is wrong."
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
        else:
            print(f"WARN: no consistency entry for {fname}")

    META.write_text(json.dumps(meta, indent=2))
    CONSIST.write_text(json.dumps(consist, indent=2))
    print(f"Updated metadata end_pose_description: {updated_meta} entries")
    print(f"Updated consistency_report: {updated_consist} entries")


if __name__ == "__main__":
    main()
