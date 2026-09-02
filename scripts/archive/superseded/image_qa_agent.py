#!/usr/bin/env python3
"""
Claude-powered agent for fixing failing exercise images.

Uses Anthropic SDK tool-use pattern: Claude reasons about which strategy to try,
calls tools to generate/QA images, and produces a structured fix report.

This module is imported by fix_failing_images.py — not run directly.
"""

import json
import time
from pathlib import Path

import anthropic

# Import from existing scripts (no modifications needed)
from generate_exercise_images import (
    _CUSTOM_VISUAL_PROMPTS,
    generate_image,
    save_image,
)
from qa_exercise_images import analyze_image

# ---------- Constants ----------

SCRIPT_DIR = Path(__file__).parent
OUTPUT_DIR = SCRIPT_DIR / "output"

AGENT_MODEL = "claude-sonnet-4-6"
AGENT_MAX_TOKENS = 4096
AGENT_TIMEOUT_S = 60 * 60  # 60 minutes total
TOOL_TIMEOUT_S = 5 * 60  # 5 minutes per tool call

# ---------- Tool schemas (Anthropic tool-use format) ----------

TOOLS = [
    {
        "name": "read_qa_failures",
        "description": (
            "Read the current QA report and return all failing exercises with their "
            "failure details, pose scores, body positions, and whether a custom visual "
            "prompt override exists. Call this first to understand what needs fixing."
        ),
        "input_schema": {
            "type": "object",
            "properties": {},
            "required": [],
        },
    },
    {
        "name": "generate_image",
        "description": (
            "Generate an exercise image using BFL FLUX API. Takes 30-90 seconds "
            "(BFL polling). The image is saved to scripts/output/{exercise_name}.png. "
            "Use seed_offset to get a different result for the same exercise. "
            "Use model='flux2-pro' as an alternative if kontext-pro fails."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "exercise_name": {
                    "type": "string",
                    "description": "Normalized filename of the exercise (e.g., 'toe-raises')",
                },
                "seed_offset": {
                    "type": "integer",
                    "description": "Added to deterministic seed for different results. Default 0. Try 1000, 2000 for retries.",
                    "default": 0,
                },
                "model": {
                    "type": "string",
                    "enum": ["kontext-pro", "flux2-pro"],
                    "description": "FLUX model to use. kontext-pro is default, flux2-pro uses structured JSON prompts.",
                    "default": "kontext-pro",
                },
            },
            "required": ["exercise_name"],
        },
    },
    {
        "name": "qa_image",
        "description": (
            "Run Gemini vision QA on an exercise image. Returns all 9 QA checks "
            "(anatomy, subject, full_body, clothing, background, no_text, art_style, "
            "body_orientation, pose_accuracy), pose_score (1-5), overall_pass, and "
            "critical_failures list. An image passes if all checks pass AND pose_score > 1."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "exercise_name": {
                    "type": "string",
                    "description": "Normalized filename of the exercise to QA",
                },
            },
            "required": ["exercise_name"],
        },
    },
    {
        "name": "check_custom_prompt",
        "description": (
            "Check if an exercise has a custom visual prompt override in the generation "
            "script. Custom prompts are hand-written descriptions for exercises that FLUX "
            "frequently misinterprets. If a custom prompt exists and the image still fails, "
            "seed changes or model switches are the remaining levers."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "exercise_name": {
                    "type": "string",
                    "description": "Normalized filename of the exercise",
                },
            },
            "required": ["exercise_name"],
        },
    },
    {
        "name": "submit_fix_report",
        "description": (
            "Submit the final fix report when all exercises have been processed. "
            "This terminates the agent loop. Call this after processing all failures."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "exercises": {
                    "type": "array",
                    "items": {
                        "type": "object",
                        "properties": {
                            "name": {"type": "string"},
                            "original_failure": {"type": "string"},
                            "attempts": {
                                "type": "array",
                                "items": {
                                    "type": "object",
                                    "properties": {
                                        "strategy": {"type": "string"},
                                        "model": {"type": "string"},
                                        "result": {"type": "string", "enum": ["PASS", "FAIL"]},
                                        "pose_score": {"type": "integer"},
                                    },
                                    "required": ["strategy", "result"],
                                },
                            },
                            "final_status": {
                                "type": "string",
                                "enum": ["fixed", "still_failing", "flagged_manual"],
                            },
                        },
                        "required": ["name", "original_failure", "attempts", "final_status"],
                    },
                },
                "summary": {
                    "type": "object",
                    "properties": {
                        "fixed": {"type": "integer"},
                        "still_failing": {"type": "integer"},
                        "flagged_manual": {"type": "integer"},
                    },
                    "required": ["fixed", "still_failing", "flagged_manual"],
                },
            },
            "required": ["exercises", "summary"],
        },
    },
]

