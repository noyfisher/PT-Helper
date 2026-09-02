# Archived pipeline scripts

Everything in here either **ran once and is done** or was **superseded** by a script
that still lives at `scripts/`. These files are kept for provenance — to explain how
the current `output/` contents came to exist — not because anyone is expected to run
them again.

**Nothing here is maintained.** Several of these scripts target APIs we no longer use
(FLUX 2 Pro / BFL), read intermediate JSON files that no longer exist, or reference
counts and tiers from a specific cleanup sweep that has since concluded. Treat them as
a historical record. If you need the behaviour of one of them, port the idea into a
current script rather than reviving the file.

For the live pipeline, see [`../README.md`](../README.md).

## Broken imports (by design)

Python puts a script's *own* directory on `sys.path`, so sibling imports **inside** each
archive subfolder still resolve after the move. What no longer resolves is anything that
reached **up** into `scripts/`:

| File | Broken import | Notes |
|---|---|---|
| `one-off/retry_stuck_with_custom_prompts.py` | `qa_exercise_images` | lazy, inside a function |
| `one-off/retry_best_of_three.py` | `qa_exercise_images` | lazy |
| `one-off/pilot_nano_banana.py` | `qa_exercise_images` | lazy |
| `one-off/recover_api_error_qa.py` | `qa_exercise_images` | **module level** — fails on import |
| `one-off/migrate_aliases_to_firestore.py` | `fuzzy_match` | **module level** — fails on import |
| `one-off/seed_aliases_from_swift.py` | `fuzzy_match` | lazy |
| `superseded/regen_with_nano_banana.py` | `qa_exercise_images` | lazy |
| `superseded/fix_failing_images.py` | `generate_exercise_images` | lazy |
| `superseded/image_qa_agent.py` | `generate_exercise_images`, `qa_exercise_images` | **module level** — fails on import |

Still working, because both ends moved into the same folder:
`retry_best_of_three.py` → `retry_stuck_with_custom_prompts.py` (`one-off/`), and
`fix_failing_images.py` → `image_qa_agent.py` (`superseded/`).

Two more scripts *mention* an archived sibling in prose but never import it:
`_apply_medium_fixes.py` and `_apply_medium_end_fixes.py` say their pattern mirrors
`_apply_variant_fixes.py` / `_apply_end_frame_fixes.py`, and `review_alias_candidates.py`
tells the operator to run `dedupe_stockpile.py --consume-review` afterwards.

Also note: `one-off/seed_aliases_from_swift.py` still hardcodes the pre-rename path
`ios/PT-Helper/PT-Helper/Services/ExerciseImageService.swift`. The app folder is
`ios/PT-Helper/COIL/`. It was deliberately left unfixed — the script is a completed
one-time port, and correcting the path would imply it is meant to run again.

## `one-off/` — ran once, job done

