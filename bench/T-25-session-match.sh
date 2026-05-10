#!/usr/bin/env bash
# Karpathy bench runner: T-25 session match.
# Each case provisions its own isolated task-pool so they don't interfere.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TMO="${TMO:-$REPO_ROOT/bin/tmo}"
[[ -x "$TMO" ]] || { echo "FAIL: tmo not executable at $TMO"; exit 1; }

PASSED=0
FAILED=0
declare -a RESULTS

pass_case() { PASSED=$((PASSED+1)); RESULTS+=("PASS: $1"); printf '  [PASS] %s\n' "$1"; }
fail_case() { FAILED=$((FAILED+1)); RESULTS+=("FAIL: $1 — $2"); printf '  [FAIL] %s — %s\n' "$1" "$2"; }

# Provision a closed task with a synthetic session-meta (no tmux needed).
# Args: <state-dir> <task-id-output-var> <subject> <session> <role> <branch>
provision_closed() {
    local state="$1" subject="$2" session="$3" role="$4" branch="$5"
    local task_id meta
    TMO_STATE_DIR="$state" task_id=$("$TMO" task add "$subject" --by orch | awk '{print $NF}')
    TMO_STATE_DIR="$state" "$TMO" task done "$task_id" --output "stub" >/dev/null
    meta=$(jq -nc \
        --arg s "$session" --arg r "$role" --arg b "$branch" \
        --arg id "$task_id" \
        --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '{schema:"tmo.session-meta.v1", task_id:$id, session:$s, role:$r,
          role_md:"-", cwd:"/tmp", branch:$b, last_sha:"deadbee", panes:[],
          closed_at:$ts}')
    TMO_STATE_DIR="$state" "$TMO" task update "$task_id" desc "$meta" >/dev/null
    printf '%s' "$task_id"
}

mk_state() { mktemp -d -t tmo-bench-T25-XXXXXX; }

# ---------------------------------------------------------------------------
# Case 1: typical — 3 distinct roles, query hits one
# ---------------------------------------------------------------------------
case_typical() {
    local s; s=$(mk_state)
    TMO_STATE_DIR="$s" "$TMO" init >/dev/null
    provision_closed "$s" "fix navbar in app"        "fe-1" "frontend-dev"     "main"  >/dev/null
    provision_closed "$s" "tune database query"      "be-1" "backend-builder"  "main"  >/dev/null
    provision_closed "$s" "write release notes"      "dx-1" "docs-writer"      "main"  >/dev/null

    local out top1_role rc
    out=$(TMO_STATE_DIR="$s" "$TMO" session match "frontend component bug" 2>&1) ; rc=$?
    rm -rf "$s"
    if [[ $rc -ne 0 ]]; then fail_case "typical" "exit=$rc out=$out"; return; fi
    top1_role=$(printf '%s' "$out" | head -1 | awk -F'\t' '{print $4}')
    if [[ "$top1_role" != *"frontend"* ]]; then
        fail_case "typical" "top1 role=$top1_role (want *frontend*) full=$out"; return
    fi
    pass_case "typical"
}

# ---------------------------------------------------------------------------
# Case 2: edge-case empty pool
# ---------------------------------------------------------------------------
case_edge_empty() {
    local s; s=$(mk_state)
    TMO_STATE_DIR="$s" "$TMO" init >/dev/null
    local out rc
    out=$(TMO_STATE_DIR="$s" "$TMO" session match "anything goes here" 2>&1) ; rc=$?
    rm -rf "$s"
    if [[ $rc -ne 0 ]]; then fail_case "edge-case-empty-pool" "exit=$rc"; return; fi
    if [[ -n "$out" ]]; then
        fail_case "edge-case-empty-pool" "expected empty stdout, got: $out"; return
    fi
    pass_case "edge-case-empty-pool"
}

