#!/usr/bin/env bash
# F4 empirical test: peer exited claude REPL
#
# DANGEROUS: paste lands in bash; Enter executes the body as a shell
# command. If the body contains anything bash can interpret as a
# command (e.g. starts with `rm`, `curl ... | sh`, `>file`), data loss
# or arbitrary code execution can follow.
#
# Setup: spawn pc-test-B inside a bash wrapper so the tmux session
# survives /exit. Start claude. Send /exit to leave the REPL. Then
# attempt Channel A injection. Capture-pane shows bash interpreting
# the body and emitting an error.
#
# Mitigation (sender MUST do this BEFORE every direct injection):
#   tmux capture-pane -t "$PEER:0.0" -p -S -5 \
#     | grep -E '^[─]+$|^❯ ?$' >/dev/null \
#     || { echo "peer not in claude REPL"; exit 1; }
# OR fall back to Channel B forward.
#
# Repro:
#   bash tests/peer-comm/03-peer-exited.sh
#   cat tests/peer-comm/03-peer-exited.txt

set -u
PEER=pc-test-B
SELF=${TMO_SESSION:-peercomm-orch}
WORKTREE=$(cd "$(dirname "$0")/../.." && pwd)
LOG="$WORKTREE/tests/peer-comm/03-peer-exited.txt"

tmux kill-session -t "$PEER" 2>/dev/null
tmux new-session -d -s "$PEER" -c "$WORKTREE" bash
sleep 1
tmux send-keys -t "$PEER:0.0" "TMO_SESSION=$PEER TMO_STATE_DIR=/home/freek/GitHub/tmux-orchestrator/state claude --dangerously-skip-permissions"
sleep 0.2
tmux send-keys -t "$PEER:0.0" Enter
sleep 12

# Step 1: exit claude.
tmux send-keys -t "$PEER:0.0" "/exit"
sleep 0.3
tmux send-keys -t "$PEER:0.0" Enter
sleep 3

# Step 2: attempt Channel A injection (BENIGN payload, no shell-evaluable parts).
BODY="[from $SELF] PEER-INJECT-AT-BASH: this should never reach a claude REPL because B has exited."
BUF="peer-${SELF}-$(date +%s%N)"
printf '%s' "$BODY" | tmux load-buffer -b "$BUF" -
tmux paste-buffer -b "$BUF" -t "$PEER:0.0"
sleep 0.2
tmux send-keys -t "$PEER:0.0" Enter
tmux delete-buffer -b "$BUF"

# Step 3: capture, observe bash error.
sleep 2
tmux capture-pane -t "$PEER:0.0" -p -S -200 > "$LOG"
echo "Log written: $LOG (expect bash-error from interpreting the body)"

tmux kill-session -t "$PEER" 2>/dev/null
