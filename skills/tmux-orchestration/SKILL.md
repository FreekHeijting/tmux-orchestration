---
name: tmux-orchestration
description: >
  Triggers on "tmux-orchestration", "tmux orchestration", "spawn workers",
  "start N workers", "orchestrator + workers", "current session as orchestrator",
  "current session becomes orchestrator", "multi-claude orchestration with live sessions",
  "I want multiple claudes in parallel with roles", "spawn N tmux workers with role-context".
  Use when current Claude session must become a persistent orchestrator that drives N
  named worker-claude sessions in tmux, each with assigned role-md, file-scope, initial
  task, skill-hints, and quality-gate supervision. The skill forces a mandatory question
  flow before spawning, scans live tmux sessions, writes/loads roles from
  ${CLAUDE_PLUGIN_ROOT}/roles/, ensures workspace state files exist
  (state/messages.jsonl as central forum), supports cross-workspace workers via shared
  TMO_STATE_DIR, and provides a quality-gate loop with APPROVE / RE-INSTRUCT / REPLACE
  decisions. Distinct from tmux-multi-orchestrator which is one-shot parallel fanout
  (brainstorm/critique/synthesis) without persistent orchestrator-driven workflow,
  roles, file-scope-isolation, or quality-gate. Use this skill for role-based +
  persistent + file-scope-isolated orchestration. Use tmux-multi-orchestrator for
  ad-hoc parallel A/B/C-style fanout. Keywords tmux, orchestrator, workers,
  multi-claude, parallel-with-roles, spawn, dispatch, role-md, worker-context,
  message-bus, central-forum, orchestrator-runbook, quality-gate, re-instruct,
  replace-worker, peer-injection, jsonl, state-file, file-scope, sync-point,
  cross-workspace, vs-code-panels, tasks-json, prompt-improver-enforced.
license: MIT
metadata:
  author: Impertio.Studio
  version: "0.4.0"
  related-skills: tmux-multi-orchestrator, superpowers:writing-plans, superpowers:brainstorming, superpowers:dispatching-parallel-agents
  cheatsheet: ~/Bureaublad/TMO_CHEATSHEET.html
  cli: ~/GitHub/tmux-orchestrator/bin/tmo
---

# Tmux Orchestration

Current Claude session becomes orchestrator. Spawns N tmux worker-sessions, each running its own claude with a role + file-scope + initial context. Orchestrator drives workers via `tmo send`, captures their output, evaluates quality, re-instructs or replaces failing workers. All inter-session communication goes through workspace state-files (auto-created if missing).

## Assumed environment

User ALWAYS works in VS Code on Linux. Workers MUST be visible to the user. Spawning a worker without making it visible is a bug. Default visibility-flow per spawn (no extra question needed):

1. Spawn detached tmux session (`tmux new-session -d -s <name>`).
2. ALWAYS append/update `.vscode/tasks.json` with one task per worker plus composite `tmo:start-all` (runOn folderOpen).
3. ALWAYS update `.gitignore` to include `!.vscode/tasks.json` so the config is shareable.
4. ALWAYS open the worker as a visible window NOW (do not wait for user to manually run task):
   - Try VS Code panel auto-trigger via `code --command workbench.action.tasks.runTask <task-label>` (best effort, may noop on some setups).
   - Fall back: `gnome-terminal --window --title="tmo:<name>" -- bash -lic "tmux attach -t <name>"` opens external visible window.
   - Both = belt-and-braces. User sees it either way.
5. Tell user: panel is open. To dock it inside VS Code permanently, run `Tasks: Run Task → tmo:<name>` once.

If `.vscode/tasks.json` does not exist in the workspace: skill writes it (template from `~/GitHub/tmux-orchestrator/.vscode/tasks.json`), updates `.gitignore`, and proceeds with step 4 above. NEVER stop after writing tasks.json without making the worker visible.

## ALWAYS / NEVER

