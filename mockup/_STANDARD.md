# Flowchart Quality Standard

Reference voor wat een duidelijke flowchart in `mockup/` betekent. ALL flowcharts
in this repo MUST honor this standard.

## Symbols (legenda — altijd opnemen onder de chart)

```
┌───────────┐    rectangle = action / state
│ Do thing  │
└───────────┘

┌────?────┐
│ choice? │   diamond (or angled box) = decision point
└────?────┘

▼ ─ ▶            arrow = transition direction
⊙                start node (filled circle or bracketed [START])
⊚                end node (double circle or bracketed [END])
```

## Rules (ALWAYS)

1. **Verb + object on every node.** Not `process`, but `decompose prompt`.
   Not `state`, but `task in review`. Reader must understand the node from
   its label alone.
2. **All paths visible.** No implicit "else"-branches. Every diamond has
   labeled outgoing edges (`yes` / `no` / specific condition).
3. **Decision points are diamonds**, never rectangles. A rectangle never
   forks.
4. **Vertical layout default.** Top-to-bottom flow for the happy path.
   Side-branches go left or right. Reasoning: terminal/markdown render is
   tall, not wide.
5. **No crossing lines** where avoidable. If unavoidable, use a small
   labeled jump-marker (`(A)` → continues at `(A)`).
6. **Legenda block at the bottom.** List every symbol used.
7. **One responsibility per chart.** If chart has 20+ nodes, split into
   sub-flowcharts and link them.
8. **Source of state changes visible.** When an arrow represents a state
   transition, label the transition with the trigger (event/command/condition).

## NEVER

- NEVER use bare `process` / `state` / `step` labels.
- NEVER omit the diamond when there's a branch.
- NEVER use color as the only differentiator (terminal users have no color).
- NEVER let arrows cross without a jump-marker.
- NEVER mix horizontal + vertical layouts in one chart.

## Examples

### GOOD: vertical flow, all paths, labeled diamonds

```
        ⊙
        │
        ▼
┌──────────────────┐
│ receive prompt   │
└────────┬─────────┘
         │
         ▼
    ┌─────────────┐
    │ multi-      │
    │ intent?     │
    └──┬───────┬──┘
   yes │       │ no
       ▼       ▼
┌───────────┐  ┌──────────────┐
│ decompose │  │ keep as one  │
│ into N    │  │ task         │
└────┬──────┘  └──────┬───────┘
     │                │
     ▼                ▼
   ┌───────────────────────┐
   │ confirm with user     │
   └──────────┬────────────┘
              │
              ▼
            ⊚

Legenda:
  ⊙ start   ⊚ end   ◇ decision (diamond)
  ─▶ transition
```

### BAD: bare labels, no decision symbol, hidden branch

```
[prompt] → [process] → [task] → [done]
```

Why bad: `process` says nothing. Where does multi-intent branching go? Where
does failure/decline go?

## State-diagram variant

For task lifecycles and similar state machines, use a state-diagram with
labeled transitions:

```
[pending] ──claim──▶ [in_progress] ──review──▶ [review]
                                                  │
                              ┌───approve─────────┤
                              ▼                   │
                          [completed]      reject │
                                              │   │
                                              ▼   │
                                          [in_progress] (loop)
```

Same rule: every transition labeled with the trigger event.

## File layout

Each mockup file should follow:

```
# <Feature name>

## Purpose
One paragraph: what this feature does and why.

## Flowchart
<ascii-art chart per standard above>

## State
<state-diagram if applicable>

## CLI / API
<signatures + brief semantics per command>

## Schema changes
<if applicable: new event types, fields, files>

## Open questions
<bullets, before commit>

## Status
- mockup: draft | reviewed | approved
- impl:   not-started | in-progress | done
- bench:  not-started | passing | failing
```

When `mockup: approved` AND `impl: done` AND `bench: passing`, the feature
is live. Until then, the mockup is the source of truth for the design.
