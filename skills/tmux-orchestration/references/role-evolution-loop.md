# Role evolution loop - candidate to stable graduation

Detail-doc voor Phase 4b van tmux-orchestration skill. Houdt SKILL.md core lean.

## ROLE-DEFINITION-FLOW (when user picks "Other" in Phase 4)

Three-stage flow with auto-name-proposal.

### Naming convention (enforce)

`<stack-or-context>-<role-type>` in kebab-case.
- `stack` = framework/tech the role is bound to (e.g. `frappe`, `react`, `python`, `nextcloud`, `pdf`, `docker`)
- `role-type` = function (e.g. `backend`, `frontend`, `reviewer`, `debugger`, `migrator`, `tester`, `docs-writer`, `ops`)

Forbidden as standalone names: `backend`, `frontend`, `dev`, `developer`, `engineer`, `worker`, `helper`. Too generic - always require a stack/context prefix.

Examples: `frappe-backend`, `react-frontend`, `python-data-eng`, `pdf-debugger`, `docker-compose-ops`, `nextcloud-app-dev`.

### Stage A - one AskUserQuestion call with 4 single-select questions

| # | Question | Options |
|---|----------|---------|
| 1 | Domein? | frontend / backend / infra-or-ops / data-or-research |
| 2 | Output-verify-aanpak? | automated tests / visual screenshots / manual user-review / peer-worker review |
| 3 | Schrijf/edit-scope omvang? | single-file / single-component / single-package / multi-package |
| 4 | Inter-worker patroon? | independent / handoff-receiver / handoff-sender / orchestrator-only |

### Stage B - regular chat ask (free-text)

```
Voor nieuwe rol, geef in dit format:

persona: <1-2 zinnen, type expert + mindset>
stack: <hoofdtech, bv frappe, react, python, nextcloud, pdf, docker, postgres>
responsibilities: <3-5 bullets, concrete deliverables>
file-scope-pattern: <typische paths/globs deze rol claimt, kommagescheiden>
tags: <kommagescheiden, bv: frappe, doctype, server-script, restricted-python>
skills-to-use: <skill-namen of "scan" voor auto-detect>
always: <1-3 invariants>
never: <1-3 antipatterns>
short-description: <1-regel samenvatting voor frontmatter>
```

Wait for free-text reply, parse it.

### Stage C - auto-name-proposal via AskUserQuestion

Skill genereert 2-3 kandidaat-namen uit Stage A Q1 + Stage B `stack` + role-type-extract uit responsibilities. Format: `<stack>-<role-type>` kebab-case.

Voorbeelden mapping:
- domain=backend + stack=frappe + responsibilities-mention="doctype, hooks" → `frappe-backend` of `frappe-doctype-engineer`
- domain=frontend + stack=react + responsibilities-mention="components, styling" → `react-frontend` of `react-component-author`
- domain=data-or-research + stack=python + responsibilities-mention="ETL, pipeline" → `python-data-eng` of `python-pipeline-builder`

Show via AskUserQuestion: 3 voorstellen + Other. User picks or overrides.

If user-supplied name matches forbidden-generic-list: reject + force re-pick with stack-prefix.

Compose final role-md from Stage A + B + C.

## Role template (with rich metadata frontmatter)

```markdown
---
name: <stack>-<role-type>
status: candidate
description: <1-regel uit Stage B short-description>
stack: <Stage B stack>
role-type: <extracted: backend|frontend|reviewer|debugger|migrator|tester|docs-writer|ops|data-eng>
tags: [<comma-list-from-stage-B>]
domain: <Stage A Q1>
verify-approach: <Stage A Q2>
scope-size: <Stage A Q3>
inter-worker: <Stage A Q4>
created: <ISO-date>
created-by: <user-email-or-handle>
usages: 0
approve_count: 0
reinstruct_count: 0
replace_count: 0
graduation_threshold: 3-uses-low-correction-rate
last-used: null
last-bench-pass-rate: null
conflicts-with: []
---

# Role: <name>

## Persona
<stage-B-persona>

## Responsibilities
<stage-B-responsibilities-bullets>

## File-scope pattern
<stage-B-file-scope-pattern>

## Commands available
- tmo send / receive / wait-for
- <project-specific commands resolved from cwd>

## ALWAYS / NEVER
<stage-B-always-bullets>
<stage-B-never-bullets>

## Skills to actively use
<stage-B-skills-to-use>
```

## Counter-tracking

After each worker-output evaluation in the quality-gate loop, increment the role's frontmatter counters:

```bash
tmo role-stat <role-name> approve     # APPROVE verdict
tmo role-stat <role-name> reinstruct  # RE-INSTRUCT verdict
tmo role-stat <role-name> replace     # REPLACE verdict
```

If `tmo role-stat` subcommand not yet available: orchestrator edits role-md frontmatter directly via Edit tool - increments counter line.

## Graduation criteria

Default `3-uses-low-correction-rate`:
- `usages >= 3` AND `replace_count == 0` AND `reinstruct_count * 2 <= usages` (less than half required correction) → eligible to graduate

## ROLE-BENCHMARK (Karpathy autoresearch style)

When candidate role becomes eligible OR at end-of-session cleanup, run benchmark.

Generate 5 test-tasks covering these categories:
- **typical**: 1 mainline task this role would receive
- **edge-case**: 1 task at scope-boundary (large input, unusual combination)
- **anti-pattern-attempt**: 1 task that tempts a forbidden action (role's NEVER list should reject it)
- **ambiguous-scope**: 1 task where file-scope assignment is unclear (role should know to ask orchestrator)
- **cross-skill**: 1 task requiring an externally-suggested skill-hint

For each test-task: orchestrator self-evaluates whether the role's instructions are sufficient (no missing info, no contradictions, no scope-violations baked in). Score per task: `Y=1.0` (pass), `P=0.5` (partial - workable but ambiguity), `N=0.0` (fail).

Pass-rate = sum(scores) / 5. If `>= 0.8`: offer to graduate role. Log results to `state/role-bench/<role>-<iso-ts>.tsv`.

## Graduation flow

Use `AskUserQuestion`: "Promote `<role>` from candidate to stable? [Yes / Edit-first / Keep-candidate]"

- **Yes**: edit frontmatter `status: candidate` → `status: stable`, append benchmark-results to role-md, propose `git add roles/<role>.md && git commit -m "feat(roles): graduate <role> to stable"`. Push via PR or direct push per user-preference.
- **Edit-first**: open file for user, wait, re-test.
- **Keep-candidate**: do nothing, candidate stays in repo.

Result: roles grow organically. Candidates that earn their place get promoted and pushed.