- ALWAYS run the 8-phase flow in order. Skip nothing. Each phase has a verify-condition.
- ALWAYS ask the mandatory questions in Phase 2 via `AskUserQuestion`. No defaults, no shortcuts.
- ALWAYS use 2-step Enter when injecting prompts: text first, then Enter as separate `tmux send-keys` call, with `sleep 0.2` between.
- ALWAYS spawn workers in the orchestrator's workspace (`-c <cwd>`) unless user explicitly assigns a different workspace per worker.
- ALWAYS ensure `state/messages.jsonl` + `state/sessions.yaml` exist before spawning. Auto-run `tmo init` in target workspace(s) if absent.
- ALWAYS hand each worker a context-bundle including its role, file-scope, communication protocol, and skill-hints.
- ALWAYS verify spawn success via `capture-pane` per worker before reporting completion.
- ALWAYS run the quality-gate loop after each worker-output: approve / re-instruct / replace.
- NEVER kill an existing tmux session without explicit user confirmation. Show the live-session list, ask per-session.
- NEVER write to a file outside a worker's declared file-scope. Two workers on the same file is forbidden per CLAUDE.md rule 2.
- PREFER direct peer-injection: worker A places prompt in worker B's REPL via `tmux send-keys` (2-step) so the user sees it happen on screen. ALWAYS pair this with `tmo send` audit-log so `state/messages.jsonl` records the peer-traffic.
- ALWAYS self-identify in the injected prompt body, prefix with `[from <$TMO_SESSION>]`. Example: `[from tui-builder] can you confirm the schema for users.role?`. This way the receiver knows which peer is asking without parsing audit-log. Receiver replies with `[from <self>]` prefix as well.
- ALWAYS fall back to orchestrator-routed message when direct peer-injection fails (peer session missing, paste-buffer locked, target not in claude-prompt state). Worker emits `tmo send orchestrator forward '{"to":"<peer>","payload":...}'` and continues with own work.
- ALWAYS treat `state/messages.jsonl` as the central forum: orchestrator tails it, peer-traffic + status + decisions all land here, immutable append-only audit-trail.
- ALWAYS use `tmo task` as the single source of truth for every actionable work-item across the orchestration. Lifecycle is mandatory:
  1. Orchestrator dispatches a sub-task: `tmo task add "<subject>" --by orchestrator` BEFORE bundle-injection. Capture the returned `T-<id>`.
  2. Worker context-bundle MUST include a `## tmo task ID\nT-<id>` section so the worker knows which task to claim.
  3. Worker first action after consuming bundle: `tmo task claim T-<id> --by <self>`.
  4. Worker per phase: `tmo task update T-<id> status in_progress` (or whatever the phase reports).
  5. Worker on completion: `tmo task done T-<id> --output "<sha or summary>"`.
  6. Quality-gate verdict: orchestrator runs `tmo task update T-<id> status approved` (or `rejected`) AFTER reviewing.
  Watchdog backlog reads `tmo task list --status pending`; if a task lives only as a Claude session-local TaskCreate item and not in `tmo task`, idle pickup is broken. Therefore: `tmo task` events MUST exist for every work-item.
