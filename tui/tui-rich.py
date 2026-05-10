#!/usr/bin/env python3
"""tmo TUI dashboard mockup (rich-based).

Three-panel orchestrator view: sessions table, message feed, detail.
Reads state/sessions.yaml + state/messages.jsonl when present, else
falls back to tui/demo-state.json for mockup-mode.

Fail-fast: missing rich -> ImportError. Malformed JSONL -> raises.
No try/except masking, per workspace rule (geen fallbacks).
"""

from __future__ import annotations

import argparse
import json
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

from rich.console import Console
from rich.layout import Layout
from rich.live import Live
from rich.panel import Panel
from rich.table import Table
from rich.text import Text

REPO_ROOT = Path(__file__).resolve().parent.parent
DEMO_FILE = REPO_ROOT / "tui" / "demo-state.json"
STATE_DIR = REPO_ROOT / "state"
SESSIONS_FILE = STATE_DIR / "sessions.yaml"
MESSAGES_FILE = STATE_DIR / "messages.jsonl"

STATUS_EMOJI = {"idle": "💤", "working": "⚡", "blocked": "⛔", "done": "✅", "replaced": "🔁"}
STATUS_STYLE = {"idle": "dim", "working": "bold cyan", "blocked": "yellow", "done": "green", "replaced": "red"}
TYPE_STYLE = {"task": "blue", "status": "green", "peer-prompt": "cyan", "blocked": "yellow", "replace": "red", "done": "bold green"}
FEED_LIMIT = 12


def load_state(demo: bool) -> dict:
    """Return {"sessions": {...}, "messages": [...]}.

    demo=True forces demo-state.json. Else read live state if present.
    """
    if demo:
        return json.loads(DEMO_FILE.read_text())

    sessions = {}
    messages = []
    if SESSIONS_FILE.exists():
        import yaml
        raw = yaml.safe_load(SESSIONS_FILE.read_text()) or {}
        if isinstance(raw, dict) and "sessions" in raw and isinstance(raw["sessions"], list):
            sessions = {}
        else:
            sessions = raw if isinstance(raw, dict) else {}
    if MESSAGES_FILE.exists():
        for line in MESSAGES_FILE.read_text().splitlines():
            line = line.strip()
            if not line:
                continue
            messages.append(json.loads(line))

    if not sessions and not messages:
        return json.loads(DEMO_FILE.read_text())
    return {"sessions": sessions, "messages": messages}


def render_header(state: dict) -> Panel:
    now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    cwd = str(Path.cwd())
    n_sessions = len(state.get("sessions", {}))
    title = Text()
    title.append("tmo orchestrator dashboard", style="bold cyan")
    title.append("   ")
    title.append(f"sessions={n_sessions}", style="dim")
    title.append("   ")
    title.append(cwd, style="dim")
    title.append("   ")
    title.append(now, style="bold")
    return Panel(title, border_style="cyan", padding=(0, 1))


def render_sessions_table(state: dict, selected: str | None) -> Panel:
    table = Table(expand=True, show_header=True, header_style="bold cyan", border_style="cyan", pad_edge=False)
    table.add_column("name", style="bold", no_wrap=True)
    table.add_column("role", style="dim", no_wrap=True)
    table.add_column("st", justify="center", no_wrap=True)
    table.add_column("uses", justify="right", style="dim")
    table.add_column("last", style="dim", no_wrap=True)
    for name, info in state.get("sessions", {}).items():
        status = info.get("status", "idle")
        emoji = STATUS_EMOJI.get(status, "?")
        style = STATUS_STYLE.get(status, "")
        last = info.get("last_activity", "-")[-8:]
        row_name = Text(name, style="reverse bold cyan" if name == selected else "")
        table.add_row(row_name, info.get("role", "-"), Text(f"{emoji} {status}", style=style), str(info.get("usages", 0)), last)
    return Panel(table, title="[bold cyan]sessions[/]", border_style="cyan")


def render_message_feed(state: dict) -> Panel:
    msgs = state.get("messages", [])[-FEED_LIMIT:]
    body = Text()
    if not msgs:
        body.append("(no messages)\n", style="dim")
    for m in msgs:
        ts = m.get("ts", "")[-9:-1] if m.get("ts") else "--:--:--"
        mtype = m.get("type", "?")
        style = TYPE_STYLE.get(mtype, "white")
        frm = m.get("from", "?")
        to = m.get("to", "?")
        payload = m.get("payload", {})
        summary = payload.get("goal") or payload.get("step") or payload.get("need") or payload.get("hint") or payload.get("reason")
        if not summary and "files" in payload:
            summary = f"files={len(payload['files'])}"
        if not summary:
            summary = json.dumps(payload, separators=(",", ":"))[:60]
        body.append(f"{ts} ", style="dim")
        body.append(f"[{mtype:^11}] ", style=style)
        body.append(f"{frm:>14} ", style="dim cyan")
        body.append("→ ", style="dim")
        body.append(f"{to:<14} ", style="cyan")
        body.append(f"{summary}\n", style="white")
    return Panel(body, title=f"[bold cyan]message feed[/] [dim](last {len(msgs)})[/]", border_style="cyan")


