# MCP servers for this repository

MCP servers are declared once, agent-neutrally, in [mcp-servers.json](../mcp-servers.json).
`ai_tooling/setup.ps1` generates the config your agent actually reads. The file, key and HTTP field
of each agent are in the `mcp` entry of each agent in [agents.json](../manifest/agents.json); at the
time of writing:

| Agent | File | Notes |
|-------|------|-------|
| Claude Code | `.mcp.json` | key `mcpServers`, HTTP uses `url` + `type` |
| Antigravity | `.agents/mcp_config.json` | key `mcpServers`, HTTP uses `serverUrl` |
| GitHub Copilot | `.vscode/mcp.json` | key `servers`, HTTP uses `url` + `type` |
| Cursor | `.cursor/mcp.json` | key `mcpServers`, HTTP uses `url` + `type` |

All four are gitignored. Edit `mcp-servers.json` and re-run `setup.ps1`; never edit the generated
files.

A run of `setup.ps1` without `-Agent` regenerates **every layout set up in this clone**, so a
config written by an earlier `-Agent all` run cannot quietly drift out of date; only the first run
detects the installed agents. If you want one gone, run
`.\ai_tooling\setup.ps1 -Remove {agent}`: it removes what setup wrote for that agent, its MCP
config included, and it does not come back ([overview.md](overview.md)).
`verify-agent-setup.ps1` compares the contents of each layout that exists against
`mcp-servers.json` and fails on a missing server or a changed transport.

## The neutral file

Each entry of `servers` is either

- a stdio server: `"transport": "stdio"`, `"command"`, `"args"`, or
- an HTTP server: `"transport": "http"`, `"url"`.

Optional keys: `description`, `skipAgents`, `skipReason`, `envArgs`, and any `$...` key as a
comment (setup ignores them; use them to record why, and what the server needs).

- **`${REPO_ROOT}`** in a value is replaced with this clone's absolute path at generation time.
  That sidesteps the fact that path variables differ per tool too (`${CLAUDE_PROJECT_DIR}` vs
  `${workspaceFolder}` vs nothing in Cursor). It is safe because every generated file is
  gitignored; only `mcp-servers.json`, which keeps the placeholder, is committed.
- **`skipAgents`** lists agent keys from `agents.json` that already get the server another way
  (an editor extension registers it). Adding it again would run a second, duplicate process. Give
  the reason in `skipReason`.
- **`envArgs`** maps an environment variable to arguments that setup appends to the server's
  `args` when the variable is set (Process or User scope); `${VALUE}` is replaced with its value.
  It is a per-developer opt-in: nothing changes for anyone who has not set the variable. After
  setting one, re-run `setup.ps1` and restart the agent so the server starts with the new
  argument.