- NEVER use Claude Code's session-local TaskCreate as the only tracker for plugin work. Session-local UI is fine, but every plugin action MUST also exist in `tmo task`. If they diverge: `tmo task` wins.
- NEVER skip the prompt-improver hook in any worker session. If a worker sees `[PROMPT-IMPROVER ACTIVE]` it MUST run the improvement-flow.
- ALWAYS default-accept prompt-improver suggestions in worker sessions (auto-respond with the affirmative literal for the configured reply-language: `yes` for English, `ja` for Nederlands, user-supplied for Other). Worker only deviates from this default if the improver suggestion is verifiably wrong (then `fix: <correction>`).
- NEVER add fallback paths in worker logic ("if X fails, try Y") for code/tasks. Per global CLAUDE.md: root-cause first, fix at the responsible place. The orchestrator-routed fallback for inter-worker comm is the ONE exception, because it has a semantic meaning (peer unreachable = orchestrator-aware).
- NEVER write a long single-line prompt directly via `send-keys` if it contains newlines. Use `load-buffer` + `paste-buffer` + Enter.
- ALWAYS detect tmux copy-mode hangs: when a worker pane shows `pane_in_mode == 1` (user scrolled up in the gnome-terminal window) the user may perceive the session as stuck even though the agent is fine. Orchestrator runs `tmux send-keys -t <session> -X cancel` to drop the pane back to live cursor. Never re-spawn the window over a visual-only scroll-state. Watchdog SHOULD include this check per tick (future task).
- ALWAYS decompose every new user-request into N tmo task entries BEFORE any worker dispatch or code-edit. Single-intent prompts: keep as one task but enrich the desc with **what was literally asked**, **why / context**, **success criteria**, and **scope / constraints**. Multi-intent prompts: run `tmo task decompose <raw-id> "sub1" "sub2" ...`, show the proposed split to the user, ask `ja / skip / fix: <correction>`, only proceed after explicit confirmation. The raw prompt-task auto-closes with `output="decomposed → T-X, T-Y, ..."`. Reason: user-requests must never silently lose intent in a long dispatch chain; the kanban is the source of truth.
- ALWAYS create `mockup/<feature>.md` with a flowchart (per `mockup/_STANDARD.md`) BEFORE the first implementation commit for any new CLI subcommand, hook, role, skill, or workspace-level mechanic. Mockup contains: purpose, flowchart, state-diagram (if stateful), CLI signatures, schema changes, open questions, status. Implementation commit body must reference the mockup file. Sub-orchs honor this rule too: their dispatch prompt explicitly tells them to land the mockup file first, get orchestrator confirm, then build. Reason: design is communicated visually before code, so the user sees the intent before the diff.
- ALWAYS route every sub-orch finished work through the verplichte `review` status: sub-orch runs `tmo task review T-X --evidence "<sha> + bench-rate + capture-pane url"`. Orchestrator gates with `tmo task approve T-X` (followed by `tmo task done T-X --output "<merge-sha>"`) or `tmo task reject T-X --reason "<text>"`. Reject loops the task back to `in_progress` and re-instructs the sub-orch via `tmo note`. Sub-orchs MUST NOT call `tmo task done` directly; that command is reserved for the orchestrator after approve. Reason: quality-gate is non-skippable + always visible in `tmo task board`.

## The 8 phases

### Phase 1 - Context snapshot

Read the orchestrator's context. Goal: orchestrator can cite the existing plan and constraints back to the user before spawning anything.

Read in this order, only if present:
1. `CLAUDE.md` (workspace root + parent `~/GitHub/CLAUDE.md`)
2. `ROADMAP.md`, `HANDOFF.md`, `LESSONS.md`, `DECISIONS.md`
3. `.claude/state/_active.yaml` (Workspace Memory Protocol active entries)
4. `plans/*.md` (most recent first)
5. `git log --oneline -20`
6. Current `TaskList` (TaskGet)

Verify: orchestrator produces a 5-line summary of (a) what user is building, (b) which plan is active, (c) what's blocking, (d) which constraints apply, (e) which skills are already loaded. If user has not written a plan yet OR plan does not decompose into independent file-scopes: STOP. Offer to invoke `superpowers:writing-plans` first.

### Phase 2 - Mandatory questions

API constraint: `AskUserQuestion` accepts max 4 questions per call, each with 2-4 fixed options. Free-text only via "Other" auto-option or via regular chat ask. Phase 2 splits into 3 stages.

**Stage A** - one `AskUserQuestion` call with 4 single-select questions:

| # | Question | Header | Options |
|---|----------|--------|---------|
| 1 | How many workers? | Worker count | 1 / 2 / 3 / 4-or-5 |
| 2 | Spawn target? | Spawn target | VS Code panels (default) / standalone tmux |
| 3 | Skill-hints scan? | Skill scan | Yes (recommended) / Skip |
| 4 | Quality-gate cadence? | QG cadence | Every worker reply / At sync-points only |

