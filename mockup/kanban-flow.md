# Kanban-flow voor tmo task

Mockup voor T-28 (kanban decompose + review + approve + reject + board).
Follows `mockup/_STANDARD.md`.

## Purpose

Geen user-request mag direct naar worker zonder eerst een tmo task te zijn.
Multi-intent prompts moeten worden gedecomponeerd in N taken voordat actie
genomen wordt. Tussen `in_progress` en `completed` komt een verplichte
`review`-status zodat de orchestrator quality-gate altijd zichtbaar is.
Taken bevatten **complete + eerlijke + contextuele** omschrijving (wat user
literally vroeg, waarom, success-criteria, scope/constraints).

## Full flowchart (user-prompt → completed task)

```
                       ⊙ user submits prompt
                       │
                       ▼
        ┌────────────────────────────────┐
        │ UserPromptSubmit hook fires    │
        │ auto-task-add.sh appends raw   │
        │ prompt as T-X with context     │
        │ (last 3 prompts prepended)     │
        └──────────────┬─────────────────┘
                       │
                       ▼
              ┌──────────────────┐
              │ multi-intent     │
              │ in prompt?       │
              └──┬────────────┬──┘
            yes  │            │  no
                 ▼            ▼
   ┌─────────────────────┐  ┌──────────────────────────┐
   │ orchestrator        │  │ keep T-X as the          │
   │ decomposes into     │  │ single actionable task   │
   │ N child subjects    │  │ enrich desc if shallow   │
   │ + context inherit   │  │ (what + why + criteria)  │
   └──────────┬──────────┘  └────────────┬─────────────┘
              │                          │
              ▼                          │
   ┌──────────────────────────┐          │
   │ show decomp to user      │          │
   │ ask: ja / skip / fix     │          │
   └────────────┬─────────────┘          │
                │                        │
                ▼                        │
        ┌───────────────┐                │
        │ user replies? │                │
        └──┬─────────┬──┘                │
        ja │      fix│                   │
           │         ▼                   │
           │   ┌──────────────┐          │
           │   │ revise N     │          │
           │   │ subjects per │          │
           │   │ user input   │          │
           │   └──────┬───────┘          │
           │          │                  │
           └─────┬────┘                  │
                 ▼                       │
   ┌──────────────────────────┐          │
   │ tmo task decompose T-X   │          │
   │   "sub1" "sub2" ...      │          │
   │ creates T-Y, T-Z, ...    │          │
   │ each inherits parent     │          │
   │   = T-X + raw-context    │          │
   │ T-X auto-done with       │          │
   │   output="decomposed →   │          │
   │   T-Y, T-Z, ..."         │          │
   └────────────┬─────────────┘          │
                │                        │
                └────────┬───────────────┘
                         │
                         ▼
              ┌──────────────────────┐
              │ for each child task: │
              │ pick role + worktree │
              │ + dispatch sub-orch  │
              └──────────┬───────────┘
                         │
                         ▼
              ┌──────────────────────┐
              │ SessionStart hook    │
              │ → tmo task claim     │
              │ (status: pending →   │
              │   in_progress)       │
              └──────────┬───────────┘
                         │
                         ▼
              ┌──────────────────────┐
              │ sub-orch works,      │
              │ self-benches via     │
              │ skill-bench          │
              └──────────┬───────────┘
                         │
                         ▼
              ┌──────────────────────┐
              │ bench pass-rate?     │
              └──┬─────────────────┬─┘
              >=0.8                <0.8
                 │                   │
                 ▼                   ▼
   ┌──────────────────────┐   ┌──────────────────────┐
   │ tmo task review T-Y  │   │ iterate on feature   │
   │   --evidence "<sha>  │   │ re-run bench         │
   │   + bench rate +     │   │ (loop)               │
   │   capture-pane url"  │   └──────────┬───────────┘
   └──────────┬───────────┘              │
              │                          │
              │           ┌──────────────┘
              │           │
              │           ▼
              │     back to in_progress
              │
              ▼
   ┌──────────────────────┐
   │ status: review       │
   │ orchestrator alerted │
   │ via sidenote + tmo   │
   │ task board shows it  │
   └──────────┬───────────┘
              │
              ▼
   ┌──────────────────────┐
   │ orchestrator reviews:│
   │ - diff               │
   │ - bench yaml         │
   │ - e2e output         │
   │ - scope compliance   │
   └──┬─────────────────┬─┘
   approve            reject
      │                 │
      ▼                 ▼
┌─────────────────┐  ┌──────────────────────────┐
│ tmo task        │  │ tmo task reject T-Y      │
│   approve T-Y   │  │   --reason "<text>"      │
│ (records gate-  │  │ status: review →         │
│  decision +     │  │   in_progress            │
│  approver       │  │ re-instruct sub-orch     │
│  identity)      │  │ via tmo note (specific   │
└────────┬────────┘  │   change requested)      │
         │           └────────┬─────────────────┘
         ▼                    │
┌─────────────────┐           │
│ tmo task done   │           └─────────► back to in_progress loop
│   T-Y --output  │
│   "<merge sha>" │
│ status:         │
│   completed     │
└────────┬────────┘
         │
         ▼
         ⊚

Legenda:
  ⊙ start            ⊚ end
  ◇ decision (yes/no/specific condition labeled)
  ─▶ transition       (A) → (A) jump-marker if needed
  rectangles = action / state
```

