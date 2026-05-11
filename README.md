# tmux-orchestration

Claude Code skill that turns the current Claude session into a persistent orchestrator driving N parallel worker-Claude sessions in tmux. Each worker has an assigned role, file-scope, initial task, skill-hints, and quality-gate supervision.

Designed for VS Code on Linux. Workers spawn as VS Code integrated terminal panels.

## What you get

- 8-phase mandatory flow before any spawn (context snapshot, mandatory questions, live-session check, role assignment, workspace assignment, skill-hint scan, communication channels, spawn + runbook)
- Kanban task tracker (`tmo task`): pending → in_progress → review → completed with `decompose`, `review`, `approve`, `reject`, `board` subcommands. Sub-orchs MUST NOT call `done` directly; reserved for orchestrator after `approve`
- Auto-task capture: every user prompt becomes a `tmo task` via `UserPromptSubmit` hook, with last 3 prompts prepended as context
- Auto-claim on spawn: `SessionStart` hook auto-claims `TMO_TASK` if set in env
- Karpathy 5-task bench harness (`skill-bench`): every new feature self-benches; >= 0.8 pass-rate to graduate
- Mockup-first workflow: every new feature lands `mockup/<feature>.md` with flowchart BEFORE first impl commit
- Three communication channels: direct peer-injection (user-visible), orchestrator-routed fallback, append-only audit-forum (`state/messages.jsonl`)
- File-scope isolation per worker; sub-orchs run in git worktrees
- Cross-workspace workers share state via `TMO_STATE_DIR`
- Per-session tmux 4-line status-bar: session, role, task-id, state, peer-traffic count, git branch, current dir, first sentence of task desc
- Live session cleanup + reopen: `tmo cleanup` persists session-meta, `tmo session reopen <task-id>` re-spawns at original cwd
- Prompt-improver enforcement: never skipped, default-accepted in workers

## Prerequisites

| Component | Minimum | Check |
|---|---|---|
| OS | Linux, macOS, or WSL2 | `uname -s` |
| tmux | 3.4 | `tmux -V` |
| bash | 4 | `bash --version` |
| jq | any | `jq --version` |
| Claude Code CLI | latest | `claude --version` |
| VS Code | any recent | `code --version` |
| Anthropic account | Claude Max recommended for parallel quota | account dashboard |

VS Code setting required (one-time, global):

```jsonc
// User settings.json
"task.allowAutomaticTasks": "on"
```

PATH requirement: `~/.local/bin` must be on `$PATH` (or pick another bin dir and adjust install).

## Install

This repo is structured as a Claude Code **plugin**. Two install paths.

### Path A - Plugin install (recommended)

```
/plugin install https://github.com/<your-username>/tmux-orchestration
```

Claude Code registers the plugin, auto-discovers `skills/tmux-orchestration/SKILL.md` and `skills/skill-bench/SKILL.md`, loads `hooks/hooks.json` (UserPromptSubmit + SessionStart), and resolves `${CLAUDE_PLUGIN_ROOT}` to the install location so role-md paths work out of the box.

### Path B - Manual install via `install.sh` (idempotent)

```bash
git clone https://github.com/<your-username>/tmux-orchestration.git ~/GitHub/tmux-orchestration
cd ~/GitHub/tmux-orchestration
./install.sh
```

`install.sh` is idempotent. It does three things:

1. Symlinks `bin/tmo` and `bin/skill-bench` into `~/.local/bin/` (overwrite on re-run).
2. Copies `skills/tmux-orchestration/SKILL.md` + `references/` into `~/.claude/skills/tmux-orchestration/` (overwrite on re-run).
3. Appends `export CLAUDE_PLUGIN_ROOT=<repo-path>` to `~/.bashrc` if not already there.

Re-source `~/.bashrc` (or open a new shell) after first install. Verify:

```bash
tmo --version       # expect: tmo 0.3.0 or newer
skill-bench --version
ls ~/.claude/skills/tmux-orchestration/
```

In manual-install mode, hooks are NOT auto-wired into `~/.claude/settings.json`. Either install via Path A (plugin) which registers them, or copy the hook entries from `hooks/hooks.json` into your global `~/.claude/settings.json` manually.