**Stage A2** - reply-language (one extra `AskUserQuestion` call). Repo content is always English, but user-facing replies (orchestrator status, summaries, prompts) can be in the user's preferred language:

| # | Question | Header | Options |
|---|----------|--------|---------|
| 1 | Reply language? | Reply language | English / Nederlands / Other |

The chosen language flows into every worker's context-bundle so workers reply in the same language. Worker rule for the prompt-improver default-accept literal adjusts to language:
- `English` → respond `yes`
- `Nederlands` → respond `ja`
- `Other` → ask user once for the affirmative literal in their language, then use it

**Stage B** - one `AskUserQuestion` call with up-to-4 questions, 1 per worker (worker count from Stage A determines how many): role per worker as single-select (`orchestrator` / `backend` / `frontend` / `reviewer`). User picks "Other" + types a custom role-name to trigger new-role-creation in Phase 4.

If N>=5: split Stage B into 2 calls of 4 + 1.

**Stage C** - regular chat ask (no AskUserQuestion). Orchestrator emits one prompt block:

```
Per worker, provide in this format (1 line per worker):
worker-1: file-scope=<paths>, workspace=<absolute-path-or-default>, initial-task=<one-paragraph>
worker-2: file-scope=<paths>, workspace=<absolute-path-or-default>, initial-task=<one-paragraph>
...
Comm-mode: jsonl-only / jsonl+tmux-direct (default)
```

Wait for free-text reply, parse it.

Verify: all answers captured for all N workers. If N>=4: emit warning about Anthropic-quota share. If 2 workers declare overlapping file-scope: STOP, refuse, return to Stage C.

### Phase 3 - Live-session check

Run `tmux ls` (parse output, ignore errors when no server). For each existing session:
- Show name + last-attached + last-activity (capture-pane tail)
- Ask via `AskUserQuestion`: keep / reattach-as-worker / kill / rename

Verify: every existing session has an explicit user-decision. No silent re-use, no silent kill.

### Phase 3b - Branching strategy per worker

For each task being dispatched: ALWAYS ask "is this work big enough to live on its own feature-branch?". Default answer YES when ANY of:
- Multi-phase Karpathy plan with verify-conditions
- Adds a new CLI subcommand, file, or module
- Touches >2 files
- Will be reviewed/merged in a single review

Default answer NO when:
- Single-line typo / docstring fix
- Hot-fix on a release branch
- Sandbox/throwaway test that won't be committed

When YES: instruct worker to `git checkout -b feat/<topic>` (or `fix/`, `docs/`, `refactor/`) before first commit, push branch on first commit (`git push -u origin <branch>`), commit per phase, mention branch in every status report. Top-orchestrator reviews + merges via PR or fast-forward.

When NO: worker commits directly on current branch.

The skill MUST surface this question explicitly to the user once per task-dispatch round. Skipping = reverting to per-worker default which is feature-branch.

### Phase 4 - Role assignment

For each worker, resolve role:
- Existing role: read `${CLAUDE_PLUGIN_ROOT}/roles/<role>.md`. Inject as initial context.
- New role: run **ROLE-DEFINITION-FLOW** (3-stage: 4-question multi-choice + free-text spec + auto-name-proposal). See `references/role-evolution-loop.md` for full flow + role-template + naming-convention.

Verify: every worker has a resolved role-md path. New roles exist on disk in repo with `status: candidate`.

### Phase 4b - Role evolution loop

After each worker-output evaluation in the quality-gate loop, increment the role's frontmatter counters via `tmo role-stat <role> approve|reinstruct|replace` (or direct Edit-tool if subcommand absent).

**Graduation criteria** (default `3-uses-low-correction-rate`): `usages >= 3` AND `replace_count == 0` AND `reinstruct_count * 2 <= usages`.

