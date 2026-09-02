#!/usr/bin/env python3
"""
apply_image_qa_fixes.py

Idempotent script that patches three JSON files to force a regeneration pass
for 11 specific exercise slugs.

What it does:
  - all_exercises_metadata.json  : updates pose_description (and
                                   end_pose_description where provided)
  - qa_all_starts_report.json    : sets pose_score=0, overall_pass=false,
                                   pose_accuracy.observation=<start_obs>
  - consistency_report.json      : (START+END slugs only) sets
                                   overall_consistency_score=0,
                                   overall_pass=false,
                                   movement_logic.score=2 + .observation,
                                   body_anchoring.score=2  + .observation

What it does NOT do:
  - Call any API
  - Generate or modify any image file
  - Remove or alter any field not listed above

Usage:
  python3 scripts/apply_image_qa_fixes.py [--dry-run]

  --dry-run   Print what would change without writing any files.

Output:
  Per-slug summary line:
    <slug> | pose_score <old>→<new> | cr_score <old>→<new>
             | pose_desc[:60] <old>→<new>
             | end_desc[:60]  <old>→<new>  (if changed)
"""

import argparse
import copy
import json
import os
import sys

# ---------------------------------------------------------------------------
# Paths (all relative to the repo root; resolved to absolute below)
# ---------------------------------------------------------------------------
_REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
_SCRIPTS_OUTPUT = os.path.join(_REPO_ROOT, "scripts", "output")

META_PATH = os.path.join(_SCRIPTS_OUTPUT, "all_exercises_metadata.json")
QA_PATH   = os.path.join(_SCRIPTS_OUTPUT, "qa_all_starts_report.json")
CR_PATH   = os.path.join(_SCRIPTS_OUTPUT, "consistency_report.json")

