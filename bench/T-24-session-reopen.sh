#!/usr/bin/env bash
# Karpathy bench runner: T-24 session reopen mechanic.
# All reopens use --no-terminal and (most) --no-prompt to keep the bench
# headless-safe. Tests do NOT spawn real gnome-terminal nor real claude;
# they replace the launched process with `bash -i` via a temp PATH override.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TMO="${TMO:-$REPO_ROOT/bin/tmo}"
[[ -x "$TMO" ]] || { echo "FAIL: tmo not executable at $TMO"; exit 1; }

TEST_STATE_DIR="$(mktemp -d -t tmo-bench-T24-XXXXXX)"
SHIM_DIR="$(mktemp -d -t tmo-bench-T24-shim-XXXXXX)"
# Stub `claude` -> bash -i so reopen creates a shell instead of failing
cat > "$SHIM_DIR/claude" <<'EOF'
#!/usr/bin/env bash
exec bash -i
EOF
chmod +x "$SHIM_DIR/claude"
export PATH="$SHIM_DIR:$PATH"
export TMO_STATE_DIR="$TEST_STATE_DIR"
"$TMO" init >/dev/null

PASSED=0
FAILED=0
declare -a RESULTS
declare -a EPH_SESSIONS=()

cleanup_all() {
    local s
    for s in "${EPH_SESSIONS[@]}"; do
        tmux kill-session -t "$s" 2>/dev/null
    done
    rm -rf "$TEST_STATE_DIR" "$SHIM_DIR"
    rm -rf /tmp/T-24-bench-cwd 2>/dev/null
}
trap cleanup_all EXIT

pass_case() { PASSED=$((PASSED+1)); RESULTS+=("PASS: $1"); printf '  [PASS] %s\n' "$1"; }
fail_case() { FAILED=$((FAILED+1)); RESULTS+=("FAIL: $1 — $2"); printf '  [FAIL] %s — %s\n' "$1" "$2"; }

# Helper: spawn ephemeral session, claim+done+approve+cleanup. Returns task-id.
prepare_cleaned_task() {
    local name="$1" cwd="$2" subject="$3"
    local task_id
    mkdir -p "$cwd"
    tmux new-session -d -s "$name" -c "$cwd" 'bash -i'
    EPH_SESSIONS+=("$name")
    task_id=$("$TMO" task add "$subject" --by orch | awk '{print $NF}')
    "$TMO" task claim "$task_id" --by "$name" >/dev/null
    "$TMO" task done "$task_id" --output "stub" >/dev/null
    "$TMO" task update "$task_id" verdict approve >/dev/null
    "$TMO" cleanup "$name" >/dev/null 2>&1
    printf '%s' "$task_id"
}

# ---------------------------------------------------------------------------
# Case 1: typical
# ---------------------------------------------------------------------------
case_typical() {
    local name="t24-typ-$$"
    local cwd="/tmp/T-24-bench-cwd"
    local task_id
    task_id=$(prepare_cleaned_task "$name" "$cwd" "T-24 typical")

    local out rc
    out=$("$TMO" session reopen "$task_id" --no-terminal --no-prompt 2>&1) ; rc=$?
    EPH_SESSIONS+=("$name")
    if [[ $rc -ne 0 ]]; then fail_case "typical" "exit=$rc out=$out"; return; fi
    if ! tmux has-session -t "$name" 2>/dev/null; then
        fail_case "typical" "tmux session not created"; return
    fi
    local pane_cwd
    pane_cwd=$(tmux display-message -t "$name" -p '#{pane_current_path}')
    if [[ "$pane_cwd" != "$cwd" ]]; then
        fail_case "typical" "pane cwd=$pane_cwd want=$cwd"; return
    fi
    # statusline check: status-format[1] must be set at session scope
    # (tmux show-options without -g reads session-scoped value).
    if ! tmux show-options -t "$name" status-format[1] 2>/dev/null \
         | grep -q "headerline"; then
        fail_case "typical" "statusline not applied at session scope"; return
    fi
    pass_case "typical"
}

# ---------------------------------------------------------------------------
# Case 2: edge-case no meta
# ---------------------------------------------------------------------------
case_edge_no_meta() {
    local task_id
    task_id=$("$TMO" task add "T-24 no-meta" --by orch | awk '{print $NF}')
    local out rc
    out=$("$TMO" session reopen "$task_id" --no-terminal --no-prompt 2>&1) ; rc=$?
    if [[ $rc -eq 0 ]]; then
        fail_case "edge-case-no-meta" "expected non-zero exit"; return
    fi
    if ! printf '%s' "$out" | grep -q "no valid session-meta"; then
        fail_case "edge-case-no-meta" "missing error msg; out=$out"; return
    fi
    pass_case "edge-case-no-meta"
}

