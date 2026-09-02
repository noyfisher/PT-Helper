# Exercise Animation Pilot

Generate looping exercise animation GIFs using FLUX 2 Pro (end frames) + Pika Pikaframes (video interpolation).

## Setup

```bash
cd scripts/animation-pilot
pip install -r requirements.txt
brew install ffmpeg  # if not already installed
```

**API keys needed:**
- **BFL** (FLUX 2 Pro) — https://dashboard.bfl.ai — for end-position frame generation
- **fal.ai** (Pika Pikaframes) — https://fal.ai/dashboard — for video interpolation

## Quick Start

```bash
# 1. Preview prompts (no API calls)
python generate.py --dry-run

# 2. Generate end frame for one exercise
python generate.py --bfl-api-key KEY --exercises bird-dog --step end-frame

# 3. Full pipeline for one exercise
python generate.py --bfl-api-key KEY --fal-api-key KEY --exercises bird-dog

# 4. Review results in browser
python review.py
# Open http://localhost:5111

# 5. Run all 10 pilot exercises
python generate.py --bfl-api-key KEY --fal-api-key KEY --exercises pilot
```

## Pipeline

```
Start frame (existing)     End frame (FLUX 2 Pro)
  ../output/{name}.png  →   output/end-frames/{name}_end.png
         ↓                          ↓
         └────── Pika Pikaframes ──┘
                      ↓
              output/videos/{name}.mp4
                      ↓
              output/gifs/{name}_anim.gif
```

## CLI Flags

| Flag | Description |
|------|-------------|
| `--exercises pilot` | Process the 10 pilot exercises (default) |
| `--exercises bird-dog,clamshells` | Process specific exercises |
| `--step end-frame\|video\|gif` | Run only one pipeline step |
| `--skip-end-frame` | Skip FLUX 2 Pro, reuse existing end frames |
| `--skip-existing` | Skip exercises with existing output |
| `--dry-run` | Print prompts, no API calls |

## Iteration Workflow

1. Generate end frames: `--step end-frame`
2. Review end frames in gallery: `python review.py`
3. If end frame is wrong → tweak description in `generate.py`, re-run step 1
4. Generate video: `--step video`
5. Review video/GIF in gallery
6. If motion is wrong → tweak motion prompt, re-run step 2
7. Adjust GIF settings → `--step gif` (change fps/resolution in `config.json`)

## Cost

~$0.25 per exercise:
- FLUX 2 Pro end frame: ~$0.05
- Pika Pikaframes (720p): ~$0.20
- Full pilot (10 exercises): ~$2.50

## Output Structure

```
output/
├── end-frames/          # FLUX 2 Pro end-position PNGs
├── videos/              # Raw MP4s from Pikaframes
├── gifs/                # Final looping GIFs (ready for iOS)
├── review-log.json      # Pass/fail/retry notes per exercise
└── generation-log.json  # Pipeline run results
```

## Pilot Exercises

| # | Exercise | Position | Movement |
|---|----------|----------|----------|
| 1 | wall-slides | standing | Arms slide up wall from W to Y |
| 2 | standing-hip-abduction | standing | Leg lifts to the side |
| 3 | pendulum-swings | standing | Arm swings in pendulum arc |
| 4 | bird-dog | quadruped | Opposite arm + leg extend |
| 5 | clamshells | side_lying | Top knee opens up |
| 6 | straight-leg-raises | supine | Leg raises to 45 degrees |
| 7 | seated-knee-extension | seated | Leg extends forward |
| 8 | seated-calf-raises | seated | Heels rise off ground |
| 9 | chin-tucks | standing | Chin retracts backward |
| 10 | scapular-squeezes | standing | Shoulder blades squeeze together |
