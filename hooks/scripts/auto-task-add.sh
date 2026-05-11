#!/usr/bin/env bash
# auto-task-add.sh - UserPromptSubmit hook.
# Reads JSON event from stdin and forwards every user prompt to tmo task
# as a candidate task. Orchestrator (the Claude session in this workspace)
# promotes / dedupes / closes them later.
#
# Behavior:
# - Always appends a tmo task entry with status=pending and the prompt as subject
#   (truncated to 200 chars, single-line). Source-of-truth for "what did the user
#   actually ask for, exactly when".
# - Skips empty prompts, prompts that look like one-word acks (yes/ja/no/oke/ok),
#   and prompts that already start with "[from " (peer-injected sidenotes).
# - Adds metadata field source=user-prompt-submit + ts.
# - Failure-modes are silent on the user side: if tmo is missing or state-dir
#   absent, the hook exits 0 without blocking the prompt.
#
# Required: jq, tmo on PATH, TMO_STATE_DIR pointing at a workspace with state/
# already initialized (run `tmo init` once per orchestrator workspace).

set -euo pipefail

command -v jq  >/dev/null 2>&1 || exit 0
command -v tmo >/dev/null 2>&1 || exit 0

input=$(cat)
prompt=$(printf '%s' "$input" | jq -r '.prompt // empty' 2>/dev/null || true)
[[ -n "$prompt" ]] || exit 0

# strip leading/trailing whitespace, collapse newlines
trimmed=$(printf '%s' "$prompt" | tr '\n' ' ' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g; s/[[:space:]]+/ /g')
[[ -n "$trimmed" ]] || exit 0

# skip very short acks
if [[ ${#trimmed} -le 4 ]]; then
    exit 0
fi
case "$trimmed" in
    "yes"|"ja"|"no"|"nee"|"oke"|"ok"|"akkoord"|"skip"|"ga door"|"doorgaan"|"klaar")
        exit 0
        ;;
esac

# skip peer-inject sidenotes
case "$trimmed" in
    "[from "*|"[SIDENOTE "*) exit 0 ;;
esac

# truncate
subject="${trimmed:0:200}"
[[ ${#trimmed} -gt 200 ]] && subject="${subject}..."

# resolve state dir
STATE_DIR="${TMO_STATE_DIR:-${PWD}/state}"
[[ -d "$STATE_DIR" ]] || exit 0
[[ -f "$STATE_DIR/messages.jsonl" ]] || exit 0

# capture session metadata for later re-open / re-attach
sess_id="${TMO_SESSION:-claude-main}"
cwd_p="${PWD:-unknown}"
tmux_sess="$(tmux display-message -p -F '#S' 2>/dev/null || echo "none")"
desc="session=${sess_id} cwd=${cwd_p} tmux=${tmux_sess} ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# capture last 3 user-prompt tasks as "recent context" so the new task sees
# the conversational background. Limit ~500 chars total.
ctx=""
TASKS_F="$STATE_DIR/tasks.jsonl"
if [[ -f "$TASKS_F" ]]; then
    recent=$(jq -r 'select(.event == "add" and (.by // "") == "user-prompt-submit-hook")
                   | "\(.id) \(.subject)"' "$TASKS_F" 2>/dev/null | tail -3)
    if [[ -n "$recent" ]]; then
        # collapse newlines + truncate
        ctx_raw=$(printf '%s' "$recent" | tr '\n' '|' | sed 's/|$//')
        ctx="${ctx_raw:0:500}"
    fi
fi

if [[ -n "$ctx" ]]; then
    TMO_STATE_DIR="$STATE_DIR" tmo task add "$subject" --desc "$desc" --by user-prompt-submit-hook --context "recent prompts: $ctx" >/dev/null 2>&1 || true
else
    TMO_STATE_DIR="$STATE_DIR" tmo task add "$subject" --desc "$desc" --by user-prompt-submit-hook >/dev/null 2>&1 || true
fi

exit 0
