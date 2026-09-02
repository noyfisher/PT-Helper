# Exercise Image Pipeline

Tooling that produces and maintains COIL's exercise illustration library: 1,364 canonical
exercises, each with a start frame and an end frame, generated with **Nano Banana Pro**
(`gemini-3-pro-image-preview`) and quality-scored with **Gemini 2.5 Flash** vision. The
pipeline's outputs are the PNGs in `output/` plus `output/exercise_image_mapping.json`,
which both the iOS app and the Cloud Functions catalog are built against. FLUX 2 Pro (BFL)
is the retired first-generation generator; two of its scripts stay only because live code
imports constants from them.

Scripts that ran once, or that a current script replaced, live in
[`archive/`](archive/README.md) and are not maintained.

```
output/all_exercises_metadata.json ──▶ generate_missing_images.py ──▶ output/<slug>.png
        (names + pose descriptions)     (Nano Banana Pro)                    │
                    ▲                            ▲                          ▼
                    │                            │              qa_exercise_images.py
        triage_failures.py          regen_with_auto_prompts.py     (Gemini 2.5 Flash)
        (rewrite bad descs)         (QA observation → anti-error            │
                    ▲                 prompt → regenerate)                  ▼
                    └──────────────────────────┴──── output/qa_all_starts_report.json

output/<slug>.png ──▶ generate_end_frames_nb.py ──▶ output/<slug>_end.png ──▶ qa_consistency.py

output/*.png ──▶ rebuild_image_mapping.py ──▶ output/exercise_image_mapping.json
                                                  ├─▶ ios/PT-Helper/COIL/Resources/ (copied)
                                                  └─▶ functions/src/generated/ (npm run build)
output/*.png ──▶ upload_to_firebase.sh ──▶ Firebase Storage  (this is how the app gets images)
```

## Script index

### Primary generation

| Script | Purpose |
|---|---|
| `generate_missing_images.py` | Generates start images for exercises that don't have one, with Nano Banana Pro, running QA inline and updating the report incrementally. The main entry point for new images. |
| `regen_with_auto_prompts.py` | The auto-prompt correction loop: feeds Gemini its own QA observation of what went wrong and has it write a targeted anti-cue prompt, then regenerates with NB Pro and re-scores. The fix for nearly every stuck image. |
| `triage_failures.py` | For images scoring below 3, asks Gemini whether the *image* is wrong, the *description* is wrong, or the pose is unrenderable — and rewrites the description in place when that's the fault. |
| `stockpile_exercise_images.py` | Discovery agent: generates rehab plans for hundreds of conditions via Claude, collects unique exercise names, finds gaps in the library, and batch-generates. Resumable; designed to run for hours. |
| `review_starts_server.py` | Local review UI for start images (`--port 5300`), sorted worst-score-first, showing the pose description beside the image and the QA observation. Live-reloads the report so you can review while a sweep runs. |

### QA

| Script | Purpose |
|---|---|
| `qa_exercise_images.py` | Single-image QA with Gemini 2.5 Flash vision: 9 defect checks plus a POSE_ACCURACY score of 1–5. Includes the no-schema fallback for Gemini's structured-output bug. |
| `qa_sweep_robust.py` | Serial whole-library QA sweep. One image at a time, per-image wall-clock timeout, report written after every image, skips what's already scored. Use this over `qa_exercise_images.py` for bulk runs. |
| `qa_consistency.py` | Pair QA: compares a start and end frame side by side for visual consistency (camera, character, clothing, equipment) and movement logic. Writes `output/consistency_report.json`. |

### End-frame pipeline

| Script | Purpose |
|---|---|
| `generate_end_descriptions.py` | Fills missing `end_pose_description` fields in the canonical metadata using Gemini 2.5 Flash, derived from the start description plus name, body position, and target area. |
| `generate_end_frames_nb.py` | Generates `<slug>_end.png` by conditioning NB Pro on the already-passing start PNG as a reference image, rewriting only the body posture. Resumable via `output/end_gen_progress.json`. |
| `regen_end_frames_with_corrections.py` | The auto-prompt correction loop applied to end frames that failed pair-consistency QA. Requires `output/consistency_report.json` from `qa_consistency.py`. |

### Mapping & sync

| Script | Purpose |
|---|---|
| `rebuild_image_mapping.py` | Rebuilds `output/exercise_image_mapping.json` from the PNGs actually on disk (one entry per start image), merging in metadata, then copies **the JSON only** to `ios/PT-Helper/COIL/Resources/`. It does **not** copy PNGs. Run after any generation batch. |
| `check_image_mapping_integrity.py` | Read-only CI check: every mapping key has a PNG, every start PNG has an entry, the iOS copy is byte-identical, aliases are unique, ≥95% of entries carry `body_position`. Exits 1 with a diff on any mismatch. |
| `upload_to_firebase.sh` | Uploads the PNGs to Firebase Storage. **This is the real deploy path for images** — the app downloads them at runtime. Needs `gcloud auth login`. |

