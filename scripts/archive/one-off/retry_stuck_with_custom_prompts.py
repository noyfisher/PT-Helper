"""
Retry the 27 stuck-at-<3 exercises with exercise-specific custom prompts
that explicitly address what went wrong (based on Gemini's observations).

Each custom prompt:
  - Leads with the DISTINGUISHING feature of the exercise
  - Spells out direction-sensitive details (band pull direction, wrist orientation)
  - Includes anti-cues where the generic prompt was getting confused
  - Specifies camera angle (side-profile for subtle movements)

After regen, re-runs the same QA to update scores in qa_all_starts_report.json.
Old images are preserved in scripts/output/_flux_backup/ (already backed up by
the previous regen pass); this script additionally backs up the post-regen
version to _nb_round1_backup/ before overwriting.

Usage:
  python scripts/retry_stuck_with_custom_prompts.py --api-key KEY
  python scripts/retry_stuck_with_custom_prompts.py --api-key KEY --only wrist-curls
"""
from __future__ import annotations

import argparse
import json
import shutil
import sys
import time
from pathlib import Path

from google import genai
from google.genai import types

SCRIPT_DIR = Path(__file__).resolve().parent
OUTPUT_DIR = SCRIPT_DIR / "output"
BACKUP1 = OUTPUT_DIR / "_nb_round1_backup"
METADATA = OUTPUT_DIR / "all_exercises_metadata.json"
QA_REPORT = OUTPUT_DIR / "qa_all_starts_report.json"
MODEL = "gemini-3-pro-image-preview"

SUBJECT = (
    "An athletic young man with short dark hair, lean fit build, "
    "wearing a fitted light gray athletic t-shirt, dark navy compression "
    "shorts, white ankle socks, and gray athletic sneakers."
)

STYLE = (
    "Style: clean professional fitness illustration, soft even studio lighting, "
    "plain white background, no text, labels, watermarks, or arrows anywhere. "
    "Single figure centered, full body visible from head to toe. "
    "The pose must EXACTLY match what is described."
)

