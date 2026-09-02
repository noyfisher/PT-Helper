"""
Strengthen end_pose_descriptions for the 12 corrected variant exercises and
seed consistency_report.json with real failure observations so
regen_end_frames_with_corrections.py has a real signal.

The fix template emphasizes that the end frame must preserve the same single-leg
laterality as the (now-correct) start frame, since otherwise the AI tends to
revert to a two-feet form when the END description doesn't explicitly call out
the single-leg cue.
"""
import json
from pathlib import Path

OUT = Path(__file__).resolve().parent / "output"
META = OUT / "all_exercises_metadata.json"
CONSIST = OUT / "consistency_report.json"

# (normalized_filename, new_end_pose_description, body_anchoring_obs, movement_logic_obs)
FIXES = [
    (
        "dead-bug",
        "Lying supine. The right arm has lowered overhead toward the floor BEHIND the head — left arm reaches past the ear, fingertips hovering just above the floor near the top of the head (NOT lateral to the side). The OPPOSITE (right) leg has extended straight out at near floor level, heel hovering just above the ground. The right arm remains extended straight up at the ceiling. The left knee remains bent in tabletop. CRITICAL: this is OPPOSITE arm + leg lowered. Lowered arm goes OVERHEAD-toward-floor BEHIND the head, NOT to the side.",
        "FAILURE: in the end frame the lowered arm extends LATERALLY to the side at floor level instead of OVERHEAD-toward-the-floor BEHIND the head. The dead-bug pattern requires the lowered arm to reach past the ear toward the floor near the top of the head.",
        "FAILURE: end frame must preserve dead-bug pattern with OPPOSITE arm and leg lowered toward the floor — opposite arm reaching overhead behind the head, opposite leg extended out toward the floor."
    ),
    (
        "dead-bug-with-dumbbell",
        "Lying supine in tabletop with hips/knees at 90/90 (feet still in the air, NOT planted). Both arms remain extended STRAIGHT UP toward the ceiling with BOTH HANDS gripping the SAME SINGLE dumbbell. ONE leg has extended straight out at near floor level — the heel hovers just above the floor without touching. The other leg remains in tabletop with knee bent at 90 degrees. CRITICAL: feet are NOT both planted on the floor; one leg is lowered toward the floor while the other stays in tabletop. ONE dumbbell, BOTH hands.",
        "FAILURE: in the end frame both feet are planted on the floor. The end position requires one leg lowered toward the floor (heel hovering above ground) while the other leg remains in tabletop with knee bent at 90 degrees. The dumbbell must stay overhead, gripped by BOTH hands.",
        "FAILURE: end frame must show one leg lowered toward the floor while the other stays in tabletop, with both arms still extended overhead holding ONE dumbbell. Both feet planted is wrong."
    ),
    (
        "glute-bridge-single-leg",
        "Hips bridged HIGH off the floor, supported by the LEFT foot only. Torso, hips, and left thigh form a straight diagonal line from shoulders to left knee. The RIGHT leg remains suspended in the air with the knee bent at roughly 90 degrees — the right foot is clearly NOT touching the floor. CRITICAL: only ONE foot is on the floor; the right foot is in the air. Both feet planted is wrong.",
        "FAILURE: in the end frame both feet are planted on the floor. The end position requires only the LEFT foot on the floor with hips bridged HIGH; the RIGHT leg must stay suspended in the air with the knee bent.",
        "FAILURE: end frame must show single-leg bridge — only the standing foot on the floor, hips bridged high, the other leg remaining lifted in the air with the knee bent."
    ),
    (
        "single-leg-balance-dumbbell-hold",
        "Held single-leg balance position. Standing on the LEFT leg only with a slight knee bend. The RIGHT (non-standing) leg is lifted with the knee bent at approximately 90 degrees, thigh raised toward hip height. The dumbbell remains in the RIGHT hand at the side of the body (the hand OPPOSITE the standing leg). The left arm hangs naturally at the side of the body. CRITICAL: this is a HELD position — torso stays UPRIGHT, no forward hinge. Only ONE foot on the floor.",
        "FAILURE: in the end frame the torso has hinged forward (single-leg deadlift form) instead of remaining upright. This is a single-leg balance HOLD — torso stays upright, only the lifted knee changes height (still bent at 90 degrees, not extended back).",
        "FAILURE: end frame must show held single-leg balance with upright torso (NOT a single-leg deadlift hinge). Standing on one leg with the other knee lifted to about hip height; dumbbell stays at side in the opposite hand from standing leg."
    ),
    (
        "single-leg-balance-foam",
        "Standing on a blue foam balance pad on ONE foot only. The LEFT foot is the only foot on the foam pad, knee slightly bent. The RIGHT (non-standing) leg is lifted with knee bent at about 90 degrees, foot suspended in the air clearly off the foam pad. Arms are extended outward for balance. CRITICAL: only ONE foot is on the foam pad; the other is in the air.",
        "FAILURE: in the end frame both feet are on the foam pad. The end position requires only ONE foot on the pad with the other leg lifted in the air, knee bent.",
        "FAILURE: end frame must show single-leg balance maintained on the foam pad — one foot stays on the pad, the other leg remains lifted with the knee bent."
    ),
    (
        "single-leg-balance-hold",
        "Held single-leg balance position. Standing on the LEFT leg only with a slight knee bend. The RIGHT (non-standing) foot is clearly lifted off the floor with the knee bent at about 90 degrees, thigh near hip height. Arms are at the sides or extended for balance. Torso is upright. CRITICAL: this is a HELD position — only ONE foot on the floor, the other suspended in the air.",
        "FAILURE: in the end frame both feet are planted on the floor. The end position requires the same single-leg balance as the start — only the standing foot on the floor with the other leg lifted in the air, knee bent.",
        "FAILURE: end frame must preserve single-leg balance hold — one foot on the floor, the other lifted in the air with knee bent at 90 degrees."
    ),
    (
        "single-leg-stance",
        "Held single-leg stance. Standing on the LEFT leg only with a slight knee bend. The RIGHT foot is clearly lifted off the floor with the right knee bent at about 90 degrees, thigh raised to roughly hip height. Arms are at the sides or extended for balance. Torso upright. CRITICAL: only ONE foot on the floor; the other foot is suspended in the air.",
        "FAILURE: in the end frame both feet are planted on the floor. The end position requires the held single-leg stance — only the standing foot on the floor with the other leg lifted in the air, knee bent.",
        "FAILURE: end frame must show held single-leg stance — one foot on the floor, other leg lifted in the air with knee bent."
    ),
    (
        "single-leg-stance-support",
        "Held single-leg stance with rail support. Standing on the LEFT leg only beside the gym railing/wall, right hand fingertips lightly touching the rail. The RIGHT foot is clearly lifted off the floor with the knee bent at about 90 degrees. The standing left knee has a slight bend. Torso upright. CRITICAL: only ONE foot on the floor; the other suspended in the air.",
        "FAILURE: in the end frame both feet are planted on the floor. The end position requires single-leg stance with the rail providing light support — only the standing foot on the floor.",
        "FAILURE: end frame must preserve single-leg stance with rail support — one foot on the floor, the other lifted in the air with knee bent, fingertips lightly touching the rail."
    ),
    (
        "standing-balance-on-one-leg",
        "Held single-leg balance with wall/counter support. Standing on the LEFT leg only beside the wall/counter, right hand resting lightly on the surface. The RIGHT foot is clearly lifted off the floor with the right knee bent at about 90 degrees. The standing left knee has a slight bend. Torso upright. CRITICAL: only ONE foot on the floor.",
        "FAILURE: in the end frame both feet are planted on the floor. The end position requires single-leg balance with the wall/counter providing light support — only the standing foot on the floor.",
        "FAILURE: end frame must show held single-leg balance with the hand resting on the wall — one foot on the floor, the other lifted with knee bent."
    ),
    (
        "standing-single-leg-balance",
        "Held single-leg balance with chair/wall support. Standing on the LEFT leg only beside the chair/wall, right hand resting on the support. The RIGHT foot is clearly lifted off the floor with the right knee bent at about 90 degrees. The standing left knee has a slight bend. Torso upright. CRITICAL: only ONE foot on the floor.",
        "FAILURE: in the end frame both feet are planted on the floor. The end position requires single-leg balance with the chair/wall providing support — only the standing foot on the floor.",
        "FAILURE: end frame must show held single-leg balance with chair support — one foot on the floor, the other lifted with knee bent."
    ),
    (
        "standing-single-leg-stance",
        "Held single-leg stance. Standing on the LEFT leg only near a wall or sturdy chair (not actively touching, ready to grasp if needed). The RIGHT foot is clearly lifted off the floor with the right knee bent at about 90 degrees. Arms at sides ready to grasp support. Torso upright. CRITICAL: only ONE foot on the floor.",
        "FAILURE: in the end frame both feet are planted on the floor. The end position requires held single-leg stance — only the standing foot on the floor with the other leg lifted, knee bent.",
        "FAILURE: end frame must show held single-leg stance — one foot on the floor, other leg lifted in the air with knee bent."
    ),
    (
        "standing-single-leg-stance-band",
        "Held single-leg stance with band support. Standing on the LEFT leg only facing a wall, the resistance band looped around a wall post at waist height held in both hands at the waist for light support. The RIGHT foot is clearly lifted off the floor with the right knee bent at about 90 degrees. The standing left knee has a slight bend. Torso upright. CRITICAL: only ONE foot on the floor.",
        "FAILURE: in the end frame both feet are planted on the floor. The end position requires single-leg stance with the band providing light support at the waist — only the standing foot on the floor.",
        "FAILURE: end frame must show held single-leg stance with band — one foot on the floor, the other lifted with knee bent, band held at waist for light feedback."
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