# ---------------------------------------------------------------------------
# Fix definitions
# ---------------------------------------------------------------------------
# Each entry:
#   slug           : normalized_filename key used everywhere
#   pose_desc      : new value for metadata.pose_description
#   end_pose_desc  : new value for metadata.end_pose_description (None → skip)
#   start_obs      : new value for qa_all_starts_report pose_accuracy.observation
#   end_obs        : (START+END only) text for consistency_report
#                    movement_logic.observation AND body_anchoring.observation
# ---------------------------------------------------------------------------
FIXES = [
    {
        "slug": "prone-iyt-raises-band",
        "pose_desc": (
            "Lie face-down (prone) on a flat bench with your entire torso and chest fully "
            "supported on the bench surface, hips on the bench, and both feet resting on the "
            "floor behind you. Hold one end of a light resistance band in EACH hand with both "
            "arms hanging straight down toward the floor off the side of the bench. Forehead "
            "neutral, gaze down. Clean flat fitness illustration, single figure, plain white "
            "background. CRITICAL: the chest rests ON the bench (this is NOT a decline plank "
            "and the chest must NOT hang off the end of the bench); BOTH hands hold the band "
            "hanging down; the band is held only in the hands and is NOT looped around the "
            "feet or any table leg."
        ),
        "end_pose_desc": (
            "Keeping the chest supported on the bench, raise both arms out and up away from "
            "the floor into the I, Y, and T overhead positions, squeezing the rear shoulder "
            "blades, with both hands still holding the band. Both arms move together "
            "symmetrically."
        ),
        "start_obs": (
            "WRONG: the figure's chest hangs off the end of the bench with hips on the bench "
            "in a decline-plank position; the band is incorrectly routed around the foot and "
            "a table leg; only one arm holds the band; rendered photo-realistic. CORRECT: "
            "prone with the whole chest/torso supported flat on the bench, feet on the floor, "
            "BOTH hands holding the band hanging straight down off the side, clean "
            "illustration style."
        ),
        "end_obs": (
            "Both frames: chest stays supported on the bench, BOTH hands hold the band, no "
            "band routed around feet/table. Start = arms hanging down; End = arms raised "
            "overhead/out squeezing shoulder blades."
        ),
    },
    {
        "slug": "scapular-stabilization-band",
        "pose_desc": (
            "Stand upright with feet hip-width apart and hold a resistance band at chest "
            "height with both hands, arms extended straight AHEAD in front of the chest, with "
            "a slight bend in the elbows. Core engaged, shoulders relaxed away from ears. "
            "CRITICAL: at the start BOTH arms point straight FORWARD/AHEAD in front of the "
            "body holding the band, arms close together — the arms must NOT be spread wide "
            "out to the sides (arms wide is the end position, not the start)."
        ),
        "end_pose_desc": (
            "Pull the band apart by drawing both hands out to the sides at chest height, "
            "squeezing the shoulder blades together, keeping elbows slightly bent and spine "
            "neutral."
        ),
        "start_obs": (
            "WRONG: arms are pulled wide out to the sides (the band-pull-apart END position). "
            "CORRECT: this is the START — both arms extended straight forward in front of the "
            "chest holding the band, arms close together, NOT abducted to the sides."
        ),
        "end_obs": (
            "Start = arms forward together in front of chest; End = arms pulled wide to the "
            "sides squeezing shoulder blades. The two frames must clearly differ."
        ),
    },
    {
        "slug": "kneeling-quadruped-shoulder-reaches",
        "pose_desc": (
            "A clean fitness illustration of EXACTLY ONE single person on hands and knees "
            "(quadruped) with shoulders directly over wrists and hips over knees, neutral "
            "spine, plain white background. CRITICAL: render only ONE figure — no duplicated, "
            "overlapping, doubled, or ghosted bodies; exactly one head, one torso, two arms, "
            "two legs."
        ),
        "end_pose_desc": (
            "The single figure reaches one arm forward and slightly across the body, extending "
            "through the shoulder while the torso stays stable on the supporting hand and both "
            "knees. Exactly one figure, no duplication."
        ),
        "start_obs": (
            "WRONG: the image contains two overlapping/ghosted figures (two heads and two "
            "torsos superimposed). CORRECT: exactly ONE single clean figure in a neutral "
            "quadruped position, no duplication or ghosting."
        ),
        "end_obs": (
            "Render exactly ONE figure (no ghosting/duplication). Start = neutral quadruped; "
            "End = one arm reaching forward, torso stable."
        ),
    },
    {
        "slug": "resistance-band-reverse-pec-flyes",
        "pose_desc": (
            "Sit upright with feet flat on the floor and a resistance band anchored at chest "
            "height in front of you, holding both ends with both arms extended straight "
            "FORWARD together in front of the chest. Shoulders relaxed, spine neutral. "
            "CRITICAL: at the start BOTH arms are extended straight forward in front of the "
            "chest holding the band ends together — the arms must NOT be spread wide apart to "
            "the sides (arms wide is the end position)."
        ),
        "end_pose_desc": (
            "Pull the band outward and back, moving both arms out to the sides while squeezing "
            "the shoulder blades together, opening the chest and engaging the upper back."
        ),
        "start_obs": (
            "WRONG: arms are spread wide out to the sides (the reverse-fly END position). "
            "CORRECT: START position with both arms extended forward together in front of the "
            "chest holding the anchored band, arms NOT yet pulled apart."
        ),
        "end_obs": (
            "Start = arms forward together; End = arms pulled out wide to the sides squeezing "
            "shoulder blades. Frames must clearly differ."
        ),
    },
    {
        "slug": "sidelying-external-rotation-band",
        "pose_desc": (
            "A clean fitness illustration of ONE single coherent person lying on their LEFT "
            "side on the floor, head supported, with the right shoulder flexed and the right "
            "elbow bent to about 90 degrees tucked at the ribs, the right hand holding a "
            "resistance band at chest level. Both legs are extended and resting along the "
            "floor, stacked. CRITICAL: render exactly one anatomically connected body — NO "
            "floating, detached, disembodied, or extra limbs anywhere in the image; both legs "
            "remain attached to the body and resting on the floor."
        ),
        "end_pose_desc": (
            "Keeping the right elbow fixed at the ribs, rotate the right forearm upward/outward "
            "against the band (external rotation). One single coherent body, no detached or "
            "floating limbs."
        ),
        "start_obs": (
            "WRONG: a detached/floating lower leg (disembodied limb) appears in the upper-right "
            "of the image. CORRECT: one single coherent body lying on the left side, both legs "
            "connected and resting on the floor, right elbow bent at the ribs holding the band "
            "— no floating or extra limbs."
        ),
        "end_obs": (
            "One single coherent body, no floating/extra limbs. Start = forearm down across "
            "body; End = forearm rotated up/out, elbow fixed at ribs."
        ),
    },
    {
        "slug": "resistance-band-forearm-pronation",
        "pose_desc": (
            "Sit with your elbow bent at 90 degrees, upper arm held close against your side, "
            "and your forearm pointing forward horizontally with the open palm facing clearly "
            "UP toward the ceiling (supinated start position). Loop the resistance band around "
            "your hand and anchor the other end under your foot. CRITICAL: the open palm faces "
            "directly upward and is clearly visible; the forearm is horizontal; show a clear "
            "side or three-quarter view so the palm-up orientation is unambiguous; render a "
            "single static start position."
        ),
        "end_pose_desc": None,  # START only
        "start_obs": (
            "WRONG: the palm orientation is ambiguous and reads as neutral/thumb-up rather than "
            "clearly palm-up; the band drops straight down making the rotation unclear. CORRECT: "
            "forearm horizontal with the open palm facing clearly UP toward the ceiling at the "
            "start, viewed so the palm orientation is unmistakable."
        ),
        "end_obs": None,
    },
    {
        "slug": "resistance-band-forearm-supination",
        "pose_desc": (
            "Sit with your elbow bent at 90 degrees, upper arm held close against your side, "
            "and your forearm pointing forward horizontally with the palm facing clearly DOWN "
            "toward the floor (pronated start position, back of the hand up). Loop the "
            "resistance band around your hand and anchor the other end under your foot. "
            "CRITICAL: the back of the hand faces up and the palm faces directly DOWN toward "
            "the floor; the forearm is horizontal; show a clear side or three-quarter view so "
            "the palm-down orientation is unambiguous; render a single static start position."
        ),
        "end_pose_desc": None,  # START only
        "start_obs": (
            "WRONG: the palm appears to face up (supinated) rather than the required palm-DOWN "
            "start; orientation ambiguous. CORRECT: forearm horizontal with the palm facing "
            "clearly DOWN toward the floor at the start, viewed so orientation is unmistakable."
        ),
        "end_obs": None,
    },
    {
        "slug": "pronation-supination-rotation",
        "pose_desc": (
            "Sit at a table with your elbow bent to 90 degrees and your forearm resting flat "
            "and supported on the tabletop (or on a rolled towel), with the hand extending just "
            "past the table edge. Start with the palm facing clearly DOWN toward the table. Keep "
            "the elbow stationary against the table. CRITICAL: at the start the palm faces DOWN; "
            "render a single static start position with NO motion arcs, NO arrows, and NO "
            "mid-rotation hand; the orientation must be unambiguous."
        ),
        "end_pose_desc": None,  # START only
        "start_obs": (
            "WRONG: the hand is shown mid-rotation with the palm reading as up and a motion arc, "
            "so the start position is unclear. CORRECT: a single static START with the forearm "
            "resting on the table and the palm facing clearly DOWN, no motion lines or arrows."
        ),
        "end_obs": None,
    },
    {
        "slug": "supine-chest-stretch-band",
        "pose_desc": (
            "Lie on your back on a mat with knees bent and feet flat on the floor. Hold a light "
            "resistance band taut between BOTH hands with your arms extended straight UP toward "
            "the ceiling above your chest, hands about shoulder-width apart. CRITICAL: the band "
            "is held between the two hands up over the chest and is NOT looped around or routed "
            "toward the knees or legs; both arms point straight up toward the ceiling at the "
            "start."
        ),
        "end_pose_desc": (
            "Keeping the band taut between both hands and arms roughly straight, lower both arms "
            "backward overhead toward the floor behind your head, opening the chest and feeling "
            "a stretch across the front of the shoulders and chest. The band stays between the "
            "hands and never routes to the knees."
        ),
        "start_obs": (
            "WRONG: the band is routed down toward the bent knees instead of being held up "
            "across the chest; it does not read as a chest stretch. CORRECT: supine, both hands "
            "holding the band taut with arms extended straight up over the chest toward the "
            "ceiling, band nowhere near the knees."
        ),
        "end_obs": (
            "Band stays between the two hands over/behind the chest in BOTH frames; never routes "
            "to the knees. Start = arms up toward ceiling; End = arms lowered overhead behind "
            "the head opening the chest."
        ),
    },
    {
        "slug": "tricep-extension-band",
        "pose_desc": (
            "Stand with feet shoulder-width apart, holding the resistance band overhead with "
            "both hands, with the ELBOWS BENT to about 90 degrees so the forearms and hands "
            "drop down BEHIND your head (the band runs down behind your back). Upper arms point "
            "straight up close to the ears. CRITICAL: at the start the elbows are clearly bent "
            "about 90 degrees with the hands behind the head — the arms are NOT straight and the "
            "band is NOT stretched taut horizontally between wide-apart hands above the head; "
            "upper arms stay vertical and close to the head."
        ),
        "end_pose_desc": None,  # START only
        "start_obs": (
            "WRONG: the arms are extended nearly straight overhead with the band stretched taut "
            "horizontally between wide-apart hands (looks like an overhead pull-apart). CORRECT: "
            "the START of an overhead triceps extension — elbows bent about 90 degrees, "
            "hands/forearms dropped behind the head, upper arms vertical close to the head, "
            "band running down behind the back."
        ),
        "end_obs": None,
    },
    {
        "slug": "prone-scapular-y-raises-with-band",
        "pose_desc": (
            "Lie face-down (prone) with your forehead resting on a small pillow or towel and "
            "legs straight. Hold a light resistance band with both hands and let BOTH ARMS HANG "
            "DOWN resting along your sides on the floor (the relaxed start, before the raise), "
            "thumbs up. CRITICAL: at the start both arms are DOWN at the sides resting on the "
            "floor — the arms are NOT yet raised overhead into the Y position (raised is the "
            "end); band held between the hands."
        ),
        "end_pose_desc": (
            "Raise both arms off the floor and overhead into a Y position (arms about 45 degrees "
            "out from the body, thumbs up), engaging the lower trapezius and lifting the band. "
            "Hold briefly at the top."
        ),
        "start_obs": (
            "WRONG: the image shows the arms already raised overhead into the elevated Y "
            "end-position. CORRECT: the START — prone with both arms resting DOWN at the sides "
            "on the floor holding the band, before any raise."
        ),
        "end_obs": (
            "Start = arms down at sides on the floor; End = arms raised overhead into the Y. "
            "The two frames must clearly differ (start low, end raised)."
        ),
    },
]


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _load_json(path: str) -> dict:
    with open(path, "r", encoding="utf-8") as fh:
        return json.load(fh)


