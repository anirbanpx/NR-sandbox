# Process Coverage — interactive prototype

A self-contained, clickable prototype of the proposed **"Process Coverage"** view for New Relic
Infrastructure — the hero solution from this exercise.

**▶ Live:** https://anirbanpx.github.io/NR-sandbox/prototype/
**Source:** [`index.html`](index.html) (single file, no build step, no external dependencies)

---

## What it shows

A 4-screen journey, where each step closes a friction documented in
[`../docs/friction-log.md`](../docs/friction-log.md):

1. **Processes — today** — the real 62-process tab, sorted by CPU. The business-critical
   payment-queue worker is buried at rank 7 / 0.037% CPU. An account-health banner flags that
   alert conditions have no notification destination *(the notification void)*.
2. **Process Coverage — proposed** — sorted by **business priority**, with a coverage meter,
   bidirectional **process ↔ service ↔ host** links, and the worker surfaced as
   ★ business-critical (derived from the journey it serves, not CPU) and ⚠ unmonitored — with a
   one-click **Watch** that previews the gap-safe alert it configures.
3. **NRAI — propose & confirm** — natural-language alert creation that proposes the correct
   condition and **shows it for confirmation before saving** (the guardrail is the point).
4. **Alert — active + validated** — the alert is live and wired; **Test this alert** backtests
   it against the last 24h and confirms the full chain fires *(closing the validation void)*.

## How to navigate

The prototype guides the reviewer through it:

- **Pulsing hotspot rings** mark the exact element to click on each screen.
- A **numbered step bar** on every screen explains what to do next.
- A bottom **nav bar** (← Back / Next → / Restart) and the **arrow keys** also move between screens.
- A **Guide: On/Off** toggle (bottom bar) hides all guidance for a clean screen-recording.

## Run it locally

No server needed — open the file directly:

```bash
# from the repo root
open prototype/index.html        # macOS
start prototype/index.html       # Windows
```

Fonts are self-hosted in [`fonts/`](fonts/), so it renders identically offline.

## Notes

- Built to the live New Relic light-theme UI using design tokens extracted from real screenshots
  (white canvas, `#E3E4E5` borders, `#1D252C` / `#6E7780` text, teal `#0E7C86` links,
  NR green `#00AC69`), set in **Inter** with tabular figures.
- It is a faithful *visual* prototype — data and navigation are scripted to tell the story, not
  wired to a live backend.
