"""
Apply pose_description + QA seeding fixes for the 12 HIGH-risk variant exercises
that failed visual review. Each entry strengthens the start pose_description with
explicit anti-error wording and seeds a real failure observation in
qa_all_starts_report.json so regen_with_auto_prompts.py has a real failure
signal to correct from.
"""
import json
from pathlib import Path

OUT = Path(__file__).resolve().parent / "output"
META = OUT / "all_exercises_metadata.json"
QA = OUT / "qa_all_starts_report.json"

# (normalized_filename, new_pose_description, qa_failure_observation)
FIXES = [
    (
        "dead-bug",
        "Lying supine in tabletop position with hips and knees BOTH bent at 90 degrees and shins parallel to the floor (knees stacked over hips, feet in the air). The right arm remains extended STRAIGHT UP toward the ceiling. The LEFT arm is lowered overhead toward the floor BEHIND the head (not laterally to the side) — left bicep close to the left ear, fingertips reaching for the floor near the top of the head. The OPPOSITE (RIGHT) leg is extended straight out at hip level toward the floor, hovering just above the ground. The left knee remains bent and stays in tabletop. CRITICAL: this is OPPOSITE arm + leg lowering. Lowered arm is OVERHEAD-toward-floor, NOT lateral.",
        "FAILURE: the lowered arm is extended LATERALLY (out to the side at floor level) instead of OVERHEAD toward the floor behind the head. The dead-bug pattern requires the lowered arm to go past the ear toward the floor BEHIND the head, fingertips reaching back, like reaching for something on the floor above the top of the head. Also confirm OPPOSITE-side limbs are lowered (e.g., LEFT arm overhead + RIGHT leg out)."
    ),
    (
        "dead-bug-with-dumbbell",
        "Lying supine in TABLETOP position: hips and knees both bent at 90 degrees, shins parallel to the floor with both feet suspended in the air (NOT planted). Both arms extended STRAIGHT UP toward the ceiling, BOTH HANDS gripping ONE dumbbell together (one dumbbell, two hands holding it like a goblet). Lower back is neutral, pressed against the floor. CRITICAL: This is NOT a dumbbell floor press — feet must be in the air at 90/90 tabletop, not planted on the floor. CRITICAL: ONE dumbbell held by BOTH hands, not one hand.",
        "FAILURE: the image depicts a one-handed dumbbell floor press, NOT a dead-bug. Two problems: (1) feet are flat on the floor instead of suspended in tabletop position with hips/knees at 90/90, and (2) the dumbbell is held by ONE hand instead of BOTH hands. To fix: feet must be in the AIR with knees stacked over hips and shins parallel to the floor; both hands grip a single dumbbell together overhead."
    ),
    (
        "glute-bridge-single-leg",
        "Lying supine with hips still on the floor (NOT yet bridged). ONLY the left foot is flat on the floor with the left knee bent at about 90 degrees. The RIGHT leg is clearly lifted into the air: right foot is suspended 4-6 inches above the floor with the right knee bent at roughly 90 degrees. CRITICAL: only ONE foot is on the floor — both feet planted is wrong, this is NOT a regular two-leg glute bridge.",
        "FAILURE: both feet appear planted on the floor — this depicts a regular two-leg glute bridge setup, NOT a single-leg variant. The right foot must be visibly lifted 4-6 inches off the floor with the right knee still bent at about 90 degrees, while only the left foot remains on the floor."
    ),
    (
        "single-leg-balance-dumbbell-hold",
        "Standing on the LEFT leg only with a slight knee bend (left foot is the only foot on the floor). The RIGHT (non-standing) leg is lifted with the knee bent at about 90 degrees and the thigh raised to roughly hip height (high-knee position). The dumbbell is held in the RIGHT hand at the side of the body (the hand OPPOSITE the standing leg). The left arm is at the side of the body. CRITICAL: dumbbell is in the hand on the OPPOSITE side of the standing leg — if standing on the LEFT leg, the dumbbell is in the RIGHT hand. Same-side dumbbell + standing leg is wrong (cross-body stabilization is the point of this exercise).",
        "FAILURE: dumbbell is held in the SAME-side hand as the standing leg. The exercise requires the dumbbell in the OPPOSITE hand from the standing leg (cross-body stabilization). To fix: if standing on the left leg, the dumbbell goes in the RIGHT hand; if standing on the right leg, the dumbbell goes in the LEFT hand."
    ),
    (
        "single-leg-balance-foam",
        "Standing on a blue foam balance pad on ONE leg only — the LEFT foot is the only foot on the foam pad with the left knee slightly bent. The RIGHT (non-standing) foot is lifted off the foam pad and suspended in the air with the right knee bent. Arms are at the sides of the body or extended outward for balance. CRITICAL: only the left foot is on the pad; the right foot is clearly off the pad and in the air. Both feet on the pad is wrong.",
        "FAILURE: both feet are planted on the foam pad. The exercise is single-leg balance on foam — only ONE foot should be on the pad, with the other leg lifted off the pad and suspended in the air, knee bent."
    ),
    (
        "single-leg-balance-hold",
        "Standing on the LEFT leg only with a slight bend in the standing knee. The RIGHT (non-standing) foot is clearly lifted off the floor with the right knee bent at about 90 degrees. Arms are at the sides of the body or extended outward for balance. CRITICAL: only the LEFT foot is on the floor; the right foot is suspended in the air. This is a held single-leg position — both feet planted is wrong.",
        "FAILURE: both feet appear planted on the floor. The exercise is a single-leg balance HOLD — only ONE foot should be on the floor with the other leg lifted in the air, knee bent. The image must clearly convey the single-leg variant in the start frame."
    ),
    (
        "single-leg-stance",
        "Standing on the LEFT leg only with a slight bend in the standing knee. The RIGHT foot is clearly lifted off the floor — right knee bent at about 90 degrees with the thigh raised to roughly hip height. Arms are at the sides or extended for balance. CRITICAL: this is the single-leg STANCE — only ONE foot on the floor, the other clearly suspended in the air. Both feet planted is wrong.",
        "FAILURE: both feet are planted on the floor. The exercise is single-leg stance — exactly ONE foot must be on the floor with the other leg clearly lifted into the air."
    ),
    (
        "single-leg-stance-support",
        "Standing on the LEFT leg only beside a sturdy gym railing/wall, with the right hand fingertips lightly touching the rail/wall for light support. The RIGHT foot is clearly lifted off the floor with the right knee bent at about 90 degrees. The standing left knee has a slight bend. CRITICAL: only ONE foot on the floor; the other foot is suspended in the air. Both feet planted is wrong.",
        "FAILURE: both feet are planted on the floor. The exercise is single-leg stance with upper body support — only the standing foot should be on the floor, with the other leg lifted in the air, knee bent. The hand contacts the rail for light balance support."
    ),
    (
        "standing-balance-on-one-leg",
        "Standing on the LEFT leg only beside a wall/counter with the right hand resting lightly on the wall/counter for light support. The RIGHT (non-standing) foot is clearly lifted off the floor with the right knee bent at about 90 degrees. The standing left knee is slightly bent. CRITICAL: only ONE foot is on the floor; the other foot is suspended in the air.",
        "FAILURE: both feet are planted on the floor. The exercise is standing balance on ONE leg — only the standing foot should be on the floor with the other leg lifted, knee bent. The hand rests on a wall for light support."
    ),
    (
        "standing-single-leg-balance",
        "Standing on the LEFT leg only beside a wall or sturdy chair, with the right hand resting on the wall/chair for support. The RIGHT (non-standing) foot is clearly lifted off the floor with the right knee bent at about 90 degrees. The standing left knee has a slight bend. CRITICAL: only ONE foot is on the floor; the other foot is suspended in the air.",
        "FAILURE: both feet are on the floor and no support is being used. The exercise is standing single-leg balance — only ONE foot should be on the floor with the other leg lifted in the air. A hand should rest lightly on a wall or chair for support."
    ),
    (
        "standing-single-leg-stance",
        "Standing on the LEFT leg only near a wall or sturdy chair (within reach but not necessarily touching). The RIGHT (non-standing) foot is clearly lifted off the floor with the right knee bent at about 90 degrees. Arms are at the sides ready to grasp support if needed. CRITICAL: only ONE foot is on the floor; the other foot is suspended in the air.",
        "FAILURE: both feet are on the floor. The exercise is single-leg stance — only the standing foot should be on the floor, with the other leg clearly lifted in the air, knee bent."
    ),
    (
        "standing-single-leg-stance-band",
        "Standing on the LEFT leg only facing a wall, with a resistance band looped around a wall post at waist height held in both hands at the waist for light support. The RIGHT (non-standing) foot is clearly lifted off the floor with the right knee bent at about 90 degrees. The standing left knee has a slight bend. CRITICAL: only ONE foot is on the floor; the other foot is suspended in the air. The band provides light tactile feedback for balance.",
        "FAILURE: both feet are planted on the floor. The exercise is single-leg stance with band support — only the standing foot should be on the floor, with the other leg lifted in the air, knee bent. The band loops around a wall post and is held at the waist for light feedback."
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
        # Update metadata pose_description
        by_name[fname]["pose_description"] = new_desc
        updated_meta += 1
        # Update QA report — flag pose_accuracy as failed with detailed observation
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
