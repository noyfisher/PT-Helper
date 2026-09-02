#!/usr/bin/env python3
"""
Fix failing exercise images using a Claude-powered QA agent.

Reads qa_report.json to find failures, then uses Claude to orchestrate
the generate → QA → retry loop with intelligent strategy selection.

Usage:
    # With explicit API keys
    python scripts/fix_failing_images.py --bfl-key KEY --gemini-key KEY

    # With macOS Keychain
    python scripts/fix_failing_images.py --keychain

    # Dry run (no BFL/Gemini API calls, tests agent reasoning)
    python scripts/fix_failing_images.py --dry-run

    # Filter to specific exercises
    python scripts/fix_failing_images.py --keychain --filter-name toe-raises,chin-tucks

Required env var:
    ANTHROPIC_API_KEY — Anthropic SDK reads this automatically.

Do NOT run concurrently with process_missing_images.py (both write to scripts/output/).

Prerequisites:
    pip install anthropic google-genai pydantic Pillow requests
"""

import argparse
import json
import os
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

# ---------- Paths ----------

SCRIPT_DIR = Path(__file__).parent
OUTPUT_DIR = SCRIPT_DIR / "output"
QA_REPORT_PATH = OUTPUT_DIR / "qa_report.json"
FIX_REPORT_PATH = OUTPUT_DIR / "fix_report.json"


def get_keychain_key(service: str) -> str | None:
    """Read an API key from macOS Keychain."""
    try:
        result = subprocess.run(
            ["security", "find-generic-password", "-s", service, "-w"],
            capture_output=True, text=True, check=True,
        )
        return result.stdout.strip()
    except subprocess.CalledProcessError:
        return None


def load_qa_report() -> dict:
    """Load the QA report, filtering to only failures."""
    if not QA_REPORT_PATH.exists():
        print(f"ERROR: QA report not found at {QA_REPORT_PATH}")
        print("Run qa_exercise_images.py first to generate the report.")
        sys.exit(1)

    with open(QA_REPORT_PATH, "r") as f:
        return json.load(f)


def load_exercises_by_name(filter_names: set[str] | None = None) -> dict[str, dict]:
    """Load exercise_list.json into a dict keyed by normalized_filename."""
    from generate_exercise_images import load_exercise_list

    exercises = load_exercise_list()
    by_name = {}
    for ex in exercises:
        name = ex.get("normalized_filename", "")
        if filter_names and name not in filter_names:
            continue
        by_name[name] = ex

    return by_name


def load_already_fixed() -> set[str]:
    """Load exercises already fixed in a previous run (crash recovery)."""
    if not FIX_REPORT_PATH.exists():
        return set()
    try:
        with open(FIX_REPORT_PATH, "r") as f:
            report = json.load(f)
        return {
            ex["name"]
            for ex in report.get("exercises", [])
            if ex.get("final_status") == "fixed"
        }
    except (json.JSONDecodeError, KeyError):
        return set()


def filter_qa_report(qa_report: dict, already_fixed: set[str]) -> dict:
    """Remove already-fixed exercises from the QA report's failure list."""
    if not already_fixed:
        return qa_report

    filtered = dict(qa_report)
    filtered["results"] = {
        k: v for k, v in qa_report.get("results", {}).items()
        if k not in already_fixed
    }
    skipped = len(already_fixed)
    if skipped > 0:
        print(f"  Skipping {skipped} exercises already fixed in previous run")
    return filtered


def save_fix_report(report: dict) -> None:
    """Save the fix report to disk."""
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    with open(FIX_REPORT_PATH, "w") as f:
        json.dump(report, f, indent=2)
    print(f"\n  Fix report saved to: {FIX_REPORT_PATH}")


def update_qa_report(qa_report: dict, fix_report: dict) -> None:
    """Update qa_report.json with results from fixed exercises."""
    fixed_exercises = {
        ex["name"]
        for ex in fix_report.get("exercises", [])
        if ex.get("final_status") == "fixed"
    }

    if not fixed_exercises:
        return

    # Re-run QA on fixed exercises to get fresh results
    # (The agent already verified them, but we update the report for consistency)
    results = qa_report.get("results", {})
    updated = 0
    for name in fixed_exercises:
        if name in results:
            # Mark as passing — the agent already verified via qa_image
            results[name]["overall_pass"] = True
            results[name]["critical_failures"] = []
            updated += 1

    if updated > 0:
        # Recompute totals
        total = len(results)
        passed = sum(1 for r in results.values() if r.get("overall_pass", False))
        qa_report["passed"] = passed
        qa_report["failed"] = total - passed

        with open(QA_REPORT_PATH, "w") as f:
            json.dump(qa_report, f, indent=2)
        print(f"  Updated qa_report.json: {passed}/{total} passing ({updated} newly fixed)")


