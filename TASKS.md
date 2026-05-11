# tmux-orchestration — Open Tasks

## [ ] feat: tmo dispatch — smart bundle-inject met context-check

**Branch:** `feat/tmo-dispatch`

**Beschrijving:**
Nieuw subcommand `tmo dispatch <session> <bundle-file>` dat context-check + compact + inject combineert in één stap.

**Motivatie:**
Orchestrator moet nu handmatig `tmo context-check` aanroepen vóór elke inject. Bewezen patroon (2026-05-11): bij >= 80% context stuurt `/compact <resume>` als inline commando, daarna pas de bundle. Dit verdient een first-class CLI-commando.

**Gedrag:**

```bash
tmo dispatch builder /tmp/bundle.txt
```

Interne flow:
1. `tmo context-check <session>` — leest `X% until auto-compact` uit Claude TUI
2. Als HIGH (>= 80% gebruikt):
   - Leest `# RESUME: <tekst>` header uit bundle-file als compact-instructie
   - Stuurt `/compact <resume>` als één inline commando
   - Wacht op prompt-return
3. Altijd (ook na compact): load-buffer + paste-buffer + Enter met volledige bundle

**Bundle-file convention:**

```
# RESUME: Worker tester, rol tester-debugger. Vorige taak X klaar. Wacht op orchestrator.
[from orchestrator] Volledige taak-tekst hier...
```

`tmo dispatch` leest de `# RESUME:` header voor compact-instructie. Als absent: generieke fallback `"Jij bent worker <session>. Lees de nieuwe taak en voer uit."`.

**Acceptatiecriteria:**
- `tmo dispatch` beschikbaar als subcommand in `bin/tmo`
- Context < 80%: direkte inject, geen compact
- Context >= 80%: compact met RESUME-header, daarna inject
- RESUME-header absent: fallback zonder crash
- Gedocumenteerd in `usage_root()` en SKILL.md dispatch-protocol

**Gerelateerd:**
- `tmo context-check` (commit: aanwezig)
- `tmo context-compact` (commit: aanwezig, intern gebruikt door dispatch)
- SKILL.md: dispatch-guard sectie al gedocumenteerd