# --- Custom anti-error prompts per exercise ---
CUSTOM: dict[str, str] = {
    "eccentric-calf-lowering":
        "Side-profile view. Standing on one leg on the EDGE of a step with ONLY "
        "the BALL of the foot on the step. The heel is hanging OFF THE BACK EDGE, "
        "clearly LOWERED below the step surface, dropping toward the floor below. "
        "The other leg is lifted off the step, not touching anything. "
        "One hand rests on a wall for balance. Do NOT show a flat-footed stance.",

    "eccentric-hamstring-curls":
        "Kneeling upright on both knees on a padded mat, body held in a straight "
        "line from knees to head. Ankles are HELD DOWN from behind by a partner's "
        "hands or wedged under a fixed surface. Torso then tips forward slowly, "
        "leaning toward the floor while maintaining the straight hip-to-head line. "
        "Arms crossed in front of chest. Side-profile view.",

    "forearm-rotation-band":
        "Standing upright, feet shoulder-width apart. ONE upper arm is tucked "
        "against the side, elbow bent 90 degrees, forearm parallel to the floor "
        "pointing straight forward. That hand grips one end of a resistance band "
        "whose other end is anchored to a low fixed point beside the body. "
        "The forearm rotates so the palm faces DOWN (pronation). Upper arm stays "
        "completely still. Front view showing the forearm rotation clearly.",

    "lateral-lunge-dumbbell":
        "Wide lateral lunge stance: one leg deeply bent at the knee lunging "
        "sideways, other leg fully extended straight out sideways. Upper body "
        "upright. BOTH hands cup a single dumbbell vertically held at CHEST "
        "HEIGHT in a goblet grip. Front-facing view showing the very wide stance. "
        "Do NOT show a forward lunge or a bicep curl.",

    "resistance-band-ankle-eversion":
        "Seated upright on a chair with both feet flat on the floor. ONE resistance "
        "band is looped around the OUTSIDE of the working foot's forefoot only "
        "(not both feet). The band stretches AWAY from the body, anchored on the "
        "OPPOSITE side (midline side). The working ankle ROLLS OUTWARD so the "
        "SOLE FACES AWAY from the midline, working against the band that pulls "
        "it inward. Close-up front view of the feet.",

    "reverse-wrist-curls":
        "Seated on a bench. The working forearm rests FLAT on the thigh with the "
        "PALM FACING DOWN, holding a small dumbbell. The HAND and WRIST hang off "
        "the front edge of the knee. The wrist is EXTENDED so the BACK of the "
        "hand lifts UPWARD toward the ceiling. Side-profile view showing the "
        "horizontal forearm on the thigh. NOT a bicep curl.",

    "seated-adductor-squeeze-with-band":
        "Seated upright on a chair. A resistance band is placed BETWEEN the two "
        "knees (on the INNER side of each knee). The knees press INWARD, squeezing "
        "the band between them. The band is COMPRESSED between the knees. Feet "
        "flat on the floor. Front-facing view showing the band held between knees.",

    "seated-ankle-inversion-with-band":
        "Seated on a chair with one ankle crossed over the opposite knee (figure-4 "
        "position, working foot elevated). A resistance band is looped around the "
        "forefoot of that elevated foot and anchored on the LATERAL (outer) side. "
        "The foot TURNS INWARD, sole rotating to face the other leg (inversion), "
        "fighting the band's outward pull. Front-quarter view.",

    "toe-raises":
        "Side-profile view. Standing upright with back flat against a wall. "
        "HEELS remain firmly PLANTED on the ground. TOES and the forefoot are "
        "LIFTED clearly OFF the floor, pivoting on the heels. Weight is entirely "
        "on the heels. This is the OPPOSITE of a calf raise — do NOT show heels "
        "up. The lifted toes should be visible.",

    "wrist-curls":
        "Seated on a bench. The working forearm rests FLAT on the thigh with the "
        "PALM FACING UP, holding a small dumbbell. The HAND and WRIST hang off "
        "the front edge of the knee. The wrist CURLS UPWARD toward the forearm "
        "(wrist flexion), the dumbbell rising up. Side-profile view showing the "
        "horizontal forearm resting on the thigh. NOT a bicep curl.",

    "calf-stretch-band-wall":
        "Seated on the floor with ONE leg extended straight in front. A long "
        "towel or resistance band is looped around the BALL of the EXTENDED "
        "foot. Both hands hold the ends of the band and pull it back toward "
        "the body, pulling the foot's toes up toward the shin (dorsiflexion) "
        "to stretch the calf. Other leg is bent comfortably. Side view.",

    "chin-tucks":
        "Strict side-profile view of a man standing upright. He is performing "
        "a chin retraction: the head is drawn STRAIGHT BACK horizontally (NOT "
        "tilted down), creating a visible DOUBLE CHIN beneath the jaw. The "
        "neck appears slightly shortened. The chin is clearly pulled BACK, "
        "not tucked down. Emphasize the backward horizontal head position.",

    "dumbbell-pullovers":
        "Lying supine on a flat weight bench, upper back supported by the bench, "
        "feet flat on the floor. BOTH HANDS cup a single dumbbell together "
        "(holding one end in two hands). Arms are extended STRAIGHT UP directly "
        "above the chest. Side-profile view of the bench.",

    "intrinsic-foot-strengthening":
        "Seated upright on a chair with BARE feet on the floor (NO socks, NO "
        "shoes). The toes are actively CURLING DOWNWARD, scrunching a small "
        "hand towel on the floor beneath the toes. Close-enough view to see "
        "the bare toes gripping the towel. Do not show socks or shoes.",

    "lying-hip-flexor-stretch":
        "Lying supine on the EDGE of a bench or massage table. ONE leg hangs "
        "OFF the edge, dropping DOWN toward the floor with the knee bent at "
        "about 90 degrees. The other leg is pulled toward the chest, both arms "
        "wrapping around that bent knee holding it in. The dropped leg stretches "
        "the hip flexor. Side view showing the hanging leg clearly.",

    "median-nerve-gliding":
        "Seated upright. One arm is raised to the side at shoulder height, "
        "elbow fully extended STRAIGHT, palm facing UP toward the ceiling. "
        "The wrist is extended so the fingers point UP. The head is tilted "
        "AWAY from the raised arm. Front-facing view showing the extended arm.",

    "open-book-stretch":
        "Side-lying on the floor, both knees bent and stacked, hips stacked. "
        "BOTH arms extended straight out in front of the chest with palms "
        "together. Now the TOP arm lifts up and opens outward in an arc, "
        "rotating the torso to reach BEHIND the body on the opposite side "
        "(thoracic rotation). Bottom arm stays resting on the floor in front. "
        "Like opening a book. Overhead view showing the rotating torso.",

    "prone-gastrocnemius-stretch":
        "Lying prone on a mat, forearms supporting upper body in a light press-up. "
        "One knee is bent 90 degrees with the foot pointing UP toward the ceiling. "
        "The ankle is DORSIFLEXED (toes pulled toward the shin), and the heel "
        "is pressed UP toward the ceiling, stretching the calf. Side view "
        "showing the bent knee with heel up and toes curled toward shin.",

    "resisted-ankle-dorsiflexion":
        "Seated on the floor with ONE leg extended straight in front. A "
        "resistance band is looped around the FOREFOOT of the extended leg. "
        "The OTHER end of the band is anchored to a LOW POINT IN FRONT of the "
        "figure (not behind). The foot pulls UP toward the shin (dorsiflexion) "
        "against the band's forward pull. Side view showing the forward anchor.",

    "scapular-squeezes":
        "Seated upright on a chair. Arms relaxed at sides. The SHOULDER BLADES "
        "are actively SQUEEZED TOGETHER toward the spine, clearly visible as "
        "pinched tension in the upper back. The chest opens forward as the "
        "scapulae retract. Rear-quarter view showing the pinched shoulder blades.",

    "seated-cervical-retraction":
        "Strict side-profile view of a man seated upright on a chair. Head is "
        "drawn STRAIGHT BACK horizontally (not tilted down), creating a visible "
        "DOUBLE CHIN beneath the jaw. The cervical spine is clearly retracted "
        "backward. Feet flat on floor, arms relaxed.",

    "seated-hip-rotation-stretch":
        "Seated upright on the floor, ONE leg extended straight in front. The "
        "OTHER knee is bent with that foot placed flat on the floor on the "
        "OUTSIDE of the extended leg's knee (crossed over). The opposite elbow "
        "hooks against the OUTSIDE of the bent knee, pressing it across the "
        "body, rotating the torso toward the bent-knee side. Stretches the "
        "glute/piriformis.",

    "serratus-anterior-punch-prone":
        "Prone on a flat bench, face down, legs extended behind. Both arms hang "
        "STRAIGHT DOWN over the sides of the bench, each hand holding a light "
        "dumbbell. The shoulder blades PROTRACT (round forward), pushing the "
        "dumbbells DOWNWARD toward the floor — like punching downward. The "
        "elbows stay straight. Side view showing the downward push.",

    "short-arc-quads":
        "Supine on the floor. A large foam roller or bolster is placed UNDER "
        "ONE knee, lifting that knee to approximately 30 degrees of bend. "
        "That SAME leg LIFTS the foot off the floor, straightening the knee "
        "completely at the top while the knee itself stays resting on the "
        "bolster. The other leg is extended fully flat on the floor. Side "
        "view showing the lifted foot.",

    "single-leg-calf-raise":
        "Side-profile view. Standing on ONE leg beside a wall, one hand on the "
        "wall for balance. The other foot is lifted off the floor behind. "
        "The standing leg's HEEL is CLEARLY RAISED off the floor; all weight "
        "is on the BALL of the foot and toes. Heel is elevated several inches. "
        "NOT a flat-footed single-leg stand.",

    "supine-cross-body-shoulder-stretch":
        "Lying supine on the floor with knees bent, feet flat. ONE arm is raised "
        "toward the ceiling then brought ACROSS the body horizontally toward the "
        "opposite shoulder. The OPPOSITE hand grips the raised elbow and gently "
        "pulls it further across the chest. Stretches the posterior shoulder. "
        "Top-down view showing the crossed arm.",

    "tandem-stance-heel-to-toe":
        "Standing upright. ONE foot is placed DIRECTLY IN FRONT of the other, "
        "so the HEEL of the front foot TOUCHES the TOES of the back foot, "
        "forming a single straight line. Arms held slightly out at sides for "
        "balance. Side-quarter view showing the heel-to-toe foot alignment.",
}


