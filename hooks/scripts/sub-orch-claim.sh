#!/usr/bin/env bash
# sub-orch-claim.sh - SessionStart hook for tmo sub-orch sessions.
#
# When this Claude session was spawned via 'tmo spawn --task <T-id>' (or
# manually with TMO_TASK env-var set), auto-claim that task on first start.
# Idempotent: never re-claims if the same session already owns the task.
#
# Required env (set by parent shell at spawn-time):
#   TMO_TASK       - the T-id to auto-claim
#   TMO_SESSION    - this session's name (becomes the claim owner)
# State dir is resolved automatically (TMO_STATE_DIR override, else nearest .claude/).
#
# Failure modes are silent on the user side: if any of the above is missing,
# or tmo is unavailable, the hook exits 0 without blocking session start.

set -euo pipefail

# nothing to do without these
[[ -n "${TMO_TASK:-}"      ]] || exit 0
[[ -n "${TMO_SESSION:-}"   ]] || exit 0

command -v tmo >/dev/null 2>&1 || exit 0

# shellcheck source=_resolve-state-dir.sh
source "$(dirname "${BASH_SOURCE[0]}")/_resolve-state-dir.sh"
STATE_DIR="$(tmo_resolve_state_dir)"

TASKS_FILE="$STATE_DIR/tasks.jsonl"
[[ -f "$TASKS_FILE" ]] || exit 0

# pre-flight: refuse to claim a task-id that has no add-event (would write
# a bogus claim event referencing a non-existent task, which appears as a
# 'null' entry in `tmo task list`). silent exit 0.
if ! grep -qE "\"event\":\"add\"[^}]*\"id\":\"$TMO_TASK\"" "$TASKS_FILE" 2>/dev/null; then
    exit 0
fi

# idempotent: skip if a claim event by this session already exists for this task
if grep -qE "\"event\":\"claim\"[^}]*\"id\":\"$TMO_TASK\"[^}]*\"owner\":\"$TMO_SESSION\"" "$TASKS_FILE" 2>/dev/null; then
    exit 0
fi

TMO_STATE_DIR="$STATE_DIR" tmo task claim "$TMO_TASK" >/dev/null 2>&1 || true

exit 0