## Task state-diagram

```
                   ┌──────────────┐
                   │   pending    │ ←─── tmo task add
                   └──────┬───────┘      tmo task decompose (children)
                          │
                  claim   │ (auto via SessionStart hook
                          │  OR manual: tmo task claim)
                          ▼
                   ┌──────────────┐
                   │ in_progress  │
                   └──┬─────────┬─┘
                      │         │
              review  │         │  (worker abandons)
                      │         │
                      ▼         ▼
              ┌──────────────┐  ┌─────────────┐
              │   review     │  │  pending    │ (un-claim, rare)
              └──┬────────┬──┘  └─────────────┘
        approve  │        │  reject
                 │        │
                 ▼        ▼
       ┌─────────────┐   ┌──────────────┐
       │  completed  │   │ in_progress  │ (loop, re-do)
       └─────────────┘   └──────────────┘

(parent decomposition):
       ┌──────────────────┐    decompose      ┌─────────────────┐
       │ raw prompt task  │ ──────────────────│  N child tasks  │
       │ (status=pending) │                   │  (parent=raw-id)│
       └─────────┬────────┘                   └─────────────────┘
                 │
                 ▼
       ┌──────────────────┐
       │ auto-done with   │
       │ output="decompo- │
       │ sed → T-X..."    │
       └──────────────────┘
```

## CLI signatures (new + changed)

```
tmo task add <subject>
  [--desc <text>]
  [--by <handle>]
  [--context <text>]           ← NEW: situational context, prepended in desc
  [--parent <id>]              ← NEW: link to parent task (decomposed children)

tmo task decompose <parent-id> <subject1> <subject2> ...
  [--context <text>]           ← inherited by all children
  effect: adds N children with parent=<parent-id>,
          auto-emits done event on <parent-id> with
          output="decomposed → T-X, T-Y, ..."

tmo task review <id>
  --evidence <text>            ← MANDATORY: sha, bench-rate, capture-pane url
  effect: status in_progress → review

tmo task approve <id>
  [--by <name>]
  effect: gate-decision recorded.
          Hint: caller usually follows with `tmo task done <id> --output ...`

tmo task reject <id>
  --reason <text>              ← MANDATORY
  [--by <name>]
  effect: status review → in_progress; appends reject event with reason

tmo task board
  [--include-completed]        ← default: hide completed
  effect: kanban-style output, 4 columns

  ┌───────────────┬───────────────┬───────────────┬───────────────┐
  │ pending       │ in_progress   │ review        │ completed     │
  ├───────────────┼───────────────┼───────────────┼───────────────┤
  │ T-30  workspc │ T-33  kanban  │ T-Y  feat-x   │ T-1  skill-b. │
  │ T-31  skill-r │ ...           │ ...           │ ...           │
  │ ...           │               │               │               │
  └───────────────┴───────────────┴───────────────┴───────────────┘

tmo task list                  ← unchanged but knows review status now
tmo task get <id>              ← shows parent/context/review-evidence in output
```

