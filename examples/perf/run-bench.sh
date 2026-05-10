#!/usr/bin/env bash
# run-bench.sh — hermetic performance benchmark for `tmo task`.
#
# Measures latency of add/list/get and storage growth at given N.
# State-dir is an ephemeral tmpdir; live $TMO_STATE_DIR is never touched.
#
# Usage:
#   run-bench.sh <N> [csv_out]
#   run-bench.sh sweep [csv_out]            # runs N=10,100,1000,10000
#
# CSV columns:
#   N,add_p50_ms,add_p95_ms,add_p99_ms,list_ms,get_ms_avg,jsonl_kb,jq_replay_ms

set -euo pipefail
export LC_ALL=C

# ---- locate tmo (prefer worktree binary so we benchmark THIS branch) -------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TMO_BIN="$REPO_ROOT/bin/tmo"
[[ -x "$TMO_BIN" ]] || { printf >&2 'fatal: %s not executable\n' "$TMO_BIN"; exit 2; }

command -v jq  >/dev/null || { printf >&2 'fatal: jq missing\n';  exit 2; }
command -v awk >/dev/null || { printf >&2 'fatal: awk missing\n'; exit 2; }

# ---- helpers ---------------------------------------------------------------
now_ms() { date +%s%3N; }

# percentile for sorted file of numbers; degrades gracefully at N=1
percentile() {
    local file="$1" pct="$2"
    awk -v p="$pct" '
        { a[NR]=$1 } END {
            if (NR==0) { print 0; exit }
            n=NR
            i=int((p/100.0)*(n-1))+1
            if (i<1) i=1; if (i>n) i=n
            print a[i]
        }' "$file"
}

# ---- one-N bench -----------------------------------------------------------
bench_one() {
    local N="$1"
    local STATE; STATE="$(mktemp -d -t tmo-bench-XXXXXX)"
    trap "rm -rf -- '$STATE'" RETURN

    export TMO_STATE_DIR="$STATE"
    export TMO_SESSION="bench-orch-$$"

    "$TMO_BIN" init >/dev/null

    local lat_file; lat_file="$STATE/.add-latencies"
    : > "$lat_file"

    # -- add N tasks, record per-op latency in ms --
    local i t0 t1
    for ((i=1; i<=N; i++)); do
        t0=$(now_ms)
        "$TMO_BIN" task add "bench-task-$i" >/dev/null
        t1=$(now_ms)
        printf '%d\n' "$((t1 - t0))" >> "$lat_file"
    done

    # -- percentiles over add latencies --
    local sorted; sorted="$STATE/.add-sorted"
    sort -n "$lat_file" > "$sorted"
    local p50 p95 p99
    p50=$(percentile "$sorted" 50)
    p95=$(percentile "$sorted" 95)
    p99=$(percentile "$sorted" 99)

    # -- list (full replay, single shot) --
    t0=$(now_ms); "$TMO_BIN" task list >/dev/null; t1=$(now_ms)
    local list_ms=$((t1 - t0))

    # -- get for arbitrary id, avg of 3 random ids --
    local g_total=0 reps=3 r idx id
    for ((r=1; r<=reps; r++)); do
        idx=$(( (RANDOM % N) + 1 ))
        id="T-$idx"
        t0=$(now_ms); "$TMO_BIN" task get "$id" >/dev/null; t1=$(now_ms)
        g_total=$((g_total + t1 - t0))
    done
    local get_ms_avg=$((g_total / reps))

    # -- file size (kB) --
    local kb=0
    if [[ -f "$STATE/tasks.jsonl" ]]; then
        kb=$(awk '{ s+=length($0)+1 } END { printf "%.0f", s/1024 }' "$STATE/tasks.jsonl")
    fi

    # -- raw jq replay time (no tmo wrapper, isolates jq cost) --
    t0=$(now_ms)
    jq -s '
        reduce .[] as $e ({};
            if $e.event == "add" then
                .[$e.id] = {id:$e.id, status:"pending"}
            elif $e.event == "claim" then
                .[$e.id].status = "in_progress"
            elif $e.event == "done" then
                .[$e.id].status = "completed"
            else . end)
        | [.[]]' "$STATE/tasks.jsonl" >/dev/null
    t1=$(now_ms)
    local jq_ms=$((t1 - t0))

    printf '%d,%d,%d,%d,%d,%d,%d,%d\n' \
        "$N" "$p50" "$p95" "$p99" "$list_ms" "$get_ms_avg" "$kb" "$jq_ms"

    trap - RETURN
    rm -rf -- "$STATE"
}

# ---- entrypoint ------------------------------------------------------------
main() {
    [[ $# -ge 1 ]] || { printf >&2 'usage: %s <N|sweep> [csv_out]\n' "$0"; exit 2; }

    local mode="$1"; shift
    local csv_out="${1:-}"

    local header='N,add_p50_ms,add_p95_ms,add_p99_ms,list_ms,get_ms_avg,jsonl_kb,jq_replay_ms'

    if [[ "$mode" == "sweep" ]]; then
        if [[ -n "$csv_out" ]]; then
            printf '%s\n' "$header" > "$csv_out"
            for N in 10 100 1000 10000; do
                printf >&2 'bench: N=%d ...\n' "$N"
                bench_one "$N" >> "$csv_out"
            done
            printf >&2 'bench: csv written to %s\n' "$csv_out"
        else
            printf '%s\n' "$header"
            for N in 10 100 1000 10000; do
                printf >&2 'bench: N=%d ...\n' "$N"
                bench_one "$N"
            done
        fi
    else
        local N="$mode"
        [[ "$N" =~ ^[0-9]+$ ]] || { printf >&2 'fatal: N must be integer or "sweep"\n'; exit 2; }
        if [[ -n "$csv_out" ]]; then
            printf '%s\n' "$header" > "$csv_out"
            bench_one "$N" >> "$csv_out"
        else
            printf '%s\n' "$header"
            bench_one "$N"
        fi
    fi
}

main "$@"
