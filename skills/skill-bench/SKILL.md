---
name: skill-bench
description: Triggers when the user asks to benchmark, bench, validate, or grade a skill or role using Karpathy autoresearch methodology, OR when a sub-orchestrator must self-bench its work before signaling done. Use to enforce a 5-task pass-rate gate (>=0.8 = graduate) on candidate skills, candidate roles, or completed feature-branches.
version: 0.1.0
status: candidate
keywords: [bench, benchmark, validate, karpathy, autoresearch, pass-rate, graduate, skill, role, quality-gate]
---

# skill-bench

Karpathy autoresearch 5-task benchmark harness. Forces every new skill,
role, or feature to prove itself against 5 categories before being marked
done or promoted from candidate to stable.

## When to invoke (deterministic)

ALWAYS invoke when:
- user asks "bench this", "benchmark X", "validate skill", "grade role"
- a sub-orchestrator is about to call `tmo task done <T-id>`
- a candidate role needs promotion to stable (status: candidate -> stable)
- a candidate skill needs the same promotion

NEVER invoke when:
- the work is a one-line bug-fix or typo (no behavioral surface to bench)
- the user explicitly asks to skip bench ("just merge", "no bench needed")

## Methodology (Karpathy autoresearch)

Every benchable target gets exactly 5 cases. The categories are fixed:

| # | category | what it tests |
|---|----------|---------------|
| 1 | typical | the happy path the feature was built for |
| 2 | edge-case | boundary input (empty, max, malformed) |
| 3 | anti-pattern | input that SHOULD be rejected/handled |
| 4 | ambiguous-scope | request outside scope (must not regress adjacent features) |
| 5 | cross-skill | adjacent feature still works after the change |

Pass-rate = PASS / (PASS + FAIL). SKIP cases are excluded from denominator.

Threshold: `pass-rate >= 0.8` (i.e. >=4/5 PASS, with 0 SKIPs).
Below threshold: iterate on the work; do not graduate.

## Workflow

1. **Generate template**: `skill-bench gen <target>` writes a fresh yaml at
   `bench/<target>-<timestamp>.yaml` with 5 empty cases.
2. **Fill cases**: edit yaml. For each case set `description`, `expected`,
   then run/observe the target, set `actual` + `verdict`.
3. **Score**: `skill-bench score <yaml>` outputs PASS/FAIL/SKIP counts and
   pass-rate. Exit code 0 if rate >= 0.8 else 1.
4. **Commit** the yaml alongside the feature change so the bench is
   reproducible from git history.

## Bench file schema

```yaml
target: <role-md path | skill SKILL.md path | feature description>
created: <ISO timestamp>
methodology: karpathy-autoresearch-5task
graduate-threshold: 0.8

cases:
  - id: 1
    category: typical
    description: <what scenario>
    expected: <observable outcome>
    actual: <what happened>
    verdict: PASS | FAIL | SKIP
    notes: <evidence: capture-pane excerpt, log line, file diff>
  ... (4 more)
```

## ALWAYS rules

ALWAYS produce 5 cases. Never 3 or 4. Cross-skill case must reference an
EXISTING adjacent feature, not a hypothetical one.

ALWAYS commit the bench yaml when committing the feature. The bench is part
of the artifact, not throwaway scaffolding.

ALWAYS cite evidence in `notes` for FAIL verdicts (which assertion failed,
which capture-pane excerpt). FAIL without evidence = SKIP.

ALWAYS re-run the bench after iterating on the feature. Stale results are
worse than no results.

## NEVER rules

NEVER mark verdict PASS without observing the actual behavior end-to-end.
"Code looks right" is a SKIP, not a PASS.

NEVER skip the anti-pattern case to inflate the pass-rate. Anti-pattern is
the most informative case.

NEVER graduate a target that has 1+ SKIP and rate >=0.8 by skipping the
hard case. SKIP must be justified in notes (e.g. "category cross-skill
not applicable: this is a leaf feature with no adjacent skill").

## Tooling

- `skill-bench gen <target> [out-file]` writes template
- `skill-bench score <bench-file>` computes pass-rate, exits 0 if PASS

Location: `bin/skill-bench` (also symlinked into ~/.local/bin via
plugin install.sh).

## Self-bench

skill-bench was built using its own methodology. See
`bench/skill-bench-self-v0.1.yaml` in the repo for the founding bench.
Pass-rate at v0.1.0: 5/5.
