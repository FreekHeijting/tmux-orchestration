# Watchdog — orchestrator state-machine & cron-driven idle/awaiting detection

A cron-driven watchdog that tracks orchestrator-session liveness in tmux+Claude.
Detects when the orchestrator is idle (REPL waiting, no work) versus
awaiting-user (Claude asked a question and the human has not replied for N
ticks) and takes corrective action: log, park, or soft-inject a sidenote that
prods the orchestrator to pick from a backlog instead of stalling.

The watchdog is invoked per-tick via cron. It does NOT run as a daemon.

## State machine

| Status              | Trigger transition                                 | Action                                                                                                                                |
|---------------------|----------------------------------------------------|---------------------------------------------------------------------------------------------------------------------------------------|
| `active`            | pane content changed since last tick OR busy-spinner visible | none (refresh `last_active_ts`, reset `awaiting_user_count`)                                                                          |
| `awaiting-user`     | open question detected, no user reply since 1 tick (`count=1`) | log only                                                                                                                              |
| `awaiting-user`     | still no reply at next tick (`count>=2`)           | soft-inject `[SIDENOTE] user not replying. Park to state/parked-questions.yaml. Pick next from state/backlog.yaml`. Append to parked. |
| `idle-no-work`      | REPL idle + backlog empty + parked empty           | log only                                                                                                                              |
| `idle-with-backlog` | REPL idle + backlog non-empty                      | soft-inject `[SIDENOTE] backlog has N items, pick top-prio`                                                                           |

**Definitions:**

- *pane content changed*: SHA1 of `tmux capture-pane -p -S -200` differs from `last_pane_hash` stored in state.
- *busy-spinner visible*: pane tail contains a Claude busy indicator (`✻`, `✶`, `✢`, `Thinking`, `tokens`, or any spinner glyph).
- *open question*: pane tail contains a trailing `?` on a non-code line OR explicit `[AWAITING-USER]` marker. The trailing-`?` rule ignores lines inside fenced code blocks.
- *REPL idle*: pane changed = false AND no busy-spinner AND no open question.

**Tick interval**: every 10 minutes via cron is the recommended default.
Definition of "1 tick" = one watchdog invocation. The 10-minute baseline
gives the user enough time to reply naturally; tighten only if a workflow
demands faster pickup.

## Files (under `$TMO_STATE_DIR`)

### `state/orchestrator-status.yaml`

Per orchestrator session, the live status entry. Read+write each tick.

```yaml
sessions:
  orchestrator:
    status: active                 # one of: active|awaiting-user|idle-no-work|idle-with-backlog
    last_pane_hash: 7a3f...         # sha1 of last captured pane
    awaiting_user_count: 0          # consecutive ticks in awaiting-user
    current_question_id: null       # id when awaiting-user, else null
    last_checked_ts: 2026-05-10T16:30:00Z
    last_active_ts: 2026-05-10T16:25:00Z
    enabled: true                   # tracking flag
```

Multiple sessions can be tracked in parallel under `sessions:`.

### `state/parked-questions.yaml`

Append-on-park. Resume manually with `tmo watchdog resume <id>` (future).

```yaml
parked:
  - id: q-1
    session: orchestrator
    question: "Should I rebase or merge feat/foo?"
    parked_at: 2026-05-10T16:40:00Z
    pane_excerpt: |
      ...last 30 lines of pane at park time...
```

### `state/backlog.yaml`

Populated externally (orchestrator decides what is backlog). Watchdog reads
only; pick-action does NOT auto-claim — the soft-inject prods the
orchestrator to claim the top item itself.

```yaml
items:
  - id: b-1
    priority: high
    task: "review feat/foo PR comments"
    added_at: 2026-05-10T15:00:00Z
    claimed_by: null
```

## CLI surface

```
tmo watchdog tick <session>          # single tick: read state, classify, write back, optionally soft-inject
tmo watchdog status                  # show current state for all tracked sessions
tmo watchdog enable <session>        # initialize state for a session (status=active, count=0)
tmo watchdog disable <session>       # mark enabled=false (do not delete history)
```

All subcommands honor `$TMO_STATE_DIR` (set by orchestrator at session
start). Defaults to `$TMO_ROOT/state`.

## Cron entry (recommended)

```
*/10 * * * * /home/freek/.local/bin/tmo watchdog tick orchestrator >> /tmp/tmo-watchdog.log 2>&1
```

Tune the interval per workflow. 5 min = aggressive, 15 min = relaxed. The
state-machine is interval-agnostic; only `awaiting_user_count` thresholds
behave differently per cadence.

## Soft-inject mechanic

The action for `awaiting-user count>=2` and `idle-with-backlog` reuses the
existing `tmo note` soft-inject path (queued send-keys + 2-step Enter,
non-disruptive). This keeps pane interaction monomorphic and respects the
orchestrator's current turn boundary.

## Self-identification rule

Every soft-inject prefixes `[SIDENOTE HH:MM] [from watchdog]` so the
orchestrator can distinguish watchdog injections from user input or peer
messages.
