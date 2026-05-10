#!/usr/bin/env bash
# Karpathy bench driver — reads bench/T-7-bench-orch.yaml, executes each
# case, evaluates expectations, prints per-case PASS/FAIL and a final
# pass-rate.
#
# YAML parsing is delegated to python3 (always available in this repo).

set -euo pipefail
export LC_ALL=C

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
YAML="${1:-$REPO_ROOT/bench/T-7-bench-orch.yaml}"
[[ -f "$YAML" ]] || { printf >&2 'fatal: %s missing\n' "$YAML"; exit 2; }

cd "$REPO_ROOT"

# Emit "id|cmd|exp_code|exp_nonzero|sc|snc|sosc|run_under" per case.
mapfile -t LINES < <(
    python3 - "$YAML" <<'PYEOF'
import sys, yaml
with open(sys.argv[1]) as f:
    doc = yaml.safe_load(f)
for c in doc.get("cases", []):
    e = c.get("expect", {}) or {}
    fields = [
        c.get("id", ""),
        c.get("command", ""),
        str(e.get("exit_code", "")),
        "1" if e.get("exit_code_nonzero") else "0",
        e.get("stdout_contains", ""),
        e.get("stdout_not_contains", ""),
        e.get("stdout_or_stderr_contains", ""),
        str(e.get("runtime_under_s", "")),
    ]
    print("|".join(fields))
PYEOF
)

passes=0
total=0
results=()

for line in "${LINES[@]}"; do
    IFS='|' read -r cid cmd exp_code exp_nonzero sc snc sosc run_under <<< "$line"
    total=$((total+1))

    out_file="$(mktemp)"
    err_file="$(mktemp)"

    t0=$(date +%s)
    set +e
    bash -c "$cmd" > "$out_file" 2> "$err_file"
    rc=$?
    set -e
    t1=$(date +%s)
    elapsed=$((t1 - t0))

    out="$(cat "$out_file")"
    err="$(cat "$err_file")"
    rm -f "$out_file" "$err_file"

    fail_reasons=()

    if [[ -n "$exp_code" ]]; then
        if [[ "$rc" -ne "$exp_code" ]]; then
            fail_reasons+=("exit=$rc want=$exp_code")
        fi
    fi
    if [[ "$exp_nonzero" == "1" && "$rc" -eq 0 ]]; then
        fail_reasons+=("exit=0 want nonzero")
    fi
    if [[ -n "$sc" ]] && ! grep -qF "$sc" <<< "$out"; then
        fail_reasons+=("stdout missing '$sc'")
    fi
    if [[ -n "$snc" ]] && grep -qiF "$snc" <<< "$out"; then
        fail_reasons+=("stdout has forbidden '$snc'")
    fi
    if [[ -n "$sosc" ]] && ! { grep -qF "$sosc" <<< "$out" || grep -qF "$sosc" <<< "$err"; }; then
        fail_reasons+=("stdout+stderr missing '$sosc'")
    fi
    if [[ -n "$run_under" && "$elapsed" -gt "$run_under" ]]; then
        fail_reasons+=("runtime ${elapsed}s > ${run_under}s")
    fi

    if (( ${#fail_reasons[@]} == 0 )); then
        printf 'PASS  %-18s  (%ds)\n' "$cid" "$elapsed"
        passes=$((passes+1))
        results+=("PASS|$cid|$elapsed")
    else
        printf 'FAIL  %-18s  (%ds)  -- %s\n' "$cid" "$elapsed" "$(IFS='; '; echo "${fail_reasons[*]}")"
        results+=("FAIL|$cid|$elapsed|${fail_reasons[*]}")
    fi
done

rate="0"
if (( total > 0 )); then
    rate=$(awk -v p="$passes" -v t="$total" 'BEGIN{ printf "%.2f", p/t }')
fi

printf '\n----\nKarpathy bench: %d/%d pass (rate=%s)\n' "$passes" "$total" "$rate"

# Exit non-zero if pass-rate < 0.8 (sub-orch-builder threshold).
awk -v r="$rate" 'BEGIN{ exit (r+0 < 0.8) }'
