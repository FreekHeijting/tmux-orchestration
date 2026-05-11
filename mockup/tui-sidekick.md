# TUI: per-worker sidekick (split-pane, design for T-20)

Follows `mockup/_STANDARD.md`.

## Purpose

Elke worker (sub-orch of stable role) krijgt naast de claude REPL een
**sidekick-pane** rechts naast de claude. Sidekick toont in real-time:
- huidige task + status + bench-rate
- last 5 peer-messages (in / out)
- watchdog state per peer-session
- snelle hint-blok: welke commands kun je nu draaien

Reden: 4-line statusbar is goed voor "at a glance" maar geeft geen
inkomende peer-messages of historie. Sidekick is een pull-flow log + state
mirror naast de chat-REPL.

## Layout binnen tmux-sessie

```
┌─────────────────────────────────────────────┬──────────────────────────────┐
│                                             │ ┃ sidekick - debug-orch ┃    │
│         claude REPL (links, 70%)            ├──────────────────────────────┤
│                                             │ TASK                         │
│         ❯                                   │ T-18  in_progress            │
│                                             │ bench: -                     │
│           ⏵⏵ bypass on                      │                              │
│                                             │ PEER-TRAFFIC (last 5)        │
│                                             │ ▸ in  from orch  18:16 sigh  │
│                                             │ ▸ out to orch    18:16 done  │
│                                             │ ▸ in  from clean 18:17 ack   │
│                                             │                              │
│                                             │ WATCHDOG                     │
│                                             │ orch       active            │
│                                             │ cleanup    idle              │
│                                             │ bench-orch idle              │
│                                             │                              │
│                                             │ HINT                         │
│                                             │ next:  tmo task review T-18  │
│                                             │ on done: tmo note orch ...   │
├─────────────────────────────────────────────┴──────────────────────────────┤
│ debug-orch │ role=sub-orch-builder │ task=T-18 │ state=in_progress │ peer=3 │ ← statusbar line 0
│ 📋 T-18: copy-mode detect ...                                              │ ← line 1
│ branch=feat/copy-mode-detect | dir=tmo-wt-debug                            │ ← line 2
│ Watchdog tick + auto -X cancel + throttle...                               │ ← line 3
└────────────────────────────────────────────────────────────────────────────┘
```

## Spawn flow met split-pane

```
                       ⊙ orchestrator runs tmo spawn ... --task T-X
                       │
                       ▼
        ┌──────────────────────────┐
        │ tmux new-session -d -s   │
        │   <name> -c <wt>         │
        │   "TMO_* env claude"     │
        └──────────────┬───────────┘
                       │
                       ▼
        ┌──────────────────────────┐
        │ tmux split-window -h     │
        │   -p 30 -t <name>:0      │
        │   "tmo sidekick <name>"  │
        │ (right pane, 30% width)  │
        └──────────────┬───────────┘
                       │
                       ▼
              ┌──────────────────┐
              │ sidekick?        │
              └──┬────────────┬──┘
        opt-in  │            │ opt-out
                ▼            ▼
   ┌────────────────────┐  ┌──────────────────┐
   │ tmo sidekick       │  │ kill the right   │
   │ <session>          │  │ pane, full-width │
   │ polls every 3s     │  │ claude only      │
   └─────────┬──────────┘  └──────────────────┘
             │
             ▼
   ┌─────────────────────┐
   │ apply statusline    │
   │ (4-line bar)        │
   │ on whole window     │
   └─────────┬───────────┘
             │
             ▼
   ┌─────────────────────┐
   │ tmux select-pane -t │
   │ <name>:0.0 (focus   │
   │ left = claude REPL) │
   └─────────────────────┘

Legenda: ⊙ start. ◇ decision. Rectangles = action.
```

## tmo sidekick subcommand (new)

```
tmo sidekick <session>
  [--interval <sec>]      poll cadence (default 3)
  [--no-watchdog]         hide watchdog panel
  [--no-hints]            hide hint panel

Effect:
  Renders a rich-Live TUI inside the current pane.
  Reads:
    state/tasks.jsonl   for claimed task
    state/messages.jsonl tail for peer-traffic
    state/orchestrator-status.yaml for watchdog state
  Refreshes every <interval> seconds.
  Ctrl+C exits cleanly.
```

## Schema-changes

Nothing. Sidekick is purely a reader of existing state files. No new
events, no new state.

## Implementation (T-20 scope)

- Add `tmo sidekick` to `bin/tmo` (shells out to `python3 <plugin>/tui/sidekick.py <session>`).
- Add `tui/sidekick.py` (rich.Live with 4 panels: TASK, PEER-TRAFFIC, WATCHDOG, HINT).
- Update `cmd_spawn` in `bin/tmo`: after `tmux new-session -d`, optionally
  `tmux split-window -h -p 30 -t <name>:0 "tmo sidekick <name>"`.
  Behind a `--sidekick` flag, default off.
- Statusbar already applies to the entire window (both panes share).

## Failure modes

- rich not installed → sidekick.py exits with helpful pip install message
- state files missing → sidekick shows empty panels, doesn't crash
- TMO_STATE_DIR not set in tmux env → use $PWD/state default

## Open questions

- [ ] Width 30% always or auto-shrink for narrow terminals?
- [ ] Should sidekick send commands too (e.g. "approve" button) or read-only?
- [ ] Click-handlers via rich mouse-events feasible inside tmux pane?
- [ ] Sidekick per ALL sessions or only sub-orchs (not orchestrator)?

## Karpathy 5-task bench plan

| # | category         | scenario                                                                 |
|---|------------------|--------------------------------------------------------------------------|
| 1 | typical          | spawn with --sidekick, both panes alive, sidekick shows current task     |
| 2 | edge-case        | session with no claimed task → sidekick shows "(idle)" not crash         |
| 3 | anti-pattern     | rich not installed → sidekick exits 1 with install hint, claude unaffected |
| 4 | ambiguous-scope  | narrow terminal (< 80 cols) → sidekick auto-degrades or warns            |
| 5 | cross-skill      | after split + sidekick, peer-injection into claude pane still works (target the left pane) |

## Status

- mockup: draft (awaiting user confirm before T-20 impl)
- impl:   not-started
- bench:  not-started