Paths in the generated files are absolute, so a generated file works from whatever folder the
agent launches the server in, but a server that must run inside an app folder needs a launcher
that changes into it: `.mcp.json` and the other files have no `cwd` field ([Known servers](#known-servers)
shows two).

## First run

Claude Code asks you to approve project MCP servers the first time you open the repository.
Approve them all. Run `/mcp` to check the status at any time.

The first time the agent uses an **azure-devops** tool, a browser window opens and you sign in
with **your own** account against the Azure DevOps organisation. The token is cached by MSAL on
your machine; nothing is stored in the repository: no PAT, no token, no secret. Every action the
agent takes on Azure DevOps runs as you, with exactly your permissions.

### Optional: sign in through the Azure CLI instead

With the default browser sign-in, the token expires after about an hour and whenever the server
restarts. The next azure-devops call then waits on a browser window that often opens behind
everything else, so the agent seems stuck until you finish signing in. To reuse the Azure CLI's
sign-in instead, which renews itself, opt in per developer (this needs the `envArgs` entry of the
`azure-devops` server in [Known servers](#known-servers)):

```powershell
winget install Microsoft.AzureCLI
az login
[Environment]::SetEnvironmentVariable('AZDO_MCP_AUTH', 'azcli', 'User')
.\ai_tooling\setup.ps1
```

`setup.ps1` then adds `--authentication azcli` to your own generated MCP config. Restart the agent
afterwards. To go back, remove the variable and re-run `setup.ps1`. Changing an environment
variable of the user is the developer's own step: an agent offers it and waits for approval
(`PERMISSIONS.md`, section 5).

### Azure CLI for PR reviewers and votes

The azure-devops MCP server cannot mark a PR reviewer as required, so the work item skill adds
reviewers with `az repos pr reviewer add --required true`, and the PR review skill can vote with
`az repos pr set-vote`. Both need the Azure CLI, signed in, with its azure-devops extension (once
per developer, independent of the MCP sign-in):

```powershell
winget install Microsoft.AzureCLI
az login
az extension add --name azure-devops
```

Both are Azure DevOps writes: `PERMISSIONS.md`, section 1 applies.

If a server shows as failed in `/mcp`, the cause is almost always a missing local toolchain; see
the prerequisites per server in [Known servers](#known-servers). If an npm server fails with
`CONNECT_TIMEOUT`, see [Connect timeouts](#connect-timeouts).

### Connect timeouts

Claude Code gives each MCP server 30 seconds to connect (`MCP_TIMEOUT`, in milliseconds). Servers
published on npm are therefore started through [npm-mcp.js](../npm-mcp.js), which takes the pinned
`{package}@{version}` as its first argument (so the version stays in `mcp-servers.json`) and starts
a pinned copy with `node`. `setup.ps1` installs those copies, in the versions `mcp-servers.json`
pins, into `ai_tooling/mcp-packages/` (gitignored), through `scripts/setup-tools.ps1`. In a new
Claude desktop session such servers connected within 5 seconds.

Without the copy (setup ran with `-SkipTools`, or `npm install` failed; `verify-agent-setup.ps1`
warns), `npm-mcp.js` falls back to `npx`. `npx` loads the npm CLI and asks the npm registry for the
package metadata at every start, even for an exact version. In the Claude desktop app two servers
then took 35-52 seconds to connect at session start, and a new clone failed with
`CONNECT_TIMEOUT`. Run `.\ai_tooling\scripts\setup-tools.ps1` to install the copy. A launcher
that falls back to `npx` starts it through `cmd` on Windows: `npx` is a `.cmd` shim there, and
Node 20.12+ refuses to spawn one without a shell.

If a server still times out, give it more time in your own, gitignored
`.claude/settings.local.json`, then start a new session:

```json
{ "env": { "MCP_TIMEOUT": "60000" } }
```

Merge the `env` key into the file if it already exists. Each server's connect time is in Claude
Code's log, `%LOCALAPPDATA%\claude-cli-nodejs\Cache\{project}\mcp-logs-{server}\`
("Successfully connected ... in {ms}ms").

### Why not the hosted azure-devops server?

Microsoft hosts one at `https://mcp.dev.azure.com/{organisation}` and recommends it in general, but it
authenticates through Microsoft Entra, which does not support the dynamic OAuth client
registration Claude Code and Cursor rely on. [Microsoft's own
guidance](https://learn.microsoft.com/azure/devops/mcp-server/mcp-server-overview) is to use the
local server for those clients.

The hosted endpoint becomes an option once someone registers an Entra app for the tenant: redirect
URI `http://localhost:3118/callback`, public client flows enabled, delegated permissions on the
Azure DevOps application with admin consent. Every developer then passes its client id:

```powershell
claude mcp add --transport http azure-devops https://mcp.dev.azure.com/{organisation} `
  --client-id {client-id} --callback-port 3118
```

If that ever happens, switch the entry in `mcp-servers.json` to `"transport": "http"` and drop
the stdio fields. Until then, stdio is the one that actually runs.

## Antigravity users

`.mcp.json` is Claude Code only. For Antigravity, `setup.ps1 -Agent gemini` writes the project's
servers (those not in their `skipAgents`) to `.agents/mcp_config.json`, the workspace file
Antigravity reads in the opened folder, so each clone has its own. Open the repository root. The
IDE lists the workspace's servers under its workspace settings and starts them a little after the
global ones.

Antigravity also reads its global file `~/.gemini/config/mcp_config.json`, and on a name clash the
global server wins (tested 2026-10-20 with Antigravity 2.24.0 and Antigravity IDE 2.5.5). Setup
never writes the project's servers there. `verify-agent-setup.ps1` (also `-Quick`) names a server
in the global file that is named like a project one; one that has comments it can read only in
PowerShell 7. Keep your own servers in the global file under other names.

The global file must stay a JSON object: while it is empty, Antigravity loads no MCP server at
all, not even the workspace file's, and it recreates the file empty when it is missing (tested
2026-10-20 with Antigravity 2.24.0). So setup writes `{ "mcpServers": {} }` into a missing or
empty global file and never deletes it; a file with comments, or one that is not valid JSON, it
leaves alone. `verify-agent-setup.ps1` (also `-Quick`) fails while it is missing, empty or not a
JSON object; the last you fix by hand. A bare `{}` is enough too (tested 2026-10-20 with
Antigravity 2.24.0 and Antigravity IDE 2.5.5).

Antigravity IDE 2.5.5 does not load an HTTP server declared with `httpUrl`: the field is
`serverUrl` (setup writes it). Only without setup, copy the entries into
`.agents/mcp_config.json` by hand (and keep the global file a JSON object), with `serverUrl`
instead of `url` for an HTTP server. An editor extension may register a server in Antigravity on
its own (the Dart and Nx Console extensions do): do not add those by hand and put them in
`skipAgents` with `gemini`, since a manual entry would run a second, duplicate server.

## Known servers

A catalogue of servers the tooling has been used with. `ai_tooling/mcp-servers.json` starts with an
empty `servers` object; the setup agent adds an entry from here for each server the project's
apps need, with the paths, versions and app folders filled in, and adds the matching check to
`ai_tooling/scripts/verify-project.ps1`. Each entry goes into `servers`. In the checks below,
`Check '{label}' {condition} '{what to do}'` and `$Servers` are what `verify-project.ps1`
provides (see its header).

Servers published on npm are pinned to an exact version and started through `npm-mcp.js`, so
raise a version deliberately: a server update changes the tools every agent sees, and
`setup-tools.ps1` installs the version `mcp-servers.json` names.

### GitHub projects

A project on GitHub needs no MCP server for its workflow skills: they work through the GitHub CLI
`gh`, which every developer installs once and signs in with `gh auth login` (check:
`gh auth status`). Its sign-in is per developer and outside the repository, so nothing about it is
committed. GitHub also publishes its own MCP server (`github/github-mcp-server`, hosted at
`https://api.githubcopilot.com/mcp/`); it authenticates per agent (OAuth, or a personal access
token sent as a header), which `mcp-servers.json` has no field for, so declare it only after
trying it with each agent the project uses, and never put a token into a committed file
(`PERMISSIONS.md`, section 6). A check worth adding to `verify-project.ps1` for a GitHub project
(not with `-SourceOnly`):

```powershell
if (-not $SourceOnly) {
    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { Write-Host "  WARN  gh is not on PATH - the workflow skills need the GitHub CLI" }
    else { gh auth status *> $null; if ($LASTEXITCODE -ne 0) { Write-Host "  WARN  gh is not signed in - run 'gh auth login'" } }
}
```

### azure-devops

**Gives:** work items (read, create, edit, delete), pull requests, branches, repositories, wiki,
test plans, pipelines and search, about 40 tools. Local stdio server (the reasoning is in
[Why not the hosted azure-devops server?](#why-not-the-hosted-azure-devops-server)).

**Needs:** Node 20+; a browser sign-in with your own account, or `az login` with the
`AZDO_MCP_AUTH` opt-in ([Optional: sign in through the Azure CLI instead](#optional-sign-in-through-the-azure-cli-instead)).
Every call needs `project: "{project}"`, as the root `AGENTS.md` says.

```json
"azure-devops": {
  "description": "Work items, pull requests, branches, repos, wiki, pipelines, search. Browser sign-in with your own account.",
  "$requires": "Node 20+. npm-mcp.js starts the copy setup-tools.ps1 pins in ai_tooling/mcp-packages, or falls back to npx.",
  "transport": "stdio",
  "command": "node",
  "args": ["${REPO_ROOT}/ai_tooling/npm-mcp.js", "@azure-devops/mcp@2.10.0", "{organisation}"],
  "$envArgs": [
    "Per-developer opt-ins, appended by setup.ps1 when the environment variable",
    "is set (Process or User scope); ${VALUE} is replaced with its value.",
    "AZDO_MCP_AUTH=azcli reuses your 'az login' session instead of a browser",
    "sign-in whose token expires hourly. Unset = the default browser sign-in."
  ],
  "envArgs": { "AZDO_MCP_AUTH": ["--authentication", "${VALUE}"] }
}
```

**Check for `verify-project.ps1`:** the server stays declared and pinned, and starts through
`npm-mcp.js` with the organisation as its last argument.

```powershell
Check 'azure-devops MCP server is declared and pinned' (
    $Servers.'azure-devops' -and ($Servers.'azure-devops'.args -join ' ') -match '@azure-devops/mcp@\d+\.\d+\.\d+ {organisation}') `
    'keep azure-devops in ai_tooling/mcp-servers.json, pinned to an exact version, with the organisation after it'
```

`verify-agent-setup.ps1` does not check the Azure CLI sign-in. For a project that uses this server
and the `AZDO_MCP_AUTH` opt-in, add this to `verify-project.ps1` (informational warnings, skipped
in a source-only run):

```powershell
if (-not $SourceOnly) {
    $adoAuth = [Environment]::GetEnvironmentVariable('AZDO_MCP_AUTH', 'Process')
    if (-not $adoAuth) { $adoAuth = [Environment]::GetEnvironmentVariable('AZDO_MCP_AUTH', 'User') }
    if ($adoAuth -eq 'azcli') {
        if (-not (Get-Command az -ErrorAction SilentlyContinue)) { Write-Host "  WARN  AZDO_MCP_AUTH=azcli but the Azure CLI is not on PATH" }
        else {
            az account show --only-show-errors *> $null
            if ($LASTEXITCODE -eq 0) { Write-Host "  OK    azure-devops uses the Azure CLI sign-in" }
            else { Write-Host "  WARN  AZDO_MCP_AUTH=azcli but not signed in - run 'az login'" }
        }
        $claudeMcp = Join-Path $RepoRoot '.mcp.json'
        if ((Test-Path $claudeMcp) -and -not ((Get-Content $claudeMcp -Raw) -match '"azcli"')) {
            Write-Host "  WARN  .mcp.json does not pass --authentication azcli yet - re-run setup.ps1"
        }
    }
}
```

### chrome-devtools

**Gives:** Google's Chrome DevTools server: the agent drives a Chrome window against an app served
locally (navigate, click, fill, screenshots, console messages with source-mapped stack traces,
network requests, scripts in the page, performance traces).

**Needs:** Node 20.19+ and Google Chrome.

- **Its own Chrome window.** The server starts Chrome the first time a tool needs it, with a
  separate profile in `~/.cache/chrome-devtools-mcp/chrome-profile`. Your normal Chrome profile is
  not touched. Logins in that window persist between sessions.
- **Your own Chrome instead (opt-in).** Start Chrome with remote debugging and its own profile
  folder (Chrome ignores the port on the default profile), then point the server at it and
  re-run `setup.ps1`:

  ```powershell
  & "$env:ProgramFiles\Google\Chrome\Application\chrome.exe" --remote-debugging-port=9222 --user-data-dir="$env:LOCALAPPDATA\{project}\chrome-debug"
  [Environment]::SetEnvironmentVariable('CHROME_DEVTOOLS_BROWSER_URL', 'http://127.0.0.1:9222', 'User')
  .\ai_tooling\setup.ps1
  ```

  Remove the variable and re-run `setup.ps1` to go back.
- **Nothing goes to Google by default.** The server sends usage statistics to Google, and the URLs
  of performance traces to the CrUX API, unless told not to. The entry below passes
  `--no-usage-statistics` and `--no-performance-crux`; keep both.
- **The agent sees everything in that window.** Use desanitised data, not customer data
  (`PERMISSIONS.md`, section 2).
- **Flutter web draws on a canvas.** There are no page elements to click, so without help the
  agent can only click by screen position. Every Flutter web page has a hidden "Enable
  accessibility" button (the `flt-semantics-placeholder` element). After each page load, the agent
  clicks it, or runs `document.querySelector('flt-semantics-placeholder')?.click()` in the page;
  the agent then finds widgets by their text and labels. Widgets without a label can still only be
  clicked by position. Use the `flutter-dart` server alongside it.

```json
"chrome-devtools": {
  "description": "Drive and inspect a Chrome window: navigate, click, fill, screenshots, console, network, performance traces. For the locally served web apps.",
  "$requires": "Node 20.19+ and Google Chrome. npm-mcp.js starts the copy setup-tools.ps1 pins in ai_tooling/mcp-packages, or falls back to npx.",
  "$privacy": [
    "--no-usage-statistics: the server reports tool usage to Google by default.",
    "--no-performance-crux: performance traces would otherwise send the traced",
    "URLs to Google's CrUX API. verify-project.ps1 checks that both stay."
  ],
  "transport": "stdio",
  "command": "node",
  "args": ["${REPO_ROOT}/ai_tooling/npm-mcp.js", "chrome-devtools-mcp@1.10.1", "--no-usage-statistics", "--no-performance-crux"],
  "$envArgs": [
    "Per-developer opt-in: CHROME_DEVTOOLS_BROWSER_URL=http://127.0.0.1:9222 attaches",
    "to a Chrome you started with --remote-debugging-port=9222 instead of opening",
    "the server's own window. Unset = the server's own Chrome and profile."
  ],
  "envArgs": { "CHROME_DEVTOOLS_BROWSER_URL": ["--browser-url", "${VALUE}"] }
}
```

**Check for `verify-project.ps1`:** both privacy flags stay.

```powershell
$cdt = if ($Servers.'chrome-devtools') { $Servers.'chrome-devtools'.args -join ' ' } else { '' }
Check 'chrome-devtools passes --no-usage-statistics and --no-performance-crux' (
    $cdt -match '--no-usage-statistics' -and $cdt -match '--no-performance-crux') `
    'put both flags back into the chrome-devtools args in ai_tooling/mcp-servers.json'
```

### devextreme

**Gives:** search in the DevExtreme documentation, pinned to one version. A hosted HTTP endpoint;
no authentication, nothing to install.

The `v` query parameter pins the documentation to the DevExtreme `major.minor` the app depends on
(the upstream default is the newest release, which may be ahead of the app). Set it from the app's
`package.json` and change it with the dependency.

```json
"devextreme": {
  "description": "DevExtreme documentation search, pinned to the version the web app depends on.",
  "transport": "http",
  "url": "https://api.devexpress.com/mcp/docs?v={major.minor}"
}
```

**Check for `verify-project.ps1`:** the URL's version equals the app's DevExtreme `major.minor`
(`{app folder}` is the app that uses DevExtreme).

```powershell
$dxPkg = Get-Content (Join-Path $RepoRoot '{app folder}/package.json') -Raw | ConvertFrom-Json
$dxVersion = ($dxPkg.dependencies.'devextreme' -replace '^[^\d]*', '') -split '\.' | Select-Object -First 2
$dxPinned = if ($Servers.devextreme) { $Servers.devextreme.url } else { '' }
Check 'devextreme docs URL is pinned to the app version' ($dxPinned -match "[?&]v=$($dxVersion -join '\.')$") `
    'set ?v={major.minor} in the devextreme url of ai_tooling/mcp-servers.json to the DevExtreme version of the app'
```

### angular

**Gives:** the Angular CLI's own MCP server (`ng mcp`): best practices for the workspace's
Angular version, documentation search, examples, and the project list.

**Needs:** the workspace's dependencies installed (`npm install` in the app folder), so that
`node_modules/@angular/cli` exists.

It is started by a small node launcher, not directly: `ng mcp` finds `angular.json` from the
working directory, MCP clients launch servers from the repository root, and the config has no
`cwd` field. The launcher changes into the app folder, and it runs the workspace's own CLI, never
`npx @angular/cli`, so the server always matches the version the workspace is pinned to. Node is
used rather than a `.cmd` so it works on macOS and Linux too.

The launcher is project code: save it as `ai_tooling/angular-mcp.js` (committed, because the
entry references it), replace `{app folder}` with the folder of the Angular app, and have the
project's own setup tools or the app's `Prepare` command run `npm install` there.

```js
#!/usr/bin/env node
// Launches the Angular CLI MCP server against the {app folder} workspace.
//
// Committed on purpose: the MCP config references it, so every clone needs it.
//
// Why a launcher at all: `ng mcp` discovers angular.json from the working
// directory, MCP clients launch servers from the repository root, and the
// Angular workspace is one level down. The config has no "cwd" field, so the
// chdir happens here.
//
// It runs the workspace's own CLI, never `npx @angular/cli`, so the server
// always matches the version the workspace is pinned to.

const { spawn } = require('child_process');
const path = require('path');
const fs = require('fs');

const workspace = path.join(__dirname, '..', '{app folder}');
const cli = path.join(workspace, 'node_modules', '@angular', 'cli', 'bin', 'ng.js');

if (!fs.existsSync(cli)) {
  process.stderr.write(
    `angular-mcp: ${path.relative(process.cwd(), cli)} not found. ` +
      'Run "npm install" in {app folder} first.\n'
  );
  process.exit(1);
}

const child = spawn(process.execPath, [cli, 'mcp', ...process.argv.slice(2)], {
  cwd: workspace,
  stdio: 'inherit',
});

child.on('exit', (code, signal) => process.exit(signal ? 1 : code ?? 0));
```

```json
"angular": {
  "description": "Angular best practices, docs, examples and project list for the web app.",
  "transport": "stdio",
  "command": "node",
  "args": ["${REPO_ROOT}/ai_tooling/angular-mcp.js"]
}
```

**Check for `verify-project.ps1`:** the launcher exists and the app's Angular CLI is installed (a
warning, not a failure: it depends on `npm install`, and is skipped in a source-only CI run).

```powershell
Check 'angular-mcp.js launcher exists' (Test-Path (Join-Path $AiDir 'angular-mcp.js')) 'add ai_tooling/angular-mcp.js (documentation/mcp.md, "angular")'
if (-not $SourceOnly -and -not (Test-Path (Join-Path $RepoRoot '{app folder}/node_modules/@angular/cli/bin/ng.js'))) {
    Write-Host "  WARN  the angular MCP server needs npm install in {app folder}"
}
```

### nx

**Gives:** Nx project graph, project details, generators, documentation, and (with `--minimal
false`) the workspace analysis tools.

**Needs:** Node. In an editor with Nx Console (Antigravity), the extension provides the server, so
the entry is skipped for `gemini`: its copy is editor-connected, and a second one would be a
duplicate.

It is started by a launcher that handles two things a plain config entry cannot: `--minimal`
defaults to true in `nx-mcp`, which hides everything except `nx_docs`, so it is forced to false;
and a locally installed copy is preferred over `npx`, so the npm fetch at every start is skipped.
`nx mcp` itself is only a shim that spawns `npx -y nx-mcp@latest`, so it is deliberately not
used: it would float to whatever npm publishes next. The launcher is project code: save it as
`ai_tooling/nx-mcp.js` (committed) and replace `{app folder}` with the folder of the Nx workspace.
Its `NX_MCP_VERSION` line is the one place the version is pinned.

To install the pinned copy, add a section to `ai_tooling/scripts/setup-tools.ps1` that reads
`NX_MCP_VERSION` from `nx-mcp.js` and runs `npm install --prefix ai_tooling/nx-mcp nx-mcp@{version}`
(`ai_tooling/nx-mcp/` is generated and gitignored: add it to `.gitignore`). Without the copy the
launcher falls back to `npx` with the same version.

```js
#!/usr/bin/env node
// Launches the Nx MCP server against the {app folder} workspace.
//
// Committed on purpose: the MCP config references it, so every clone needs it.
//
// Two things this handles that a plain config entry cannot:
//
// 1. `--minimal` defaults to TRUE in nx-mcp, which hides everything except
//    nx_docs. It is forced to false here so the workspace analysis tools
//    (nx_workspace, nx_project_details, nx_generators, ...) are available.
// 2. A locally installed copy is preferred over `npx`: scripts/setup-tools.ps1
//    installs NX_MCP_VERSION into ai_tooling/nx-mcp. Everyone else falls back
//    to npx with the same pinned version.
//
// `nx mcp` itself is only a shim that spawns `npx -y nx-mcp@latest`, so it is
// deliberately not used - it would float to whatever npm publishes next.

const { spawn } = require('child_process');
const path = require('path');
const fs = require('fs');

// The one place the version is pinned: setup-tools.ps1 reads it from this line.
const NX_MCP_VERSION = '0.25.0';

const workspace = path.join(__dirname, '..', '{app folder}');
const serverArgs = [workspace, '--minimal', 'false', '--disableTelemetry', ...process.argv.slice(2)];

const pinned = path.join(__dirname, 'nx-mcp', 'node_modules', 'nx-mcp', 'main.js');

let command;
let args;
if (fs.existsSync(pinned)) {
  command = process.execPath;
  args = [pinned, ...serverArgs];
} else if (process.platform === 'win32') {
  // npx is a .cmd shim: Node 20.12+ refuses to spawn one without a shell.
  command = process.env.ComSpec || 'cmd.exe';
  args = ['/d', '/s', '/c', 'npx', '-y', `nx-mcp@${NX_MCP_VERSION}`, ...serverArgs];
} else {
  command = 'npx';
  args = ['-y', `nx-mcp@${NX_MCP_VERSION}`, ...serverArgs];
}

const child = spawn(command, args, { stdio: 'inherit' });

child.on('error', (err) => {
  process.stderr.write(`nx-mcp: failed to start (${err.message})\n`);
  process.exit(1);
});
child.on('exit', (code, signal) => process.exit(signal ? 1 : code ?? 0));
```

```json
"nx": {
  "description": "Nx project graph, project details, generators and docs.",
  "transport": "stdio",
  "command": "node",
  "args": ["${REPO_ROOT}/ai_tooling/nx-mcp.js"],
  "skipAgents": ["gemini"],
  "skipReason": "Nx Console registers the nx-mcp provider in Antigravity, and that copy is editor-connected."
}
```

**Check for `verify-project.ps1`:** the launcher exists and keeps `--minimal false` and an exact
pin.

```powershell
$nxLauncher = Join-Path $AiDir 'nx-mcp.js'
Check 'nx-mcp.js launcher exists' (Test-Path $nxLauncher) 'add ai_tooling/nx-mcp.js (documentation/mcp.md, "nx")'
if (Test-Path $nxLauncher) {
    $nxText = Get-Content $nxLauncher -Raw
    Check 'nx-mcp.js pins nx-mcp and forces --minimal false' (
        $nxText -match "NX_MCP_VERSION = '\d+\.\d+\.\d+'" -and $nxText -match "'--minimal', 'false'") `
        'keep the exact NX_MCP_VERSION and the --minimal false arguments in ai_tooling/nx-mcp.js'
}
```

### flutter-dart

**Gives:** Dart and Flutter in one server (`dart mcp-server`): analyzer diagnostics, hot reload and
restart, the widget inspector, pub.

**Needs:** the Flutter SDK (which ships Dart) on `PATH`. In an editor with the Dart extension
(Antigravity), the extension registers the server as an IDE-level provider, so the entry is
skipped for `gemini`.

```json
"flutter-dart": {
  "description": "Dart and Flutter: analyzer diagnostics, hot reload/restart, widget inspector, pub. One server covers both languages.",
  "transport": "stdio",
  "command": "dart",
  "args": ["mcp-server"],
  "skipAgents": ["gemini"],
  "skipReason": "The Dart extension registers dart-sdk-mcp-servers as an IDE-level provider in Antigravity."
}
```

**Check for `verify-project.ps1`:** `dart` is on `PATH` (a warning: a backend developer without
the Flutter SDK is not broken).

```powershell
if (-not $SourceOnly -and -not (Get-Command dart -ErrorAction SilentlyContinue)) {
    Write-Host "  WARN  the flutter-dart MCP server needs the Flutter SDK (dart) on PATH"
}
```

A Dart or Flutter app whose SDK is older than the one `dart mcp-server` needs (Dart 3) cannot use
this server; say so in that app's `AGENTS.md` instead of declaring it.
