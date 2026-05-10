# tests/peer-comm - empirical edge-case test logs

Each numbered log captures a tmux capture-pane transcript of an inter-claude peer-injection scenario. Logs are raw, append-only, written by the test runner during each phase.

## Test runner setup

Two ephemeral tmux sessions:
- `pc-test-A` - sender role
- `pc-test-B` - receiver role

Both inherit `TMO_STATE_DIR=/home/freek/GitHub/tmux-orchestrator/state` so audit-log lands in the orchestrator's central forum.

## Test scripts

| Phase | Edge case | Script | Log |
|---|---|---|---|
| F2 | Peer mid-thinking (busy-spinner) | `01-busy-spinner.sh` | `01-busy-spinner.txt` |
| F3 | Peer mid-tool-call | `02-tool-call.sh` | `02-tool-call.txt` |
| F4 | Peer exited claude | `03-peer-exited.sh` | `03-peer-exited.txt` |
| F5 | Rapid multi-prompt | `04-rapid-multi.sh` | `04-rapid-multi.txt` |
| F5 | Buffer-name collision | `05-buffer-collision.sh` | `05-buffer-collision.txt` |
| F5 | Trust-folder dialog | `06-trust-dialog.sh` | `06-trust-dialog.txt` |
| F5 | Reply-language drift | `07-language.sh` | `07-language.txt` |

## How to repro

```bash
cd ~/GitHub/tmux-orchestration
bash tests/peer-comm/<NN>-<name>.sh
# inspect tests/peer-comm/<NN>-<name>.txt
```

Each script:
1. Spawns `pc-test-A` and `pc-test-B` (kills existing first)
2. Waits for claude REPL to render in both panes
3. Drives the sender via `tmux send-keys` to perform Channel A injection
4. Captures receiver pane to log
5. Tears down sessions

## Privacy

These logs may contain user-paths and prompt content. They are committed for repro but contain no secrets. Review before sharing externally.
