# Inter-Claude tmux Peer-Communication

Empirical reference for peer-to-peer communication between live Claude REPLs running inside tmux sessions, as orchestrated by the `tmux-orchestration` skill.

Status: living document. Edge-case sections record empirical capture-pane evidence, not speculation. Each edge case links to its raw transcript under `tests/peer-comm/`.

Audience: worker-claude sessions and the orchestrator. Read before injecting a prompt into another worker.

---

## 1. Channel A: Direct peer-injection (PROVEN, stable)

Sender places a prompt directly into the receiver's tmux pane.

### Wire sequence

```bash
# 1. Self-identify in body. Receiver MUST see [from <sender>] prefix.
BODY="[from $TMO_SESSION] <actual question or instruction>"

# 2. Pick a unique buffer name (collision-safe per sender + epoch).
BUF="peer-${TMO_SESSION}-$(date +%s%N)"

# 3. Load body into named tmux paste-buffer.
printf '%s' "$BODY" | tmux load-buffer -b "$BUF" -

# 4. Paste into receiver's REPL pane.
tmux paste-buffer -b "$BUF" -t "$PEER:0.0"

# 5. Settle (paste does not commit by itself).
sleep 0.2

# 6. Submit. Two-step Enter is required: a single Enter directly after paste
#    can race the input buffer in claude REPL. Send the Enter as its own
#    send-keys call AFTER the sleep.
tmux send-keys -t "$PEER:0.0" Enter

# 7. Clean up the named buffer.
tmux delete-buffer -b "$BUF"
```

### Audit-log (mandatory)

Every direct injection MUST be paired with an audit-log entry so the orchestrator can replay traffic:

```bash
tmo send "$PEER" peer-prompt "$(cat <<EOF
{"from":"$TMO_SESSION","mode":"direct","buf":"$BUF","prompt_preview":"<first 80 chars>"}
EOF
)"
```

The audit-log is Channel C (section 3). Channel A without Channel C is an anti-pattern: orchestrator becomes blind to peer traffic.

### Why `load-buffer` instead of `send-keys "$body"`

- `send-keys` interprets embedded newlines as separate Enter events. A multi-line prompt would submit line-by-line and the first line wins.
- `send-keys` also has special-character escaping issues (backticks, dollar-signs, single-quotes).
- `load-buffer -` reads stdin literally. Paste-buffer payload survives unmolested.

### Why `sleep 0.2` between paste and Enter

Empirical: without the sleep, the Enter sometimes arrives at claude's input layer before the paste has been fully consumed by the readline buffer, producing partial submission. 200 ms is conservative; 100 ms also works on tested hardware. Documented at 0.2 for safety.

---

## 2. Channel B: Orchestrator-routed forward (fallback, stable)

Use when direct peer-injection is not viable. Sender does NOT inject; sender writes a forward request to the orchestrator inbox; orchestrator performs the injection on behalf of the sender (after sanity-checks).

### When to use Channel B (decision tree)

```
Is peer session alive?            (tmux has-session -t <peer>)
├─ NO  → Channel B forward
└─ YES → Is peer pane in claude REPL state?  (capture-pane shows the prompt indicator)
         ├─ NO  → Channel B forward (peer might be at bash, in dialog, exited)
         └─ YES → Is paste-buffer slot free? (BUF name collision check)
                  ├─ NO  → retry with new BUF name OR Channel B forward
                  └─ YES → Channel A direct
```

Sender uses sender-side detection (see section 5 edge cases for what each failure mode looks like in capture-pane).

### Wire shape

```bash
tmo send orchestrator forward "$(cat <<EOF
{"to":"<peer>","reason":"<why direct failed>","payload":{"prompt":"[from $TMO_SESSION] ..."}}
EOF
)"
```

Orchestrator behavior (out of scope of this doc, but documented for round-trip understanding):
- tails `state/messages.jsonl` for `type:"forward"` events
- validates `to` exists, peer is in REPL state
- performs Channel A injection on sender's behalf
- emits `type:"forward-ack"` with success/failure

Sender does NOT block on the forward; it continues with own work and listens for the ack via `tmo receive`.

