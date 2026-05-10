#!/usr/bin/env bash
# e2e: copy-mode detection in `tmo watchdog tick`.
#
# Setup: spawn throwaway tmux session, force pane into copy-mode, run tick,
# assert that messages.jsonl gained both copy-mode-hang and copy-mode-cancelled
# events, that the pane left copy-mode, and that a second tick within the
# throttle window does NOT log a new hang/cancel pair.
#
# Exits 0 on full pass, non-zero with diagnostic on any failed assertion.

set -euo pipefail

TMO_BIN="$(cd "$(dirname "$0")/../.." && pwd)/bin/tmo"
[[ -x "$TMO_BIN" ]] || { echo "fail: tmo binary not found at $TMO_BIN" >&2; exit 1; }

SESSION="tmo-e2e-copymode-$$"
WORKDIR="$(mktemp -d -t tmo-copymode-e2e.XXXXXX)"
export TMO_STATE_DIR="$WORKDIR/state"

cleanup() {
    tmux kill-session -t "$SESSION" 2>/dev/null || true
    rm -rf "$WORKDIR"
}
trap cleanup EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

# --- setup ---
"$TMO_BIN" init >/dev/null
tmux new-session -d -s "$SESSION" -x 200 -y 50 "bash --noprofile --norc"
sleep 0.3
"$TMO_BIN" watchdog enable "$SESSION" >/dev/null

MSG_FILE="$TMO_STATE_DIR/messages.jsonl"
[[ -f "$MSG_FILE" ]] || fail "messages.jsonl missing after init"

# --- case 1: typical copy-mode → tick detects + cancels + logs both events ---
tmux copy-mode -t "${SESSION}:0.0"
sleep 0.2
in_mode_before=$(tmux display-message -p -t "${SESSION}:0.0" -F '#{pane_in_mode}')
[[ "$in_mode_before" == "1" ]] || fail "case-typical: failed to enter copy-mode (got '$in_mode_before')"

baseline_lines=$(wc -l < "$MSG_FILE")
"$TMO_BIN" watchdog tick "$SESSION" 2>&1 | sed 's/^/[tick1] /'

new_events=$(tail -n +"$((baseline_lines + 1))" "$MSG_FILE")
echo "$new_events" | jq -c 'select(.type=="copy-mode-hang")'      | grep -q . || fail "case-typical: no copy-mode-hang event"
echo "$new_events" | jq -c 'select(.type=="copy-mode-cancelled")' | grep -q . || fail "case-typical: no copy-mode-cancelled event"

in_mode_after=$(tmux display-message -p -t "${SESSION}:0.0" -F '#{pane_in_mode}')
[[ "$in_mode_after" == "0" ]] || fail "case-typical: still in copy-mode after tick (got '$in_mode_after')"

pass "typical: copy-mode detected, both events logged, pane dropped out of mode"

# --- case 2: throttle — second tick within interval, re-enter copy-mode, no new hang event ---
tmux copy-mode -t "${SESSION}:0.0"
sleep 0.2
[[ "$(tmux display-message -p -t "${SESSION}:0.0" -F '#{pane_in_mode}')" == "1" ]] \
    || fail "case-throttle: failed to re-enter copy-mode"

baseline_lines=$(wc -l < "$MSG_FILE")
"$TMO_BIN" watchdog tick "$SESSION" 2>&1 | sed 's/^/[tick2] /'

throttled_events=$(tail -n +"$((baseline_lines + 1))" "$MSG_FILE")
hang_count=$(echo "$throttled_events" | jq -c 'select(.type=="copy-mode-hang")' | grep -c . || true)
[[ "$hang_count" == "0" ]] || fail "case-throttle: tick within interval emitted $hang_count hang event(s) (expected 0)"

pass "throttle: second tick within TMO_WATCHDOG_TICK_INTERVAL emits no extra hang"

# --- case 3: not in copy-mode → tick must NOT emit copy-mode-* events ---
tmux send-keys -t "${SESSION}:0.0" -X cancel 2>/dev/null || true
sleep 0.2
[[ "$(tmux display-message -p -t "${SESSION}:0.0" -F '#{pane_in_mode}')" == "0" ]] \
    || fail "case-no-mode: pane unexpectedly still in copy-mode"

