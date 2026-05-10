#!/usr/bin/env bash
# Karpathy bench runner: T-23 cleanup mechanic.
# Isolated state via mktemp + TMO_STATE_DIR. Each case spawns its own ephemeral
# tmux session; cleanup runs on EXIT regardless of pass/fail.
# Exit 0 if pass-rate >= 0.8, else 1.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TMO="${TMO:-$REPO_ROOT/bin/tmo}"
[[ -x "$TMO" ]] || { echo "FAIL: tmo not executable at $TMO"; exit 1; }

TEST_STATE_DIR="$(mktemp -d -t tmo-bench-T23-XXXXXX)"
export TMO_STATE_DIR="$TEST_STATE_DIR"
"$TMO" init >/dev/null

PASSED=0
FAILED=0
declare -a RESULTS

# Tracked sessions for global cleanup
declare -a EPH_SESSIONS=()

cleanup_all() {
    local s
    for s in "${EPH_SESSIONS[@]}"; do
        tmux kill-session -t "$s" 2>/dev/null
    done
    rm -rf "$TEST_STATE_DIR"
    rm -rf /tmp/T-23-bench-a /tmp/T-23-bench-b 2>/dev/null
}
trap cleanup_all EXIT

pass_case() { PASSED=$((PASSED+1)); RESULTS+=("PASS: $1"); printf '  [PASS] %s\n' "$1"; }
fail_case() { FAILED=$((FAILED+1)); RESULTS+=("FAIL: $1 — $2"); printf '  [FAIL] %s — %s\n' "$1" "$2"; }

new_eph_session() {
    local name="$1" cwd="${2:-$REPO_ROOT}"
    tmux new-session -d -s "$name" -c "$cwd" 'bash -i'
    EPH_SESSIONS+=("$name")
}

# ---------------------------------------------------------------------------
# Case 1: typical
# ---------------------------------------------------------------------------
case_typical() {
    local name="t23-typ-$$"
    local task_id

    new_eph_session "$name" "$REPO_ROOT"
    tmux set-environment -t "$name" TMO_ROLE "sub-orch-builder"

    task_id=$("$TMO" task add "typical bench task" --by orch | awk '{print $NF}')
    "$TMO" task claim "$task_id" --by "$name" >/dev/null
    "$TMO" task done "$task_id" --output "stub" >/dev/null
    "$TMO" task update "$task_id" verdict approve >/dev/null

    local out rc
    out=$("$TMO" cleanup "$name" 2>&1) ; rc=$?

    if [[ $rc -ne 0 ]]; then
        fail_case "typical" "exit=$rc out=$out"; return
    fi
    if tmux has-session -t "$name" 2>/dev/null; then
        fail_case "typical" "tmux session still alive"; return
    fi
    local desc
    desc=$("$TMO" task get "$task_id" | jq -r '.desc')
    if ! printf '%s' "$desc" | grep -q '"schema":"tmo.session-meta.v1"'; then
        fail_case "typical" "no schema marker in desc"; return
    fi
    local k missing=()
    for k in session role cwd branch last_sha panes closed_at; do
        printf '%s' "$desc" | jq -e --arg k "$k" 'has($k)' >/dev/null \
            || missing+=("$k")
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        fail_case "typical" "missing meta keys: ${missing[*]}"; return
    fi
    pass_case "typical"
}

# ---------------------------------------------------------------------------
# Case 2: edge-case no-session
# ---------------------------------------------------------------------------
case_edge_no_session() {
    local name="t23-ghost-$$"
    tmux has-session -t "$name" 2>/dev/null && tmux kill-session -t "$name"
    local out rc
    out=$("$TMO" cleanup "$name" 2>&1) ; rc=$?
    if [[ $rc -ne 0 ]]; then
        fail_case "edge-case-no-session" "expected exit 0, got $rc; out=$out"; return
    fi
    if ! printf '%s' "$out" | grep -q "nothing to do"; then
        fail_case "edge-case-no-session" "missing 'nothing to do' message; out=$out"; return
    fi
    pass_case "edge-case-no-session"
}

