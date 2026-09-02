#!/usr/bin/env python3
"""
Local review server for exercise image pairs.

Serves a web UI for quickly reviewing start/end image pairs,
writing notes about issues, and marking pairs as pass/fail/needs-regen.

Usage:
    python review_server.py                    # Review all pairs
    python review_server.py --failures-only    # Only pairs that failed consistency QA
    python review_server.py --port 5200

Then open http://localhost:5200 in your browser.
"""

import argparse
import json
import sys
from http.server import HTTPServer, SimpleHTTPRequestHandler
from pathlib import Path
from urllib.parse import parse_qs, urlparse

SCRIPT_DIR = Path(__file__).parent
OUTPUT_DIR = SCRIPT_DIR / "output"
REVIEW_LOG = OUTPUT_DIR / "review_log.json"
CONSISTENCY_REPORT = OUTPUT_DIR / "consistency_report.json"


def load_review_log() -> dict:
    if REVIEW_LOG.exists():
        with open(REVIEW_LOG) as f:
            return json.load(f)
    return {}


def save_review_log(log: dict):
    with open(REVIEW_LOG, "w") as f:
        json.dump(log, f, indent=2)


def get_exercise_pairs(failures_only: bool = False) -> list[dict]:
    """Find all start/end image pairs in the output directory."""
    end_images = sorted(OUTPUT_DIR.glob("*_end.png"))
    pairs = []

    # Load consistency report if available
    consistency = {}
    if CONSISTENCY_REPORT.exists():
        with open(CONSISTENCY_REPORT) as f:
            data = json.load(f)
            consistency = data.get("results", {})

    # Load existing reviews
    reviews = load_review_log()

    for end_path in end_images:
        name = end_path.stem.replace("_end", "")
        start_path = OUTPUT_DIR / f"{name}.png"
        if not start_path.exists():
            continue

        qa = consistency.get(name, {})
        qa_score = qa.get("overall_consistency_score", None)
        qa_pass = qa.get("overall_pass", None)
        qa_failures = qa.get("critical_failures", [])

        if failures_only and qa_pass is True:
            continue

        review = reviews.get(name, {})

        pairs.append({
            "name": name,
            "display_name": name.replace("-", " ").title(),
            "start_image": f"{name}.png",
            "end_image": f"{name}_end.png",
            "qa_score": qa_score,
            "qa_pass": qa_pass,
            "qa_failures": qa_failures,
            "qa_checks": {
                k: qa.get(k, {})
                for k in ["camera_angle", "character_identity", "clothing",
                           "art_style", "scene_setup", "body_anchoring", "movement_logic"]
                if k in qa
            },
            "review_status": review.get("status", "unreviewed"),
            "review_notes": review.get("notes", ""),
        })

    return pairs


# Store pairs globally so the handler can access them
PAIRS: list[dict] = []
FAILURES_ONLY = False


class ReviewHandler(SimpleHTTPRequestHandler):
    def do_GET(self):
        parsed = urlparse(self.path)

        if parsed.path == "/":
            self.send_response(200)
            self.send_header("Content-Type", "text/html")
            self.end_headers()
            self.wfile.write(build_html().encode())

        elif parsed.path == "/api/pairs":
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            # Refresh pairs to pick up new reviews
            pairs = get_exercise_pairs(FAILURES_ONLY)
            self.wfile.write(json.dumps(pairs).encode())

        elif parsed.path.startswith("/images/"):
            filename = parsed.path.replace("/images/", "")
            filepath = OUTPUT_DIR / filename
            if filepath.exists() and filepath.suffix == ".png":
                self.send_response(200)
                self.send_header("Content-Type", "image/png")
                self.end_headers()
                self.wfile.write(filepath.read_bytes())
            else:
                self.send_error(404)

        else:
            self.send_error(404)

    def do_POST(self):
        if self.path == "/api/review":
            length = int(self.headers.get("Content-Length", 0))
            body = json.loads(self.rfile.read(length))

            name = body.get("name")
            status = body.get("status")  # "pass", "fail", "regen"
            notes = body.get("notes", "")

            if not name or not status:
                self.send_error(400, "name and status required")
                return

            log = load_review_log()
            log[name] = {
                "status": status,
                "notes": notes,
            }
            save_review_log(log)

            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps({"ok": True}).encode())
        else:
            self.send_error(404)

    def log_message(self, format, *args):
        # Suppress access logs
        pass


