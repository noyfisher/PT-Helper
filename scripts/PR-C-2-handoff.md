# Tier 2 PR C-2 — Knowledge Graph v2 Data Pipeline (handoff)

> **STATUS (2026-09-02):** This work is paused, not finished. The PT review
> stalled at **1,238 of 1,582** decisions in `scripts/output/kg_review_decisions.json`;
> `merge_kg_review.py` has never been run, so
> `ios/PT-Helper/COIL/Resources/medical_knowledge_graph_v2.json` does not exist and
> the `knowledgeGraphV2Enabled` flag in `KnowledgeGraphService.swift` is still off —
> the app runs on v1 alone. The three scripts this document describes
> (`expand_knowledge_graph.py`, `review_kg_candidates.py`, `merge_kg_review.py`) are
> live and unchanged at `scripts/`; everything below still applies once the review
> resumes.

## State

PR C-1 shipped the **infrastructure** (gen script, review tool, iOS-side v2
loader, in-app v1+v2 merge, feature flag — all default OFF and runtime no-op
until v2 data ships). PR C-2 is the **data pipeline**: actually generate
verdicts, walk the PT review queue, merge, then flip the flag.

Of PR C-2's four sub-steps:

| Step | Status | Owner | What's blocking |
|---|---|---|---|
| 1. Generate v2 draft | ✅ kicked off this session | Claude (background) | ~30-60 min runtime, ~$6.42 Anthropic spend |
| 2. PT clinician review | ⛔ NEEDS HUMAN | You + a clinician | Review tool is built; needs ~2-3 hrs of focused review time |
| 3. Merge reviewed verdicts | ✅ already built (`scripts/merge_kg_review.py`) | One-line invocation | Step 2 must complete first |
| 4. Flip feature-flag default to ON | ✅ trivial | One-line code edit | Step 3 must produce a valid `medical_knowledge_graph_v2.json` |

This document is the cookbook for steps 2-4.

## Generation params used (Step 1, **complete**)

```bash
ANTHROPIC_API_KEY=$(firebase functions:secrets:access ANTHROPIC_API_KEY --project pt-helper-dev) \
    python3 scripts/expand_knowledge_graph.py \
    --exercises-file scripts/output/curated_exercise_ids.txt
```

- **Conditions**: 25 (from v1 KG seed list)
- **Exercises**: 187 curated, after stripping 3 placeholder entries
  (`exercise-1/2/3`) that exist as test data in `scripts/exercise_list.json`
  (indices 181-183). See "Followup" section below.
- **Pairs**: 25 × 187 = 4,675 verdicts (originally 4,750, 75 placeholders dropped)
- **Actual cost**: $6.42 estimated; actual cost will appear in Anthropic billing
- **Wall-clock time**: 2,432 seconds (~40.5 min)
- **Failures**: 0 pairs failed (all 4,750 originally generated returned valid JSON)
- **Verdict distribution**:
  - safe: 3,437 (73.5%)
  - unclear: 807 (17.3%)
  - contraindicated: 431 (9.2%) — 423 relative + 8 absolute
- **Output files**:
  - `scripts/output/knowledge_graph_v2_draft.json` — every verdict (1.3 MB)
  - `scripts/output/kg_failed_pairs.json` — empty `[]`, no failures
  - `scripts/output/kg_progress.json` — resumable checkpoint (1.5 MB)
- **Resume**: if you ever re-run, use `--resume` to skip already-done pairs
- **Background log**: `/tmp/kg_v2_gen.log` (full successful run captured)