# ---------------------------------------------------------------------------
# Case 3: anti-pattern cleanup BEFORE done
# ---------------------------------------------------------------------------
case_anti_not_done() {
    local name="t23-anti-$$"
    local task_id
    new_eph_session "$name" "$REPO_ROOT"
    task_id=$("$TMO" task add "anti-pattern task" --by orch | awk '{print $NF}')
    "$TMO" task claim "$task_id" --by "$name" >/dev/null
    # NOT done; NOT approved.

    local out rc
    out=$("$TMO" cleanup "$name" 2>&1) ; rc=$?
    if [[ $rc -eq 0 ]]; then
        fail_case "anti-pattern-not-done" "expected non-zero exit, got 0"; return
    fi
    if ! tmux has-session -t "$name" 2>/dev/null; then
        fail_case "anti-pattern-not-done" "session got killed despite refusal"; return
    fi
    if ! printf '%s' "$out" | grep -qE "status='in_progress'|verdict=''"; then
        fail_case "anti-pattern-not-done" "missing gate-violation message; out=$out"; return
    fi
    pass_case "anti-pattern-not-done"
}

# ---------------------------------------------------------------------------
# Case 4: multi-window cwds
# ---------------------------------------------------------------------------
case_multi_window() {
    local name="t23-multi-$$"
    local task_id
    mkdir -p /tmp/T-23-bench-a /tmp/T-23-bench-b

    new_eph_session "$name" "$REPO_ROOT"
    tmux new-window -t "$name" -c /tmp/T-23-bench-a 'bash -i'
    tmux new-window -t "$name" -c /tmp/T-23-bench-b 'bash -i'

    task_id=$("$TMO" task add "multi-window task" --by orch | awk '{print $NF}')
    "$TMO" task claim "$task_id" --by "$name" >/dev/null
    "$TMO" task done "$task_id" --output "stub" >/dev/null
    "$TMO" task update "$task_id" verdict approve >/dev/null

    local rc
    "$TMO" cleanup "$name" >/dev/null 2>&1; rc=$?
    if [[ $rc -ne 0 ]]; then
        fail_case "ambiguous-scope-multi-window" "cleanup exit=$rc"; return
    fi
    if tmux has-session -t "$name" 2>/dev/null; then
        fail_case "ambiguous-scope-multi-window" "session still alive"; return
    fi
    local desc panes_n cwds
    desc=$("$TMO" task get "$task_id" | jq -r '.desc')
    panes_n=$(printf '%s' "$desc" | jq '.panes | length')
    if [[ "$panes_n" -lt 3 ]]; then
        fail_case "ambiguous-scope-multi-window" "panes count=$panes_n (need >=3)"; return
    fi
    cwds=$(printf '%s' "$desc" | jq -r '.panes[].cwd' | sort -u)
    if ! printf '%s' "$cwds" | grep -q '/tmp/T-23-bench-a' \
       || ! printf '%s' "$cwds" | grep -q '/tmp/T-23-bench-b'; then
        fail_case "ambiguous-scope-multi-window" "missing tmp cwds; got: $cwds"; return
    fi
    pass_case "ambiguous-scope-multi-window"
}

# ---------------------------------------------------------------------------
# Case 5: cross-skill — task list still shows completed
# ---------------------------------------------------------------------------
case_cross_skill() {
    local name="t23-cross-$$"
    local task_id
    new_eph_session "$name" "$REPO_ROOT"
    task_id=$("$TMO" task add "cross-skill task" --by orch | awk '{print $NF}')
    "$TMO" task claim "$task_id" --by "$name" >/dev/null
    "$TMO" task done "$task_id" --output "stub" >/dev/null
    "$TMO" task update "$task_id" verdict approve >/dev/null
    "$TMO" cleanup "$name" >/dev/null 2>&1

    local listed
    listed=$("$TMO" task list --status completed | grep -c "^${task_id}\b" || true)
    if [[ "$listed" -lt 1 ]]; then
        fail_case "cross-skill-task-list" "task $task_id not in completed list"; return
    fi
    pass_case "cross-skill-task-list"
}

# ---------------------------------------------------------------------------
# Drive
# ---------------------------------------------------------------------------
echo "[bench T-23] state=$TEST_STATE_DIR"
echo "--- case: typical ---"
case_typical
echo "--- case: edge-case-no-session ---"
case_edge_no_session
echo "--- case: anti-pattern-not-done ---"
case_anti_not_done
echo "--- case: ambiguous-scope-multi-window ---"
case_multi_window
echo "--- case: cross-skill-task-list ---"
case_cross_skill

TOTAL=$((PASSED + FAILED))
RATE=$(awk "BEGIN { printf \"%.2f\", $PASSED/$TOTAL }")
echo
echo "[bench T-23] passed=$PASSED failed=$FAILED total=$TOTAL pass-rate=$RATE"
for r in "${RESULTS[@]}"; do printf '  %s\n' "$r"; done

awk "BEGIN { exit !($PASSED/$TOTAL >= 0.8) }" || exit 1