baseline_lines=$(wc -l < "$MSG_FILE")
TMO_WATCHDOG_TICK_INTERVAL=1 "$TMO_BIN" watchdog tick "$SESSION" 2>&1 | sed 's/^/[tick3] /'

quiet_events=$(tail -n +"$((baseline_lines + 1))" "$MSG_FILE")
copy_count=$(echo "$quiet_events" | jq -c 'select(.type=="copy-mode-hang" or .type=="copy-mode-cancelled")' | grep -c . || true)
[[ "$copy_count" == "0" ]] || fail "case-no-mode: tick on non-copy-mode pane emitted $copy_count copy-mode event(s)"

pass "no-mode: tick on normal pane emits no copy-mode events"

# --- case 4: throttle expiry — short interval, re-enter copy-mode → new hang event ---
sleep 1.2
tmux copy-mode -t "${SESSION}:0.0"
sleep 0.2
[[ "$(tmux display-message -p -t "${SESSION}:0.0" -F '#{pane_in_mode}')" == "1" ]] \
    || fail "case-expiry: failed to re-enter copy-mode"

baseline_lines=$(wc -l < "$MSG_FILE")
TMO_WATCHDOG_TICK_INTERVAL=1 "$TMO_BIN" watchdog tick "$SESSION" 2>&1 | sed 's/^/[tick4] /'

expired_events=$(tail -n +"$((baseline_lines + 1))" "$MSG_FILE")
echo "$expired_events" | jq -c 'select(.type=="copy-mode-hang")'      | grep -q . || fail "case-expiry: no new hang event after interval expired"
echo "$expired_events" | jq -c 'select(.type=="copy-mode-cancelled")' | grep -q . || fail "case-expiry: no new cancelled event after interval expired"

pass "expiry: tick after throttle window emits a fresh hang/cancel pair"

# --- case 5: cross-skill — existing park-and-pick path still triggers after change ---
# Make sure pane is NOT in copy-mode and is stable, then plant [AWAITING-USER]
# marker. First tick classifies awaiting-user (count=1, action=log). Second
# tick on the SAME pane (count=2) MUST trigger action=park-and-pick.
tmux send-keys -t "${SESSION}:0.0" -X cancel 2>/dev/null || true
sleep 0.2
tmux send-keys -t "${SESSION}:0.0" -l $'printf %s\\\\n "[AWAITING-USER] need decision?"\n'
tmux send-keys -t "${SESSION}:0.0" Enter
sleep 0.3

# tick5a primes pane_hash (status=active because pane changed). tick5b sees
# unchanged pane + AWAITING-USER → awaiting-user count=1 action=log. tick5c
# sees unchanged pane + AWAITING-USER → awaiting-user count=2 action=park-and-pick.
tick5a=$(TMO_WATCHDOG_TICK_INTERVAL=600 "$TMO_BIN" watchdog tick "$SESSION" 2>&1)
echo "$tick5a" | sed 's/^/[tick5a] /'
echo "$tick5a" | grep -q 'open_q=1' || fail "case-cross-skill: tick5a did not detect [AWAITING-USER]"

tick5b=$(TMO_WATCHDOG_TICK_INTERVAL=600 "$TMO_BIN" watchdog tick "$SESSION" 2>&1)
echo "$tick5b" | sed 's/^/[tick5b] /'
echo "$tick5b" | grep -q 'status=awaiting-user' || fail "case-cross-skill: tick5b status not awaiting-user"

tick5c=$(TMO_WATCHDOG_TICK_INTERVAL=600 "$TMO_BIN" watchdog tick "$SESSION" 2>&1)
echo "$tick5c" | sed 's/^/[tick5c] /'
echo "$tick5c" | grep -q 'action=park-and-pick' || fail "case-cross-skill: tick5c did not trigger park-and-pick (got: $tick5c)"

PARKED_FILE="$TMO_STATE_DIR/parked-questions.yaml"
[[ -f "$PARKED_FILE" ]] || fail "case-cross-skill: parked-questions.yaml not written"
grep -q "$SESSION" "$PARKED_FILE" || fail "case-cross-skill: session not present in parked-questions.yaml"

pass "cross-skill: park-and-pick path intact after copy-mode short-circuit"

echo
echo "ALL E2E CASES PASS"