### Legacy FLUX — kept as an import dependency

| Script | Purpose |
|---|---|
| `generate_exercise_images.py` | The original FLUX 2 Pro (BFL API) generator. Retired for new work, but `qa_exercise_images.py` and `process_missing_images.py` import constants from it, so it stays at top level. Also still the model behind the on-demand `generateExerciseImage` Cloud Function. |
| `process_missing_images.py` | Reads the `missingExerciseImages` Firestore collection, generates the gaps via FLUX, uploads, and updates mappings. Superseded in practice by the NB Pro path but not yet ported. |

### Knowledge graph v2

| Script | Purpose |
|---|---|
| `expand_knowledge_graph.py` | Asks Claude Haiku, for every (condition, exercise) pair in the seed lists, whether the exercise is safe, contraindicated, or unclear. Batched, prompt-cached, checkpointed. Writes `output/knowledge_graph_v2_draft.json`. |
| `review_kg_candidates.py` | Local review UI that walks a human through every `contraindicated` verdict plus a 10% sample of `safe` ones. A hard gate before anything ships. Saves to `output/kg_review_decisions.json`. |
| `merge_kg_review.py` | Applies the review decisions to the draft and writes the production `ios/PT-Helper/COIL/Resources/medical_knowledge_graph_v2.json`. Unreviewed verdicts are dropped. **Not yet run** — see status below. |
| `capture_kg_regression_goldens.py` | Replaces the hand-authored goldens in the analysis regression fixtures at `ios/PT-Helper/COILTests/GroundTruth/cases.json` with real Claude responses, so the fixtures detect model drift and not just validator changes. |

### Analysis / misc

| Script | Purpose |
|---|---|
| `audit_plan_exercise_frequency.py` | Ranks exercise names by how often they appear across rehab plans in Firestore. Drives which exercises earn named rules in `BiomechanicalRuleEngine`. |
| `calibrate_confidence.py` | Analysis pipeline for replacing the hardcoded 85% confidence cap with an empirically fitted one, once enough outcome ratings exist. Safe to run with zero data — it reports zero samples and exits. |
| `generate_brand_launch_assets.py` | Derives the dark/tinted app-icon variants and launch-screen logo from `AppIcon.png` via a chroma-key distance mask. |

### Shared

| Script | Purpose |
|---|---|
| `fuzzy_match.py` | Python port of the multi-layer exercise-name matching in `ExerciseImageService.swift` (exact → prefix → suffix → plural toggle → synonym expansion). Imported by the stockpile and FLUX-era scripts. |

`requirements.txt` covers all of the above: `pip install -r requirements.txt`.

## Data files

`output/` **is tracked in git** — deliberately. It holds the master illustrations, and
regenerating them costs real API quota, so they are versioned rather than rebuilt. It
currently contains **2,734 PNGs**: 1,364 start frames, 1,364 end frames, and 6 leftover
`*_mask*.png` files from the abandoned inpainting pilot.

What is *not* tracked (see the `scripts/output/` block in the repo `.gitignore`): `*.log`
at any depth, the `_*_backup/` and other `_*` iteration directories, progress checkpoints
(`output/end_gen_progress.json`, `output/end_desc_progress.json`), and `*.before_*.json` safety copies.
Those stay on your disk and never enter a commit.

| File | Role |
|---|---|
| `output/all_exercises_metadata.json` | **Canonical.** One entry per exercise: name, `normalized_filename`, category, target area, `body_position`, `pose_description`, `end_pose_description`, aliases. Everything generative reads this. |
| `output/exercise_image_mapping.json` | **Canonical, and a cross-system dependency — do not move or hand-edit.** `functions/scripts/build_catalog.ts` reads it on every Cloud Functions build, and a byte-identical copy is bundled at `ios/PT-Helper/COIL/Resources/exercise_image_mapping.json`. Regenerate it with `rebuild_image_mapping.py`. |
| `output/qa_all_starts_report.json` | **Canonical** QA report for start images. Latest sweep: 1,295 at score 5, 62 at 4, 9 at 3, one each at 2 and 1. |
| `output/consistency_report.json` | Pair QA results from `qa_consistency.py`; the input `regen_end_frames_with_corrections.py` corrects from. |
| `output/stockpile_progress.json` | The stockpile agent's resume checkpoint — but also a *secondary metadata source*: `rebuild_image_mapping.py`, `generate_missing_images.py`, `regen_with_auto_prompts.py`, and `triage_failures.py` all merge it at runtime. Don't delete it. |
| `output/curated_exercise_ids.txt` | 187 exercise ids used as the `--exercises-file` seed for `expand_knowledge_graph.py`. |
| `exercise_list.json` | The legacy curated 190-exercise list. Still read by `generate_exercise_images.py`, `qa_exercise_images.py`, `qa_consistency.py`, and `process_missing_images.py`, so it stays. Note that it contains three placeholder entries named "Exercise 1", "Exercise 2", and "Exercise 3", with no pose description — they generate nothing useful, so ignore them if you see them in output. |

