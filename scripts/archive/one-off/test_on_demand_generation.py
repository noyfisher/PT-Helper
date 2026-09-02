#!/usr/bin/env python3
"""
Standalone test script for the generateExerciseImage Cloud Function.
Calls the function directly via HTTP POST — no simulator needed.

Usage:
  # Get a Firebase ID token first (or use a virtual user token)
  python test_on_demand_generation.py --token <firebase_id_token>
  python test_on_demand_generation.py --service-account path/to/key.json

Tests:
  1. Known exercise (should return already_exists)
  2. Fuzzy-matchable name (should auto-alias)
  3. Novel exercise (should trigger full generation)
  4. Duplicate concurrent requests (should hit lock)
  5. Rate limiting (4+ rapid requests)
"""

import argparse
import asyncio
import json
import sys
import time
from concurrent.futures import ThreadPoolExecutor

import requests

# Default Cloud Function URL
DEFAULT_URL = "https://us-central1-pt-helper-dev.cloudfunctions.net/generateExerciseImage"


def get_token_from_service_account(sa_path: str) -> str:
    """Create a virtual user and get their ID token."""
    import firebase_admin
    from firebase_admin import auth, credentials

    if not firebase_admin._apps:
        cred = credentials.Certificate(sa_path)
        firebase_admin.initialize_app(cred)

    # Create or get a test user
    test_email = "image-test@pt-helper-test.com"
    try:
        user = auth.get_user_by_email(test_email)
    except auth.UserNotFoundError:
        user = auth.create_user(email=test_email, display_name="Image Test User")

    # Generate a custom token and exchange it
    custom_token = auth.create_custom_token(user.uid)

    # Exchange custom token for ID token via Firebase Auth REST API
    import os
    api_key = os.environ.get("FIREBASE_WEB_API_KEY", "")
    if not api_key:
        print("Warning: FIREBASE_WEB_API_KEY not set. Using custom token directly.")
        return custom_token.decode() if isinstance(custom_token, bytes) else custom_token

    resp = requests.post(
        f"https://identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken?key={api_key}",
        json={"token": custom_token.decode() if isinstance(custom_token, bytes) else custom_token, "returnSecureToken": True},
    )
    resp.raise_for_status()
    return resp.json()["idToken"]


def call_generate(url: str, token: str, exercise_name: str, **kwargs) -> dict:
    """Call the generateExerciseImage Cloud Function."""
    body = {"exerciseName": exercise_name}
    body.update(kwargs)

    resp = requests.post(
        url,
        json=body,
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
        },
        timeout=360,
    )

    return {
        "status_code": resp.status_code,
        "body": resp.json() if resp.headers.get("content-type", "").startswith("application/json") else resp.text,
    }


def test_known_exercise(url: str, token: str):
    """Test 1: Known exercise should return already_exists."""
    print("\n--- Test 1: Known exercise (should return already_exists) ---")
    result = call_generate(url, token, "Quad Sets")
    print(f"  Status: {result['status_code']}")
    print(f"  Response: {json.dumps(result['body'], indent=2)}")

    status = result["body"].get("status") if isinstance(result["body"], dict) else None
    if status in ("already_exists", "alias_added"):
        print("  ✅ PASS — exercise found via mapping")
    else:
        print(f"  ❌ FAIL — expected already_exists/alias_added, got {status}")


def test_fuzzy_match(url: str, token: str):
    """Test 2: Fuzzy-matchable name should auto-alias."""
    print("\n--- Test 2: Fuzzy-matchable name (should auto-alias) ---")
    result = call_generate(url, token, "Cat-Cow Stretch Modified For Lower Back Relief")
    print(f"  Status: {result['status_code']}")
    print(f"  Response: {json.dumps(result['body'], indent=2)}")

    status = result["body"].get("status") if isinstance(result["body"], dict) else None
    if status in ("already_exists", "alias_added"):
        print("  ✅ PASS — fuzzy match resolved")
    else:
        print(f"  ⚠️  Status: {status} (may trigger generation if alias not in Firestore yet)")


