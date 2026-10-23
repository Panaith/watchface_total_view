# Helpers for the expected-output test of ai_tooling/setup.ps1, dot-sourced by
# Invoke-Tests.ps1 and setup.Tests.ps1.
#
# A snapshot is one text file per agent: every file and junction setup.ps1
# writes for that agent, normalized so it is the same on every machine and in
# both Windows PowerShell 5.1 and PowerShell 7:
#   - the repository, output and home roots become {REPO_ROOT}, {OUTPUT_ROOT}
#     and {HOME_ROOT}; paths use forward slashes;
#   - line endings become LF; a UTF-8 BOM is noted on the header line;
#   - JSON is re-serialized in one fixed form (ConvertTo-Json indents
#     differently in 5.1 and 7); the hashes in localsources.json become
#     {sha256};
#   - a junction is recorded as its target, not followed; a skill copy (a
#     folder with setup's marker file) as the folder it was copied from;
#   - where a generated file ends with the content of a source file
#     (PERMISSIONS.md, an AGENTS.md, an ai_tooling/instructions or
#     external-skill-config file, with or without its frontmatter), that
#     content is replaced by a reference to the source. The snapshot then
#     changes when setup.ps1 changes what it writes, not when a document it
#     copies is edited.
#
# Snapshots are text, not a copy of the generated tree: .gitignore ignores the
# generated names (CLAUDE.md, .claude/, .mcp.json, ...) at every level, and an
# agent would read a committed stub or rules folder as live instructions.

$SnapshotAiDir    = Split-Path -Parent $PSScriptRoot
$SnapshotRepoRoot = Split-Path -Parent $SnapshotAiDir
# Remove-FolderSafely and the skill copy marker. Not -Force: the Pester tests
# have loaded it already, and their mocks need that one instance.
Import-Module (Join-Path $SnapshotAiDir 'lib\AgentSetup.psm1')
$SnapshotAgents   = @((Read-AgentManifest $SnapshotAiDir).Keys)
$SnapshotVersion  = ([System.IO.File]::ReadAllText((Join-Path $SnapshotAiDir 'version'))).Trim()

# Environment variables that change the generated MCP config ("envArgs" in
# mcp-servers.json). setup.ps1 also reads them from the User scope, so they
# cannot be cleared for a child process; the snapshot refuses to run instead.
function Get-SnapshotEnvConflicts {
    $def = Get-Content (Join-Path $SnapshotAiDir 'mcp-servers.json') -Raw | ConvertFrom-Json
    $names = @()
    foreach ($server in $def.servers.PSObject.Properties) {
        if ($server.Value.envArgs) { $names += $server.Value.envArgs.PSObject.Properties.Name }
    }
    return @($names | Select-Object -Unique | Where-Object {
        [Environment]::GetEnvironmentVariable($_, 'Process') -or [Environment]::GetEnvironmentVariable($_, 'User')
    })
}

# One fixed JSON form: two-space indent, keys in their original order, only
# the escapes JSON requires.
function ConvertTo-CanonicalJson($value, [int]$depth = 0) {
    $pad = '  ' * ($depth + 1)
    $end = '  ' * $depth
    if ($null -eq $value) { return 'null' }
    if ($value -is [bool]) { if ($value) { return 'true' } else { return 'false' } }
    if ($value -is [string]) {
        $s = $value.Replace('\', '\\').Replace('"', '\"').Replace("`n", '\n').Replace("`r", '\r').Replace("`t", '\t')
        return '"' + $s + '"'
    }
    if ($value -is [ValueType]) { return [string]::Format([Globalization.CultureInfo]::InvariantCulture, '{0}', $value) }
    if ($value -is [System.Collections.IList]) {
        if ($value.Count -eq 0) { return '[]' }
        $items = foreach ($v in $value) { $pad + (ConvertTo-CanonicalJson $v ($depth + 1)) }
        return "[`n" + ($items -join ",`n") + "`n$end]"
    }
    $props = @($value.PSObject.Properties)
    if ($props.Count -eq 0) { return '{}' }
    $items = foreach ($p in $props) { $pad + (ConvertTo-CanonicalJson $p.Name) + ': ' + (ConvertTo-CanonicalJson $p.Value ($depth + 1)) }
    return "{`n" + ($items -join ",`n") + "`n$end}"
}