def build_html() -> str:
    return """<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Exercise Image Review</title>
<style>
  * { margin: 0; padding: 0; box-sizing: border-box; }
  body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; background: #0a0a0a; color: #e0e0e0; }

  .header {
    position: fixed; top: 0; left: 0; right: 0; z-index: 100;
    background: #1a1a1a; border-bottom: 1px solid #333;
    padding: 12px 24px; display: flex; align-items: center; gap: 16px;
  }
  .header h1 { font-size: 18px; font-weight: 600; white-space: nowrap; }
  .progress { font-size: 14px; color: #888; white-space: nowrap; }
  .progress .reviewed { color: #4ade80; }
  .progress .failed { color: #f87171; }
  .filter-bar { display: flex; gap: 8px; margin-left: auto; }
  .filter-btn {
    padding: 6px 12px; border-radius: 6px; border: 1px solid #444;
    background: transparent; color: #ccc; cursor: pointer; font-size: 13px;
  }
  .filter-btn.active { background: #2563eb; border-color: #2563eb; color: white; }

  .main { margin-top: 60px; display: flex; height: calc(100vh - 60px); }

  .sidebar {
    width: 280px; min-width: 280px; border-right: 1px solid #333;
    overflow-y: auto; background: #111;
  }
  .sidebar-item {
    padding: 10px 16px; cursor: pointer; border-bottom: 1px solid #1a1a1a;
    display: flex; align-items: center; gap: 10px;
  }
  .sidebar-item:hover { background: #1a1a1a; }
  .sidebar-item.active { background: #1e3a5f; border-left: 3px solid #3b82f6; }
  .sidebar-item .name { font-size: 13px; flex: 1; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .sidebar-item .badge {
    font-size: 11px; padding: 2px 6px; border-radius: 4px; white-space: nowrap;
  }
  .badge.pass { background: #166534; color: #4ade80; }
  .badge.fail { background: #7f1d1d; color: #f87171; }
  .badge.regen { background: #713f12; color: #fbbf24; }
  .badge.unreviewed { background: #333; color: #888; }
  .badge.qa-pass { background: #14532d; color: #86efac; }
  .badge.qa-fail { background: #450a0a; color: #fca5a5; }

  .content { flex: 1; overflow-y: auto; padding: 24px; }

  .exercise-name { font-size: 24px; font-weight: 700; margin-bottom: 16px; }

  .images-row { display: flex; gap: 24px; margin-bottom: 20px; }
  .image-col { flex: 1; text-align: center; }
  .image-col img {
    max-width: 100%; max-height: 400px; border-radius: 12px;
    border: 2px solid #333; background: #fff;
  }
  .image-label {
    margin-top: 8px; font-size: 14px; font-weight: 600;
    text-transform: uppercase; letter-spacing: 1px; color: #888;
  }

  .qa-section { margin-bottom: 20px; }
  .qa-title { font-size: 14px; font-weight: 600; color: #888; margin-bottom: 8px; }
  .qa-checks { display: flex; flex-wrap: wrap; gap: 8px; }
  .qa-check {
    padding: 4px 10px; border-radius: 6px; font-size: 12px;
    display: flex; align-items: center; gap: 6px;
  }
  .qa-check.good { background: #14532d; color: #86efac; }
  .qa-check.bad { background: #450a0a; color: #fca5a5; }
  .qa-check .score { font-weight: 700; }

  .review-section { margin-top: 20px; }
  .review-section textarea {
    width: 100%; height: 80px; background: #1a1a1a; border: 1px solid #444;
    border-radius: 8px; color: #e0e0e0; padding: 12px; font-size: 14px;
    font-family: inherit; resize: vertical;
  }
  .review-section textarea:focus { outline: none; border-color: #3b82f6; }
  .review-section textarea::placeholder { color: #555; }

  .actions { display: flex; gap: 12px; margin-top: 12px; }
  .action-btn {
    padding: 10px 24px; border-radius: 8px; border: none;
    font-size: 14px; font-weight: 600; cursor: pointer; transition: all 0.15s;
  }
  .action-btn:hover { transform: translateY(-1px); }
  .btn-pass { background: #166534; color: #4ade80; }
  .btn-pass:hover { background: #15803d; }
  .btn-fail { background: #7f1d1d; color: #f87171; }
  .btn-fail:hover { background: #991b1b; }
  .btn-regen { background: #713f12; color: #fbbf24; }
  .btn-regen:hover { background: #854d0e; }

  .keyboard-hint {
    margin-top: 12px; font-size: 12px; color: #555;
  }
  kbd {
    background: #333; padding: 2px 6px; border-radius: 4px;
    font-family: monospace; font-size: 11px; border: 1px solid #555;
  }

  .empty { text-align: center; padding: 80px 20px; color: #555; }
  .empty h2 { font-size: 20px; margin-bottom: 8px; }
</style>
</head>
<body>

<div class="header">
  <h1>Exercise Image Review</h1>
  <div class="progress">
    <span class="reviewed" id="reviewed-count">0</span> reviewed &middot;
    <span class="failed" id="failed-count">0</span> need regen &middot;
    <span id="total-count">0</span> total
  </div>
  <div class="filter-bar">
    <button class="filter-btn active" data-filter="all">All</button>
    <button class="filter-btn" data-filter="unreviewed">Unreviewed</button>
    <button class="filter-btn" data-filter="fail">Failed QA</button>
    <button class="filter-btn" data-filter="regen">Needs Regen</button>
  </div>
</div>

<div class="main">
  <div class="sidebar" id="sidebar"></div>
  <div class="content" id="content">
    <div class="empty">
      <h2>Select an exercise from the sidebar</h2>
      <p>Use arrow keys to navigate, 1/2/3 to rate</p>
    </div>
  </div>
</div>

<script>
let pairs = [];
let currentIndex = -1;
let currentFilter = 'all';

async function loadPairs() {
  const resp = await fetch('/api/pairs');
  pairs = await resp.json();
  updateCounts();
  renderSidebar();
  if (pairs.length > 0 && currentIndex === -1) selectPair(0);
}

function updateCounts() {
  const reviewed = pairs.filter(p => p.review_status !== 'unreviewed').length;
  const regen = pairs.filter(p => p.review_status === 'regen').length;
  document.getElementById('reviewed-count').textContent = reviewed;
  document.getElementById('failed-count').textContent = regen;
  document.getElementById('total-count').textContent = pairs.length;
}

function filteredPairs() {
  if (currentFilter === 'all') return pairs;
  if (currentFilter === 'unreviewed') return pairs.filter(p => p.review_status === 'unreviewed');
  if (currentFilter === 'fail') return pairs.filter(p => p.qa_pass === false);
  if (currentFilter === 'regen') return pairs.filter(p => p.review_status === 'regen');
  return pairs;
}

function renderSidebar() {
  const sidebar = document.getElementById('sidebar');
  const filtered = filteredPairs();
  sidebar.innerHTML = filtered.map((p, i) => {
    const realIdx = pairs.indexOf(p);
    const active = realIdx === currentIndex ? 'active' : '';
    const reviewBadge = p.review_status !== 'unreviewed'
      ? `<span class="badge ${p.review_status}">${p.review_status}</span>`
      : '';
    const qaBadge = p.qa_score !== null
      ? `<span class="badge ${p.qa_pass ? 'qa-pass' : 'qa-fail'}">${p.qa_score}</span>`
      : '';
    return `<div class="sidebar-item ${active}" onclick="selectPair(${realIdx})">
      <span class="name">${p.display_name}</span>
      ${qaBadge}${reviewBadge}
    </div>`;
  }).join('');
}

function selectPair(index) {
  currentIndex = index;
  const p = pairs[index];
  renderSidebar();

  const checksHtml = Object.entries(p.qa_checks || {}).map(([name, check]) => {
    const score = check.score || 0;
    const cls = score >= 4 ? 'good' : 'bad';
    const label = name.replace(/_/g, ' ');
    return `<span class="qa-check ${cls}"><span class="score">${score}</span> ${label}</span>`;
  }).join('');

  const content = document.getElementById('content');
  content.innerHTML = `
    <div class="exercise-name">${p.display_name}</div>

    <div class="images-row">
      <div class="image-col">
        <img src="/images/${p.start_image}" alt="Start position">
        <div class="image-label">Start</div>
      </div>
      <div class="image-col">
        <img src="/images/${p.end_image}" alt="End position">
        <div class="image-label">End</div>
      </div>
    </div>

    ${p.qa_score !== null ? `
    <div class="qa-section">
      <div class="qa-title">Consistency QA: ${p.qa_pass ? 'PASS' : 'FAIL'} (avg ${p.qa_score}/5)</div>
      <div class="qa-checks">${checksHtml}</div>
    </div>` : ''}

    <div class="review-section">
      <textarea id="notes" placeholder="What's wrong with this pair? (e.g., 'band disappears in end frame', 'camera angle shifted')">${p.review_notes}</textarea>
      <div class="actions">
        <button class="action-btn btn-pass" onclick="submitReview('pass')">Pass (1)</button>
        <button class="action-btn btn-regen" onclick="submitReview('regen')">Needs Regen (2)</button>
        <button class="action-btn btn-fail" onclick="submitReview('fail')">Bad / Skip (3)</button>
      </div>
      <div class="keyboard-hint">
        <kbd>&uarr;</kbd><kbd>&darr;</kbd> navigate &middot;
        <kbd>1</kbd> pass &middot; <kbd>2</kbd> needs regen &middot; <kbd>3</kbd> bad/skip &middot;
        <kbd>Enter</kbd> submit &amp; next
      </div>
    </div>
  `;
}

async function submitReview(status) {
  const p = pairs[currentIndex];
  const notes = document.getElementById('notes')?.value || '';

  await fetch('/api/review', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ name: p.name, status, notes }),
  });

  p.review_status = status;
  p.review_notes = notes;
  updateCounts();

  // Auto-advance to next unreviewed
  const filtered = filteredPairs();
  const nextUnreviewed = pairs.findIndex((p, i) => i > currentIndex && p.review_status === 'unreviewed');
  if (nextUnreviewed !== -1) {
    selectPair(nextUnreviewed);
  } else {
    renderSidebar();
  }
}

// Keyboard shortcuts
document.addEventListener('keydown', (e) => {
  // Don't capture when typing in textarea
  if (e.target.tagName === 'TEXTAREA') {
    if (e.key === 'Enter' && (e.metaKey || e.ctrlKey)) {
      e.preventDefault();
      submitReview('regen');
    }
    return;
  }

  const filtered = filteredPairs();

  if (e.key === 'ArrowDown' || e.key === 'j') {
    e.preventDefault();
    const next = pairs.findIndex((p, i) => i > currentIndex && filtered.includes(p));
    if (next !== -1) selectPair(next);
  }
  if (e.key === 'ArrowUp' || e.key === 'k') {
    e.preventDefault();
    let prev = -1;
    for (let i = currentIndex - 1; i >= 0; i--) {
      if (filtered.includes(pairs[i])) { prev = i; break; }
    }
    if (prev !== -1) selectPair(prev);
  }
  if (e.key === '1') submitReview('pass');
  if (e.key === '2') submitReview('regen');
  if (e.key === '3') submitReview('fail');
});

// Filter buttons
document.querySelectorAll('.filter-btn').forEach(btn => {
  btn.addEventListener('click', () => {
    document.querySelectorAll('.filter-btn').forEach(b => b.classList.remove('active'));
    btn.classList.add('active');
    currentFilter = btn.dataset.filter;
    renderSidebar();
  });
});

loadPairs();
</script>
</body>
</html>"""


def main():
    parser = argparse.ArgumentParser(description="Exercise image pair review server")
    parser.add_argument("--port", type=int, default=5200)
    parser.add_argument("--failures-only", action="store_true",
                        help="Only show pairs that failed consistency QA")
    args = parser.parse_args()

    global FAILURES_ONLY
    FAILURES_ONLY = args.failures_only

    pairs = get_exercise_pairs(args.failures_only)
    print(f"Found {len(pairs)} exercise pairs to review")

    reviewed = sum(1 for p in pairs if p["review_status"] != "unreviewed")
    if reviewed:
        print(f"  {reviewed} already reviewed (from review_log.json)")

    server = HTTPServer(("localhost", args.port), ReviewHandler)
    print(f"\nReview server running at http://localhost:{args.port}")
    print("Press Ctrl+C to stop\n")

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nStopped")
        server.server_close()


if __name__ == "__main__":
    main()
