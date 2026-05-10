# Watchdog examples

Sample artifacts to bootstrap or verify a watchdog setup.

## Files

- `example-backlog.yaml` — populate `state/backlog.yaml` with two items so
  `idle-with-backlog` actions have something to prod with.
- `example-orchestrator-status.yaml` — schema reference; do not copy
  blindly, the watchdog auto-creates this file on first tick.
- `example-crontab` — cron entry that ticks every 10 minutes.
- `e2e-test.sh` — end-to-end self-test against an ephemeral tmux
  session. Exits non-zero on any phase failure.

## Quick start

```bash
# 1. install backlog so prod-backlog has something to point at
mkdir -p state
cp examples/watchdog/example-backlog.yaml state/backlog.yaml

# 2. enable watchdog for your orchestrator session
tmo watchdog enable orchestrator

# 3. add the cron entry
crontab -l 2>/dev/null > /tmp/cron.bak
cat /tmp/cron.bak examples/watchdog/example-crontab | crontab -

# 4. inspect state any time
tmo watchdog status
tail -f /tmp/tmo-watchdog.log
```

## E2E self-test

```bash
bash examples/watchdog/e2e-test.sh
```

Prints `[PASS]` for each phase or `[FAIL]` with diagnostics. Cleans up
its tmux session and state on exit.
