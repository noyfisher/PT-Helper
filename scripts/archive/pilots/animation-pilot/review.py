#!/usr/bin/env python3
"""
Local web gallery for reviewing exercise animation results.

Shows side-by-side: start frame | end frame | animated GIF for each exercise.
Includes pass/fail/retry buttons that save to review-log.json.

Usage:
    python review.py              # Starts on http://localhost:5111
    python review.py --port 8080  # Custom port
"""

import argparse
import json
import os
from datetime import datetime
from pathlib import Path

try:
    from flask import Flask, jsonify, request, send_from_directory
except ImportError:
    print("ERROR: flask not installed. Run: pip install -r requirements.txt")
    exit(1)


SCRIPT_DIR = Path(__file__).parent
OUTPUT_DIR = SCRIPT_DIR / "output"
START_FRAMES_DIR = SCRIPT_DIR.parent / "output"
END_FRAMES_DIR = OUTPUT_DIR / "end-frames"
VIDEOS_DIR = OUTPUT_DIR / "videos"
GIFS_DIR = OUTPUT_DIR / "gifs"
CORRECTED_START_DIR = OUTPUT_DIR / "start-frames"
CONFIG_PATH = SCRIPT_DIR / "config.json"
REVIEW_LOG_PATH = OUTPUT_DIR / "review-log.json"

app = Flask(__name__)


def load_config() -> dict:
    with open(CONFIG_PATH) as f:
        return json.load(f)


def load_review_log() -> dict:
    if REVIEW_LOG_PATH.exists():
        with open(REVIEW_LOG_PATH) as f:
            return json.load(f)
    return {}


def save_review_log(log: dict):
    REVIEW_LOG_PATH.parent.mkdir(parents=True, exist_ok=True)
    with open(REVIEW_LOG_PATH, "w") as f:
        json.dump(log, f, indent=2)


def get_exercise_status() -> list[dict]:
    """Gather the status of all pilot exercises."""
    config = load_config()
    review_log = load_review_log()
    exercises = []

    for name in config["pilot_exercises"]:
        corrected_start = CORRECTED_START_DIR / f"{name}.png"
        original_start = START_FRAMES_DIR / f"{name}.png"
        start = corrected_start if corrected_start.exists() else original_start
        has_corrected_start = corrected_start.exists()
        end = END_FRAMES_DIR / f"{name}_end.png"
        video = VIDEOS_DIR / f"{name}.mp4"
        gif = GIFS_DIR / f"{name}_anim.gif"

        review = review_log.get(name, {})

        exercises.append({
            "name": name,
            "has_start": start.exists(),
            "has_corrected_start": has_corrected_start,
            "has_end": end.exists(),
            "has_video": video.exists(),
            "has_gif": gif.exists(),
            "start_size_kb": round(start.stat().st_size / 1024) if start.exists() else 0,
            "end_size_kb": round(end.stat().st_size / 1024) if end.exists() else 0,
            "video_size_kb": round(video.stat().st_size / 1024) if video.exists() else 0,
            "gif_size_kb": round(gif.stat().st_size / 1024) if gif.exists() else 0,
            "review_status": review.get("status", "pending"),
            "review_notes": review.get("notes", ""),
            "review_timestamp": review.get("timestamp", ""),
        })

    return exercises


# ---------- Routes ----------

@app.route("/")
def index():
    return HTML_PAGE


@app.route("/api/exercises")
def api_exercises():
    return jsonify(get_exercise_status())


@app.route("/api/review", methods=["POST"])
def api_review():
    data = request.json
    name = data.get("name")
    status = data.get("status")
    notes = data.get("notes", "")

    if not name or status not in ("pass", "fail", "retry"):
        return jsonify({"error": "Invalid request"}), 400

    log = load_review_log()
    log[name] = {
        "status": status,
        "notes": notes,
        "timestamp": datetime.now().isoformat(),
    }
    save_review_log(log)
    return jsonify({"ok": True})


# Serve image/video files
@app.route("/files/start/<filename>")
def serve_start(filename):
    # Serve corrected start frame if it exists, otherwise original
    corrected = CORRECTED_START_DIR / filename
    if corrected.exists():
        return send_from_directory(CORRECTED_START_DIR, filename)
    return send_from_directory(START_FRAMES_DIR, filename)


@app.route("/files/end/<filename>")
def serve_end(filename):
    return send_from_directory(END_FRAMES_DIR, filename)