function Get-NormalizedText($text, $roots) {
    $text = $text.Replace("`r`n", "`n")
    # Case-insensitive: the drive letter's case depends on how the script was invoked.
    foreach ($r in $roots) {
        foreach ($form in @($r.Path, $r.Path.Replace('\', '/'))) {
            $text = [regex]::Replace($text, [regex]::Escape($form), $r.Token.Replace('$', '$$'), 'IgnoreCase')
        }
    }
    return $text
}

# The documents setup.ps1 copies into rule files, LF-normalized, longest first
# so the most specific match wins.
function Get-SnapshotSources {
    $files = @(Join-Path $SnapshotAiDir 'PERMISSIONS.md')
    $files += @(Get-ChildItem $SnapshotRepoRoot -Directory | ForEach-Object { Join-Path $_.FullName 'AGENTS.md' } | Where-Object { Test-Path $_ })
    $files += @(Get-ChildItem (Join-Path $SnapshotAiDir 'instructions') -Filter *.md -File | ForEach-Object { $_.FullName })
    $files += @(Get-ChildItem (Join-Path $SnapshotAiDir 'external-skill-config') -Filter *.md -File -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
    $sources = foreach ($f in $files) {
        $text = [System.IO.File]::ReadAllText($f).Replace("`r`n", "`n")
        $name = '{REPO_ROOT}/' + $f.Substring($SnapshotRepoRoot.Length + 1).Replace('\', '/')
        [pscustomobject]@{ Name = $name; Text = $text }
        if ($text -match '\A---\n(?s:.*?)\n---\n') {
            [pscustomobject]@{ Name = "$name without frontmatter"; Text = $text.Substring($matches[0].Length).TrimStart("`n") }
        }
    }
    return @($sources | Where-Object { $_.Text.Length -gt 0 } | Sort-Object { $_.Text.Length } -Descending)
}

# Every file and junction under $root, as snapshot entries, paths relative to
# the root with forward slashes, in ordinal order. Junctions are not followed.
function Get-TreeEntries($root, $token, $roots, $sources) {
    $entries = New-Object System.Collections.Generic.List[object]
    $pending = New-Object System.Collections.Generic.Stack[string]
    $pending.Push($root)
    while ($pending.Count -gt 0) {
        foreach ($item in Get-ChildItem -LiteralPath $pending.Pop() -Force) {
            $rel = "$token/" + $item.FullName.Substring($root.Length + 1).Replace('\', '/')
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                $target = Get-NormalizedText (@($item.Target)[0]) $roots
                $entries.Add([pscustomobject]@{ Path = $rel; Body = "$($item.LinkType.ToLower()) -> $($target.Replace('\', '/'))" })
            } elseif ($item.PSIsContainer -and (Test-Path -LiteralPath (Join-Path $item.FullName $SkillCopyMarker))) {
                # A skill copy: its files are the source's, so record where it came from.
                $marker = [System.IO.File]::ReadAllText((Join-Path $item.FullName $SkillCopyMarker))
                $source = if ($marker -match 'from (.+?)\. Edit') { (Get-NormalizedText $Matches[1] $roots).Replace('\', '/') } else { '?' }
                $entries.Add([pscustomobject]@{ Path = $rel; Body = "copy of $source" })
            } elseif ($item.PSIsContainer) {
                $pending.Push($item.FullName)
            } else {
                $bytes = [System.IO.File]::ReadAllBytes($item.FullName)
                $bom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
                $text = [System.IO.File]::ReadAllText($item.FullName)
                if ($item.Extension -eq '.json') {
                    $text = ConvertTo-CanonicalJson ($text | ConvertFrom-Json)
                }
                # localsources.json: the hashes change with every edit of a
                # source; the snapshot keeps which sources were recorded.
                if ($item.Name -eq 'localsources.json') { $text = $text -replace '"[0-9a-f]{64}"', '"{sha256}"' }
                $text = Get-NormalizedText $text $roots
                # localversion: the version number would otherwise change every
                # snapshot with every version raise.
                if ($text.Trim() -eq $SnapshotVersion) { $text = "{the number in {REPO_ROOT}/$ToolingDirName/version}" }
                foreach ($s in $sources) {
                    if ($text.EndsWith($s.Text, [StringComparison]::Ordinal)) {
                        $text = $text.Substring(0, $text.Length - $s.Text.Length) + "{contents of $($s.Name)}`n"
                        break
                    }
                }
                $path = $rel
                if ($bom) { $path += ' (UTF-8 BOM)' }
                $entries.Add([pscustomobject]@{ Path = $path; Body = $text.TrimEnd("`n") })
            }
        }
    }
    # Ordinal: culture-aware sorting differs between 5.1 (NLS) and 7 (ICU).
    $entries.Sort([Comparison[object]] { param($a, $b) [string]::CompareOrdinal($a.Path, $b.Path) })
    return $entries.ToArray()
}

function Format-Snapshot($agent, $entries) {
    $lines = @("# Expected output of $ToolingDirName/setup.ps1 -Agent $agent -SkipTools -OutputRoot {OUTPUT_ROOT} -HomeRoot {HOME_ROOT}.",
               "# Written by $ToolingDirName/tests/Invoke-Tests.ps1 -Update. Do not edit by hand.")
    foreach ($e in $entries) { $lines += @('', "=== $($e.Path)", $e.Body) }
    return ($lines -join "`n") + "`n"
}

# Normalized entries of the files under one or two roots that setup.ps1 has
# already written to.
function Get-OutputEntries($outRoot, $homeRoot) {
    $roots = @(
        [pscustomobject]@{ Path = $SnapshotRepoRoot; Token = '{REPO_ROOT}' }
    )
    if ($outRoot) { $roots = @([pscustomobject]@{ Path = $outRoot; Token = '{OUTPUT_ROOT}' }) + $roots }
    if ($homeRoot) { $roots = @([pscustomobject]@{ Path = $homeRoot; Token = '{HOME_ROOT}' }) + $roots }
    $sources = Get-SnapshotSources
    $entries = @()
    if ($outRoot) { $entries += Get-TreeEntries $outRoot '{OUTPUT_ROOT}' $roots $sources }
    if ($homeRoot) { $entries += Get-TreeEntries $homeRoot '{HOME_ROOT}' $roots $sources }
    return $entries
}

# Runs setup.ps1 for one agent into two fresh temp roots, in a child process of
# the same PowerShell edition, and returns the snapshot text.
function Get-SetupSnapshot($agent) {
    $base = Join-Path ([System.IO.Path]::GetTempPath()) "ai-tooling-setup-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
    $out  = Join-Path $base 'out'
    $home_ = Join-Path $base 'home'
    New-Item -ItemType Directory -Force -Path $out, $home_ | Out-Null
    try {
        $log = Invoke-SetupChild @('-Agent', $agent, '-SkipTools', '-OutputRoot', $out, '-HomeRoot', $home_)
        if ($LASTEXITCODE -ne 0) { throw "setup.ps1 -Agent $agent failed:`n$($log -join "`n")" }
        return Format-Snapshot $agent (Get-OutputEntries $out $home_)
    } finally {
        Remove-FolderSafely $base
    }
}

# Runs setup.ps1 in a child process of the same PowerShell edition and returns
# its output lines; $LASTEXITCODE tells whether it succeeded.
function Invoke-SetupChild([string[]]$arguments) {
    $ErrorActionPreference = 'Continue'
    $exe = (Get-Process -Id $PID).Path
    $setup = Join-Path $SnapshotAiDir 'setup.ps1'
    return @(& $exe -NoProfile -ExecutionPolicy Bypass -File $setup @arguments 2>&1 | ForEach-Object { "$_" })
}
