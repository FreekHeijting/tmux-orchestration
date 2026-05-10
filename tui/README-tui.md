# tmo TUI dashboard (rich-based mockup)

Visualisatie van de tmo orchestrator-state in een drie-paneel layout.
Gebruikt de [rich](https://github.com/Textualize/rich) library.

## Layout

| Paneel | Inhoud |
|--------|--------|
| Header | titel, sessie-count, cwd, ISO timestamp |
| LEFT   | sessies-tabel: name, role, status-emoji, usages, last-activity |
| CENTER | message feed: laatste 12 events uit `state/messages.jsonl` |
| RIGHT  | detail van geselecteerde sessie: file-scope, skill-hints, capture-tail |
| Footer | keybinding-hints (q quit, arrows navigate, r reload) |

Status-emoji's: `💤` idle, `⚡` working, `⛔` blocked, `✅` done, `🔁` replaced.

Message-types kleuren: task=blauw, status=groen, peer-prompt=cyan, blocked=geel, replace=rood, done=bold groen.

## Run-modes

### Live loop (default)

```bash
python3 tui/tui-rich.py
```

Vol-screen rich.Live, refresh per 2 seconden. `Ctrl+C` om te stoppen.
Leest `state/sessions.yaml` + `state/messages.jsonl`. Als beide ontbreken
of leeg zijn: fallback naar `tui/demo-state.json` (mockup-data).

### Mockup / demo-mode

```bash
python3 tui/tui-rich.py --demo
```

Forceer `tui/demo-state.json` als bron. Handig voor screenshots, demo's,
en voor verificatie tijdens build.

### Frame-rendering (non-interactive)

Print N frames naar stdout en stop, geen live-loop. Bedoeld voor CI,
verify-conditions en logging.

```bash
python3 tui/tui-rich.py --demo --frames 3
```

### Capture eerste frame als plain text

```bash
python3 tui/tui-rich.py --demo --frames 1 --capture /tmp/tui-frame.txt
```

Schrijft eerste frame als ANSI-vrije tekst naar het opgegeven pad.
Bruikbaar voor visual-checker hooks of vision-MCP analyse.

### Custom refresh-interval

```bash
python3 tui/tui-rich.py --refresh 1.0
```

## CLI-flags

| Flag | Default | Effect |
|------|---------|--------|
| `--demo` | uit | gebruik `tui/demo-state.json` (negeert live state) |
| `--frames N` | 0 | render N frames naar stdout en stop |
| `--capture PATH` | (geen) | schrijf eerste frame plain-text naar PATH |
| `--refresh S` | 2.0 | refresh-interval in seconden |

## Architectuur

* `load_state(demo)` leest live state of `demo-state.json`. Geen
  silent fallback bij parse-errors: malformed JSONL of YAML raised.
* `render_*` functies bouwen elk een `rich.Panel`. Stateless,
  pure functies van `state -> Panel`.
* `build_layout()` zet header/body/footer samen via `rich.Layout`,
  body splitst horizontaal in left/center/right.
* `pick_selected()` kiest de eerste `working` sessie als detail-target,
  anders de eerste sessie. Geen toetsenbord-navigatie in v0.

## Beperkingen

* Geen live keyboard-navigation (out of scope voor v0 mockup).
* Geen filtering of zoek in message-feed.
* Capture-tail komt uit demo-state. In live-mode wordt het veld
  alleen getoond als de sessions-yaml writer het meelevert.

## Schema verwachting

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

`state/messages.jsonl` (1 JSON per regel):

```json
{"from":"sender","to":"recipient","type":"task","payload":{...},"ts":"2026-05-10T13:51:58Z"}
```

## Dependencies

Alleen `rich` (en `pyyaml` voor live-mode). Geen extra packages
toegevoegd. Geen textual, geen curses.
