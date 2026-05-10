#!/usr/bin/env bash
# ambiguous-scope test: run bench at small N, then assert no bench tasks
# leaked into the live state-dir.

set -euo pipefail
export LC_ALL=C

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LIVE="${TMO_STATE_DIR:-$HOME/GitHub/tmux-orchestrator/state}/tasks.jsonl"
[[ -f "$LIVE" ]] || { printf 'SKIP: live %s not found\n' "$LIVE"; exit 0; }

# Snapshot any pre-existing "bench-task-" hits in live (should be 0,
# but tolerate prior runs that may have left stale data).
before=$(grep -c '"bench-task-' "$LIVE" 2>/dev/null || true)
before=${before:-0}

# Run a small bench.
"$REPO_ROOT/examples/perf/run-bench.sh" 5 >/dev/null

after=$(grep -c '"bench-task-' "$LIVE" 2>/dev/null || true)
after=${after:-0}

if [[ "$before" == "$after" ]]; then
    printf 'HERMETIC_OK before=%s after=%s\n' "$before" "$after"
    exit 0
fi

printf 'HERMETIC_FAIL before=%s after=%s\n' "$before" "$after"
exit 1
