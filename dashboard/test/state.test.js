const { describe, it } = require('node:test');
const assert = require('node:assert/strict');
const { parseLogLine, buildRunState, mergeArtifacts, TERMINAL_STATUSES, classifyRunActivity } = require('../lib/state.js');

describe('parseLogLine', () => {
  it('parses valid JSONL log entry', () => {
    const line = '{"ts":"2026-03-21T14:30:00Z","level":"INFO","cat":"startup","msg":"Run started","details":{}}';
    const entry = parseLogLine(line);
    assert.equal(entry.ts, '2026-03-21T14:30:00Z');
    assert.equal(entry.level, 'INFO');
    assert.equal(entry.cat, 'startup');
    assert.equal(entry.msg, 'Run started');
  });

  it('returns null for empty line', () => {
    assert.equal(parseLogLine(''), null);
    assert.equal(parseLogLine('  '), null);
  });

  it('returns null for malformed JSON', () => {
    assert.equal(parseLogLine('{broken json'), null);
    assert.equal(parseLogLine('not json at all'), null);
  });

  it('returns null for JSON missing required fields', () => {
    assert.equal(parseLogLine('{"foo":"bar"}'), null);
    assert.equal(parseLogLine('{"level":"INFO"}'), null);
  });

  it('handles entry without details field', () => {
    const line = '{"ts":"2026-03-21T14:30:00Z","level":"INFO","cat":"startup","msg":"hi"}';
    const entry = parseLogLine(line);
    assert.equal(entry.msg, 'hi');
    assert.equal(entry.details, undefined);
  });
});

describe('buildRunState', () => {
  it('builds state from log entries', () => {
    const logs = [
      { ts: '2026-03-21T14:30:00Z', level: 'INFO', cat: 'startup', msg: 'Run started' },
      { ts: '2026-03-21T14:30:05Z', level: 'INFO', cat: 'intake', msg: 'Ticket validated' },
    ];
    const state = buildRunState('WTP-123', logs);
    assert.equal(state.ticketId, 'WTP-123');
    assert.equal(state.stages.length, 11);
    assert.equal(state.stages[0].status, 'complete'); // startup
    assert.equal(state.stages[1].status, 'in_progress'); // intake
    assert.equal(state.activeAgent, 'jira-agent');
    assert.equal(state.recentLogs.length, 2);
    assert.equal(state.startedAt, '2026-03-21T14:30:00Z');
    assert.equal(state.lastActivity, '2026-03-21T14:30:05Z');
  });

  it('returns empty state for no logs', () => {
    const state = buildRunState('TEST-1', []);
    assert.equal(state.ticketId, 'TEST-1');
    assert.equal(state.activeAgent, null);
    assert.equal(state.recentLogs.length, 0);
    assert.equal(state.errors.length, 0);
    assert.equal(state.startedAt, null);
  });

  it('collects error entries', () => {
    const logs = [
      { ts: '1', level: 'INFO', cat: 'startup', msg: 'ok' },
      { ts: '2', level: 'ERROR', cat: 'qa', msg: 'tsc failed' },
      { ts: '3', level: 'ERROR', cat: 'qa', msg: 'lint failed' },
    ];
    const state = buildRunState('T-1', logs);
    assert.equal(state.errors.length, 2);
    assert.equal(state.errors[0].msg, 'tsc failed');
  });

  it('keeps only last 50 logs in recentLogs', () => {
    const logs = Array.from({ length: 60 }, (_, i) => ({
      ts: String(i), level: 'INFO', cat: 'implementation', msg: `log ${i}`,
    }));
    const state = buildRunState('T-1', logs);
    assert.equal(state.recentLogs.length, 50);
    assert.equal(state.recentLogs[0].msg, 'log 10');
  });

  it('counts review and feedback rounds from event logs', () => {
    const logs = [
      { ts: '1', level: 'EVENT', cat: 'review', msg: 'Critic review round 1' },
      { ts: '2', level: 'EVENT', cat: 'review', msg: 'Critic review round 2' },
      { ts: '3', level: 'EVENT', cat: 'monitor', msg: 'feedback round 1' },
    ];
    const state = buildRunState('T-1', logs);
    assert.equal(state.reviewRounds, 2);
    assert.equal(state.feedbackRounds, 1);
  });
});

