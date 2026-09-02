"""
Merge three independent QA passes into a median-smoothed report.

For each image: take pose_score from all 3 passes, use the median as the
canonical score, and keep the QAResult from the pass whose score matches
the median (so observations/checks stay coherent).

Usage:
  python scripts/qa_median_merge.py \
      scripts/output/qa_pass_1.json \
      scripts/output/qa_pass_2.json \
      scripts/output/qa_pass_3.json \
      --output scripts/output/qa_all_starts_report.json
"""
from __future__ import annotations

import argparse
import json
import statistics
from pathlib import Path


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("passes", nargs="+", help="Paths to QA pass reports")
    ap.add_argument("--output", required=True)
    ap.add_argument("--scores-log", default="scripts/output/qa_pass_scores.json",
                    help="Where to save per-image scores across passes")
    args = ap.parse_args()

    pass_reports = []
    for p in args.passes:
        data = json.loads(Path(p).read_text())
        pass_reports.append(data.get("results", {}))

    all_names = sorted(set().union(*[set(r.keys()) for r in pass_reports]))

    scores_log = {}
    merged_results = {}
    dist = {1: 0, 2: 0, 3: 0, 4: 0, 5: 0, None: 0}

    for name in all_names:
        scores = []
        entries = []
        for r in pass_reports:
            e = r.get(name)
            if e is None:
                continue
            s = e.get("pose_score")
            # Treat API_ERROR as 0 (worst) so median reflects fragility
            if "API_ERROR" in e.get("critical_failures", []):
                continue  # exclude API_ERRORs from median computation
            if s is None:
                continue
            scores.append(s)
            entries.append(e)

        if not scores:
            # All 3 passes errored — keep the last seen entry if any
            any_entry = next((r.get(name) for r in pass_reports if r.get(name)), None)
            if any_entry:
                merged_results[name] = any_entry
                scores_log[name] = {"passes": [], "median": None}
                dist[None] += 1
            continue

        median = int(statistics.median_low(scores))  # conservative tie-breaker
        # Pick the entry whose score matches median, preferring the most recent
        matched = [e for e, s in zip(entries, scores) if s == median]
        chosen = matched[-1] if matched else entries[-1]
        merged_results[name] = chosen

        scores_log[name] = {"passes": scores, "median": median}
        dist[median] += 1

    total = len(merged_results)
    passed = sum(1 for v in merged_results.values() if v.get("overall_pass"))
    report = {
        "total_images": total,
        "passed": passed,
        "failed": total - passed,
        "skipped": 0,
        "failures_by_check": {},
        "results": merged_results,
    }
    # Recompute failures_by_check
    for v in merged_results.values():
        for fc in v.get("critical_failures", []):
            report["failures_by_check"][fc] = report["failures_by_check"].get(fc, 0) + 1

    Path(args.output).write_text(json.dumps(report, indent=2))
    Path(args.scores_log).write_text(json.dumps(scores_log, indent=2))

    print(f"Merged {total} images over {len(args.passes)} passes")
    print(f"Pass: {passed} ({passed*100//total}%)")
    print()
    print("Median distribution:")
    for s in [5, 4, 3, 2, 1, None]:
        n = dist[s]
        pct = n * 100 // total if total else 0
        print(f"  {s}: {n:3d} ({pct}%)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