---

## 3. Channel C: jsonl audit forum (always, stable)

`state/messages.jsonl` is the central forum. Every peer-action MUST produce a Channel C event regardless of whether Channel A or B was used. Append-only. File-locked via `state/messages.jsonl.lock`.

### Event shape

```json
{"from":"<sender>","to":"<peer-or-broadcast>","type":"<event-type>","payload":{...},"ts":"<ISO8601 UTC>"}
```

### Event types relevant to peer-comm

| Type | When | Payload keys |
|---|---|---|
| `peer-prompt` | Channel A direct injection done | `from`, `mode:"direct"`, `buf`, `prompt_preview` |
| `forward` | Channel B forward request to orchestrator | `to`, `reason`, `payload.prompt` |
| `forward-ack` | Orchestrator completed (or failed) forward | `to`, `status:"ok"\|"fail"`, `reason` |
| `peer-reply` | Receiver acknowledges peer-prompt | `to:<original-sender>`, `prompt_preview` |
| `escalate` | Worker spawning sub-workers | `reason`, `spawning` |

### Why jsonl + append-only + file-lock

- Replay: orchestrator can reconstruct any session's view by reading the file from offset 0.
- Concurrent senders: multiple workers writing simultaneously cannot interleave bytes mid-line.
- Auditability: timestamps + sender prove "who said what when". Required for quality-gate review.

---

## 4. Self-identification rule (mandatory)

Every peer-injected prompt body MUST start with `[from <$TMO_SESSION>]`.

Reason: receiver lands in mid-thinking with a new prompt in its input buffer. Without an explicit prefix, receiver has no synchronous signal of who is asking. Parsing audit-log mid-turn is too expensive and error-prone.

Sender prefix:
```
[from peercomm-orch] What is the schema for users.role?
```

Receiver reply prefix (when replying via Channel A back to sender):
```
[from worker-B] users.role is enum('admin','member','guest'). See migrations/0014.
```

If sender is the orchestrator forwarding on behalf of another worker, both identities MUST appear:
```
[from orchestrator on behalf of worker-A] ...
```

### Reply-language

Sender writes the prompt in the receiver's configured reply-language. Default English. If receiver is configured for Dutch (Nederlands), sender prefixes still in English `[from ...]` form but body in Dutch. Mixed-language prefix vs body is acceptable; the prefix is metadata, the body is content.

If sender does not know receiver's reply-language: write in English. English is the documented default for all worker sessions (per task-dispatch contract).

---

## 5. Edge cases (empirical)

Each edge case has been tested with two ephemeral tmux+claude sessions (`pc-test-A`, `pc-test-B`). Raw capture-pane transcripts are stored under `tests/peer-comm/`.

### 5.1 Peer is mid-thinking (busy-spinner)

- Status: PROVEN (F2)
- Transcript: `tests/peer-comm/01-busy-spinner.txt`
- Repro: `bash tests/peer-comm/01-busy-spinner.sh`
- Expected: paste lands in input buffer, Enter is queued, prompt submits at next-turn boundary.
- Observed:
  - sender fired peer-prompt at T+2s after busy-trigger, while receiver was rendering token output ("Gesticulating..." spinner)
  - paste appeared in receiver's input area immediately, visible above the spinner
  - receiver completed busy-trigger task ("Baked for 8s"), then automatically picked up the queued peer-prompt
  - receiver replied with `PONG-BUSY-OK` confirming successful pickup
  - no input loss, no ordering ambiguity, no race
- Mitigation: none required. Channel A wire sequence works as documented during busy-spinner state.

### 5.2 Peer is mid-tool-call (Bash running)

- Status: PROVEN (F3)
- Transcript: `tests/peer-comm/02-tool-call.txt`
- Repro: `bash tests/peer-comm/02-tool-call.sh`
- Expected: similar to 5.1, prompt queued until tool-call returns and turn boundary occurs.
- Observed:
  - receiver was running `Bash(bash -lc 'for i in 1..8; do echo tick-$i; sleep 1; done')` for ~8s
  - peer-prompt injected at T+12s after tool started; tool was clearly mid-flight
  - paste landed and claude REPL explicitly displayed `Press up to edit queued messages` indicator (more obvious than busy-spinner case)
  - tool finished; receiver replied `TOOL-DONE` for the original prompt
  - receiver then auto-picked the queued peer-prompt and replied `PONG-TOOL-OK`
  - ordering preserved: tool-prompt first, peer-prompt second
