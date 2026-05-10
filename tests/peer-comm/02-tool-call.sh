#!/usr/bin/env bash
# F3 empirical test: peer mid-tool-call (Bash running)
#
# Setup: assumes pc-test-B already running (or spawns fresh). Trigger a
# Bash tool call that takes ~8 seconds. While tool is running, inject a
# peer-prompt via Channel A.
#
# Expected: paste lands in input buffer during tool-call, claude REPL
# explicitly shows "Press up to edit queued messages" indicator. After
# tool returns and the parent prompt completes, claude picks up the
# queued peer-prompt and processes it.
#
# Repro:
#   bash tests/peer-comm/02-tool-call.sh
#   cat tests/peer-comm/02-tool-call.txt

set -u
PEER=pc-test-B
SELF=${TMO_SESSION:-peercomm-orch}
WORKTREE=$(cd "$(dirname "$0")/../.." && pwd)
LOG="$WORKTREE/tests/peer-comm/02-tool-call.txt"

if ! tmux has-session -t "$PEER" 2>/dev/null; then
  tmux new-session -d -s "$PEER" -c "$WORKTREE" \
    "TMO_SESSION=$PEER TMO_STATE_DIR=/home/freek/GitHub/tmux-orchestrator/state claude --dangerously-skip-permissions"
  sleep 12
fi

# Step 1: trigger tool-call (8-second bash loop).
TOOL_PROMPT="Run this exact bash one-liner with the Bash tool: bash -lc 'for i in 1 2 3 4 5 6 7 8; do echo tick-\$i; sleep 1; done'. After the tool returns, only then reply with the literal string TOOL-DONE."
printf '%s' "$TOOL_PROMPT" | tmux load-buffer -b tool-trigger -
tmux paste-buffer -b tool-trigger -t "$PEER:0.0"
sleep 0.2
tmux send-keys -t "$PEER:0.0" Enter
tmux delete-buffer -b tool-trigger

# Step 2: while tool-call runs, inject peer-prompt via Channel A.
sleep 5
BODY="[from $SELF] PEER-INJECT-DURING-TOOL: please reply with the literal string PONG-TOOL-OK as your final message after the bash tool finishes."
BUF="peer-${SELF}-$(date +%s%N)"
printf '%s' "$BODY" | tmux load-buffer -b "$BUF" -
tmux paste-buffer -b "$BUF" -t "$PEER:0.0"
sleep 0.2
tmux send-keys -t "$PEER:0.0" Enter
tmux delete-buffer -b "$BUF"
tmo send "$PEER" peer-prompt "{\"from\":\"$SELF\",\"mode\":\"direct\",\"buf\":\"$BUF\",\"prompt_preview\":\"PEER-INJECT-DURING-TOOL...\"}"

# Step 3: wait for both prompts to finish, capture pane.
sleep 25
tmux capture-pane -t "$PEER:0.0" -p -S -300 > "$LOG"
echo "Log written: $LOG"
