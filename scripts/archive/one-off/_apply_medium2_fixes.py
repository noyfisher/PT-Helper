"""
Fix run #2: 3 additional MEDIUM-tier failures from batches 6-7.
"""
import json
from pathlib import Path

OUT = Path(__file__).resolve().parent / "output"
META = OUT / "all_exercises_metadata.json"
QA = OUT / "qa_all_starts_report.json"

FIXES = [
    (
        "internal-rotation",
        "Standing upright facing the camera with feet shoulder-width apart. The RIGHT (working) elbow is BENT at 90 degrees and TUCKED FIRMLY against the right side of the ribs (upper arm vertical, hugging the torso). The right forearm is HORIZONTAL pointing AWAY from the body to the right side (forearm at hip height pointing 90 degrees outward, the canonical START position for internal rotation). The right hand grips one end of a resistance band; the OTHER end is anchored to a fixed point on the RIGHT side of the body (the band runs from the right hand horizontally outward to a wall anchor on the right). The left arm hangs at the side. CRITICAL: the right elbow stays GLUED to the right ribs throughout — the upper arm does not lift away from the torso. CRITICAL: this is UNILATERAL — only ONE working arm is engaged with the band; the LEFT arm hangs at the side, NOT extended forward. CRITICAL: BOTH arms extended forward holding a band depicts a band pull-apart, NOT internal rotation — that is wrong.",
        "FAILURE: image shows BOTH arms extended forward holding the band like a pull-apart or chest press. The exercise is shoulder INTERNAL rotation: only ONE working arm is engaged, with the elbow tucked tightly at the side of the ribs and the forearm rotating inward across the body. The other arm must hang at the side. Both arms forward is wrong (different exercise)."
    ),
    (
        "isometric-shoulder-external-rotation",
        "Standing next to a wall, with the body parallel to the wall and the RIGHT working arm closest to the wall. The RIGHT elbow is BENT at 90 degrees and PINNED FIRMLY at the SIDE of the right ribs (upper arm vertical hugging the torso, NOT raised up high). The right forearm is HORIZONTAL pointing forward (across the front of the body), with the back of the wrist/hand pressed firmly outward into the wall to the right side, as if trying to externally rotate against the wall's resistance. No visible movement — purely isometric pressing. The left arm hangs at the side. CRITICAL: the elbow is at WAIST/RIB height tucked at the side, NOT raised at shoulder height with the hand pressing the wall above the head. CRITICAL: the BACK of the wrist is what contacts the wall (because the forearm is rotating outward into it), NOT the palm.",
        "FAILURE: image shows the arm RAISED UP HIGH with the palm pressing flat against the wall at head/shoulder height. That is a wall-press, NOT isometric ER. The correct setup keeps the elbow BENT at 90 and PINNED at the SIDE of the ribs (waist height), with the forearm horizontal pointing forward and the BACK of the wrist pressing outward into the wall. Raised-arm against the wall is the wrong setup entirely."
    ),
    (
        "lateral-side-lying-clam-shell",
        "Lying on the LEFT side with the body in a clam-shell setup. CRITICAL: the hips are BENT at approximately 45 degrees AND the KNEES ARE BENT at approximately 90 degrees — both legs are clearly bent (NOT extended). The feet are stacked TOGETHER touching each other, and the legs are stacked one on top of the other. The bottom (left) arm extends under the head for support; the top (right) hand rests on the right hip. A resistance band may be looped around both thighs just above the knees. CRITICAL: the legs MUST be BENT at 90 degrees at the knees — this is fundamental to the clamshell exercise. Extended/straight legs depict a different exercise (side-lying hip abduction), which is WRONG. CRITICAL: the feet are TOGETHER, touching each other, with knees bent.",
        "FAILURE: image shows the legs EXTENDED (straight at the knees) like a side-lying hip abduction setup. The clam-shell exercise REQUIRES both knees bent at approximately 90 degrees with hips bent at 45 degrees, feet stacked together. The bent-knee position is the defining feature of a clamshell — without it, this is a different exercise (side-lying hip abduction). The pelvis must NOT rotate backward."
    ),
]


def main():
    meta = json.loads(META.read_text())
    by_name = {e["normalized_filename"]: e for e in meta["exercises"]}
    qa = json.loads(QA.read_text())

    updated_meta = 0
    updated_qa = 0
    for fname, new_desc, fail_obs in FIXES:
        if fname not in by_name:
            print(f"MISSING: {fname}")
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

    META.write_text(json.dumps(meta, indent=2))
    QA.write_text(json.dumps(qa, indent=2))
    print(f"Updated metadata: {updated_meta}")
    print(f"Updated QA: {updated_qa}")


if __name__ == "__main__":
    main()
