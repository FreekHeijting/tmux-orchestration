#!/usr/bin/env bash
# F5 empirical test: rapid multi-prompt to same target
#
# Setup: pc-test-B in claude REPL idle state. Fire 3 peer-prompts
# back-to-back within ~0.5s.
#
# Expected: prompts queue in submission order; first one starts
# processing immediately, the rest are visible in the queue area
# under "Press up to edit queued messages". After the first prompt
# completes, the next is auto-picked. FIFO.
#
# Repro:
#   bash tests/peer-comm/04-rapid-multi.sh
#   cat tests/peer-comm/04-rapid-multi.txt

set -u
PEER=pc-test-B
SELF=${TMO_SESSION:-peercomm-orch}
WORKTREE=$(cd "$(dirname "$0")/../.." && pwd)
LOG="$WORKTREE/tests/peer-comm/04-rapid-multi.txt"

if ! tmux has-session -t "$PEER" 2>/dev/null; then
  tmux new-session -d -s "$PEER" -c "$WORKTREE" \
    "TMO_SESSION=$PEER TMO_STATE_DIR=/home/freek/GitHub/tmux-orchestrator/state claude --dangerously-skip-permissions"
  sleep 12
fi

for n in 1 2 3 ; do
  BODY="[from $SELF] RAPID-$n: please reply with the literal RAPID-ACK-$n in your final answer."
  BUF="peer-${SELF}-$(date +%s%N)"
  printf '%s' "$BODY" | tmux load-buffer -b "$BUF" -
  tmux paste-buffer -b "$BUF" -t "$PEER:0.0"
  sleep 0.05
  tmux send-keys -t "$PEER:0.0" Enter
  tmux delete-buffer -b "$BUF"
  sleep 0.2
done

# Wait for ALL three acks to appear (FIFO: ACK-3 last).
until tmux capture-pane -t "$PEER:0.0" -p -S -300 | grep -q "RAPID-ACK-3"; do sleep 2; done
tmux capture-pane -t "$PEER:0.0" -p -S -300 > "$LOG"
echo "Log written: $LOG"
