#!/usr/bin/env bash
# anti-pattern test: corrupted tasks.jsonl must make jq replay fail loudly.
# Exits non-zero IFF the corrupted-file replay errors (the desired behaviour).

set -uo pipefail
export LC_ALL=C

STATE="$(mktemp -d -t tmo-corrupt-XXXXXX)"
trap "rm -rf -- '$STATE'" EXIT

# Build a file with one valid event + one garbage line.
cat > "$STATE/tasks.jsonl" <<'EOF'
{"event":"add","id":"T-1","subject":"ok","desc":"","by":"x","ts":"2026-05-10T00:00:00Z"}
this-is-not-json
EOF

# Run the SAME jq replay the bench script uses; expect non-zero exit.
if jq -s '.[]' "$STATE/tasks.jsonl" >/dev/null 2>&1; then
    printf 'FAIL: replay accepted corrupt input\n'
    exit 0   # success here means bench would silently pass corrupt input → bad
fi

# jq printed an error somewhere; surface it so the bench-harness sees it.
jq -s '.[]' "$STATE/tasks.jsonl" 2>&1 >/dev/null | head -1
exit 1