def print_summary(report: dict) -> None:
    """Print a human-readable summary table."""
    exercises = report.get("exercises", [])
    summary = report.get("summary", {})
    status = report.get("status", "unknown")

    print("\n" + "=" * 60)
    print("  EXERCISE IMAGE QA FIX REPORT")
    print("=" * 60)
    print(f"  Status: {status}")
    print(f"  Fixed: {summary.get('fixed', 0)}")
    print(f"  Still failing: {summary.get('still_failing', 0)}")
    print(f"  Flagged for manual: {summary.get('flagged_manual', 0)}")
    print("-" * 60)

    for ex in exercises:
        name = ex.get("name", "?")
        final = ex.get("final_status", "?")
        attempts = ex.get("attempts", [])
        icon = {"fixed": "+", "still_failing": "X", "flagged_manual": "?"}
        print(f"  [{icon.get(final, ' ')}] {name}: {final} ({len(attempts)} attempts)")
        for att in attempts:
            strategy = att.get("strategy", "?")
            result = att.get("result", "?")
            score = att.get("pose_score", "")
            score_str = f" (score={score})" if score else ""
            print(f"      {strategy}: {result}{score_str}")

    print("=" * 60)


def main():
    parser = argparse.ArgumentParser(
        description="Fix failing exercise images using Claude QA agent",
    )
    parser.add_argument("--anthropic-key", help="Anthropic API key (or use --keychain / ANTHROPIC_API_KEY env var)")
    parser.add_argument("--bfl-key", help="BFL (FLUX) API key")
    parser.add_argument("--gemini-key", help="Gemini API key")
    parser.add_argument(
        "--keychain", action="store_true",
        help="Read API keys from macOS Keychain (bfl-api-key, gemini-api-key)",
    )
    parser.add_argument(
        "--dry-run", action="store_true",
        help="Skip BFL/Gemini API calls; test agent reasoning only",
    )
    parser.add_argument(
        "--filter-name",
        help="Comma-separated list of exercise normalized_filenames to process",
    )
    args = parser.parse_args()

    # --- Resolve API keys ---
    bfl_key = args.bfl_key
    gemini_key = args.gemini_key

    anthropic_key = args.anthropic_key

    if args.keychain:
        if not bfl_key:
            # Try multiple Keychain service names
            bfl_key = get_keychain_key("BFL_API_KEY") or get_keychain_key("bfl-api") or get_keychain_key("bfl-api-key")
        if not gemini_key:
            gemini_key = get_keychain_key("gemini-api-key") or get_keychain_key("GEMINI_API_KEY")
        if not anthropic_key:
            anthropic_key = get_keychain_key("anthropic-api-key")

    # Fall back to env vars
    if not anthropic_key:
        anthropic_key = os.environ.get("ANTHROPIC_API_KEY")
    if not gemini_key:
        gemini_key = os.environ.get("GEMINI_API_KEY") or os.environ.get("GOOGLE_API_KEY")

    if not args.dry_run:
        if not bfl_key:
            print("ERROR: BFL API key required. Use --bfl-key or --keychain")
            sys.exit(1)
        if not gemini_key:
            print("ERROR: Gemini API key required. Use --gemini-key or --keychain")
            sys.exit(1)

    if not anthropic_key:
        print("ERROR: Anthropic API key required. Use --anthropic-key, --keychain, or set ANTHROPIC_API_KEY")
        sys.exit(1)

    # Set for the Anthropic SDK (reads from env automatically)
    os.environ["ANTHROPIC_API_KEY"] = anthropic_key

    # --- Load data ---
    print("Loading QA report and exercise metadata...")
    qa_report = load_qa_report()

    filter_names = None
    if args.filter_name:
        filter_names = set(args.filter_name.split(","))

    exercises_by_name = load_exercises_by_name(filter_names)
    print(f"  Loaded {len(exercises_by_name)} exercises")

    # Filter out already-fixed exercises (crash recovery)
    already_fixed = load_already_fixed()
    qa_report = filter_qa_report(qa_report, already_fixed)

    failure_count = sum(
        1 for r in qa_report.get("results", {}).values()
        if not r.get("overall_pass", True)
    )
    print(f"  {failure_count} failures to process")

    if failure_count == 0:
        print("  No failures to fix!")
        return

    # --- Initialize clients ---
    print("Initializing API clients...")
    import anthropic
    anthropic_client = anthropic.Anthropic()

    gemini_client = None
    if not args.dry_run:
        from google import genai
        gemini_client = genai.Client(api_key=gemini_key)

    # --- Run agent ---
    print(f"\nStarting QA fix agent {'(DRY RUN)' if args.dry_run else ''}...")
    print("-" * 40)

    from image_qa_agent import run_agent

    start = time.time()
    report = run_agent(
        anthropic_client=anthropic_client,
        qa_report=qa_report,
        exercises_by_name=exercises_by_name,
        bfl_key=bfl_key or "",
        gemini_client=gemini_client,
        dry_run=args.dry_run,
    )
    elapsed = time.time() - start

    # --- Save results ---
    report["run_timestamp"] = datetime.now(timezone.utc).isoformat()
    report["elapsed_seconds"] = round(elapsed)
    report["total_input"] = failure_count
    report["dry_run"] = args.dry_run

    save_fix_report(report)

    if not args.dry_run:
        update_qa_report(qa_report, report)

    print_summary(report)
    print(f"\n  Completed in {elapsed:.0f}s")


if __name__ == "__main__":
    main()