# ---------------------------------------------------------------------------
# Case 3: anti-pattern collision
# ---------------------------------------------------------------------------
case_anti_collision() {
    local name="t24-coll-$$"
    local cwd="/tmp/T-24-bench-cwd"
    local task_id
    task_id=$(prepare_cleaned_task "$name" "$cwd" "T-24 collision")

    "$TMO" session reopen "$task_id" --no-terminal --no-prompt >/dev/null 2>&1
    EPH_SESSIONS+=("$name")
    # Now session is alive; second reopen must refuse
    local out rc
    out=$("$TMO" session reopen "$task_id" --no-terminal --no-prompt 2>&1) ; rc=$?
    if [[ $rc -eq 0 ]]; then
        fail_case "anti-pattern-name-collision" "expected refusal, got exit 0"; return
    fi
    if ! printf '%s' "$out" | grep -q "already alive"; then
        fail_case "anti-pattern-name-collision" "missing 'already alive' msg; out=$out"; return
    fi
    pass_case "anti-pattern-name-collision"
}

# ---------------------------------------------------------------------------
# Case 4: ambiguous-scope headless (no-terminal + no-prompt)
# ---------------------------------------------------------------------------
case_ambiguous_headless() {
    local name="t24-hl-$$"
    local cwd="/tmp/T-24-bench-cwd"
    local task_id
    task_id=$(prepare_cleaned_task "$name" "$cwd" "T-24 headless")

    local before_msgs
    before_msgs=$(wc -l < "$TEST_STATE_DIR/messages.jsonl")
    "$TMO" session reopen "$task_id" --no-terminal --no-prompt >/dev/null 2>&1
    EPH_SESSIONS+=("$name")
    if ! tmux has-session -t "$name" 2>/dev/null; then
        fail_case "ambiguous-scope-headless" "session not alive"; return
    fi
    # No 'note' event should have been written (since --no-prompt)
    local note_events
    note_events=$(grep -c '"event":"note"' "$TEST_STATE_DIR/messages.jsonl" || true)
    if [[ "$note_events" -gt 0 ]]; then
        fail_case "ambiguous-scope-headless" "expected 0 note events, got $note_events"; return
    fi
    pass_case "ambiguous-scope-headless"
}

# ---------------------------------------------------------------------------
# Case 5: cross-skill roundtrip (cleanup -> reopen -> cleanup again)
# ---------------------------------------------------------------------------
case_cross_roundtrip() {
    local name="t24-rt-$$"
    local cwd="/tmp/T-24-bench-cwd"
    local task_id
    task_id=$(prepare_cleaned_task "$name" "$cwd" "T-24 roundtrip")

    "$TMO" session reopen "$task_id" --no-terminal --no-prompt >/dev/null 2>&1
    EPH_SESSIONS+=("$name")

    # Re-approve + run cleanup again
    "$TMO" cleanup "$name" >/dev/null 2>&1
    local rc=$?
    if [[ $rc -ne 0 ]]; then
        fail_case "cross-skill-roundtrip" "second cleanup exit=$rc"; return
    fi
    if tmux has-session -t "$name" 2>/dev/null; then
        fail_case "cross-skill-roundtrip" "session still alive after 2nd cleanup"; return
    fi
    local desc
    desc=$("$TMO" task get "$task_id" | jq -r '.desc')
    if ! printf '%s' "$desc" | grep -q '"schema":"tmo.session-meta.v1"'; then
        fail_case "cross-skill-roundtrip" "meta lost after roundtrip"; return
    fi
    pass_case "cross-skill-roundtrip"
}

echo "[bench T-24] state=$TEST_STATE_DIR  shim=$SHIM_DIR"
echo "--- case: typical ---"
case_typical
echo "--- case: edge-case-no-meta ---"
case_edge_no_meta
echo "--- case: anti-pattern-name-collision ---"
case_anti_collision
echo "--- case: ambiguous-scope-headless ---"
case_ambiguous_headless
echo "--- case: cross-skill-roundtrip ---"
case_cross_roundtrip

TOTAL=$((PASSED + FAILED))
RATE=$(awk "BEGIN { printf \"%.2f\", $PASSED/$TOTAL }")
echo
echo "[bench T-24] passed=$PASSED failed=$FAILED total=$TOTAL pass-rate=$RATE"
for r in "${RESULTS[@]}"; do printf '  %s\n' "$r"; done

awk "BEGIN { exit !($PASSED/$TOTAL >= 0.8) }" || exit 1
