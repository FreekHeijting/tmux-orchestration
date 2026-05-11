# Workspace mockup: tmux-orchestration

Living document. Reflects the current state of the repo's mechanics. Whenever
a new feature lands (CLI subcommand, hook, role, skill, workspace mechanic),
its mockup file under `mockup/<feature>.md` is created first, then this file
is updated to cross-reference it.

## Purpose

`tmux-orchestration` turns a Claude Code session into a persistent
orchestrator that drives N parallel Claude worker sessions in tmux, visible
in VS Code terminal-tabs. Cross-session state lives in `state/` (jsonl audit
log + yaml metadata). Workers self-claim tasks, self-bench against Karpathy,
and report back to the orchestrator for quality-gate.

## Repo file tree

```
tmux-orchestration/
├── .claude-plugin/
│   └── plugin.json              ← plugin manifest
├── .vscode/
│   ├── tasks.json               ← runOn:folderOpen → 4 attach-tabs
│   └── tasks.json.template
├── bin/
│   ├── tmo                      ← main CLI (init/spawn/send/task/etc)
│   └── skill-bench              ← Karpathy 5-task harness
├── hooks/
│   ├── hooks.json               ← UserPromptSubmit + SessionStart
│   └── scripts/
│       ├── auto-task-add.sh     ← every user prompt → tmo task add
│       └── sub-orch-claim.sh    ← SessionStart auto-claim TMO_TASK
├── skills/
│   ├── tmux-orchestration/
│   │   ├── SKILL.md
│   │   └── references/          ← inter-claude-comm, role-evolution, etc
│   └── skill-bench/
│       └── SKILL.md             ← Karpathy methodology
├── roles/
│   ├── orchestrator.md          ← stable
│   ├── backend.md               ← stable
│   ├── frontend.md              ← stable
│   ├── reviewer.md              ← stable
│   ├── generalist.md            ← stable
│   └── sub-orch-builder.md      ← candidate
├── bench/                       ← Karpathy bench yamls
├── mockup/                      ← this directory
│   ├── _STANDARD.md             ← flowchart-quality rules
│   ├── WORKSPACE.md             ← this file
│   └── <feature>.md             ← one per feature, design-first
├── examples/                    ← runnable examples per feature
├── tests/                       ← e2e + integration tests
├── CLAUDE.md                    ← workspace conventions
├── install.sh                   ← idempotent installer
└── state/                       ← gitignored, live runtime data
```

## State files (live runtime, gitignored)

```
state/
├── messages.jsonl              ← append-only audit forum (all peer-comm)
├── sessions.yaml               ← spawned tmux sessions metadata
├── tasks.jsonl                 ← append-only event-source (add/claim/update/done)
├── orchestrator-status.yaml    ← watchdog state per session
├── parked-questions.yaml       ← watchdog-parked unanswered prompts
├── backlog.yaml                ← watchdog work-pickup queue
├── inboxes/                    ← per-session inbox dirs
└── locks/                      ← file-locks for jsonl writes
```

### tasks.jsonl event types

| event   | fields                              | effect on replay-state          |
|---------|-------------------------------------|---------------------------------|
| add     | id, subject, desc, by, ts           | status=pending, owner=null      |
| claim   | id, owner, ts                       | status=in_progress              |
| update  | id, field, value, ts                | overwrite field (subject/desc/status) |
| done    | id, output, ts                      | status=completed                |

Replay rule: latest event per id wins. Re-derived on every read via `jq -s reduce`.

## CLI: tmo

```
tmo init                          initialize state/
tmo spawn <N> [--role R]          spawn N tmux+claude workers
tmo list-roles                    list roles/*.md
tmo send <to> <type> <payload>    write to inbox
tmo receive [--for S]             read from inbox
tmo wait-for <session> <event>    block until event
tmo note <session> <msg>          soft-inject sidenote into running claude
tmo task <action>                 add/list/get/claim/update/done
tmo watchdog <action>             tick/status/enable/disable
tmo statusline <session>          one-line status for tmux status-bar
tmo headerline <session> [1|2|3]  3-line task banner per session
tmo cleanup <session> [--task]    persist meta + kill tmux session
tmo session list-closed           list completed tasks with meta
tmo session reopen <task-id>      respawn from persisted meta
tmo session match <prompt>        score closed-meta against prompt
tmo context-check <session>       detect claude /compact warning
tmo bootstrap                     init + spawn + roles
```

## CLI: skill-bench

```
skill-bench gen <target> [out]    write 5-case template yaml
skill-bench score <bench-file>    pass-rate, exit 0 if >=0.8
```

## Hooks

```
UserPromptSubmit → hooks/scripts/auto-task-add.sh
  every user prompt → tmo task add (subject truncated 200ch)

SessionStart → hooks/scripts/sub-orch-claim.sh
  if TMO_TASK + TMO_SESSION + TMO_STATE_DIR set → auto-claim TMO_TASK
  idempotent + pre-flight check (refuses unknown task-ids)
```

## Skills

```
tmux-orchestration  → activated on keywords (tmux-orch, spawn workers, etc)
                      8-phase mandatory flow:
                      context → questions → live-check → role → workspace
                      → skill-hints → channels → spawn+runbook

skill-bench         → Karpathy 5-task methodology
                      categories: typical | edge-case | anti-pattern
                                  ambiguous-scope | cross-skill
                      threshold: pass-rate >= 0.8
```

