const { describe, it } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const htmlPath = path.join(__dirname, '..', 'index.html');
const html = fs.readFileSync(htmlPath, 'utf8');

describe('P2.4: Task progress bar', () => {
  it('has .task-progress CSS class', () => {
    assert.ok(html.includes('.task-progress'), 'missing .task-progress CSS');
  });

  it('has .progress-bar and .progress-fill CSS classes', () => {
    assert.ok(html.includes('.progress-bar'), 'missing .progress-bar CSS');
    assert.ok(html.includes('.progress-fill'), 'missing .progress-fill CSS');
  });

  it('has .task-progress-label CSS class', () => {
    assert.ok(html.includes('.task-progress-label'), 'missing .task-progress-label CSS');
  });

  it('JS creates progress bar with verified/total count', () => {
    assert.ok(html.includes("'task-progress'"), 'missing task-progress element creation');
    assert.ok(html.includes("'progress-bar'"), 'missing progress-bar element creation');
    assert.ok(html.includes("'progress-fill'"), 'missing progress-fill element creation');
    assert.ok(html.includes("verified / total * 100"), 'missing progress width calculation');
  });

  it('JS filters verified and complete tasks for progress', () => {
    assert.ok(
      html.includes("=== 'verified'") && html.includes("=== 'complete'"),
      'progress must count both verified and complete tasks'
    );
  });
});

describe('P2.5: Elapsed time display', () => {
  it('has .status-elapsed CSS class', () => {
    assert.ok(html.includes('.status-elapsed'), 'missing .status-elapsed CSS');
  });

  it('JS creates elapsed time element with id elapsedTime', () => {
    assert.ok(html.includes("'elapsedTime'"), 'missing elapsedTime element');
  });

  it('JS sets up interval for active runs', () => {
    assert.ok(html.includes('setInterval(updateElapsed'), 'missing setInterval for elapsed timer');
  });

  it('JS clears old elapsed timer on re-render', () => {
    assert.ok(html.includes("getElementById('elapsedTime')"), 'missing old timer cleanup lookup');
    assert.ok(html.includes('clearInterval'), 'missing clearInterval for old timer');
  });

  it('JS computes elapsed from startedAt', () => {
    assert.ok(html.includes('run.startedAt'), 'must use run.startedAt');
    assert.ok(html.includes('Math.floor(diffMs / 60000)'), 'must compute minutes');
  });
});

describe('P2.6: Browser notifications', () => {
  it('JS declares notificationPermission state', () => {
    assert.ok(html.includes('notificationPermission'), 'missing notificationPermission variable');
  });

  it('JS declares lastSeenLogCount tracking map', () => {
    assert.ok(html.includes('lastSeenLogCount'), 'missing lastSeenLogCount');
  });

  it('JS requests notification permission on first click', () => {
    assert.ok(html.includes('Notification.requestPermission'), 'missing permission request');
  });

  it('JS defines notify() function', () => {
    assert.ok(html.includes('function notify('), 'missing notify function');
  });

  it('JS checks document.hidden before sending notification', () => {
    assert.ok(html.includes('document.hidden'), 'must check document.hidden');
  });

  it('JS notifies on ERROR log entries', () => {
    assert.ok(html.includes("entry.level === 'ERROR'"), 'must check for ERROR level');
  });

  it('JS notifies on status transition to done', () => {
    assert.ok(html.includes("=== 'done'"), 'must detect done status');
  });

  it('JS notifies on status transition to escalated', () => {
    assert.ok(html.includes("=== 'escalated'"), 'must detect escalated status');
  });

  it('JS compares previous state before setting new state for notifications', () => {
    // state.runs.set() must come AFTER notification checks
    const notifyIdx = html.indexOf('function notify(');
    const setIdx = html.indexOf("state.runs.set(event.ticketId, event.data)");
    const prevRunIdx = html.indexOf("prevRun && prevRun.overallStatus !== event.data.overallStatus");
    assert.ok(notifyIdx > 0, 'notify function must exist');
    assert.ok(setIdx > 0, 'state.runs.set must exist in handleEvent');
    assert.ok(prevRunIdx > 0, 'must compare prevRun state');
    assert.ok(prevRunIdx < setIdx, 'notification checks must come before state.runs.set');
  });
});