def render_detail(state: dict, selected: str) -> Panel:
    info = state.get("sessions", {}).get(selected)
    if info is None:
        return Panel(Text(f"session not found: {selected}", style="yellow"), title="[bold cyan]detail[/]", border_style="cyan")
    body = Text()
    body.append(f"{selected}\n", style="bold cyan")
    body.append(f"role        : ", style="dim"); body.append(f"{info.get('role','-')}\n")
    status = info.get("status", "idle")
    body.append(f"status      : ", style="dim"); body.append(f"{STATUS_EMOJI.get(status,'?')} {status}\n", style=STATUS_STYLE.get(status, ""))
    body.append(f"started     : ", style="dim"); body.append(f"{info.get('started_at','-')}\n")
    body.append(f"last        : ", style="dim"); body.append(f"{info.get('last_activity','-')}\n")
    body.append(f"usages      : ", style="dim"); body.append(f"{info.get('usages',0)}\n")
    body.append(f"\nfile-scope:\n", style="bold dim")
    for p in info.get("file_scope", []):
        body.append(f"  • {p}\n")
    body.append(f"\nskill-hints:\n", style="bold dim")
    for s in info.get("skill_hints", []) or ["(none)"]:
        body.append(f"  • {s}\n", style="cyan")
    body.append(f"\nrecent capture-pane:\n", style="bold dim")
    for line in info.get("capture_tail", [])[-5:]:
        body.append(f"  {line}\n", style="dim")
    return Panel(body, title=f"[bold cyan]detail · {selected}[/]", border_style="cyan")


def render_footer() -> Panel:
    hint = Text()
    hint.append("q", style="bold cyan"); hint.append(" quit  ", style="dim")
    hint.append("↑↓", style="bold cyan"); hint.append(" navigate  ", style="dim")
    hint.append("r", style="bold cyan"); hint.append(" reload  ", style="dim")
    hint.append("(mockup: auto-refresh 2s, no live keys)", style="dim italic")
    return Panel(hint, border_style="cyan", padding=(0, 1))


def build_layout(state: dict, selected: str) -> Layout:
    layout = Layout()
    layout.split_column(
        Layout(render_header(state), name="header", size=3),
        Layout(name="body", ratio=1),
        Layout(render_footer(), name="footer", size=3),
    )
    layout["body"].split_row(
        Layout(render_sessions_table(state, selected), name="left", ratio=2),
        Layout(render_message_feed(state), name="center", ratio=3),
        Layout(render_detail(state, selected), name="right", ratio=2),
    )
    return layout


def pick_selected(state: dict) -> str:
    sessions = state.get("sessions", {})
    if not sessions:
        return ""
    for name, info in sessions.items():
        if info.get("status") == "working":
            return name
    return next(iter(sessions))


def main() -> int:
    parser = argparse.ArgumentParser(description="tmo TUI dashboard mockup")
    parser.add_argument("--demo", action="store_true", help="force demo-state.json")
    parser.add_argument("--frames", type=int, default=0, help="render N frames then exit (0 = live loop)")
    parser.add_argument("--capture", type=Path, help="write first frame as plain-text to this file")
    parser.add_argument("--refresh", type=float, default=2.0, help="refresh interval in seconds")
    args = parser.parse_args()

    if args.frames > 0 or args.capture:
        console = Console(record=bool(args.capture), force_terminal=True, width=140)
        for i in range(max(args.frames, 1)):
            state = load_state(args.demo)
            selected = pick_selected(state)
            console.print(build_layout(state, selected))
            if args.capture and i == 0:
                args.capture.write_text(console.export_text(clear=False))
            if i < args.frames - 1:
                time.sleep(args.refresh)
        return 0

    console = Console()
    with Live(console=console, refresh_per_second=4, screen=True) as live:
        while True:
            state = load_state(args.demo)
            selected = pick_selected(state)
            live.update(build_layout(state, selected))
            time.sleep(args.refresh)


if __name__ == "__main__":
    sys.exit(main())
