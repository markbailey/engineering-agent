# Dashboard Improvement Plan

## Context

Audit of `dashboard/` — zero-dependency Node.js real-time monitoring UI for agent workflows. User wants: prioritized fixes, focus on live updates, simplified scope (no historic run browsing), no CORS/proxy concerns.

---

## Priority 1 — Fix What's Broken

### P1.1: SSE keepalive
**Problem:** Idle SSE connections die after ~30-60s on many networks/firewalls. The browser reconnects but there's a blackout window where events are missed.
**Fix:** Server sends `:keepalive\n\n` (SSE comment) every 15s in `server.js`. One `setInterval` in the SSE handler.
**Files:** `server.js`

### P1.2: Close the startup event gap
**Problem:** `loadInitial().then(() => connect())` — SSE starts *after* the initial fetch finishes. Any events emitted between the fetch response arriving and the SSE connection opening are permanently lost. On a fast poll cycle (1s), this is a real window.
**Fix:** Connect SSE first, then fetch `/api/runs`. SSE events that arrive before the fetch response are applied on top.
**Files:** `index.html` (JS section)

### P1.3: Stop accumulating logs in memory
**Problem:** `run.logs` in `server.js` grows forever — every log entry for every ticket stays in memory. Redundant since logs are file-based (JSONL on disk).
**Fix:** Don't accumulate. Each poll, read only the last N bytes/lines from the file (tail-read). `LogTailer` already tracks byte offsets — change it to a sliding window that keeps only the last ~50 lines worth of bytes. The file is the source of truth; memory just holds the current view.
**Files:** `server.js`, `lib/watcher.js`

### P1.4: Cache artifact file reads by mtime
**Problem:** `loadArtifacts()` does 5 synchronous `readFileSync` calls per ticket *every single poll* (1s default). Most polls, these files haven't changed.
**Fix:** `stat` each artifact file first, compare `mtimeMs` against a cached value. Only re-read on change. `stat` is much cheaper than `readFile + JSON.parse`.
**Files:** `server.js`

### P1.5: Replace JSON.stringify change detection
**Problem:** `JSON.stringify(run.state)` is called twice per ticket per poll to detect changes. With large states this is O(n) serialization just to check equality.
**Fix:** Increment a version counter when state actually changes (new log lines arrived OR artifact mtime changed). Compare counter instead of serializing.
**Files:** `server.js`

---

## Priority 2 — Live Update UX

### P2.1: Log level filter buttons
**What:** Row of toggle buttons above the log stream: `INFO` `WARN` `ERROR` `EVENT`. Click to show/hide that level. All on by default.
**Why:** Currently the only way to find errors is scrolling through all 50 log entries. Filtering to ERROR-only is the #1 thing you'd do when something goes wrong.
**Files:** `index.html`

### P2.2: Expandable log details
**What:** Log entries with a `details` field (the JSONL `details` object) get a `▸` toggle. Click to expand a `<pre>` block showing the JSON.
**Why:** The `details` field carries structured data (error stacks, file lists, diff stats) that's currently invisible.
**Files:** `index.html`

### P2.3: Show artifact content — REVIEW.json & ESCALATION.json
**What:** Below the task queue, add collapsible panels for each present artifact. REVIEW.json shows critic issues (severity, file, message). ESCALATION.json shows escalation entries (category, severity, summary). FEEDBACK.json shows PR feedback items.
**Why:** Currently artifacts are just boolean flags (`hasPrd: true`). The most useful information in the system — why something was blocked, what the critic found — is invisible.
**Implementation:**
- Server already reads these files in `loadArtifacts()`. Change `mergeArtifacts()` to include content, not just presence flags.
- Add ESCALATION.json to the artifact file list.
- Frontend renders collapsible sections per artifact.
**Files:** `lib/state.js`, `server.js`, `index.html`

### P2.4: Task progress summary
**What:** Above the task list, show `3/5 verified` with a thin progress bar.
**Why:** Quick glance at completion. Currently you count badges manually.
**Files:** `index.html`

### P2.5: Elapsed time display
**What:** Show elapsed time (e.g., `12m 34s`) next to the run status in the sidebar footer. Use `startedAt` and `lastActivity` (both already tracked).
**Why:** No sense of how long a run has been going or how long it took.
**Files:** `index.html`

### P2.6: Browser notifications
**What:** Request notification permission. Fire browser `Notification` on: ERROR-level log, escalation, run complete, PR events.
**Why:** User shouldn't have to stare at the tab. Errors and escalations need attention.
**Files:** `index.html`

---

## Priority 3 — Code Health

### P3.1: Diff-based DOM updates
**Problem:** `render()` does `innerHTML = ''` then rebuilds the entire DOM tree. Every poll that changes anything destroys and recreates all elements — log entries, task items, workflow steps. This causes: flicker, lost scroll position (partially mitigated by auto-scroll), and unnecessary layout/paint.
**Fix:** Compare new state against currently rendered state. Only update changed elements. For the log stream specifically: append new entries, remove old ones.
**Files:** `index.html`

### P3.2: Split `index.html` into separate files
**Problem:** 28KB monolithic file with HTML + CSS + JS. Can't test frontend logic independently, hard to navigate.
**Fix:** Split into `index.html`, `style.css`, `app.js`. Serve all three from the HTTP server. Add `Content-Type` handling for `.css` and `.js`.
**Files:** `index.html` → `index.html` + `style.css` + `app.js`, `server.js`

### P3.3: Change `isActive` to boolean
**Problem:** `isActive` is `'active'` or `'inactive'` (strings). Every comparison is `=== 'active'` or `=== 'inactive'`. Fragile — a typo like `'actve'` silently fails.
**Fix:** Change to `true`/`false`. Update all comparisons in `state.js`, `server.js`, `index.html`.
**Files:** `lib/state.js`, `server.js`, `index.html`, tests

### P3.4: Fix `server.listen` monkey-patch
**Problem:** `server.js:172-177` overrides `server.listen` with a wrapper to start the poll timer. This is brittle — if anything calls `http.Server.prototype.listen.call(server, ...)` the timer never starts.
**Fix:** Use `server.on('listening', () => { poll(); pollTimer = setInterval(poll, pollInterval); })` instead.
**Files:** `server.js`

### P3.5: Replace silent `catch {}` blocks
**Problem:** Multiple empty catch blocks in the frontend (`onmessage`, `loadInitial`, `connect`). If JSON parsing fails or the fetch errors, nothing is logged. Debugging is blind.
**Fix:** Add `console.warn` in catch blocks. Optionally show a subtle "parse error" indicator in the UI.
**Files:** `index.html`

### P3.6: Remove inactive run view entirely
**What:** Remove the Active/Inactive toggle, `viewFilter` state, and all filtering logic. Show all runs on disk as flat tabs — no active/inactive distinction in the UI.
**Files:** `index.html`

---

## Verification

1. Run existing tests: `node --test dashboard/test/`
2. Start server: `node dashboard/server.js`
3. Create a fake run: write JSONL to `runs/TEST-1/run.log`, verify it appears in UI
4. Verify SSE keepalive with browser DevTools Network tab (`:keepalive` comments every 15s)
5. Verify log filtering toggles work
6. Verify artifact panels show content
7. Add tests for new server behavior (keepalive, artifact caching, log cap)

---

## Resolved Questions

- **Logs:** File-based, no in-memory accumulation — tail-read only.
- **Artifact display:** Keep current fields as-is.
- **Inactive view:** Removed entirely — flat list of all runs on disk.
