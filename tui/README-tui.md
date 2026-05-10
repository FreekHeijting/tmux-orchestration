# tmo TUI dashboard (rich-based mockup)

Visualization of the tmo orchestrator state in a three-panel layout.
Uses the [rich](https://github.com/Textualize/rich) library.

## Layout

| Panel  | Content |
|--------|---------|
| Header | title, session count, cwd, ISO timestamp |
| LEFT   | sessions table: name, role, status emoji, usages, last-activity |
| CENTER | message feed: latest 12 events from `state/messages.jsonl` |
| RIGHT  | detail of the selected session: file-scope, skill-hints, capture-tail |
| Footer | keybinding hints (q quit, arrows navigate, r reload) |

Status emojis: `💤` idle, `⚡` working, `⛔` blocked, `✅` done, `🔁` replaced.

Message-type colors: task=blue, status=green, peer-prompt=cyan, blocked=yellow, replace=red, done=bold green.

## Run modes

### Live loop (default)

```bash
python3 tui/tui-rich.py
```

Full-screen rich.Live, refresh every 2 seconds. `Ctrl+C` to stop.
Reads `state/sessions.yaml` + `state/messages.jsonl`. If both are missing
or empty: fallback to `tui/demo-state.json` (mockup data).

### Mockup / demo mode

```bash
python3 tui/tui-rich.py --demo
```

Force `tui/demo-state.json` as the source. Useful for screenshots, demos,
and verification during build.

### Frame rendering (non-interactive)

Print N frames to stdout and stop, no live loop. Intended for CI,
verify-conditions, and logging.

```bash
python3 tui/tui-rich.py --demo --frames 3
```

### Capture first frame as plain text

```bash
python3 tui/tui-rich.py --demo --frames 1 --capture /tmp/tui-frame.txt
```

Writes the first frame as ANSI-free text to the given path.
Usable for visual-checker hooks or vision-MCP analysis.

### Custom refresh interval

```bash
python3 tui/tui-rich.py --refresh 1.0
```

## CLI flags

| Flag | Default | Effect |
|------|---------|--------|
| `--demo` | off | use `tui/demo-state.json` (ignores live state) |
| `--frames N` | 0 | render N frames to stdout and stop |
| `--capture PATH` | (none) | write first frame as plain text to PATH |
| `--refresh S` | 2.0 | refresh interval in seconds |

## Architecture

* `load_state(demo)` reads live state or `demo-state.json`. No
  silent fallback on parse errors: malformed JSONL or YAML is raised.
* `render_*` functions each build a `rich.Panel`. Stateless,
  pure functions of `state -> Panel`.
* `build_layout()` assembles header/body/footer via `rich.Layout`,
  body splits horizontally into left/center/right.
* `pick_selected()` picks the first `working` session as the detail target,
  otherwise the first session. No keyboard navigation in v0.

## Limitations

* No live keyboard navigation (out of scope for the v0 mockup).
* No filtering or searching in the message feed.
* Capture-tail comes from demo-state. In live mode the field is shown
  only if the sessions-yaml writer supplies it.

## Schema expectation

`state/sessions.yaml`:

```yaml
session-name:
  role: <string>
  status: idle|working|blocked|done|replaced
  started_at: <ISO8601>
  last_activity: <ISO8601>
  usages: <int>
  file_scope: [<path>, ...]
  skill_hints: [<skill>, ...]
  capture_tail: [<line>, ...]
```

`state/messages.jsonl` (1 JSON per line):

```json
{"from":"sender","to":"recipient","type":"task","payload":{...},"ts":"2026-05-10T13:51:58Z"}
```

## Dependencies

Only `rich` (and `pyyaml` for live mode). No extra packages
added. No textual, no curses.
