const { describe, it, beforeEach, afterEach } = require('node:test');
const assert = require('node:assert/strict');
const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const { createDashboardServer } = require('../server.js');

function tmpDir() {
  return fs.mkdtempSync(path.join(os.tmpdir(), 'dash-int-'));
}

function fetch(url) {
  return new Promise((resolve, reject) => {
    http.get(url, (res) => {
      let body = '';
      res.on('data', (chunk) => body += chunk);
      res.on('end', () => resolve({ status: res.statusCode, headers: res.headers, body }));
      res.on('error', reject);
    }).on('error', reject);
  });
}

function waitForEvent(url, timeout = 5000) {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      req.destroy();
      reject(new Error('SSE timeout'));
    }, timeout);
    const req = http.get(url, (res) => {
      let buf = '';
      res.on('data', (chunk) => {
        buf += chunk;
        // Look for a complete SSE event (data: line followed by double newline)
        const match = buf.match(/data: (.+)\n\n/);
        if (match) {
          clearTimeout(timer);
          req.destroy();
          resolve(JSON.parse(match[1]));
        }
      });
      res.on('error', () => {}); // ignore destroy errors
    });
    req.on('error', (err) => {
      if (err.code !== 'ECONNRESET') {
        clearTimeout(timer);
        reject(err);
      }
    });
  });
}

