#!/usr/bin/env bash
# F5 empirical test: peer in trust-folder dialog
#
# Setup: spawn claude WITHOUT --dangerously-skip-permissions in a fresh
# /tmp directory that has never been trusted. Claude shows the
# "Accessing workspace: ... Yes, I trust this folder / No, exit" dialog
# before the REPL is usable. Inject Channel A peer-prompt while the
# dialog is active.
#
# Expected (and observed): dialog UI swallows the pasted text. Enter
# activates the focused option ("Yes, I trust this folder" by default).
# The peer-prompt is silently lost. INADVERTENT CONFIRMATION RISK if
# the dialog were a destructive action.
#
# Mitigation: sender pre-flight grep for dialog headers
#   ('Accessing workspace:', 'Quick safety check:', 'Enter to confirm · Esc to cancel').
# If matched, fall back to Channel B forward.
#
# Repro:
#   bash tests/peer-comm/06-trust-dialog.sh
#   cat tests/peer-comm/06-trust-dialog.txt

set -u
PEER=pc-test-trust
SELF=${TMO_SESSION:-peercomm-orch}
LOG=$(cd "$(dirname "$0")" && pwd)/06-trust-dialog.txt
FRESH="/tmp/peer-test-fresh-$(date +%s)"

mkdir -p "$FRESH"
tmux kill-session -t "$PEER" 2>/dev/null
tmux new-session -d -s "$PEER" -c "$FRESH" -x 200 -y 50 \
  "TMO_SESSION=$PEER TMO_STATE_DIR=/home/freek/GitHub/tmux-orchestrator/state claude"
sleep 12

{
  echo "F5 empirical: peer in trust-folder dialog"
  echo "Run: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo
  echo "--- BEFORE injection (dialog active) ---"
  tmux capture-pane -t "$PEER:0.0" -p -S -50
  echo
} > "$LOG"

BODY="[from $SELF] PEER-INJECT-AT-DIALOG: this should not reach a real REPL because trust-dialog is intercepting."
BUF="peer-${SELF}-$(date +%s%N)"
printf '%s' "$BODY" | tmux load-buffer -b "$BUF" -
tmux paste-buffer -b "$BUF" -t "$PEER:0.0"
sleep 0.2
tmux send-keys -t "$PEER:0.0" Enter
tmux delete-buffer -b "$BUF"
sleep 4

{
  echo "--- AFTER injection (paste lost, Enter accepted dialog) ---"
  tmux capture-pane -t "$PEER:0.0" -p -S -50
  echo
  echo "Conclusion: paste lost; Enter ACCEPTED the focused dialog option."
  echo "Mitigation: sender MUST pre-flight via capture-pane grep for dialog headers."
} >> "$LOG"

tmux kill-session -t "$PEER" 2>/dev/null
rm -rf "$FRESH"
echo "Log written: $LOG"
