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

  /**
   * Read the last N complete lines from a file. Fresh read each call (no offset tracking).
   * @param {string} filePath
   * @param {number} maxLines
   * @returns {string[]}
   */
  tailLast(filePath, maxLines = 50) {
    let content;
    try {
      content = fs.readFileSync(filePath, 'utf8');
    } catch {
      return [];
    }
    if (!content) return [];
    const lines = content.split('\n').filter(l => l.length > 0);
    return lines.slice(-maxLines);
  }

  /**
   * Check if the file has grown since the last tail() call, without reading content.
   * @param {string} filePath
   * @returns {boolean}
   */
  hasNewData(filePath) {
    let stat;
    try {
      stat = fs.statSync(filePath);
    } catch {
      return false;
    }
    const offset = this.offsets.get(filePath) || 0;
    return stat.size > offset;
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