describe('mergeArtifacts', () => {
  it('merges PRD.json data into state', () => {
    const state = buildRunState('T-1', []);
    const prd = {
      title: 'Add pagination',
      overall_status: 'in_progress',
      tasks: [
        { id: 'task-1', description: 'setup', status: 'verified', repo: 'api' },
        { id: 'task-2', description: 'implement', status: 'in_progress', repo: 'api' },
      ],
    };
    const merged = mergeArtifacts(state, { prd });
    assert.equal(merged.title, 'Add pagination');
    assert.equal(merged.overallStatus, 'in_progress');
    assert.equal(merged.tasks.length, 2);
    assert.equal(merged.tasks[0].status, 'verified');
    assert.equal(merged.artifacts.hasPrd, true);
  });

  it('detects artifact presence', () => {
    const state = buildRunState('T-1', []);
    const merged = mergeArtifacts(state, {
      prd: { title: 'x', overall_status: 'done', tasks: [] },
      review: {},
      feedback: {},
      escalation: {},
      conflict: {},
      secrets: {},
    });
    assert.equal(merged.artifacts.hasPrd, true);
    assert.equal(merged.artifacts.hasReview, true);
    assert.equal(merged.artifacts.hasFeedback, true);
    assert.equal(merged.artifacts.hasEscalation, true);
    assert.equal(merged.artifacts.hasConflict, true);
    assert.equal(merged.artifacts.hasSecrets, true);
  });

  it('stores artifact content for review, feedback, escalation', () => {
    const state = buildRunState('T-1', []);
    const reviewData = { issues: [{ severity: 'high', msg: 'missing null check' }] };
    const feedbackData = { items: [{ file: 'index.js', comment: 'simplify' }] };
    const escalationData = { category: 'test_failure', severity: 'high' };
    const merged = mergeArtifacts(state, {
      review: reviewData,
      feedback: feedbackData,
      escalation: escalationData,
    });
    assert.deepEqual(merged.reviewContent, reviewData);
    assert.deepEqual(merged.feedbackContent, feedbackData);
    assert.deepEqual(merged.escalationContent, escalationData);
  });

  it('handles missing PRD gracefully', () => {
    const state = buildRunState('T-1', []);
    const merged = mergeArtifacts(state, {});
    assert.equal(merged.title, null);
    assert.equal(merged.overallStatus, null);
    assert.equal(merged.tasks.length, 0);
    assert.equal(merged.artifacts.hasPrd, false);
  });
});

describe('classifyRunActivity', () => {
  it('returns inactive for terminal status done even with pidAlive', () => {
    assert.equal(classifyRunActivity({ overallStatus: 'done' }, true), 'inactive');
  });

  it('returns inactive for terminal status escalated even with pidAlive', () => {
    assert.equal(classifyRunActivity({ overallStatus: 'escalated' }, true), 'inactive');
  });

  it('returns inactive for terminal status blocked_secrets even with pidAlive', () => {
    assert.equal(classifyRunActivity({ overallStatus: 'blocked_secrets' }, true), 'inactive');
  });

  it('returns active for non-terminal status with pidAlive true', () => {
    assert.equal(classifyRunActivity({ overallStatus: 'in_progress' }, true), 'active');
  });

  it('returns inactive for non-terminal status with pidAlive false', () => {
    assert.equal(classifyRunActivity({ overallStatus: 'in_progress' }, false), 'inactive');
  });

  it('returns active for null overallStatus with pidAlive true', () => {
    assert.equal(classifyRunActivity({ overallStatus: null }, true), 'active');
  });

  it('returns inactive for null overallStatus with pidAlive false', () => {
    assert.equal(classifyRunActivity({ overallStatus: null }, false), 'inactive');
  });
});
