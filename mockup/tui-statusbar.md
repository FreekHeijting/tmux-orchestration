# TUI: tmux statusbar (live, document-only)

Follows `mockup/_STANDARD.md`. **Documents existing behaviour** rather than
proposing new (T-19 + T-26 already merged on main).

## Purpose

Every spawned tmux session shows a 4-line status-bar at the bottom of its
tmux pane. Lines 1-3 are a task-banner (subject, branch, desc); line 4 is
the live one-line status. Refreshes every 5 seconds via shell-out to `tmo
headerline` and `tmo statusline`. Lets the user see at a glance which
agent is doing what, on which branch, with what task.

## Layout

```
┌─────────────────────────────────────────────────────────────────────┐
│ <claude REPL takes the entire visible pane height minus 4 rows>     │
│                                                                     │
│ ❯                                                                   │
│   ⏵⏵ bypass permissions on (shift+tab to cycle)                     │
├─────────────────────────────────────────────────────────────────────┤
│ 📋 T-41: mockup/tui-dashboard.md ...                          [1]   │ ← status-format[1]
│ branch=feat/tui-dashboard | dir=tmux-orchestration             [2]   │ ← status-format[2]
│ Central rich-based live dashboard wiring                       [3]   │ ← status-format[3]
│ debug-orch | role=sub-orch-builder | task=T-41 | state=in_pr… [0]   │ ← status-format[0]
└─────────────────────────────────────────────────────────────────────┘
```

## Data-flow

```
                       ⊙ tmux pane refresh tick (5s)
                       │
                       ▼
        ┌──────────────────────────┐
        │ tmux re-evaluates        │
        │ status-format[0..3]      │
        └──────────────┬───────────┘
                       │
       ┌───────────────┼───────────────┐
       │               │               │
       ▼               ▼               ▼
 ┌──────────┐   ┌──────────────┐  ┌──────────────────┐
 │ static:  │   │ #(tmo        │  │ #(tmo            │
 │ <sess>   │   │  statusline  │  │  headerline      │
 │ + role   │   │  <sess>)     │  │  <sess> 1|2|3)   │
 │ at spawn │   │              │  │                  │
 └──────────┘   └──────┬───────┘  └────────┬─────────┘
                       │                   │
                       ▼                   ▼
                ┌─────────────┐    ┌──────────────────┐
                │ replay      │    │ replay + git +   │
                │ tasks.jsonl │    │ pane_current_pat │
                │ filter      │    │ + tasks.jsonl    │
                │ in_progress │    │                  │
                │ by sess     │    │                  │
                └─────────────┘    └──────────────────┘
                       │                   │
                       ▼                   ▼
                "task=T-X | state=…  "T-X: subject"
                | peer=N"            "branch=… | dir=…"
                                     "first sentence of desc"
```

Legenda: ⊙ = trigger. Rectangles = action. Arrows = data flow.

## CLI signatures (already live)

```
tmo statusline <session>
  Output (one line, with tmux #[fg=...] markup):
    task=T-X | state=working | peer=N

tmo headerline <session> 1|2|3
  Output (one line per call):
    1 → "📋 T-X: <subject truncated to 108ch>"  OR  "(no claimed task)"
    2 → "branch=<git branch> | dir=<basename pwd>"
    3 → "<first sentence of task.desc>"
```

## tmux options set by `_apply_statusline` on spawn

```
status               4                     ← 4-line bar
status-interval      5                     ← 5s refresh
status-bg            colour234
status-fg            white
status-left-length   120
status-right-length  60
status-left          "<sess> | role=<r> | #(tmo statusline <sess>) "
status-right         "<HH:MM> | tmo"
status-format[0]     <align-left status-left><align-right status-right>
status-format[1]     #(tmo headerline <sess> 1)
status-format[2]     #(tmo headerline <sess> 2)
status-format[3]     #(tmo headerline <sess> 3)
```

## Performance contract

Each `#(...)` shell-out must complete in <100ms. Current implementation:
- `tmo statusline`: ~30-50ms (jq replay + 2 small jq filters)
- `tmo headerline`: ~50-80ms (same replay + git command + path basename)

Multiple refreshes per session per second never happen (5s floor). Replay
overhead measured in T-7 bench: 42ms at N=1000 tasks, 1.6s at N=10000.
Acceptable.

## Failure modes

- TMO_STATE_DIR not exported in tmux env → all shell-outs return empty (silent)
- tasks.jsonl missing → status shows `task=- state=?`
- git not a repo → branch shows `-`
- Subject longer than 108 chars → truncated, no ellipsis (intentional, saves space)

## Open questions

- [ ] Add a color-cue for state (green=working, yellow=blocked, red=stale)?
- [ ] Add a peer-traffic flash when peer>0 in last tick?
- [ ] Show watchdog state (active/awaiting/idle) in line 4?

## Status

- mockup: documents-existing (T-19 + T-26 merged on main)
- impl:   live
- bench:  no separate bench; T-19 + T-26 lifecycle covered by their merges