def test_novel_exercise(url: str, token: str):
    """Test 3: Novel exercise should trigger full generation."""
    print("\n--- Test 3: Novel exercise (should trigger generation) ---")
    print("  This test takes 45-90 seconds (FLUX generation + Gemini QA)...")
    start = time.time()
    result = call_generate(
        url, token,
        "Single Arm Overhead Kettlebell Press",
        exerciseCategory="strength",
        targetArea="Shoulder",
        bodyPosition="standing",
        poseDescription="Standing upright with feet shoulder-width apart. Right arm presses a kettlebell overhead with elbow fully extended. Left arm at side.",
    )
    elapsed = time.time() - start
    print(f"  Status: {result['status_code']} ({elapsed:.1f}s)")
    print(f"  Response: {json.dumps(result['body'], indent=2)}")

    status = result["body"].get("status") if isinstance(result["body"], dict) else None
    if status == "success":
        print("  ✅ PASS — image generated successfully")
    elif status in ("already_exists", "alias_added"):
        print("  ✅ PASS — image already existed")
    elif status == "locked":
        print("  ⚠️  Locked — another generation in progress")
    else:
        print(f"  ❌ FAIL — status: {status}")


def test_concurrent_requests(url: str, token: str):
    """Test 4: Concurrent requests should hit the lock."""
    print("\n--- Test 4: Concurrent duplicate requests (should hit lock) ---")
    exercise_name = "Banded Hip Thrust With Pause"

    with ThreadPoolExecutor(max_workers=2) as executor:
        future1 = executor.submit(call_generate, url, token, exercise_name)
        time.sleep(0.5)  # Slight delay so first request gets the lock
        future2 = executor.submit(call_generate, url, token, exercise_name)

        r1 = future1.result()
        r2 = future2.result()

    print(f"  Request 1: status={r1['body'].get('status') if isinstance(r1['body'], dict) else 'error'}")
    print(f"  Request 2: status={r2['body'].get('status') if isinstance(r2['body'], dict) else 'error'}")

    statuses = {r1["body"].get("status"), r2["body"].get("status")} if isinstance(r1["body"], dict) and isinstance(r2["body"], dict) else set()
    if "locked" in statuses:
        print("  ✅ PASS — second request was locked")
    else:
        print(f"  ⚠️  Both requests completed: {statuses}")


def test_rate_limiting(url: str, token: str):
    """Test 5: Rapid requests should hit rate limit."""
    print("\n--- Test 5: Rate limiting (4 rapid requests) ---")
    for i in range(4):
        result = call_generate(url, token, f"Test Rate Limit Exercise {i}")
        status = result["body"].get("status") if isinstance(result["body"], dict) else None
        print(f"  Request {i+1}: status_code={result['status_code']}, status={status}")
        if status == "rate_limited":
            print("  ✅ PASS — rate limit triggered")
            return

    print("  ⚠️  Rate limit not triggered (may need to run again)")


def main():
    parser = argparse.ArgumentParser(description="Test generateExerciseImage Cloud Function")
    parser.add_argument("--token", help="Firebase ID token")
    parser.add_argument("--service-account", help="Path to service account JSON (creates test user)")
    parser.add_argument("--url", default=DEFAULT_URL, help="Cloud Function URL")
    parser.add_argument("--test", choices=["known", "fuzzy", "novel", "concurrent", "rate", "all"], default="all")
    args = parser.parse_args()

    # Get token
    if args.token:
        token = args.token
    elif args.service_account:
        token = get_token_from_service_account(args.service_account)
    else:
        print("Error: provide --token or --service-account")
        sys.exit(1)

    print(f"Testing {args.url}")
    print(f"Token: {token[:20]}...")

    tests = {
        "known": test_known_exercise,
        "fuzzy": test_fuzzy_match,
        "novel": test_novel_exercise,
        "concurrent": test_concurrent_requests,
        "rate": test_rate_limiting,
    }

    if args.test == "all":
        for name, fn in tests.items():
            fn(args.url, token)
    else:
        tests[args.test](args.url, token)

    print("\n--- Done ---")


if __name__ == "__main__":
    main()
