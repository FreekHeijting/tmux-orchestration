# tmux-orchestration repo - conventions

Geldt voor elke Claude-sessie die in deze repo werkt of die de skill `tmux-orchestration` installeert/gebruikt.

## Doel van deze repo

Distributable bron-of-truth voor de `tmux-orchestration` Claude Code skill. Bevat alleen essentiele bestanden die nodig zijn om de skill in een nieuwe workspace te installeren en te gebruiken.

## Bestand-purpose (plugin-structuur)

| Pad | Functie |
|---|---|
| `.claude-plugin/plugin.json` | Plugin manifest (naam, versie, metadata) |
| `skills/tmux-orchestration/SKILL.md` | De skill zelf. Auto-discovered door Claude Code |
| `skills/tmux-orchestration/references/` | Skill-internal naslag (cheatsheet-excerpt) |
| `roles/*.md` | Canonical role-definities. Source-of-truth, referenced via `${CLAUDE_PLUGIN_ROOT}/roles/` |
| `bin/tmo` | CLI binary. Symlink naar `~/.local/bin/tmo` na install |
| `tui/tui-rich.py` | Rich-based dashboard mockup. Optioneel runtime-tool |
| `claude-md-blocks/` | Paste-able CLAUDE.md snippets voor users (drop-in OF copy-into-existing) |
| `.vscode/tasks.json.template` | Per-workspace template voor VS Code panel auto-spawn |
| `README.md` | Prerequisites + install (plugin OF manual) + quick-start |
| `CLAUDE.md` | Deze file. Conventies voor Claude-sessies binnen deze repo |
| `LICENSE` | MIT |

## Hoe een Claude-sessie deze repo behandelt

### Bij read

- Als de huidige sessie de **orchestrator** is en de skill is getriggerd: lees `SKILL.md` voor de 8-fase flow. Volg het.
- Als sessie aan de skill **werkt** (bug-fix, feature, role-uitbreiding): lees relevante files surgical, niet alles.
- Als sessie een **nieuwe rol** heeft gegradueerd uit candidate naar stable: append role-md aan `roles/`, commit.

### Bij write

ALWAYS:
- Edit binnen scope (skill of role of cli of doc).
- Geen em-dashes in user-facing text (README, SKILL.md descripties).
- Conventional Commits (`feat:`, `fix:`, `docs:`, `refactor:`, `test:`, `chore:`) met scope (`feat(skill):`, `feat(roles):`).
- Surgical changes per Karpathy-guidelines: elke wijziging traceerbaar naar user-prompt.

NEVER:
- Geen fallbacks (`try-X-else-Y`) per global CLAUDE.md regel.
- Geen secrets/credentials.
- Geen runtime-state files (`state/`, `*.log`) gecommit.
- Geen private files (`PROMPTS.md`, `CLAUDE.local.md`) gecommit.

### Quality-gate bij wijziging aan SKILL.md

- Re-run `skill-bench` (mental of via toekomstig skill-bench skill) op wijziging.
- Triggering tests: 6 positieve, 4 negatieve, 5 functional.
- Pass-rate target: >= 0.9.
- Bij functionele wijziging: bump version in frontmatter (`metadata.version`).

### Role-graduation flow

Nieuwe rol komt als `status: candidate`. Na bewezen gebruik (graduation criteria in SKILL.md Phase 4b):
1. Run ROLE-BENCHMARK (5 test-tasks).
2. Bij pass-rate >= 0.8 en user-akkoord: edit frontmatter `status: stable`.
3. Commit: `feat(roles): graduate <name> to stable`.
4. Push naar remote.

## Install-flow voor nieuwe gebruiker

Per `README.md`. Skill leest **roles uit deze repo-pad direct** (`~/GitHub/tmux-orchestration/roles/`), dus repo MOET op die exacte locatie gecloned zijn. README documenteert dit.

## Privacy

`.gitignore` blokkeert: `state/`, `PROMPTS.md`, `SKILLS_LOG.md`, `CLAUDE.local.md`, `.vscode/*` (behalve `tasks.json` en `tasks.json.template`).

## Versie + roadmap

Huidige skill-versie staat in `SKILL.md` frontmatter `metadata.version`. Roadmap-items (toekomstig):
- `bin/tmo` uitbreiden met `tmo role-stat` subcommand voor counter-updates
- `helpers/tmux-multi-*` migreren wanneer test ze nodig heeft
- TUI dashboard (`tui/tui-rich.py`) wanneer mockup-test slaagt
- `skill-bench` skill als sidekick voor automated testing + iterating
