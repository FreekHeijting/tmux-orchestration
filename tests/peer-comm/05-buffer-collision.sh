#!/usr/bin/env bash
# F5 empirical test: paste-buffer name collision
#
# Pure tmux mechanics (no claude needed). Demonstrates that
# `tmux load-buffer -b NAME` silently overwrites an existing buffer
# of the same name. If two senders use the same NAME, last-loader
# wins and the first sender's paste-buffer injects the wrong content.
#
# Mitigation: BUF="peer-${TMO_SESSION}-$(date +%s%N)" guarantees
# uniqueness across senders and within sender.
#
# Repro:
#   bash tests/peer-comm/05-buffer-collision.sh
#   cat tests/peer-comm/05-buffer-collision.txt

set -u
SESSION=pc-test-buf
LOG=$(cd "$(dirname "$0")" && pwd)/05-buffer-collision.txt

tmux kill-session -t "$SESSION" 2>/dev/null
tmux new-session -d -s "$SESSION" -x 200 -y 50 bash
sleep 2
tmux send-keys -t "$SESSION:0.0" "echo hello-bash" Enter
sleep 0.5

printf 'PAYLOAD-X-from-sender-X' | tmux load-buffer -b shared-name -
printf 'PAYLOAD-Y-from-sender-Y' | tmux load-buffer -b shared-name -
tmux paste-buffer -b shared-name -t "$SESSION:0.0"
sleep 0.3
tmux send-keys -t "$SESSION:0.0" Enter
sleep 0.5

{
  echo "F5 empirical: paste-buffer name collision"
  echo "Run: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "--- pane after collided paste ---"
  tmux capture-pane -t "$SESSION:0.0" -p
} > "$LOG"

tmux delete-buffer -b shared-name 2>/dev/null
tmux kill-session -t "$SESSION" 2>/dev/null
echo "Log written: $LOG"
