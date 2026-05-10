#!/usr/bin/env bash
# install.sh - install or update the tmux-orchestration plugin on this machine.
# Idempotent. Re-run after every git pull / merge.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
SKILL_INSTALL="${HOME}/.claude/skills/tmux-orchestration"
LOCAL_BIN="${HOME}/.local/bin"

echo "tmux-orchestration installer"
echo "  repo:  $REPO_ROOT"
echo "  skill: $SKILL_INSTALL"
echo "  bin:   $LOCAL_BIN"
echo

# 1. tmo CLI symlink
mkdir -p "$LOCAL_BIN"
ln -sfn "$REPO_ROOT/bin/tmo" "$LOCAL_BIN/tmo"
chmod +x "$REPO_ROOT/bin/tmo"
printf '[1/3] symlink %-18s -> %s\n' "$LOCAL_BIN/tmo" "$REPO_ROOT/bin/tmo"

# 1b. skill-bench CLI symlink
ln -sfn "$REPO_ROOT/bin/skill-bench" "$LOCAL_BIN/skill-bench"
chmod +x "$REPO_ROOT/bin/skill-bench"
printf '      symlink %-18s -> %s\n' "$LOCAL_BIN/skill-bench" "$REPO_ROOT/bin/skill-bench"

# 2. Skill files (overwrites, including SKILL.md and references/)
mkdir -p "$SKILL_INSTALL/references"
cp -f "$REPO_ROOT/skills/tmux-orchestration/SKILL.md" "$SKILL_INSTALL/SKILL.md"
cp -fr "$REPO_ROOT/skills/tmux-orchestration/references/." "$SKILL_INSTALL/references/"
printf '[2/3] sync %-21s -> %s\n' "skill files" "$SKILL_INSTALL"

# 3. CLAUDE_PLUGIN_ROOT export hint (idempotent in ~/.bashrc)
PLUGIN_EXPORT="export CLAUDE_PLUGIN_ROOT=$REPO_ROOT"
if ! grep -qF "$PLUGIN_EXPORT" "$HOME/.bashrc" 2>/dev/null; then
    echo "$PLUGIN_EXPORT" >> "$HOME/.bashrc"
    printf '[3/3] appended CLAUDE_PLUGIN_ROOT export to ~/.bashrc (re-source to activate)\n'
else
    printf '[3/3] CLAUDE_PLUGIN_ROOT already set in ~/.bashrc\n'
fi

echo
echo "verify:"
echo "  tmo --version"
echo "  tmo watchdog --help"
echo "  ls $SKILL_INSTALL/references/"
echo
echo "tmux-orchestration installed."
