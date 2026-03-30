# Dashboard Upgrade — Implementation Plan

Based on [claude-dashboard-improvement-plan.md](file:///e:/workflows/axomic-engineering/plans/claude-dashboard-improvement-plan.md). All 17 items, organized into 5 execution phases.

---

## Phase 1 — Server Fixes

Server-side changes to [server.js](file:///e:/workflows/axomic-engineering/dashboard/server.js) and [lib/watcher.js](file:///e:/workflows/axomic-engineering/dashboard/lib/watcher.js). No frontend changes — existing tests remain green throughout.

### P1.1: SSE keepalive

#### [MODIFY] [server.js](file:///e:/workflows/axomic-engineering/dashboard/server.js)
- Add a `setInterval` that sends `:keepalive\n\n` to every SSE client every 15s
- Start the interval alongside the poll timer in the `listening` handler (see P3.4)
- Clear the interval in `server.close()`

### P1.3: Stop accumulating logs in memory

#### [MODIFY] [watcher.js](file:///e:/workflows/axomic-engineering/dashboard/lib/watcher.js)
- Add a `tailLast(filePath, maxLines)` method to [LogTailer](file:///e:/workflows/axomic-engineering/dashboard/lib/watcher.js#6-50) that reads the last N complete lines from a file (seeking backwards from EOF)
- This replaces the streaming-accumulation approach — each poll gets a fresh snapshot of the last 50 lines

#### [MODIFY] [server.js](file:///e:/workflows/axomic-engineering/dashboard/server.js)
- Remove `run.logs` array accumulation. Instead, each poll calls `tailLast(logFile, 50)` to get the most recent lines
- Parse them fresh each poll via [parseLogLine()](file:///e:/workflows/axomic-engineering/dashboard/lib/state.js#7-21). Since it's only 50 lines, this is cheap
- Pass the parsed entries directly to [buildRunState()](file:///e:/workflows/axomic-engineering/dashboard/lib/state.js#22-63)

### P1.4: Cache artifact reads by mtime

#### [MODIFY] [server.js](file:///e:/workflows/axomic-engineering/dashboard/server.js)
- Add a `Map<string, { mtimeMs: number, data: object }>` cache for artifacts
- In [loadArtifacts()](file:///e:/workflows/axomic-engineering/dashboard/server.js#92-111), `fs.statSync()` each artifact file first. If `mtimeMs` matches cache, skip the read. Otherwise `readFileSync` + `JSON.parse` and update cache

### P1.5: Version-based change detection

#### [MODIFY] [server.js](file:///e:/workflows/axomic-engineering/dashboard/server.js)
- Replace `JSON.stringify` comparison with a `version` counter per run
- Increment version when: new log lines returned by `tailLast()`, or any artifact mtime changed
- Only [broadcast()](file:///e:/workflows/axomic-engineering/dashboard/server.js#112-125) when at least one run's version incremented

### P3.4: Fix `server.listen` monkey-patch

#### [MODIFY] [server.js](file:///e:/workflows/axomic-engineering/dashboard/server.js)
- Replace the `server.listen` override (L172-177) with `server.on('listening', ...)` event
- Replace the `server.close` override (L179-187) with `server.on('close', ...)` event

---

## Phase 2 — Frontend Fixes

Changes to the JS section of [index.html](file:///e:/workflows/axomic-engineering/dashboard/index.html). No server changes.

### P1.2: Close startup event gap

#### [MODIFY] [index.html](file:///e:/workflows/axomic-engineering/dashboard/index.html)
- Change init from [loadInitial().then(() => connect())](file:///e:/workflows/axomic-engineering/dashboard/index.html#706-726) to [connect(); loadInitial()](file:///e:/workflows/axomic-engineering/dashboard/index.html#673-693)
- SSE events received before [loadInitial()](file:///e:/workflows/axomic-engineering/dashboard/index.html#706-726) resolves get buffered — on load completion, merge initial state with any SSE updates that arrived

### P3.5: Replace silent `catch {}` blocks

#### [MODIFY] [index.html](file:///e:/workflows/axomic-engineering/dashboard/index.html)
- Add `console.warn('SSE parse error:', err)` in [onmessage](file:///e:/workflows/axomic-engineering/dashboard/index.html#682-688) catch
- Add `console.warn('Initial load failed:', err)` in [loadInitial](file:///e:/workflows/axomic-engineering/dashboard/index.html#706-726) catch
- Add `console.warn('EventSource error:', err)` in [onerror](file:///e:/workflows/axomic-engineering/dashboard/index.html#689-692)

### P3.6: Remove Active/Inactive toggle

#### [MODIFY] [index.html](file:///e:/workflows/axomic-engineering/dashboard/index.html)
- Remove `state.viewFilter` property
- Remove [renderViewToggle()](file:///e:/workflows/axomic-engineering/dashboard/index.html#763-793) function and its call in [render()](file:///e:/workflows/axomic-engineering/dashboard/index.html#743-762)
- Remove the `viewToggleContainer` div from HTML
- Simplify [renderTabs()](file:///e:/workflows/axomic-engineering/dashboard/index.html#794-817) — show all runs as flat tabs, no filtering
- Simplify [render()](file:///e:/workflows/axomic-engineering/dashboard/index.html#743-762) — select first run if none active, no filter matching
- Remove `run.isActive !== state.viewFilter` check in tab click handler

---

## Phase 3 — File Split (P3.2)

Split monolithic [index.html](file:///e:/workflows/axomic-engineering/dashboard/index.html) into three files and add static file serving.

#### [MODIFY] [index.html](file:///e:/workflows/axomic-engineering/dashboard/index.html)
- Keep only `<html>`, `<head>` (with `<link rel="stylesheet" href="style.css">`), `<body>` with structural HTML, and `<script src="app.js"></script>`

#### [NEW] [style.css](file:///e:/workflows/axomic-engineering/dashboard/style.css)
- Extract all CSS from the `<style>` block (lines 10-618 of current [index.html](file:///e:/workflows/axomic-engineering/dashboard/index.html))

#### [NEW] [app.js](file:///e:/workflows/axomic-engineering/dashboard/app.js)
- Extract all JS from the `<script>` block (lines 656-1072 of current [index.html](file:///e:/workflows/axomic-engineering/dashboard/index.html))
- Keep the IIFE wrapper

#### [MODIFY] [server.js](file:///e:/workflows/axomic-engineering/dashboard/server.js)
- Add static file serving for `/style.css` and `/app.js` with appropriate `Content-Type` headers
- Use `fs.readFileSync` at startup (same pattern as [loadIndexHtml](file:///e:/workflows/axomic-engineering/dashboard/server.js#134-141))

---

## Phase 4 — Live Update UX

All changes in `app.js` (post-split) and `style.css`, plus server-side artifact content exposure.

### P2.1: Log level filter buttons

#### [MODIFY] [app.js](file:///e:/workflows/axomic-engineering/dashboard/app.js)
- Add `state.logFilters = { INFO: true, WARN: true, ERROR: true, EVENT: true }` to state
- Render a row of toggle buttons in the log stream header
- Filter `run.recentLogs` by active levels before rendering entries

#### [MODIFY] [style.css](file:///e:/workflows/axomic-engineering/dashboard/style.css)
- Add styles for `.log-filter-btn` / `.log-filter-btn.active` — small pill buttons matching existing color scheme

### P2.2: Expandable log details

#### [MODIFY] [app.js](file:///e:/workflows/axomic-engineering/dashboard/app.js)
- In [createLogEntry()](file:///e:/workflows/axomic-engineering/dashboard/index.html#1032-1058), check if `entry.details` exists and is non-empty
- If so, add a `▸` toggle button. On click, append/remove a `<pre>` with `JSON.stringify(entry.details, null, 2)`

#### [MODIFY] [style.css](file:///e:/workflows/axomic-engineering/dashboard/style.css)
- Add styles for `.log-details-toggle` and `.log-details-content` (`<pre>` block)

### P2.3: Show artifact content

#### [MODIFY] [state.js](file:///e:/workflows/axomic-engineering/dashboard/lib/state.js)
- Change [mergeArtifacts()](file:///e:/workflows/axomic-engineering/dashboard/lib/state.js#64-90) to store artifact content, not just boolean flags
- Add `reviewContent`, `feedbackContent`, `escalationContent` fields to the merged state (null if absent)

#### [MODIFY] [server.js](file:///e:/workflows/axomic-engineering/dashboard/server.js)
- Add `escalation: 'ESCALATION.json'` to the artifact files map in [loadArtifacts()](file:///e:/workflows/axomic-engineering/dashboard/server.js#92-111)

#### [MODIFY] [app.js](file:///e:/workflows/axomic-engineering/dashboard/app.js)
- Below the task queue section, render collapsible panels for each present artifact:
  - **REVIEW**: Table of code review items — severity, file, line, comment, status
  - **ESCALATION**: List of escalation entries — category, severity, summary, resolved status
  - **FEEDBACK**: List of feedback items — type, file, comment, status

#### [MODIFY] [style.css](file:///e:/workflows/axomic-engineering/dashboard/style.css)
- Add styles for `.artifact-panel`, `.artifact-toggle`, `.artifact-content`, severity badges

### P2.4: Task progress summary

#### [MODIFY] [app.js](file:///e:/workflows/axomic-engineering/dashboard/app.js)
- Above the task list, compute `verified / total` counts from `run.tasks`
- Render a `3/5 verified` label with a thin progress bar

#### [MODIFY] [style.css](file:///e:/workflows/axomic-engineering/dashboard/style.css)
- Add `.progress-bar` and `.progress-fill` styles

### P2.5: Elapsed time display

#### [MODIFY] [app.js](file:///e:/workflows/axomic-engineering/dashboard/app.js)
- In the sidebar status footer, compute elapsed from `run.startedAt` to now (or `run.lastActivity` if inactive)
- Format as `Xm Ys` and render next to the status value
- Update every second via a `setInterval` that re-renders just the elapsed element

### P2.6: Browser notifications

#### [MODIFY] [app.js](file:///e:/workflows/axomic-engineering/dashboard/app.js)
- On first user interaction, call `Notification.requestPermission()`
- In [handleEvent()](file:///e:/workflows/axomic-engineering/dashboard/index.html#727-742), fire a browser `Notification` when:
  - An ERROR-level log appears
  - Run `overallStatus` transitions to `done` or `escalated`
- Track last-seen log count per run to avoid duplicate notifications

---

## Phase 5 — Code Health

### P3.1: Diff-based DOM updates

#### [MODIFY] [app.js](file:///e:/workflows/axomic-engineering/dashboard/app.js)
- Track `lastRenderedState` (ticketId + overallStatus + stage statuses + task list + recentLogs length)
- **Log stream**: Only append new entries and remove old ones instead of rebuilding. Compare `recentLogs` by timestamp/index
- **Workflow steps**: Only update status class/icon if changed
- **Task list**: Only re-render if task array changed
- **Sidebar status**: Only update text if status/counters changed
- Fall back to full re-render on tab switch

### P3.3: Change `isActive` to boolean

#### [MODIFY] [state.js](file:///e:/workflows/axomic-engineering/dashboard/lib/state.js)
- [classifyRunActivity()](file:///e:/workflows/axomic-engineering/dashboard/lib/state.js#93-97) returns `true`/`false` instead of `'active'`/`'inactive'`

#### [MODIFY] [server.js](file:///e:/workflows/axomic-engineering/dashboard/server.js)
- No changes needed — `isActive` is set from [classifyRunActivity()](file:///e:/workflows/axomic-engineering/dashboard/lib/state.js#93-97) return value

#### [MODIFY] [app.js](file:///e:/workflows/axomic-engineering/dashboard/app.js)
- Replace all `=== 'active'` / `=== 'inactive'` comparisons with boolean checks

#### [MODIFY] Tests
- Update [state.test.js](file:///e:/workflows/axomic-engineering/dashboard/test/state.test.js) assertions from `'active'`/`'inactive'` to `true`/`false`
- Update [integration.test.js](file:///e:/workflows/axomic-engineering/dashboard/test/integration.test.js) assertions similarly

---

## Verification Plan

### Automated Tests

**Existing tests** (must remain green throughout):
```bash
node --test dashboard/test/stages.test.js dashboard/test/state.test.js dashboard/test/watcher.test.js dashboard/test/integration.test.js dashboard/test/pid.test.js
```

**New tests to add** in `dashboard/test/`:

| Test File | What It Covers |
|---|---|
| `watcher.test.js` | Add tests for `tailLast()` method: reads last N lines, handles files shorter than N, handles empty file |
| `state.test.js` | Update `classifyRunActivity` tests for boolean returns (P3.3). Add tests for `mergeArtifacts` with full content (P2.3) |
| `integration.test.js` | Add test that SSE keepalive comments arrive within 20s. Add test that artifact cache works (write artifact, poll, verify state, modify file, poll again, verify update) |

### Manual Browser Verification

> [!IMPORTANT]
> Manual checks should be done after Phase 3 (file split) when the UI is testable as a whole.

1. Start the server: `node dashboard/server.js`
2. Open `http://localhost:3847` in browser
3. Create a fake run directory:
   ```bash
   mkdir -p runs/TEST-1
   echo '{"ts":"2026-03-27T13:00:00Z","level":"INFO","cat":"startup","msg":"Run started"}' >> runs/TEST-1/run.log
   ```
4. Verify: tab appears, workflow shows "Startup" in progress, log stream shows entry
5. Append more logs with different levels/categories and verify:
   - Log filter buttons toggle visibility
   - Expandable details work for entries with `details` field
   - Workflow steps progress correctly
6. Create artifact files (`REVIEW.json`, `ESCALATION.json`, `FEEDBACK.json`) and verify collapsible panels appear with content
7. Check browser DevTools Network tab → EventStream shows `:keepalive` comments every ~15s
8. Verify browser notifications fire on ERROR log append
