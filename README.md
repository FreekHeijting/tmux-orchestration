# tmux-orchestration

Claude Code skill that turns the current Claude session into a persistent orchestrator driving N parallel worker-Claude sessions in tmux. Each worker has an assigned role, file-scope, initial task, skill-hints, and quality-gate supervision.

Designed for VS Code on Linux. Workers spawn as VS Code integrated terminal panels.

## What you get

- 8-phase mandatory flow before any spawn (context snapshot, mandatory questions, live-session check, role assignment, workspace assignment, skill-hint scan, communication channels, spawn + runbook)
- Quality-gate loop after every worker reply: APPROVE / RE-INSTRUCT / REPLACE
- Three communication channels: direct peer-injection (user-visible), orchestrator-routed fallback, append-only audit-forum (`state/messages.jsonl`)
- File-scope isolation per worker
- Cross-workspace workers share state via `TMO_STATE_DIR`
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

Claude Code registers the plugin, auto-discovers `skills/tmux-orchestration/SKILL.md`, and resolves `${CLAUDE_PLUGIN_ROOT}` to the install location so role-md paths work out of the box.

### Path B - Manual install (no plugin system)

```bash
git clone https://github.com/<your-username>/tmux-orchestration.git ~/GitHub/tmux-orchestration

# skill into global skills dir
mkdir -p ~/.claude/skills/tmux-orchestration
cp -r ~/GitHub/tmux-orchestration/skills/tmux-orchestration/* ~/.claude/skills/tmux-orchestration/

# tmo CLI on PATH
ln -sf ~/GitHub/tmux-orchestration/bin/tmo ~/.local/bin/tmo

# manually export CLAUDE_PLUGIN_ROOT so SKILL.md role-paths resolve
echo 'export CLAUDE_PLUGIN_ROOT=$HOME/GitHub/tmux-orchestration' >> ~/.bashrc
```

### Per-workspace tasks template

```bash
cp ~/GitHub/tmux-orchestration/.vscode/tasks.json.template <workspace>/.vscode/tasks.json
echo "!.vscode/tasks.json" >> <workspace>/.gitignore
```

Verify install: in a new Claude Code session, `tmux-orchestration` shows in the available-skills list.

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
   - `start tmux-orchestration met 2 workers`
   - `spawn workers met rollen`
4. Skill loads. It runs the 8-phase flow, asks mandatory questions, writes `.vscode/tasks.json`, and tells you to reload the window or run `Tasks: Run Task → tmo:start-all`.
5. Worker panels open in VS Code. Orchestrator drives them via `tmo send` and direct peer-injection.

## Status

v0.3.0 - skill core + audit-trail communication. Iterating per real-session test feedback.

Essentials in this repo grow as testing reveals what is actually needed. Currently in repo (plugin format):

```
tmux-orchestration/
├── .claude-plugin/
│   └── plugin.json           plugin manifest
├── skills/tmux-orchestration/
│   ├── SKILL.md              the skill
│   └── references/           skill-internal naslag
├── roles/                    canonical role library (5 stable + runtime candidates)
├── bin/tmo                   CLI binary
├── tui/                      rich-based dashboard mockup (tui-rich.py + demo-state.json)
├── claude-md-blocks/         paste-able CLAUDE.md snippets for users
├── .vscode/tasks.json.template   per-workspace auto-spawn template
├── README.md / CLAUDE.md / LICENSE / .gitignore
```

Coming as testing dictates need:

- `helpers/*` tmux-multi-inject / -capture / tmux-tree
- `commands/` slash-commands (e.g. `/tmo-status`, `/tmo-spawn`)
- `hooks/` event hooks
- `docs/TMO_CHEATSHEET.html` full visual cheatsheet
- screenshots

## License

MIT. See LICENSE.