When eligible OR at end-of-session cleanup: run **ROLE-BENCHMARK** (Karpathy autoresearch). 5 test-tasks across categories: typical, edge-case, anti-pattern-attempt, ambiguous-scope, cross-skill. Score Y=1.0 / P=0.5 / N=0.0. If `>= 0.8`: AskUserQuestion to promote candidate → stable. On Yes: frontmatter update + commit `feat(roles): graduate <role> to stable` + push.

Full benchmark-categories, role-template, scoring-rules: `references/role-evolution-loop.md`.

### Phase 5 - Workspace assignment

For each worker:
- Default: orchestrator cwd
- Cross-workspace: user supplied path. Verify path exists + is git repo (warn if not).

If worker's workspace differs from orchestrator's: communicate via shared state path. Set `TMO_STATE_DIR=<orchestrator-cwd>/state` in the worker's spawn env. All workers, regardless of workspace, write to and read from the same `messages.jsonl`.

Verify: every worker has a resolved workspace path. Cross-workspace workers have `TMO_STATE_DIR` configured.

### Phase 6 - Skill-hints scan

For each worker, scan available skills and produce a hint-list of skills the worker should ACTIVELY use during its work.

Sources to scan (in order):
1. `~/.claude/skills/` (global personal)
2. `<workspace>/.claude/skills/` (project-level)
3. `~/GitHub/*-Claude-Skill-Package/skills/source/**/SKILL.md` (cloned packages)

Match skill `description` field against worker's role + initial-task. For every match: add to worker's context-bundle:

```
Use skill: <skill-name>
When: <one-line trigger condition copied from skill description>
```

Verify: every worker has at least one skill-hint OR an explicit "no skill matches".

### Phase 7 - Communication channels (auto-create)

Ensure these files/dirs exist in the orchestrator workspace's `state/` dir. Two-step creation: `tmo init` for files it owns, then plain `mkdir` for what tmo CLI does not yet manage.

| Path | Owned by | Purpose |
|------|----------|---------|
| `state/messages.jsonl` | `tmo init` | Central forum: append-only event log (orchestrator + workers) |
| `state/sessions.yaml` | `tmo init` | Session metadata + status per worker |
| `state/inboxes/` | `mkdir -p` | Per-worker filtered inbox dir. Files appended on first send. |
| `state/locks/` | `mkdir -p` | File-scope claim locks dir |

Bash (idempotent):

```bash
# 1. tmo init for messages.jsonl + sessions.yaml
tmo init    # noop if state/ already initialized

# 2. extra dirs the skill manages directly
mkdir -p state/inboxes state/locks
```

If `tmo init` fails: STOP, root-cause (missing dependency: tmux/jq/claude, permission, missing tmo on PATH). Do not proceed with spawn.

Verify: `test -f state/messages.jsonl && test -f state/sessions.yaml && test -d state/inboxes && test -d state/locks` returns 0.

### Phase 8 - Spawn + orchestrator-runbook

Two spawn-modes depending on Stage A Q2.

#### Mode A - VS Code panels (default)

1. Write/update `.vscode/tasks.json` with one task per worker plus a composite. Template under `~/GitHub/tmux-orchestrator/.vscode/tasks.json`. Each per-worker task runs `tmux new-session -A -s <name> -c <workspace> 'TMO_SESSION=<name> TMO_STATE_DIR=<orchestrator-state-dir> claude'`. Composite uses `dependsOrder: parallel` and `runOptions.runOn: folderOpen`.
2. Update `.gitignore` to allow tasks.json: add `!.vscode/tasks.json`.
3. Tell user: run `Tasks: Run Task -> tmo:start-all` once now (later folder-opens auto-spawn).
4. Wait until VS Code panels report claude is up. Detect via `tmux capture-pane -t <name>:0.0 -p` containing `Welcome` or the prompt indicator (`❯` or `>`). Loop with timeout:

