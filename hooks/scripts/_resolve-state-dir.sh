#!/usr/bin/env bash
# Shared resolver for the workspace state dir, portable across machines and users
# (no hardcoded /home/<user>/ paths). Sourced by the hook scripts so hooks and the
# tmo CLI agree on where state lives.
#
# Order: TMO_STATE_DIR override, else the nearest ancestor directory that contains a
# .claude/ dir (the workspace root) yields <root>/.claude/state, else PWD/state.
tmo_resolve_state_dir() {
    if [[ -n "${TMO_STATE_DIR:-}" ]]; then
        printf '%s\n' "$TMO_STATE_DIR"
        return 0
    fi
    local dir="$PWD"
    while [[ "$dir" != "/" && -n "$dir" ]]; do
        if [[ -d "$dir/.claude" ]]; then
            printf '%s\n' "$dir/.claude/state"
            return 0
        fi
        dir="$(dirname "$dir")"
    done
    printf '%s\n' "$PWD/state"
}