# ---------- System prompt ----------

SYSTEM_PROMPT = """You are an exercise image QA fix agent for the PT Helper physical therapy app.

You receive a batch of failing exercise images and must fix each one by choosing the right regeneration strategy.

## Your Workflow
1. Call read_qa_failures to get all current failures
2. Process API_ERROR failures first (likely just transient — re-generate with same params)
3. Then process POSE_ACCURACY failures using the escalation strategy below
4. After processing all exercises, call submit_fix_report with your results

## Strategy Escalation (for POSE_ACCURACY failures)
For each failing exercise, try strategies in this order (up to 3 total attempts):

1. **Re-QA only** — If pose_score was 2 (borderline), just re-run qa_image. Gemini has variance and it might pass this time.
2. **Seed offset** — Generate with seed_offset=1000, then QA. If still failing, try seed_offset=2000.
3. **Model switch** — Generate with model="flux2-pro" (structured JSON prompts, sometimes better for complex poses).
4. **Flag for manual** — After 3 failed attempts, mark as flagged_manual and move on.

## Important Rules
- ONLY use exercise names that appear in the read_qa_failures output. Never guess or invent exercise names.
- After each generate_image call, ALWAYS call qa_image to verify the result.
- Process exercises in batches by failure type: all API_ERROR first, then POSE_ACCURACY.
- If an exercise has a custom visual prompt (check via check_custom_prompt), seed offsets may be less effective — consider model switch earlier.
- When you've processed ALL exercises, call submit_fix_report immediately.

## Context
- FLUX Kontext Pro (default) uses text prompts with body position primers
- FLUX 2 Pro uses structured JSON prompts — sometimes better for non-standing positions
- Gemini 2.5 Flash does the QA — it has some variance in pose_score (±1 is normal)
- BFL generation takes 30-90 seconds per image (this is expected, be patient)
- 26 exercises have custom visual prompt overrides for poses FLUX frequently misinterprets"""


# ---------- Tool execution functions ----------

def execute_read_qa_failures(
    qa_report: dict,
    exercises_by_name: dict[str, dict],
) -> dict:
    """Return all failing exercises with metadata."""
    results = qa_report.get("results", {})
    failures = []

    for key, result in results.items():
        if result.get("overall_pass", True):
            continue

        exercise_name = key  # normalized_filename is the key
        exercise_meta = exercises_by_name.get(exercise_name)
        if exercise_meta is None:
            continue  # Skip exercises not in the loaded set (filtered out)
        has_custom = exercise_name in _CUSTOM_VISUAL_PROMPTS

        failures.append({
            "exercise_name": exercise_name,
            "display_name": result.get("exercise_name", exercise_name),
            "pose_score": result.get("pose_score", 0),
            "critical_failures": result.get("critical_failures", []),
            "body_position": exercise_meta.get("body_position", "unknown"),
            "pose_description": exercise_meta.get("pose_description", ""),
            "has_custom_prompt": has_custom,
            "observations": {
                check: result[check].get("observation", "")
                for check in [
                    "anatomy", "subject", "full_body", "clothing",
                    "background", "no_text", "art_style",
                    "body_orientation", "pose_accuracy",
                ]
                if check in result and isinstance(result[check], dict)
            },
        })

    return {
        "total_failures": len(failures),
        "failures": failures,
    }


