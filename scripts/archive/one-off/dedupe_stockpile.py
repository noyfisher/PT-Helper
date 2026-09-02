#!/usr/bin/env python3
"""Dedupe the stockpile needs list before image generation.

Reads:
  - scripts/output/stockpile_progress.json          (source of truth for discovered exercises)
  - scripts/output/stockpile_sanity_report.json     (noise, near-duplicates, generic, compound)
  - scripts/output/stockpile_likely_aliases.json    (117 Jaccard-scored alias candidates)
  - scripts/output/exercise_image_mapping.json      (canonical set with images on disk)

Writes (with --apply):
  - scripts/output/stockpile_alias_map.json      {variant -> canonical} for Firestore upload
                                                 (merged at runtime by ExerciseImageService)
  - scripts/output/stockpile_dropped.json        audit log of what was removed and why
  - scripts/output/stockpile_needs_review.json   candidates whose token diff is unknown vocabulary
  - scripts/output/stockpile_progress.json       all_exercises trimmed (drops moved out)

Without --apply, prints the plan and writes nothing.

Classification of token-set symmetric diffs between variant and candidate:
  * SAFE   — diff is empty (reorder) / all cosmetic / all filler / all grammar / plural toggle
             of an action noun. Auto-merge.
  * SKIP   — diff contains any POSITION, EQUIPMENT, DIRECTION, LATERALITY, PHASE, or ROLE
             (assisted/resisted/...) token. Distinct image; auto-skip.
  * REVIEW — diff contains only unrecognized tokens. Could be muscle specifier, stretch suffix,
             or other semantic diff. Human decides.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUTPUT = ROOT / "scripts" / "output"
PROGRESS = OUTPUT / "stockpile_progress.json"
SANITY = OUTPUT / "stockpile_sanity_report.json"
ALIASES_IN = OUTPUT / "stockpile_likely_aliases.json"
MAPPING = OUTPUT / "exercise_image_mapping.json"
ALIAS_MAP_OUT = OUTPUT / "stockpile_alias_map.json"
DROPPED_OUT = OUTPUT / "stockpile_dropped.json"
REVIEW_OUT = OUTPUT / "stockpile_needs_review.json"
DECISIONS_IN = OUTPUT / "alias_review_decisions.json"

# --- Hand-picked canonical winners from sanity report near_duplicates ---
# (review: band-assisted vs band-resisted external rotation kept as two distinct exercises)
NEAR_DUP_CANONICAL: dict[str, str] = {
    "gentle-wrist-flexion-stretch": "wrist-flexion-stretch",
    "isometric-wrist-hold": "wrist-isometric-hold",
    "dumbbell-deadlifts-light": "dumbbell-deadlifts",
    "standing-quad-sets-band": "standing-quad-sets-with-band",
    "forearm-pronation-supination-mobility": "forearm-pronation-supination",
    "shoulder-rolls-seated": "seated-shoulder-rolls",
    "seated-torso-twist-gentle": "seated-torso-twist",
    "lateral-neck-flexion-stretch": "neck-lateral-flexion-stretch",
    "resistance-band-rows-seated": "seated-resistance-band-rows",
    "gentle-neck-flexion-extension": "neck-flexion-extension",
    "calf-raises-step": "calf-raises-on-step",
}

# --- Pure noise: not exercises, drop with no alias target ---
NOISE_DROP: set[str] = {
    "warm-compress-rest",
    "thermal-moist-heat-relaxation",
    "mirror-facial-awareness",
    "seated-sleeper-stretch",
}

# --- Safe token sets (all in diff => safe to merge) ---
COSMETIC_TOKENS: set[str] = {
    "gentle", "mild", "slow", "smooth", "controlled",
    "light", "lightweight", "heavy",
    "basic", "simple", "easy",
    "mobility", "flexibility",
}
FILLER_TOKENS: set[str] = {
    "with", "on", "in", "to", "the", "a", "an", "and", "for", "of", "at",
}
GRAMMAR_TOKENS: set[str] = {
    "exercises", "exercise", "drill", "drills",
}
SAFE_TOKENS: set[str] = COSMETIC_TOKENS | FILLER_TOKENS | GRAMMAR_TOKENS

# Action nouns whose singular/plural toggle (e.g. `raise`/`raises`) is a safe diff.
ACTION_NOUNS: set[str] = {
    "raise", "roll", "twist", "circle", "curl", "press", "row",
    "lift", "swing", "pull", "squat", "lunge", "bend", "tuck",
    "stretch", "hold", "slide", "reach", "crunch", "kick", "step",
    "set", "rotation",
}

# --- Skip token sets (any in diff => different image; auto-skip) ---
POSITION_TOKENS: set[str] = {
    "seated", "sitting", "standing", "supine", "prone", "lying",
    "sidelying", "kneeling", "quadruped",
    "wall", "floor", "inclined", "reclined",
    # NOTE: `side-lying` splits to ["side", "lying"]; `lying` alone catches it.
    # `side` lives in DIRECTION_TOKENS because it also appears in directional contexts.
}
EQUIPMENT_TOKENS: set[str] = {
    "band", "bands", "banded", "resistance", "resisted-band",
    "dumbbell", "dumbbells", "weight", "weighted",
    "kettlebell", "barbell", "cable", "ball", "foam", "roller",
    "box", "machine", "pulley", "bodyweight", "pillow", "towel", "strap", "stick",
}
DIRECTION_TOKENS: set[str] = {
    "forward", "backward", "back", "lateral", "medial", "side",
    "flexion", "extension", "abduction", "adduction", "rotation",
    "internal", "external", "pronation", "supination",
    "radial", "ulnar", "horizontal", "vertical", "diagonal",
}
LATERALITY_TOKENS: set[str] = {
    "bilateral", "unilateral", "alternating", "contralateral", "ipsilateral",
    # NOTE: `single-leg`/`double-leg` split; `single`/`double` captured below.
    "single", "double",
}
PHASE_TOKENS: set[str] = {
    "progression", "modified", "advanced", "beginner", "intermediate", "regression",
    # phase-N, level-N are multi-token after split; `phase`/`level` catch them.
    "phase", "level",
    # prep-position specifiers that define a distinct starting pose
    "90", "figure", "4", "four",
}
ROLE_TOKENS: set[str] = {
    "assisted", "resisted", "supported", "unsupported", "loaded", "unloaded",
}
SKIP_TOKENS: set[str] = (
    POSITION_TOKENS | EQUIPMENT_TOKENS | DIRECTION_TOKENS
    | LATERALITY_TOKENS | PHASE_TOKENS | ROLE_TOKENS
)


def tokens(key: str) -> set[str]:
    return set(key.split("-"))


def is_plural_toggle(diff: set[str]) -> bool:
    """True if diff is exactly one action noun toggled singular<->plural."""
    if len(diff) != 2:
        return False
    a, b = sorted(diff, key=len)
    return b == a + "s" and a in ACTION_NOUNS


def classify_alias(variant: str, canonical: str) -> str:
    """Return one of: 'safe', 'skip', 'review'."""
    diff = tokens(variant).symmetric_difference(tokens(canonical))
    if not diff:
        return "safe"  # pure reorder
    if is_plural_toggle(diff):
        return "safe"
    if diff & SKIP_TOKENS:
        return "skip"
    if diff.issubset(SAFE_TOKENS):
        return "safe"
    return "review"


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--apply", action="store_true", help="Write changes (default: dry run)")
    ap.add_argument("--consume-review", action="store_true",
                    help="Also fold merge decisions from alias_review_decisions.json into the alias map.")
    args = ap.parse_args()

    progress = json.loads(PROGRESS.read_text())
    sanity = json.loads(SANITY.read_text())
    likely = json.loads(ALIASES_IN.read_text())
    mapping = json.loads(MAPPING.read_text())

    all_ex: dict = progress["all_exercises"]
    # Idempotency: restore prior dedupe drops back into all_exercises before re-classifying.
    prior_drops = progress.pop("dropped_during_dedupe", {}) or {}
    for k, v in prior_drops.items():
        all_ex.setdefault(k, v)

    canonical_keys = set(mapping.keys()) | set(all_ex.keys())

    alias_map: dict[str, str] = {}
    drops: list[dict] = []

    # 1. Noise — drop outright.
    for key in NOISE_DROP:
        if key in all_ex:
            drops.append({"key": key, "reason": "noise", "canonical": None})

    # 2. Near-duplicate losers.
    for variant, canonical in NEAR_DUP_CANONICAL.items():
        if variant not in all_ex:
            continue
        if canonical not in canonical_keys:
            print(f"  skip near-dup {variant!r}: canonical {canonical!r} not in mapping/stockpile")
            continue
        alias_map[variant] = canonical
        drops.append({"key": variant, "reason": "near_duplicate", "canonical": canonical})

    # 3. Likely-alias candidates — classify each per the rule spec.
    auto_merged = 0
    skipped_auto = 0
    skipped_no_canonical = 0
    review_entries: list[dict] = []
    for entry in likely:
        variant = entry["needs_key"]
        if variant not in all_ex:
            continue
        if variant in alias_map or variant in NOISE_DROP:
            continue
        # Evaluate each candidate; pick highest-jaccard safe match, else record for review.
        safe_choice: str | None = None
        review_candidates: list[dict] = []
        saw_canonical = False
        for cand in sorted(entry["candidates"], key=lambda c: -c["jaccard"]):
            ck = cand["key"]
            if ck not in canonical_keys:
                continue
            saw_canonical = True
            verdict = classify_alias(variant, ck)
            if verdict == "safe" and safe_choice is None:
                safe_choice = ck
            elif verdict == "review":
                review_candidates.append({"canonical": ck, "jaccard": cand["jaccard"]})
        if safe_choice is not None:
            alias_map[variant] = safe_choice
            drops.append({"key": variant, "reason": "alias", "canonical": safe_choice})
            auto_merged += 1
        elif not saw_canonical:
            skipped_no_canonical += 1
        elif review_candidates:
            review_entries.append({
                "variant": variant,
                "variant_name": entry.get("needs_name", variant),
                "candidates": review_candidates,
            })
        else:
            skipped_auto += 1

    # 4. Optionally consume human-review decisions for variants not auto-merged.
    consumed_merges = 0
    consumed_skips = 0
    if args.consume_review and DECISIONS_IN.exists():
        decisions = json.loads(DECISIONS_IN.read_text())
        review_variants = {e["variant"] for e in review_entries}
        kept_review: list[dict] = []
        for e in review_entries:
            d = decisions.get(e["variant"])
            if not d:
                kept_review.append(e)
                continue
            if d["verdict"] == "merge":
                canonical = d["canonical"]
                if canonical not in canonical_keys:
                    print(f"  skip review-merge {e['variant']!r}: canonical {canonical!r} not found")
                    kept_review.append(e)
                    continue
                alias_map[e["variant"]] = canonical
                drops.append({"key": e["variant"], "reason": "review_merge", "canonical": canonical})
                consumed_merges += 1
            elif d["verdict"] == "skip":
                consumed_skips += 1
                # keep out of review list (decision made) but don't drop
        review_entries = kept_review

    # ---- Report ----
    needs_before = len(all_ex)
    drop_keys = {d["key"] for d in drops}
    needs_after = needs_before - len(drop_keys)
    print(f"Stockpile dedupe report")
    print(f"  Total exercises in stockpile:    {needs_before}")
    print(f"  Noise drops:                     {len(NOISE_DROP & set(all_ex.keys()))}")
    print(f"  Near-duplicate aliases:          {sum(1 for d in drops if d['reason']=='near_duplicate')}")
    print(f"  Safe auto-merged aliases:        {auto_merged}")
    print(f"  Auto-skipped (distinct image):   {skipped_auto}")
    print(f"  Flagged for human review:        {len(review_entries)}")
    if args.consume_review:
        print(f"  Consumed review merges:          {consumed_merges}")
        print(f"  Consumed review skips:           {consumed_skips}")
    print(f"  Skipped (no canonical on disk):  {skipped_no_canonical}")
    print(f"  ------")
    print(f"  Keys removed from needs:         {len(drop_keys)}")
    print(f"  Remaining exercises:             {needs_after}")
    print(f"  Alias map entries:               {len(alias_map)}")

    if not args.apply:
        print("\nDry run — pass --apply to write files.")
        return 0

    # ---- Write ----
    ALIAS_MAP_OUT.write_text(json.dumps(alias_map, indent=2, sort_keys=True) + "\n")
    DROPPED_OUT.write_text(json.dumps({"dropped": drops}, indent=2, sort_keys=True) + "\n")
    REVIEW_OUT.write_text(json.dumps({"needs_review": review_entries}, indent=2, sort_keys=True) + "\n")

    moved = {k: all_ex[k] for k in drop_keys if k in all_ex}
    for k in drop_keys:
        all_ex.pop(k, None)
    progress.setdefault("dropped_during_dedupe", {}).update(moved)
    PROGRESS.write_text(json.dumps(progress, indent=2) + "\n")

    print(f"\nWrote:")
    print(f"  {ALIAS_MAP_OUT.relative_to(ROOT)}")
    print(f"  {DROPPED_OUT.relative_to(ROOT)}")
    print(f"  {REVIEW_OUT.relative_to(ROOT)}")
    print(f"  {PROGRESS.relative_to(ROOT)} (moved {len(moved)} entries to dropped_during_dedupe)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
