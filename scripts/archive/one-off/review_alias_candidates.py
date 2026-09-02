"""
Local review UI for alias candidates flagged by dedupe_stockpile.py.

For each entry in scripts/output/stockpile_needs_review.json, shows:
  - variant name + canonical name side-by-side
  - canonical exercise image (variant has no image yet)
  - proposed default verdict (merge/skip) with rationale
  - [M]erge / [S]kip buttons (or keyboard: M / S, arrow keys to navigate)

Decisions saved to scripts/output/alias_review_decisions.json.
Run `python scripts/dedupe_stockpile.py --consume-review` afterwards to apply.

Usage:
  python scripts/review_alias_candidates.py
  python scripts/review_alias_candidates.py --port 5301
"""
from __future__ import annotations

import argparse
import json
from http.server import HTTPServer, SimpleHTTPRequestHandler
from pathlib import Path
from urllib.parse import urlparse, parse_qs

SCRIPT_DIR = Path(__file__).resolve().parent
OUTPUT_DIR = SCRIPT_DIR / "output"
REVIEW_IN = OUTPUT_DIR / "stockpile_needs_review.json"
DECISIONS = OUTPUT_DIR / "alias_review_decisions.json"
MAPPING = OUTPUT_DIR / "exercise_image_mapping.json"

# Proposed default verdicts (from the walkthrough). User overrides as needed.
DEFAULT_VERDICTS: dict[str, tuple[str, str, str]] = {
    # variant -> (verdict, canonical, rationale)
    "supine-bridge":                         ("merge", "supine-glute-bridge",                        "glute implicit"),
    "shoulder-cross-body-stretch":           ("merge", "cross-body-stretch",                         "cross-body IS shoulder"),
    "shoulder-pendulum-swings":              ("merge", "pendulum-swings",                            "pendulums are shoulder"),
    "prone-shoulder-horizontal-abduction":   ("merge", "prone-horizontal-abduction",                 "shoulder implicit"),
    "band-shoulder-external-rotation":       ("merge", "band-external-rotation",                     "band ER is shoulder"),
    "shoulder-internal-rotation-band":       ("merge", "band-internal-rotation",                     "shoulder implicit"),
    "standing-core-rotation-band":           ("merge", "standing-rotation-band",                     "core implicit"),
    "standing-torso-rotation-with-band":     ("merge", "standing-rotation-band",                     "torso implicit"),
    "plantar-fascia-foot-stretch":           ("merge", "plantar-fascia-stretch",                     "foot implicit"),
    "pronation-supination":                  ("merge", "wrist-pronation-supination",                 "forearm rotation at wrist"),
    "postural-chin-tucks":                   ("merge", "chin-tucks",                                 "qualifier adjective"),
    "big-standing-marching":                 ("merge", "standing-marching",                          "'big' = intensity"),
    "graded-grip-strengthening":             ("merge", "grip-strengthening",                         "'graded' = progression"),
    "standing-quad-sets-wall":               ("merge", "standing-quad-sets-against-wall",            "'against' = filler"),
    "thoracic-extension-stretch":            ("merge", "thoracic-extension",                         "thoracic ext IS a stretch"),
    "cervical-rotation":                     ("merge", "cervical-rotation-stretch",                  "same pose, held"),
    "gentle-knee-flexion":                   ("merge", "knee-flexion-stretch",                       "gentle + missing 'stretch'"),
    "neck-isometric-flexion":                ("merge", "cervical-isometric-neck-flexion",            "neck = cervical"),
    "prone-t-y-i-holds":                     ("merge", "prone-iyt-holds",                            "letter reorder"),
    "step-up-dumbbell":                      ("merge", "dumbbell-step-ups",                          "reorder + plural"),
    "doorway-shoulder-stretch":              ("merge", "doorway-stretch",                            "doorway stretch is pec/shoulder"),
    "doorway-pectoral-stretch":              ("merge", "doorway-stretch",                            "doorway stretch is pec/shoulder"),
    "doorway-pec-stretch":                   ("merge", "pec-stretch",                                "doorway is standard pec stretch"),
    "thumb-cmc-isometric-hold":              ("merge", "isometric-thumb-hold",                       "CMC = thumb joint"),
    "hand-wrist-circles":                    ("merge", "wrist-circles",                              "hand moves with wrist"),
    "seated-figure-four-hip-stretch":        ("merge", "seated-figure-four-stretch",                 "fig-4 is hip stretch"),
    "resistance-band-internal-rotation":     ("merge", "resistance-band-shoulder-internal-rotation", "shoulder implicit (j=0.80)"),
    # SKIPS
    "posterior-shoulder-doorway-stretch":    ("skip",  "posterior-shoulder-stretch",                 "doorway technique differs"),
    "single-leg-romanian-deadlift":          ("skip",  "single-leg-deadlift",                        "Romanian = specific hinge"),
    "dumbbell-deadlifts":                    ("skip",  "dumbbell-romanian-deadlifts",                "Romanian = specific hinge"),
    "heel-toe-raises":                       ("skip",  "toe-raises",                                 "different muscles (gastroc vs tib)"),
    "standing-heel-toe-raises":              ("skip",  "standing-heel-raises",                       "different muscles"),
    "cervical-lateral-flexion":              ("skip",  "cervical-isometric-lateral-flexion",         "dynamic vs isometric"),
    "supine-hip-knee-flexion":               ("skip",  "supine-hip-flexion",                         "knee bent changes pose"),
    "hip-internal-rotation-band":            ("skip",  "band-internal-rotation",                     "canonical ambiguous"),
}


