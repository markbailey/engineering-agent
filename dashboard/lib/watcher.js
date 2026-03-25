/** File watcher utilities: log tailing with byte offsets, directory scanning. */

const fs = require('node:fs');
const path = require('node:path');

class LogTailer {
  constructor() {
    /** @type {Map<string, number>} file path → byte offset */
    this.offsets = new Map();
  }

  /**
   * Read new complete lines from a file since last tail call.
   * Tracks byte offset per file. Ignores partial lines (no trailing newline).
   * Returns array of line strings (without newline).
   */
  tail(filePath) {
    let stat;
    try {
      stat = fs.statSync(filePath);
    } catch {
      return [];
    }

    const offset = this.offsets.get(filePath) || 0;
    if (stat.size <= offset) return [];

    const buf = Buffer.alloc(stat.size - offset);
    const fd = fs.openSync(filePath, 'r');
    try {
      fs.readSync(fd, buf, 0, buf.length, offset);
    } finally {
      fs.closeSync(fd);
    }

    const chunk = buf.toString('utf8');
    const lastNewline = chunk.lastIndexOf('\n');
    if (lastNewline === -1) {
      // No complete line yet — don't advance offset
      return [];
    }

    // Advance offset to just past the last newline
    this.offsets.set(filePath, offset + lastNewline + 1);

    const complete = chunk.substring(0, lastNewline);
    return complete.split('\n').filter(l => l.length > 0);
  }
}

/**
 * Scan a runs directory and return ticket IDs (subdirectory names).
 */
function scanRunsDir(runsPath) {
  try {
    const entries = fs.readdirSync(runsPath, { withFileTypes: true });
    return entries.filter(e => e.isDirectory()).map(e => e.name);
  } catch {
    return [];
  }
}

module.exports = { LogTailer, scanRunsDir };