def _write_json(path: str, data: dict, dry_run: bool) -> None:
    if dry_run:
        return
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(data, fh, indent=2, ensure_ascii=False)
        fh.write("\n")  # trailing newline


def _trunc(s: str, n: int = 60) -> str:
    s = s.replace("\n", " ")
    return s[:n] + "..." if len(s) > n else s


# ---------------------------------------------------------------------------
# Main apply logic
# ---------------------------------------------------------------------------

def apply_fixes(dry_run: bool = False) -> None:
    meta = _load_json(META_PATH)
    qa   = _load_json(QA_PATH)
    cr   = _load_json(CR_PATH)

    # Build a fast lookup: slug → index in meta["exercises"]
    meta_index: dict[str, int] = {
        e["normalized_filename"]: i
        for i, e in enumerate(meta["exercises"])
    }

    meta_changed = False
    qa_changed   = False
    cr_changed   = False

    print(f"{'DRY RUN — ' if dry_run else ''}Applying fixes to {len(FIXES)} slugs.\n")
    print(f"{'Slug':<45} {'pose_score':>10} {'cr_score':>10}  desc/obs changes")
    print("-" * 110)

    for fix in FIXES:
        slug      = fix["slug"]
        new_pd    = fix["pose_desc"]
        new_epd   = fix["end_pose_desc"]   # may be None
        start_obs = fix["start_obs"]
        end_obs   = fix["end_obs"]         # may be None

        changes = []

        # ---- 1) all_exercises_metadata.json --------------------------------
        if slug not in meta_index:
            print(f"  WARNING: slug '{slug}' NOT FOUND in metadata — skipping metadata patch")
        else:
            idx = meta_index[slug]
            ex  = meta["exercises"][idx]

            old_pd = ex.get("pose_description", "")
            if old_pd != new_pd:
                ex["pose_description"] = new_pd
                meta_changed = True
                changes.append(f"pose_desc: '{_trunc(old_pd)}'→'{_trunc(new_pd)}'")

            if new_epd is not None:
                old_epd = ex.get("end_pose_description", "")
                if old_epd != new_epd:
                    ex["end_pose_description"] = new_epd
                    meta_changed = True
                    changes.append(f"end_desc: '{_trunc(old_epd)}'→'{_trunc(new_epd)}'")

        # ---- 2) qa_all_starts_report.json ----------------------------------
        qa_results = qa.setdefault("results", {})
        if slug not in qa_results:
            qa_results[slug] = {}
            qa_changed = True
            changes.append("qa: created new entry")

        entry = qa_results[slug]

        old_ps = entry.get("pose_score", "MISSING")
        if old_ps != 0:
            entry["pose_score"] = 0
            qa_changed = True
            changes.append(f"pose_score: {old_ps}→0")

        old_op = entry.get("overall_pass", "MISSING")
        if old_op is not False:
            entry["overall_pass"] = False
            qa_changed = True
            changes.append(f"qa.overall_pass: {old_op}→False")

        pa = entry.setdefault("pose_accuracy", {})
        old_obs = pa.get("observation", "MISSING")
        if old_obs != start_obs:
            pa["observation"] = start_obs
            qa_changed = True
            changes.append(f"qa.obs: '{_trunc(old_obs)}'→'{_trunc(start_obs)}'")

        # ---- 3) consistency_report.json (START+END slugs only) -------------
        cr_score_before = "n/a"
        cr_score_after  = "n/a"

        if end_obs is not None:
            cr_results = cr.setdefault("results", {})
            if slug not in cr_results:
                cr_results[slug] = {}
                cr_changed = True
                changes.append("cr: created new entry")

            cr_entry = cr_results[slug]
            cr_score_before = cr_entry.get("overall_consistency_score", "MISSING")

            if cr_entry.get("overall_consistency_score") != 0:
                cr_entry["overall_consistency_score"] = 0
                cr_changed = True
                changes.append(f"cr_score: {cr_score_before}→0")
            cr_score_after = 0

            if cr_entry.get("overall_pass") is not False:
                old_cop = cr_entry.get("overall_pass", "MISSING")
                cr_entry["overall_pass"] = False
                cr_changed = True
                changes.append(f"cr.overall_pass: {old_cop}→False")

            # movement_logic
            ml = cr_entry.setdefault("movement_logic", {})
            if ml.get("score") != 2:
                old_ml_s = ml.get("score", "MISSING")
                ml["score"] = 2
                cr_changed = True
                changes.append(f"ml.score: {old_ml_s}→2")
            old_ml_obs = ml.get("observation", "MISSING")
            if old_ml_obs != end_obs:
                ml["observation"] = end_obs
                cr_changed = True
                changes.append(f"ml.obs: '{_trunc(old_ml_obs)}'→'{_trunc(end_obs)}'")

            # body_anchoring
            ba = cr_entry.setdefault("body_anchoring", {})
            if ba.get("score") != 2:
                old_ba_s = ba.get("score", "MISSING")
                ba["score"] = 2
                cr_changed = True
                changes.append(f"ba.score: {old_ba_s}→2")
            old_ba_obs = ba.get("observation", "MISSING")
            if old_ba_obs != end_obs:
                ba["observation"] = end_obs
                cr_changed = True
                changes.append(f"ba.obs: '{_trunc(old_ba_obs)}'→'{_trunc(end_obs)}'")

        # ---- Print summary row ----
        ps_display = f"{old_ps!s}→0" if old_ps != 0 else f"0 (no chg)"
        cr_display = (
            f"{cr_score_before!s}→0" if (end_obs is not None and cr_score_before != 0)
            else ("0 (no chg)" if end_obs is not None else "n/a (start-only)")
        )
        if changes:
            print(f"  {slug:<43} ps:{ps_display:<12} cr:{cr_display:<14}")
            for c in changes:
                print(f"    {c}")
        else:
            print(f"  {slug:<43} NO CHANGES (already at target state)")

    print()

    # ---- Write back --------------------------------------------------------
    if not dry_run:
        if meta_changed:
            _write_json(META_PATH, meta, dry_run=False)
            print(f"Wrote {META_PATH}")
        else:
            print(f"No changes to write for {META_PATH}")

        if qa_changed:
            _write_json(QA_PATH, qa, dry_run=False)
            print(f"Wrote {QA_PATH}")
        else:
            print(f"No changes to write for {QA_PATH}")

        if cr_changed:
            _write_json(CR_PATH, cr, dry_run=False)
            print(f"Wrote {CR_PATH}")
        else:
            print(f"No changes to write for {CR_PATH}")
    else:
        print("DRY RUN complete — no files written.")


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(
        description="Patch JSON files to force image regen for 11 exercise slugs."
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print what would change without writing any files.",
    )
    args = parser.parse_args()
    apply_fixes(dry_run=args.dry_run)


if __name__ == "__main__":
    main()