- Mitigation: none required. Channel A wire sequence works during tool-call. Note: the explicit queued-message indicator means a sender can sender-side-detect "queued" state by capture-pane grep for `Press up to edit queued messages` if it needs to confirm queueing.

### 5.3 Peer just exited claude (REPL gone)

- Status: PROVEN DANGEROUS (F4)
- Transcript: `tests/peer-comm/03-peer-exited.txt`
- Repro: `bash tests/peer-comm/03-peer-exited.sh`
- Expected: paste lands in bash, Enter executes the body as a shell command. DANGEROUS.
- Observed:
  - receiver pane was at bash prompt `freek@host:~/...$` after `/exit` (claude REPL gone)
  - Channel A injection still succeeded mechanically: paste appeared on the bash command line, Enter submitted
  - bash interpreted the payload: `Opdracht '[from' niet gevonden` (command not found error)
  - benign in this test (payload had no shell-evaluable parts), but a payload starting with `rm`, `curl ... | sh`, redirections (`>file`), or any executable name would EXECUTE
  - sender had no signal of failure beyond the absence of an audit-log peer-reply; orchestrator can detect via `tmux has-session` + capture-pane grep, but only AFTER the damage is done
- Mitigation (mandatory, sender-side, BEFORE any Channel A injection):
  1. `tmux has-session -t "$PEER" 2>/dev/null` must succeed
  2. capture-pane and verify claude REPL state. Reliable signals in current claude CLI render: a horizontal separator line of `─` characters and a `❯` prompt indicator inside it. A bash prompt looks like `<user>@<host>:<cwd>$` with no separator.
  3. If detection fails, fall back to Channel B (orchestrator forward) which performs its own pre-flight check and either retries when peer recovers or emits `forward-ack` with `status:"fail"`.
- Sender pre-flight snippet:
  ```bash
  is_claude_repl() {
    tmux capture-pane -t "$1:0.0" -p -S -5 | grep -qE '^─+$' \
      && tmux capture-pane -t "$1:0.0" -p -S -5 | grep -qE '^❯ ?$'
  }
  if ! is_claude_repl "$PEER"; then
    tmo send orchestrator forward "..."  # Channel B fallback
    exit 0
  fi
  # ... proceed with Channel A
  ```

### 5.4 Multiple peer-prompts in flight to same target within 1 second

- Status: PROVEN with caveat (F5)
- Transcript: `tests/peer-comm/04-rapid-multi.txt`
- Repro: `bash tests/peer-comm/04-rapid-multi.sh`
- Expected: prompts queue in submission order, FIFO, claude processes one-by-one.
- Observed:
  - 3 peer-prompts (RAPID-1, RAPID-2, RAPID-3) fired ~250ms apart
  - RAPID-1 entered REPL and started processing immediately ("Nesting...")
  - RAPID-2 and RAPID-3 appeared as queued items under "Press up to edit queued messages"
  - claude processed and emitted ONE response with `RAPID-ACK-2` and `RAPID-ACK-3`
  - `RAPID-ACK-1` was NOT visible in the transcript: claude appears to have merged the queued tail or partially absorbed prompt 1 into the queued-batch turn
  - Lesson: rapid-fire CAN cause apparent ack loss / prompt-merging at queue boundaries
- Mitigation: serialize peer-prompts via wait-for-ack pattern when each prompt requires its own isolated turn:
  ```bash
  send_peer_prompt
  until tmux capture-pane -t "$PEER:0.0" -p -S -200 | grep -q "$EXPECTED_ACK"; do sleep 2; done
  send_next_peer_prompt
  ```
  Use rapid-fire only for fire-and-forget broadcasts where ack-isolation is not required.

