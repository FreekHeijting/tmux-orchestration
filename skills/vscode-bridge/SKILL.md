---
name: vscode-bridge
description: >
  Use when orchestrating tmux Claude sessions that must appear in the user's VS Code UI, or
  when driving the VS Code editor directly from Claude. Triggers on "vscode bridge",
  "vscode-mcp-server", "run all tasks", "show tmux sessions in vscode", "spawn visible sessions",
  "execute_command_code", and alongside the tmux-orchestration skill. Covers the HTTP MCP bridge
  on localhost:3000 (extension juehangqin.vscode-mcp-server), its file, symbol, diagnostics and
  command tools, the single-bridge-per-window constraint, and the Meta-Orchestrator pattern where
  only the project-level Meta drives the bridge to run VS Code tasks that open orchestrated tmux
  sessions as integrated terminals while sub-orchestrators escalate spawn requests to Meta.
  Keywords: vscode bridge, vscode-mcp-server, execute_command_code, Run All Tasks, tasks.json,
  integrated terminal, tmux orchestration, get_diagnostics_code, localhost:3000, meta orchestrator.
---

# vscode-bridge

Direct control over the user's open VS Code window from Claude, via the `vscode-mcp-server`
MCP bridge. Companion to `tmux-orchestration`: it is how a Meta-Orchestrator makes spawned tmux
sessions visible as VS Code integrated terminals.

## What it is

- Extension: `juehangqin.vscode-mcp-server`, HTTP transport on `http://localhost:3000/mcp`
  (port 3000 hardcoded in the extension).
- The extension starts the server automatically when VS Code is open.
- MCP client config lives in `~/.claude.json` user scope, and may also be registered per project
  in `.mcp.json`.

## When available

- VS Code is running with a workspace open AND the extension is active.
- ALWAYS verify before depending on it: `claude mcp list` must show
  `vscode-mcp-server: http://localhost:3000/mcp (HTTP) - Connected`.
- NEVER assume the bridge in a bare-terminal session. If it is not connected, use ordinary
  Read/Edit/Bash tools instead.

## Single-bridge constraint

- There is ONE bridge per VS Code window (port 3000 is single-bind). It is not consumed by use:
  multiple Claude sessions can call it concurrently over HTTP, but they all drive the SAME editor.
- NEVER let multiple sessions drive the bridge at once. They will fight over the editor.
- ALWAYS designate a single driver. In an orchestrated project that driver is the Meta-Orchestrator.

## Tools (typical)

- `list_files_code` file-tree navigation without shelling out.
- `read_file_code` file content straight from VS Code.
- `replace_lines_code` surgical edits with exact-content match.
- `create_file_code` new files or full overwrites.
- `search_symbols_code` / `get_document_symbols_code` symbol lookup and file outline.
- `get_symbol_definition_code` type info and docs without loading the whole file.
- `get_diagnostics_code` LSP errors and warnings.
- `execute_command_code` run any VS Code workbench command (save, format, refactor, run task).

## Editing rules

- When editing inside an open VS Code workspace: ALWAYS prefer the bridge edit tools so the user
  sees the change live and the editor picks up diagnostics.
- ALWAYS call `get_diagnostics_code` after a set of edits, before marking work complete.
- Prefer `search_symbols_code` + `get_document_symbols_code` over reading whole files, to save context.
- The bridge only sees the currently open VS Code workspace, not arbitrary directories on disk.

## Meta-Orchestrator pattern (the orchestration use)

Goal: the user literally sees the orchestrated tmux sessions as integrated terminals in VS Code.

- ALWAYS centralize spawning at Meta. Only the Meta-Orchestrator (project level) drives the bridge.
- Meta uses `execute_command_code` to run the VS Code task command (Command Palette,
  `Tasks: Run All Tasks`, or run a specific task). The tasks in `.vscode/tasks.json` each open a
  `tmux new-session ... claude` as a dedicated integrated terminal panel.
- A fase- or stap-orchestrator that needs a new visible task session (with a cd to the level where
  claude must start) does NOT spawn it itself. It escalates the request to Meta. Meta spawns and
  bootstraps the session. Reason: the single-bridge constraint above.
- Requires the VS Code user setting `task.allowAutomaticTasks: on` for `runOn: folderOpen` tasks.

## Setup reference (one-time)

```bash
code --install-extension JuehangQin.vscode-mcp-server
claude mcp add --transport http -s user vscode-mcp-server http://localhost:3000/mcp
```

If the extension misbehaves: open VS Code, run `VS Code MCP Server: Restart Server` via the
Command Palette, and re-verify with `claude mcp list | grep vscode-mcp-server`.