# ---------------------------------------------------------------------------
# Case 3: anti-pattern noise tokens
# ---------------------------------------------------------------------------
case_anti_noise() {
    local s; s=$(mk_state)
    TMO_STATE_DIR="$s" "$TMO" init >/dev/null
    provision_closed "$s" "fix navbar"          "fe-1" "frontend-dev"     "main"  >/dev/null
    provision_closed "$s" "database tuning"     "be-1" "backend-builder"  "main"  >/dev/null

    local out rc
    out=$(TMO_STATE_DIR="$s" "$TMO" session match "a b c d" 2>&1) ; rc=$?
    rm -rf "$s"
    if [[ $rc -ne 0 ]]; then fail_case "anti-pattern-noise-tokens" "exit=$rc out=$out"; return; fi
    if [[ -n "$out" ]]; then
        fail_case "anti-pattern-noise-tokens" "expected empty stdout, got: $out"; return
    fi
    pass_case "anti-pattern-noise-tokens"
}

# ---------------------------------------------------------------------------
# Case 4: ambiguous-scope multi-equal
# ---------------------------------------------------------------------------
case_ambiguous_multi() {
    local s; s=$(mk_state)
    TMO_STATE_DIR="$s" "$TMO" init >/dev/null
    provision_closed "$s" "backend api change"   "be-1" "backend-builder" "main" >/dev/null
    provision_closed "$s" "backend job worker"   "be-2" "backend-builder" "dev"  >/dev/null
    provision_closed "$s" "frontend tweak"       "fe-1" "frontend-dev"    "main" >/dev/null

    local out rc count
    out=$(TMO_STATE_DIR="$s" "$TMO" session match "backend builder" 2>&1) ; rc=$?
    rm -rf "$s"
    if [[ $rc -ne 0 ]]; then fail_case "ambiguous-scope-multi-equal" "exit=$rc"; return; fi
    count=$(printf '%s' "$out" | grep -c "backend-builder" || true)
    if [[ "$count" -lt 2 ]]; then
        fail_case "ambiguous-scope-multi-equal" "expected >=2 hits, got $count; out=$out"; return
    fi
    pass_case "ambiguous-scope-multi-equal"
}

# ---------------------------------------------------------------------------
# Case 5: cross-skill --top N truncation
# ---------------------------------------------------------------------------
case_cross_top_n() {
    local s; s=$(mk_state)
    TMO_STATE_DIR="$s" "$TMO" init >/dev/null
    provision_closed "$s" "backend api"          "be-1" "backend-builder" "main" >/dev/null
    provision_closed "$s" "backend worker"       "be-2" "backend-builder" "dev"  >/dev/null
    provision_closed "$s" "backend migration"    "be-3" "backend-builder" "main" >/dev/null

    local out rc lines
    out=$(TMO_STATE_DIR="$s" "$TMO" session match "backend" --top 1 2>&1) ; rc=$?
    rm -rf "$s"
    if [[ $rc -ne 0 ]]; then fail_case "cross-skill-top-N" "exit=$rc"; return; fi
    lines=$(printf '%s' "$out" | grep -c . || true)
    if [[ "$lines" -ne 1 ]]; then
        fail_case "cross-skill-top-N" "expected exactly 1 line, got $lines; out=$out"; return
    fi
    pass_case "cross-skill-top-N"
}

echo "[bench T-25]"
echo "--- case: typical ---"
case_typical
echo "--- case: edge-case-empty-pool ---"
case_edge_empty
echo "--- case: anti-pattern-noise-tokens ---"
case_anti_noise
echo "--- case: ambiguous-scope-multi-equal ---"
case_ambiguous_multi
echo "--- case: cross-skill-top-N ---"
case_cross_top_n

TOTAL=$((PASSED + FAILED))
RATE=$(awk "BEGIN { printf \"%.2f\", $PASSED/$TOTAL }")
echo
echo "[bench T-25] passed=$PASSED failed=$FAILED total=$TOTAL pass-rate=$RATE"
for r in "${RESULTS[@]}"; do printf '  %s\n' "$r"; done

awk "BEGIN { exit !($PASSED/$TOTAL >= 0.8) }" || exit 1
