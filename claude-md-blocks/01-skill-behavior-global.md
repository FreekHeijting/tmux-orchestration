<!--
BLOCK: tmux-orchestration skill behavior (global)

Paste in: ~/.claude/CLAUDE.md (user-global instructions)
OR: workspace-level CLAUDE.md if you only want this in one project
OR: standalone read by Claude when relevant

Purpose: enforce skill behaviors that must hold even when the skill is not actively loaded into context.
-->

## tmux-orchestration skill behavior

Wanneer de `tmux-orchestration` skill actief is OF wanneer een Claude-sessie als worker draait (`$TMO_SESSION` is gezet), gelden deze regels:

### Worker-sessies

- ALWAYS check `$TMO_SESSION` env-var bij sessie-start. Indien gezet: ben je een worker. Lees je context-bundel (eerste user-prompt na claude-startup). Volg het.
- ALWAYS rapporteer status via `tmo send orchestrator status '{"phase":"working|done|blocked"}'` bij elke fase-overgang.
- ALWAYS check je inbox eerst: `TMO_SESSION=$TMO_SESSION tmo receive` voor je een nieuwe taak begint.
- ALWAYS edit alleen binnen je gedeclareerde file-scope. Buiten scope = `tmo send orchestrator blocked` en stop.
- NEVER spawn additional tmux sessies vanuit een worker.
- NEVER edit files in een peer worker's file-scope.
- NEVER skip prompt-improver hooks. Bij `[PROMPT-IMPROVER ACTIVE]`: run improvement-flow, default-respond `ja` (accepteer verbeterde versie).

### Inter-worker communicatie

- PREFER direct peer-injection: gebruik `tmux load-buffer + paste-buffer + 2-step Enter` om een prompt in peer-worker's pane te plaatsen. ALWAYS koppel met `tmo send <peer> peer-prompt '{"from":"<self>","mode":"direct"}'` voor audit-log.
- Bij faal van direct peer-injection: ALWAYS fall back via `tmo send orchestrator forward '{"to":"<peer>","payload":...}'`.
- ALWAYS treat `state/messages.jsonl` als centrale forum + audit-trail.

### Quality-gate (orchestrator-zijde)

- ALWAYS evalueer worker-output: APPROVE / RE-INSTRUCT / REPLACE.
- NEVER laat een worker stilzwijgend doorgaan met slechte output.
- Bij REPLACE: `tmux kill-session` + re-spawn met verbeterde context-bundle.
