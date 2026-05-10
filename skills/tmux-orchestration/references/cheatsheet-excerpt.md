# Cheatsheet excerpt

Quick reference. Full version: `~/Bureaublad/TMO_CHEATSHEET.html`.

## tmo CLI

| Subcommand | Purpose |
|---|---|
| `tmo init` | Create `state/messages.jsonl` + `state/sessions.yaml` |
| `tmo spawn N --role R` | Spawn N tmux worker-sessions running claude |
| `tmo list-roles` | List roles under `roles/*.md` |
| `tmo send <to> <type> <payload>` | Append message to inbox of `<to>` |
| `tmo receive --for <session>` | Read messages addressed to `<session>` |
| `tmo wait-for <session> <event>` | Block until `<session>` emits `<event>` |
| `tmo bootstrap` | End-to-end: init + spawn + roles + attach panes |

## Tmux essentials

```bash
tmux ls                                    # list sessions
tmux new-session -A -s <name> claude       # attach-or-create, idempotent
tmux attach -t <name>                      # attach existing
tmux kill-session -t <name>                # destroy
tmux kill-server                           # nuclear: all sessions gone
```

## 2-step Enter (mandatory for claude REPL)

```bash
tmux send-keys -t <name>:0.0 "prompt"
sleep 0.2
tmux send-keys -t <name>:0.0 Enter
```

Single-call combined form fails intermittently. Always split.

## Multiline injection

```bash
echo "multi
line
prompt" | tmux load-buffer -b ctx -
tmux paste-buffer -b ctx -t <name>:0.0
sleep 0.2
tmux send-keys -t <name>:0.0 Enter
tmux delete-buffer -b ctx
```

## Capture

```bash
tmux capture-pane -t <name>:0.0 -p -S -200 | tail -50
```

## VS Code tasks.json (template)

```json
{
  "version": "2.0.0",
  "tasks": [
    {
      "label": "tmo:<name>",
      "type": "shell",
      "command": "tmux new-session -A -s <name> claude",
      "presentation": { "panel": "dedicated", "group": "tmo", "focus": false }
    },
    {
      "label": "tmo:start-all",
      "dependsOn": ["tmo:orchestrator", "tmo:worker-1", "tmo:worker-2"],
      "dependsOrder": "parallel",
      "runOptions": { "runOn": "folderOpen" }
    }
  ]
}
```

Plus `.gitignore` exception: `!.vscode/tasks.json`.

## State files

| File | Format | Purpose |
|---|---|---|
| `state/messages.jsonl` | append-only JSON-lines | Central forum / audit-trail |
| `state/sessions.yaml` | mutable YAML | Session metadata + status |
| `state/inboxes/<name>.jsonl` | append-only | Per-worker filtered inbox |
| `state/locks/` | empty marker files | File-scope claim locks |

## Message schema

```json
{"ts":"2026-05-10T13:42:00Z","from":"orchestrator","to":"worker-1","type":"task","payload":{...}}
```

Common types: `task`, `status`, `done`, `blocked`, `peer-prompt`, `forward`, `reinstruct`, `replace`, `approved`.

## Status values (sessions.yaml)

| Value | Meaning |
|---|---|
| `idle` | Awaiting work |
| `working` | In progress |
| `blocked` | Waiting on peer/orchestrator |
| `done` | Task finished |