@app.route("/files/video/<filename>")
def serve_video(filename):
    return send_from_directory(VIDEOS_DIR, filename)


@app.route("/files/gif/<filename>")
def serve_gif(filename):
    return send_from_directory(GIFS_DIR, filename)


# ---------- HTML Page ----------

HTML_PAGE = """<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Exercise Animation Review</title>
<style>
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', system-ui, sans-serif;
         background: #1a1a2e; color: #e0e0e0; padding: 24px; }
  h1 { text-align: center; margin-bottom: 8px; color: #fff; font-size: 24px; }
  .subtitle { text-align: center; color: #888; margin-bottom: 24px; font-size: 14px; }
  .stats { display: flex; gap: 16px; justify-content: center; margin-bottom: 24px; }
  .stat { background: #16213e; padding: 12px 20px; border-radius: 8px; text-align: center; }
  .stat-value { font-size: 24px; font-weight: 700; color: #e94560; }
  .stat-label { font-size: 12px; color: #888; margin-top: 2px; }
  .exercise-grid { display: grid; gap: 20px; }
  .exercise-card { background: #16213e; border-radius: 12px; padding: 20px;
                   border: 1px solid #2a2a4a; }
  .exercise-card.pass { border-color: #4ade80; }
  .exercise-card.fail { border-color: #f87171; }
  .exercise-card.retry { border-color: #fbbf24; }
  .card-header { display: flex; justify-content: space-between; align-items: center;
                 margin-bottom: 16px; }
  .exercise-name { font-size: 18px; font-weight: 600; color: #fff; }
  .status-badge { padding: 4px 12px; border-radius: 100px; font-size: 12px;
                  font-weight: 600; text-transform: uppercase; }
  .status-badge.pending { background: #334155; color: #94a3b8; }
  .status-badge.pass { background: #166534; color: #4ade80; }
  .status-badge.fail { background: #991b1b; color: #f87171; }
  .status-badge.retry { background: #92400e; color: #fbbf24; }
  .frames-row { display: grid; grid-template-columns: 1fr 1fr 1fr; gap: 12px;
                margin-bottom: 16px; }
  .frame-box { text-align: center; }
  .frame-label { font-size: 11px; color: #888; margin-bottom: 4px;
                 text-transform: uppercase; letter-spacing: 0.5px; }
  .frame-box img { width: 100%; aspect-ratio: 1; object-fit: contain;
                   background: #0f0f23; border-radius: 8px; border: 1px solid #2a2a4a; }
  .frame-box .placeholder { width: 100%; aspect-ratio: 1; background: #0f0f23;
                            border-radius: 8px; border: 1px dashed #333;
                            display: flex; align-items: center; justify-content: center;
                            color: #555; font-size: 13px; }
  .meta-row { display: flex; gap: 12px; margin-bottom: 12px; flex-wrap: wrap; }
  .meta-tag { background: #0f0f23; padding: 4px 10px; border-radius: 6px;
              font-size: 12px; color: #888; }
  .actions { display: flex; gap: 8px; align-items: center; }
  .btn { padding: 8px 16px; border: none; border-radius: 6px; font-size: 13px;
         font-weight: 600; cursor: pointer; transition: opacity 0.2s; }
  .btn:hover { opacity: 0.85; }
  .btn-pass { background: #166534; color: #4ade80; }
  .btn-fail { background: #991b1b; color: #f87171; }
  .btn-retry { background: #92400e; color: #fbbf24; }
  .notes-input { flex: 1; background: #0f0f23; border: 1px solid #2a2a4a;
                 border-radius: 6px; padding: 8px 12px; color: #e0e0e0;
                 font-size: 13px; }
  .notes-input::placeholder { color: #555; }
  .video-link { color: #60a5fa; text-decoration: none; font-size: 12px; }
  .video-link:hover { text-decoration: underline; }
  .refresh-btn { position: fixed; bottom: 24px; right: 24px; background: #e94560;
                 color: #fff; border: none; border-radius: 50%; width: 48px;
                 height: 48px; font-size: 20px; cursor: pointer; box-shadow: 0 4px 12px rgba(0,0,0,0.3); }
</style>
</head>
<body>

<h1>Exercise Animation Review</h1>
<p class="subtitle">Review generated animations — mark pass/fail/retry for each exercise</p>

<div class="stats" id="stats"></div>
<div class="exercise-grid" id="grid"></div>
<button class="refresh-btn" onclick="loadExercises()" title="Refresh">&#x21bb;</button>

<script>
let exercises = [];

async function loadExercises() {
  const resp = await fetch('/api/exercises');
  exercises = await resp.json();
  render();
}

function render() {
  // Stats
  const total = exercises.length;
  const passed = exercises.filter(e => e.review_status === 'pass').length;
  const failed = exercises.filter(e => e.review_status === 'fail').length;
  const gifs = exercises.filter(e => e.has_gif).length;

  document.getElementById('stats').innerHTML = `
    <div class="stat"><div class="stat-value">${total}</div><div class="stat-label">Total</div></div>
    <div class="stat"><div class="stat-value">${gifs}</div><div class="stat-label">GIFs Ready</div></div>
    <div class="stat"><div class="stat-value">${passed}</div><div class="stat-label">Passed</div></div>
    <div class="stat"><div class="stat-value">${failed}</div><div class="stat-label">Failed</div></div>
  `;

  // Cards
  document.getElementById('grid').innerHTML = exercises.map(ex => `
    <div class="exercise-card ${ex.review_status !== 'pending' ? ex.review_status : ''}" id="card-${ex.name}">
      <div class="card-header">
        <span class="exercise-name">${ex.name}</span>
        <span class="status-badge ${ex.review_status}">${ex.review_status}</span>
      </div>
      <div class="frames-row">
        <div class="frame-box">
          <div class="frame-label">Start Frame ${ex.has_corrected_start ? '<span style="color:#4ade80;font-weight:600">(Fixed)</span>' : ''}</div>
          ${ex.has_start
            ? `<img src="/files/start/${ex.name}.png?t=${Date.now()}" alt="Start frame">`
            : '<div class="placeholder">Not found</div>'}
        </div>
        <div class="frame-box">
          <div class="frame-label">End Frame</div>
          ${ex.has_end
            ? `<img src="/files/end/${ex.name}_end.png" alt="End frame">`
            : '<div class="placeholder">Not generated</div>'}
        </div>
        <div class="frame-box">
          <div class="frame-label">Animation</div>
          ${ex.has_gif
            ? `<img src="/files/gif/${ex.name}_anim.gif?t=${Date.now()}" alt="Animation">`
            : '<div class="placeholder">Not generated</div>'}
        </div>
      </div>
      <div class="meta-row">
        ${ex.has_start ? `<span class="meta-tag">Start: ${ex.start_size_kb} KB</span>` : ''}
        ${ex.has_end ? `<span class="meta-tag">End: ${ex.end_size_kb} KB</span>` : ''}
        ${ex.has_gif ? `<span class="meta-tag">GIF: ${ex.gif_size_kb} KB</span>` : ''}
        ${ex.has_video ? `<a href="/files/video/${ex.name}.mp4" target="_blank" class="video-link">View MP4</a>` : ''}
      </div>
      <div class="actions">
        <button class="btn btn-pass" onclick="review('${ex.name}', 'pass')">Pass</button>
        <button class="btn btn-fail" onclick="review('${ex.name}', 'fail')">Fail</button>
        <button class="btn btn-retry" onclick="review('${ex.name}', 'retry')">Retry</button>
        <input class="notes-input" id="notes-${ex.name}" placeholder="Notes..."
               value="${ex.review_notes || ''}">
      </div>
      ${ex.review_timestamp ? `<div style="font-size:11px; color:#555; margin-top:8px;">Last reviewed: ${new Date(ex.review_timestamp).toLocaleString()}</div>` : ''}
    </div>
  `).join('');
}

async function review(name, status) {
  const notes = document.getElementById('notes-' + name)?.value || '';
  await fetch('/api/review', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ name, status, notes })
  });
  await loadExercises();
}

// Auto-refresh every 30 seconds
setInterval(loadExercises, 30000);
loadExercises();
</script>
</body>
</html>
"""


def main():
    parser = argparse.ArgumentParser(description="Exercise animation review gallery")
    parser.add_argument("--port", type=int, default=5111, help="Port to run on (default: 5111)")
    parser.add_argument("--host", default="127.0.0.1", help="Host to bind to (default: 127.0.0.1)")
    args = parser.parse_args()

    print(f"\n  Exercise Animation Review Gallery")
    print(f"  http://{args.host}:{args.port}")
    print(f"  Press Ctrl+C to stop\n")

    app.run(host=args.host, port=args.port, debug=False)


if __name__ == "__main__":
    main()