## Roles

```
status: stable
  orchestrator    → top-orch behavior, dispatch, gate, kill, reopen
  backend         → server-side / API / data tasks
  frontend        → UI / browser tasks
  reviewer        → quality-gate reviewer
  generalist      → fallback

status: candidate
  sub-orch-builder → focused builder, file-scope isolation, Karpathy bench
                     mandatory, conventional commits, no fallbacks
```

## Sub-orch dispatch flow

```
        ⊙ user request
        │
        ▼
┌────────────────────────────────┐
│ orchestrator decomposes prompt │   (T-28 kanban-flow, mockup-first)
│ into N tmo tasks               │
└──────────────┬─────────────────┘
               │
               ▼
       ┌────────────────────┐
       │ confirm with user  │
       └─────────┬──────────┘
                 │ approved
                 ▼
       ┌─────────────────────────┐
       │ for each task: pick     │
       │ scope, role, worktree   │
       └─────────┬───────────────┘
                 │
                 ▼
┌─────────────────────────────────────┐
│ tmux new-session -d -s <name>       │
│   -c <worktree>                     │
│   "TMO_SESSION=<n>                  │
│    TMO_ROLE=sub-orch-builder        │
│    TMO_TASK=T-X                     │
│    TMO_STATE_DIR=... claude"        │
└────────────────┬────────────────────┘
                 │
                 ▼
       ┌──────────────────────┐
       │ SessionStart hook    │   (auto-claim TMO_TASK)
       │ → tmo task claim T-X │
       └──────────┬───────────┘
                  │
                  ▼
       ┌──────────────────────┐
       │ apply statusline +   │   (4-line tmux status-bar)
       │ headerline banner    │
       └──────────┬───────────┘
                  │
                  ▼
       ┌──────────────────────┐
       │ load-buffer +        │
       │ paste-buffer +       │
       │ Enter (2-step)       │
       └──────────┬───────────┘
                  │ dispatch prompt injected
                  ▼
       ┌──────────────────────┐
       │ sub-orch executes,   │
       │ commits, benches,    │
       │ sidenote done event  │
       └──────────┬───────────┘
                  │
                  ▼
       ┌──────────────────────┐
       │ orchestrator gates:  │
       │ approve → merge      │
       │ reject  → reinstruct │
       └──────────┬───────────┘
                  │
                  ▼
       ┌──────────────────────┐
       │ tmo cleanup <name>   │   (persist meta + kill tmux)
       └──────────┬───────────┘
                  │
                  ▼
                  ⊚

Legenda:
  ⊙ start  ⊚ end
  ─▶ transition
```

## Watchdog state-machine

```
[active] ──no-reply-1── [awaiting-user count=1]
                                  │
                                  ├── reply─▶ [active]
                                  │
                                  └── no-reply-2 ─▶ [park+next-task]
                                                          │
                                                          ▼
                                                     [active]
                                                     (working
                                                      next-task)
[idle-no-work]  ← session ack done, no backlog
[idle-with-backlog] ← session ack done, backlog non-empty
```

Tick interval: 240s active, 1200s slow-build, 1800s idle. Avoid exactly 300s
(prompt-cache TTL boundary).

Implementation: `tmo watchdog tick` + cron entry. Detects pane_in_mode
(copy-mode) per tick → auto `-X cancel` + log to messages.jsonl. Throttle:
600s between cancels per session.

## Peer-comm channels

```
Channel A (preferred, user-visible):
  tmux load-buffer -b peer-${TMO_SESSION}-$(date +%s%N) /tmp/msg.txt
  tmux paste-buffer -b <buf> -t <peer>:0.0
  tmux send-keys -t <peer>:0.0 Enter
  body prefixed: "[from $TMO_SESSION] ..."

Channel B (orchestrator-routed):
  worker → tmo note orchestrator "..."
  orchestrator → tmo note <other-worker> "[from <a>] ..."

Channel C (audit, always-on):
  tmo send <to> <type> <payload>
  appends to state/messages.jsonl
  no prompt-injection, but persistent record
```

7 edge-cases empirically tested in
`skills/tmux-orchestration/references/inter-claude-comm.md`.

## Quality gate

- sub-orchs MUST self-bench via skill-bench (Karpathy 5-task) before signaling done
- pass-rate >= 0.8 to graduate
- orchestrator reviews bench yaml + commit-diff + e2e output before merge
- merge --no-ff to main with descriptive message
- install.sh reinstall after merge (idempotent symlink + skill files sync)

## Cross-refs

- `mockup/kanban-flow.md` — T-28 decompose/review/approve/board flow (next)
- `mockup/_STANDARD.md` — flowchart quality rules (this dir)
- `skills/tmux-orchestration/SKILL.md` — 8-phase flow + hard rules
- `roles/sub-orch-builder.md` — sub-orch binding rules
- `bench/skill-bench-self-v0.1.yaml` — founding bench

## Status

- mockup: draft (foundation file, expand as features land)
- impl:   most mechanics live on main (statusline, headerline, cleanup, hooks)
- bench:  10 yamls in bench/, all 5/5 PASS where committed