### Auto-reinstall workflow

When you pull or merge changes into the repo, re-run `install.sh` once. Because it overwrites symlinks and skill files, this is the canonical way to pick up updates without restarting Claude Code:

```bash
cd ~/GitHub/tmux-orchestration
git pull --ff-only
./install.sh
```

Take the same step after each `git merge --no-ff feat/<branch>` you do locally. The `bin/tmo` symlink resolves through to the working tree, so changes to the CLI take effect immediately for new invocations.

### Per-workspace tasks template

```bash
cp ~/GitHub/tmux-orchestration/.vscode/tasks.json.template <workspace>/.vscode/tasks.json
echo "!.vscode/tasks.json" >> <workspace>/.gitignore
```

Verify install: in a new Claude Code session, `tmux-orchestration` shows in the available-skills list and `tmo task board` runs without error.

## Role library

Roles live at `${CLAUDE_PLUGIN_ROOT}/roles/<name>.md`. Standard roles ship with the plugin:

- `orchestrator`, `frontend`, `backend`, `reviewer`, `generalist` (all `status: stable`)

Runtime-created roles write to the same dir as `status: candidate`. After 3-uses-low-correction-rate AND ROLE-BENCHMARK pass: graduate to `stable` + commit + push back via PR.

## Quick start

In any workspace where you want to orchestrate:

1. Open the workspace in VS Code (with `task.allowAutomaticTasks: "on"` already set)
2. Open Claude Code in a terminal panel
3. Type a triggering phrase, e.g.:
   - `tmux-orchestration`
   - `start tmux-orchestration with 2 workers`
   - `spawn workers with roles`
4. Skill loads. It runs the 8-phase flow, asks mandatory questions, writes `.vscode/tasks.json`, and tells you to reload the window or run `Tasks: Run Task → tmo:start-all`.
5. Worker panels open in VS Code. Orchestrator drives them via `tmo send` and direct peer-injection.

## Status

v0.7-ish - skill core + kanban tmo task + skill-bench + mockup-first + hooks + cleanup/reopen mechanic. Iterating per real-session test feedback.

Repo layout (plugin format):

```
tmux-orchestration/
├── .claude-plugin/
│   └── plugin.json           plugin manifest
├── .vscode/
│   ├── tasks.json            live 4-attach-tab config (runOn: folderOpen)
│   └── tasks.json.template   per-workspace template
├── bin/
│   ├── tmo                   main CLI (init/spawn/task/note/watchdog/etc)
│   └── skill-bench           Karpathy 5-task bench harness
├── hooks/
│   ├── hooks.json            UserPromptSubmit + SessionStart wiring
│   └── scripts/
│       ├── auto-task-add.sh  every user prompt -> tmo task add
│       └── sub-orch-claim.sh SessionStart auto-claim TMO_TASK
├── skills/
│   ├── tmux-orchestration/
│   │   ├── SKILL.md          the orchestration skill
│   │   └── references/       inter-claude-comm, role-evolution, watchdog
│   └── skill-bench/
│       └── SKILL.md          Karpathy methodology
├── roles/                    5 stable + sub-orch-builder (candidate)
├── mockup/                   design-first per feature
│   ├── _STANDARD.md          flowchart quality rules
│   ├── WORKSPACE.md          living workspace overview
│   └── kanban-flow.md        T-28 design
├── bench/                    Karpathy bench yamls per feature
├── examples/                 runnable examples (perf, watchdog, cleanup)
├── tests/                    e2e tests per feature
├── tui/                      rich-based dashboard mockup
├── claude-md-blocks/         paste-able CLAUDE.md snippets for users
├── install.sh                idempotent installer (Path B)
├── README.md / CLAUDE.md / LICENSE / .gitignore
└── state/                    gitignored, live runtime data
```

Coming as testing dictates need:

- `commands/` slash-commands (e.g. `/tmo-status`, `/tmo-spawn`)
- smart-compacter worker (5-min context-watchdog + agent-team begrip-pass + iterating compact-instructie writer)
- per-agent split-pane sidekick TUI
- `docs/TMO_CHEATSHEET.html` full visual cheatsheet
- screenshots

## License

MIT. See LICENSE.
