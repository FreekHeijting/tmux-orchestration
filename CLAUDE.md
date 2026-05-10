# tmux-orchestration repo - conventions

Applies to every Claude session that works in this repo or that installs/uses the `tmux-orchestration` skill.

## Purpose of this repo

Distributable source-of-truth for the `tmux-orchestration` Claude Code skill. Contains only the essential files needed to install and use the skill in a new workspace.

## File purpose (plugin structure)

| Path | Function |
|---|---|
| `.claude-plugin/plugin.json` | Plugin manifest (name, version, metadata) |
| `skills/tmux-orchestration/SKILL.md` | The skill itself. Auto-discovered by Claude Code |
| `skills/tmux-orchestration/references/` | Skill-internal reference (cheatsheet-excerpt) |
| `roles/*.md` | Canonical role definitions. Source of truth, referenced via `${CLAUDE_PLUGIN_ROOT}/roles/` |
| `bin/tmo` | CLI binary. Symlink to `~/.local/bin/tmo` after install |
| `tui/tui-rich.py` | Rich-based dashboard mockup. Optional runtime tool |
| `claude-md-blocks/` | Paste-able CLAUDE.md snippets for users (drop-in OR copy into existing) |
| `.vscode/tasks.json.template` | Per-workspace template for VS Code panel auto-spawn |
| `README.md` | Prerequisites + install (plugin OR manual) + quick start |
| `CLAUDE.md` | This file. Conventions for Claude sessions inside this repo |
| `LICENSE` | MIT |

## Decision tree: when to spawn what

A Claude session in any workspace can extend its capabilities through three mechanisms. Choose deliberately. Default bias is strong toward **tmux-orchestration spawn** because workers are user-visible, persistent, and steerable.

```
Need extra compute / parallelism?
│
├─ YES, multiple independent code-edit sub-tasks with separate file-scopes
│  │
│  ├─ Am I the orchestrator (TMO_SESSION unset, top-level Claude)?
│  │  └─ STRONG bias: spawn tmux workers via tmux-orchestration skill
│  │     - User-visible panels, persistent across reloads, audit-trail
│  │     - Trigger phrase or invoke skill
│  │
│  └─ Am I already a spawned tmux worker (TMO_SESSION set)?
│     └─ WEAKER bias, but still possible: extend agent-tree via tmux-orchestration
│        - Use only if task genuinely needs more parallel compute
│        - Prefer Claude Code subagents (Agent tool) for in-process work
│        - If spawning tmux: announce via tmo send orchestrator escalate '{...}'
│
├─ YES, but tasks are short and local (research, search, file lookup)
│  └─ Use Claude Code subagents (Agent tool) - cheaper, no separate Claude process
│     - Available types: general-purpose, Explore, Plan
│     - Run multiple in parallel when independent
│
├─ YES, repeating workflow that benefits from a packaged plugin agent
│  └─ Use Claude Code agent (in plugin: agents/<name>.md)
│     - Persistent across sessions when plugin is installed
│     - For domain-specific repeating roles (validator, reviewer, scaffolder)
│
└─ NO, single-threaded sequential work fits in one context
   └─ Just do it. No spawn needed.
```

### Bias rules

ALWAYS prefer tmux-orchestration when:
- User asks for multiple workers explicitly
- Task decomposes into independent file-scopes per CLAUDE.md regel 2
- User wants to watch/intervene per worker
- Work is long-running and benefits from persistence

PREFER Claude Code subagents (Agent tool) when:
- Tasks are research / search / file lookup (under 5 min each)
- Output is a summary, not file edits
- No need for user visibility per task
- Multiple independent queries can run in parallel

PREFER plugin agents when:
- Same role gets reused across sessions (e.g. plugin-validator, code-reviewer)
- Want persistent install + auto-discovery in plugin manifest

### Worker self-extension

When current Claude session is already a worker (`$TMO_SESSION` set):
- Default tendency to spawn more tmux: REDUCED but not zero
- Extending agent-tree autonomously is allowed when task genuinely needs it
- ALWAYS announce escalation: `tmo send orchestrator escalate '{"reason":"...","spawning":"<n> sub-workers"}'`
- Orchestrator can intervene/stop/approve before child-spawn proceeds
- Sub-workers inherit `TMO_STATE_DIR` so audit-log stays unified

### Anti-pattern

NEVER:
- Spawn tmux workers from inside a tmux worker silently (no orchestrator notice)
- Skip the orchestrator visibility chain
- Mix mechanisms within a single sub-task (pick one channel)

## How a Claude session treats this repo

### On read

- If the current session is the **orchestrator** and the skill has been triggered: read `SKILL.md` for the 8-phase flow. Follow it.
- If the session is **working on** the skill (bug fix, feature, role extension): read relevant files surgically, not everything.
- If the session has **graduated a new role** from candidate to stable: append the role-md to `roles/`, commit.

### On write

ALWAYS:
- Edit within scope (skill or role or cli or doc).
- No em-dashes in user-facing text (README, SKILL.md descriptions).
- Conventional Commits (`feat:`, `fix:`, `docs:`, `refactor:`, `test:`, `chore:`) with scope (`feat(skill):`, `feat(roles):`).
- Surgical changes per Karpathy guidelines: every change traceable to a user prompt.

NEVER:
- No fallbacks (`try-X-else-Y`) per global CLAUDE.md rule.
- No secrets/credentials.
- No runtime state files (`state/`, `*.log`) committed.
- No private files (`PROMPTS.md`, `CLAUDE.local.md`) committed.

### Quality-gate on changes to SKILL.md

- Re-run `skill-bench` (mentally or via a future skill-bench skill) on changes.
- Triggering tests: 6 positive, 4 negative, 5 functional.
- Pass-rate target: >= 0.9.
- On a functional change: bump version in frontmatter (`metadata.version`).

### Role-graduation flow

A new role arrives as `status: candidate`. After proven use (graduation criteria in SKILL.md Phase 4b):
1. Run ROLE-BENCHMARK (5 test tasks).
2. On pass-rate >= 0.8 and user approval: edit frontmatter `status: stable`.
3. Commit: `feat(roles): graduate <name> to stable`.
4. Push to remote.

## Install flow for a new user

Per `README.md`. The skill reads **roles directly from this repo path** (`~/GitHub/tmux-orchestration/roles/`), so the repo MUST be cloned at that exact location. README documents this.

## Privacy

`.gitignore` blocks: `state/`, `PROMPTS.md`, `SKILLS_LOG.md`, `CLAUDE.local.md`, `.vscode/*` (except `tasks.json` and `tasks.json.template`).

## Version + roadmap

Current skill version is in `SKILL.md` frontmatter `metadata.version`. Roadmap items (future):
- Extend `bin/tmo` with `tmo role-stat` subcommand for counter updates
- Migrate `helpers/tmux-multi-*` once a test needs them
- TUI dashboard (`tui/tui-rich.py`) once the mockup test passes
- `skill-bench` skill as a sidekick for automated testing + iterating
