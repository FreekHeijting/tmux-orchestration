# `tmo task` performance results — T-7

Empirical benchmark of the event-sourced `tasks.jsonl` store. Runs are
hermetic: each `N` uses a fresh `mktemp -d` state-dir and never touches
`$TMO_STATE_DIR`.

Reproduce: `examples/perf/run-bench.sh sweep examples/perf/results.csv`

## Raw measurements

| N      | add p50 (ms) | add p95 (ms) | add p99 (ms) | list (ms) | get avg (ms) | tasks.jsonl (kB) | raw jq replay (ms) |
|--------|-------------:|-------------:|-------------:|----------:|-------------:|-----------------:|-------------------:|
|     10 |           11 |           16 |           16 |         8 |            8 |                1 |                  4 |
|    100 |           11 |           14 |           15 |        14 |           11 |               12 |                  5 |
|   1000 |           11 |           15 |           18 |        42 |           42 |              117 |                 12 |
|  10000 |           11 |           14 |           17 |     1 561 |        1 619 |            1 189 |                 91 |

Run platform: Linux 6.17, bash 5, jq present, single warm machine.

## ASCII histogram — list latency vs N (log-N axis)

```
N=    10 |▏              8 ms
N=   100 |▎             14 ms
N=  1000 |█             42 ms
N= 10000 |██████████  1561 ms
```

ASCII histogram — get latency:

```
N=    10 |▏              8 ms
N=   100 |▏             11 ms
N=  1000 |█             42 ms
N= 10000 |██████████  1619 ms
```

## Findings

1. **`tmo task add` is constant-time at this scale.** p50 ~11 ms across
   N=10..10000. Cost is dominated by bash + jq fork overhead, not by
   replay. `_next_task_id` greps `tasks.jsonl` for `"event":"add"`, which
   is fast enough that 10000 lines disappear in noise.

2. **`tmo task list` and `tmo task get` scale linearly with N.** Both
   trigger `_tasks_replay`, which jq-slurps the entire file into a dict.
   At N=10000 a single `list` or `get` call costs ~1.6 s.

3. **The replay itself is cheap; the wrapper is the tax.** Raw jq replay
   on the same file is 91 ms at N=10000. The `tmo task list` runtime is
   1561 ms, so ~1.5 s of overhead sits in the bash wrapper: shell init,
   `require_state`, two jq processes piped (`_tasks_replay | jq …`),
   `iso_ts` calls, etc. The replay is not the bottleneck.

4. **Storage growth is linear and modest.** 1.19 MB at N=10000. JSONL
   line ~119 bytes average. No compaction needed below N=100k.

## Threshold decision

The dispatch defines bottleneck thresholds: any operation > 1 s at
N=1000 or > 5 s at N=10000 must be optimised.

| Operation | N=1000 | < 1 s? | N=10000 | < 5 s? |
|-----------|-------:|:------:|--------:|:------:|
| add (p99) |   18ms |   yes  |    17ms |   yes  |
| list      |   42ms |   yes  |  1561ms |   yes  |
| get       |   42ms |   yes  |  1619ms |   yes  |

**No threshold breached. No optimisation performed.** `tmo task` is
acceptable up to N=10000 at single-user latency.

## When to revisit

- If usage grows to N >> 10000 in a single state-dir, fold replay into a
  cached snapshot (rebuild on append, reuse on read). Linear `list/get`
  cost will become noticeable above ~30000 entries (extrapolated).
- If `list` is hot-pathed by an interactive UI, reduce the wrapper tax
  by collapsing the two-jq pipe into a single jq pipeline.

Neither change is justified by current data.
