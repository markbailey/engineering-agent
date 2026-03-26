const { describe, it, beforeEach, afterEach } = require('node:test');
const assert = require('node:assert/strict');
const { execSync } = require('node:child_process');
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');

const SCRIPT = path.resolve(__dirname, '../../scripts/pid.sh');

function run(args, env = {}) {
  return execSync(`bash ${SCRIPT} ${args}`, {
    encoding: 'utf8',
    env: { ...process.env, ...env },
    stderr: 'pipe',
  });
}

describe('pid.sh', () => {
  let tmpDir;
  let runsDir;
  const ticketId = 'TEST-1';

  beforeEach(() => {
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'pid-test-'));
    // Create a fake agent root with runs/ and scripts/
    runsDir = path.join(tmpDir, 'runs');
    fs.mkdirSync(runsDir, { recursive: true });
    // Symlink scripts dir so AGENT_ROOT resolves to tmpDir
    fs.symlinkSync(path.dirname(SCRIPT), path.join(tmpDir, 'scripts'));
  });

  afterEach(() => {
    fs.rmSync(tmpDir, { recursive: true, force: true });
  });

  function runPid(args) {
    const script = path.join(tmpDir, 'scripts', 'pid.sh');
    return execSync(`bash ${script} ${args}`, {
      encoding: 'utf8',
      stderr: 'pipe',
    });
  }

  describe('write', () => {
    it('creates pid.json with correct format', () => {
      runPid(`write ${ticketId}`);
      const pidFile = path.join(runsDir, ticketId, 'pid.json');
      assert.ok(fs.existsSync(pidFile), 'pid.json should exist');
      const data = JSON.parse(fs.readFileSync(pidFile, 'utf8'));
      assert.equal(typeof data.pid, 'number', 'pid should be a number');
      assert.ok(data.pid > 0, 'pid should be positive');
      assert.equal(typeof data.startedAt, 'string', 'startedAt should be a string');
      // Validate ISO 8601 format
      assert.ok(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/.test(data.startedAt),
        'startedAt should be ISO 8601');
    });

    it('writes explicit PID when passed as third argument', () => {
      const targetPid = process.pid;
      runPid(`write ${ticketId} ${targetPid}`);
      const pidFile = path.join(runsDir, ticketId, 'pid.json');
      const data = JSON.parse(fs.readFileSync(pidFile, 'utf8'));
      assert.equal(data.pid, targetPid, 'pid should match the explicit argument');
    });
  });

  describe('remove', () => {
    it('deletes pid.json', () => {
      runPid(`write ${ticketId}`);
      const pidFile = path.join(runsDir, ticketId, 'pid.json');
      assert.ok(fs.existsSync(pidFile), 'pid.json should exist before remove');
      runPid(`remove ${ticketId}`);
      assert.ok(!fs.existsSync(pidFile), 'pid.json should not exist after remove');
    });

    it('succeeds even if pid.json does not exist', () => {
      // Should not throw
      runPid(`remove ${ticketId}`);
    });
  });

  describe('check', () => {
    it('returns alive=true for current process PID', () => {
      // Write a pid.json with our own PID (which is alive)
      const ticketDir = path.join(runsDir, ticketId);
      fs.mkdirSync(ticketDir, { recursive: true });
      fs.writeFileSync(path.join(ticketDir, 'pid.json'), JSON.stringify({
        pid: process.pid,
        startedAt: '2026-03-21T14:30:00Z',
      }));
      const output = runPid(`check ${ticketId}`);
      const result = JSON.parse(output);
      assert.equal(result.alive, true);
      assert.equal(result.pid, process.pid);
      assert.equal(result.startedAt, '2026-03-21T14:30:00Z');
    });

    it('returns alive=false for dead PID', () => {
      const ticketDir = path.join(runsDir, ticketId);
      fs.mkdirSync(ticketDir, { recursive: true });
      fs.writeFileSync(path.join(ticketDir, 'pid.json'), JSON.stringify({
        pid: 99999999,
        startedAt: '2026-03-21T14:30:00Z',
      }));
      const output = runPid(`check ${ticketId}`);
      const result = JSON.parse(output);
      assert.equal(result.alive, false);
      assert.equal(result.pid, 99999999);
      assert.equal(result.startedAt, '2026-03-21T14:30:00Z');
    });

    it('returns alive=false when no pid.json', () => {
      const output = runPid(`check ${ticketId}`);
      const result = JSON.parse(output);
      assert.equal(result.alive, false);
      assert.equal(result.pid, undefined);
      assert.equal(result.startedAt, undefined);
    });
  });
});