If the run failed, check `/tmp/kg_v2_gen.log` for errors. Common failure modes (per the script's own resilience layers):

- `RATE LIMIT / OVERLOAD` — auto-backoff [5s, 15s, 45s] up to 3 attempts
- `TIMEOUT` — SIGALRM 90s per call, retried per backoff
- `PROHIBITED_CONTENT` — raised immediately (won't succeed on retry); pair lands in `kg_failed_pairs.json`
- Partial-array recovery: if Haiku truncates mid-batch, valid `{ … }` chunks are kept; broken one logged as failed

## Step 2 — PT clinician review (HUMAN BOTTLENECK)

```bash
python3 scripts/review_kg_candidates.py
# Visit http://localhost:5302
```

The review queue surfaces:
- **All `contraindicated` verdicts** — high-stakes; a wrong call ships dangerous guidance
- **All `unclear` verdicts** — Claude itself punted, needs a human call
- **A 10% deterministic sample of `safe` verdicts** — sanity check (the other 90% ship as-is)

For each card:
- **A** = Approve (keep verdict as-is)
- **R** = Reject (drop the pair entirely — won't appear in v2 output)
- **F** = Flip (safe ↔ contraindicated)
- **E** = Edit reason (overrides Claude's reason in the merged output)
- ← / → arrow keys to navigate

Decisions save live (POST per click) to `scripts/output/kg_review_decisions.json`.
Resume-friendly — re-launch picks up where you left off.

**Actual queue size after generation**: **1,582 cards**
- 431 contraindicated (every one)
- 807 unclear (every one)
- 344 safe samples (10% of 3,437)

At 5-10s per card (most are obvious to a clinician), that's **2-4 hrs** of
focused review time. Recommend splitting across two sessions.

**Recruit a real PT for this**. The whole point of PR C-2 is replacing AI
guesses with clinical judgment on the high-stakes calls. If you have to do it
yourself, at minimum cross-reference each contraindicated verdict against
[ChoosePT.com](https://www.choosept.com/) clinical practice guidelines before
approving.

## Step 3 — Merge

```bash
python3 scripts/merge_kg_review.py
```

The script:
- Reads `scripts/output/knowledge_graph_v2_draft.json` + `kg_review_decisions.json`
- Refuses to ship if any contraindicated/unclear verdict is still PENDING
  (override with `--allow-pending` only if you accept the risk)
- Applies decisions: APPROVE keeps, REJECT drops, FLIP inverts, EDIT overrides reason
- Outputs `ios/PT-Helper/COIL/Resources/medical_knowledge_graph_v2.json`

Note: **the v2 file contains only the NEW pairs** — the in-app
`KnowledgeGraphService.merge(v1:v2:)` unions v1 + v2 at runtime. So v1's expert
curation is preserved as-is and v2 only ADDS coverage.

To preview what would be written without committing changes:
```bash
python3 scripts/merge_kg_review.py --dry-run
```

## Step 4 — Flip the feature flag default

After Step 3 produces a clean `medical_knowledge_graph_v2.json` and the iOS
build picks it up (Xcode auto-syncs new resources via
`PBXFileSystemSynchronizedRootGroup`), enable v2 by default:

```swift
// ios/PT-Helper/COIL/Services/KnowledgeGraphService.swift
enum KnowledgeGraphFeatureFlag {
    static let key = "knowledgeGraphV2Enabled"
    static var isEnabled: Bool {
        // Was: UserDefaults.standard.bool(forKey: key)  // defaults to false
        // Now: default-on when key absent
        UserDefaults.standard.object(forKey: key) as? Bool ?? true
    }
}
```

Then run the existing `KnowledgeGraphExpansionTests` to confirm the merged
graph still satisfies all v1 invariants:

```bash
xcodebuild test \
    -project ios/PT-Helper/COIL.xcodeproj \
    -scheme COIL \
    -destination 'platform=iOS Simulator,name=iPhone 16' \
    -only-testing:COILTests/KnowledgeGraphExpansionTests
```

Should report 13/13 green.

## Verification gates

Before shipping the flag flip:

1. `merge_kg_review.py` exit code 0 (no PENDING contraindicated/unclear left)
2. `medical_knowledge_graph_v2.json` parses as valid `KnowledgeGraph` JSON
   (decode test in step 4)
3. `KnowledgeGraphExpansionTests`: 13/13 pass
4. `SmokePlan`: 11/11 pass (sanity check — no v2 regression in unrelated paths)
5. Manual smoke: build + open `RehabPlanView` for a user with osteoporosis;
   confirm any newly contraindicated v2 pair surfaces a `.serious` warning
   via `SeriousWarningModal`

## Rollback

If v2 ships and causes any false-positive `.serious` modals or analysis
regressions:

1. Revert the one-line flag flip from Step 4 (PR-revert is fine; the v2 JSON
   stays bundled but unused).
2. Optionally delete `medical_knowledge_graph_v2.json` to remove from the
   bundle entirely.
3. The in-app fallback to v1-only is byte-identical to pre-PR-C behavior.

## Cost & time accounting (final)

- Generation: $6.42 + 40.5 min wall clock (DONE)
- Review: 1,582 cards × ~5-10s = ~2-4 hrs of clinician time (the real bottleneck)
- Merge + flag flip: ~5 min
- Total: 1 day end-to-end if review happens same-day; >1 wk if waiting on a
  scheduled clinician slot

## Followup (out of PR C-2 scope)

`scripts/exercise_list.json` indices 181-183 contain three placeholder entries
named "Exercise 1", "Exercise 2", "Exercise 3" with matching
`normalized_filename: exercise-N`. These appear to be leftover test data from
some earlier import. They were stripped from the v2 generation seed (and from
the draft) but they still exist in the source list — they'll silently rejoin
any future seed generation. Worth a one-off cleanup commit to delete those
three entries from `scripts/exercise_list.json`.
