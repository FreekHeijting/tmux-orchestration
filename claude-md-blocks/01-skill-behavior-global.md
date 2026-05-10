<!--
BLOCK: tmux-orchestration skill behavior (global)

Paste in: ~/.claude/CLAUDE.md (user-global instructions)
OR: workspace-level CLAUDE.md if you only want this in one project
OR: standalone read by Claude when relevant

Purpose: enforce skill behaviors that must hold even when the skill is not actively loaded into context.
-->

## tmux-orchestration skill behavior

When the `tmux-orchestration` skill is active OR when a Claude session is running as a worker (`$TMO_SESSION` is set), these rules apply:

### Worker sessions

- ALWAYS check the `$TMO_SESSION` env var at session start. If set: you are a worker. Read your context bundle (the first user prompt after claude startup). Follow it.
- ALWAYS report status via `tmo send orchestrator status '{"phase":"working|done|blocked"}'` at every phase transition.
- ALWAYS check your inbox first: `TMO_SESSION=$TMO_SESSION tmo receive` before starting a new task.
- ALWAYS edit only inside your declared file-scope. Outside scope = `tmo send orchestrator blocked` and stop.
- NEVER spawn additional tmux sessions from a worker.
- NEVER edit files inside a peer worker's file-scope.
- NEVER skip prompt-improver hooks. On `[PROMPT-IMPROVER ACTIVE]`: run the improvement flow, default-respond `ja` (accept the improved version).

### Inter-worker communication

- PREFER direct peer-injection: use `tmux load-buffer + paste-buffer + 2-step Enter` to place a prompt in the peer worker's pane. ALWAYS pair with `tmo send <peer> peer-prompt '{"from":"<self>","mode":"direct"}'` for the audit log.
- On failure of direct peer-injection: ALWAYS fall back via `tmo send orchestrator forward '{"to":"<peer>","payload":...}'`.
- ALWAYS treat `state/messages.jsonl` as the central forum + audit-trail.

### Quality-gate (orchestrator side)

- ALWAYS evaluate worker output: APPROVE / RE-INSTRUCT / REPLACE.
- NEVER let a worker silently continue with bad output.
- On REPLACE: `tmux kill-session` + re-spawn with an improved context bundle.