## Schema changes (tasks.jsonl events)

| event type | new?      | fields                                              | replay effect                                           |
|------------|-----------|-----------------------------------------------------|---------------------------------------------------------|
| add        | extended  | + context (str), + parent (id or null)              | status=pending; context/parent stored                   |
| claim      | unchanged | id, owner, ts                                       | status=in_progress; owner set                           |
| update     | unchanged | id, field, value, ts                                | overwrite field                                         |
| decompose  | NEW       | id (parent), children: [{id, subject}], by, ts      | each child added as add-event; parent auto-done event   |
| review     | NEW       | id, evidence (str, required), by, ts                | status=review; evidence stored                          |
| approve    | NEW       | id, by, ts                                          | gate-decision: approve. Does NOT auto-done.             |
| reject     | NEW       | id, reason (str, required), by, ts                  | status=review → in_progress; reason stored              |
| done       | unchanged | id, output, ts                                      | status=completed                                        |

Replay-rule still "latest event per id wins for status", with new statuses
`review` and the existing chain pending → in_progress → review → completed.

Replayed task object adds fields: `parent`, `context`, `evidence`, `gate`
(approve/reject/null), `reject_reason`.

## Description-completeness rule

Every `tmo task add` (and decompose-children) MUST set a `desc` that captures:

1. **What** the user literally asked (verbatim short quote where possible)
2. **Why** / context (situation in which it was asked)
3. **Success criteria** (what does done look like, observable)
4. **Scope / constraints** (what is NOT in scope, file boundaries if known)

NEVER summarize to vague labels. NEVER omit context. If the prompt is short
("doe X"), the desc must still capture the situational context from the last
few user prompts and the current orchestrator state.

## auto-task-add hook context-capture

Hook extension: when capturing a new user prompt, also read the last 3
user-prompt entries from `state/messages.jsonl` (or `tasks.jsonl` filtered
by `by=user-prompt-submit-hook`), and prepend a "recent context: ..." block
to the desc field. Limit ~500 chars total.

## Open questions (pre-build)

- [x] confirm flow: orchestrator shows decomp + asks ja/skip/fix → DECIDED yes
- [x] review-status required for all sub-orch → DECIDED yes
- [ ] reject: also send sidenote to worker automatically? (proposed: yes,
      with reason verbatim)
- [ ] approve + done in one command? (proposed: keep separate; approve
      records gate-decision, done records merge-sha)
- [ ] should `tmo task board` show parent → children grouping? (proposed:
      v2; v1 = flat columns)

## Karpathy 5-task bench plan (T-37)

| # | category         | scenario                                                                 |
|---|------------------|--------------------------------------------------------------------------|
| 1 | typical          | decompose 3-intent prompt → 3 children + parent auto-done                |
| 2 | edge-case        | decompose with 1 child (no-op-like) still works without warning          |
| 3 | anti-pattern     | decompose with 0 subjects → refuse, exit non-zero, no events written     |
| 4 | ambiguous-scope  | decompose preserves any prior status/verdict on parent before close      |
| 5 | cross-skill      | tmo task list + tmo task get still work with new event types in jsonl    |

Threshold: 5/5 PASS = graduate. Bench yaml committed at `bench/T-28-kanban-flow.yaml`.

## Status

- mockup: draft (awaiting user confirm before build)
- impl:   not-started
- bench:  not-started
- hook:   not-started