## Adding a new exercise

1. **Add metadata.** Append an entry to `output/all_exercises_metadata.json` with at least
   `name`, `normalized_filename` (the slug, which becomes the PNG filename),
   `body_position`, `pose_description`, and `end_pose_description`.

2. **Generate the start frame.**
   ```bash
   python3 generate_missing_images.py --api-key "$GEMINI_KEY" --only "your-slug"
   ```
   QA runs inline and the report is updated as it goes.

3. **Fix failures.** If the pose scores below 4:
   ```bash
   python3 regen_with_auto_prompts.py --api-key "$GEMINI_KEY" --only "your-slug"
   ```
   If the *description* is the problem rather than the image, run `triage_failures.py`
   first — it rewrites descriptions in place.

4. **Generate the end frame**, then check the pair:
   ```bash
   python3 generate_end_frames_nb.py --api-key "$GEMINI_KEY" --only "your-slug"
   python3 qa_consistency.py --api-key "$GEMINI_KEY" --filter-name "your-slug"
   ```

5. **Rebuild and verify the mapping.**
   ```bash
   python3 rebuild_image_mapping.py
   python3 check_image_mapping_integrity.py
   ```

6. **Upload the images and regenerate the catalog.**
   ```bash
   ./upload_to_firebase.sh
   cd ../functions && npm run build
   ```

## Deploying

There are **no exercise PNGs in the app bundle** — `ios/PT-Helper/COIL/Resources/` holds
only fonts, the body model, and three JSON files. The app fetches every illustration from
Firebase Storage at runtime and caches it. So deploying images means two separate things:

- **The images** go to Firebase Storage via `./upload_to_firebase.sh`. Nothing is copied
  into the iOS project.
- **The mapping JSON** is what ships in the app and in the functions bundle.
  `rebuild_image_mapping.py` writes `output/exercise_image_mapping.json` and copies it to
  `ios/PT-Helper/COIL/Resources/`; `cd functions && npm run build` regenerates
  `src/generated/exerciseCatalog.ts` from the same file. Run
  `check_image_mapping_integrity.py` afterwards — it fails loudly if the two copies drift.

`ExerciseImageService.swift` resolves an exercise name to a filename through this mapping
using its own fuzzy-matching layers, mirrored in `fuzzy_match.py`.

## Quotas

Gemini free-tier quotas are per-model, so generation and QA don't compete:

- `gemini-3-pro-image-preview` — **~250 image generations/day**
- `gemini-2.5-flash` — **~1,500 QA calls/day**

The scripts insert no sleeps; they rely on the daily quota plus per-call SIGALRM timeouts
(60–90s). Fetch the key with
`cd ../functions && firebase functions:secrets:access GEMINI_API_KEY`.

## Troubleshooting

- **NB Pro misses a pose** — run `regen_with_auto_prompts.py`. Feeding the model its own
  failure observation is near-100% effective on anything fixable.
- **Gemini QA returns `None` or a blank result** — known structured-output bug when
  `response_schema` is set. `qa_exercise_images.py` already falls back to a schema-free
  call and normalizes the keys; just re-run the failed items.
- **A Gemini call hangs** — it happens; every script wraps calls in a SIGALRM timeout.
  Re-run and the checkpoint will pick up where it stopped.
- **`PROHIBITED_CONTENT` on an exercise image** — a false positive on fitness poses. Look
  at the image yourself; if it's fine, ignore the block.
- **QA passed but the image is wrong** — Gemini QA does **not** reliably validate variant
  compliance. Single-leg, single-arm, and alternating exercises routinely get hallucinated
  passing observations on visibly broken images. Review those by eye.
- **Scores moved without you changing anything** — Gemini QA is noisy by roughly ±1
  between runs. Don't chase a single-point drop.
- **Daily quota exhausted** — resume tomorrow; every long-running script is checkpointed.

## Knowledge graph v2 status

Paused mid-review. `expand_knowledge_graph.py` produced the draft, and
`output/kg_review_decisions.json` holds **1,238 of 1,582** decisions.
`merge_kg_review.py` has never been run, so `ios/PT-Helper/COIL/Resources/medical_knowledge_graph_v2.json` does not exist, and the `knowledgeGraphV2Enabled` flag in `KnowledgeGraphService.swift`
is still off. The app runs on v1 alone. Full context in
[`PR-C-2-handoff.md`](PR-C-2-handoff.md).