### 5.5 Paste-buffer name collision

- Status: PROVEN (F5)
- Transcript: `tests/peer-comm/05-buffer-collision.txt`
- Repro: `bash tests/peer-comm/05-buffer-collision.sh`
- Expected: `tmux load-buffer -b <name>` overwrites existing buffer. Last-loader wins.
- Observed:
  - sender X: `printf 'PAYLOAD-X' | tmux load-buffer -b shared-name -`
  - sender Y: `printf 'PAYLOAD-Y' | tmux load-buffer -b shared-name -`
  - sender X: `tmux paste-buffer -b shared-name`
  - receiver pane shows `PAYLOAD-Y-from-sender-Y` (Y's content)
  - X's content silently lost; no warning, no error
- Mitigation: per-sender + nanosecond-unique buffer names:
  ```bash
  BUF="peer-${TMO_SESSION}-$(date +%s%N)"
  ```
  This is already mandated in the Channel A wire sequence (section 1) and the audit-log payload includes `buf` so the orchestrator can spot-check uniqueness.

### 5.6 Peer in trust-folder dialog

- Status: PROVEN DANGEROUS (F5)
- Transcript: `tests/peer-comm/06-trust-dialog.txt`
- Repro: `bash tests/peer-comm/06-trust-dialog.sh`
- Expected: paste goes into the dialog's input, Enter activates the default button or types into the dialog field. Disruptive.
- Observed:
  - dialog active: "Accessing workspace: ... Yes, I trust this folder / No, exit / Enter to confirm · Esc to cancel"
  - Channel A injection: paste was silently swallowed by the dialog UI (not visible anywhere)
  - Enter activated the focused option ("Yes, I trust this folder" by default)
  - dialog accepted; claude proceeded into normal REPL state
  - peer-prompt LOST; no audit trail of failure beyond absence of a peer-reply
  - INADVERTENT CONFIRMATION risk: any dialog (trust-folder, permission-grant, destructive-action confirmation) could be auto-accepted by an injection
- Mitigation: sender pre-flight grep for known dialog headers BEFORE Channel A injection:
  ```bash
  if tmux capture-pane -t "$PEER:0.0" -p -S -50 \
       | grep -qE 'Accessing workspace:|Quick safety check:|Enter to confirm · Esc to cancel'; then
    tmo send orchestrator forward "..."  # Channel B fallback
    exit 0
  fi
  ```
  Combine with the section 5.3 mitigation (`is_claude_repl` check). Together they cover bash-prompt and dialog-state.

### 5.7 Peer has different reply-language

- Status: PROVEN (F5)
- Transcript: `tests/peer-comm/07-language.txt`
- Repro: `bash tests/peer-comm/07-language.sh`
- Expected: receiver responds in body-content language; English `[from X]` prefix is metadata only.
- Observed:
  - sender prefix `[from peercomm-orch]` (English)
  - body: Dutch ("Beantwoord deze vraag uitsluitend in het Nederlands... Welke kleur is de lucht...")
  - receiver reply was in Dutch: "Lucht overdag bij helder weer blauw. Komt door Rayleigh-verstrooiing..."
  - terminator `LANG-NL-OK` returned correctly
  - prefix did not influence reply-language; body content (and any per-session language config) does
- Mitigation: none required for protocol. Sender writes body in receiver's expected reply-language (default English; per role-md if specified). Prefix stays English `[from <session>]` regardless.

### 5.8 Hard-inject (Esc Esc) during sender's own busy state

- Status: design-only (would require sender to interrupt itself)
- Sender CANNOT Esc-Esc itself meaningfully via tmux send-keys without aborting its current tool-call mid-flight. This is destructive to the sender's own work.
- Recommendation: do NOT invoke `--hard` on self. `--hard` is only safe target=peer when peer is in a recoverable state, AND user has approved the interruption.
- Mitigation: hard-inject is operator-only (orchestrator on user request); workers MUST use soft-inject (Channel A as documented).

---

## 6. Supported API surface

Final, derived from empirical evidence in section 5 and the live `bin/tmo` implementation.

### Stable

Use these freely in worker logic.

| Surface | Form | Purpose |
|---|---|---|
| Channel A | `load-buffer + paste-buffer + sleep 0.2 + send-keys Enter + delete-buffer` (section 1) | Direct peer-injection. Required pre-flight: `tmux has-session` AND capture-pane grep for claude REPL signals (sections 5.3 + 5.6). |
| Channel B | `tmo send orchestrator forward '{"to":"<peer>","reason":"...","payload":...}'` (section 2) | Fallback when peer is not in claude REPL state. Orchestrator handles. |
| Channel C | `tmo send <to> <type> '<json>'` writes to `state/messages.jsonl` (section 3) | Audit log. Mandatory pairing with Channel A. |
| Self-id prefix | `[from <$TMO_SESSION>]` at start of every body (section 4) | Receiver sees who is asking without parsing audit-log. |
| `tmo send <to> <type> <json>` | append message to `state/messages.jsonl` | Audit-log + Channel B. |
| `tmo receive [--for <s>] [--type <t>] [--since <ts>]` | read inbox messages | Worker polling. |
| `tmo note <session> <body>` | soft-inject sidenote (Channel A under the hood with `[SIDENOTE HH:MM]` prefix) | Out-of-band steering, queued during busy. |
| `tmo note <session> --raw <body>` | soft-inject without `[SIDENOTE]` prefix | When caller controls full prefix (e.g. `[from <self>]`). |
| Buffer naming `peer-${TMO_SESSION}-$(date +%s%N)` | per-sender, nanosecond-unique buffer name | Prevents 5.5 collision. |
| Wait-for-ack pattern | `until tmux capture-pane | grep -q "<EXPECTED>"; do sleep 2; done` | Serialize peer-prompts that need turn isolation (per 5.4). |

### Experimental

These work but are not yet hardened or fully spec'd. Use with caution and explicit user approval.

| Surface | Status | Caveat |
|---|---|---|
| `tmo note <session> --hard <body>` | experimental | Sends Esc Esc to abort current tool/turn before injecting. Risky during Write/Edit; can lose receiver work. Operator-only. |
| Cross-workspace peer-comm via shared `TMO_STATE_DIR` | experimental | All workers point at one state dir (e.g. `/home/freek/GitHub/tmux-orchestrator/state`). Audit log unifies, peer-injection still requires same-host tmux. |
| `tmo wait-for <session> <event>` | experimental (F5 stub in current `bin/tmo`) | Blocks on inbox event arrival. Implementation is a polling stub today. |
| `tmo task` subcommands (`add/list/claim/update/done`) | experimental | Cross-session task tracker. Stable enough for orchestrator dispatch but not the focus of this doc. |

### Not supported

These are explicit non-goals. Do not attempt; there is no semantic for them.

- Sender-side hard-inject of self (Esc Esc on own pane). Destructive to current tool-call.
- Direct injection across hosts. Only same-host tmux is supported.
- Binary payloads via Channel A. Text only. For binary, write to a file and include the path in a Channel C payload.
- Last-wins concatenation semantics for rapid-fire prompts (per 5.4 caveat). If you need that, batch into one prompt body.

### Cross-references

- `skills/tmux-orchestration/SKILL.md` - Phase 6 ("Communication protocol") and Phase 4 ("Worker spawn") cite Channel A wire sequence and the load-buffer + paste-buffer + 2-step Enter rule
- `skills/tmux-orchestration/references/cheatsheet-excerpt.md` - quick-reference for the same wire sequence (kept short for clipboard use)
- `skills/tmux-orchestration/references/role-evolution-loop.md` - role graduation flow (orthogonal to this doc but referenced from SKILL.md Phase 4b)
- `roles/orchestrator.md`, `roles/backend.md`, `roles/frontend.md`, `roles/reviewer.md`, `roles/generalist.md` - each role inherits this protocol; no role-specific override is permitted
- `bin/tmo` - implementation of `send`, `receive`, `note`, `wait-for`, `task`, `spawn`, `bootstrap`
- `tests/peer-comm/` - repro scripts and capture-pane transcripts for every empirical claim in section 5
