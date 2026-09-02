"""
Recover QA scores for images that hit API_ERROR with structured output.

Calls Gemini WITHOUT response_schema (workaround for a bug where the
constrained schema returns None), parses the JSON response text, and
coerces into the QAResult shape expected by the rest of the tooling.

Updates qa_all_starts_report.json in place.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

from google import genai
from PIL import Image

SCRIPT_DIR = Path(__file__).resolve().parent
OUTPUT_DIR = SCRIPT_DIR / "output"
METADATA = OUTPUT_DIR / "all_exercises_metadata.json"
STOCKPILE = OUTPUT_DIR / "stockpile_progress.json"
QA_REPORT = OUTPUT_DIR / "qa_all_starts_report.json"

sys.path.insert(0, str(SCRIPT_DIR))
from qa_exercise_images import build_qa_prompt, QAResult  # noqa


def qa_without_schema(client: genai.Client, img_path: Path, ex: dict) -> dict | None:
    img = Image.open(img_path)
    prompt = build_qa_prompt(ex) + (
        "\n\nRespond with ONLY a single JSON object (no markdown code fences). "
        "The JSON must have these top-level keys: exercise_name, filename, "
        "anatomy, subject, full_body, clothing, background, no_text, art_style, "
        "body_orientation, pose_accuracy, pose_score, overall_pass, critical_failures. "
        "Each check field except pose_score/overall_pass/critical_failures must be "
        'an object with shape {"observation": "...", "passed": true|false}. '
        "pose_score must be an integer 1-5. critical_failures must be a list of "
        "strings naming any failed checks."
    )
    resp = client.models.generate_content(
        model="gemini-2.5-flash",
        contents=[img, prompt],
    )
    text = resp.text
    if not text:
        return None
    # Strip markdown code fences if present
    m = re.search(r"```(?:json)?\s*(\{.*\})\s*```", text, re.DOTALL)
    if m:
        text = m.group(1)
    else:
        # Find first {...} block
        m = re.search(r"\{.*\}", text, re.DOTALL)
        if m:
            text = m.group(0)
    try:
        data = json.loads(text)
    except json.JSONDecodeError as e:
        print(f"    JSON parse error: {e}. Raw: {text[:200]}")
        return None
    try:
        # Coerce into QAResult (validates shape, fills defaults)
        result = QAResult.model_validate(data)
    except Exception as e:
        print(f"    Schema validation error: {e}")
        return None
    result.exercise_name = ex["name"]
    result.filename = f"{ex['normalized_filename']}.png"
    # Recompute overall_pass from the individual checks
    checks = {
        "ANATOMY": result.anatomy,
        "SUBJECT": result.subject,
        "FULL_BODY": result.full_body,
        "CLOTHING": result.clothing,
        "BACKGROUND": result.background,
        "NO_TEXT": result.no_text,
        "ART_STYLE": result.art_style,
        "BODY_ORIENTATION": result.body_orientation,
        "POSE_ACCURACY": result.pose_accuracy,
    }
    failures = [n for n, c in checks.items() if not c.passed]
    if result.pose_score <= 1 and "POSE_ACCURACY" not in failures:
        failures.append("POSE_ACCURACY")
    result.critical_failures = failures
    result.overall_pass = len(failures) == 0
    return json.loads(result.model_dump_json())


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--api-key", required=True)
    ap.add_argument("--only", help="Comma-separated; defaults to all API_ERROR rows")
    args = ap.parse_args()

    report = json.loads(QA_REPORT.read_text())
    meta = {e["normalized_filename"]: e
            for e in json.loads(METADATA.read_text())["exercises"]}
    if STOCKPILE.exists():
        stock = json.loads(STOCKPILE.read_text())
        for k, e in stock.get("all_exercises", {}).items():
            img_name = e.get("imageFileName") or k
            if img_name not in meta:
                meta[img_name] = {
                    "normalized_filename": img_name,
                    "name": e.get("name", img_name.replace("-", " ").title()),
                    "category": e.get("category", ""),
                    "target_area": e.get("targetArea", ""),
                    "body_position": e.get("bodyPosition", ""),
                    "pose_description": e.get("startPoseDescription", ""),
                }

    if args.only:
        names = [n.strip() for n in args.only.split(",") if n.strip()]
    else:
        names = sorted(n for n, v in report["results"].items()
                       if "API_ERROR" in v.get("critical_failures", []))

    client = genai.Client(api_key=args.api_key)

    fixed = failed = 0
    for idx, name in enumerate(names, 1):
        ex = meta.get(name)
        if not ex:
            print(f"[{idx}/{len(names)}] {name}: no metadata")
            failed += 1
            continue
        img_path = OUTPUT_DIR / f"{name}.png"
        if not img_path.exists():
            print(f"[{idx}/{len(names)}] {name}: missing image")
            failed += 1
            continue

        print(f"[{idx}/{len(names)}] {name} ...", end="", flush=True)
        qa = qa_without_schema(client, img_path, ex)
        if qa is None:
            print(" FAIL")
            failed += 1
            continue

        report["results"][name] = qa
        fixed += 1
        print(f" score={qa.get('pose_score')}/5  pass={qa.get('overall_pass')}")

    # Recompute aggregate counts
    total = len(report["results"])
    passed = sum(1 for v in report["results"].values() if v.get("overall_pass"))
    report["total_images"] = total
    report["passed"] = passed
    report["failed"] = total - passed
    QA_REPORT.write_text(json.dumps(report, indent=2))

    print(f"\nFixed: {fixed}   Failed: {failed}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