```bash
for w in <workers>; do
  for i in $(seq 1 30); do
    tmux capture-pane -t "$w:0.0" -p 2>/dev/null | grep -qE 'Welcome|❯|^> $' && break
    sleep 1
  done || { echo "worker $w never ready"; exit 1; }
done
```

5. Inject context-bundle per worker using FILE-based load-buffer (robust against quotes/backticks):

```bash
# write bundle to file (clean handling of quotes/newlines/multiline)
cat > /tmp/tmo-bundle-<name>.txt <<'BUNDLE_EOF'
<bundle text here>
BUNDLE_EOF

tmux load-buffer -b ctx-<name> /tmp/tmo-bundle-<name>.txt
tmux paste-buffer -b ctx-<name> -t <name>:0.0
sleep 0.5
tmux send-keys -t <name>:0.0 Enter
tmux delete-buffer -b ctx-<name>
rm /tmp/tmo-bundle-<name>.txt
```

#### Mode B - standalone tmux (fallback, no VS Code)

```bash
tmux new-session -d -s <name> -c <workspace> "TMO_SESSION=<name> TMO_STATE_DIR=<orchestrator-state-dir> claude"
# same readiness-loop + bundle injection as Mode A
# user attaches separately: tmux attach -t <name>
```

#### Orchestrator-runbook (after spawn)

Hold in-memory (do not write to file unless user asks):

1. Worker-table: name | role | workspace | file-scope | initial-task
2. Dispatch-order: which `tmo send` calls in which order
3. Sync-points: `tmo wait-for <worker> <event>` calls
4. Quality-gate criteria per worker (concrete pass/fail conditions)
5. Skill-hints per worker
6. Polling-cadence per Stage A Q4 (every-reply or sync-points-only)

Verify: per worker, `tmux capture-pane -t <name>:0.0 -p | tail -10` shows claude has consumed bundle (no error, prompt-line free again). `state/sessions.yaml` lists all workers with status `idle` or `working`. Orchestrator self-test: emit one `tmo send <worker> ping '{"t":"<ts>"}'` to first worker, expect `tmo wait-for <worker> pong` within 60s.

## Quality-gate loop

Trigger source depends on Stage A Q4:
- **every-reply**: orchestrator polls each worker every N seconds (default 30s) via `tmux capture-pane`. Detect new output by tail-diff vs last snapshot.
- **sync-points-only**: orchestrator listens for explicit `done` / `blocked` / `need-review` events in `state/messages.jsonl` (tail with `tmo receive` loop).

Per evaluation cycle, for each worker with new output:

1. Capture: `tmux capture-pane -t <worker>:0.0 -p -S -200 | tail -100`
2. Evaluate against worker's task + ALWAYS/NEVER rules + role-responsibility + file-scope (was anything outside scope claimed?)
3. Decide and act:

| Decision | When | Action |
|---|---|---|
| **APPROVE** | Output coherent + on-task + within file-scope | `tmo send <worker> status '{"verdict":"approved"}'` and continue. |
| **RE-INSTRUCT** | Partially right but wrong path / minor scope drift | Build correction-prompt (cite the deviation). Use file-based load-buffer + paste-buffer + 2-step Enter into worker's pane. Log `tmo send <worker> reinstruct '{"reason":"...","correction":"..."}'`. |
| **REPLACE** | Worker stuck, wrong role, context corrupted, repeated failures (>=2 RE-INSTRUCTs ignored) | `tmux kill-session -t <worker>`. Re-spawn via Phase 8 with same role-md but improved context (lesson embedded). Log `tmo send orchestrator replace '{"old":"<worker>","reason":"..."}'`. |

Counters:
- Track per worker: `reinstruct_count`, `replace_count`. After 2 REPLACE on same worker-name: STOP, escalate to user.
- Never silently let a worker continue with bad output.

## Worker context bundle template

Inject this into each worker as initial prompt (via load-buffer + paste-buffer):

