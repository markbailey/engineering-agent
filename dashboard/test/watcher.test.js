const { describe, it, beforeEach, afterEach } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const { LogTailer, scanRunsDir } = require('../lib/watcher.js');

function tmpDir() {
  return fs.mkdtempSync(path.join(os.tmpdir(), 'dash-test-'));
}

describe('LogTailer', () => {
  let dir;
  let logFile;

  beforeEach(() => {
    dir = tmpDir();
    logFile = path.join(dir, 'run.log');
  });

  afterEach(() => {
    fs.rmSync(dir, { recursive: true, force: true });
  });

  it('reads new lines from beginning of new file', () => {
    const tailer = new LogTailer();
    fs.writeFileSync(logFile, '{"ts":"1","level":"INFO","cat":"startup","msg":"a"}\n');
    const lines = tailer.tail(logFile);
    assert.equal(lines.length, 1);
    assert.equal(lines[0], '{"ts":"1","level":"INFO","cat":"startup","msg":"a"}');
  });

  it('reads only new lines on subsequent calls', () => {
    const tailer = new LogTailer();
    fs.writeFileSync(logFile, 'line1\n');
    tailer.tail(logFile);

    fs.appendFileSync(logFile, 'line2\nline3\n');
    const lines = tailer.tail(logFile);
    assert.equal(lines.length, 2);
    assert.equal(lines[0], 'line2');
    assert.equal(lines[1], 'line3');
  });

  it('handles partial lines (no trailing newline)', () => {
    const tailer = new LogTailer();
    fs.writeFileSync(logFile, 'complete\npartial');
    const lines = tailer.tail(logFile);
    assert.equal(lines.length, 1);
    assert.equal(lines[0], 'complete');
  });

  it('completes partial line on next tail', () => {
    const tailer = new LogTailer();
    fs.writeFileSync(logFile, 'line1\npart');
    tailer.tail(logFile);

    fs.writeFileSync(logFile, 'line1\npartial_complete\n');
    const lines = tailer.tail(logFile);
    assert.equal(lines.length, 1);
    assert.equal(lines[0], 'partial_complete');
  });

  it('returns empty array for nonexistent file', () => {
    const tailer = new LogTailer();
    const lines = tailer.tail('/nonexistent/path/file.log');
    assert.deepEqual(lines, []);
  });

  it('returns empty array when no new data', () => {
    const tailer = new LogTailer();
    fs.writeFileSync(logFile, 'line1\n');
    tailer.tail(logFile);
    const lines = tailer.tail(logFile);
    assert.deepEqual(lines, []);
  });

  it('handles empty file', () => {
    const tailer = new LogTailer();
    fs.writeFileSync(logFile, '');
    const lines = tailer.tail(logFile);
    assert.deepEqual(lines, []);
  });
});

describe('scanRunsDir', () => {
  let dir;

  beforeEach(() => {
    dir = tmpDir();
  });

  afterEach(() => {
    fs.rmSync(dir, { recursive: true, force: true });
  });

  it('returns empty array for empty directory', () => {
    const tickets = scanRunsDir(dir);
    assert.deepEqual(tickets, []);
  });

  it('discovers ticket directories', () => {
    fs.mkdirSync(path.join(dir, 'WTP-123'));
    fs.mkdirSync(path.join(dir, 'SHRED-456'));
    fs.writeFileSync(path.join(dir, 'somefile.txt'), ''); // not a dir
    const tickets = scanRunsDir(dir);
    assert.equal(tickets.length, 2);
    assert.ok(tickets.includes('WTP-123'));
    assert.ok(tickets.includes('SHRED-456'));
  });

  it('returns empty for nonexistent directory', () => {
    const tickets = scanRunsDir('/nonexistent/path');
    assert.deepEqual(tickets, []);
  });
});