def build_prompt(name: str, ex: dict) -> str:
    custom = CUSTOM[name]
    return (
        f"Clean professional fitness illustration.\n\n"
        f"Subject: {SUBJECT}\n\n"
        f"Exercise: {ex['name']}\n\n"
        f"Pose (follow EXACTLY):\n{custom}\n\n"
        f"{STYLE}"
    )


def generate_image(client: genai.Client, prompt: str) -> bytes | None:
    try:
        resp = client.models.generate_content(
            model=MODEL,
            contents=prompt,
            config=types.GenerateContentConfig(response_modalities=["IMAGE"]),
        )
    except Exception as e:
        print(f"    GEN ERROR: {e}")
        return None
    for cand in (resp.candidates or []):
        if cand.content and cand.content.parts:
            for part in cand.content.parts:
                inline = getattr(part, "inline_data", None)
                if inline and inline.data:
                    return inline.data
    return None


def qa_new_image(client: genai.Client, img_path: Path, ex: dict) -> dict:
    sys.path.insert(0, str(SCRIPT_DIR))
    from qa_exercise_images import analyze_image
    result = analyze_image(client, img_path, ex)
    return json.loads(result.model_dump_json())


def update_report(name: str, new_qa: dict) -> None:
    report = json.loads(QA_REPORT.read_text())
    report["results"][name] = new_qa
    total = len(report["results"])
    passed = sum(1 for v in report["results"].values() if v.get("overall_pass"))
    report["total_images"] = total
    report["passed"] = passed
    report["failed"] = total - passed
    QA_REPORT.write_text(json.dumps(report, indent=2))


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--api-key", required=True)
    ap.add_argument("--only", help="Comma-separated subset")
    args = ap.parse_args()

    BACKUP1.mkdir(parents=True, exist_ok=True)
    meta = {e["normalized_filename"]: e
            for e in json.loads(METADATA.read_text())["exercises"]}

    names = list(CUSTOM.keys())
    if args.only:
        names = [n.strip() for n in args.only.split(",") if n.strip() in CUSTOM]

    client = genai.Client(api_key=args.api_key)

    rows = []
    upgraded = unchanged = regressed = failed = 0

    for idx, name in enumerate(names, 1):
        ex = meta.get(name)
        if not ex:
            print(f"[{idx}/{len(names)}] {name}: no metadata, skip")
            failed += 1
            continue

        old_score = json.loads(QA_REPORT.read_text())["results"][name].get("pose_score")
        print(f"\n[{idx}/{len(names)}] {name}  (was {old_score}/5)")

        src = OUTPUT_DIR / f"{name}.png"
        if src.exists():
            bk = BACKUP1 / f"{name}.png"
            if not bk.exists():
                shutil.copy2(src, bk)

        prompt = build_prompt(name, ex)
        img_bytes = generate_image(client, prompt)
        if not img_bytes:
            print(f"  generation FAILED")
            failed += 1
            time.sleep(2)
            continue

        src.write_bytes(img_bytes)
        print(f"  generated -> {src.name}")

        qa = qa_new_image(client, src, ex)
        new_score = qa.get("pose_score")
        obs = qa.get("pose_accuracy", {}).get("observation", "")
        print(f"  new score: {new_score}/5")
        if obs:
            print(f"    obs: {obs[:180]}")

        update_report(name, qa)
        rows.append((name, old_score, new_score))

        if new_score is None or old_score is None:
            pass
        elif new_score > old_score:
            upgraded += 1
        elif new_score < old_score:
            regressed += 1
        else:
            unchanged += 1

        time.sleep(2)

    print("\n" + "=" * 72)
    print("CUSTOM-PROMPT RETRY SUMMARY")
    print("=" * 72)
    print(f"  Attempted:  {len(names)}")
    print(f"  Upgraded:   {upgraded}")
    print(f"  Unchanged:  {unchanged}")
    print(f"  Regressed:  {regressed}")
    print(f"  Failed:     {failed}")
    print()
    print(f"{'Exercise':<42} {'old':>5} {'new':>5}")
    for name, old, new in rows:
        arrow = "->" if (new or 0) > (old or 0) else ("==" if (new or 0) == (old or 0) else "vv")
        print(f"{name:<42} {str(old):>5} {arrow} {str(new):>4}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