def load_decisions() -> dict:
    if DECISIONS.exists():
        return json.loads(DECISIONS.read_text())
    return {}


def save_decisions(d: dict) -> None:
    DECISIONS.write_text(json.dumps(d, indent=2, sort_keys=True) + "\n")


def find_image(key: str) -> str | None:
    p = OUTPUT_DIR / f"{key}.png"
    return f"/img/{key}.png" if p.exists() else None


def build_entries() -> list[dict]:
    review = json.loads(REVIEW_IN.read_text())["needs_review"]
    mapping = json.loads(MAPPING.read_text())
    decisions = load_decisions()
    entries = []
    for r in review:
        variant = r["variant"]
        default = DEFAULT_VERDICTS.get(variant)
        if default:
            verdict, canonical, rationale = default
        else:
            verdict, canonical, rationale = "skip", r["candidates"][0]["canonical"], "no default — review"
        canonical_name = mapping.get(canonical, {}).get("name", canonical)
        entries.append({
            "variant": variant,
            "variant_display": r.get("variant_name", variant),
            "canonical": canonical,
            "canonical_display": canonical_name,
            "image_url": find_image(canonical),
            "all_candidates": r["candidates"],
            "default_verdict": verdict,
            "rationale": rationale,
            "current_verdict": decisions.get(variant, {}).get("verdict", verdict),
            "current_canonical": decisions.get(variant, {}).get("canonical", canonical),
        })
    return entries


HTML = """<!doctype html><html><head><meta charset=utf-8><title>Alias review</title>
<style>
  body {{ font-family: -apple-system, system-ui, sans-serif; margin: 0; background: #0f1115; color: #e5e7eb; }}
  header {{ position: sticky; top: 0; background: #111827; padding: 12px 24px; border-bottom: 1px solid #1f2937; display: flex; gap: 24px; align-items: center; z-index: 10; }}
  header h1 {{ font-size: 16px; margin: 0; font-weight: 600; }}
  header .counts {{ font-size: 13px; color: #9ca3af; }}
  header .keys {{ font-size: 11px; color: #6b7280; margin-left: auto; }}
  header button {{ background: #2563eb; color: white; border: 0; padding: 6px 12px; border-radius: 6px; cursor: pointer; font-weight: 500; }}
  .grid {{ display: grid; grid-template-columns: repeat(auto-fill, minmax(420px, 1fr)); gap: 16px; padding: 16px; }}
  .card {{ background: #1f2937; border-radius: 10px; padding: 12px; border: 2px solid transparent; transition: border 0.1s; }}
  .card.merge {{ border-color: #16a34a; }}
  .card.skip  {{ border-color: #dc2626; }}
  .card.focused {{ box-shadow: 0 0 0 2px #60a5fa; }}
  .card img {{ width: 100%; aspect-ratio: 1; object-fit: contain; background: white; border-radius: 6px; }}
  .card .placeholder {{ width: 100%; aspect-ratio: 1; background: #374151; border-radius: 6px; display: flex; align-items: center; justify-content: center; color: #6b7280; }}
  .card h3 {{ font-size: 14px; margin: 8px 0 4px; }}
  .card .variant {{ color: #fbbf24; font-family: ui-monospace, monospace; font-size: 12px; word-break: break-all; }}
  .card .arrow {{ color: #6b7280; margin: 4px 0; }}
  .card .canonical {{ color: #86efac; font-family: ui-monospace, monospace; font-size: 12px; word-break: break-all; }}
  .card .rationale {{ color: #9ca3af; font-size: 11px; margin: 6px 0; font-style: italic; }}
  .card .buttons {{ display: flex; gap: 8px; margin-top: 8px; }}
  .card button {{ flex: 1; padding: 6px; border-radius: 5px; border: 1px solid #374151; background: #111827; color: #e5e7eb; cursor: pointer; font-weight: 500; }}
  .card button.active-merge {{ background: #16a34a; border-color: #16a34a; color: white; }}
  .card button.active-skip  {{ background: #dc2626; border-color: #dc2626; color: white; }}
  .card .idx {{ color: #6b7280; font-size: 10px; font-family: ui-monospace, monospace; }}
</style></head>
<body>
<header>
  <h1>Alias review</h1>
  <div class=counts id=counts></div>
  <button onclick="exportJSON()">Save progress</button>
  <div class=keys>M = merge · S = skip · ← → navigate</div>
</header>
<div class=grid id=grid></div>
<script>
const entries = {entries_json};
let focused = 0;

function update(i, verdict) {{
  entries[i].current_verdict = verdict;
  fetch('/decide', {{method:'POST', headers:{{'content-type':'application/json'}}, body: JSON.stringify({{
    variant: entries[i].variant, verdict, canonical: entries[i].current_canonical
  }})}});
  render();
}}

function focusCard(i) {{
  focused = Math.max(0, Math.min(entries.length - 1, i));
  render();
  document.querySelectorAll('.card')[focused]?.scrollIntoView({{block:'nearest', behavior:'smooth'}});
}}

function render() {{
  const grid = document.getElementById('grid');
  const merges = entries.filter(e => e.current_verdict === 'merge').length;
  const skips = entries.filter(e => e.current_verdict === 'skip').length;
  document.getElementById('counts').textContent = `${{merges}} merge · ${{skips}} skip · ${{entries.length}} total`;
  grid.innerHTML = entries.map((e, i) => {{
    const img = e.image_url ? `<img src="${{e.image_url}}" loading=lazy>` : '<div class=placeholder>no image</div>';
    const mergeActive = e.current_verdict === 'merge' ? 'active-merge' : '';
    const skipActive = e.current_verdict === 'skip' ? 'active-skip' : '';
    const focusedCls = i === focused ? 'focused' : '';
    return `
      <div class="card ${{e.current_verdict}} ${{focusedCls}}" onclick="focusCard(${{i}})">
        <div class=idx>${{i + 1}}/${{entries.length}}</div>
        ${{img}}
        <div class=variant>${{e.variant}}</div>
        <div class=arrow>↓</div>
        <div class=canonical>${{e.canonical}}</div>
        <div class=rationale>${{e.rationale}}</div>
        <div class=buttons>
          <button class="${{mergeActive}}" onclick="event.stopPropagation();update(${{i}},'merge')">Merge</button>
          <button class="${{skipActive}}" onclick="event.stopPropagation();update(${{i}},'skip')">Skip</button>
        </div>
      </div>`;
  }}).join('');
}}

function exportJSON() {{
  window.location = '/export';
}}

document.addEventListener('keydown', e => {{
  if (e.key === 'm' || e.key === 'M') {{ update(focused, 'merge'); focusCard(focused + 1); }}
  else if (e.key === 's' || e.key === 'S') {{ update(focused, 'skip'); focusCard(focused + 1); }}
  else if (e.key === 'ArrowRight') focusCard(focused + 1);
  else if (e.key === 'ArrowLeft') focusCard(focused - 1);
  else if (e.key === 'ArrowDown') focusCard(focused + 3);
  else if (e.key === 'ArrowUp') focusCard(focused - 3);
}});

render();
</script>
</body></html>"""


