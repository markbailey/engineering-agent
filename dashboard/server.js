#!/usr/bin/env node
/** Zero-dependency dashboard server: HTTP + SSE + file polling. */

const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const { LogTailer, scanRunsDir } = require('./lib/watcher.js');
const { parseLogLine, buildRunState, mergeArtifacts, classifyRunActivity } = require('./lib/state.js');

const DEFAULT_PORT = 3847;
const DEFAULT_POLL_MS = 1000;

/**
 * Create and return an HTTP server (not yet listening).
 * @param {{ runsDir?: string, pollInterval?: number }} opts
 */
function createDashboardServer(opts = {}) {
  const runsDir = opts.runsDir || path.resolve(process.cwd(), 'runs');
  const pollInterval = opts.pollInterval || DEFAULT_POLL_MS;

  /** @type {Map<string, { logs: object[], state: object }>} */
  const runs = new Map();
  const tailer = new LogTailer();
  /** @type {Set<http.ServerResponse>} */
  const sseClients = new Set();

  const indexHtml = loadIndexHtml();

  // --- Polling ---

  function poll() {
    const tickets = scanRunsDir(runsDir);
    let changed = false;

    for (const ticketId of tickets) {
      const ticketDir = path.join(runsDir, ticketId);
      const logFile = path.join(ticketDir, 'run.log');

      // Initialize run entry if new
      if (!runs.has(ticketId)) {
        runs.set(ticketId, { logs: [], state: null });
      }

      const run = runs.get(ticketId);

      const prevJson = run.state ? JSON.stringify(run.state) : '';

      // Tail log file
      const newLines = tailer.tail(logFile);
      for (const line of newLines) {
        const entry = parseLogLine(line);
        if (entry) run.logs.push(entry);
      }

      // Rebuild state (cheap — always rebuild to pick up artifact changes)
      const newState = buildRunState(ticketId, run.logs);
      const artifacts = loadArtifacts(ticketDir);
      run.state = mergeArtifacts(newState, artifacts);

      const pidAlive = checkPidAlive(ticketDir);
      run.state.isActive = classifyRunActivity(run.state, pidAlive);

      if (JSON.stringify(run.state) !== prevJson) {
        changed = true;
      }
    }

    // Remove runs no longer on disk
    for (const ticketId of runs.keys()) {
      if (!tickets.includes(ticketId)) {
        runs.delete(ticketId);
        changed = true;
      }
    }

    if (changed) {
      broadcast();
    }
  }

  function checkPidAlive(ticketDir) {
    try {
      const raw = fs.readFileSync(path.join(ticketDir, 'pid.json'), 'utf8');
      const { pid } = JSON.parse(raw);
      process.kill(pid, 0);
      return true;
    } catch {
      return false;
    }
  }

  function loadArtifacts(ticketDir) {
    const artifacts = {};
    const files = {
      prd: 'PRD.json',
      review: 'REVIEW.json',
      feedback: 'FEEDBACK.json',
      conflict: 'CONFLICT.json',
      secrets: 'SECRETS.json',
    };
    for (const [key, filename] of Object.entries(files)) {
      try {
        const content = fs.readFileSync(path.join(ticketDir, filename), 'utf8');
        artifacts[key] = JSON.parse(content);
      } catch {
        // file doesn't exist or invalid JSON — skip
      }
    }
    return artifacts;
  }

  function broadcast() {
    const allStates = getAllStates();
    for (const client of sseClients) {
      for (const state of allStates) {
        const event = { type: 'snapshot', ticketId: state.ticketId, data: state };
        try {
          client.write(`data: ${JSON.stringify(event)}\n\n`);
        } catch {
          sseClients.delete(client);
        }
      }
    }
  }

  function getAllStates() {
    return Array.from(runs.values())
      .map(r => r.state)
      .filter(Boolean);
  }

  // --- HTTP ---

  function loadIndexHtml() {
    try {
      return fs.readFileSync(path.join(__dirname, 'index.html'), 'utf8');
    } catch {
      return '<!DOCTYPE html><html><body><h1>Dashboard</h1><p>index.html not found</p></body></html>';
    }
  }

  const server = http.createServer((req, res) => {
    if (req.method === 'GET' && req.url === '/') {
      res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
      res.end(indexHtml);
      return;
    }

    if (req.method === 'GET' && req.url === '/api/runs') {
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify(getAllStates()));
      return;
    }

    if (req.method === 'GET' && req.url === '/events') {
      res.writeHead(200, {
        'Content-Type': 'text/event-stream',
        'Cache-Control': 'no-cache',
        'Connection': 'keep-alive',
      });
      res.write('\n'); // flush headers
      sseClients.add(res);
      req.on('close', () => sseClients.delete(res));
      return;
    }

    res.writeHead(404, { 'Content-Type': 'text/plain' });
    res.end('Not Found');
  });

  let pollTimer;
  server.on('listening', () => {
    poll(); // initial scan
    pollTimer = setInterval(poll, pollInterval);
  });

  server.on('close', () => {
    clearInterval(pollTimer);
    for (const client of sseClients) {
      try { client.end(); } catch {}
    }
    sseClients.clear();
  });

  return server;
}

// --- CLI entry point ---
if (require.main === module) {
  const port = parseInt(process.env.DASHBOARD_PORT, 10) || DEFAULT_PORT;
  const server = createDashboardServer();
  server.listen(port, '0.0.0.0', () => {
    console.log(`Dashboard running at http://localhost:${port}`);
  });
}

module.exports = { createDashboardServer };
