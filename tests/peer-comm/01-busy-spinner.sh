#!/usr/bin/env bash
# F2 empirical test: peer mid-thinking (busy-spinner)
#
# Setup: spawn ephemeral pc-test-B running claude. Send a long-thinking
# prompt to put B in busy state, then within ~1s inject a peer-prompt
# via Channel A (load-buffer + paste-buffer + 2-step Enter).
#
# Expected: paste lands in B's input buffer during busy state, Enter is
# queued, prompt submits at next-turn boundary after B finishes the
# busy-trigger task. B replies with PONG-BUSY-OK to confirm pickup.
#
# Repro:
#   bash tests/peer-comm/01-busy-spinner.sh
#   cat tests/peer-comm/01-busy-spinner.txt
#
# Cleanup: tmux kill-session -t pc-test-B at end.

set -u
PEER=pc-test-B
SELF=${TMO_SESSION:-peercomm-orch}
WORKTREE=$(cd "$(dirname "$0")/../.." && pwd)
LOG="$WORKTREE/tests/peer-comm/01-busy-spinner.txt"

tmux kill-session -t "$PEER" 2>/dev/null
tmux new-session -d -s "$PEER" -c "$WORKTREE" \
  "TMO_SESSION=$PEER TMO_STATE_DIR=/home/freek/GitHub/tmux-orchestrator/state claude --dangerously-skip-permissions"

# Wait for claude REPL to render (12s safe upper bound).
sleep 12

# Step 1: trigger busy state with a thinking-heavy prompt (no tool calls).
BUSY_PROMPT="Without using any tools, write 25 short random sentences about the weather. Just text, one per line. Quick."
printf '%s' "$BUSY_PROMPT" | tmux load-buffer -b busy-trigger -
tmux paste-buffer -b busy-trigger -t "$PEER:0.0"
sleep 0.2
tmux send-keys -t "$PEER:0.0" Enter
tmux delete-buffer -b busy-trigger

# Step 2: while B is busy, inject peer-prompt via Channel A.
sleep 2
BODY="[from $SELF] PEER-INJECT-DURING-BUSY: please reply with the literal string PONG-BUSY-OK as your final message after finishing your current task."
BUF="peer-${SELF}-$(date +%s%N)"
printf '%s' "$BODY" | tmux load-buffer -b "$BUF" -
tmux paste-buffer -b "$BUF" -t "$PEER:0.0"
sleep 0.2
tmux send-keys -t "$PEER:0.0" Enter
tmux delete-buffer -b "$BUF"
tmo send "$PEER" peer-prompt "{\"from\":\"$SELF\",\"mode\":\"direct\",\"buf\":\"$BUF\",\"prompt_preview\":\"PEER-INJECT-DURING-BUSY...\"}"

# Step 3: wait for B to finish both prompts, capture pane.
sleep 30
tmux capture-pane -t "$PEER:0.0" -p -S -200 > "$LOG"
echo "Log written: $LOG"

# Cleanup.
tmux kill-session -t "$PEER" 2>/dev/null