| File | What it did |
|---|---|
| `_apply_variant_fixes.py` | Strengthened `pose_description` for the 12 HIGH-risk variant exercises that failed visual review, and seeded matching failure observations into the QA report so the auto-prompt loop had a real signal to correct from. |
| `_apply_medium_fixes.py` | Same treatment for the 7 MEDIUM-tier variant failures from review batches 1–5. |
| `_apply_medium2_fixes.py` | Same again for 3 further MEDIUM-tier failures found in batches 6–7. |
| `_apply_end_frame_fixes.py` | The end-frame counterpart of `_apply_variant_fixes.py`: rewrote `end_pose_description` for the 12 corrected variant exercises and seeded `consistency_report.json`. |
| `_apply_medium_end_fixes.py` | End-frame descriptions for the 7 corrected MEDIUM-tier exercises. |
| `_apply_medium2_end_fixes.py` | End-frame descriptions for fix run #2. |
| `apply_image_qa_fixes.py` | Idempotently patched three JSON files — metadata, `qa_all_starts_report.json`, and `consistency_report.json` — to force a regeneration pass for 11 named exercise slugs. Touched no images and called no API. |
| `retry_stuck_with_custom_prompts.py` | Retried the 27 exercises stuck below score 3 using hand-written per-exercise prompts with anti-cues and explicit camera angles. |
| `retry_best_of_three.py` | Generated each remaining stuck exercise three times, QA'd every candidate, and installed the best-scoring one. |
| `pilot_nano_banana.py` | The pilot that proved Nano Banana Pro beat FLUX: regenerated 6 score-1 FLUX failures and re-scored them on the same QA rubric. |
| `inpaint_end_frames.py` | Pilot end-frame generation via FLUX Fill inpainting over a hand-drawn mask. Abandoned once NB Pro proved it could rewrite a pose from a reference image without masks. |
| `generate_masks.py` | Built the MediaPipe Pose body masks that the inpainting pilot needed, plus red-overlay previews for eyeballing them. (Six leftover `*_mask*.png` files in `output/` come from here.) |
| `dedupe_stockpile.py` | Deduplicated the stockpile discovery list against the canonical catalog before the big generation run, using a sanity report and Jaccard-scored alias candidates. |
| `review_alias_candidates.py` | Local web UI for accepting/rejecting the alias candidates `dedupe_stockpile.py` flagged. |
| `merge_shuffle_discoveries.py` | Appended the successfully-generated shuffle-discovery exercises into the canonical metadata once their PNGs existed on disk. |
| `run_shuffle_image_gen.sh` | Chunked wrapper that drove `generate_missing_images.py` across the 143-exercise shuffle-discovery residual list. |
| `upload_stockpile_aliases.py` | Merged `stockpile_alias_map.json` into the Firestore `config/exerciseImageAliases` doc the app overlays at runtime. |
| `migrate_aliases_to_firestore.py` | The original one-time upload of the hardcoded Swift alias map to that same Firestore doc. |
| `seed_aliases_from_swift.py` | Extracted the Swift `aliasMap` (plus the `fuzzy_match.py` mirror), inverted it to canonical→aliases, and merged it into the canonical metadata. |
| `test_on_demand_generation.py` | Standalone HTTP smoke test for the `generateExerciseImage` Cloud Function, no simulator required. |
| `consolidate_metadata.py` | Folded `stockpile_progress.json` entries into `all_exercises_metadata.json` so scripts that forgot the runtime stockpile merge stopped silently missing ~30% of exercises. |
| `regen_from_visual_review.py` | Regenerated failures using human-written visual-review notes as the observation, covering the variant-compliance failures Gemini QA does not catch. |
| `install_regen_winners.py` | Promoted reviewed `*_regen.png` candidates over the live images, backing up what it replaced and updating the review log. |
| `recover_api_error_qa.py` | Re-scored images stuck at `API_ERROR` by calling Gemini without `response_schema`, working around the structured-output bug. |
| `qa_median_merge.py` | Merged three independent QA passes into a median-smoothed report to damp Gemini's ±1 score noise. |

## `superseded/` — replaced by a live script

| File | What it did | Replaced by |
|---|---|---|
| `regen_with_nano_banana.py` | First NB Pro regeneration pass: picked sub-threshold images, backed up the FLUX original, regenerated, re-QA'd. | `../regen_with_auto_prompts.py`, which feeds the prior QA observation back in to write a targeted anti-error prompt. |
| `review_server.py` | Web UI for reviewing start/end **pairs** and marking pass/fail/needs-regen. | `../review_starts_server.py` (start images, sorted worst-first) and `../qa_consistency.py` for pairs. |
| `generate_reference.py` | Generated the one-off FLUX "reference character" image that early exercise prompts were anchored to. | Nothing — NB Pro holds character consistency from the pose description and, for end frames, from the start image itself. |
| `fix_failing_images.py` | Claude-orchestrated fix loop: read the QA report, let an agent pick a retry strategy per failure. | `../triage_failures.py` + `../regen_with_auto_prompts.py`, which are deterministic and cheaper. |
| `image_qa_agent.py` | The Anthropic tool-use agent module `fix_failing_images.py` drove. Never run directly. | Same as above. |
| `build_unified_metadata.py` | Built the first `all_exercises_metadata.json` by merging the curated 190 with the stockpile's 717 discoveries. | Nothing — `all_exercises_metadata.json` is now the canonical source and is edited in place. |

## `pilots/`

| Directory | What it is |
|---|---|
| `animation-pilot/` | Paused pilot for animating exercises (FLUX end frames → Pika video → GIF). Self-contained: it keeps its own `README.md`, `requirements.txt`, `config.json`, and its own untracked `.env`. Start there, not here. |

Because that `.env` is untracked but required, its path is listed in the repo's
`.worktreeinclude` so it follows into new worktrees. Moving the pilot changed that path
to `scripts/archive/pilots/animation-pilot/.env`.
