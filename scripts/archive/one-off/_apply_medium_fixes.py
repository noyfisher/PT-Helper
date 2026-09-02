"""
Apply pose_description + QA seeding fixes for the MEDIUM-risk variant exercises
that failed visual review (batches 1-5 of MEDIUM tier, 7 failures).

Pattern mirrors _apply_variant_fixes.py: strengthen pose_description with explicit
anti-error wording, then seed a real failure observation in qa_all_starts_report.json
so regen_with_auto_prompts.py has a real failure signal to correct from.
"""
import json
from pathlib import Path

OUT = Path(__file__).resolve().parent / "output"
META = OUT / "all_exercises_metadata.json"
QA = OUT / "qa_all_starts_report.json"

# (normalized_filename, new_pose_description, qa_failure_observation)
FIXES = [
    (
        "band-external-rotation",
        "Sit upright on a bench with the right elbow firmly TUCKED AGAINST the right side of the ribs (upper arm vertical, hugging the torso). The right forearm is bent at 90 degrees and points STRAIGHT FORWARD across the front of the body, hand near the centerline of the torso (in front of the belly button). The right hand grips one end of a resistance band; the OTHER end is anchored to the side (held by the LEFT hand at hip level, or to a fixed anchor on the LEFT side of the body). The band runs HORIZONTALLY across the front of the body. CRITICAL: the right elbow stays GLUED to the right ribs — do not let the upper arm float forward or out to the side. CRITICAL: the band runs sideways across the body (anchored on the opposite side), the forearm is the only thing that rotates. This is NOT a band pull-apart and NOT a forward press — both arms are NOT extended forward.",
        "FAILURE: image shows both arms extended forward holding the band like a pull-apart or forward press. The exercise is shoulder external rotation: the working elbow MUST be tucked tightly against the working side of the ribs, upper arm vertical against the torso, ONLY the forearm rotating. The band must run horizontally across the front of the body anchored on the opposite side. Both arms straight forward is fundamentally wrong — that's a different exercise (pull-apart)."
    ),
    (
        "banded-copenhagen-adductor-exercise",
        "Side-lying SIDE-PLANK position (NOT a front plank). The body is on its right side, supported on the right forearm with right elbow under the right shoulder; hips are STACKED vertically (left hip directly above right hip) and the body forms a straight line from head to feet rotated onto its side. The TOP (left) leg is fully extended with the left shin or ankle resting on a low elevated surface (a bench or box) at about hip height. The BOTTOM (right) leg is extended straight beneath the top leg, hovering above the floor (or just touching). A resistance band is looped around both legs just above the knees. CRITICAL: this is a SIDE plank — chest faces the wall (not the floor), hips stacked vertically — NOT a front plank where the chest faces the floor. CRITICAL: only ONE forearm supports the upper body (the bottom-side forearm), not both forearms.",
        "FAILURE: image shows a regular front plank (face-down, chest facing the floor, supported on a forearm or both forearms with the body horizontal). The Copenhagen adductor exercise is fundamentally a SIDE plank — body rotated onto one side, hips stacked vertically, chest facing the wall, supported on ONE forearm. The TOP leg's shin/ankle rests on a bench at about hip height; the bottom leg is the working leg. Front plank is the wrong base position."
    ),
    (
        "banded-external-rotation-90-90",
        "Standing upright. The right shoulder is ABDUCTED to 90 degrees so the upper arm is horizontal pointing OUT to the right side at shoulder height (like the start of a goal-post / cactus arms). The right elbow is BENT at 90 degrees so the forearm makes a clear L-SHAPE with the upper arm — forearm initially points STRAIGHT DOWN toward the floor, hand below the elbow. The right hand grips one end of a resistance band that is anchored at SHOULDER height on the right side of the body (band runs horizontally to a fixed anchor at shoulder level). The left arm hangs at the side. CRITICAL: the elbow is BENT at 90 — the arm makes an L-SHAPE, NOT a straight line out to the side. The upper arm is horizontal at shoulder height; the forearm hangs perpendicular below it. A fully extended (straight) right arm out to the side is wrong — that loses the 90/90 setup.",
        "FAILURE: image shows the right arm fully EXTENDED (straight) out to the side at shoulder height with NO elbow bend. The 90/90 external rotation setup requires both shoulder abduction at 90 degrees AND elbow flexion at 90 degrees — the arm must form a clear L-SHAPE with the upper arm horizontal and the forearm hanging perpendicular below it. Without the elbow bend, this is just shoulder abduction, not the 90/90 ER setup."
    ),
    (
        "banded-hip-internal-rotation",
        "Sit upright on a bench with the torso vertical and core engaged. Both knees are bent at 90 degrees and BOTH FEET are flat on the floor about hip-width apart (knees and feet aligned). A resistance band is VISIBLY LOOPED around both feet at the level of the arches/instep — the band can be clearly seen running between the two feet, providing a visible horizontal loop or figure-eight. The arms rest on the thighs or at the sides. CRITICAL: the resistance band MUST be visible in the image, looped around both feet. No band rendered = missing the central piece of equipment.",
        "FAILURE: image shows the seated bench position correctly but the resistance band is COMPLETELY MISSING from the image — there is no visible band looped around the feet. The band is the central piece of equipment for this exercise; without a visible band looped around both feet, the image fails to depict the exercise."
    ),
    (
        "doorway-pec-stretch-rotation",
        "Standing in a doorway with the body angled so the right side of the chest is closer to the doorframe. The RIGHT arm is raised to 90 degrees of shoulder abduction (upper arm horizontal at shoulder height) AND the right elbow is BENT at 90 degrees so the forearm points STRAIGHT UP toward the ceiling (or alternatively palm forward), making a clear GOAL-POST / L-SHAPE. The forearm and palm rest flat against the doorframe (the vertical edge of the door). One foot (the right) is stepped slightly forward through the doorway to gently begin the stretch. CRITICAL: the elbow MUST be bent at 90 degrees — the forearm is VERTICAL up against the doorframe, NOT a straight extended arm pressing against a flat wall. CRITICAL: there is a visible doorway/doorframe (vertical edge), NOT an open flat wall.",
        "FAILURE: image shows the arm fully EXTENDED (elbow straight) with the hand pressed flat against an open wall — no doorframe is visible and the elbow is not bent. The doorway pec stretch requires elbow flexion at 90 degrees (forearm vertical up against the doorframe edge, like a goal-post arm) AND a clear doorway/doorframe in the scene. Straight-arm against a flat wall depicts a different stretch (e.g., chest opener) — wrong elbow geometry and wrong scene."
    ),
    (
        "foam-roller-quad",
        "Lying FACE-DOWN (prone) in a modified FOREARM plank. Both forearms are flat on the floor with the elbows bent at about 90 degrees directly under the shoulders, hands forward (NOT a high plank with straight arms). A foam roller is positioned horizontally UNDER THE FRONT OF BOTH THIGHS — the roller sits between the floor and the mid-thighs (the quadriceps), well above the knees and well below the hips. The lower legs (shins) extend straight back behind the roller with toes touching the floor or slightly elevated. The body is nearly horizontal. CRITICAL: forearms (not hands) support the upper body — elbows bent 90, forearms flat on floor. CRITICAL: the foam roller is under the FRONT OF THE THIGHS (mid-thigh area, on the quadriceps), NOT under the shins, NOT under the knees, and NOT under the hips/pelvis.",
        "FAILURE: image shows a HIGH plank (straight arms with hands on the floor) instead of a forearm plank, AND the foam roller appears to be positioned under the lower legs (shins) rather than under the front of the thighs (quadriceps). To fix: forearms flat on floor with elbows bent 90 directly under shoulders; foam roller centered under the mid-thighs (quads) so the body weight presses the front of the thighs into the roller. Hand-supported plank with roller at shins is wrong on both counts."
    ),
    (
        "forearm-rotation-band",
        "Seated upright. The working (right) elbow is BENT at 90 degrees and the upper arm is firmly tucked against the right ribs (elbow glued to the side of the body). The right forearm is HORIZONTAL pointing STRAIGHT FORWARD, parallel to the ground, palm initially facing DOWN (pronated). The right hand grips one end of a resistance band; the band hangs vertically downward from the hand toward an anchor on the floor (or under the foot). The left arm rests on the lap. CRITICAL: the elbow stays bent at 90 degrees throughout — the forearm is the ONLY thing that rotates (rotating the wrist between palm-down and palm-up). The upper arm does NOT extend forward, the elbow does NOT leave the side of the body. A fully extended/straight arm reaching forward is wrong — that's a different exercise.",
        "FAILURE: image shows both arms fully EXTENDED forward at chest level with elbows straight (and hands held wider than shoulder-width). The forearm pronation/supination exercise requires the working elbow bent at 90 degrees and TUCKED against the side of the body, with the forearm horizontal pointing forward. Only the forearm/wrist rotates between palm-down and palm-up; the elbow stays glued to the ribs and the upper arm does not move. Straight-arm-forward is wrong elbow geometry."
    ),
]


def main():
    meta = json.loads(META.read_text())
    by_name = {e["normalized_filename"]: e for e in meta["exercises"]}
    qa = json.loads(QA.read_text())

    updated_meta = 0
    updated_qa = 0
    missing = []
    for fname, new_desc, fail_obs in FIXES:
        if fname not in by_name:
            missing.append(fname)
            continue
        by_name[fname]["pose_description"] = new_desc
        updated_meta += 1
        if fname in qa.get("results", {}):
            entry = qa["results"][fname]
            if "pose_accuracy" not in entry:
                entry["pose_accuracy"] = {}
            entry["pose_accuracy"]["observation"] = fail_obs
            entry["pose_accuracy"]["passed"] = False
            entry["pose_score"] = 0
            entry["overall_pass"] = False
            entry["critical_failures"] = ["pose_accuracy"]
            updated_qa += 1
        else:
            print(f"WARN: no QA entry for {fname}, skipping QA seed")

    META.write_text(json.dumps(meta, indent=2))
    QA.write_text(json.dumps(qa, indent=2))
    print(f"Updated metadata: {updated_meta} entries")
    print(f"Updated QA report: {updated_qa} entries")
    if missing:
        print(f"MISSING from metadata: {missing}")


if __name__ == "__main__":
    main()
