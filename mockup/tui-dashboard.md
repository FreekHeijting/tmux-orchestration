# TUI: central live dashboard (design for T-2)

Follows `mockup/_STANDARD.md`.

## Purpose

Eén centrale rich-based dashboard die orchestrator (en optioneel user)
opent in een eigen terminal-tab of pane. Toont in real-time:
- alle live tmux-sessies + hun role + state + last activity
- kanban-board (4 kolommen) van `tmo task`
- live tail van `state/messages.jsonl` (laatste 20)
- watchdog status overzicht
- bench-rates per recente feature

Reden: huidige `tui/tui-rich.py` is mockup met hardcoded demo-state.json.
T-2 wire = wire naar live state-files met polling.

## Layout

```
┌──────────────────────────────────────────────────────────────────────────────────┐
│ tmux-orchestration dashboard                                  2026-05-11 19:50   │
├────────────────────────────────────┬─────────────────────────────────────────────┤
│ SESSIONS                           │ KANBAN                                      │
│ ▸ orchestrator   active   T-1     │ pending(4)  in_progress(2)  review(0) done │
│ ▸ debug-orch     done     T-18    │ T-2 .....   T-41 dash       (empty)    .... │
│ ▸ cleanup-orch   done     T-23    │ T-20 ....   T-42 sidekick                   │
│ ▸ bench-orch     done     T-7     │ T-38 ....                                   │
├────────────────────────────────────┼─────────────────────────────────────────────┤
│ MESSAGES (last 20)                 │ WATCHDOG                                    │
│ 18:16 debug-orch → orch  done T-18 │ orchestrator   active   0   2026-05-11T19  │
│ 18:16 cleanup    → orch  done T-23 │ debug-orch     idle     -   2026-05-10T18  │
│ 18:19 bench-orch → orch  done T-7  │ cleanup-orch   idle     -   2026-05-10T18  │
│ ... (truncated)                    │ bench-orch     idle     -   2026-05-10T18  │
├────────────────────────────────────┴─────────────────────────────────────────────┤
│ BENCH-RATES (recent)                                                             │
│ T-7  perf       1.00  graduate                                                   │
│ T-18 copy-mode  1.00  graduate                                                   │
│ T-23 cleanup    1.00  graduate                                                   │
│ T-27 auto-claim 1.00  graduate                                                   │
│ T-28 kanban     1.00  graduate                                                   │
│ T-40 replay-hd  1.00  graduate                                                   │
└──────────────────────────────────────────────────────────────────────────────────┘
[q] quit  [r] refresh now  [↑/↓] scroll  [tab] cycle panels
```

## Data-flow

```
                       ⊙ user runs tmo dashboard
                       │
                       ▼
        ┌──────────────────────────┐
        │ open rich.Live           │
        │ layout: 4 panels         │
        │ + bench summary         │
        │ + key-help footer        │
        └──────────────┬───────────┘
                       │
                       ▼
              ┌──────────────────┐
              │ poll loop (2s)?  │
              └──┬────────────┬──┘
            tick │            │ user key
                 ▼            ▼
   ┌─────────────────────┐  ┌──────────────────┐
   │ re-read state files │  │ q → exit         │
   │ - sessions.yaml     │  │ r → force tick   │
   │ - tasks.jsonl       │  │ tab → cycle      │
   │ - messages.jsonl    │  │      focus panel │
   │ - orchestrator-     │  └────┬─────────────┘
   │   status.yaml       │       │
   │ - bench/*.yaml      │       │
   └─────────┬───────────┘       │
             │                   │
             ▼                   │
   ┌─────────────────────┐       │
   │ rebuild panels:     │       │
   │ - sessions table    │       │
   │ - kanban board      │       │
   │ - messages tail     │       │
   │ - watchdog overview │       │
   │ - bench table       │       │
   └─────────┬───────────┘       │
             │                   │
             ▼                   │
   ┌─────────────────────┐       │
   │ rich.Live.update()  │ ◄─────┘
   └─────────┬───────────┘
             │
             ▼
        loop back to poll

Legenda: ⊙ start. ◇ decision. Rectangles = action.
```

## CLI signature (new)

```
tmo dashboard
  [--state-dir <path>]    override TMO_STATE_DIR
  [--interval <sec>]      poll cadence (default 2)
  [--no-bench]            hide bench-rates panel

Effect:
  Launches python3 <plugin>/tui/dashboard.py with TMO_STATE_DIR resolved.
  Full-screen rich.Live. Quit with q. Read-only.
```

## Existing vs new

- `tui/tui-rich.py` exists as static mockup; will be replaced or refactored
  into `tui/dashboard.py` with live-polling.
- `tui/demo-state.json` becomes a unit-test fixture instead of runtime input.

## Schema-changes

None. Pure reader.

## Implementation order (T-2 scope)

1. Refactor `tui/tui-rich.py` → `tui/dashboard.py`. Take TMO_STATE_DIR from env.
2. Wire 5 panels to live state-files (read-only, no caching).
3. Implement key-handlers: q, r, tab.
4. Add `tmo dashboard` subcommand to `bin/tmo`.
5. Karpathy bench (5 cases).

## Failure modes

- TMO_STATE_DIR missing or unreadable → dashboard shows banner "state-dir not found" and exits non-zero
- rich not installed → exit 1 with install hint
- One of the state-files missing → that panel shows "(empty)", others continue

## Open questions

- [ ] Embed kanban directly or shell-out to `tmo task board`?
- [ ] Support multiple workspaces side-by-side (multi-state-dir)?
- [ ] Add `[a] approve` and `[j] reject` key-shortcuts for review-state tasks?

## Karpathy 5-task bench plan

| # | category         | scenario                                                                 |
|---|------------------|--------------------------------------------------------------------------|
| 1 | typical          | dashboard launches on live state, shows all 5 panels populated           |
| 2 | edge-case        | empty workspace (no tasks, no sessions) → panels show "(empty)", no crash |
| 3 | anti-pattern     | corrupt jsonl line → panel shows "(parse error: line N)", continues      |
| 4 | ambiguous-scope  | narrow terminal (< 100 cols) → layout collapses gracefully or warns      |
| 5 | cross-skill      | dashboard open while orchestrator does `tmo cleanup`, board updates within 1 tick |

## Status

- mockup: draft (awaiting user confirm before T-2 impl)
- impl:   not-started
- bench:  not-started