describe('Dashboard Server', () => {
  let runsDir;
  let server;
  let baseUrl;

  beforeEach(async () => {
    runsDir = tmpDir();
    server = createDashboardServer({ runsDir, pollInterval: 200 });
    await new Promise((resolve) => {
      server.listen(0, '127.0.0.1', () => {
        const { port } = server.address();
        baseUrl = `http://127.0.0.1:${port}`;
        resolve();
      });
    });
  });

  afterEach(async () => {
    await new Promise((resolve) => server.close(resolve));
    fs.rmSync(runsDir, { recursive: true, force: true });
  });

  it('serves index.html at GET /', async () => {
    const res = await fetch(`${baseUrl}/`);
    assert.equal(res.status, 200);
    assert.ok(res.headers['content-type'].includes('text/html'));
    assert.ok(res.body.includes('<!DOCTYPE html>') || res.body.includes('<!doctype html>'));
  });

  it('returns 404 for unknown routes', async () => {
    const res = await fetch(`${baseUrl}/unknown`);
    assert.equal(res.status, 404);
  });

  it('returns empty runs at GET /api/runs initially', async () => {
    const res = await fetch(`${baseUrl}/api/runs`);
    assert.equal(res.status, 200);
    const data = JSON.parse(res.body);
    assert.ok(Array.isArray(data));
    assert.equal(data.length, 0);
  });

  it('returns run state after log file created', async () => {
    const ticketDir = path.join(runsDir, 'WTP-123');
    fs.mkdirSync(ticketDir);
    fs.writeFileSync(
      path.join(ticketDir, 'run.log'),
      '{"ts":"2026-03-21T14:30:00Z","level":"INFO","cat":"startup","msg":"Run started"}\n'
    );

    // Wait for poll cycle
    await new Promise(r => setTimeout(r, 400));

    const res = await fetch(`${baseUrl}/api/runs`);
    const data = JSON.parse(res.body);
    assert.equal(data.length, 1);
    assert.equal(data[0].ticketId, 'WTP-123');
    assert.equal(data[0].recentLogs.length, 1);
  });

  it('streams SSE events on log append', async () => {
    const ticketDir = path.join(runsDir, 'SSE-1');
    fs.mkdirSync(ticketDir);
    const logFile = path.join(ticketDir, 'run.log');
    fs.writeFileSync(logFile, '');

    // Start listening for SSE
    const eventPromise = waitForEvent(`${baseUrl}/events`);

    // Wait a tick then append log
    await new Promise(r => setTimeout(r, 100));
    fs.appendFileSync(logFile, '{"ts":"1","level":"INFO","cat":"startup","msg":"go"}\n');

    const event = await eventPromise;
    assert.equal(event.type, 'snapshot');
    assert.ok(event.ticketId);
  });

  it('GET /events has correct SSE headers', async () => {
    const res = await new Promise((resolve, reject) => {
      const req = http.get(`${baseUrl}/events`, (res) => {
        resolve({ status: res.statusCode, headers: res.headers });
        req.destroy();
      });
      req.on('error', () => {}); // ignore destroy
    });
    assert.equal(res.status, 200);
    assert.equal(res.headers['content-type'], 'text/event-stream');
    assert.equal(res.headers['cache-control'], 'no-cache');
    assert.equal(res.headers['connection'], 'keep-alive');
  });

  it('merges PRD.json artifacts into run state', async () => {
    const ticketDir = path.join(runsDir, 'PRD-1');
    fs.mkdirSync(ticketDir);
    fs.writeFileSync(
      path.join(ticketDir, 'run.log'),
      '{"ts":"1","level":"INFO","cat":"startup","msg":"started"}\n'
    );
    fs.writeFileSync(
      path.join(ticketDir, 'PRD.json'),
      JSON.stringify({
        title: 'Test PRD',
        overall_status: 'in_progress',
        tasks: [{ id: 't1', description: 'do thing', status: 'pending' }],
      })
    );

    await new Promise(r => setTimeout(r, 400));

    const res = await fetch(`${baseUrl}/api/runs`);
    const data = JSON.parse(res.body);
    assert.equal(data[0].title, 'Test PRD');
    assert.equal(data[0].tasks.length, 1);
    assert.equal(data[0].artifacts.hasPrd, true);
  });

  it('run with valid pid.json (current process PID) → isActive === active', async () => {
    const ticketDir = path.join(runsDir, 'PID-1');
    fs.mkdirSync(ticketDir);
    fs.writeFileSync(
      path.join(ticketDir, 'run.log'),
      '{"ts":"2026-03-21T14:30:00Z","level":"INFO","cat":"startup","msg":"Run started"}\n'
    );
    fs.writeFileSync(
      path.join(ticketDir, 'pid.json'),
      JSON.stringify({ pid: process.pid, startedAt: '2026-03-21T14:30:00Z' })
    );

    await new Promise(r => setTimeout(r, 400));

    const res = await fetch(`${baseUrl}/api/runs`);
    const data = JSON.parse(res.body);
    assert.equal(data[0].isActive, 'active');
  });

  it('run with no pid.json → isActive === inactive', async () => {
    const ticketDir = path.join(runsDir, 'PID-2');
    fs.mkdirSync(ticketDir);
    fs.writeFileSync(
      path.join(ticketDir, 'run.log'),
      '{"ts":"2026-03-21T14:30:00Z","level":"INFO","cat":"startup","msg":"Run started"}\n'
    );

    await new Promise(r => setTimeout(r, 400));

    const res = await fetch(`${baseUrl}/api/runs`);
    const data = JSON.parse(res.body);
    assert.equal(data[0].isActive, 'inactive');
  });

  it('run with stale pid.json (dead PID) → isActive === inactive', async () => {
    const ticketDir = path.join(runsDir, 'PID-3');
    fs.mkdirSync(ticketDir);
    fs.writeFileSync(
      path.join(ticketDir, 'run.log'),
      '{"ts":"2026-03-21T14:30:00Z","level":"INFO","cat":"startup","msg":"Run started"}\n'
    );
    fs.writeFileSync(
      path.join(ticketDir, 'pid.json'),
      JSON.stringify({ pid: 99999999, startedAt: '2026-03-21T14:30:00Z' })
    );

    await new Promise(r => setTimeout(r, 400));

    const res = await fetch(`${baseUrl}/api/runs`);
    const data = JSON.parse(res.body);
    assert.equal(data[0].isActive, 'inactive');
  });
});