class Handler(SimpleHTTPRequestHandler):
    def log_message(self, *a, **kw): pass

    def do_GET(self):
        url = urlparse(self.path)
        if url.path == "/":
            entries = build_entries()
            body = HTML.format(entries_json=json.dumps(entries)).encode()
            self.send_response(200)
            self.send_header("content-type", "text/html; charset=utf-8")
            self.send_header("content-length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        elif url.path.startswith("/img/"):
            name = url.path[len("/img/"):]
            p = OUTPUT_DIR / name
            if not p.exists() or not p.is_file():
                self.send_error(404)
                return
            data = p.read_bytes()
            self.send_response(200)
            self.send_header("content-type", "image/png")
            self.send_header("content-length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
        elif url.path == "/export":
            data = (DECISIONS.read_bytes() if DECISIONS.exists() else b"{}\n")
            self.send_response(200)
            self.send_header("content-type", "application/json")
            self.send_header("content-disposition", 'attachment; filename="alias_review_decisions.json"')
            self.send_header("content-length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
        else:
            self.send_error(404)

    def do_POST(self):
        if self.path != "/decide":
            self.send_error(404)
            return
        length = int(self.headers.get("content-length", "0"))
        payload = json.loads(self.rfile.read(length))
        decisions = load_decisions()
        decisions[payload["variant"]] = {
            "verdict": payload["verdict"],
            "canonical": payload["canonical"],
        }
        save_decisions(decisions)
        self.send_response(204)
        self.end_headers()


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=5301)
    args = ap.parse_args()
    # Pre-seed decisions file with defaults so a "no-op" pass still captures them.
    existing = load_decisions()
    mapping = json.loads(MAPPING.read_text())  # validate it loads
    for variant, (verdict, canonical, _) in DEFAULT_VERDICTS.items():
        existing.setdefault(variant, {"verdict": verdict, "canonical": canonical})
    save_decisions(existing)
    print(f"Alias review: http://localhost:{args.port}/")
    print(f"Entries: {len(json.loads(REVIEW_IN.read_text())['needs_review'])}")
    print(f"Decisions will save live to: {DECISIONS.relative_to(SCRIPT_DIR.parent)}")
    print(f"When done, run: python scripts/dedupe_stockpile.py --consume-review")
    HTTPServer(("127.0.0.1", args.port), Handler).serve_forever()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
