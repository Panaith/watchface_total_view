#!/usr/bin/env node
// Starts an MCP server published on npm, pinned to an exact version:
//
//   node npm-mcp.js {package}@{version} [server args...]
//
// Committed on purpose: mcp-servers.json starts its npm servers through it, so
// every clone needs it. The version stays in mcp-servers.json;
// ai_tooling/scripts/setup-tools.ps1 installs the same versions into
// ai_tooling/mcp-packages (gitignored).
//
// Why not `npx -y {package}@{version}` directly: npx loads the whole npm CLI and,
// even for an exact version, asks the registry for the package metadata on every
// start. In the Claude desktop app that pushed the start of two servers past
// Claude Code's 30 s connect limit (documentation/mcp.md). The pinned
// copy is started with node instead; without it (setup ran with -SkipTools, or
// npm install failed) the server still starts through npx, as before.

const { spawn } = require('child_process');
const path = require('path');
const fs = require('fs');

const [spec, ...serverArgs] = process.argv.slice(2);
const at = spec ? spec.lastIndexOf('@') : -1;
if (at <= 0) {
  process.stderr.write(`npm-mcp: expected {package}@{version} as the first argument, got "${spec || ''}"\n`);
  process.exit(1);
}
const name = spec.slice(0, at);
const version = spec.slice(at + 1);

// The package's own bin: the one named like the package (a package can have
// several), otherwise its only one.
function pinnedBin() {
  const dir = path.join(__dirname, 'mcp-packages', 'node_modules', ...name.split('/'));
  let pkg;
  try {
    pkg = JSON.parse(fs.readFileSync(path.join(dir, 'package.json'), 'utf8'));
  } catch {
    return null;
  }
  if (pkg.version !== version) return null;
  let bin = pkg.bin;
  if (bin && typeof bin === 'object') {
    const keys = Object.keys(bin);
    bin = bin[name.split('/').pop()] || (keys.length === 1 ? bin[keys[0]] : null);
  }
  return typeof bin === 'string' ? path.join(dir, bin) : null;
}

const bin = pinnedBin();
let command;
let args;
if (bin) {
  command = process.execPath;
  args = [bin, ...serverArgs];
} else if (process.platform === 'win32') {
  // npx is a .cmd shim: Node 20.12+ refuses to spawn one without a shell.
  command = process.env.ComSpec || 'cmd.exe';
  args = ['/d', '/s', '/c', 'npx', '-y', spec, ...serverArgs];
} else {
  command = 'npx';
  args = ['-y', spec, ...serverArgs];
}

const child = spawn(command, args, { stdio: 'inherit' });

child.on('error', (err) => {
  process.stderr.write(`npm-mcp: ${name} failed to start (${err.message})\n`);
  process.exit(1);
});
child.on('exit', (code, signal) => process.exit(signal ? 1 : code ?? 0));
