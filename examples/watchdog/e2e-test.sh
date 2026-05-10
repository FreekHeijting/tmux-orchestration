#!/usr/bin/env bash
# End-to-end self-test for tmo watchdog. Spawns an ephemeral tmux session,
# walks the full state-machine cycle, asserts state-file contents, cleans up.
# Exit 0 on full pass, 1 on any failure.
set -u

# --- locate tmo --------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TMO="${TMO:-$REPO_ROOT/bin/tmo}"
[[ -x "$TMO" ]] || { echo "FAIL: tmo not executable at $TMO"; exit 1; }

# --- isolated state ----------------------------------------------------------
TEST_STATE_DIR="$(mktemp -d -t wd-e2e-XXXXXX)"
export TMO_STATE_DIR="$TEST_STATE_DIR"
: > "$TEST_STATE_DIR/messages.jsonl"

SESSION="wd-e2e-$$"

cleanup() {
    tmux kill-session -t "$SESSION" 2>/dev/null
    rm -rf "$TEST_STATE_DIR"
}
trap cleanup EXIT

pass() { printf '[PASS] %s\n' "$*"; }
fail() { printf '[FAIL] %s\n' "$*"; exit 1; }

assert_status() {
    # assert_status <session> <expected-status>
    local got
    got=$(python3 -c "
import sys, yaml
with open('$TEST_STATE_DIR/orchestrator-status.yaml') as f:
    d = yaml.safe_load(f) or {}
print((d.get('sessions') or {}).get('$1', {}).get('status', '?'))
")
    [[ "$got" == "$2" ]] || fail "session=$1 expected status=$2 got=$got"
    pass "session=$1 status=$2"
}

assert_count() {
    local got
    got=$(python3 -c "
import sys, yaml
with open('$TEST_STATE_DIR/orchestrator-status.yaml') as f:
    d = yaml.safe_load(f) or {}
print((d.get('sessions') or {}).get('$1', {}).get('awaiting_user_count', '?'))
")
    [[ "$got" == "$2" ]] || fail "session=$1 expected count=$2 got=$got"
    pass "session=$1 count=$2"
}

assert_parked_count() {
    local got
    got=$(python3 -c "
import sys, yaml
with open('$TEST_STATE_DIR/parked-questions.yaml') as f:
    d = yaml.safe_load(f) or {}
print(len(d.get('parked') or []))
")
    [[ "$got" == "$1" ]] || fail "expected parked count=$1 got=$got"
    pass "parked count=$1"
}

# --- phase 1: bootstrap ------------------------------------------------------
tmux new -d -s "$SESSION" -c /tmp 'sleep 600' \
    || fail "could not start tmux session $SESSION"
"$TMO" watchdog enable "$SESSION" >/dev/null \
    || fail "watchdog enable returned non-zero"
pass "session spawned + watchdog enabled"

# --- phase 2: idle baseline --------------------------------------------------
"$TMO" watchdog tick "$SESSION" >/dev/null 2>&1 || fail "tick exit"
# first tick has no prev_hash so changed=0; pane empty -> idle-no-work
assert_status "$SESSION" "idle-no-work"

# --- phase 3: open question -> awaiting-user count++ ------------------------
# Respawn with question as last pane line (no trailing shell prompt) to mimic
# a real Claude REPL pane where the question sits at the bottom of the screen.
tmux kill-session -t "$SESSION" 2>/dev/null
tmux new -d -s "$SESSION" -c /tmp \
    'printf "Should I rebase or merge?\n"; sleep 600' \
    || fail "could not respawn $SESSION with question"
sleep 1

"$TMO" watchdog tick "$SESSION" >/dev/null 2>&1
# pane changed since prior baseline -> active
assert_status "$SESSION" "active"

# next tick: no change, question still last line -> awaiting-user count=1
"$TMO" watchdog tick "$SESSION" >/dev/null 2>&1
assert_status "$SESSION" "awaiting-user"
assert_count "$SESSION" "1"

# --- phase 4: count hits 2 -> park-and-pick ---------------------------------
"$TMO" watchdog tick "$SESSION" >/dev/null 2>&1
# park-and-pick fires; status reset/qid cleared after park
assert_parked_count 1

# --- phase 5: backlog prod ---------------------------------------------------
cat > "$TEST_STATE_DIR/backlog.yaml" <<'YAML'
items:
  - id: b-1
    priority: high
    task: "review pending PR comments"
YAML

# Respawn idle session (no question) so detection won't fire awaiting-user.
tmux kill-session -t "$SESSION" 2>/dev/null
tmux new -d -s "$SESSION" -c /tmp 'sleep 600' \
    || fail "could not respawn idle $SESSION"
sleep 1

# first tick on new pane -> changed -> active
"$TMO" watchdog tick "$SESSION" >/dev/null 2>&1
assert_status "$SESSION" "active"

# next tick: no change, no question, backlog non-empty -> idle-with-backlog
sleep 1
"$TMO" watchdog tick "$SESSION" >/dev/null 2>&1
assert_status "$SESSION" "idle-with-backlog"

# --- phase 6: status command renders ----------------------------------------
"$TMO" watchdog status | grep -q "$SESSION" \
    || fail "status output missing session $SESSION"
pass "watchdog status lists $SESSION"

printf '\n[ALL PASSED] watchdog e2e cycle complete (state=%s)\n' "$TEST_STATE_DIR"
