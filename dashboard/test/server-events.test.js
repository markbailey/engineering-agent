const { describe, it, afterEach } = require('node:test');
const assert = require('node:assert/strict');
const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const { createDashboardServer } = require('../server.js');

function tmpDir() {
  return fs.mkdtempSync(path.join(os.tmpdir(), 'dash-evt-'));
}

describe('server event handlers (no monkey-patching)', () => {
  let server;
  let runsDir;

  afterEach((_, done) => {
    if (server && server.listening) {
      server.close(done);
    } else {
      done();
    }
  });

  it('server.listen is the original http.Server method, not overridden', () => {
    runsDir = tmpDir();
    server = createDashboardServer({ runsDir, pollInterval: 60000 });
    // If monkey-patched, server.listen would be a plain function, not the native method
    assert.strictEqual(server.listen, http.Server.prototype.listen,
      'server.listen should be the original http.Server.prototype.listen');
  });

  it('server.close is the original http.Server method, not overridden', () => {
    runsDir = tmpDir();
    server = createDashboardServer({ runsDir, pollInterval: 60000 });
    assert.strictEqual(server.close, http.Server.prototype.close,
      'server.close should be the original http.Server.prototype.close');
  });

  it('has listening and close event handlers registered', () => {
    runsDir = tmpDir();
    server = createDashboardServer({ runsDir, pollInterval: 60000 });
    assert.ok(server.listenerCount('listening') > 0,
      'should have at least one listening event handler');
    assert.ok(server.listenerCount('close') > 0,
      'should have at least one close event handler');
  });

  it('poll runs after server starts listening', (t, done) => {
    runsDir = tmpDir();
    // Create a ticket dir with a log file so poll has something to find
    const ticketDir = path.join(runsDir, 'TEST-1');
    fs.mkdirSync(ticketDir, { recursive: true });
    fs.writeFileSync(path.join(ticketDir, 'run.log'),
      '{"ts":"2026-01-01T00:00:00Z","level":"INFO","cat":"startup","msg":"started"}\n');

    server = createDashboardServer({ runsDir, pollInterval: 60000 });
    server.listen(0, '127.0.0.1', () => {
      // After listening, poll should have run; verify via /api/runs
      const port = server.address().port;
      http.get(`http://127.0.0.1:${port}/api/runs`, (res) => {
        let body = '';
        res.on('data', (c) => body += c);
        res.on('end', () => {
          const data = JSON.parse(body);
          assert.ok(Array.isArray(data), 'response should be array');
          assert.ok(data.length > 0, 'poll should have discovered TEST-1');
          assert.strictEqual(data[0].ticketId, 'TEST-1');
          done();
        });
      });
    });
  });
});