```
You are worker <name> with role <role>.

## Reply language
<English | Nederlands | Other:<literal>> - reply to user in this language. Repo content stays English.


## Workspace
<absolute-path>

## File-scope (HARD GATE)
You may write/edit ONLY these paths:
- <allowed-path-1>
- <allowed-path-2>
NEVER edit any other path. If your task requires it: emit `tmo send orchestrator blocked '{"need":"<path>"}'` and stop.

## Communication
- Inbox: read with `TMO_SESSION=<name> tmo receive`
- Send to peer (preferred direct): tmux load-buffer + paste-buffer + 2-step Enter into peer's pane. ALWAYS audit-log via `tmo send <peer> peer-prompt '{"from":"<self>","mode":"direct",...}'`.
- Send to peer (fallback): `tmo send orchestrator forward '{"to":"<peer>","payload":...}'` — orchestrator routes when direct fails.
- Send to orchestrator: `tmo send orchestrator <type> '<json-payload>'`
- Status updates: `tmo send orchestrator status '{"phase":"working"}'`
- All messages persist in state/messages.jsonl. Central forum. Audit-trail.

## Prompt-improver enforcement (CRITICAL)
If you see `[PROMPT-IMPROVER ACTIVE]` in any UserPromptSubmit hook context: NEVER skip the improvement-flow. ALWAYS:
1. Write improved version with `[INFERRED: ...]` tags
2. Show diff
3. Default response is `ja` (accept improved version)
4. Only respond `fix: <correction>` if a specific tag is verifiably wrong
5. NEVER respond `skip` unless user explicitly typed it themselves

## tmo task ID
T-<id>

(Mandatory. Worker first action after this bundle: `tmo task claim T-<id> --by <self>`. Update status per phase via `tmo task update T-<id> status <state>`. End with `tmo task done T-<id> --output "<sha or summary>"`. NEVER finish without a `done` event.)

## Initial task
<one-paragraph task derived from orchestrator plan>

## Skills to actively use
- <skill-name>: <trigger condition>
- <skill-name>: <trigger condition>

## Role guide
<full content of roles/<role>.md inlined>

## ALWAYS / NEVER
- ALWAYS report status changes via tmo send.
- ALWAYS check inbox before starting next sub-task.
- NEVER edit files outside file-scope.
- NEVER spawn additional tmux sessions.
- When done: `tmo send orchestrator done '{"output":"..."}'` and idle.

Begin.
```

## Inter-worker communication

Two channels, BOTH used together. State-file is the central forum (audit), direct peer-injection is the user-visible action.

### Channel 1 (preferred) - Direct peer-injection

Worker A places a prompt directly in worker B's claude REPL via tmux. User sees it appear in B's panel. Lowest latency, full visibility.

```bash
# worker-A injects question into worker-B
PROMPT="[from worker-A] Q: can you confirm the schema for users.role?"
echo "$PROMPT" | tmux load-buffer -b peer-A-to-B -
tmux paste-buffer -b peer-A-to-B -t worker-B:0.0
sleep 0.2
tmux send-keys -t worker-B:0.0 Enter
tmux delete-buffer -b peer-A-to-B

# ALWAYS audit-log alongside
tmo send worker-B peer-prompt '{"from":"worker-A","prompt":"...","mode":"direct"}'
```

### Channel 2 (fallback) - Orchestrator-routed

Use when direct peer-injection fails (peer session not found, peer not in claude-prompt state, paste-buffer locked):

```bash
tmo send orchestrator forward '{"to":"worker-B","payload":{"prompt":"Q from worker-A: ..."}}'
```

Orchestrator tails `state/messages.jsonl`, sees the `forward` request, performs the injection on behalf of worker-A. Logs `forward-completed` back. If orchestrator is busy: queued in jsonl until orchestrator catches up.

### Channel 3 (always-on) - Audit forum

