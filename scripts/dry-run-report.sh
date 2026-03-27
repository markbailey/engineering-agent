#!/usr/bin/env bash
# dry-run-report.sh — Generate human-readable dry-run summary
# Args: $1=ticket_id
# Reads artifacts from runs/{ticket_id}/ and prints summary to stdout

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/output.sh"
AGENT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [[ $# -lt 1 ]]; then
  emit_error "Usage: dry-run-report.sh <ticket_id>"
fi

ticket_id="$1"
RUN_DIR="$AGENT_ROOT/runs/$ticket_id"

if [[ ! -d "$RUN_DIR" ]]; then
  emit_error "Run directory not found: $RUN_DIR"
fi

echo "============================================"
echo "  DRY-RUN REPORT: $ticket_id"
echo "============================================"
echo ""

# --- PRD.json ---
PRD="$RUN_DIR/PRD.json"
if [[ -f "$PRD" ]]; then
  echo "## PRD Summary"
  node -e "
    const prd = JSON.parse(require('fs').readFileSync(process.argv[1], 'utf8'));
    console.log('  Status: ' + (prd.overall_status || 'unknown'));
    console.log('  Dry run: ' + (prd.dry_run ? 'yes' : 'no'));
    console.log('  Branch: ' + (prd.branch || 'n/a'));
    console.log('');

    // Tasks
    const tasks = prd.tasks || [];
    if (tasks.length > 0) {
      console.log('  Tasks (' + tasks.length + '):');
      let filesTotal = 0;
      tasks.forEach((t, i) => {
        const files = (t.files_affected || []).length;
        filesTotal += files;
        console.log('    ' + (i+1) + '. [' + (t.status || 'unknown') + '] ' + (t.title || t.id || 'untitled') + ' (' + files + ' files)');
      });
      console.log('');
      console.log('  Estimated PR size: ' + filesTotal + ' files affected');
    } else {
      console.log('  No tasks found');
    }
    console.log('');

    // Acceptance criteria
    const ac = prd.acceptance_criteria || [];
    if (ac.length > 0) {
      console.log('  Acceptance Criteria (' + ac.length + '):');
      ac.forEach((c, i) => {
        const met = c.met !== undefined ? (c.met ? 'MET' : 'NOT MET') : '???';
        const text = typeof c === 'string' ? c : (c.criterion || c.text || JSON.stringify(c));
        console.log('    ' + (i+1) + '. [' + met + '] ' + text);
      });
    }
  " "$PRD" 2>/dev/null || echo "  (failed to parse PRD.json)"
  echo ""
else
  echo "## PRD: not found"
  echo ""
fi

# --- REVIEW.json ---
REVIEW="$RUN_DIR/REVIEW.json"
if [[ -f "$REVIEW" ]]; then
  echo "## Critic Review"
  node -e "
    const review = JSON.parse(require('fs').readFileSync(process.argv[1], 'utf8'));
    const verdict = review.verdict || review.overall_verdict || 'unknown';
    console.log('  Verdict: ' + verdict);
    const issues = review.issues || [];
    if (issues.length > 0) {
      const bySev = {};
      issues.forEach(i => { const s = i.severity || 'unknown'; bySev[s] = (bySev[s]||0)+1; });
      console.log('  Issues: ' + Object.entries(bySev).map(([k,v]) => v + ' ' + k).join(', '));
    } else {
      console.log('  Issues: none');
    }
  " "$REVIEW" 2>/dev/null || echo "  (failed to parse REVIEW.json)"
  echo ""
else
  echo "## Critic Review: not run"
  echo ""
fi

# --- SECRETS.json ---
SECRETS="$RUN_DIR/SECRETS.json"
if [[ -f "$SECRETS" ]]; then
  echo "## Secret Scan"
  node -e "
    const secrets = JSON.parse(require('fs').readFileSync(process.argv[1], 'utf8'));
    const findings = secrets.findings || [];
    if (findings.length > 0) {
      console.log('  FINDINGS: ' + findings.length + ' secret(s) detected — WOULD BLOCK PR');
      findings.forEach(f => {
        console.log('    - ' + (f.file || '?') + ':' + (f.line || '?') + ' (' + (f.type || 'unknown') + ')');
      });
    } else {
      console.log('  Result: clean — no secrets found');
    }
  " "$SECRETS" 2>/dev/null || echo "  (failed to parse SECRETS.json)"
  echo ""
else
  echo "## Secret Scan: clean (no SECRETS.json)"
  echo ""
fi

# --- CONFLICT.json ---
CONFLICT="$RUN_DIR/CONFLICT.json"
if [[ -f "$CONFLICT" ]]; then
  echo "## Conflict Resolution"
  node -e "
    const c = JSON.parse(require('fs').readFileSync(process.argv[1], 'utf8'));
    console.log('  Merge: ' + (c.merge_status || 'unknown'));
    console.log('  Regression guard: ' + (c.regression_guard || 'unknown'));
    console.log('  Orphan check: ' + (c.orphan_check || 'unknown'));
    const conflicts = c.conflicts || [];
    if (conflicts.length > 0) {
      console.log('  Conflicted files: ' + conflicts.map(f => typeof f === 'string' ? f : f.file).join(', '));
    }
  " "$CONFLICT" 2>/dev/null || echo "  (failed to parse CONFLICT.json)"
  echo ""
else
  echo "## Conflict Resolution: not run"
  echo ""
fi

# --- ESCALATION.json ---
ESCALATION="$RUN_DIR/ESCALATION.json"
if [[ -f "$ESCALATION" ]]; then
  echo "## Escalations"
  node -e "
    const data = JSON.parse(require('fs').readFileSync(process.argv[1], 'utf8'));
    const entries = Array.isArray(data) ? data : (data.escalations || []);
    if (entries.length > 0) {
      entries.forEach(e => {
        console.log('  - [' + (e.severity || 'unknown') + '] ' + (e.reason || e.message || JSON.stringify(e)));
      });
    } else {
      console.log('  None');
    }
  " "$ESCALATION" 2>/dev/null || echo "  (failed to parse ESCALATION.json)"
  echo ""
else
  echo "## Escalations: none"
  echo ""
fi

# --- METRICS.json ---
METRICS="$RUN_DIR/METRICS.json"
if [[ -f "$METRICS" ]]; then
  echo "## Metrics"
  node -e "
    const m = JSON.parse(require('fs').readFileSync(process.argv[1], 'utf8'));
    Object.entries(m).forEach(([k,v]) => {
      console.log('  ' + k + ': ' + (typeof v === 'object' ? JSON.stringify(v) : v));
    });
  " "$METRICS" 2>/dev/null || echo "  (failed to parse METRICS.json)"
  echo ""
else
  echo "## Metrics: not collected"
  echo ""
fi

echo "============================================"
echo "  END OF DRY-RUN REPORT"
echo "============================================"
