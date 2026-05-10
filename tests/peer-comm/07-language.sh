#!/usr/bin/env bash
# F5 empirical test: reply-language drift
#
# Setup: pc-test-B in claude REPL (English-default). Send a peer-prompt
# with English `[from <X>]` prefix but Dutch body content.
#
# Expected: receiver replies in Dutch, following body content. Prefix
# is metadata only and does not steer reply language.
#
# Repro:
#   bash tests/peer-comm/07-language.sh
#   cat tests/peer-comm/07-language.txt

set -u
PEER=pc-test-B
SELF=${TMO_SESSION:-peercomm-orch}
WORKTREE=$(cd "$(dirname "$0")/../.." && pwd)
LOG="$WORKTREE/tests/peer-comm/07-language.txt"

if ! tmux has-session -t "$PEER" 2>/dev/null; then
  tmux new-session -d -s "$PEER" -c "$WORKTREE" \
    "TMO_SESSION=$PEER TMO_STATE_DIR=/home/freek/GitHub/tmux-orchestrator/state claude --dangerously-skip-permissions"
  sleep 12
fi

BODY="[from $SELF] LANG-TEST: Beantwoord deze vraag uitsluitend in het Nederlands. Welke kleur is de lucht overdag bij helder weer? Sluit af met de letterlijke string LANG-NL-OK."
BUF="peer-${SELF}-$(date +%s%N)"
printf '%s' "$BODY" | tmux load-buffer -b "$BUF" -
tmux paste-buffer -b "$BUF" -t "$PEER:0.0"
sleep 0.2
tmux send-keys -t "$PEER:0.0" Enter
tmux delete-buffer -b "$BUF"

until tmux capture-pane -t "$PEER:0.0" -p -S -300 | grep -q "LANG-NL-OK"; do sleep 2; done
tmux capture-pane -t "$PEER:0.0" -p -S -300 > "$LOG"
echo "Log written: $LOG"
