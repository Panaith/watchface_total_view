# Functions of the agent tooling setup, used by ai_tooling/setup.ps1,
# ai_tooling/scripts/*.ps1, ai_tooling/verify-agent-setup.ps1 and the
# update-*-skills.ps1 installers. They hold no agent's paths: those come from
# ai_tooling/manifest/agents.json through Get-AgentLayout, and nothing of the
# project: its name and skill prefixes come from ai_tooling/manifest/project.json.
# This file is the same in every project set up from the ai_tooling blueprint;
# project-specific code goes into ai_tooling/scripts/.
# Nothing here reads the caller's variables; every input is a parameter, so each
# function can be tested on its own.
#
# Works in Windows PowerShell 5.1 and PowerShell 7.

$Utf8NoBom = New-Object System.Text.UTF8Encoding $false

# The tooling folder at the repository root: the folder this module's lib/ is in
# (ai_tooling by convention).
$ToolingDirName = Split-Path -Leaf (Split-Path -Parent $PSScriptRoot)
$ToolingSkillsPattern = '\\' + [regex]::Escape($ToolingDirName) + '\\skills'

# ---------------------------------------------------------------- manifests ---

# The project's own facts from ai_tooling/manifest/project.json, as
# @{ Name; Prefixes; Pattern }: Prefixes are the skill prefixes of the project
# skills and subagents (the first one is the main one), Pattern matches a name
# that starts with one of them and a hyphen.
function Read-ProjectManifest([string]$AiDir) {
    $json = Get-Content (Join-Path $AiDir 'manifest\project.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $prefixes = @($json.skillPrefixes | Where-Object { $_ })
    if (-not $prefixes) { throw "ai_tooling/manifest/project.json names no skillPrefixes" }
    return [pscustomobject]@{
        Name     = $json.name
        Prefixes = $prefixes
        Pattern  = '^(' + (($prefixes | ForEach-Object { [regex]::Escape($_) }) -join '|') + ')-'
    }
}

# The agents in manifest order, as an ordered dictionary key -> entry.
function Read-AgentManifest([string]$AiDir) {
    $json = Get-Content (Join-Path $AiDir 'manifest\agents.json') -Raw | ConvertFrom-Json
    $agents = [ordered]@{}
    foreach ($p in $json.agents.PSObject.Properties) { $agents[$p.Name] = $p.Value }
    return $agents
}

# File name -> @{ Description; Globs } for every ai_tooling/instructions file, with
# allApps expanded to one glob per app folder.
function Read-InstructionManifest([string]$AiDir, [string[]]$AppNames) {
    $json = Get-Content (Join-Path $AiDir 'manifest\instructions.json') -Raw | ConvertFrom-Json
    $meta = @{}
    foreach ($p in $json.instructions.PSObject.Properties) {
        $globs = @($p.Value.globs | Where-Object { $_ })
        if ($p.Value.allApps) { $globs += @($AppNames | ForEach-Object { "$_/**" }) }
        $meta[$p.Name] = @{ Description = $p.Value.description; Globs = $globs }
    }
    return $meta
}

function Join-ManifestPath([string]$root, [string]$relative) {
    return Join-Path $root ($relative.Replace('/', '\'))
}

# One agent's layout with absolute paths, and what setup publishes for it.
# The three Publishes* values follow from the agent's facts in agents.json and
# are the only place that decision is made.
function Get-AgentLayout([string]$Key, $Entry, [string]$OutRoot, [string]$HomeDir) {
    $rules = $Entry.rules
    $stub = $Entry.stub
    $mcpRoot = if ($Entry.mcp.root -eq 'home') { $HomeDir } else { $OutRoot }
    $legacyRoot = if ($Entry.mcp.legacyRoot -eq 'home') { $HomeDir } elseif ($Entry.mcp.legacyRoot -eq 'repo') { $OutRoot } else { $mcpRoot }
    $appStubsImport = [bool]($stub -and $stub.inApps -and $Entry.resolvesImports)
    return @{
        Key                   = $Key
        Name                  = $Entry.name
        Detect                = $Entry.detect
        Skills                = Join-ManifestPath $OutRoot $Entry.skills
        SkillLinks            = $Entry.skillLinks
        Subagents             = if ($Entry.subagents) { Join-ManifestPath $OutRoot $Entry.subagents } else { $null }
        Rules                 = if ($rules) { Join-ManifestPath $OutRoot $rules.folder } else { $null }
        RuleFormat            = if ($rules) { $rules.format } else { $null }
        StaleRules            = if ($rules) { @($rules.staleFiles | Where-Object { $_ }) } else { @() }
        Stub                  = if ($stub) { $stub.file } else { $null }
        AppStubs              = [bool]($stub -and $stub.inApps)
        ResolvesImports       = [bool]$Entry.resolvesImports
        ReadsNestedAgentsMd   = [bool]$Entry.readsNestedAgentsMd
        PointerFile           = if ($Entry.pointerFile) { Join-ManifestPath $OutRoot $Entry.pointerFile } else { $null }
        LegacyFiles           = @($Entry.legacyFiles | Where-Object { $_ })
        PersonalSkills        = @($Entry.personal.skills | Where-Object { $_ })
        PersonalMcp           = @($Entry.personal.mcp | Where-Object { $_ })
        Mcp                   = Join-ManifestPath $mcpRoot $Entry.mcp.file
        McpLegacy             = @($Entry.mcp.legacyFiles | Where-Object { $_ } | ForEach-Object { Join-ManifestPath $legacyRoot $_ })
        McpKeepValid          = @($Entry.mcp.keepValid | Where-Object { $_ } | ForEach-Object { Join-ManifestPath $legacyRoot $_ })
        McpInHome             = ($Entry.mcp.root -eq 'home')
        McpKey                = $Entry.mcp.key
        HttpUrlField          = $Entry.mcp.httpUrlField
        HttpType              = [bool]$Entry.mcp.httpType
        PublishesPermissions  = [bool]($rules -and -not $Entry.resolvesImports)
        PublishesInstructions = [bool]($rules -and -not $Entry.resolvesImports)
        PublishesAppRules     = [bool]($rules -and -not $Entry.readsNestedAgentsMd -and -not $appStubsImport)
    }
}

# Every agent's layout, in manifest order.
function Get-AgentLayouts([string]$AiDir, [string]$OutRoot, [string]$HomeDir) {
    $layouts = [ordered]@{}
    $manifest = Read-AgentManifest $AiDir
    foreach ($key in $manifest.Keys) { $layouts[$key] = Get-AgentLayout $key $manifest[$key] $OutRoot $HomeDir }
    return $layouts
}

# ------------------------------------------------------------------- skills ---

# ai_tooling/manifest/skills.json with every skill resolved: what it inherits from its
# group (owner, source, apps, default) and its folder ai_tooling/skills/{group}/{name}.
# A skill whose group is missing keeps $null there; Test-SkillManifest reports it.
function Read-SkillManifest([string]$AiDir) {
    $json = Get-Content (Join-Path $AiDir 'manifest\skills.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $groups = [ordered]@{}
    foreach ($p in $json.groups.PSObject.Properties) { $groups[$p.Name] = $p.Value }
    $profiles = [ordered]@{}
    foreach ($p in $json.profiles.PSObject.Properties) { $profiles[$p.Name] = $p.Value }
    $skillsDir = Join-Path $AiDir 'skills'
    $skills = [ordered]@{}
    foreach ($p in $json.skills.PSObject.Properties) {
        $s = $p.Value
        $g = $groups[$s.group]
        $skills[$p.Name] = [pscustomobject]@{
            Name       = $p.Name
            Group      = $s.group
            Path       = Join-ManifestPath $skillsDir "$($s.group)/$($p.Name)"
            Owner      = if ($g) { $g.owner } else { $null }
            Source     = if ($g) { $g.source } else { $null }
            Apps       = @(if ($null -ne $s.apps) { $s.apps } elseif ($g) { $g.apps })
            Default    = if ($null -ne $s.default) { [bool]$s.default } else { [bool]($g -and $g.default) }
            Status     = if ($s.status) { $s.status } else { 'active' }
            ReplacedBy = $s.replacedBy
        }
    }
    return [pscustomobject]@{ Groups = $groups; Profiles = $profiles; Skills = $skills }
}

# The names of the skills the given profiles publish, in manifest order.
# 'default' (every skill with default true) and 'all' are built in; several
# profiles add up. 'a,b' counts as two: powershell -File passes it as one string.
function Resolve-SkillProfile($Manifest, [string[]]$Names) {
    $Names = @($Names | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    if (-not $Names) { $Names = @('default') }
    $known = @('default', 'all') + @($Manifest.Profiles.Keys)
    $unknown = @($Names | Where-Object { $known -notcontains $_ })
    if ($unknown) { throw "Unknown profile '$($unknown -join "', '")'. Use $($known -join ', ')." }
    $all = $Names -contains 'all'
    $default = $Names -contains 'default'
    $groups = @($Names | Where-Object { $_ -ne 'all' -and $_ -ne 'default' } | ForEach-Object { $Manifest.Profiles[$_].groups })
    return @($Manifest.Skills.Values | Where-Object { $all -or ($default -and $_.Default) -or ($groups -contains $_.Group) } | ForEach-Object { $_.Name })
}

# Every skill folder on disk: a folder under ai_tooling/skills that holds a SKILL.md,
# at most three levels down ({group}/{name} with a group of one or two
# segments). Group is the path between ai_tooling/skills and the skill, '' for one
# directly in ai_tooling/skills. A list, not a dictionary: a name can occur twice.
function Get-SkillFolders([string]$SkillsDir) {
    $found = @()
    $level = @(Get-ChildItem $SkillsDir -Directory)
    for ($depth = 1; $level -and $depth -le 3; $depth++) {
        $next = @()
        foreach ($d in $level) {
            $rel = $d.FullName.Substring($SkillsDir.TrimEnd('\').Length + 1).Replace('\', '/')
            if (Test-Path (Join-Path $d.FullName 'SKILL.md')) {
                $group = if ($rel.Contains('/')) { $rel.Substring(0, $rel.LastIndexOf('/')) } else { '' }
                $found += [pscustomobject]@{ Name = $d.Name; Group = $group; Path = $d.FullName }
            } else {
                $next += @(Get-ChildItem $d.FullName -Directory)
            }
        }
        $level = $next
    }
    return $found
}

# What is wrong between skills.json and the folders, as one message each:
# a folder without an entry, an entry without its folder, a skill in another
# group's folder, a name in several folders, and references to groups or
# skills that do not exist. Empty when they agree.
function Test-SkillManifest($Manifest, [string]$SkillsDir) {
    $problems = @()
    $folders = @(Get-SkillFolders $SkillsDir)
    foreach ($dup in @($folders | Group-Object Name | Where-Object Count -gt 1)) {
        $problems += "$($dup.Name): in several folders ($(($dup.Group | ForEach-Object { "$($_.Group)/$($_.Name)" }) -join ', ')); skill names must be unique across groups"
    }
    foreach ($f in $folders) {
        $entry = $Manifest.Skills[$f.Name]
        if (-not $entry) { $problems += "$($f.Group)/$($f.Name): folder has no entry in skills.json" }
        elseif ($entry.Group -ne $f.Group) { $problems += "$($f.Name): folder is in '$($f.Group)', skills.json says group '$($entry.Group)'" }
    }
    foreach ($s in $Manifest.Skills.Values) {
        if (-not $Manifest.Groups.Contains($s.Group)) { $problems += "$($s.Name): group '$($s.Group)' is not defined in skills.json" }
        if (-not ($folders | Where-Object Name -eq $s.Name)) { $problems += "$($s.Name): no folder ai_tooling/skills/$($s.Group)/$($s.Name)" }
        if ($s.ReplacedBy -and -not $Manifest.Skills.Contains($s.ReplacedBy)) { $problems += "$($s.Name): replacedBy '$($s.ReplacedBy)' is not a skill" }
    }
    foreach ($p in $Manifest.Profiles.Keys) {
        foreach ($g in @($Manifest.Profiles[$p].groups | Where-Object { -not $Manifest.Groups.Contains($_) })) {
            $problems += "profile '$p': group '$g' is not defined"
        }
    }
    return $problems
}

# Records the upstream commit an update-*-skills.ps1 installed in the group's
# source in skills.json ("commit"). Edits that one line, so the rest of the
# file keeps its layout, comments and line endings.
function Set-SkillGroupCommit([string]$AiDir, [string]$Group, [string]$Commit) {
    if ($Commit -notmatch '^[0-9a-f]{40}$') { throw "not a full commit id: '$Commit'" }
    Set-SkillGroupSourceValue $AiDir $Group 'commit' $Commit
}

# Records the content hash of the group's folder (Get-SkillGroupHash) in the
# group's source in skills.json ("hash"), the same way as the commit.
function Set-SkillGroupHash([string]$AiDir, [string]$Group, [string]$Hash) {
    if ($Hash -cnotmatch '^[0-9a-f]{64}$') { throw "not a SHA-256 hash in lowercase hex: '$Hash'" }
    Set-SkillGroupSourceValue $AiDir $Group 'hash' $Hash
}

# SHA-256 over every file under a group's folder, as 64 lowercase hex characters:
# for each file in the order of its relative path (forward slashes, ordinal), the
# path as UTF-8, a NUL byte, the file's bytes with CRLF turned into LF, a NUL
# byte. The line endings are normalised because a clone's core.autocrlf decides
# them; nothing else is left out (LICENSE files belong to the group).
function Get-SkillGroupHash([string]$GroupDir) {
    $root = (Get-Item -LiteralPath $GroupDir).FullName.TrimEnd('\', '/')
    $files = @{}
    foreach ($f in Get-ChildItem -LiteralPath $root -Recurse -File -Force) {
        $files[$f.FullName.Substring($root.Length + 1).Replace('\', '/')] = $f.FullName
    }
    $order = [string[]]@($files.Keys)
    [Array]::Sort($order, [System.StringComparer]::Ordinal)
    # Latin-1 maps every byte to one character and back, so the CRLF -> LF
    # replacement is a string replace on the bytes.
    $latin1 = [System.Text.Encoding]::GetEncoding(28591)
    $nul = [byte[]]@(0)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        foreach ($rel in $order) {
            $data = $latin1.GetBytes($latin1.GetString([System.IO.File]::ReadAllBytes($files[$rel])).Replace("`r`n", "`n"))
            foreach ($bytes in @($Utf8NoBom.GetBytes($rel), $nul, $data, $nul)) {
                [void]$sha.TransformBlock($bytes, 0, $bytes.Length, $null, 0)
            }
        }
        [void]$sha.TransformFinalBlock([byte[]]@(), 0, 0)
        return ([System.BitConverter]::ToString($sha.Hash).Replace('-', '')).ToLowerInvariant()
    } finally {
        $sha.Dispose()
    }
}

# Whether the group has the one-line "source": { ... "installer": ... } in
# skills.json that Set-SkillGroupSourceValue can write into.
function Test-SkillGroupSourceLine([string]$AiDir, [string]$Group) {
    $lines = [System.IO.File]::ReadAllText((Join-Path $AiDir 'manifest\skills.json'), [System.Text.Encoding]::UTF8) -split "`r?`n"
    $inGroup = $false
    foreach ($line in $lines) {
        if ($line -match "^\s*""$([regex]::Escape($Group))""\s*:\s*\{") { $inGroup = $true; continue }
        if ($inGroup -and $line -match '^\s*"source"\s*:\s*\{') { return [bool]($line -match '"installer"\s*:') }
        if ($inGroup -and $line -match '^\s*\}') { return $false }
    }
    return $false
}

# Sets "$Field": "$Value" in the group's one-line "source": { ... } in
# skills.json: replaces the field, or inserts it before "installer".
function Set-SkillGroupSourceValue([string]$AiDir, [string]$Group, [string]$Field, [string]$Value) {
    $file = Join-Path $AiDir 'manifest\skills.json'
    $text = [System.IO.File]::ReadAllText($file, [System.Text.Encoding]::UTF8)
    $nl = if ($text.Contains("`r`n")) { "`r`n" } else { "`n" }
    $lines = $text -split "`r?`n"
    $inGroup = $false
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match "^\s*""$([regex]::Escape($Group))""\s*:\s*\{") { $inGroup = $true; continue }
        if ($inGroup -and $lines[$i] -match '^\s*"source"\s*:\s*\{') {
            $before = $lines[$i]
            if ($before -match """$Field""\s*:\s*""[^""]*""") { $lines[$i] = $before -replace """$Field""\s*:\s*""[^""]*""", """$Field"": ""$Value""" }
            else { $lines[$i] = $before -replace ',\s*"installer"', ", ""$Field"": ""$Value"", ""installer""" }
            # A value equal to the recorded one changes nothing and is fine;
            # a line with neither the field nor "installer" is not.
            if ($lines[$i] -notmatch """$Field"": ""$Value""") { throw "could not record the $Field in the source of group '$Group' in $file" }
            [System.IO.File]::WriteAllText($file, ($lines -join $nl), (New-Object System.Text.UTF8Encoding $false))
            return
        }
        if ($inGroup -and $lines[$i] -match '^\s*\}') { break }
    }
    throw "group '$Group' with a one-line source not found in $file"
}

# Limits that keep the skill list every session loads cheap, and each skill
# readable: the Agent Skills specification's maximum description, and a
# SKILL.md short enough to read at once (detail belongs in references/).
$SkillDescriptionMax = 1024
$SkillLinesMax = 500
# A reference file longer than this starts with a Contents list (Anthropic's
# skill authoring best practices), so a partial read still shows its scope.
$SkillReferenceLinesMax = 100
# The Agent Skills specification's other limits: the name and the optional
# compatibility field.
$SkillNameMax = 64
$SkillCompatibilityMax = 500

# The description in a SKILL.md frontmatter, as one line: quotes, a folded or
# literal block marker and line breaks removed.
function Get-SkillDescription([string]$Text) {
    return Get-SkillFrontmatterValue $Text 'description'
}

# One field of a SKILL.md frontmatter, as Get-SkillDescription reads it; $null
# when the frontmatter or the field is missing.
function Get-SkillFrontmatterValue([string]$Text, [string]$Key) {
    if ($Text -notmatch '\A\s*---\r?\n((?s:.*?))\r?\n---') { return $null }
    $front = $Matches[1]
    if ($front -notmatch "(?ms)^$([regex]::Escape($Key)):[ \t]*(.*?)(?=^[A-Za-z][\w-]*:|\z)") { return $null }
    $value = ($Matches[1] -replace '^[>|][-+]?\s*', '' -replace '\s+', ' ').Trim()
    if ($value.Length -ge 2 -and (($value[0] -eq '"' -and $value[-1] -eq '"') -or ($value[0] -eq "'" -and $value[-1] -eq "'"))) {
        $value = $value.Substring(1, $value.Length - 2)
    }
    return $value
}

# What is wrong inside the skills, as @{ Errors; Warnings }: a BOM, a
# frontmatter name that is not the folder's, a missing or too long
# description, a compatibility over $SkillCompatibilityMax characters, a
# SKILL.md over $SkillLinesMax lines (an error for a project
# skill, a warning for an upstream one, which is not edited here), a name over
# $SkillNameMax characters or with a leading, trailing or double hyphen, a name
# against the naming convention (only project skills start with one of the
# project's prefixes, $Project from Read-ProjectManifest), a project skill that
# mentions approvals without pointing to PERMISSIONS.md, a Markdown file other
# than SKILL.md in a project skill's folder (references/) over
# $SkillReferenceLinesMax lines without a "## Contents" list in its first 30
# lines, and every deprecated skill (a warning: remove it after one release).
# Skills without a folder are left to Test-SkillManifest.
function Test-SkillContent($Manifest, $ProjectFacts) {
    # $ProjectFacts, not $Project: PowerShell names ignore case, and $project below is a flag.
    $prefixes = ($ProjectFacts.Prefixes | ForEach-Object { [regex]::Escape($_) }) -join '|'
    $prefixList = $ProjectFacts.Prefixes -join ', '
    $named = ($ProjectFacts.Prefixes | ForEach-Object { "$_-..." }) -join ' or '
    $maintain = "$($ProjectFacts.Prefixes[0])-aitooling-maintain"
    $errors = @()
    $warnings = @()
    foreach ($s in $Manifest.Skills.Values) {
        $md = Join-Path $s.Path 'SKILL.md'
        if (-not (Test-Path -LiteralPath $md)) { continue }
        $project = ($s.Source -eq 'project')
        $bytes = [System.IO.File]::ReadAllBytes($md)
        if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
            $errors += "$($s.Name): SKILL.md starts with a UTF-8 BOM, which hides the frontmatter from the loader"
        }
        $text = [System.IO.File]::ReadAllText($md, [System.Text.Encoding]::UTF8)
        if ($text -notmatch "(?m)^name:\s*['`"]?$([regex]::Escape($s.Name))['`"]?\s*$") {
            $errors += "$($s.Name): the frontmatter name is not '$($s.Name)'"
        }
        $desc = Get-SkillDescription $text
        if (-not $desc) { $errors += "$($s.Name): no description; agents pick a skill by it" }
        elseif ($desc.Length -gt $SkillDescriptionMax) { $errors += "$($s.Name): description has $($desc.Length) characters, more than $SkillDescriptionMax" }
        $compat = Get-SkillFrontmatterValue $text 'compatibility'
        if ($compat -and $compat.Length -gt $SkillCompatibilityMax) { $errors += "$($s.Name): compatibility has $($compat.Length) characters, more than $SkillCompatibilityMax" }
        if ($s.Name.Length -gt $SkillNameMax) { $errors += "$($s.Name): the name has $($s.Name.Length) characters, more than $SkillNameMax" }
        $hyphens = ($s.Name -match '--' -or $s.Name.StartsWith('-') -or $s.Name.EndsWith('-'))
        if ($hyphens) { $errors += "$($s.Name): a name has no leading, trailing or double hyphen (Agent Skills specification)" }
        $lines = ($text.TrimEnd() -split "`n").Count
        if ($lines -gt $SkillLinesMax) {
            $msg = "$($s.Name): SKILL.md has $lines lines, more than $SkillLinesMax; move detail into references/"
            if ($project) { $errors += $msg } else { $warnings += "$msg (upstream, not edited here)" }
        }
        if ($project -and -not $hyphens -and $s.Name -cnotmatch "^($prefixes)(-[a-z0-9]+)+$") {
            $errors += "$($s.Name): a project skill is named $named ($maintain, section 2)"
        }
        if (-not $project -and $s.Name -match "^($prefixes)-") {
            $errors += "$($s.Name): the prefixes $prefixList are for project skills; this one comes from upstream"
        }
        if ($project -and $text -match '(?i)\bapprov' -and $text -notmatch 'PERMISSIONS\.md') {
            $errors += "$($s.Name): mentions approvals without pointing to PERMISSIONS.md, the only place those rules are written"
        }
        if ($project) {
            $root = (Get-Item -LiteralPath $s.Path).FullName.TrimEnd('\', '/')
            foreach ($f in Get-ChildItem -LiteralPath $s.Path -Recurse -File -Filter '*.md') {
                if ($f.FullName -eq (Join-Path $root 'SKILL.md')) { continue }
                $refLines = ([System.IO.File]::ReadAllText($f.FullName, [System.Text.Encoding]::UTF8).TrimEnd() -split "`n")
                if ($refLines.Count -le $SkillReferenceLinesMax) { continue }
                $head = @($refLines | Select-Object -First 30)
                if (-not @($head | Where-Object { $_ -match '(?i)^##\s+Contents\s*$' })) {
                    $rel = $f.FullName.Substring($root.Length + 1).Replace('\', '/')
                    $errors += "$($s.Name): $rel has $($refLines.Count) lines and no '## Contents' list at the top (a reference file over $SkillReferenceLinesMax lines starts with one)"
                }
            }
        }
        if ($s.Status -eq 'deprecated') {
            $warnings += "$($s.Name): deprecated, replaced by $($s.ReplacedBy); remove it after one release"
        }
    }
    return @{ Errors = $errors; Warnings = $warnings }
}

# Whether every upstream group's folder still has the content hash its
# installer recorded in skills.json, as @{ Errors; Warnings; Matches }: an
# error names the group whose folder differs (edited by hand, a file added, or
# the installer not run) and the installer to run; a warning names a group
# without a recorded hash; Matches lists the groups that agree. Project groups
# and groups without a folder are skipped (Test-SkillManifest reports the
# missing folder).
function Test-UpstreamSkillHashes($Manifest, [string]$SkillsDir) {
    $errors = @()
    $warnings = @()
    $matches = @()
    foreach ($g in @($Manifest.Groups.Keys | Sort-Object)) {
        $source = $Manifest.Groups[$g].source
        if (-not $source -or $source -eq 'project') { continue }
        $groupDir = Join-ManifestPath $SkillsDir $g
        if (-not (Test-Path -LiteralPath $groupDir)) { continue }
        $installer = $source.installer
        if (-not $source.hash) {
            $warnings += "upstream group ${g}: no hash recorded yet; the next run of $installer records it"
        } elseif ((Get-SkillGroupHash $groupDir) -eq $source.hash) {
            $matches += $g
        } else {
            $errors += "upstream group ${g}: a file under ai_tooling/skills/$g was changed by hand, a file was added there, or the installer was not run; run $installer or revert the edit"
        }
    }
    return @{ Errors = $errors; Warnings = $warnings; Matches = $matches }
}

# The skills named in the routing tables ("| When you ... | Load |") of the
# root AGENTS.md and the app AGENTS.md files: @{ File; Line; Name } for every
# backticked name in the Load column, except one followed by "MCP server".
function Get-RoutedSkills([string]$RepoRoot) {
    $files = @(Join-Path $RepoRoot 'AGENTS.md') + @(Get-ChildItem $RepoRoot -Directory | ForEach-Object { Join-Path $_.FullName 'AGENTS.md' } | Where-Object { Test-Path $_ })
    $found = @()
    foreach ($f in $files) {
        $lines = [System.IO.File]::ReadAllLines($f, [System.Text.Encoding]::UTF8)
        $inTable = $false
        for ($i = 0; $i -lt $lines.Count; $i++) {
            $line = $lines[$i]
            if ($line -match '^\|.*\|\s*Load\s*\|\s*$') { $inTable = $true; continue }
            if (-not $inTable) { continue }
            if ($line -notmatch '^\|') { $inTable = $false; continue }
            if ($line -match '^\|[\s|:-]+$') { continue }
            $cells = $line.Trim().Trim('|') -split '\|'
            # "the `devextreme` MCP server" names a server, not a skill.
            foreach ($m in [regex]::Matches($cells[-1], '`([a-z0-9][a-z0-9-]*)`(?! MCP server)')) {
                $found += [pscustomobject]@{ File = $f.Substring($RepoRoot.Length + 1).Replace('\', '/'); Line = $i + 1; Name = $m.Groups[1].Value }
            }
        }
    }
    return $found
}

# Whether a skill copy holds the same files with the same bytes as its source
# (setup's marker file aside): SKILL.md, references/, scripts/ and the rest.
function Test-FolderCopyCurrent([string]$Copy, [string]$Source) {
    $list = {
        param($root)
        $len = $root.TrimEnd('\').Length + 1
        @(Get-ChildItem -LiteralPath $root -Recurse -File -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -ne $SkillCopyMarker } | ForEach-Object { $_.FullName.Substring($len) } | Sort-Object)
    }
    $a = & $list $Copy
    $b = & $list $Source
    if (($a -join '|') -ne ($b -join '|')) { return $false }
    foreach ($rel in $a) {
        $x = [System.IO.File]::ReadAllBytes((Join-Path $Copy $rel))
        $y = [System.IO.File]::ReadAllBytes((Join-Path $Source $rel))
        if ($x.Length -ne $y.Length -or [Convert]::ToBase64String($x) -ne [Convert]::ToBase64String($y)) { return $false }
    }
    return $true
}

# Each published skills folder against the profile: what setup published there
# (junctions and marked copies), compared with the skills the profile chooses.
# @{ Missing; Extra; Dangling; Stale } (names): not published, published but
# not chosen, a junction whose source is gone, a copy older than its source.
function Test-PublishedSkills($Layout, $Skills, [string]$SkillsDir, [string[]]$KnownNames) {
    if (-not $KnownNames) { $KnownNames = @($Skills | ForEach-Object { $_.Name }) }
    $r = @{ Missing = @(); Extra = @(); Dangling = @(); Stale = @() }
    $wanted = @{}
    foreach ($s in $Skills) { $wanted[$s.Name] = $s }
    $published = @{}
    foreach ($entry in @(Get-ChildItem -LiteralPath $Layout.Skills -Force -Directory -ErrorAction SilentlyContinue)) {
        $kind = Get-PublishedSkillKind $entry $SkillsDir $KnownNames
        if (-not $kind) { continue }
        $published[$entry.Name] = $true
        if (-not $wanted.ContainsKey($entry.Name)) { $r.Extra += $entry.Name; continue }
        if ($kind -eq 'junction' -and -not (Test-Path -LiteralPath (Join-Path $entry.FullName 'SKILL.md'))) { $r.Dangling += $entry.Name }
        if ($kind -eq 'copy' -and -not (Test-FolderCopyCurrent $entry.FullName $wanted[$entry.Name].Path)) { $r.Stale += $entry.Name }
    }
    foreach ($name in $wanted.Keys) { if (-not $published.ContainsKey($name)) { $r.Missing += $name } }
    $r.Missing = @($r.Missing | Sort-Object)
    return $r
}

# ------------------------------------------------------------ choose agents ---

# Pure: turns whatever the developer typed into agent keys. Kept separate from
# the prompt so it can be exercised without a console.
function Resolve-AgentChoice($answer, $keys) {
    if ([string]::IsNullOrWhiteSpace($answer)) { return @() }
    $answer = $answer.Trim()
    if ($answer -eq 'a' -or $answer -eq 'all') { return $keys }
    $picked = @()
    foreach ($part in ($answer -split '[,\s]+' | Where-Object { $_ })) {
        $n = 0
        if ([int]::TryParse($part, [ref]$n)) {
            if ($n -ge 1 -and $n -le $keys.Count) { $picked += $keys[$n - 1] }
        } elseif ($keys -contains $part.ToLower()) {
            $picked += $part.ToLower()
        }
    }
    return @($picked | Select-Object -Unique)
}

# Detection covers the usual installs, not every editor. Rather than give up on
# a JetBrains developer, or an IDE nobody here has seen yet, ask. Skipped where
# there is no console to ask on - CI, a git hook, or an AI agent running this
# through a tool - all of which redirect stdin. Assume redirected if we cannot
# tell: not prompting is recoverable, hanging forever is not.
function Select-AgentsInteractively($Layouts) {
    $redirected = $true
    try { $redirected = [Console]::IsInputRedirected } catch { }
    if ($env:CI -or $redirected) { return @() }

    $keys = @($Layouts.Keys)
    Write-Host "No agent detected automatically. That is expected in a JetBrains IDE,"
    Write-Host "or before you have started your agent for the first time."
    Write-Host ""
    for ($i = 0; $i -lt $keys.Count; $i++) {
        Write-Host ("  {0}) {1}" -f ($i + 1), $Layouts[$keys[$i]].Name)
    }
    Write-Host "  a) all of them"
    Write-Host ""
    $answer = Read-Host "Which do you use? (number, name, 'a', or Enter to skip)"
    $picked = Resolve-AgentChoice $answer $keys
    if ((-not $picked) -and $answer) { Write-Warning "Did not understand '$answer'." }
    return $picked
}

# The agents whose detection signals (agents.json "detect") are present.
function Find-InstalledAgents($Layouts, [string]$UserHome = $env:USERPROFILE) {
    $found = @()
    $vsx = @("$UserHome\.vscode\extensions", "$UserHome\.vscode-insiders\extensions")
    $ext = @($vsx | Where-Object { Test-Path $_ } | ForEach-Object { Get-ChildItem $_ -Directory -ErrorAction SilentlyContinue })

    foreach ($key in $Layouts.Keys) {
        $d = $Layouts[$key].Detect
        $hit = $false
        foreach ($pattern in @($d.vscodeExtensions | Where-Object { $_ })) {
            if ($ext | Where-Object { $_.Name -like $pattern }) { $hit = $true }
        }
        foreach ($folder in @($d.homeFolders | Where-Object { $_ })) {
            if (Test-Path (Join-ManifestPath $UserHome $folder)) { $hit = $true }
        }
        foreach ($command in @($d.commands | Where-Object { $_ })) {
            if (Get-Command $command -ErrorAction SilentlyContinue) { $hit = $true }
        }
        if ($hit) { $found += $key }
    }
    return @($found | Select-Object -Unique)
}

# Whether the layout is on disk in this clone: its skills folder holds something
# setup published (a junction into the tooling's skills, or a marked copy). A
# skills folder that setup.ps1 -Remove kept for a developer's own skills does
# not count, nor one that is itself a junction (a folder of the developer's:
# setup publishes nothing into it). A copy -Remove could not
# take away because it was in use still counts: that remove is unfinished, and
# runs again once the folder is free. An MCP config does not count either:
# -Remove keeps one that still holds the developer's own servers.
function Test-LayoutOnDisk($Layout) {
    $item = Get-Item -LiteralPath $Layout.Skills -Force -ErrorAction SilentlyContinue
    if (-not $item) { return $false }
    if ($item.LinkType) { return $false }
    foreach ($entry in @(Get-ChildItem -LiteralPath $Layout.Skills -Directory -Force -ErrorAction SilentlyContinue)) {
        if ($entry.LinkType) {
            if (([string](@($entry.Target)[0])) -match ($ToolingSkillsPattern + '\\')) { return $true }
        } elseif (Test-Path -LiteralPath (Join-Path $entry.FullName $SkillCopyMarker)) { return $true }
    }
    return $false
}

# The agents whose layout is on disk in this clone (Test-LayoutOnDisk), in
# manifest order. A run without -Agent refreshes exactly these, so a layout that
# was set up once keeps following mcp-servers.json (a stale config is worse than
# none) and one that was removed stays removed (setup.ps1 -Remove).
function Get-AgentsOnDisk($Layouts) {
    return @($Layouts.Keys | Where-Object { Test-LayoutOnDisk $Layouts[$_] })
}

# A path as one comparable string: full, backslashes, no trailing slash, lower
# case. ~/.claude.json writes the project paths with / or \ and any case.
function ConvertTo-ComparablePath([string]$Path) {
    $full = $Path.Replace('/', '\')
    try { $full = [System.IO.Path]::GetFullPath($full) } catch { }
    return $full.TrimEnd('\', '/').ToLowerInvariant()
}

# JSON as nested dictionaries with case-sensitive keys. ConvertFrom-Json makes
# properties, which ignore case: for keys that differ only in case, as the
# project paths in ~/.claude.json can (C:/... and c:/...), Windows PowerShell
# 5.1 throws and PowerShell 7 keeps only the last one. Throws on text that is
# not a JSON object.
function ConvertFrom-JsonCaseSensitive([string]$Text) {
    if ($PSVersionTable.PSVersion.Major -ge 7) {
        $json = $Text | ConvertFrom-Json -AsHashtable
    } else {
        Add-Type -AssemblyName System.Web.Extensions
        $serializer = New-Object System.Web.Script.Serialization.JavaScriptSerializer
        $serializer.MaxJsonLength = [int]::MaxValue
        $json = $serializer.DeserializeObject($Text)
    }
    if (-not ($json -is [System.Collections.IDictionary])) { throw 'not a JSON object' }
    return $json
}

# The personal skills and MCP servers of the agents set up in this clone
# (Get-AgentsOnDisk) that carry the name of a project skill ($SkillManifest) or
# a project MCP server ($McpNames), from the places agents.json "personal"
# lists, as @{ Agent; Kind; Name; Location; Hides }:
#   Kind 'skill'       Name a folder of the personal skills folder Location
#   Kind 'mcp'         Name a server of the file Location (Claude Code: the
#                      entry for $RepoRoot under its per-project key)
#   Kind 'unreadable'  the file Location is not a valid JSON object; Name is $null
# Hides: the personal one wins, as the agent's documentation says or a test
# found (agents.json). A file that is missing or empty is skipped. Only names
# are read: no value of a file is returned. $McpSkip maps a server name to the
# agent keys it is not written for (skipAgents in mcp-servers.json): a personal
# server of that name hides nothing there.
# The roots are parameters so a test can pass temporary ones.
function Get-ShadowingEntries($Layouts, [string]$HomeDir, [string]$AppDataDir, [string]$RepoRoot, $SkillManifest, [string[]]$McpNames, [hashtable]$McpSkip = @{}) {
    $found = @()
    $repoKey = ConvertTo-ComparablePath $RepoRoot
    foreach ($key in @(Get-AgentsOnDisk $Layouts)) {
        $layout = $Layouts[$key]
        foreach ($s in @($layout.PersonalSkills)) {
            $dir = Join-ManifestPath $HomeDir $s.folder
            foreach ($d in @(Get-ChildItem -LiteralPath $dir -Directory -Force -ErrorAction SilentlyContinue)) {
                if (-not $SkillManifest.Skills.Contains($d.Name)) { continue }
                $found += [pscustomobject]@{ Agent = $layout.Name; Kind = 'skill'; Name = $d.Name; Location = $dir; Hides = [bool]$s.hides }
            }
        }
        foreach ($m in @($layout.PersonalMcp)) {
            $root = if ($m.root -eq 'appdata') { $AppDataDir } else { $HomeDir }
            $file = Join-ManifestPath $root $m.file
            if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { continue }
            $names = @()
            try {
                # An agent may create the file empty (Antigravity does): no servers.
                $text = [System.IO.File]::ReadAllText($file)
                if (-not $text.Trim()) { continue }
                $json = ConvertFrom-JsonCaseSensitive $text
                $holders = @($json)
                if ($m.perProject) {
                    $holders = @()
                    $projects = $json[$m.perProject]
                    if ($projects -is [System.Collections.IDictionary]) {
                        foreach ($p in @($projects.Keys)) {
                            if ((ConvertTo-ComparablePath $p) -eq $repoKey) { $holders += , $projects[$p] }
                        }
                    }
                }
                foreach ($h in $holders) {
                    if (($h -is [System.Collections.IDictionary]) -and ($h[$m.key] -is [System.Collections.IDictionary])) { $names += @($h[$m.key].Keys) }
                }
            } catch {
                $found += [pscustomobject]@{ Agent = $layout.Name; Kind = 'unreadable'; Name = $null; Location = $file; Hides = [bool]$m.hides }
                continue
            }
            foreach ($n in $names) {
                if (($McpNames -contains $n) -and -not (@($McpSkip[$n]) -contains $key)) {
                    $found += [pscustomobject]@{ Agent = $layout.Name; Kind = 'mcp'; Name = $n; Location = $file; Hides = [bool]$m.hides }
                }
            }
        }
    }
    return $found
}

# ----------------------------------------------------------------- helpers ---

# A folder given on the command line, made absolute and created; or the default.
function Resolve-Root($path, $default) {
    if (-not $path) { return $default }
    $full = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($path).TrimEnd('\', '/')
    New-Item -ItemType Directory -Force -Path $full | Out-Null
    return $full
}

# Deletes a folder that may hold junctions. Windows PowerShell 5.1's
# Remove-Item -Recurse can follow a junction and empty its target (for example
# ai_tooling/skills), so every reparse point is removed as a link first.
function Remove-FolderSafely($path) {
    if (-not (Get-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue)) { return }
    if ((Get-Item -LiteralPath $path -Force).LinkType) { [System.IO.Directory]::Delete($path); return }
    $pending = New-Object System.Collections.Generic.Stack[string]
    $pending.Push($path)
    while ($pending.Count -gt 0) {
        foreach ($item in Get-ChildItem -LiteralPath $pending.Pop() -Force -Directory) {
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { [System.IO.Directory]::Delete($item.FullName) }
            else { $pending.Push($item.FullName) }
        }
    }
    Remove-Item -LiteralPath $path -Recurse -Force
}

# Runs $Action again while it fails with an access or I/O error, up to
# $RemoveTries times, $RemoveRetryMs apart; then throws that error. Right after
# setup copied a file, something (most likely antivirus: Microsoft Defender's
# real-time protection was on; the holder was not traced) can hold it open for a
# moment, and renaming its folder or deleting it fails with "Access ... denied".
# Seen for skill copies on a developer machine; each time free again at the first retry,
# 50 ms later. A path really in use (an open IDE) costs only these few tries.
$RemoveTries = 4
$RemoveRetryMs = 100
function Invoke-WhileLocked([scriptblock]$Action) {
    for ($try = 1; ; $try++) {
        try { & $Action; return }
        catch {
            $e = $_.Exception
            while ($e.InnerException) { $e = $e.InnerException }
            $locked = (($e -is [System.IO.IOException]) -and -not ($e -is [System.IO.FileNotFoundException]) -and -not ($e -is [System.IO.DirectoryNotFoundException])) -or
                      ($e -is [System.UnauthorizedAccessException])
            if (-not $locked -or $try -ge $RemoveTries) { throw }
            Start-Sleep -Milliseconds $RemoveRetryMs
        }
    }
}

# Removes a file, a folder or a link whole or not at all. Returns $null when the
# path is gone (or was never there), else the problem as text. A folder is first
# renamed to "{name}.removing-{8 hex}", which Windows refuses while any file in
# it is open: a folder in use (for longer than Invoke-WhileLocked waits) is
# reported and left whole, not half deleted.
# A junction is removed as a link, never through its target.
function Remove-PathWhole([string]$Path) {
    # The caller's 'Stop' does not reach into a module function; without it a
    # file in use would be a non-terminating error, and reported as removed.
    $ErrorActionPreference = 'Stop'
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if (-not $item) { return $null }
    $problem = $null
    try {
        if ($item.PSIsContainer -and -not $item.LinkType) {
            $moved = "$Path.removing-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
            Invoke-WhileLocked { [System.IO.Directory]::Move($Path, $moved) }
            Remove-FolderSafely $moved
        } elseif ($item.PSIsContainer) {
            Remove-FolderSafely $Path
        } else {
            Invoke-WhileLocked { Remove-Item -LiteralPath $Path -Force }
        }
    } catch { $problem = $_.Exception.Message.Trim() }
    if (-not $problem -and (Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue)) { $problem = 'still there after removing it' }
    return $problem
}

# One folder as a junction to another, so it exists once on disk; a copy where
# links are not permitted. Either way the result is gitignored.
function New-FolderLink($target, $linkPath) {
    $parent = Split-Path -Parent $linkPath
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
    Remove-FolderSafely $linkPath
    cmd /c mklink /J "$linkPath" "$target" 2>&1 | Out-Null
    if (Test-Path $linkPath) { return 'junction' }
    Copy-Item $target $linkPath -Recurse -Force
    if (Test-Path $linkPath) { return 'copy' }
    return $null
}

# ------------------------------------------------------------ publish skills ---
#
# Every published skill is its own entry in the agent's skills folder: a
# junction to ai_tooling/skills/{group}/{name}, or a copy for agents that do not follow
# a junction inside their skills folder (agents.json skillLinks; Antigravity,
# tested 2026-10-06). A copy carries a marker file, so setup can tell its own
# copies from a developer's own skill folder, which it never touches.

$SkillCopyMarker = '.ai-tooling-setup-copy'

# What setup published as this entry of a skills folder: 'junction' (into
# $SkillsDir; or, for an entry named like a skill in skills.json ($KnownNames),
# into a folder of that name under the skills folder of this clone's earlier
# path or of another clone: a moved or renamed clone would otherwise publish
# nothing), 'copy'
# (with the marker), or $null for anything else, which setup leaves alone.
# A junction into another clone for a skill no longer in skills.json is
# therefore left alone too: it cannot be told from a developer's own link.
function Get-PublishedSkillKind($Item, [string]$SkillsDir, [string[]]$KnownNames = @()) {
    if ($Item.LinkType) {
        $target = ([string](@($Item.Target)[0])).TrimEnd('\')
        if ($target.StartsWith($SkillsDir.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) { return 'junction' }
        $leaf = Split-Path -Leaf $target
        if (($KnownNames -contains $Item.Name) -and ($leaf -eq $Item.Name) -and ($target -match ($ToolingSkillsPattern + '\\'))) { return 'junction' }
        return $null
    }
    if (Test-Path -LiteralPath (Join-Path $Item.FullName $SkillCopyMarker)) { return 'copy' }
    return $null
}

# Publishes $Skills (entries from Read-SkillManifest) into the layout's skills
# folder. Removes what setup published earlier and is no longer chosen
# (including a junction left dangling by a branch switch), refreshes every copy,
# and leaves everything else alone. Returns
# @{ Junctions; Copies; Removed (names); Skipped (names of a developer's own
# folder in the way); Foreign (the target of a junction at the skills folder
# that points somewhere else; then nothing is published there) }. $KnownNames:
# every skill name in skills.json (Get-PublishedSkillKind); by default those
# of $Skills.
function Publish-Skills($Layout, $Skills, [string]$SkillsDir, [string[]]$KnownNames) {
    if (-not $KnownNames) { $KnownNames = @($Skills | ForEach-Object { $_.Name }) }
    $dir = $Layout.Skills
    $result = @{ Junctions = 0; Copies = 0; Removed = @(); Skipped = @(); Foreign = $null }
    $item = Get-Item -LiteralPath $dir -Force -ErrorAction SilentlyContinue
    if ($item -and $item.LinkType) {
        # Writing through a developer's own junction would put the skills into
        # the folder it points to.
        $result.Foreign = [string](@($item.Target)[0])
        return $result
    }
    New-Item -ItemType Directory -Force -Path $dir | Out-Null

    $wanted = @{}
    foreach ($s in $Skills) { $wanted[$s.Name] = $s }

    foreach ($entry in @(Get-ChildItem -LiteralPath $dir -Force -Directory)) {
        $kind = Get-PublishedSkillKind $entry $SkillsDir $KnownNames
        if (-not $kind) { continue }
        $s = $wanted[$entry.Name]
        $current = $s -and ($kind -eq 'junction') -and ($Layout.SkillLinks -eq 'junction') -and
                   ([string](@($entry.Target)[0])).TrimEnd('\') -eq $s.Path.TrimEnd('\')
        if ($current) { continue }
        Remove-FolderSafely $entry.FullName
        if (-not $s) { $result.Removed += $entry.Name }
    }

    foreach ($s in $Skills) {
        $dest = Join-Path $dir $s.Name
        $existing = Get-Item -LiteralPath $dest -Force -ErrorAction SilentlyContinue
        if ($existing) {
            # Only a current junction survived the cleanup above; anything else
            # here is the developer's own.
            if ((Get-PublishedSkillKind $existing $SkillsDir $KnownNames) -eq 'junction') { $result.Junctions++ } else { $result.Skipped += $s.Name }
            continue
        }
        if ($Layout.SkillLinks -eq 'junction') {
            try {
                New-Item -ItemType Junction -Path $dest -Value $s.Path -ErrorAction Stop | Out-Null
                $result.Junctions++
                continue
            } catch { }
        }
        Copy-Item -LiteralPath $s.Path -Destination $dest -Recurse -Force
        Write-Utf8File (Join-Path $dest $SkillCopyMarker) "Copied by ai_tooling/setup.ps1 from $($s.Path). Edit the source; the next run replaces this copy.`n"
        $result.Copies++
    }
    return $result
}

# ---------------------------------------------------------------- profile ---

# The profiles this clone publishes, as saved by the last setup run in
# ai_tooling/localprofile (gitignored), or 'default'.
function Read-LocalProfile([string]$OutRoot) {
    $file = Join-Path (Join-Path $OutRoot $ToolingDirName) 'localprofile'
    if (-not (Test-Path $file)) { return @('default') }
    $names = @(([System.IO.File]::ReadAllText($file)).Trim() -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    if (-not $names) { return @('default') }
    return $names
}

function Write-LocalProfile([string]$OutRoot, [string[]]$Names) {
    $dir = Join-Path $OutRoot $ToolingDirName
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    Write-Utf8File (Join-Path $dir 'localprofile') "$($Names -join ',')`n"
}

# Subagent definitions: a junction like the skills, unless a developer keeps
# personal subagents in a real folder there. Then only the project's files are
# copied in and theirs are left alone (New-FolderLink would delete the folder).
# A real folder is also what a fallback copy leaves behind, so project
# definitions (named with a project prefix: $PrefixPattern, the Pattern of
# Read-ProjectManifest) that no longer exist in the source are removed first;
# otherwise a renamed or deleted one would keep loading.
function New-SubagentsLink($target, $linkPath, [string]$PrefixPattern) {
    $item = if (Test-Path $linkPath) { Get-Item $linkPath -Force } else { $null }
    if (-not $item -or $item.LinkType) { return New-FolderLink $target $linkPath }
    $current = @(Get-ChildItem $target -Filter '*.md' -File)
    Get-ChildItem $linkPath -Filter '*.md' -File | Where-Object {
        ($_.Name -match $PrefixPattern) -and ($current.Name -notcontains $_.Name)
    } | Remove-Item -Force
    foreach ($f in $current) { Copy-Item $f.FullName (Join-Path $linkPath $f.Name) -Force }
    return 'copied into the existing folder'
}

# Process scope first, then User: a variable set with SetEnvironmentVariable(...,
# 'User') is not visible in a console that was already open.
function Get-EnvValue($name) {
    $v = [Environment]::GetEnvironmentVariable($name, 'Process')
    if (-not $v) { $v = [Environment]::GetEnvironmentVariable($name, 'User') }
    return $v
}

# The source's own frontmatter is dropped when an agent needs a different one.
function Remove-Frontmatter($text) {
    if ($text -match '\A---\r?\n(?s:.*?)\r?\n---\r?\n') { return $text.Substring($matches[0].Length).TrimStart("`r", "`n") }
    return $text
}

function Write-Utf8File([string]$path, [string]$text) {
    [System.IO.File]::WriteAllText($path, $text, $Utf8NoBom)
}

# --------------------------------------------------------------- rule files ---
#
# One writer per rule format (agents.json rules.format). Each takes one rule
#   @{ Name; SourceFile; Description; Globs; AlwaysOn; Text; Marker }
# and returns @{ File; Text }: the file name the agent reads and its content.
#   Name        base name ('coding-principles', 'permissions', 'app-backend')
#   SourceFile  the ai_tooling/instructions file it comes from, if any
#   Globs       where it applies, relative to the repository root
#   AlwaysOn    applies in every session (PERMISSIONS.md)
#   Text        the source text, with its own frontmatter if it has one
#   Marker      the "generated" comment put after the new frontmatter

function Format-RuleText($front, $marker, $body) {
    return ((@('---') + $front + @('---', '', $marker, '')) -join "`n") + $body
}

# Copilot reads only *.instructions.md, scoped by applyTo.
function ConvertTo-CopilotRule($Rule) {
    if ($Rule.AlwaysOn) {
        $front = @('applyTo: "**"')
    } else {
        $front = @("description: '$($Rule.Description.Replace("'", "''"))'")
        if ($Rule.Globs) { $front += "applyTo: '$($Rule.Globs -join ',')'" }
    }
    return @{ File = "$($Rule.Name).instructions.md"; Text = Format-RuleText $front $Rule.Marker (Remove-Frontmatter $Rule.Text) }
}

# Cursor reads only *.mdc, scoped by globs. The description is quoted; the
# globs stay unquoted, in the form Cursor's own docs show (a comma-separated
# list), so any glob that unquoted YAML would misread gets a warning instead.
function ConvertTo-CursorRule($Rule) {
    if ($Rule.AlwaysOn) {
        $front = @("description: $($Rule.Description)", 'alwaysApply: true')
    } else {
        foreach ($g in $Rule.Globs) {
            if ($g -match '^[*&!|>%@`]' -or $g -match ': ') { Write-Warning "  glob '$g' for $($Rule.Name) would break Cursor's unquoted YAML - start it with a folder name" }
        }
        $front = @("description: '$($Rule.Description.Replace("'", "''"))'", "globs: $($Rule.Globs -join ', ')", 'alwaysApply: false')
    }
    return @{ File = "$($Rule.Name).mdc"; Text = Format-RuleText $front $Rule.Marker (Remove-Frontmatter $Rule.Text) }
}

# Antigravity takes an instruction file whose own frontmatter has a trigger as it is.
# A scoped rule is written as model_decision, which puts its path and description
# into every prompt for the agent to read on demand: a glob rule never loaded, on a
# read, an edit or an open file (tested 2026-10-21), and a rule without a trigger is not
# even listed (tested 2026-10-21). So an instruction file whose own frontmatter says
# trigger: glob, or has no trigger (the DevExtreme files), is rewritten the same way.
function ConvertTo-AntigravityRule($Rule) {
    if ($Rule.AlwaysOn) {
        return @{ File = "$($Rule.Name).md"; Text = Format-RuleText @('trigger: always_on') $Rule.Marker $Rule.Text }
    }
    $sourceFront = [regex]::Match($Rule.Text, '\A---\r?\n[\s\S]*?\r?\n---').Value
    # The trigger's name, quoted or not; an empty or quoted-empty value counts as none.
    $trigger = ''
    if ($sourceFront -match '(?m)^trigger:[ \t]*[''"]?([A-Za-z_]*)') { $trigger = $Matches[1] }
    if ($Rule.SourceFile -and $trigger -and $trigger -ne 'glob') { return @{ File = $Rule.SourceFile; Text = $Rule.Text } }
    $description = $Rule.Description
    if ($Rule.Globs) { $description += "; read before working on files matching $($Rule.Globs -join ', ')" }
    $front = @("description: '$($description.Replace("'", "''"))'", 'trigger: model_decision')
    $file = if ($Rule.SourceFile) { $Rule.SourceFile } else { "$($Rule.Name).md" }
    return @{ File = $file; Text = Format-RuleText $front $Rule.Marker (Remove-Frontmatter $Rule.Text) }
}

function ConvertTo-Rule([string]$Format, $Rule) {
    switch ($Format) {
        'copilot'     { return ConvertTo-CopilotRule $Rule }
        'cursor'      { return ConvertTo-CursorRule $Rule }
        'antigravity' { return ConvertTo-AntigravityRule $Rule }
        default       { throw "unknown rule format '$Format'" }
    }
}

# The file name a writer gives a rule of this name (also with '*' in it, as a
# pattern for Get-ChildItem -Filter).
function Get-RuleFileName([string]$Format, [string]$Name, [switch]$AlwaysOn) {
    return (ConvertTo-Rule $Format @{ Name = $Name; AlwaysOn = [bool]$AlwaysOn; Description = ''; Globs = @('x'); Text = ''; Marker = '' }).File
}

# The file name pattern a rules folder of this format is read by: anything
# else in there is ignored by the agent.
function Get-RuleFilter([string]$Format) {
    switch ($Format) {
        'copilot'     { return '*.instructions.md' }
        'cursor'      { return '*.mdc' }
        'antigravity' { return '*.md' }
        default       { throw "unknown rule format '$Format'" }
    }
}

# Writes one rule into the layout's rules folder and returns its file name.
function Write-Rule($Layout, $Rule) {
    $r = ConvertTo-Rule $Layout.RuleFormat $Rule
    Write-Utf8File (Join-Path $Layout.Rules $r.File) $r.Text
    return $r.File
}

# ------------------------------------------------------------- MCP servers ---

# Whether JSON text holds a // or /* comment outside its strings (JSONC, as
# Antigravity edits mcp_config.json). PowerShell 7's ConvertFrom-Json accepts
# comments and drops them, Windows PowerShell 5.1's rejects them; setup treats
# such a file the same in both and leaves it alone.
function Test-JsonComment([string]$Text) {
    $inString = $false
    for ($i = 0; $i -lt $Text.Length - 1; $i++) {
        $c = $Text[$i]
        if ($inString) {
            if ($c -eq '\') { $i++ } elseif ($c -eq '"') { $inString = $false }
        } elseif ($c -eq '"') {
            $inString = $true
        } elseif (($c -eq '/') -and (($Text[$i + 1] -eq '/') -or ($Text[$i + 1] -eq '*'))) {
            return $true
        }
    }
    return $false
}

function Write-McpConfig($layout, $servers, $repoRoot) {
    $out = [ordered]@{}
    foreach ($name in $servers.PSObject.Properties.Name) {
        if ($name -eq '$comment') { continue }
        $def = $servers.$name
        if ($def.skipAgents -and ($def.skipAgents -contains $layout.Key)) { continue }

        $entry = [ordered]@{}
        if ($def.transport -eq 'http') {
            if ($layout.HttpType) { $entry['type'] = 'http' }
            $entry[$layout.HttpUrlField] = $def.url
        } else {
            $entry['command'] = $def.command
            $entry['args'] = @($def.args | ForEach-Object { $_.Replace('${REPO_ROOT}', $repoRoot.Replace('\', '/')) })
            # Per-developer opt-ins (see "$envArgs" in mcp-servers.json).
            if ($def.envArgs) {
                foreach ($var in $def.envArgs.PSObject.Properties.Name) {
                    $value = Get-EnvValue $var
                    if ($value) { $entry['args'] += @($def.envArgs.$var | ForEach-Object { $_.Replace('${VALUE}', $value) }) }
                }
            }
        }
        $out[$name] = $entry
    }

    # Preserve anything the developer added by hand that we do not manage: their
    # servers and any other top-level key. A file in the home folder is the
    # agent's own (Antigravity edits it as JSONC), so one with comments or that
    # does not parse is left alone: -1.
    $existing = [ordered]@{}
    $top = [ordered]@{}
    if ((Test-Path $layout.Mcp) -and ((Get-Item $layout.Mcp).Length -gt 0)) {
        $text = [System.IO.File]::ReadAllText($layout.Mcp)
        $parsed = $null
        if ($layout.McpInHome -and (Test-JsonComment $text)) { return -1 }
        try { $parsed = $text | ConvertFrom-Json } catch { }
        if ($parsed -is [System.Management.Automation.PSCustomObject]) {
            # The servers key keeps its place; its value is set below.
            foreach ($prop in $parsed.PSObject.Properties) { $top[$prop.Name] = $prop.Value }
            if ($parsed.($layout.McpKey)) {
                $parsed.($layout.McpKey).PSObject.Properties | ForEach-Object { $existing[$_.Name] = $_.Value }
            }
        } elseif ($layout.McpInHome -and $text.Trim()) {
            return -1
        }
    }
    # Names this script no longer manages: earlier spellings of a server that has
    # since been renamed, or one dropped outright. Empty today - add a name here
    # whenever you rename one in mcp-servers.json, so that everyone's existing
    # config loses the old entry instead of running both.
    #
    # Keep this BEFORE the merge. An OrderedDictionary matches keys
    # case-insensitively, so merging first would write the new value under the
    # old spelling ('DevExtreme' rather than 'devextreme') and this line would
    # then delete the server outright.
    foreach ($stale in @()) { $existing.Remove($stale) }
    foreach ($k in $out.Keys) { $existing[$k] = $out[$k] }

    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $layout.Mcp) | Out-Null
    $top[$layout.McpKey] = $existing
    $json = $top | ConvertTo-Json -Depth 8
    Write-Utf8File $layout.Mcp $json
    return $out.Count
}

# An MCP config file without the servers setup writes for $Layout (every other
# server and key stays), as @{ Valid; Changed; Left; Named }: Valid is false for
# a file that is not a JSON object or has comments (Test-JsonComment), and Named
# then lists the project servers its text names in quotes, which it may still
# hold; Changed whether a server was taken out, Left the remaining top-level
# keys (empty when nothing else is in the file). An empty file is valid,
# unchanged, with nothing left.
function Get-McpConfigWithoutProject([string]$File, $Layout, $Servers) {
    $text = [System.IO.File]::ReadAllText($File)
    $parsed = $null
    # Properties, not Properties.Name: an empty servers object would give one $null.
    $managed = @($Servers.PSObject.Properties | ForEach-Object { $_.Name } | Where-Object {
        ($_ -ne '$comment') -and -not ($Servers.$_.skipAgents -and ($Servers.$_.skipAgents -contains $Layout.Key))
    })
    $invalid = @{ Valid = $false; Named = @($managed | Where-Object { $text.Contains('"' + $_ + '"') }) }
    if (Test-JsonComment $text) { return $invalid }
    if ($text.Trim()) {
        try { $parsed = $text | ConvertFrom-Json } catch { return $invalid }
        if (-not ($parsed -is [System.Management.Automation.PSCustomObject])) { return $invalid }
    }
    $left = [ordered]@{}
    $changed = $false
    if ($parsed) {
        foreach ($prop in $parsed.PSObject.Properties) {
            if (($prop.Name -ne $Layout.McpKey) -or -not ($prop.Value -is [System.Management.Automation.PSCustomObject])) {
                $left[$prop.Name] = $prop.Value
                continue
            }
            $others = [ordered]@{}
            foreach ($s in $prop.Value.PSObject.Properties) {
                if ($managed -contains $s.Name) { $changed = $true } else { $others[$s.Name] = $s.Value }
            }
            if ($others.Count) { $left[$prop.Name] = $others }
        }
    }
    return @{ Valid = $true; Changed = $changed; Left = $left }
}

# Takes the project's servers out of the MCP config files earlier versions of
# setup wrote for $Layout (mcp.legacyFiles in agents.json), so they do not
# linger there, or hide this clone's own (Antigravity's global file wins over
# the workspace file on a name clash). A file left with nothing in it is
# deleted; one setup did not write servers into, or that is not valid JSON, is
# left alone, and so is one in use (a warning; the next run tries again).
# Returns the files it changed.
function Clear-LegacyMcpConfigs($Layout, $Servers) {
    $cleared = @()
    foreach ($file in @($Layout.McpLegacy)) {
        if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { continue }
        try {
            $r = Get-McpConfigWithoutProject $file $Layout $Servers
            if ($r.Named) {
                Write-Host "  WARN $file has comments or is not valid JSON, and names $($r.Named -join ', '): left alone; take the project's servers out by hand"
            }
            if (-not ($r.Valid -and $r.Changed)) { continue }
            Add-McpKeepValidKey $Layout $file $r.Left
            if ($r.Left.Count) { Write-Utf8File $file ($r.Left | ConvertTo-Json -Depth 8) }
            else { Remove-Item -LiteralPath $file -Force -ErrorAction Stop }
            $cleared += $file
        } catch {
            Write-Host "  WARN could not take the project's MCP servers out of $file ($($_.Exception.Message)); the next setup.ps1 run tries again"
        }
    }
    return $cleared
}

# A file in mcp.keepValid keeps its servers key, empty if need be, instead of
# being deleted: the agent recreates a deleted one empty and then loads no MCP
# server at all (seen with Antigravity 2.24.0, 2026-10-20). $Left is Get-McpConfigWithoutProject's.
function Add-McpKeepValidKey($Layout, [string]$File, $Left) {
    if ((@($Layout.McpKeepValid) -contains $File) -and -not $Left.Contains($Layout.McpKey)) { $Left[$Layout.McpKey] = [ordered]@{} }
}

# Writes an empty server list into each file of mcp.keepValid that is missing
# or empty: while its global file was empty, Antigravity 2.24.0 loaded no MCP
# server at all, not even the workspace file's, and it recreated that file
# empty when it was missing (2026-10-20).
# A file with content is left to Clear-LegacyMcpConfigs. Returns the files it wrote.
function Repair-McpKeepValid($Layout) {
    $written = @()
    foreach ($file in @($Layout.McpKeepValid)) {
        if ((Test-Path -LiteralPath $file -PathType Leaf) -and [System.IO.File]::ReadAllText($file).Trim()) { continue }
        try {
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $file) | Out-Null
            Write-Utf8File $file ([ordered]@{ ($Layout.McpKey) = [ordered]@{} } | ConvertTo-Json -Depth 8)
            $written += $file
        } catch {
            Write-Host "  WARN could not write an empty server list to $file ($($_.Exception.Message)); the next setup.ps1 run tries again"
        }
    }
    return $written
}

# --------------------------------------------------------- publish a layout ---

# The rules setup writes into the layout's rules folder, as the rule hashtables
# Write-Rule takes: @{ Instructions; Apps; Permissions }. Instructions and Apps
# are lists, Permissions is one rule or $null; each is empty where the agent
# gets that content another way (Publishes* in Get-AgentLayout). An instruction
# file without an entry in instructions.json gets NoMeta = $true. Publish-AgentLayout
# writes these and Remove-AgentLayout removes them, so both name the same files.
function Get-LayoutRules($Layout, $Sources) {
    $marker = "<!-- Generated by $ToolingDirName/setup.ps1. Edit the source, not this copy. -->"
    $r = @{ Instructions = @(); Apps = @(); Permissions = $null }
    if ($Layout.PublishesInstructions) {
        foreach ($f in @(Get-ChildItem $Sources.Instructions -Filter *.md -File)) {
            $meta = $Sources.InstrMeta[$f.Name]
            $noMeta = -not $meta
            if ($noMeta) { $meta = @{ Globs = @(); Description = $f.BaseName } }
            $r.Instructions += @{
                Name        = $f.Name -replace '(\.instructions)?\.md$', ''
                SourceFile  = $f.Name
                Description = $meta.Description
                Globs       = $meta.Globs
                Text        = [System.IO.File]::ReadAllText($f.FullName)
                Marker      = $marker
                NoMeta      = $noMeta
            }
        }
    }
    if ($Layout.PublishesAppRules) {
        foreach ($app in $Sources.AppDirs) {
            $name = Split-Path -Leaf $app
            $r.Apps += @{
                Name        = "app-$name"
                Description = "Rules for $name"
                Globs       = @("$name/**")
                Text        = "This is ``$name/AGENTS.md``, published for this agent by ``$ToolingDirName/setup.ps1``. Paths in it are relative to ``$name/``.`n`n" +
                              [System.IO.File]::ReadAllText((Join-Path $app 'AGENTS.md'))
                Marker      = $marker
            }
        }
    }
    if ($Layout.PublishesPermissions) {
        $r.Permissions = @{
            Name        = 'permissions'
            Description = 'What an agent may do without asking in this repository'
            AlwaysOn    = $true
            Text        = [System.IO.File]::ReadAllText($Sources.Permissions)
            Marker      = "<!-- Generated by $ToolingDirName/setup.ps1 from PERMISSIONS.md. Edit that file, not this copy. -->"
        }
    }
    return $r
}

# Writes everything one agent gets: skills, subagents, rules, pointer file,
# stubs, MCP config. $Sources: @{ RepoRoot; OutRoot; HomeDir; SkillsDir;
# Skills (the chosen entries from Read-SkillManifest); AllSkillNames (every
# skill in skills.json); Subagents;
# Instructions; InstructionManifest; Permissions; ExternalSkillConfig; AppDirs;
# InstrMeta; ServersFile; Servers } (Get-SetupSources).
function Publish-AgentLayout($Layout, $Sources) {
    $OutRoot = $Sources.OutRoot
    $shown = { param($p) $p.Replace("$OutRoot\", '') }
    Write-Host "$($Layout.Name)"

    $r = Publish-Skills $Layout $Sources.Skills $Sources.SkillsDir $Sources.AllSkillNames
    if ($r.Foreign) {
        Write-Warning "  $(& $shown $Layout.Skills) is a junction to $($r.Foreign), not written by setup.ps1 - left alone, so no skills are published there; remove the junction to get them"
    }
    $how = @()
    if ($r.Junctions) { $how += "$($r.Junctions) junctions" }
    if ($r.Copies) { $how += "$($r.Copies) copies" }
    Write-Host "  OK  skills -> $(& $shown $Layout.Skills) ($(if ($how) { $how -join ', ' } else { 'none' }))"
    if ($r.Removed) {
        Write-Host "  OK  removed $($r.Removed.Count) skills no longer published: $($r.Removed -join ', ')"
    }
    if ($r.Skipped) {
        Write-Warning ("  $(& $shown $Layout.Skills) holds folders setup.ps1 did not write, named like project skills: " +
            "$($r.Skipped -join ', '). They were left alone, so those project skills are not published there; delete the folders to get them.")
    }

    if ($Layout.Subagents) {
        $how = New-SubagentsLink $Sources.Subagents $Layout.Subagents $Sources.Project.Pattern
        if ($how) { Write-Host "  OK  subagents -> $(& $shown $Layout.Subagents) ($how)" }
        else { Write-Warning "  could not create $($Layout.Subagents)" }
    }

    if ($Layout.Rules) {
        New-Item -ItemType Directory -Force -Path $Layout.Rules | Out-Null
        $rulesShown = & $shown $Layout.Rules
        foreach ($stale in $Layout.StaleRules) {
            $p = Join-Path $Layout.Rules $stale
            if (Test-Path $p) { Remove-Item $p -Force; Write-Host "  OK  removed stale $rulesShown\$stale (a name the agent ignores)" }
        }
    }

    $rules = Get-LayoutRules $Layout $Sources
    if ($Layout.PublishesInstructions) {
        foreach ($rule in $rules.Instructions) {
            if ($rule.NoMeta) {
                Write-Warning "  $($rule.SourceFile) has no entry in ai_tooling/manifest/instructions.json - published as on-demand only; add its globs there"
            }
            Write-Rule $Layout $rule | Out-Null
        }
        Write-Host "  OK  instructions -> $rulesShown ($(@($rules.Instructions).Count) files)"
    } else {
        Write-Host "  --  instructions: read via the imports in AGENTS.md"
    }

    # Each app's AGENTS.md as a rule scoped to that app's folder, for agents
    # that do not get nested AGENTS.md files otherwise.
    if ($Layout.PublishesAppRules) {
        # A rule for an app that no longer exists would keep applying to nothing.
        $appNames = @($Sources.AppDirs | ForEach-Object { Split-Path -Leaf $_ })
        # The writer's file name for 'app-*', e.g. 'app-*.instructions.md'.
        $pattern = Get-RuleFileName $Layout.RuleFormat 'app-*'
        $suffix = $pattern.Substring('app-*'.Length)
        Get-ChildItem $Layout.Rules -Filter $pattern -File -ErrorAction SilentlyContinue | ForEach-Object {
            $appName = $_.Name.Substring(4, $_.Name.Length - 4 - $suffix.Length)
            if ($appNames -notcontains $appName) { Remove-Item $_.FullName -Force; Write-Host "  OK  removed $rulesShown\$($_.Name) (app no longer exists)" }
        }
        foreach ($rule in $rules.Apps) { Write-Rule $Layout $rule | Out-Null }
        Write-Host "  OK  app rules -> $rulesShown ($($Sources.AppDirs.Count) apps, each scoped to its folder)"
    }

    # A file the agent reads by itself, pointing it to AGENTS.md and
    # PERMISSIONS.md. Left alone if someone else wrote it.
    if ($Layout.PointerFile) {
        $pf = $Layout.PointerFile
        $pfShown = & $shown $pf
        $marker = "<!-- Generated by $ToolingDirName/setup.ps1"
        $existing = if (Test-Path $pf) { "$(Get-Content $pf -Raw)" } else { $null }
        if (($null -ne $existing) -and -not ($existing -like "*$marker*")) {
            Write-Host "  WARN $pfShown exists but was not written by setup.ps1 - left alone"
        } else {
            $up = '../' * ($pfShown.Split('\').Count - 1)
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $pf) | Out-Null
            Write-Utf8File $pf ("$marker. Edit AGENTS.md, not this file. -->`n`n" +
                "Before doing anything else, read and follow [AGENTS.md](${up}AGENTS.md) at the repository root and [PERMISSIONS.md](${up}$ToolingDirName/PERMISSIONS.md).`n" +
                "When working in an app folder, that app's ``AGENTS.md`` applies as well.`n")
            Write-Host "  OK  $pfShown (points to AGENTS.md and PERMISSIONS.md)"
        }
    }
    foreach ($legacy in $Layout.LegacyFiles) {
        $p = Join-ManifestPath $OutRoot $legacy.file
        if ((Test-Path $p) -and ((Get-Content $p -Raw).Trim() -eq $legacy.content)) {
            Remove-Item $p -Force
            Write-Host "  OK  removed $($legacy.file) (written by an earlier setup.ps1; the agent never read it)"
        }
    }

    # PERMISSIONS.md must reach every agent in every session. Agents that do not
    # follow the @PERMISSIONS.md import in AGENTS.md get it as an always-on rule.
    if ($Layout.PublishesPermissions) {
        $file = Write-Rule $Layout $rules.Permissions
        Write-Host "  OK  permissions -> $rulesShown\$file (always on)"
    } else {
        Write-Host "  --  permissions: read via the @PERMISSIONS.md import in AGENTS.md"
    }

    # Agents that read their own instruction file, not AGENTS.md - Claude Code
    # reads CLAUDE.md only. These stubs are one import line each, are gitignored
    # by repo convention, and are what makes AGENTS.md reach the agent at all.
    # Every app folder with its own AGENTS.md gets one too, or the app's rules
    # (and the instruction files it imports) never load.
    if ($Layout.Stub) {
        $stubDirs = @($OutRoot)
        if ($Layout.AppStubs) { $stubDirs += @($Sources.AppDirs | ForEach-Object { Join-Path $OutRoot (Split-Path -Leaf $_) }) }
        foreach ($dir in $stubDirs) {
            New-Item -ItemType Directory -Force -Path $dir | Out-Null
            $stubPath = Join-Path $dir $Layout.Stub
            $stubShown = & $shown $stubPath
            if (-not (Test-Path $stubPath)) {
                Write-Utf8File $stubPath "@AGENTS.md`n"
                Write-Host "  OK  $stubShown created (imports AGENTS.md)"
            } elseif ((Get-Content $stubPath -Raw) -notmatch '@AGENTS\.md') {
                Write-Host "  WARN $stubShown exists but does not import AGENTS.md"
            } else {
                Write-Host "  OK  $stubShown already imports AGENTS.md"
            }
        }
    }

    $count = Write-McpConfig $Layout $Sources.Servers $Sources.RepoRoot
    $mcpShown = (& $shown $Layout.Mcp).Replace($Sources.HomeDir, '~')
    if ($count -lt 0) {
        Write-Host "  WARN $mcpShown has comments or is not valid JSON - left alone, no MCP servers written; fix it and re-run setup.ps1"
    } else {
        Write-Host "  OK  MCP -> $mcpShown ($count servers)"
    }
    foreach ($f in @(Clear-LegacyMcpConfigs $Layout $Sources.Servers)) {
        Write-Host "  OK  removed the project's MCP servers from $((& $shown $f).Replace($Sources.HomeDir, '~')) (written by an earlier setup.ps1)"
    }
    foreach ($f in @(Repair-McpKeepValid $Layout)) {
        Write-Host "  OK  wrote an empty server list to $((& $shown $f).Replace($Sources.HomeDir, '~')) ($($Layout.Name) loads no MCP server while it is missing or empty)"
    }
    Write-Host ""
}

# ---------------------------------------------------------- setup version ---

# Records ai_tooling/version in ai_tooling/localversion under $OutRoot, so the session-start
# check in AGENTS.md stops prompting. Only for a complete run: every agent
# layout already on disk was refreshed in this run ($Agent; a partial -Agent
# run leaves the others stale).
# Line endings differ per clone (core.autocrlf) and a hand edit may add a BOM
# or spaces, so read leniently and always write one form: digits, LF, no BOM.
# Returns the number it recorded, or nothing when it recorded none.
function Write-LocalVersion([string]$AiDir, [string]$OutRoot, [string[]]$Agent, $Layouts) {
    $versionSrc = Join-Path $AiDir 'version'
    if (-not (Test-Path $versionSrc)) { return }
    Write-Host ""
    $version = ([System.IO.File]::ReadAllText($versionSrc)).Trim()
    if ($version -notmatch '^\d+$') {
        Write-Warning "ai_tooling/version holds '$version', not a whole number - ai_tooling/localversion left unchanged"
        return
    }
    $skipped = @($Layouts.Keys | Where-Object { ($Agent -notcontains $_) -and (Test-LayoutOnDisk $Layouts[$_]) })
    if ($skipped) {
        Write-Host "Setup version not recorded: the layouts for $($skipped -join ', ') are on disk but were not"
        Write-Host "refreshed in this run. Run .\ai_tooling\setup.ps1 without -Agent to refresh them all."
        return
    }
    $localDir = Join-Path $OutRoot $ToolingDirName
    New-Item -ItemType Directory -Force -Path $localDir | Out-Null
    Write-Utf8File (Join-Path $localDir 'localversion') "$([int]$version)`n"
    Write-Host "Setup version $([int]$version) recorded in ai_tooling/localversion"
    return [int]$version
}

# The number in ai_tooling/localversion under $OutRoot, read leniently (BOM,
# CRLF, spaces) as Write-LocalVersion reads version; nothing when it is missing
# or not a number.
# setup.ps1 reads it before the run, for Write-WhatsNew.
function Read-LocalVersion([string]$OutRoot) {
    $file = Join-Path (Join-Path $OutRoot $ToolingDirName) 'localversion'
    if (-not (Test-Path $file)) { return }
    $text = ([System.IO.File]::ReadAllText($file)).Trim([char]0xFEFF, ' ', "`t", "`r", "`n")
    if ($text -match '^\d+$') { return [int]$text }
}

# The entries of CHANGELOG.md with $After < version <= $UpTo, newest first, each
# from its '## {version}' heading to the next heading, LF line endings, without
# trailing blank lines. Without $After (no localversion yet) only the newest
# entry up to $UpTo, as the session-start check in AGENTS.md shows it.
function Get-ChangelogEntries([string]$ChangelogPath, $After, [int]$UpTo) {
    if (-not (Test-Path $ChangelogPath)) { return }
    $text = ([System.IO.File]::ReadAllText($ChangelogPath)) -replace "`r`n", "`n"
    $entries = @()
    foreach ($part in @($text -split '(?m)^(?=## )' | Where-Object { $_ -match '^## (\d+)\b' })) {
        $version = [int]([regex]::Match($part, '^## (\d+)').Groups[1].Value)
        if ($version -le $UpTo -and ($null -eq $After -or $version -gt [int]$After)) {
            $entries += [pscustomobject]@{ Version = $version; Text = $part.TrimEnd("`n") }
        }
    }
    $entries = @($entries | Sort-Object Version -Descending)
    if ($null -eq $After) { $entries = @($entries | Select-Object -First 1) }
    foreach ($e in $entries) { $e.Text }
}

# Prints the CHANGELOG.md entries this run installed: those after the
# localversion read before the run ($Previous) up to the version it recorded
# ($Current). Nothing when the run recorded no version or nothing is newer.
# The agent that ran setup shows this section to the user (root AGENTS.md).
function Write-WhatsNew([string]$AiDir, $Previous, $Current) {
    if ($null -eq $Current) { return }
    $entries = @(Get-ChangelogEntries (Join-Path $AiDir 'CHANGELOG.md') $Previous $Current)
    if (-not $entries) { return }
    Write-Host ""
    if ($null -eq $Previous) {
        Write-Host "What's new in setup version $Current (ai_tooling/CHANGELOG.md)"
    } else {
        Write-Host "What's new since setup version $Previous (ai_tooling/CHANGELOG.md)"
    }
    foreach ($entry in $entries) {
        Write-Host ""
        Write-Host $entry
    }
}

# --------------------------------------------------------- copied sources ---
#
# A copy is a snapshot: it goes stale when its source changes (an edit, a pull,
# a branch switch) until setup runs again, and the version check does not see
# that. setup.ps1 records a SHA-256 of every source it copied, or generated a
# file from, per agent, in ai_tooling/localsources.json (gitignored);
# verify-agent-setup.ps1 -Quick compares them with the working tree. Junctions
# and imports are live and are not recorded.

$LocalSourcesName = 'localsources.json'

# What setup publishes from, as setup.ps1 hands it to Publish-AgentLayout:
# @{ RepoRoot; OutRoot; HomeDir; SkillsDir; Skills (the entries of $SkillNames,
# from Resolve-SkillProfile); AllSkillNames; Subagents; Instructions;
# InstructionManifest; Permissions; ExternalSkillConfig; AppDirs; InstrMeta;
# ServersFile; Servers; Project (Read-ProjectManifest) }. verify-agent-setup.ps1
# builds the same, so both look at the same sources.
function Get-SetupSources([string]$AiDir, [string]$OutRoot, [string]$HomeDir, $SkillManifest, [string[]]$SkillNames) {
    $repoRoot = Split-Path -Parent $AiDir
    # Top-level app folders that carry their own AGENTS.md.
    $appDirs = @(Get-ChildItem $repoRoot -Directory | Where-Object { Test-Path (Join-Path $_.FullName 'AGENTS.md') } | ForEach-Object { $_.FullName })
    $serversFile = Join-Path $AiDir 'mcp-servers.json'
    return @{
        RepoRoot            = $repoRoot
        OutRoot             = $OutRoot
        HomeDir             = $HomeDir
        SkillsDir           = Join-Path $AiDir 'skills'
        Skills              = @($SkillNames | ForEach-Object { $SkillManifest.Skills[$_] })
        AllSkillNames       = @($SkillManifest.Skills.Keys)
        Subagents           = Join-Path $AiDir 'agents'
        Instructions        = Join-Path $AiDir 'instructions'
        InstructionManifest = Join-Path $AiDir 'manifest\instructions.json'
        Permissions         = Join-Path $AiDir 'PERMISSIONS.md'
        ExternalSkillConfig = Join-Path $AiDir 'external-skill-config'
        AppDirs             = $appDirs
        InstrMeta           = Read-InstructionManifest $AiDir @($appDirs | ForEach-Object { Split-Path -Leaf $_ })
        ServersFile         = $serversFile
        Servers             = (Get-Content $serversFile -Raw | ConvertFrom-Json).servers
        Project             = Read-ProjectManifest $AiDir
    }
}

# SHA-256 of a file, or of a folder (every file's relative path and hash, in
# ordinal order; setup's copy marker aside), as lowercase hex. $null when it
# does not exist. The bytes as they are on disk: a line-ending change counts.
function Get-SourceHash([string]$Path) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hex = { param($bytes) ([System.BitConverter]::ToString($sha.ComputeHash([byte[]]$bytes))).Replace('-', '').ToLowerInvariant() }
        if (Test-Path -LiteralPath $Path -PathType Leaf) { return & $hex ([System.IO.File]::ReadAllBytes($Path)) }
        if (-not (Test-Path -LiteralPath $Path -PathType Container)) { return $null }
        $len = $Path.TrimEnd('\').Length + 1
        $lines = [string[]]@(Get-ChildItem -LiteralPath $Path -Recurse -File -Force | Where-Object { $_.Name -ne $SkillCopyMarker } | ForEach-Object {
            "$($_.FullName.Substring($len).Replace('\', '/')) $(& $hex ([System.IO.File]::ReadAllBytes($_.FullName)))"
        })
        [Array]::Sort($lines, [StringComparer]::Ordinal)
        return & $hex ($Utf8NoBom.GetBytes($lines -join "`n"))
    } finally { $sha.Dispose() }
}

# Every source setup copies, or generates a file from, for this layout, in
# ordinal order: repository-relative path with forward slashes -> full path.
# The skill folders of an agent that gets copies, and of one whose junction
# fell back to a copy; the subagent definitions where the subagents folder is
# a real folder (a developer's own, or the fallback copy); PERMISSIONS.md, the
# instruction files and the app AGENTS.md files where they become rules
# (instructions.json gives the descriptions and globs, and the app folders those
# of an allApps file: an app folder, named with a trailing '/', counts by its
# presence only);
# external-skill-config (the docs/agents copies every agent's Matt Pocock
# skills read); mcp-servers.json (the generated MCP config).
function Get-CopiedSources($Layout, $Sources) {
    $root = $Sources.RepoRoot.TrimEnd('\')
    $paths = @()
    foreach ($s in $Sources.Skills) {
        $copy = Join-Path (Join-Path $Layout.Skills $s.Name) $SkillCopyMarker
        if (($Layout.SkillLinks -eq 'copy') -or (Test-Path -LiteralPath $copy)) { $paths += $s.Path }
    }
    if ($Layout.Subagents) {
        $item = Get-Item -LiteralPath $Layout.Subagents -Force -ErrorAction SilentlyContinue
        if ($item -and -not $item.LinkType) { $paths += @(Get-ChildItem $Sources.Subagents -Filter '*.md' -File | ForEach-Object { $_.FullName }) }
    }
    if ($Layout.PublishesPermissions) { $paths += $Sources.Permissions }
    if ($Layout.PublishesInstructions) {
        $paths += @(Get-ChildItem $Sources.Instructions -Filter '*.md' -File | ForEach-Object { $_.FullName })
        $paths += $Sources.InstructionManifest
        $paths += @($Sources.AppDirs | ForEach-Object { $_.TrimEnd('\') + '\' })
    }
    if ($Layout.PublishesAppRules) { $paths += @($Sources.AppDirs | ForEach-Object { Join-Path $_ 'AGENTS.md' }) }
    $paths += @(Get-ChildItem $Sources.ExternalSkillConfig -Filter '*.md' -File -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
    $paths += $Sources.ServersFile

    $byName = @{}
    foreach ($p in $paths) { $byName[$p.Substring($root.Length + 1).Replace('\', '/')] = $p }
    $names = [string[]]@($byName.Keys)
    [Array]::Sort($names, [StringComparer]::Ordinal)
    $map = [ordered]@{}
    foreach ($n in $names) { $map[$n] = $byName[$n] }
    return $map
}

# What localsources.json records for one source of Get-CopiedSources: its
# hash, or 'present' for an app folder (a name with a trailing '/').
function Get-CopiedSourceHash([string]$Name, [string]$Path) {
    if ($Name.EndsWith('/')) { return 'present' }
    return Get-SourceHash $Path
}

# The recorded hashes in $OutRoot/ai_tooling/localsources.json:
# agent key -> (source -> hash). Empty when the file is missing, empty or
# not of that shape; an agent whose entry is not of that shape is left out.
# Either way the next setup run writes it anew.
function Read-LocalSources([string]$OutRoot) {
    $file = Join-Path (Join-Path $OutRoot $ToolingDirName) $LocalSourcesName
    $record = @{}
    if (-not (Test-Path -LiteralPath $file)) { return $record }
    $json = $null
    try { $json = [System.IO.File]::ReadAllText($file) | ConvertFrom-Json } catch { return $record }
    # The type ConvertFrom-Json gives a JSON object; [pscustomobject] would
    # match a wrapped string or array too.
    $object = [System.Management.Automation.PSCustomObject]
    if (-not ($json -is $object) -or -not ($json.agents -is $object)) { return $record }
    foreach ($a in @($json.agents.PSObject.Properties)) {
        if (-not ($a.Value -is $object)) { continue }
        $hashes = @{}
        foreach ($s in @($a.Value.PSObject.Properties)) { $hashes[$s.Name] = [string]$s.Value }
        $record[$a.Name] = $hashes
    }
    return $record
}

# Records what each agent of $Agent got as a copy, with the hash its source
# has now, and keeps the record of every other agent (a run with -Agent
# refreshes only those). docs/agents is shared and every run rewrites it,
# so the external-skill-config sources are refreshed in every agent's record.
# Written as UTF-8 without a BOM, agents in manifest order, sources in
# ordinal order.
function Write-LocalSources([string]$OutRoot, [string[]]$Agent, $Layouts, $Sources) {
    $record = Read-LocalSources $OutRoot
    $cache = @{}
    foreach ($key in $Agent) {
        $hashes = @{}
        $copied = Get-CopiedSources $Layouts[$key] $Sources
        foreach ($name in $copied.Keys) {
            if (-not $cache.ContainsKey($name)) { $cache[$name] = Get-CopiedSourceHash $name $copied[$name] }
            $hashes[$name] = $cache[$name]
        }
        $record[$key] = $hashes
    }
    # Keys built as Get-CopiedSources builds them (from each file's FullName),
    # and old ones matched by their last two segments, so a root written in
    # another form (an 8.3 short name) cannot leave stale entries behind.
    $root = $Sources.RepoRoot.TrimEnd('\')
    $sharedPattern = '(^|/)' + [regex]::Escape((Split-Path -Leaf (Split-Path -Parent $Sources.ExternalSkillConfig))) +
                     '/' + [regex]::Escape((Split-Path -Leaf $Sources.ExternalSkillConfig)) + '/[^/]+$'
    $sharedNow = @{}
    foreach ($f in @(Get-ChildItem $Sources.ExternalSkillConfig -Filter '*.md' -File -ErrorAction SilentlyContinue)) {
        $sharedNow[$f.FullName.Substring($root.Length + 1).Replace('\', '/')] = Get-SourceHash $f.FullName
    }
    foreach ($key in @($record.Keys | Where-Object { $Agent -notcontains $_ })) {
        foreach ($name in @($record[$key].Keys | Where-Object { $_ -match $sharedPattern })) { $record[$key].Remove($name) }
        foreach ($name in $sharedNow.Keys) { $record[$key][$name] = $sharedNow[$name] }
    }
    Write-LocalSourcesFile $OutRoot $record @($Layouts.Keys)
}

# Writes the record (agent key -> (source -> hash)) as localsources.json: the
# agents of $KeyOrder that have an entry, in that order, sources in ordinal order.
function Write-LocalSourcesFile([string]$OutRoot, $Record, [string[]]$KeyOrder) {
    $agents = [ordered]@{}
    foreach ($key in $KeyOrder) {
        if (-not $Record.ContainsKey($key)) { continue }
        $names = [string[]]@($Record[$key].Keys)
        [Array]::Sort($names, [StringComparer]::Ordinal)
        $sorted = [ordered]@{}
        foreach ($n in $names) { $sorted[$n] = $Record[$key][$n] }
        $agents[$key] = $sorted
    }
    $dir = Join-Path $OutRoot $ToolingDirName
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $json = [ordered]@{
        '$comment' = 'Generated by ai_tooling/setup.ps1: the SHA-256 of every source each agent got as a copy. verify-agent-setup.ps1 -Quick compares them with the working tree.'
        agents     = $agents
    } | ConvertTo-Json -Depth 4
    Write-Utf8File (Join-Path $dir $LocalSourcesName) $json
}

# Drops one agent's entry from localsources.json (setup.ps1 -Remove), keeping
# the other entries and the order of the file. Nothing happens without the file
# or without that entry.
function Remove-LocalSourcesEntry([string]$OutRoot, [string]$AgentKey) {
    $record = Read-LocalSources $OutRoot
    if (-not $record.ContainsKey($AgentKey)) { return }
    $file = Join-Path (Join-Path $OutRoot $ToolingDirName) $LocalSourcesName
    $order = @(([System.IO.File]::ReadAllText($file) | ConvertFrom-Json).agents.PSObject.Properties.Name)
    $record.Remove($AgentKey)
    Write-LocalSourcesFile $OutRoot $record $order
}

# For every agent whose layout is on disk (Test-LayoutOnDisk), what
# setup would copy now against what it recorded: @{ Key; Name; Recorded (the
# agent has a record); Count (sources copied now); Changed (hash differs);
# Added (copied now, not recorded: a new skill, instruction file or app);
# Removed (recorded, not copied now) }, names sorted.
function Test-LocalSources([string]$OutRoot, $Layouts, $Sources) {
    $record = Read-LocalSources $OutRoot
    $cache = @{}
    $results = @()
    foreach ($key in $Layouts.Keys) {
        $layout = $Layouts[$key]
        if (-not (Test-LayoutOnDisk $layout)) { continue }
        $now = Get-CopiedSources $layout $Sources
        $r = [pscustomobject]@{ Key = $key; Name = $layout.Name; Recorded = $record.ContainsKey($key); Count = $now.Count; Changed = @(); Added = @(); Removed = @() }
        if ($r.Recorded) {
            $was = $record[$key]
            foreach ($name in $now.Keys) {
                if (-not $was.ContainsKey($name)) { $r.Added += $name; continue }
                if (-not $cache.ContainsKey($name)) { $cache[$name] = Get-CopiedSourceHash $name $now[$name] }
                if ($cache[$name] -ne $was[$name]) { $r.Changed += $name }
            }
            $r.Removed = @($was.Keys | Where-Object { -not $now.Contains($_) } | Sort-Object)
        }
        $results += $r
    }
    return $results
}

# ------------------------------------------------ external skill config ---

# The upstream Matt Pocock skills read their configuration from docs/agents/ at
# the repository root, a path they hard-code. The source is
# ai_tooling/external-skill-config/; this writes a marked copy of each
# file into $OutRoot/docs/agents/ (gitignored), removes a copy whose source is
# gone, and leaves any other file there alone. Agent-independent: every run
# writes it. Returns the number of files written.
function Publish-ExternalSkillConfig([string]$SourceDir, [string]$OutRoot) {
    $dest = Join-Path $OutRoot 'docs\agents'
    $marker = "<!-- Generated by $ToolingDirName/setup.ps1 from $ToolingDirName/external-skill-config/"
    $sources = @(Get-ChildItem -LiteralPath $SourceDir -Filter '*.md' -File -ErrorAction SilentlyContinue)
    # A project without external skill configuration gets no docs/agents/.
    if (-not $sources -and -not (Test-Path -LiteralPath $dest)) { return 0 }
    New-Item -ItemType Directory -Force -Path $dest | Out-Null
    foreach ($f in @(Get-ChildItem -LiteralPath $dest -File -ErrorAction SilentlyContinue)) {
        if ($sources.Name -contains $f.Name) { continue }
        if ([System.IO.File]::ReadAllText($f.FullName).StartsWith($marker)) {
            Remove-Item -LiteralPath $f.FullName -Force
            Write-Host "  OK  removed docs\agents\$($f.Name) (its source is gone)"
        }
    }
    foreach ($f in $sources) {
        $text = [System.IO.File]::ReadAllText($f.FullName)
        Write-Utf8File (Join-Path $dest $f.Name) ("$marker$($f.Name). Edit that file, not this copy. -->`n`n" + $text)
    }
    return $sources.Count
}

# ----------------------------------------------------------- remove a layout ---

# The comment setup puts into every file it generates (rules, pointer file).
$GeneratedMarkerPattern = 'Generated by ' + [regex]::Escape("$ToolingDirName/setup.ps1")

# A path as Remove-AgentLayout reports it: relative to $OutRoot, or ~\... under
# $HomeDir.
function Format-LayoutPath([string]$Path, [string]$OutRoot, [string]$HomeDir) {
    foreach ($pair in @(@($OutRoot, ''), @($HomeDir, '~\'))) {
        $root = $pair[0].TrimEnd('\')
        if ($Path.StartsWith($root + '\', [StringComparison]::OrdinalIgnoreCase)) { return $pair[1] + $Path.Substring($root.Length + 1) }
    }
    return $Path
}

# Removes what Publish-AgentLayout wrote for one agent, and nothing else: a
# developer's own skill, subagent, rule or MCP server stays, and so does a file
# setup cannot tell from its own or that is in use. $Sources as in
# Publish-AgentLayout, with every skill in AllSkillNames. Returns
# @{ Removed; Edited; Kept } with paths relative to $OutRoot (or ~\... under
# $HomeDir): Removed is what is gone (including the folders that became empty),
# Edited the MCP config that lost the servers setup wrote and kept the rest,
# Kept @{ Path; Reason } what was left and why. Every removal goes through
# Remove-PathWhole.
function Remove-AgentLayout($Layout, $Sources, [string]$OutRoot, [string]$HomeDir) {
    $WarningPreference = 'SilentlyContinue'
    $result = @{ Removed = @(); Edited = @(); Kept = @() }
    $gone = New-Object System.Collections.Generic.List[string]
    $show = { param($p) Format-LayoutPath $p $OutRoot $HomeDir }
    $drop = {
        param($p)
        $problem = Remove-PathWhole $p
        if ($problem) { $result.Kept += @{ Path = (& $show $p); Reason = $problem } }
        else { $result.Removed += (& $show $p); $gone.Add($p) }
    }
    $keep = { param($p, $reason) $result.Kept += @{ Path = (& $show $p); Reason = $reason } }

    # 1. Skills: setup's junctions and marked copies in the folder.
    $item = Get-Item -LiteralPath $Layout.Skills -Force -ErrorAction SilentlyContinue
    if ($item -and $item.LinkType) {
        $target = ([string](@($item.Target)[0])).TrimEnd('\')
        & $keep $Layout.Skills "junction to $target, not written by setup"
    } elseif ($item) {
        foreach ($entry in @(Get-ChildItem -LiteralPath $Layout.Skills -Force)) {
            if (Get-PublishedSkillKind $entry $Sources.SkillsDir $Sources.AllSkillNames) { & $drop (Join-Path $Layout.Skills $entry.Name) }
        }
        if (@(Get-ChildItem -LiteralPath $Layout.Skills -Force)) { & $keep $Layout.Skills 'holds files setup did not write' }
        else { & $drop $Layout.Skills }
    }

    # 2. Subagents: a junction to the tooling's agents folder, or the files setup copied into a real folder.
    $item = if ($Layout.Subagents) { Get-Item -LiteralPath $Layout.Subagents -Force -ErrorAction SilentlyContinue } else { $null }
    if ($item -and $item.LinkType) {
        $target = ([string](@($item.Target)[0])).TrimEnd('\')
        if ($target -match ('\\' + [regex]::Escape($ToolingDirName) + '\\agents$')) { & $drop $Layout.Subagents }
        else { & $keep $Layout.Subagents "junction to $target, not written by setup" }
    } elseif ($item) {
        $ours = @(Get-ChildItem -LiteralPath $Sources.Subagents -Filter '*.md' -File | ForEach-Object { $_.Name })
        foreach ($f in @(Get-ChildItem -LiteralPath $Layout.Subagents -Filter '*.md' -File -Force)) {
            if (($ours -contains $f.Name) -or ($f.Name -match $Sources.Project.Pattern)) { & $drop (Join-Path $Layout.Subagents $f.Name) }
        }
        if (@(Get-ChildItem -LiteralPath $Layout.Subagents -Force)) { & $keep $Layout.Subagents 'holds files setup did not write' }
        else { & $drop $Layout.Subagents }
    }

    # 3. Rules: the files setup writes for this layout and the names it retired, if they are setup's.
    if ($Layout.Rules -and (Test-Path -LiteralPath $Layout.Rules -PathType Container)) {
        $rules = Get-LayoutRules $Layout $Sources
        $all = @($rules.Instructions) + @($rules.Apps)
        if ($rules.Permissions) { $all += $rules.Permissions }
        $wanted = [ordered]@{}
        # Antigravity got some instruction files as their bare source text in an
        # earlier version (no marker); such a copy is setup's too.
        $sourceText = @{}
        foreach ($rule in $all) {
            $written = ConvertTo-Rule $Layout.RuleFormat $rule
            $wanted[$written.File] = $written.Text
            if ($rule.SourceFile) { $sourceText[$written.File] = $rule.Text }
        }
        foreach ($stale in $Layout.StaleRules) { if (-not $wanted.Contains($stale)) { $wanted[$stale] = $null } }
        foreach ($name in @($wanted.Keys)) {
            $p = Join-Path $Layout.Rules $name
            if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { continue }
            $text = [System.IO.File]::ReadAllText($p)
            # An instruction file Antigravity takes as it is has no marker: only its content tells.
            $ours = ($text -match $GeneratedMarkerPattern) -or
                    (($Layout.RuleFormat -eq 'antigravity') -and ($null -ne $wanted[$name]) -and ($text -ceq $wanted[$name])) -or
                    (($Layout.RuleFormat -eq 'antigravity') -and $sourceText.ContainsKey($name) -and ($text -ceq $sourceText[$name]))
            if ($ours) { & $drop $p } else { & $keep $p 'not written by setup (no generated marker)' }
        }
        # A rule setup wrote for a source that is gone since (a removed
        # instruction file or app, another branch) still carries the marker.
        foreach ($f in @(Get-ChildItem -LiteralPath $Layout.Rules -File -Force)) {
            if ($wanted.Contains($f.Name)) { continue }
            if ([System.IO.File]::ReadAllText($f.FullName) -match $GeneratedMarkerPattern) { & $drop $f.FullName }
        }
        if (@(Get-ChildItem -LiteralPath $Layout.Rules -Force)) { & $keep $Layout.Rules 'holds files setup did not write' }
        else { & $drop $Layout.Rules }
    }

    # 4. Pointer file.
    if ($Layout.PointerFile -and (Test-Path -LiteralPath $Layout.PointerFile -PathType Leaf)) {
        if ([System.IO.File]::ReadAllText($Layout.PointerFile) -match $GeneratedMarkerPattern) { & $drop $Layout.PointerFile }
        else { & $keep $Layout.PointerFile 'not written by setup (no generated marker)' }
    }

    # 5. Stubs: only the one line setup writes.
    if ($Layout.Stub) {
        $dirs = @($OutRoot)
        if ($Layout.AppStubs) { $dirs += @($Sources.AppDirs | ForEach-Object { Join-Path $OutRoot (Split-Path -Leaf $_) }) }
        foreach ($dir in $dirs) {
            $p = Join-Path $dir $Layout.Stub
            if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { continue }
            if (([System.IO.File]::ReadAllText($p)).Trim() -eq '@AGENTS.md') { & $drop $p }
            else { & $keep $p 'changed by hand' }
        }
    }

    # 6. MCP config: the servers setup writes for this agent; every other server and key stays.
    if (Test-Path -LiteralPath $Layout.Mcp -PathType Leaf) {
        $r = Get-McpConfigWithoutProject $Layout.Mcp $Layout $Sources.Servers
        if (-not $r.Valid) {
            & $keep $Layout.Mcp 'not valid JSON, or has comments'
        } elseif (-not $r.Left.Count) {
            & $drop $Layout.Mcp
        } elseif ($r.Changed) {
            Write-Utf8File $Layout.Mcp ($r.Left | ConvertTo-Json -Depth 8)
            $result.Edited += (& $show $Layout.Mcp)
        }
    }
    # The MCP files earlier versions wrote for this agent (mcp.legacyFiles), only where setup's servers are in them.
    foreach ($file in @($Layout.McpLegacy)) {
        if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { continue }
        try {
            $r = Get-McpConfigWithoutProject $file $Layout $Sources.Servers
            if ($r.Named) { & $keep $file "not valid JSON, or has comments, and names $($r.Named -join ', ')"; continue }
            if (-not ($r.Valid -and $r.Changed)) { continue }
            Add-McpKeepValidKey $Layout $file $r.Left
            if ($r.Left.Count) {
                Write-Utf8File $file ($r.Left | ConvertTo-Json -Depth 8)
                $result.Edited += (& $show $file)
            } else {
                & $drop $file
            }
        } catch {
            & $keep $file "in use ($($_.Exception.Message))"
        }
    }

    # 7. The folders those paths were in, when nothing else is in them, up to the roots.
    $roots = @($OutRoot.TrimEnd('\'), $HomeDir.TrimEnd('\'))
    foreach ($p in $gone) {
        $dir = Split-Path -Parent $p
        while ($dir) {
            $isRoot = $false
            $inside = $false
            foreach ($root in $roots) {
                if ($dir.TrimEnd('\') -ieq $root) { $isRoot = $true }
                if ($dir.StartsWith($root + '\', [StringComparison]::OrdinalIgnoreCase)) { $inside = $true }
            }
            if ($isRoot -or -not $inside) { break }
            $folder = Get-Item -LiteralPath $dir -Force -ErrorAction SilentlyContinue
            if ($folder) {
                if ($folder.LinkType -or (Get-ChildItem -LiteralPath $dir -Force)) { break }
                if (Remove-PathWhole $dir) { break }
                $result.Removed += (& $show $dir)
            }
            $dir = Split-Path -Parent $dir
        }
    }
    return $result
}

# ------------------------------------------------------------------ tools ---

# The npm packages mcp-servers.json starts through ai_tooling/npm-mcp.js, as
# '{package}@{version}' (the argument after the launcher); setup-tools.ps1 installs
# them into ai_tooling/mcp-packages, so the versions are written in one place only.
function Get-McpNpmPackages([string]$AiDir) {
    $servers = (Get-Content (Join-Path $AiDir 'mcp-servers.json') -Raw | ConvertFrom-Json).servers
    $specs = @()
    foreach ($p in $servers.PSObject.Properties) {
        $a = @($p.Value.args)
        if ($a.Count -ge 2 -and $a[0] -like '*/npm-mcp.js') { $specs += $a[1] }
    }
    return $specs
}

# Whether ai_tooling/mcp-packages holds '{package}@{version}' in exactly that
# version. npm-mcp.js checks the same before it starts the copy instead of npx, and
# also needs the package's bin (the one named like the package, or its only one).
function Test-McpNpmPackage([string]$AiDir, [string]$Spec) {
    $at = $Spec.LastIndexOf('@')
    $name = $Spec.Substring(0, $at)
    $pkg = Join-Path $AiDir ('mcp-packages\node_modules\' + $name.Replace('/', '\') + '\package.json')
    if (-not (Test-Path $pkg)) { return $false }
    return ((Get-Content $pkg -Raw | ConvertFrom-Json).version -eq $Spec.Substring($at + 1))
}

# npm, as a function of this module so a test can mock it (npm is an external
# script in PowerShell 7, which Pester cannot mock inside a module).
function Invoke-Npm { npm @args }

# Installs the npm packages of Get-McpNpmPackages into ai_tooling/mcp-packages
# (gitignored), so npm-mcp.js starts them with node instead of npx, which loads
# npm and asks the registry on every start and can exceed an agent's connect
# limit (Claude Code: 30 s). All of them go into one npm install, since a later
# --no-save install removes packages an earlier one added. Returns the specs
# that are still not installed (empty when all are); those servers fall back
# to npx, which still works.
function Install-McpNpmPackages([string]$AiDir) {
    $specs = @(Get-McpNpmPackages $AiDir)
    $missing = @($specs | Where-Object { -not (Test-McpNpmPackage $AiDir $_) })
    if (-not $missing) { return @() }
    $dir = Join-Path $AiDir 'mcp-packages'
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    Push-Location $dir
    # npm output on stderr (a warning, or offline: ENOTFOUND) is a terminating
    # error in 5.1 under 'Stop', which also abandons npm mid-install. With
    # 'Continue' npm runs to its end; the catch keeps a missing npm from
    # stopping setup.
    $saved = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { Invoke-Npm install @specs --no-save --no-audit --no-fund --loglevel=error 2>&1 | Out-Null }
    catch { }
    finally { $ErrorActionPreference = $saved; Pop-Location }
    return @($specs | Where-Object { -not (Test-McpNpmPackage $AiDir $_) })
}

# ---------------------------------------------------------- upstream skills ---

# Installs one upstream skill group from its git repository, for the
# update-{stack}-skills.ps1 installers: clones $Repo (at $Ref, a tag or branch,
# if given) into a temp folder, replaces ai_tooling/skills/{$Group}/ wholesale
# with every folder holding a SKILL.md directly under one of $Paths (relative to
# the clone, '.' for its root), except the names in $Skip, and puts the
# project's binding note ($Binding, plus $ExtraNotes[name] for one skill) after
# each SKILL.md frontmatter. With -CopyLicense the clone's LICENSE goes into
# every skill folder. $Instructions maps a file in the clone to a file name in
# ai_tooling/instructions/ (always-on rules that come with the skills).
# Records the installed commit and the folder's content hash in skills.json
# (the group needs a one-line "source": { ... "installer": ... } there) and
# returns the installed skill names. Prints the names skills.json still lacks
# and the entries whose folder is gone; verify-agent-setup.ps1 fails until
# they agree.
function Install-UpstreamSkillGroup([string]$AiDir, [string]$Group, [string]$Repo, [string]$Ref,
                                    [string[]]$Paths = @('skills'), [string[]]$Skip = @(), [string]$Binding,
                                    [hashtable]$ExtraNotes = @{}, [switch]$CopyLicense, [hashtable]$Instructions = @{}) {
    $ErrorActionPreference = 'Stop'
    $skillsDir = Join-ManifestPath (Join-Path $AiDir 'skills') $Group
    # Everything that can fail is checked before the installed group is touched.
    $before = Read-SkillManifest $AiDir
    if (-not $before.Groups.Contains($Group)) { throw "group '$Group' is not in skills.json; add it with a one-line source first" }
    if ($before.Groups[$Group].source -eq 'project') { throw "group '$Group' is a project group, not an upstream one" }
    if (-not (Test-SkillGroupSourceLine $AiDir $Group)) { throw "group '$Group' in skills.json has no one-line ""source"": { ... ""installer"": ... }" }
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) "upstream-skills-$(Get-Random)"
    Write-Host "Cloning $Repo$(if ($Ref) { " ($Ref)" }) ..."
    $cloneArgs = @('-c', 'advice.detachedHead=false', 'clone', '--depth', '1', '--quiet')
    if ($Ref) { $cloneArgs += @('--branch', $Ref) }
    # git warns on stderr for an annotated tag; Windows PowerShell 5.1 turns that
    # into a terminating error under 'Stop', so judge the clone by its exit code.
    $ErrorActionPreference = 'Continue'
    git @cloneArgs $Repo $tmp 2>&1 | ForEach-Object { "$_" } | Write-Host
    $cloneExit = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    if ($cloneExit -ne 0) { throw "git clone of $Repo failed" }
    $installed = @()
    # The new group is built next to the installed one and replaces it only when complete.
    $stage = "$skillsDir.installing-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
    try {
        $license = Join-Path $tmp 'LICENSE'
        if ($CopyLicense -and -not (Test-Path $license)) { throw "$Repo has no LICENSE file" }
        foreach ($src in $Instructions.Keys) {
            if (-not (Test-Path -LiteralPath (Join-ManifestPath $tmp $src) -PathType Leaf)) { throw "no file '$src' in $Repo" }
        }
        $commit = git -C $tmp rev-parse HEAD
        New-Item -ItemType Directory -Force -Path $stage | Out-Null
        foreach ($p in $Paths) {
            $from = if ($p -eq '.') { $tmp } else { Join-ManifestPath $tmp $p }
            if (-not (Test-Path -LiteralPath $from -PathType Container)) { throw "no folder '$p' in $Repo" }
            foreach ($d in @(Get-ChildItem -LiteralPath $from -Directory | Where-Object { (Test-Path (Join-Path $_.FullName 'SKILL.md')) -and ($Skip -notcontains $_.Name) })) {
                $dest = Join-Path $stage $d.Name
                if (Test-Path -LiteralPath $dest) { throw "skill '$($d.Name)' found twice in $Repo" }
                Copy-Item -LiteralPath $d.FullName $dest -Recurse
                Remove-FolderSafely (Join-Path $dest '.git')
                if ($CopyLicense) { Copy-Item $license (Join-Path $dest 'LICENSE') }
                if ($Binding) { Add-SkillBindingNote (Join-Path $dest 'SKILL.md') $Binding $ExtraNotes[$d.Name] }
                Write-Host "  skill: $($d.Name)"
                $installed += $d.Name
            }
        }
        Remove-FolderSafely $skillsDir
        [System.IO.Directory]::Move($stage, $skillsDir)
        foreach ($src in $Instructions.Keys) {
            $text = [System.IO.File]::ReadAllText((Join-ManifestPath $tmp $src), [System.Text.Encoding]::UTF8)
            Write-Utf8File (Join-Path (Join-Path $AiDir 'instructions') $Instructions[$src]) $text
            Write-Host "  instructions: $($Instructions[$src])"
        }
        # Recorded only once the install is complete.
        Set-SkillGroupCommit $AiDir $Group $commit
        if ($Ref) { Set-SkillGroupSourceValue $AiDir $Group 'ref' $Ref }
        Set-SkillGroupHash $AiDir $Group (Get-SkillGroupHash $skillsDir)
    } finally {
        Remove-FolderSafely $stage
        Remove-FolderSafely $tmp
    }
    $manifest = Read-SkillManifest $AiDir
    $new = @($installed | Where-Object { -not $manifest.Skills.Contains($_) })
    $gone = @($manifest.Skills.Values | Where-Object { ($_.Group -eq $Group) -and ($installed -notcontains $_.Name) } | ForEach-Object { $_.Name })
    Write-Host "$($installed.Count) skills installed into $ToolingDirName/skills/$Group."
    $entries = @($new | ForEach-Object { '"' + $_ + '": { "group": "' + $Group + '" }' })
    if ($new) { Write-Host "  add to skills.json: $($entries -join ', ')" }
    if ($gone) { Write-Host "  remove from skills.json (no longer upstream, or skipped): $($gone -join ', ')" }
    return $installed
}

# Puts the project's binding note (and a skill's extra note) after the
# frontmatter of a SKILL.md, separated from the body by one blank line, and
# writes it as UTF-8 without a BOM: a BOM ahead of the opening --- hides the
# frontmatter from the skill loader.
function Add-SkillBindingNote([string]$SkillMd, [string]$Binding, [string]$Extra) {
    # -Encoding UTF8: Windows PowerShell 5.1 would read the file as ANSI.
    $lines = @(Get-Content -LiteralPath $SkillMd -Encoding UTF8)
    if (-not $lines -or $lines[0].Trim([char]0xFEFF, ' ', "`t") -ne '---') { throw "No frontmatter at the top of $SkillMd" }
    $close = -1
    for ($i = 1; $i -lt $lines.Count; $i++) {
        if ($lines[$i].Trim() -eq '---') { $close = $i; break }
    }
    if ($close -lt 0) { throw "No frontmatter terminator in $SkillMd" }
    $note = $Binding
    if ($Extra) { $note = $note.TrimEnd() + "`n`n" + $Extra.TrimStart() }
    $start = $close + 1
    while ($start -lt $lines.Count -and $lines[$start].Trim() -eq '') { $start++ }
    $body = if ($start -lt $lines.Count) { @($lines[$start..($lines.Count - 1)]) } else { @() }
    $out = @($lines[0..$close]) + @('') + (($note.TrimEnd() -split "`r?`n") + @('')) + $body
    [System.IO.File]::WriteAllLines($SkillMd, [string[]]$out, $Utf8NoBom)
}

# ----------------------------------------------------- delivery table (docs) ---

# How each source reaches each agent, as a Markdown table, from the same
# layouts and Publishes* decisions setup.ps1 acts on. ai_tooling/documentation/overview.md holds
# it between generated-section markers; the tests check it is current.
function Format-DeliveryTable($Layouts, [string]$OutRoot, [string]$HomeDir) {
    $keys = @($Layouts.Keys)
    $rel = { param($p) '`' + $p.Replace("$OutRoot\", '').Replace('\', '/') + '`' }
    $rows = [ordered]@{
        'Skills'           = @()
        'Subagents'        = @()
        'Root `AGENTS.md`' = @()
        'App `AGENTS.md`'  = @()
        '`PERMISSIONS.md`' = @()
        '`instructions/`'  = @()
        'MCP servers'      = @()
    }
    foreach ($k in $keys) {
        $l = $Layouts[$k]
        $rules = if ($l.Rules) { & $rel $l.Rules } else { $null }
        $rows['Skills'] += if ($l.SkillLinks -eq 'copy') { "**copy** per skill in $(& $rel $l.Skills)" } else { "junction per skill in $(& $rel $l.Skills)" }
        $rows['Subagents'] += if ($l.Subagents) { "junction $(& $rel $l.Subagents)" } else { '**not delivered**' }

        if ($l.Stub -and $l.ResolvesImports) { $root = "``$($l.Stub)`` stub, import" }
        elseif ($l.Stub) { $root = "``$($l.Stub)`` stub; the imports in ``AGENTS.md`` are **not followed**" }
        else { $root = 'native' }
        if ($l.PointerFile) { $root += ", plus pointer in $(& $rel $l.PointerFile)" }
        $rows['Root `AGENTS.md`'] += $root

        if ($l.PublishesAppRules) { $app = "**copy** as app-scoped rule in $rules" }
        elseif ($l.AppStubs -and $l.ResolvesImports) { $app = "``$($l.Stub)`` stub in app folder, import" }
        elseif ($l.ReadsNestedAgentsMd) { $app = 'native' }
        else { $app = '**not delivered**' }
        $rows['App `AGENTS.md`'] += $app

        if ($l.PublishesPermissions) { $rows['`PERMISSIONS.md`'] += "**copy** as always-on rule in $rules" }
        else { $rows['`PERMISSIONS.md`'] += 'import' }

        if ($l.PublishesInstructions) {
            $how = if ($l.RuleFormat -eq 'antigravity') { 'as is with a trigger other than glob, else new frontmatter' } else { 'new frontmatter' }
            $rows['`instructions/`'] += "**copy** in $rules, $how"
        } else {
            $rows['`instructions/`'] += 'import (from app `AGENTS.md`)'
        }

        $file = if ($l.McpInHome) { '`~/' + $l.Mcp.Replace("$HomeDir\", '').Replace('\', '/') + '`' } else { & $rel $l.Mcp }
        $rows['MCP servers'] += "$file, key ``$($l.McpKey)``"
    }
    $lines = @(('| Source | ' + (($keys | ForEach-Object { $Layouts[$_].Name }) -join ' | ') + ' |'),
               (('|---' * ($keys.Count + 1)) + '|'))
    foreach ($r in $rows.Keys) { $lines += "| $r | $($rows[$r] -join ' | ') |" }
    return ($lines -join "`n")
}

# The skills in skills.json as Markdown for ai_tooling/documentation/overview.md: one row per
# group (folder, owner, source, apps, default, the skills), then the profiles
# with what each publishes. The only place skills are listed or counted.
function Format-SkillInventory($Manifest) {
    $skills = @($Manifest.Skills.Values)
    $lines = @("$($skills.Count) skills in $($Manifest.Groups.Count) groups.", '',
               '| Group (`ai_tooling/skills/{group}/`) | Skills | Owner | Source | Apps | Default |', '|---|---|---|---|---|---|')
    foreach ($g in $Manifest.Groups.Keys) {
        $def = $Manifest.Groups[$g]
        $members = @($skills | Where-Object { $_.Group -eq $g })
        $source = if ($def.source -eq 'project') { 'project' } else {
            $repo = $def.source.repo -replace '^https://github\.com/', ''
            $at = if ($def.source.commit) { " @ ``$($def.source.commit.Substring(0, 8))``" } elseif ($def.source.ref) { " @ ``$($def.source.ref)``" } else { '' }
            "[$repo]($($def.source.repo))$at, ``$($def.source.installer.Replace("$ToolingDirName/", ''))``"
        }
        $apps = if (@($def.apps).Count) { (@($def.apps) | ForEach-Object { "``$_``" }) -join ', ' } else { 'all' }
        $names = ($members | ForEach-Object {
            $n = "``$($_.Name)``"
            if ($_.Status -eq 'deprecated') { $n += " (deprecated, use ``$($_.ReplacedBy)``)" }
            if ($_.Default -ne [bool]$def.default) { $n += $(if ($_.Default) { ' (default)' } else { ' (not default)' }) }
            $n
        }) -join ', '
        $lines += "| ``$g`` | $($members.Count): $names | $($def.owner) | $source | $apps | $(if ($def.default) { 'yes' } else { 'no' }) |"
    }
    $lines += @('', '| Profile (`setup.ps1 -Profile`) | Groups | Skills |', '|---|---|---|')
    $lines += "| ``default`` | every skill with default yes | $(@(Resolve-SkillProfile $Manifest @('default')).Count) |"
    $lines += "| ``all`` | every group | $($skills.Count) |"
    foreach ($p in $Manifest.Profiles.Keys) {
        $groups = (@($Manifest.Profiles[$p].groups) | ForEach-Object { "``$_``" }) -join ', '
        $lines += "| ``$p``: $($Manifest.Profiles[$p].description) | $groups | $(@(Resolve-SkillProfile $Manifest @($p)).Count) |"
    }
    return ($lines -join "`n")
}

# Replaces the text between "<!-- BEGIN generated: $Name -->" and
# "<!-- END generated: $Name -->" with $Content.
function Set-GeneratedSection([string]$Text, [string]$Name, [string]$Content) {
    $begin = "<!-- BEGIN generated: $Name -->"
    $end = "<!-- END generated: $Name -->"
    $i = $Text.IndexOf($begin)
    $j = $Text.IndexOf($end)
    if ($i -lt 0 -or $j -lt $i) { throw "markers for '$Name' not found" }
    return $Text.Substring(0, $i + $begin.Length) + "`n" + $Content + "`n" + $Text.Substring($j)
}

# ------------------------------------------------------------- doc links ---
#
# ai_tooling/check-doc-links.ps1 and verify-agent-setup.ps1 check the repository's own
# Markdown: every relative link and anchor resolves, and every VS Code task or
# launch configuration the docs name exists. Tracked files are listed with git,
# so a sparse checkout (the PR build) is enough: a link target only has to be
# tracked, not checked out.

# Tracked files as paths relative to the repository root, forward slashes.
function Get-TrackedFiles([string]$RepoRoot) {
    $enc = [Console]::OutputEncoding
    try {
        [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
        return @(git -C $RepoRoot -c core.quotepath=off ls-files)
    } finally { [Console]::OutputEncoding = $enc }
}

# The Markdown the check covers: the root files, docs/, documentation/,
# pipelines/, each app's AGENTS.md and documentation/, every file of the
# tooling app outside skills/ (PERMISSIONS.md, CHANGELOG.md, the subagent
# definitions, external-skill-config/) and the project skills (groups
# whose source is 'project' in skills.json). Upstream skills and vendored files
# are not ours to fix.
function Get-DocFiles([string]$RepoRoot, [string[]]$Tracked) {
    $manifest = Read-SkillManifest (Join-Path $RepoRoot $ToolingDirName)
    $projectGroups = @($manifest.Groups.Keys | Where-Object { $manifest.Groups[$_].source -eq 'project' } | ForEach-Object { "$ToolingDirName/skills/$_/" })
    return @($Tracked | Where-Object {
        $f = $_
        ($f -like '*.md') -and (
            ($f -notmatch '/') -or
            ($f -like 'docs/*') -or ($f -like 'documentation/*') -or ($f -like 'pipelines/*') -or
            ($f -match '^[^/]+/AGENTS\.md$') -or ($f -match '^[^/]+/documentation/') -or
            (($f -like "$ToolingDirName/*") -and ($f -notlike "$ToolingDirName/skills/*")) -or
            @($projectGroups | Where-Object { $f.StartsWith($_) }).Count -gt 0)
    })
}

# GitHub's anchor for a heading: lower case, Markdown stripped, every character
# that is not a letter, digit, space, hyphen or underscore dropped, spaces as
# hyphens. A repeated heading gets -1, -2, ...
function ConvertTo-HeadingSlug([string]$Heading) {
    $h = $Heading -replace '\[([^\]]*)\]\([^)]*\)', '$1'
    $h = $h -replace '<[^>]+>', ''
    $h = $h.ToLowerInvariant()
    $h = [regex]::Replace($h, '[^\p{L}\p{Nd}\p{Mn} _-]', '')
    return $h.Replace(' ', '-')
}

# Every anchor a Markdown text offers: its headings' slugs (outside code
# blocks) and the ids or names of HTML anchors.
function Get-MarkdownAnchors([string]$Text) {
    $anchors = @{}
    $seen = @{}
    $fence = $null
    foreach ($line in ($Text -split "`r?`n")) {
        if ($line -match '^\s*(```+|~~~+)') {
            $mark = $Matches[1].Substring(0, 3)
            if (-not $fence) { $fence = $mark } elseif ($mark -eq $fence) { $fence = $null }
            continue
        }
        if ($fence) { continue }
        if ($line -match '^\s{0,3}#{1,6}\s+(.*?)\s*#*\s*$') {
            $slug = ConvertTo-HeadingSlug $Matches[1]
            if ($seen.ContainsKey($slug)) { $seen[$slug]++; $anchors["$slug-$($seen[$slug])"] = $true }
            else { $seen[$slug] = 0; $anchors[$slug] = $true }
        }
        foreach ($m in [regex]::Matches($line, '<a\s+(?:id|name)\s*=\s*"([^"]+)"')) { $anchors[$m.Groups[1].Value] = $true }
    }
    return $anchors
}

# Relative links in a Markdown text, outside code blocks and inline code:
# @{ Line; Target }. Inline links (one level of parentheses in the target is
# allowed), reference definitions ("[name]: target") and HTML href / src.
# Links with a scheme (https:, mailto:, ...) are left out.
function Get-MarkdownLinks([string]$Text) {
    $links = @()
    $fence = $null
    $n = 0
    foreach ($line in ($Text -split "`r?`n")) {
        $n++
        if ($line -match '^\s*(```+|~~~+)') {
            $mark = $Matches[1].Substring(0, 3)
            if (-not $fence) { $fence = $mark } elseif ($mark -eq $fence) { $fence = $null }
            continue
        }
        if ($fence) { continue }
        $plain = [regex]::Replace($line, '(`+)(?:(?!\1).)+?\1', '')
        $targets = @()
        foreach ($m in [regex]::Matches($plain, '!?\[(?:[^\[\]]|\[[^\]]*\])*\]\(\s*(?:<([^>]+)>|((?:[^()\s]|\([^()\s]*\))+))(?:\s+"[^"]*")?\s*\)')) {
            $targets += if ($m.Groups[1].Success) { $m.Groups[1].Value } else { $m.Groups[2].Value }
        }
        if ($plain -match '^\s{0,3}\[(?!\^)[^\]]+\]:\s*<?([^\s>]+)>?') { $targets += $Matches[1] }
        foreach ($m in [regex]::Matches($plain, '<(?:a|img)\b[^>]*?\b(?:href|src)\s*=\s*"([^"]+)"')) { $targets += $m.Groups[1].Value }
        foreach ($target in $targets) {
            if ($target -match '^[A-Za-z][A-Za-z0-9+.-]*:') { continue }
            $links += [pscustomobject]@{ Line = $n; Target = $target }
        }
    }
    return $links
}

# The labels of .vscode/tasks.json and the names of .vscode/launch.json. Read
# with a pattern, not as JSON: both files hold comments.
function Get-VsCodeNames([string]$RepoRoot) {
    $names = @{}
    foreach ($pair in @(@('tasks.json', 'label'), @('launch.json', 'name'))) {
        $file = Join-Path $RepoRoot ".vscode\$($pair[0])"
        if (-not (Test-Path $file)) { continue }
        foreach ($m in [regex]::Matches([System.IO.File]::ReadAllText($file), """$($pair[1])""\s*:\s*""([^""]+)""")) { $names[$m.Groups[1].Value] = $true }
    }
    return $names
}

# Every broken relative link, missing anchor and unknown VS Code task or launch
# name in the docs Get-DocFiles lists, as @{ File; Line; Problem }. A VS Code
# name is "{app}: {name}" in backticks or quotes, on a line that says task or
# launch, for an app folder of this repository.
function Test-DocLinks([string]$RepoRoot) {
    $tracked = Get-TrackedFiles $RepoRoot
    $files = @{}
    $dirs = @{}
    foreach ($t in $tracked) {
        $files[$t.ToLowerInvariant()] = $t
        $parts = $t.Split('/')
        for ($i = 1; $i -lt $parts.Count; $i++) { $dirs[($parts[0..($i - 1)] -join '/').ToLowerInvariant()] = $true }
    }
    $vscode = Get-VsCodeNames $RepoRoot
    # A sparse checkout without .vscode/ (the agent tooling job) cannot tell;
    # the doc-link job checks it out.
    $checkVsCode = (Test-Path (Join-Path $RepoRoot '.vscode\tasks.json')) -or (Test-Path (Join-Path $RepoRoot '.vscode\launch.json'))
    $apps = @(Get-ChildItem $RepoRoot -Directory | Where-Object { Test-Path (Join-Path $_.FullName 'AGENTS.md') } | ForEach-Object { [regex]::Escape($_.Name) })
    $vsPattern = "[``""]((?:$($apps -join '|')): [^``""]+)[``""]"
    $anchorCache = @{}
    $problems = @()

    foreach ($doc in (Get-DocFiles $RepoRoot $tracked)) {
        $path = Join-Path $RepoRoot $doc
        if (-not (Test-Path -LiteralPath $path)) { continue }
        $text = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
        $dir = if ($doc.Contains('/')) { $doc.Substring(0, $doc.LastIndexOf('/')) } else { '' }

        foreach ($l in (Get-MarkdownLinks $text)) {
            $target = $l.Target
            $anchor = $null
            if ($target.Contains('#')) { $anchor = $target.Substring($target.IndexOf('#') + 1); $target = $target.Substring(0, $target.IndexOf('#')) }
            $target = [Uri]::UnescapeDataString($target)
            if ($target) {
                $joined = if ($target.StartsWith('/')) { $target.TrimStart('/') } elseif ($dir) { "$dir/$target" } else { $target }
                $stack = New-Object System.Collections.Generic.List[string]
                $outside = $false
                foreach ($part in $joined.Split('/')) {
                    if ($part -eq '' -or $part -eq '.') { continue }
                    if ($part -eq '..') { if ($stack.Count) { $stack.RemoveAt($stack.Count - 1) } else { $outside = $true } } else { $stack.Add($part) }
                }
                $resolved = $stack -join '/'
                $key = $resolved.ToLowerInvariant()
                if ($outside) { $problems += [pscustomobject]@{ File = $doc; Line = $l.Line; Problem = "link '$($l.Target)' leaves the repository" }; continue }
                $exists = $files.ContainsKey($key) -or $dirs.ContainsKey($key) -or (Test-Path -LiteralPath (Join-Path $RepoRoot $resolved))
                if (-not $exists) { $problems += [pscustomobject]@{ File = $doc; Line = $l.Line; Problem = "link '$($l.Target)': $resolved does not exist" }; continue }
                if ($files.ContainsKey($key) -and $files[$key] -cne $resolved) {
                    $problems += [pscustomobject]@{ File = $doc; Line = $l.Line; Problem = "link '$($l.Target)': the file is $($files[$key]) (case differs; breaks outside Windows)" }
                }
            } else { $resolved = $doc }
            if ($anchor -and $resolved -like '*.md') {
                if (-not $anchorCache.ContainsKey($resolved)) {
                    $full = Join-Path $RepoRoot $resolved
                    $anchorCache[$resolved] = if (Test-Path -LiteralPath $full) { Get-MarkdownAnchors ([System.IO.File]::ReadAllText($full, [System.Text.Encoding]::UTF8)) } else { $null }
                }
                $known = $anchorCache[$resolved]
                if ($known -and -not $known.ContainsKey([Uri]::UnescapeDataString($anchor).ToLowerInvariant())) {
                    $problems += [pscustomobject]@{ File = $doc; Line = $l.Line; Problem = "link '$($l.Target)': no heading '#$anchor' in $resolved" }
                }
            }
        }

        $n = 0
        foreach ($line in @(if ($checkVsCode) { $text -split "`r?`n" })) {
            $n++
            if ($line -notmatch '(?i)\b(task|launch)') { continue }
            foreach ($m in [regex]::Matches($line, $vsPattern)) {
                if (-not $vscode.ContainsKey($m.Groups[1].Value)) {
                    $problems += [pscustomobject]@{ File = $doc; Line = $n; Problem = "VS Code task or launch configuration '$($m.Groups[1].Value)' is not in .vscode/tasks.json or launch.json" }
                }
            }
        }
    }
    return $problems
}

Export-ModuleMember -Function * -Variable SkillDescriptionMax, SkillLinesMax, SkillReferenceLinesMax, SkillNameMax, SkillCompatibilityMax, SkillCopyMarker, ToolingDirName, LocalSourcesName