def execute_generate_image(
    exercise_name: str,
    exercises_by_name: dict[str, dict],
    bfl_key: str,
    seed_offset: int = 0,
    model: str = "kontext-pro",
    dry_run: bool = False,
) -> dict:
    """Generate an image and save it to disk."""
    exercise_dict = exercises_by_name.get(exercise_name)
    if not exercise_dict:
        return {"success": False, "error": f"Exercise '{exercise_name}' not found in exercise list"}

    output_path = OUTPUT_DIR / f"{exercise_name}.png"

    image_bytes = generate_image(
        None,
        exercise_dict,
        dry_run=dry_run,
        api_key=bfl_key,
        seed_offset=seed_offset,
        model=model,
    )

    if dry_run:
        return {"success": True, "path": str(output_path), "dry_run": True}

    if image_bytes is None:
        return {"success": False, "error": "BFL API returned no image data"}

    saved = save_image(image_bytes, output_path)
    if not saved:
        return {"success": False, "error": "Failed to save image to disk"}

    return {"success": True, "path": str(output_path)}


def execute_qa_image(
    exercise_name: str,
    exercises_by_name: dict[str, dict],
    gemini_client,
) -> dict:
    """Run Gemini QA on a single image and return results as dict."""
    exercise_dict = exercises_by_name.get(exercise_name)
    if not exercise_dict:
        return {"error": f"Exercise '{exercise_name}' not found in exercise list"}

    image_path = OUTPUT_DIR / f"{exercise_name}.png"
    if not image_path.exists():
        return {
            "overall_pass": False,
            "pose_score": 0,
            "critical_failures": ["IMAGE_NOT_FOUND"],
            "error": f"Image file not found: {image_path}",
        }

    result = analyze_image(gemini_client, image_path, exercise_dict)
    return result.model_dump()


def execute_check_custom_prompt(exercise_name: str) -> dict:
    """Check if an exercise has a custom visual prompt override."""
    custom = _CUSTOM_VISUAL_PROMPTS.get(exercise_name)
    if custom:
        return {
            "exists": True,
            "description": custom.get("description", ""),
            "angle": custom.get("angle", ""),
        }
    return {"exists": False}


# ---------- Tool dispatcher ----------

def dispatch_tool(
    tool_name: str,
    tool_input: dict,
    *,
    qa_report: dict,
    exercises_by_name: dict[str, dict],
    bfl_key: str,
    gemini_client,
    dry_run: bool = False,
) -> dict | str:
    """Dispatch a tool call to the appropriate executor."""
    if tool_name == "read_qa_failures":
        return execute_read_qa_failures(qa_report, exercises_by_name)

    elif tool_name == "generate_image":
        return execute_generate_image(
            exercise_name=tool_input["exercise_name"],
            exercises_by_name=exercises_by_name,
            bfl_key=bfl_key,
            seed_offset=tool_input.get("seed_offset", 0),
            model=tool_input.get("model", "kontext-pro"),
            dry_run=dry_run,
        )

    elif tool_name == "qa_image":
        if dry_run:
            return {
                "overall_pass": False,
                "pose_score": 1,
                "critical_failures": ["DRY_RUN"],
                "dry_run": True,
            }
        return execute_qa_image(
            exercise_name=tool_input["exercise_name"],
            exercises_by_name=exercises_by_name,
            gemini_client=gemini_client,
        )

    elif tool_name == "check_custom_prompt":
        return execute_check_custom_prompt(tool_input["exercise_name"])

    elif tool_name == "submit_fix_report":
        return tool_input  # The report data itself — handled by the caller

    else:
        return {"error": f"Unknown tool: {tool_name}"}


# ---------- Agent loop ----------

