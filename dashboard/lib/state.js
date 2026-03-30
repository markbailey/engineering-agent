/** RunState builder: JSONL parsing, artifact merging, state aggregation. */

const { inferStages, inferActiveAgent } = require('./stages.js');

const RECENT_LOG_LIMIT = 50;

/**
 * Parse a single JSONL log line. Returns LogEntry or null if invalid.
 */
function parseLogLine(line) {
  const trimmed = line.trim();
  if (!trimmed) return null;
  try {
    const obj = JSON.parse(trimmed);
    if (!obj.level || !obj.cat || !obj.msg) return null;
    return obj;
  } catch {
    return null;
  }
}

/**
 * Build a RunState from a ticket ID and array of parsed log entries.
 */
function buildRunState(ticketId, logs) {
  const stages = inferStages(logs);
  const activeAgent = inferActiveAgent(logs);
  const errors = logs.filter(e => e.level === 'ERROR');
  const recentLogs = logs.slice(-RECENT_LOG_LIMIT);

  let reviewRounds = 0;
  let feedbackRounds = 0;
  for (const entry of logs) {
    if (entry.level === 'EVENT' && entry.cat === 'review') reviewRounds++;
    if (entry.level === 'EVENT' && entry.cat === 'monitor') feedbackRounds++;
  }

  const currentStage = [...stages].reverse().find(s => s.status !== 'pending')?.id || null;

  return {
    ticketId,
    title: null,
    overallStatus: null,
    currentStage,
    stages,
    tasks: [],
    activeAgent,
    recentLogs,
    errors,
    reviewRounds,
    feedbackRounds,
    artifacts: {
      hasPrd: false,
      hasReview: false,
      hasFeedback: false,
      hasEscalation: false,
      hasConflict: false,
      hasSecrets: false,
    },
    reviewContent: null,
    feedbackContent: null,
    escalationContent: null,
    startedAt: logs.length > 0 ? logs[0].ts : null,
    lastActivity: logs.length > 0 ? logs[logs.length - 1].ts : null,
  };
}

/**
 * Merge artifact data (PRD, REVIEW, FEEDBACK, etc.) into a RunState.
 * Returns a new state object (does not mutate input).
 */
function mergeArtifacts(state, artifacts) {
  const merged = { ...state, artifacts: { ...state.artifacts } };

  if (artifacts.prd) {
    merged.title = artifacts.prd.title || null;
    merged.overallStatus = artifacts.prd.overall_status || null;
    merged.tasks = (artifacts.prd.tasks || []).map(t => ({
      id: t.id,
      description: t.description,
      status: t.status,
      repo: t.repo || null,
    }));
    merged.artifacts.hasPrd = true;
  }

  if (artifacts.review) {
    merged.artifacts.hasReview = true;
    merged.reviewContent = artifacts.review;
  }
  if (artifacts.feedback) {
    merged.artifacts.hasFeedback = true;
    merged.feedbackContent = artifacts.feedback;
  }
  if (artifacts.escalation) {
    merged.artifacts.hasEscalation = true;
    merged.escalationContent = artifacts.escalation;
  }
  if (artifacts.conflict) merged.artifacts.hasConflict = true;
  if (artifacts.secrets) merged.artifacts.hasSecrets = true;

  return merged;
}

const TERMINAL_STATUSES = ['done', 'escalated', 'blocked_secrets'];

function classifyRunActivity(runState, pidAlive) {
  if (TERMINAL_STATUSES.includes(runState.overallStatus)) return false;
  return pidAlive;
}

function classifyRunTerminal(runState) {
  return TERMINAL_STATUSES.includes(runState.overallStatus);
}

module.exports = { parseLogLine, buildRunState, mergeArtifacts, TERMINAL_STATUSES, classifyRunActivity, classifyRunTerminal };
