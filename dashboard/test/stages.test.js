const { describe, it } = require('node:test');
const assert = require('node:assert/strict');
const {
  WORKFLOW_STAGES,
  STAGE_ORDER,
  CAT_TO_STAGE,
  CAT_TO_AGENT,
  inferStages,
  inferActiveAgent,
} = require('../lib/stages.js');

describe('WORKFLOW_STAGES', () => {
  it('has 11 stages in order', () => {
    assert.equal(WORKFLOW_STAGES.length, 11);
    assert.equal(WORKFLOW_STAGES[0].id, 'startup');
    assert.equal(WORKFLOW_STAGES[10].id, 'pr_monitoring');
  });

  it('each stage has id and label', () => {
    for (const s of WORKFLOW_STAGES) {
      assert.ok(s.id, 'missing id');
      assert.ok(s.label, 'missing label');
    }
  });
});

describe('CAT_TO_STAGE', () => {
  it('maps all known log categories to stages', () => {
    const cats = [
      'startup', 'intake', 'planning', 'worktree',
      'implementation', 'qa', 'conflict', 'review',
      'secrets', 'pr', 'monitor', 'cleanup',
    ];
    for (const c of cats) {
      assert.ok(CAT_TO_STAGE[c], `missing mapping for cat: ${c}`);
    }
  });
});

describe('CAT_TO_AGENT', () => {
  it('maps key categories to agent names', () => {
    assert.equal(CAT_TO_AGENT['intake'], 'jira-agent');
    assert.equal(CAT_TO_AGENT['planning'], 'planner-agent');
    assert.equal(CAT_TO_AGENT['implementation'], 'developer-agent');
    assert.equal(CAT_TO_AGENT['qa'], 'qa-agent');
    assert.equal(CAT_TO_AGENT['review'], 'the-critic');
    assert.equal(CAT_TO_AGENT['conflict'], 'conflict-resolution-agent');
    assert.equal(CAT_TO_AGENT['secrets'], 'secret-scanner');
    assert.equal(CAT_TO_AGENT['pr'], 'pr-agent');
    assert.equal(CAT_TO_AGENT['monitor'], 'pr-monitor');
    assert.equal(CAT_TO_AGENT['summary'], 'run-analyst');
  });
});

describe('inferStages', () => {
  it('returns all pending when no logs', () => {
    const stages = inferStages([]);
    assert.equal(stages.length, 11);
    for (const s of stages) {
      assert.equal(s.status, 'pending');
    }
  });

  it('marks startup as in_progress with only startup log', () => {
    const logs = [{ cat: 'startup', level: 'INFO' }];
    const stages = inferStages(logs);
    assert.equal(stages[0].status, 'in_progress');
    assert.equal(stages[1].status, 'pending');
  });

  it('marks earlier stages as complete when later stage seen', () => {
    const logs = [
      { cat: 'startup', level: 'INFO' },
      { cat: 'intake', level: 'INFO' },
      { cat: 'planning', level: 'INFO' },
    ];
    const stages = inferStages(logs);
    assert.equal(stages[0].status, 'complete'); // startup
    assert.equal(stages[1].status, 'complete'); // intake
    assert.equal(stages[2].status, 'in_progress'); // planning
    assert.equal(stages[3].status, 'pending'); // worktree
  });

  it('marks stage as error if last entry for that cat is ERROR level', () => {
    const logs = [
      { cat: 'startup', level: 'INFO' },
      { cat: 'intake', level: 'INFO' },
      { cat: 'qa', level: 'INFO' },
      { cat: 'qa', level: 'ERROR' },
    ];
    const stages = inferStages(logs);
    const qaStage = stages.find(s => s.id === 'full_qa');
    assert.equal(qaStage.status, 'error');
  });

  it('recovers from error if later non-error log for same cat', () => {
    const logs = [
      { cat: 'qa', level: 'ERROR' },
      { cat: 'qa', level: 'INFO' },
    ];
    const stages = inferStages(logs);
    const qaStage = stages.find(s => s.id === 'full_qa');
    assert.equal(qaStage.status, 'in_progress');
  });

  it('maps implementation cat to implementation stage', () => {
    const logs = [
      { cat: 'startup', level: 'INFO' },
      { cat: 'implementation', level: 'INFO' },
    ];
    const stages = inferStages(logs);
    const impl = stages.find(s => s.id === 'implementation');
    assert.equal(impl.status, 'in_progress');
  });

  it('ignores unknown categories gracefully', () => {
    const logs = [
      { cat: 'startup', level: 'INFO' },
      { cat: 'unknown_thing', level: 'INFO' },
    ];
    const stages = inferStages(logs);
    assert.equal(stages[0].status, 'in_progress'); // startup still latest known
  });
});

describe('inferActiveAgent', () => {
  it('returns null for empty logs', () => {
    assert.equal(inferActiveAgent([]), null);
  });

  it('returns agent for most recent mapped category', () => {
    const logs = [
      { cat: 'startup', level: 'INFO' },
      { cat: 'implementation', level: 'INFO' },
    ];
    assert.equal(inferActiveAgent(logs), 'developer-agent');
  });

  it('returns null if no cat has agent mapping', () => {
    const logs = [
      { cat: 'startup', level: 'INFO' },
      { cat: 'worktree', level: 'INFO' },
    ];
    assert.equal(inferActiveAgent(logs), null);
  });
});
