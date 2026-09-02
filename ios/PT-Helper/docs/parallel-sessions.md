# Parallel Claude Code Sessions

How to run multiple Claude Code sessions against this repo at the same time without them clobbering each other — and how to make them cooperate. Companion to the `## Parallel Sessions` section in `CLAUDE.md` (the rules live there; this doc carries the recipes). Written against Claude Code CLI 2.1.76.

## Why isolation is required

Every session started in the repo directory shares one working tree and **one git index**:

- A session can write a stale copy of a file another session just edited. The Edit tool's staleness detection reduces this but doesn't eliminate it.
- `git add .` or `git commit -a` in one session silently commits another session's half-done work.
- Two builds or test runs race on the same booted simulator.

## Starting an isolated session (one worktree per session)

| How | Command / action |
|---|---|
| New CLI session | `claude -w <name>` — optionally `-n "<display name>"` so peers can address it, `--tmux` for a dedicated pane |
| Already-running session | Ask it to "work in a worktree" (EnterWorktree tool); "exit the worktree" returns it to the main checkout |
| Delegated agent work | A lead session spawns agents with `isolation: "worktree"` (the `team` skill does this) |
| Resuming later | `claude --resume` re-enters the session's worktree; `--fork-session` to branch off a copy |

Worktrees land in `.claude/worktrees/<name>/` on their own branch (`worktree-<name>`), with their own index. **They branch from `main` by default — not from whatever branch you currently have checked out** (verified on 2.1.76). If the parallel session should continue existing branch work, check out that branch inside the worktree first. Claude Code blocks a worktree-isolated session from editing the main checkout. Two repo-specific advantages:

- **Xcode 16 synchronized groups** — adding files doesn't touch the pbxproj, so worktree merges don't hit the classic pbxproj-conflict problem.
- **DerivedData is keyed by path** — each worktree builds into its own DerivedData automatically (costs disk + a cold first build; no clashes).

**Untracked essentials.** `.worktreeinclude` (repo root, gitignore syntax) lists gitignored files that Claude Code copies into every new worktree. Currently: `functions/.env`, `scripts/archive/pilots/animation-pilot/.env`. Add any new gitignored-but-required file there. `functions/node_modules/` and `functions/lib/` are *not* copied — run `npm install` / `npm run build` inside the worktree when doing functions work.

## Shared resources worktrees don't isolate

### Simulator — one device per session

Two `xcodebuild` runs against the same booted simulator fight over install/launch (and UI tests fight for foreground). Assign each concurrent session its own device by UDID:

```bash
xcrun simctl list devices available | grep -i iphone
```

Current assignment on this Mac (re-check UDIDs after Xcode/runtime updates):

| Role | Device | UDID |
|---|---|---|
| Primary (main session default) | iPhone 16 | `8B908AF6-D437-40DC-9593-2DDC315B0480` |
| Secondary | iPhone 16 Pro | `A1579757-01DC-4BE8-A068-249FD8467C44` |
| Tertiary | iPhone 16 Plus | `122537A4-4BB4-45B6-A202-6E0C522C0C71` |

Destination syntax: `-destination 'platform=iOS Simulator,id=<UDID>'`. If more devices are needed: `xcrun simctl clone <UDID> "iPhone 16 wt2"`.

### Firebase deploys — serialize

Single `pt-helper-dev` project. Never `firebase deploy` from two sessions at once. Announce a deploy via cross-session message (below) before running it.

### Image pipeline — single owner, main checkout only

`scripts/` jobs share `scripts/output/` (gitignored, multi-GB — it does not follow into worktrees) and per-day API quotas. One session owns pipeline work at a time, from the main checkout.

### Git refs

Worktrees share `.git`. Git itself prevents two worktrees from checking out the same branch, but avoid ref surgery — rebasing shared branches, deleting branches, `git worktree prune` — while other sessions are running.

## Same-checkout fallback (when you skip worktrees)

Acceptable only for short tasks in strictly disjoint areas (e.g. `functions/` vs `ios/`):

- Stage explicitly (`git add <paths>`) — never `git add .` / `git commit -a`.
- Don't run builds/tests simultaneously against the same device.
- Treat an Edit staleness warning as "the other session touched this file" — coordinate before continuing.

## Cooperation between sessions

### Peer messaging

Sessions on this Mac can discover and message each other (the SendMessage tool; the desktop app additionally exposes session-management tools to list sessions, message one, and search transcripts). Name sessions (`claude -n "functions-work"`) so they're addressable. Use it for:

- **Claims** — "I own `ExerciseImageService.swift` and the mapping JSON today."
- **Handoffs** — "RehabPlan schema changed on my branch — rebase before touching `Models/`."
- **Serialization** — "Deploying functions now; hold deploys until I confirm."

A received message is plain text delivered into the target session's conversation — it cannot approve permissions or execute anything by itself.

### One feature split across workers — lead + agents (preferred)

Don't run N peer sessions on one feature. Run **one lead session** that decomposes the work, delegates to worktree-isolated implementation agents (`isolation: "worktree"`; the `team` skill implements the full pattern), then reviews and merges sequentially. Sequential merges by a single lead avoid cross-branch conflicts entirely, and it matches the standing preference: lead on orchestration/review, implementation delegated.

### Agent teams — experimental, revisit

Claude Code has an experimental agent-teams feature (shared task list, teammate messaging, lead orchestration). It is not advertised in the installed CLI (`claude --help`, 2.1.76) and is documented as experimental — don't build process on it yet.

## Merge & cleanup

1. Inside the worktree: commit on its branch, rebase on `main`, and run the FullPlan gate before merging (per CLAUDE.md).
2. Merge from the main checkout (or via PR), then remove the worktree:

```bash
git worktree remove .claude/worktrees/<name>
```

   Add `--force` if copied `.env` files remain in it, then delete the merged branch.
3. Hygiene: run `git worktree list` periodically; remove worktrees for finished work so stale branches don't accumulate.
