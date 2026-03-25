/** Workflow stages, category mappings, and stage inference. */

const WORKFLOW_STAGES = [
  { id: 'startup',             label: 'Startup' },
  { id: 'ticket_intake',       label: 'Ticket Intake' },
  { id: 'planning',            label: 'Planning' },
  { id: 'worktree_setup',      label: 'Worktree Setup' },
  { id: 'implementation',      label: 'Implementation' },
  { id: 'full_qa',             label: 'Full QA' },
  { id: 'conflict_resolution', label: 'Conflict Resolution' },
  { id: 'internal_review',     label: 'Internal Review' },
  { id: 'secret_scan',         label: 'Secret Scan' },
  { id: 'pr_creation',         label: 'PR Creation' },
  { id: 'pr_monitoring',       label: 'PR Monitoring' },
];

// Positional index for ordering
const STAGE_ORDER = Object.fromEntries(WORKFLOW_STAGES.map((s, i) => [s.id, i]));

// Log category → stage id
const CAT_TO_STAGE = {
  startup:        'startup',
  intake:         'ticket_intake',
  planning:       'planning',
  worktree:       'worktree_setup',
  implementation: 'implementation',
  qa:             'full_qa',
  conflict:       'conflict_resolution',
  review:         'internal_review',
  secrets:        'secret_scan',
  pr:             'pr_creation',
  monitor:        'pr_monitoring',
  cleanup:        'post_merge',
};

// Log category → active agent name
const CAT_TO_AGENT = {
  intake:         'jira-agent',
  planning:       'planner-agent',
  implementation: 'developer-agent',
  qa:             'qa-agent',
  review:         'the-critic',
  conflict:       'conflict-resolution-agent',
  secrets:        'secret-scanner',
  pr:             'pr-agent',
  monitor:        'pr-monitor',
  summary:        'run-analyst',
};

/**
 * Infer stage statuses from an ordered array of log entries.
 * Each entry must have { cat, level }.
 * Returns a new array of { id, label, status } matching WORKFLOW_STAGES order.
 */
function inferStages(logs) {
  // Track which stage ids have been seen and their last level
  const seen = new Map(); // stageId → lastLevel
  let latestStageIdx = -1;

  for (const entry of logs) {
    const stageId = CAT_TO_STAGE[entry.cat];
    if (!stageId) continue;
    const idx = STAGE_ORDER[stageId];
    if (idx === undefined) continue;
    seen.set(stageId, entry.level);
    if (idx > latestStageIdx) latestStageIdx = idx;
  }

  return WORKFLOW_STAGES.map((stage, idx) => {
    const lastLevel = seen.get(stage.id);
    let status;
    if (lastLevel === undefined) {
      status = 'pending';
    } else if (lastLevel === 'ERROR') {
      status = 'error';
    } else if (idx < latestStageIdx) {
      status = 'complete';
    } else {
      status = 'in_progress';
    }
    return { id: stage.id, label: stage.label, status };
  });
}

/**
 * Infer the currently active agent from the most recent log entry's category.
 * Returns agent name string or null.
 */
function inferActiveAgent(logs) {
  for (let i = logs.length - 1; i >= 0; i--) {
    const agent = CAT_TO_AGENT[logs[i].cat];
    if (agent !== undefined) return agent;
  }
  return null;
}

module.exports = {
  WORKFLOW_STAGES,
  STAGE_ORDER,
  CAT_TO_STAGE,
  CAT_TO_AGENT,
  inferStages,
  inferActiveAgent,
};
