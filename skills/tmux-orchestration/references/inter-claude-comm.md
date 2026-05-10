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

- Status: <pending F4>
- Transcript: `tests/peer-comm/03-peer-exited.txt`
- Expected: paste lands in bash, Enter executes the body as a shell command. DANGEROUS.
- Observed: <to be filled in F4>
- Mitigation: <to be filled in F4>

### 5.4 Multiple peer-prompts in flight to same target within 1 second

- Status: <pending F5>
- Transcript: `tests/peer-comm/04-rapid-multi.txt`
- Expected: prompts concatenate in input buffer, single Enter submits combined text. Or last-wins. Need empirical answer.
- Observed: <to be filled in F5>
- Mitigation: <to be filled in F5>

### 5.5 Paste-buffer name collision

- Status: <pending F5>
- Transcript: `tests/peer-comm/05-buffer-collision.txt`
- Expected: `tmux load-buffer -b <name>` overwrites existing buffer. If two senders use the same name, last-loader's payload wins, first sender's `paste-buffer` injects the wrong content.
- Observed: <to be filled in F5>
- Mitigation: <to be filled in F5>

### 5.6 Peer in trust-folder dialog

- Status: <pending F5>
- Transcript: `tests/peer-comm/06-trust-dialog.txt`
- Expected: paste goes into the dialog's input, Enter activates the default button or types into the dialog field. Disruptive.
- Observed: <to be filled in F5>
- Mitigation: <to be filled in F5>

### 5.7 Peer has different reply-language

- Status: <pending F5>
- Transcript: `tests/peer-comm/07-language.txt`
- Expected: receiver responds in own configured reply-language regardless of sender language. No protocol-level mismatch.
- Observed: <to be filled in F5>
- Mitigation: <to be filled in F5>

### 5.8 Hard-inject (Esc Esc) during sender's own busy state

- Status: design-only (would require sender to interrupt itself)
- Sender CANNOT Esc-Esc itself meaningfully via tmux send-keys without aborting its current tool-call mid-flight. This is destructive to the sender's own work.
- Recommendation: do NOT invoke `--hard` on self. `--hard` is only safe target=peer when peer is in a recoverable state, AND user has approved the interruption.
- Mitigation: hard-inject is operator-only (orchestrator on user request); workers MUST use soft-inject (Channel A as documented).

---

## 6. Supported API surface

To be finalized in phase F6 once empirical evidence is in.

Stable:
- Channel A (direct injection sequence in section 1)
- Channel B (orchestrator forward in section 2)
- Channel C (jsonl audit log in section 3)
- Self-identification prefix (section 4)
- `tmo send` for audit-log + forward
- `tmo receive` for inbox polling
- `tmo note <session> <body>` for soft sidenote injection (section 1 wire sequence under the hood)

Experimental:
- `tmo note --hard` (Esc Esc + inject). Operator-only.
- Cross-workspace peer-comm via shared `TMO_STATE_DIR`.

Not supported:
- Sender-side hard-inject of self
- Direct injection across hosts (only single-host tmux supported today)
- Binary payloads via Channel A (text only; for binary use file-paths in payload + Channel C)

Cross-references:
- `skills/tmux-orchestration/SKILL.md` - Phase 6 (Communication protocol) and Phase 4 (Worker spawn) reference Channel A wire sequence
- `roles/*.md` - every role inherits this protocol; no role-specific override is permitted
- `bin/tmo` - implementation of `send`, `receive`, `note`, `wait-for`