def run_agent(
    anthropic_client: anthropic.Anthropic,
    qa_report: dict,
    exercises_by_name: dict[str, dict],
    bfl_key: str,
    gemini_client,
    dry_run: bool = False,
) -> dict:
    """
    Run the Claude agent loop to fix failing exercise images.

    Returns the fix report dict from submit_fix_report, or a partial
    report if the agent times out.
    """
    start_time = time.time()

    # Build initial user message
    failure_count = sum(
        1 for r in qa_report.get("results", {}).values()
        if not r.get("overall_pass", True)
    )
    user_message = (
        f"There are {failure_count} failing exercise images that need fixing. "
        f"Start by calling read_qa_failures to see the full details, then fix each one."
    )
    if dry_run:
        user_message += " NOTE: This is a dry run — generate_image will not call the BFL API and qa_image will return dummy failures."

    messages = [{"role": "user", "content": user_message}]

    generation_count = 0
    qa_count = 0

    while True:
        # Timeout check
        elapsed = time.time() - start_time
        if elapsed > AGENT_TIMEOUT_S:
            print(f"\n  TIMEOUT after {elapsed:.0f}s")
            return {
                "status": "timeout",
                "exercises": [],
                "summary": {"fixed": 0, "still_failing": failure_count, "flagged_manual": 0},
            }

        # Call Claude
        response = anthropic_client.messages.create(
            model=AGENT_MODEL,
            max_tokens=AGENT_MAX_TOKENS,
            system=SYSTEM_PROMPT,
            tools=TOOLS,
            messages=messages,
        )

        # Process response
        if response.stop_reason == "end_turn":
            # Agent finished without calling submit_fix_report
            # Extract any text content
            text_parts = [b.text for b in response.content if b.type == "text"]
            print(f"\n  Agent ended turn: {' '.join(text_parts)[:200]}")
            return {
                "status": "ended_without_report",
                "agent_message": " ".join(text_parts),
                "exercises": [],
                "summary": {"fixed": 0, "still_failing": failure_count, "flagged_manual": 0},
            }

        if response.stop_reason != "tool_use":
            print(f"\n  Unexpected stop reason: {response.stop_reason}")
            break

        # Process tool calls
        assistant_content = response.content
        tool_results = []

        for block in assistant_content:
            if block.type == "text":
                # Print agent's reasoning
                if block.text.strip():
                    print(f"\n  Agent: {block.text[:300]}")
            elif block.type == "tool_use":
                tool_name = block.name
                tool_input = block.input
                tool_id = block.id

                # Log tool call
                if tool_name == "generate_image":
                    generation_count += 1
                    ex_name = tool_input.get("exercise_name", "?")
                    model_name = tool_input.get("model", "kontext-pro")
                    offset = tool_input.get("seed_offset", 0)
                    print(f"\n  [{generation_count}] Generating {ex_name} (model={model_name}, offset={offset})...", end="", flush=True)
                elif tool_name == "qa_image":
                    qa_count += 1
                    ex_name = tool_input.get("exercise_name", "?")
                    print(f" QA {ex_name}...", end="", flush=True)
                elif tool_name == "submit_fix_report":
                    print(f"\n  Agent submitting fix report...")
                elif tool_name == "read_qa_failures":
                    print(f"\n  Reading QA failures...")
                elif tool_name == "check_custom_prompt":
                    print(f"  Checking custom prompt for {tool_input.get('exercise_name', '?')}...", end="", flush=True)

                # Execute tool
                result = dispatch_tool(
                    tool_name,
                    tool_input,
                    qa_report=qa_report,
                    exercises_by_name=exercises_by_name,
                    bfl_key=bfl_key,
                    gemini_client=gemini_client,
                    dry_run=dry_run,
                )

                # Handle submit_fix_report specially — terminates the loop
                if tool_name == "submit_fix_report":
                    summary = result.get("summary", {})
                    print(f"  Fixed: {summary.get('fixed', 0)}, "
                          f"Still failing: {summary.get('still_failing', 0)}, "
                          f"Flagged: {summary.get('flagged_manual', 0)}")
                    print(f"\n  Total: {generation_count} generations, {qa_count} QA checks")
                    result["status"] = "completed"
                    return result

                # Log QA results
                if tool_name == "qa_image" and isinstance(result, dict):
                    passed = result.get("overall_pass", False)
                    score = result.get("pose_score", "?")
                    print(f" {'PASS' if passed else 'FAIL'} (score={score})", end="")

                tool_results.append({
                    "type": "tool_result",
                    "tool_use_id": tool_id,
                    "content": json.dumps(result) if isinstance(result, dict) else str(result),
                })

        # Append assistant message + tool results for next iteration
        messages.append({"role": "assistant", "content": assistant_content})
        messages.append({"role": "user", "content": tool_results})

    return {
        "status": "error",
        "exercises": [],
        "summary": {"fixed": 0, "still_failing": failure_count, "flagged_manual": 0},
    }