`state/messages.jsonl` is the central forum. Every peer-action lands here regardless of channel used. Orchestrator reads this stream to detect:
- Peer-traffic patterns (excessive back-and-forth = workers stuck)
- Status updates (idle/working/blocked/done)
- Quality-gate triggers
- Forwarded prompts that need orchestrator-action

Orchestrator never relies on direct send-keys to detect work. Only on the jsonl stream.

## Anti-patterns

| Anti-pattern | Why bad | Correct |
|---|---|---|
| Skip mandatory questions, use defaults | User intent unclear, file-scope conflicts likely | Always run AskUserQuestion in Phase 2 |
| Auto-kill stale sessions | Destructive, may lose state | Show + ask per session in Phase 3 |
| Two workers, overlapping file-scope | Race conditions, lost edits | Phase 2 Q3 catches this. Refuse spawn. |
| Direct `tmux send-keys` peer-injection WITHOUT audit-log | Orchestrator blind to peer-traffic, no replay | Always pair direct injection with `tmo send <peer> peer-prompt '{"from":"<self>","mode":"direct"}'` |
| Single-line prompt with embedded `\n` via send-keys | Each line submits separately | Use load-buffer + paste-buffer |
| Worker writes to peer's file-scope | File-scope violation | Worker must `tmo send orchestrator blocked` instead |
| Silent retry on bad worker output | Drift accumulates | Quality-gate loop: APPROVE / RE-INSTRUCT / REPLACE |
| Hardcoded sleep waiting for claude prompt | Flaky | `until capture-pane | grep -q '❯'; do sleep 1; done` |

## Cheatsheet

Full reference card: `~/Bureaublad/TMO_CHEATSHEET.html`. Includes: tmo CLI subcommands, tmux essentials, send-keys patterns, multiline injection, capture/observe, role list, state-file schemas, helper-scripts, troubleshooting, cleanup.

## v1 test in blank session

Recommended smoke-test for verifying the skill works end-to-end:

1. Open new VS Code window in any workspace where you have a project (any of `~/GitHub/*`).
2. Start blank Claude Code session in that workspace.
3. User types: `tmux-orchestration` (the literal trigger word).
4. Skill loads. Phase 1 produces context-summary.
5. Phase 2 asks 8 questions. Suggested test answers:
   - N=2 workers
   - roles: `backend` + `reviewer`
   - file-scope: backend → `src/api/`, reviewer → read-only
   - workspace: same as orchestrator (default)
   - comm: jsonl + tmux-direct
   - spawn: VS Code panels (default)
   - skill-scan: yes
   - QG cadence: every reply
6. Phase 3 detects existing tmux sessions. Test answer: keep all, no kills.
7. Phase 4-7: skill writes/finds roles, configures workspaces, scans skills, ensures `state/` files.
8. Phase 8: spawns 2 panels, injects context-bundles, verifies via capture-pane.
9. Test direct peer-injection: ask orchestrator to have backend ask reviewer a question. Verify it appears in reviewer panel.
10. Test fallback: kill backend session, then have orchestrator try to forward a question on behalf of a (no longer existing) backend. Verify orchestrator-routed fallback path.
11. Test quality-gate: feed backend an intentionally wrong sub-task. Orchestrator should detect, choose RE-INSTRUCT or REPLACE.
12. Verify `state/messages.jsonl` has audit-trail of every peer-action.
13. Cleanup: `tmux kill-session` per worker, archive `state/messages.jsonl` if useful.

## See also

- `tmux-multi-orchestrator` skill — pure parallel fanout (chat/chat2/chat3 brainstorm/critique/synthesis pattern). Use when no persistent orchestrator-driven workflow needed.
- `superpowers:writing-plans` — invoke before this skill if user has no plan yet.
- `superpowers:dispatching-parallel-agents` — for in-process subagents without tmux (cheaper, no separate claude instances).
- `superpowers:brainstorming` — when scope is unclear before orchestration.
- `references/cheatsheet-excerpt.md` — short version of the desktop HTML cheatsheet.
