# Pester 5 tests for the agent tooling setup: the functions in
# ai_tooling/lib/AgentSetup.psm1, the manifests in ai_tooling/manifest/, mcp-servers.json, and
# setup.ps1's parameters. Run them through .\ai_tooling\tests\Invoke-Tests.ps1.
#
# The same file in every project set up from the ai_tooling blueprint: the
# fixtures use the made-up project "Acme" (skill prefixes acme and acmego) and
# the apps app-one and app-two; the tests that read the project's own manifests
# check only what holds for every project.
#
# Mocks of commands the module calls need -ModuleName AgentSetup, so that they
# replace the command inside the module, not only in this file.

BeforeDiscovery {
    # -Skip is evaluated during discovery, before any BeforeAll has run, so
    # what it reads must be set here.
    $canTestJson = [bool](Get-Command Test-Json -ErrorAction SilentlyContinue)
    $hasProfile = @((Get-Content (Join-Path (Split-Path -Parent $PSScriptRoot) 'manifest\skills.json') -Raw | ConvertFrom-Json).profiles.PSObject.Properties).Count -gt 0
    $hasGit = [bool](Get-Command git -ErrorAction SilentlyContinue)
}

BeforeAll {
    $AiDir    = Split-Path -Parent $PSScriptRoot
    $RepoRoot = Split-Path -Parent $AiDir
    Get-Module AgentSetup | Remove-Module -Force
    Import-Module (Join-Path $AiDir 'lib\AgentSetup.psm1') -Force
    . (Join-Path $PSScriptRoot 'SetupOutput.ps1')
    $AgentKeys = @('claude', 'gemini', 'copilot', 'cursor')
    # The made-up project of the fixtures (manifest/project.json as Read-ProjectManifest returns it).
    $TestProject = [pscustomobject]@{ Name = 'Acme'; Prefixes = @('acme', 'acmego'); Pattern = '^(acme|acmego)-' }

    function Read-Utf8($path) { [System.IO.File]::ReadAllText($path) }
    # A skills folder that holds one marked copy, so Test-LayoutOnDisk counts
    # the layout as set up (a bare folder does not count).
    function New-PublishedSkill($skillsFolder) {
        New-Item -ItemType Directory -Force -Path (Join-Path $skillsFolder 'published-skill') | Out-Null
        Set-Content -Path (Join-Path $skillsFolder "published-skill\$SkillCopyMarker") -Value ''
    }
    function Test-Bom($path) {
        $b = [System.IO.File]::ReadAllBytes($path)
        return ($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF)
    }
    # Every schema error, not only the first, each with its place. Test-Json
    # decides valid or not; the messages come from the JsonSchema.Net it uses,
    # because Test-Json's own differ by version: 7.6.6 also reports
    # branches that were meant to fail (an if, the inside of a not, the other
    # branches of a oneOf that matched), so a message can point to the wrong
    # place; 7.6.7 reports only errors at the top level. Here a failure counts
    # only when no enclosing rule passed and it is not inside an if or not (as
    # keywords, not as property names). A rule built on not has no error text,
    # so for a failing rule without text and without a failing rule below it,
    # the rule and its place are named instead. A pwsh without this
    # JsonSchema.Net API (7.0-7.3 use NJsonSchema), and text that is not JSON,
    # get Test-Json's own messages.
    function Get-SchemaErrors($json, $schema) {
        $errs = $null
        $ok = $json | Test-Json -Schema $schema -ErrorAction SilentlyContinue -ErrorVariable errs
        $messages = @()
        if (-not $ok) {
            $document = $null
            if ('Json.Schema.EvaluationOptions' -as [type]) {
                try { $document = [System.Text.Json.Nodes.JsonNode]::Parse($json) } catch { }
            }
            if (-not $document) {
                $messages = @($errs | ForEach-Object { $_.Exception.Message })
            } else {
                $options = [Json.Schema.EvaluationOptions]::new()
                $options.OutputFormat = [Json.Schema.OutputFormat]::List
                $result = [Json.Schema.JsonSchema]::FromText($schema).Evaluate($document, $options)
                $nodes = @($result.Details | ForEach-Object {
                    [pscustomobject]@{ Rule = $_.EvaluationPath.ToString(); At = $_.InstanceLocation.ToString(); Valid = $_.IsValid; Errors = $_.Errors }
                })
                # Whether node $n lies below node $a: in the schema and in the document.
                $under = { param($n, $a) $n.Rule.StartsWith($a.Rule + '/') -and ($n.At -eq $a.At -or $n.At.StartsWith($a.At + '/')) }
                # Whether a rule path passes through an if or not keyword; a segment right
                # after properties, patternProperties or definitions is a name instead.
                $inIfOrNot = { param($rule)
                    $s = $rule.Split('/')
                    for ($i = 1; $i -lt $s.Count; $i++) {
                        if ($s[$i] -in 'if', 'not' -and $s[$i - 1] -notin 'properties', 'patternProperties', 'definitions') { return $true }
                    }
                    return $false
                }
                $failed = @($nodes | Where-Object { -not $_.Valid -and -not (& $inIfOrNot $_.Rule) } | Where-Object {
                    $n = $_; -not @($nodes | Where-Object { $_.Valid -and (& $under $n $_) })
                })
                $messages = @(foreach ($f in $failed) {
                    if ($f.Errors) { foreach ($k in $f.Errors.Keys) { "The JSON is not valid with the schema: $($f.Errors[$k]) at '$($f.At)'" } }
                    elseif (-not @($failed | Where-Object { & $under $_ $f })) { "The JSON is not valid with the schema ($($f.Rule)) at '$($f.At)'" }
                })
            }
        }
        return [pscustomobject]@{ Ok = $ok; Messages = @($messages | Select-Object -Unique) }
    }
}

Describe 'agents.json' {
    BeforeAll {
        $manifest = Read-AgentManifest $AiDir
        $layouts = Get-AgentLayouts $AiDir 'C:\Out' 'C:\Home'
    }

    It 'lists the agents in the order of the prompt' {
        @($manifest.Keys) | Should -Be $AgentKeys
    }

    It 'matches its schema' -Skip:(-not $canTestJson) {
        $r = Get-SchemaErrors (Get-Content (Join-Path $AiDir 'manifest\agents.json') -Raw) (Get-Content (Join-Path $AiDir 'manifest\agents.schema.json') -Raw)
        $r.Ok | Should -BeTrue -Because ("agents.json does not match agents.schema.json:`n" + ($r.Messages -join "`n"))
    }

    It 'rejects an agent that does not resolve imports but has no rules folder' -Skip:(-not $canTestJson) {
        $json = '{ "agents": { "x": { "name": "X", "detect": { "homeFolders": [".x"] }, "skills": ".x/skills", "resolvesImports": false, "readsNestedAgentsMd": true,
                  "mcp": { "root": "repo", "file": ".x/mcp.json", "key": "servers", "httpUrlField": "url", "httpType": true } } } }'
        $json | Test-Json -Schema (Get-Content (Join-Path $AiDir 'manifest\agents.schema.json') -Raw) -ErrorAction SilentlyContinue | Should -BeFalse
    }

    It 'resolves paths against the output root, and Antigravity''s global MCP config against the home folder' {
        $layouts.claude.Skills | Should -Be 'C:\Out\.claude\skills'
        $layouts.claude.Subagents | Should -Be 'C:\Out\.claude\agents'
        $layouts.gemini.Subagents | Should -BeNullOrEmpty
        $layouts.copilot.Rules | Should -Be 'C:\Out\.github\instructions'
        $layouts.copilot.PointerFile | Should -Be 'C:\Out\.github\copilot-instructions.md'
        $layouts.gemini.Mcp | Should -Be 'C:\Out\.agents\mcp_config.json'
        @($layouts.gemini.McpLegacy).Count | Should -Be 0
        $layouts.gemini.McpKeepValid | Should -Be @('C:\Home\.gemini\config\mcp_config.json')
        $layouts.gemini.McpInHome | Should -BeFalse
    }

    It 'resolves mcp.legacyFiles against mcp.root when there is no legacyRoot' {
        $entry = '{ "name": "X", "skills": ".x/skills", "mcp": { "root": "home", "file": ".x/mcp.json", "key": "servers", "legacyFiles": [".x/old.json"] } }' | ConvertFrom-Json
        (Get-AgentLayout 'x' $entry 'C:\Out' 'C:\Home').McpLegacy | Should -Be @('C:\Home\.x\old.json')
    }

    It 'publishes <what> for <key>: <expected>' -TestCases @(
        @{ key = 'claude';  what = 'PublishesPermissions';  expected = $false }
        @{ key = 'claude';  what = 'PublishesInstructions'; expected = $false }
        @{ key = 'claude';  what = 'PublishesAppRules';     expected = $false }
        @{ key = 'copilot'; what = 'PublishesPermissions';  expected = $true }
        @{ key = 'copilot'; what = 'PublishesInstructions'; expected = $true }
        @{ key = 'copilot'; what = 'PublishesAppRules';     expected = $true }
        @{ key = 'cursor';  what = 'PublishesPermissions';  expected = $true }
        @{ key = 'cursor';  what = 'PublishesInstructions'; expected = $true }
        @{ key = 'cursor';  what = 'PublishesAppRules';     expected = $false }
        @{ key = 'gemini';  what = 'PublishesPermissions';  expected = $true }
        @{ key = 'gemini';  what = 'PublishesInstructions'; expected = $true }
        @{ key = 'gemini';  what = 'PublishesAppRules';     expected = $true }
    ) {
        $layouts[$key].$what | Should -Be $expected
    }

    It 'derives what an agent gets from its facts' {
        $entry = [pscustomobject]@{
            name = 'X'; detect = $null; skills = '.x/skills'; resolvesImports = $true; readsNestedAgentsMd = $false
            stub = [pscustomobject]@{ file = 'X.md'; inApps = $false }
            rules = [pscustomobject]@{ folder = '.x/rules'; format = 'cursor' }
            mcp = [pscustomobject]@{ root = 'repo'; file = '.x/mcp.json'; key = 'servers'; httpUrlField = 'url'; httpType = $true }
        }
        $l = Get-AgentLayout 'x' $entry 'C:\Out' 'C:\Home'
        $l.PublishesPermissions | Should -BeFalse
        # The stub imports AGENTS.md at the root only; the apps need rules.
        $l.PublishesAppRules | Should -BeTrue
        $entry.stub.inApps = $true
        (Get-AgentLayout 'x' $entry 'C:\Out' 'C:\Home').PublishesAppRules | Should -BeFalse
    }
}

Describe 'instructions.json' {
    It 'has an entry for every file in ai_tooling/instructions' {
        $meta = Read-InstructionManifest $AiDir @('app1')
        foreach ($f in Get-ChildItem (Join-Path $AiDir 'instructions') -Filter *.md -File) {
            $meta.Keys | Should -Contain $f.Name
        }
    }

    It 'gives every entry a description and at least one glob' {
        foreach ($e in (Read-InstructionManifest $AiDir @('app1')).Values) {
            $e.Description | Should -Not -BeNullOrEmpty
            @($e.Globs).Count | Should -BeGreaterThan 0
        }
    }

    It 'expands allApps to one glob per app' {
        (Read-InstructionManifest $AiDir @('app1', 'app2'))['coding-principles.md'].Globs | Should -Be @('app1/**', 'app2/**')
    }
}

Describe 'skills.json' {
    BeforeAll {
        $schema = Get-Content (Join-Path $AiDir 'manifest\skills.schema.json') -Raw
        $group = '"g": { "description": "d", "owner": "o", "source": "project", "apps": [], "default": true }'
    }

    It 'matches its schema' -Skip:(-not $canTestJson) {
        $r = Get-SchemaErrors (Get-Content (Join-Path $AiDir 'manifest\skills.json') -Raw) $schema
        $r.Ok | Should -BeTrue -Because ("skills.json does not match skills.schema.json:`n" + ($r.Messages -join "`n"))
    }

    It 'rejects <name>' -Skip:(-not $canTestJson) -TestCases @(
        @{ name = 'a deprecated skill without replacedBy'; skills = '"a": { "group": "g", "status": "deprecated" }'; profiles = '{}' }
        @{ name = 'an unknown field'; skills = '"a": { "group": "g", "grup": "g" }'; profiles = '{}' }
        @{ name = 'a skill name with capitals'; skills = '"Ab": { "group": "g" }'; profiles = '{}' }
        @{ name = 'a group of three segments'; skills = '"a": { "group": "x/y/z" }'; profiles = '{}' }
        @{ name = 'a profile named default'; skills = '"a": { "group": "g" }'; profiles = '{ "default": { "description": "d", "groups": ["g"] } }' }
    ) {
        $json = "{ ""groups"": { $group }, ""profiles"": $profiles, ""skills"": { $skills } }"
        $json | Test-Json -Schema $schema -ErrorAction SilentlyContinue | Should -BeFalse
    }

    It 'matches the skill folders in ai_tooling/skills' {
        $problems = @(Test-SkillManifest (Read-SkillManifest $AiDir) (Join-Path $AiDir 'skills'))
        $problems | Should -BeNullOrEmpty -Because ($problems -join "`n")
    }
}

Describe 'Skill manifest functions' {
    BeforeEach {
        $ai = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force -Path (Join-Path $ai 'manifest') | Out-Null
        function Set-Manifest($json) { [System.IO.File]::WriteAllText((Join-Path $ai 'manifest\skills.json'), $json) }
        function New-Skill($rel) {
            $d = Join-Path $ai "skills\$rel"
            New-Item -ItemType Directory -Force -Path $d | Out-Null
            Set-Content -Path (Join-Path $d 'SKILL.md') -Value "---`nname: $(Split-Path -Leaf $rel)`n---"
        }
        Set-Manifest @'
{
  "groups": {
    "up/x": { "description": "d", "owner": "Owner X", "source": { "repo": "https://x.test", "installer": "ai_tooling/x.ps1" }, "apps": ["app-one"], "default": true },
    "proj": { "description": "d", "owner": "Owner P", "source": "project", "apps": [], "default": false }
  },
  "profiles": { "px": { "description": "d", "groups": ["up/x"] }, "pp": { "description": "d", "groups": ["proj"] } },
  "skills": {
    "x-one": { "group": "up/x" },
    "x-two": { "group": "up/x", "apps": ["app-two"], "default": false },
    "p-one": { "group": "proj", "default": true, "status": "deprecated", "replacedBy": "p-two" },
    "p-two": { "group": "proj" }
  }
}
'@
        New-Skill 'up\x\x-one'; New-Skill 'up\x\x-two'; New-Skill 'proj\p-one'; New-Skill 'proj\p-two'
    }

    It 'gives each skill what its group says, unless the skill overrides it' {
        $m = Read-SkillManifest $ai
        $m.Skills['x-one'].Owner | Should -Be 'Owner X'
        $m.Skills['x-one'].Source.repo | Should -Be 'https://x.test'
        $m.Skills['x-one'].Apps | Should -Be @('app-one')
        $m.Skills['x-one'].Default | Should -BeTrue
        $m.Skills['x-two'].Apps | Should -Be @('app-two')
        $m.Skills['x-two'].Default | Should -BeFalse
        $m.Skills['p-one'].Default | Should -BeTrue
        $m.Skills['p-two'].Default | Should -BeFalse
        $m.Skills['p-two'].Source | Should -Be 'project'
        @($m.Skills['p-two'].Apps).Count | Should -Be 0
    }

    It 'resolves the status, active unless the entry says otherwise' {
        $m = Read-SkillManifest $ai
        $m.Skills['p-one'].Status | Should -Be 'deprecated'
        $m.Skills['p-one'].ReplacedBy | Should -Be 'p-two'
        $m.Skills['x-one'].Status | Should -Be 'active'
    }

    It 'resolves the skill folder under ai_tooling/skills/{group}/{name}' {
        (Read-SkillManifest $ai).Skills['x-one'].Path | Should -Be (Join-Path $ai 'skills\up\x\x-one')
    }

    It 'publishes <expected> for profile <names>' -TestCases @(
        @{ names = @(); expected = @('x-one', 'p-one') }
        @{ names = @('default'); expected = @('x-one', 'p-one') }
        @{ names = @('all'); expected = @('x-one', 'x-two', 'p-one', 'p-two') }
        @{ names = @('px'); expected = @('x-one', 'x-two') }
        @{ names = @('px', 'pp'); expected = @('x-one', 'x-two', 'p-one', 'p-two') }
        @{ names = @('pp', 'default'); expected = @('x-one', 'p-one', 'p-two') }
    ) {
        Resolve-SkillProfile (Read-SkillManifest $ai) $names | Should -Be $expected
    }

    It 'refuses an unknown profile and names the known ones' {
        { Resolve-SkillProfile (Read-SkillManifest $ai) @('nope') } | Should -Throw '*default, all, px, pp*'
    }

    It 'finds skill folders in groups of one and two segments, and flat ones' {
        New-Skill 'flat-one'
        $found = @(Get-SkillFolders (Join-Path $ai 'skills'))
        ($found | ForEach-Object { "$($_.Group)|$($_.Name)" } | Sort-Object) | Should -Be @('|flat-one', 'proj|p-one', 'proj|p-two', 'up/x|x-one', 'up/x|x-two')
    }

    It 'does not look inside a skill for further SKILL.md files' {
        New-Skill 'up\x\x-one\references\inner'
        @(Get-SkillFolders (Join-Path $ai 'skills')).Name | Should -Not -Contain 'inner'
    }

    It 'finds nothing wrong when the manifest and the folders agree' {
        Test-SkillManifest (Read-SkillManifest $ai) (Join-Path $ai 'skills') | Should -BeNullOrEmpty
    }

    It 'reports <name>' -TestCases @(
        @{ name = 'a folder without an entry'; arrange = { New-Skill 'proj\p-three' }; expected = '*p-three: folder has no entry*' }
        @{ name = 'an entry without a folder'; arrange = { Remove-Item (Join-Path $ai 'skills\proj\p-two') -Recurse -Force }; expected = '*p-two: no folder ai_tooling/skills/proj/p-two*' }
        @{ name = 'a skill in another group''s folder'; arrange = { Move-Item (Join-Path $ai 'skills\proj\p-two') (Join-Path $ai 'skills\up\x\p-two') }; expected = "*p-two: folder is in 'up/x', skills.json says group 'proj'*" }
        @{ name = 'a name in two folders'; arrange = { New-Skill 'up\x\p-two' }; expected = '*p-two: in several folders*unique*' }
    ) {
        & $arrange
        (Test-SkillManifest (Read-SkillManifest $ai) (Join-Path $ai 'skills')) -join "`n" | Should -BeLike $expected
    }

    It 'reports an undefined group, a replacement that is not a skill, and a profile with an undefined group' {
        Set-Manifest '{ "groups": {}, "profiles": { "pz": { "description": "d", "groups": ["nope"] } }, "skills": { "x-one": { "group": "up/x", "status": "deprecated", "replacedBy": "gone" } } }'
        $text = (Test-SkillManifest (Read-SkillManifest $ai) (Join-Path $ai 'skills')) -join "`n"
        $text | Should -BeLike "*x-one: group 'up/x' is not defined*"
        $text | Should -BeLike "*x-one: replacedBy 'gone' is not a skill*"
        $text | Should -BeLike "*profile 'pz': group 'nope' is not defined*"
    }
}

Describe 'Set-SkillGroupCommit' {
    BeforeEach {
        $ai = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force -Path (Join-Path $ai 'manifest') | Out-Null
        $file = Join-Path $ai 'manifest\skills.json'
        [System.IO.File]::WriteAllText($file, (@(
            '{', '  "groups": {',
            '    "up/x": {', '      "description": "d",', '      "source": { "repo": "https://x.test", "ref": "v1", "installer": "ai_tooling/x.ps1" },', '      "default": true', '    },',
            '    "proj": {', '      "source": "project"', '    }',
            '  }', '}') -join "`n"))
        $sha1 = 'a' * 40
        $sha2 = 'b' * 40
    }

    It 'adds the commit to the group''s source, and replaces it the next time' {
        Set-SkillGroupCommit $ai 'up/x' $sha1
        [System.IO.File]::ReadAllText($file) | Should -BeLike "*""ref"": ""v1"", ""commit"": ""$sha1"", ""installer""*"
        Set-SkillGroupCommit $ai 'up/x' $sha2
        $text = [System.IO.File]::ReadAllText($file)
        $text | Should -BeLike "*""commit"": ""$sha2""*"
        $text | Should -Not -BeLike "*$sha1*"
        ($text | ConvertFrom-Json).groups.'up/x'.source.commit | Should -Be $sha2
    }

    It 'refuses <name>' -TestCases @(
        @{ name = 'a group whose source is project'; group = 'proj'; commit = ('a' * 40) }
        @{ name = 'a group that does not exist'; group = 'nope'; commit = ('a' * 40) }
        @{ name = 'a short commit id'; group = 'up/x'; commit = 'abc1234' }
    ) {
        { Set-SkillGroupCommit $ai $group $commit } | Should -Throw
    }

    It 'refuses a source line with neither a commit nor an installer, and leaves the file alone' {
        [System.IO.File]::WriteAllText($file, (@('{', '  "groups": {', '    "up/x": {', '      "source": { "repo": "https://x.test" }', '    }', '  }', '}') -join "`n"))
        $before = [System.IO.File]::ReadAllText($file)
        { Set-SkillGroupCommit $ai 'up/x' $sha1 } | Should -Throw '*could not record*'
        [System.IO.File]::ReadAllText($file) | Should -Be $before
    }

    It 'keeps the file''s line endings' {
        [System.IO.File]::WriteAllText($file, ([System.IO.File]::ReadAllText($file).Replace("`n", "`r`n")))
        Set-SkillGroupCommit $ai 'up/x' $sha1
        $text = [System.IO.File]::ReadAllText($file)
        ($text -replace "`r`n", '') | Should -Not -Match "`n"
        $text | Should -BeLike "*""commit"": ""$sha1""*"
    }
}

Describe 'Set-SkillGroupHash' {
    BeforeEach {
        $ai = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force -Path (Join-Path $ai 'manifest') | Out-Null
        $file = Join-Path $ai 'manifest\skills.json'
        $original = (@(
            '{', '  "groups": {',
            '    "up/x": {', '      "description": "d",', '      "source": { "repo": "https://x.test", "ref": "v1", "installer": "ai_tooling/x.ps1" },', '      "default": true', '    },',
            '    "proj": {', '      "source": "project"', '    }',
            '  }', '}') -join "`n")
        [System.IO.File]::WriteAllText($file, $original)
        $h1 = 'a' * 64
        $h2 = '0123456789abcdef' * 4
    }

    It 'adds the hash to the group''s source before the installer, and replaces it the next time' {
        Set-SkillGroupHash $ai 'up/x' $h1
        [System.IO.File]::ReadAllText($file) | Should -BeLike "*""ref"": ""v1"", ""hash"": ""$h1"", ""installer""*"
        Set-SkillGroupHash $ai 'up/x' $h2
        $text = [System.IO.File]::ReadAllText($file)
        $text | Should -BeLike "*""hash"": ""$h2""*"
        $text | Should -Not -BeLike "*$h1*"
        ($text | ConvertFrom-Json).groups.'up/x'.source.hash | Should -Be $h2
    }

    It 'keeps the rest of the file byte-identical, and the commit next to the hash' {
        Set-SkillGroupHash $ai 'up/x' $h1
        [System.IO.File]::ReadAllText($file) | Should -Be $original.Replace('"ref": "v1", "installer"', """ref"": ""v1"", ""hash"": ""$h1"", ""installer""")
        Set-SkillGroupCommit $ai 'up/x' ('c' * 40)
        $source = ([System.IO.File]::ReadAllText($file) | ConvertFrom-Json).groups.'up/x'.source
        $source.hash | Should -Be $h1
        $source.commit | Should -Be ('c' * 40)
    }

    It 'refuses <name>' -TestCases @(
        @{ name = 'a group whose source is project'; group = 'proj'; hash = ('a' * 64) }
        @{ name = 'a group that does not exist'; group = 'nope'; hash = ('a' * 64) }
        @{ name = 'a hash that is too short'; group = 'up/x'; hash = ('a' * 63) }
        @{ name = 'a hash in upper case'; group = 'up/x'; hash = ('A' * 64) }
        @{ name = 'a commit id'; group = 'up/x'; hash = ('a' * 40) }
    ) {
        { Set-SkillGroupHash $ai $group $hash } | Should -Throw
        [System.IO.File]::ReadAllText($file) | Should -Be $original
    }

    It 'keeps the file''s line endings' {
        [System.IO.File]::WriteAllText($file, $original.Replace("`n", "`r`n"))
        Set-SkillGroupHash $ai 'up/x' $h1
        $text = [System.IO.File]::ReadAllText($file)
        ($text -replace "`r`n", '') | Should -Not -Match "`n"
        $text | Should -BeLike "*""hash"": ""$h1""*"
    }
}

Describe 'Get-SkillGroupHash' {
    BeforeEach {
        $dir = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        function Set-GroupFile($rel, [byte[]]$bytes) {
            $p = Join-Path $dir $rel
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $p) | Out-Null
            [System.IO.File]::WriteAllBytes($p, $bytes)
        }
        function ConvertTo-Bytes([string]$text) { [System.Text.Encoding]::UTF8.GetBytes($text) }
        Set-GroupFile 's1\SKILL.md' (ConvertTo-Bytes "---`nname: s1`n---`nline`nline`n")
        Set-GroupFile 's1\references\a.md' (ConvertTo-Bytes "ref`n")
        Set-GroupFile 'LICENSE' (ConvertTo-Bytes "licence`n")
    }

    It 'is 64 lowercase hex characters' {
        Get-SkillGroupHash $dir | Should -MatchExactly '^[0-9a-f]{64}$'
    }

    It 'is the same twice, and the same for CRLF and LF line endings' {
        $lf = Get-SkillGroupHash $dir
        Get-SkillGroupHash $dir | Should -Be $lf
        Set-GroupFile 's1\SKILL.md' (ConvertTo-Bytes "---`r`nname: s1`r`n---`r`nline`r`nline`r`n")
        Set-GroupFile 'LICENSE' (ConvertTo-Bytes "licence`r`n")
        Get-SkillGroupHash $dir | Should -Be $lf
    }

    It 'changes when one byte changes' {
        $before = Get-SkillGroupHash $dir
        Set-GroupFile 's1\references\a.md' (ConvertTo-Bytes "rEf`n")
        Get-SkillGroupHash $dir | Should -Not -Be $before
    }

    It 'changes when a lone CR changes, which is not a CRLF' {
        Set-GroupFile 'x.md' (ConvertTo-Bytes "a`rb`n")
        $before = Get-SkillGroupHash $dir
        Set-GroupFile 'x.md' (ConvertTo-Bytes "a`nb`n")
        Get-SkillGroupHash $dir | Should -Not -Be $before
    }

    It 'changes when a file is renamed, moved, added or removed' {
        $before = Get-SkillGroupHash $dir
        Move-Item (Join-Path $dir 's1\references\a.md') (Join-Path $dir 's1\references\b.md')
        $renamed = Get-SkillGroupHash $dir
        $renamed | Should -Not -Be $before
        Move-Item (Join-Path $dir 's1\references\b.md') (Join-Path $dir 's1\b.md')
        Get-SkillGroupHash $dir | Should -Not -Be $renamed
        Set-GroupFile 'extra.md' (ConvertTo-Bytes "x")
        Get-SkillGroupHash $dir | Should -Not -Be $renamed
        Remove-Item (Join-Path $dir 'LICENSE')
        Remove-Item (Join-Path $dir 'extra.md')
        Get-SkillGroupHash $dir | Should -Not -Be $renamed
    }

    It 'does not depend on the order the files were written in' {
        $other = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        foreach ($rel in @('LICENSE', 's1\references\a.md', 's1\SKILL.md')) {
            $p = Join-Path $other $rel
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $p) | Out-Null
            Copy-Item (Join-Path $dir $rel) $p
        }
        Get-SkillGroupHash $other | Should -Be (Get-SkillGroupHash $dir)
    }
}

Describe 'Skill content checks' {
    BeforeEach {
        $ai = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force -Path (Join-Path $ai 'manifest') | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $ai 'manifest\skills.json'), @'
{
  "groups": {
    "up": { "description": "d", "owner": "o", "source": { "repo": "https://x.test", "installer": "ai_tooling/x.ps1" }, "apps": [], "default": true },
    "proj": { "description": "d", "owner": "o", "source": "project", "apps": [], "default": true }
  },
  "profiles": {},
  "skills": { "up-skill": { "group": "up" }, "acme-good": { "group": "proj" } }
}
'@)
        function Set-Skill($group, $name, $text) {
            $d = Join-Path $ai "skills\$group\$name"
            New-Item -ItemType Directory -Force -Path $d | Out-Null
            [System.IO.File]::WriteAllText((Join-Path $d 'SKILL.md'), $text)
        }
        function Get-Result { Test-SkillContent (Read-SkillManifest $ai) $TestProject }
        # A reference file of $count lines in a skill: a title, then $contents (a Contents list or nothing), then filler.
        function Set-Reference($group, $name, $file, $count, [bool]$contents) {
            $d = Join-Path $ai "skills\$group\$name\references"
            New-Item -ItemType Directory -Force -Path $d | Out-Null
            $head = @('# Title', '')
            if ($contents) { $head += @('## Contents', '', '- One', '- Two', '') }
            $body = 1..($count - $head.Count) | ForEach-Object { "line $_" }
            [System.IO.File]::WriteAllText((Join-Path $d $file), ((@($head) + @($body)) -join "`n") + "`n")
        }
        Set-Skill 'up' 'up-skill' "---`nname: up-skill`ndescription: An upstream skill.`n---`nBody`n"
        Set-Skill 'proj' 'acme-good' "---`nname: acme-good`ndescription: A project skill.`n---`nAsk for approval (PERMISSIONS.md, section 1).`n"
    }

    It 'finds nothing wrong in well-formed skills' {
        $r = Get-Result
        $r.Errors | Should -BeNullOrEmpty
        $r.Warnings | Should -BeNullOrEmpty
    }

    It 'reads a description that is quoted, folded or spread over lines' -TestCases @(
        @{ front = "description: 'Quoted text.'"; expected = 'Quoted text.' }
        @{ front = "description: >`n  Folded`n  text."; expected = 'Folded text.' }
        @{ front = "description: Plain`n  continued."; expected = 'Plain continued.' }
    ) {
        Get-SkillDescription "---`nname: x`n$front`nlicense: MIT`n---`nBody" | Should -Be $expected
    }

    It 'reports <name>' -TestCases @(
        @{ name = 'a BOM'; group = 'proj'; skill = 'acme-good'; text = ([char]0xFEFF + "---`nname: acme-good`ndescription: d`n---`n"); expected = '*acme-good: SKILL.md starts with a UTF-8 BOM*' }
        @{ name = 'a frontmatter name that is not the folder'; group = 'proj'; skill = 'acme-good'; text = "---`nname: other`ndescription: d`n---`n"; expected = "*frontmatter name is not 'acme-good'*" }
        @{ name = 'a missing description'; group = 'proj'; skill = 'acme-good'; text = "---`nname: acme-good`n---`n"; expected = '*acme-good: no description*' }
        @{ name = 'a description over 1024 characters'; group = 'up'; skill = 'up-skill'; text = "---`nname: up-skill`ndescription: $('x' * 1025)`n---`n"; expected = '*up-skill: description has 1025 characters*' }
        @{ name = 'a project SKILL.md over 500 lines'; group = 'proj'; skill = 'acme-good'; text = "---`nname: acme-good`ndescription: d`n---`n" + ("line`n" * 500); expected = '*acme-good: SKILL.md has 504 lines*' }
        @{ name = 'approvals without PERMISSIONS.md'; group = 'proj'; skill = 'acme-good'; text = "---`nname: acme-good`ndescription: d`n---`nWait for approval.`n"; expected = '*acme-good: mentions approvals without pointing to PERMISSIONS.md*' }
    ) {
        Set-Skill $group $skill $text
        (Get-Result).Errors -join "`n" | Should -BeLike $expected
    }

    It 'reports a name that breaks the Agent Skills specification: <name>' -TestCases @(
        @{ name = 'over 64 characters'; skill = ('a' * 65); expected = "*$('a' * 65): the name has 65 characters, more than 64*" }
        @{ name = 'with a double hyphen'; skill = 'a--b'; expected = '*a--b: a name has no leading, trailing or double hyphen*' }
        @{ name = 'with a leading hyphen'; skill = '-ab'; expected = '*-ab: a name has no leading, trailing or double hyphen*' }
        @{ name = 'with a trailing hyphen'; skill = 'ab-'; expected = '*ab-: a name has no leading, trailing or double hyphen*' }
    ) {
        [System.IO.File]::WriteAllText((Join-Path $ai 'manifest\skills.json'),
            "{ ""groups"": { ""up"": { ""description"": ""d"", ""owner"": ""o"", ""source"": { ""repo"": ""https://x.test"", ""installer"": ""ai_tooling/x.ps1"" }, ""apps"": [], ""default"": true } }, ""profiles"": {}, ""skills"": { ""$skill"": { ""group"": ""up"" } } }")
        Set-Skill 'up' $skill "---`nname: $skill`ndescription: d`n---`n"
        (Get-Result).Errors -join "`n" | Should -BeLike $expected
    }

    It 'accepts a name of exactly 64 characters' {
        $skill = 'a' * 64
        [System.IO.File]::WriteAllText((Join-Path $ai 'manifest\skills.json'),
            "{ ""groups"": { ""up"": { ""description"": ""d"", ""owner"": ""o"", ""source"": { ""repo"": ""https://x.test"", ""installer"": ""ai_tooling/x.ps1"" }, ""apps"": [], ""default"": true } }, ""profiles"": {}, ""skills"": { ""$skill"": { ""group"": ""up"" } } }")
        Set-Skill 'up' $skill "---`nname: $skill`ndescription: d`n---`n"
        (Get-Result).Errors | Should -BeNullOrEmpty
    }

    It 'reports a project skill name with a double hyphen once, not also against the naming convention' {
        [System.IO.File]::WriteAllText((Join-Path $ai 'manifest\skills.json'),
            '{ "groups": { "proj": { "description": "d", "owner": "o", "source": "project", "apps": [], "default": true } }, "profiles": {}, "skills": { "acme--x": { "group": "proj" } } }')
        Set-Skill 'proj' 'acme--x' "---`nname: acme--x`ndescription: d`n---`n"
        @((Get-Result).Errors).Count | Should -Be 1
        (Get-Result).Errors -join "`n" | Should -BeLike '*acme--x: a name has no leading, trailing or double hyphen*'
    }

    It 'reports a compatibility over 500 characters, and accepts 500 or none' {
        Set-Skill 'up' 'up-skill' "---`nname: up-skill`ndescription: d`ncompatibility: $('x' * 500)`n---`nBody`n"
        (Get-Result).Errors | Should -BeNullOrEmpty
        Set-Skill 'up' 'up-skill' "---`nname: up-skill`ndescription: d`ncompatibility: $('x' * 501)`n---`nBody`n"
        (Get-Result).Errors -join "`n" | Should -BeLike '*up-skill: compatibility has 501 characters, more than 500*'
        Set-Skill 'up' 'up-skill' "---`nname: up-skill`ncompatibility: >`n  $('x' * 300)`n  $('y' * 300)`ndescription: d`n---`nBody`n"
        (Get-Result).Errors -join "`n" | Should -BeLike '*up-skill: compatibility has 601 characters, more than 500*'
    }

    It 'only warns about an upstream SKILL.md over 500 lines' {
        Set-Skill 'up' 'up-skill' ("---`nname: up-skill`ndescription: d`n---`n" + ("line`n" * 500))
        $r = Get-Result
        $r.Errors | Should -BeNullOrEmpty
        $r.Warnings -join "`n" | Should -BeLike '*up-skill: SKILL.md has 504 lines*upstream*'
    }

    It 'accepts a project reference file over 100 lines that starts with a Contents list' {
        Set-Reference 'proj' 'acme-good' 'long.md' 150 $true
        $r = Get-Result
        $r.Errors | Should -BeNullOrEmpty
        $r.Warnings | Should -BeNullOrEmpty
    }

    It 'reports a project reference file over 100 lines without a Contents list' {
        Set-Reference 'proj' 'acme-good' 'long.md' 150 $false
        (Get-Result).Errors -join "`n" | Should -BeLike "*acme-good: references/long.md has 150 lines and no '## Contents' list*"
    }

    It 'reports a Contents list that comes after the first 30 lines' {
        Set-Reference 'proj' 'acme-good' 'long.md' 150 $false
        $file = Join-Path $ai 'skills\proj\acme-good\references\long.md'
        [System.IO.File]::AppendAllText($file, "## Contents`n")
        (Get-Result).Errors -join "`n" | Should -BeLike "*acme-good: references/long.md has 151 lines and no '## Contents' list*"
    }

    It 'accepts a project reference file of exactly 100 lines without a Contents list' {
        Set-Reference 'proj' 'acme-good' 'short.md' 100 $false
        (Get-Result).Errors | Should -BeNullOrEmpty
    }

    It 'does not check reference files of an upstream skill' {
        Set-Reference 'up' 'up-skill' 'long.md' 150 $false
        $r = Get-Result
        $r.Errors | Should -BeNullOrEmpty
        $r.Warnings | Should -BeNullOrEmpty
    }

    It 'reports a project skill without a project prefix, and an upstream skill with one' {
        [System.IO.File]::WriteAllText((Join-Path $ai 'manifest\skills.json'),
            '{ "groups": { "up": { "description": "d", "owner": "o", "source": { "repo": "https://x.test", "installer": "ai_tooling/x.ps1" }, "apps": [], "default": true }, "proj": { "description": "d", "owner": "o", "source": "project", "apps": [], "default": true } }, "profiles": {}, "skills": { "acme-up": { "group": "up" }, "plain": { "group": "proj" } } }')
        Set-Skill 'up' 'acme-up' "---`nname: acme-up`ndescription: d`n---`n"
        Set-Skill 'proj' 'plain' "---`nname: plain`ndescription: d`n---`n"
        $text = (Get-Result).Errors -join "`n"
        $text | Should -BeLike '*plain: a project skill is named acme-*'
        $text | Should -BeLike '*acme-up: the prefixes acme, acmego are for project skills*'
    }

    It 'warns about a deprecated skill' {
        [System.IO.File]::WriteAllText((Join-Path $ai 'manifest\skills.json'),
            '{ "groups": { "up": { "description": "d", "owner": "o", "source": { "repo": "https://x.test", "installer": "ai_tooling/x.ps1" }, "apps": [], "default": true } }, "profiles": {}, "skills": { "up-skill": { "group": "up", "status": "deprecated", "replacedBy": "up-new" }, "up-new": { "group": "up" } } }')
        Set-Skill 'up' 'up-new' "---`nname: up-new`ndescription: d`n---`n"
        (Get-Result).Warnings -join "`n" | Should -BeLike '*up-skill: deprecated, replaced by up-new*'
    }
}

Describe 'Test-UpstreamSkillHashes' {
    BeforeEach {
        $ai = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force -Path (Join-Path $ai 'manifest') | Out-Null
        $skillDir = Join-Path $ai 'skills\up\up-skill'
        New-Item -ItemType Directory -Force -Path $skillDir | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $skillDir 'SKILL.md'), "---`nname: up-skill`ndescription: d`n---`nBody`n")
        # 'up' has a folder; 'gone' has a hash but no folder; 'proj' is project-owned.
        function Set-Manifest($upHash, $goneHash) {
            $up = if ($upHash) { """hash"": ""$upHash"", " } else { '' }
            $gone = if ($goneHash) { """hash"": ""$goneHash"", " } else { '' }
            [System.IO.File]::WriteAllText((Join-Path $ai 'manifest\skills.json'),
                "{ ""groups"": { ""up"": { ""description"": ""d"", ""owner"": ""o"", ""source"": { ""repo"": ""https://x.test"", $up""installer"": ""ai_tooling/x.ps1"" }, ""apps"": [], ""default"": true }, " +
                """gone"": { ""description"": ""d"", ""owner"": ""o"", ""source"": { ""repo"": ""https://y.test"", $gone""installer"": ""ai_tooling/y.ps1"" }, ""apps"": [], ""default"": true }, " +
                """proj"": { ""description"": ""d"", ""owner"": ""o"", ""source"": ""project"", ""apps"": [], ""default"": true } }, ""profiles"": {}, ""skills"": { ""up-skill"": { ""group"": ""up"" } } }")
        }
        function Get-Result { Test-UpstreamSkillHashes (Read-SkillManifest $ai) (Join-Path $ai 'skills') }
        $goodHash = Get-SkillGroupHash (Join-Path $ai 'skills\up')
    }

    It 'lists a group whose folder matches its recorded hash' {
        Set-Manifest $goodHash $null
        $r = Get-Result
        $r.Matches | Should -Be @('up')
        $r.Errors | Should -BeNullOrEmpty
        $r.Warnings | Should -BeNullOrEmpty
    }

    It 'warns about a group without a recorded hash, naming its installer' {
        Set-Manifest $null $null
        $r = Get-Result
        $r.Warnings -join "`n" | Should -BeLike '*upstream group up: no hash recorded yet; the next run of ai_tooling/x.ps1 records it*'
        $r.Errors | Should -BeNullOrEmpty
        $r.Matches | Should -BeNullOrEmpty
    }

    It 'reports a group whose file was changed, naming the group and the installer' {
        Set-Manifest $goodHash $null
        [System.IO.File]::AppendAllText((Join-Path $skillDir 'SKILL.md'), ' ')
        $r = Get-Result
        $r.Errors -join "`n" | Should -BeLike '*upstream group up: a file under ai_tooling/skills/up was changed by hand, a file was added there, or the installer was not run; run ai_tooling/x.ps1 or revert the edit*'
        $r.Matches | Should -BeNullOrEmpty
    }

    It 'reports a group where a file was added' {
        Set-Manifest $goodHash $null
        [System.IO.File]::WriteAllText((Join-Path $skillDir 'notes.md'), 'stray')
        (Get-Result).Errors -join "`n" | Should -BeLike '*upstream group up:*'
    }

    It 'skips project groups and upstream groups without a folder' {
        Set-Manifest $goodHash ('0' * 64)
        $r = Get-Result
        $r.Matches | Should -Be @('up')
        $r.Errors | Should -BeNullOrEmpty
        $r.Warnings | Should -BeNullOrEmpty
    }
}

Describe 'Get-RoutedSkills' {
    It 'reads the Load column of the routing tables, and skips MCP servers' {
        $repo = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force -Path "$repo\appA" | Out-Null
        [System.IO.File]::WriteAllText("$repo\AGENTS.md", "# Root`n`n| When you ... | Load |`n|---|---|`n| do x | ``skill-a`` (with ``skill-b``) |`n`nText with ``not-routed``.`n")
        [System.IO.File]::WriteAllText("$repo\appA\AGENTS.md", "| When you ... | Load |`n|---|---|`n| use y | the ``server-x`` MCP server |`n| use z | ``skill-c`` |`n")
        $r = @(Get-RoutedSkills $repo)
        ($r | ForEach-Object { "$($_.File):$($_.Line):$($_.Name)" }) | Should -Be @('AGENTS.md:5:skill-a', 'AGENTS.md:5:skill-b', 'appA/AGENTS.md:4:skill-c')
    }
}

Describe 'Test-PublishedSkills' {
    BeforeEach {
        $case = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $skillsDir = Join-Path $case 'repo\ai_tooling\skills'
        $all = @{}
        foreach ($n in @('a', 'b')) {
            New-Item -ItemType Directory -Force -Path "$skillsDir\g\$n" | Out-Null
            Set-Content -Path "$skillsDir\g\$n\SKILL.md" -Value $n
            $all[$n] = [pscustomobject]@{ Name = $n; Path = "$skillsDir\g\$n" }
        }
        $copies = @{ Skills = Join-Path $case 'out\.agents\skills'; SkillLinks = 'copy' }
        $junctions = @{ Skills = Join-Path $case 'out\.claude\skills'; SkillLinks = 'junction' }
    }

    It 'finds nothing wrong right after publishing' {
        Publish-Skills $copies @($all.a, $all.b) $skillsDir | Out-Null
        $r = Test-PublishedSkills $copies @($all.a, $all.b) $skillsDir
        ($r.Missing + $r.Extra + $r.Dangling + $r.Stale) | Should -BeNullOrEmpty
    }

    It 'reports a missing skill, one outside the profile, and a stale copy' {
        Publish-Skills $copies @($all.a) $skillsDir | Out-Null
        Set-Content -Path "$skillsDir\g\a\SKILL.md" -Value 'changed'
        $r = Test-PublishedSkills $copies @($all.b) $skillsDir
        $r.Missing | Should -Be @('b')
        $r.Extra | Should -Be @('a')
        (Test-PublishedSkills $copies @($all.a) $skillsDir).Stale | Should -Be @('a')
    }

    It 'reports a copy whose references changed, not only its SKILL.md' {
        New-Item -ItemType Directory -Force -Path "$skillsDir\g\a\references" | Out-Null
        Set-Content -Path "$skillsDir\g\a\references\x.md" -Value 'one'
        Publish-Skills $copies @($all.a) $skillsDir | Out-Null
        (Test-PublishedSkills $copies @($all.a) $skillsDir).Stale | Should -BeNullOrEmpty
        Set-Content -Path "$skillsDir\g\a\references\x.md" -Value 'two'
        (Test-PublishedSkills $copies @($all.a) $skillsDir).Stale | Should -Be @('a')
        Set-Content -Path "$skillsDir\g\a\references\y.md" -Value 'new'
        Publish-Skills $copies @($all.a) $skillsDir | Out-Null
        (Test-PublishedSkills $copies @($all.a) $skillsDir).Stale | Should -BeNullOrEmpty
    }

    It 'reports a junction whose skill is gone' {
        Publish-Skills $junctions @($all.a, $all.b) $skillsDir | Out-Null
        Remove-Item "$skillsDir\g\b" -Recurse -Force
        (Test-PublishedSkills $junctions @($all.a, $all.b) $skillsDir).Dangling | Should -Be @('b')
    }
}

Describe 'Doc link checks' {
    # Written with [char] codes: Windows PowerShell 5.1 reads this file as ANSI.
    It 'makes GitHub''s heading anchors' -TestCases @(
        @{ heading = "PR Validation Pipeline $([char]0x2014) Acme Test"; slug = 'pr-validation-pipeline--acme-test' }
        @{ heading = "Ausf$([char]0xFC)hrung"; slug = "ausf$([char]0xFC)hrung" }
        @{ heading = 'Agent & pool rules'; slug = 'agent--pool-rules' }
        @{ heading = '3. Known pitfalls'; slug = '3-known-pitfalls' }
        @{ heading = 'acme_api compile check (tool)'; slug = 'acme_api-compile-check-tool' }
        @{ heading = 'Button images (`acme_api/Resources/Images`)'; slug = 'button-images-acme_apiresourcesimages' }
        @{ heading = 'See [the guide](x.md) **now**'; slug = 'see-the-guide-now' }
    ) {
        ConvertTo-HeadingSlug $heading | Should -Be $slug
    }

    It 'numbers repeated headings and ignores headings in code blocks' {
        $a = Get-MarkdownAnchors (@('# Intro', '## Setup', '```text', '# Not a heading', '```', '## Setup', '<a id="custom"></a>') -join "`n")
        @($a.Keys | Sort-Object) | Should -Be @('custom', 'intro', 'setup', 'setup-1')
    }

    It 'finds relative links, not URLs, code or inline code' {
        $links = Get-MarkdownLinks (@('[a](x.md) and ![img](pic.png "title")', '[web](https://x.test) [mail](mailto:a@b.c)',
            '`[no](y.md)`', '```', '[no](z.md)', '```', '[anchor](#here) [nested [x]](<w x.md>)') -join "`n")
        ($links | ForEach-Object { "$($_.Line):$($_.Target)" }) | Should -Be @('1:x.md', '1:pic.png', '7:#here', '7:w x.md')
    }

    It 'finds a target with parentheses, a reference definition and HTML href and src' {
        $links = Get-MarkdownLinks (@('[p](dir/(paren).md) and [ref][r]', '[r]: ../ref.md "title"', '<a href="a.md">a</a> <img src="img/b.png">', '<a href="https://x.test">x</a>') -join "`n")
        ($links | ForEach-Object { "$($_.Line):$($_.Target)" }) | Should -Be @('1:dir/(paren).md', '2:../ref.md', '3:a.md', '3:img/b.png')
    }

    Context 'in a repository' {
        BeforeAll {
            $repo = Join-Path $TestDrive 'docrepo'
            New-Item -ItemType Directory -Force -Path "$repo\ai_tooling\manifest", "$repo\ai_tooling\skills\proj\acme-x", "$repo\appA\documentation", "$repo\.vscode", "$repo\vendor" | Out-Null
            [System.IO.File]::WriteAllText("$repo\ai_tooling\manifest\skills.json", '{ "groups": { "proj": { "description": "d", "owner": "o", "source": "project", "apps": [], "default": true } }, "profiles": {}, "skills": { "acme-x": { "group": "proj" } } }')
            [System.IO.File]::WriteAllText("$repo\ai_tooling\skills\proj\acme-x\SKILL.md", "---`nname: acme-x`ndescription: d`n---`nSee [overview](../../../../appA/documentation/overview.md#run-it).`n")
            [System.IO.File]::WriteAllText("$repo\appA\AGENTS.md", "# appA`n")
            [System.IO.File]::WriteAllText("$repo\appA\documentation\overview.md", "# Overview`n## Run it`nVS Code task: ``appA: Build``. Launch config ``appA: Serve``.`nProgress ``appA: 100%`` is a percentage.`n[agents](../AGENTS.md) [gone](missing.md) [bad anchor](../AGENTS.md#nope) [case](../agents.md)`n")
            [System.IO.File]::WriteAllText("$repo\vendor\notes.md", "[ignored](nowhere.md)`n")
            New-Item -ItemType Directory -Force -Path "$repo\ai_tooling\documentation", "$repo\ai_tooling\skills\up\u" | Out-Null
            [System.IO.File]::WriteAllText("$repo\ai_tooling\documentation\topic.md", "# Topic`n")
            [System.IO.File]::WriteAllText("$repo\ai_tooling\skills\up\u\SKILL.md", "[upstream](nowhere.md)`n")
            [System.IO.File]::WriteAllText("$repo\.vscode\tasks.json", "{`n  // comment`n  ""tasks"": [ { ""label"": ""appA: Build"" } ]`n}`n")
            [System.IO.File]::WriteAllText("$repo\.vscode\launch.json", "{ ""configurations"": [ { ""name"": ""appA: Debug"" } ] }`n")
            # Windows PowerShell 5.1 turns git's stderr into an error under Stop.
            $ErrorActionPreference = 'Continue'
            git -C $repo init -q 2>&1 | Out-Null
            git -C $repo add -A 2>&1 | Out-Null
            $problems = @(Test-DocLinks $repo)
            $text = ($problems | ForEach-Object { "$($_.File):$($_.Line) $($_.Problem)" }) -join "`n"
        }

        It 'covers the project skills, the tooling app''s own files and app documentation, not other folders or upstream skills' {
            $docs = Get-DocFiles $repo (Get-TrackedFiles $repo)
            $docs | Should -Contain 'ai_tooling/skills/proj/acme-x/SKILL.md'
            $docs | Should -Contain 'ai_tooling/documentation/topic.md'
            $docs | Should -Contain 'appA/documentation/overview.md'
            $docs | Should -Not -Contain 'vendor/notes.md'
            $docs | Should -Not -Contain 'ai_tooling/skills/up/u/SKILL.md'
        }

        It 'accepts a link with an anchor that exists, and a task that exists' {
            $text | Should -Not -BeLike '*SKILL.md*'
            $text | Should -Not -BeLike "*'appA: Build'*"
        }

        It 'reports <name>' -TestCases @(
            @{ name = 'a missing file'; expected = "*overview.md:5 link 'missing.md': appA/documentation/missing.md does not exist*" }
            @{ name = 'a missing anchor'; expected = "*overview.md:5 link '../AGENTS.md#nope': no heading '#nope' in appA/AGENTS.md*" }
            @{ name = 'a path whose case differs'; expected = "*overview.md:5 link '../agents.md': the file is appA/AGENTS.md (case differs*" }
            @{ name = 'an unknown launch configuration'; expected = "*overview.md:3 VS Code task or launch configuration 'appA: Serve' is not in*" }
        ) {
            $text | Should -BeLike $expected
        }

        It 'does not take a name on a line without task or launch for a VS Code name' {
            $text | Should -Not -BeLike '*appA: 100%*'
        }

        It 'skips the VS Code names when .vscode is not checked out (a sparse checkout)' {
            Remove-Item "$repo\.vscode" -Recurse -Force
            $without = (@(Test-DocLinks $repo) | ForEach-Object { $_.Problem }) -join "`n"
            $without | Should -Not -BeLike '*VS Code*'
            $without | Should -BeLike "*missing.md*"
        }
    }
}

Describe 'Resolve-AgentChoice' {
    It 'returns nothing for <name>' -TestCases @(
        @{ name = 'an empty answer'; answer = '' }
        @{ name = 'whitespace'; answer = '   ' }
        @{ name = 'null'; answer = $null }
    ) {
        @(Resolve-AgentChoice $answer $AgentKeys).Count | Should -Be 0
    }

    It 'returns every agent for "<answer>"' -TestCases @(@{ answer = 'a' }, @{ answer = 'all' }, @{ answer = ' all ' }) {
        Resolve-AgentChoice $answer $AgentKeys | Should -Be $AgentKeys
    }

    It 'maps "<answer>" to <expected>' -TestCases @(
        @{ answer = '1,3'; expected = @('claude', 'copilot') }
        @{ answer = '2 4'; expected = @('gemini', 'cursor') }
        @{ answer = 'Claude, CURSOR'; expected = @('claude', 'cursor') }
        @{ answer = '0 5 foo 2'; expected = @('gemini') }
        @{ answer = '1 claude 1'; expected = @('claude') }
    ) {
        Resolve-AgentChoice $answer $AgentKeys | Should -Be $expected
    }
}

Describe 'Select-AgentsInteractively' {
    It 'does not prompt where there is no console (CI)' {
        Mock Read-Host { throw 'prompted' } -ModuleName AgentSetup
        $saved = $env:CI
        try {
            $env:CI = 'true'
            @(Select-AgentsInteractively (Get-AgentLayouts $AiDir 'C:\Out' 'C:\Home')).Count | Should -Be 0
        } finally { $env:CI = $saved }
        Should -Invoke Read-Host -Times 0 -ModuleName AgentSetup
    }
}

Describe 'Find-InstalledAgents' {
    BeforeEach {
        # TestDrive is shared by every test in a Describe: one folder per test.
        $case = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $userHome = Join-Path $case 'home'
        New-Item -ItemType Directory -Force -Path $userHome | Out-Null
        $layouts = Get-AgentLayouts $AiDir (Join-Path $case 'repo') $userHome
        Mock Get-Command { $null } -ParameterFilter { $Name -eq 'claude' } -ModuleName AgentSetup
    }

    It 'finds nothing on a clean machine' {
        @(Find-InstalledAgents $layouts $userHome).Count | Should -Be 0
    }

    It 'finds agents from their home folders and VS Code extensions' {
        New-Item -ItemType Directory -Force -Path "$userHome\.cursor", "$userHome\.gemini\antigravity-ide",
            "$userHome\.vscode\extensions\anthropic.claude-code-2.0.0", "$userHome\.vscode\extensions\github.copilot-chat-1.0.0" | Out-Null
        @(Find-InstalledAgents $layouts $userHome) | Should -Be $AgentKeys
    }

    It 'finds Claude Code from its command on PATH (JetBrains)' {
        Mock Get-Command { [pscustomobject]@{ Name = 'claude' } } -ParameterFilter { $Name -eq 'claude' } -ModuleName AgentSetup
        @(Find-InstalledAgents $layouts $userHome) | Should -Be @('claude')
    }

    It 'does not count a layout that is only on disk' {
        New-Item -ItemType Directory -Force -Path $layouts.copilot.Skills | Out-Null
        @(Find-InstalledAgents $layouts $userHome).Count | Should -Be 0
    }
}

Describe 'Get-AgentsOnDisk' {
    BeforeEach {
        $case = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $layouts = Get-AgentLayouts $AiDir (Join-Path $case 'repo') (Join-Path $case 'home')
    }

    It 'keeps refreshing a layout that is on disk although its agent is gone' {
        New-PublishedSkill $layouts.copilot.Skills
        @(Get-AgentsOnDisk $layouts) | Should -Be @('copilot')
    }

    It 'does not count a skills folder that holds only a developer''s own skills' {
        New-Item -ItemType Directory -Force -Path (Join-Path $layouts.claude.Skills 'my-skill') | Out-Null
        @(Get-AgentsOnDisk $layouts).Count | Should -Be 0
    }

    It 'does not count an MCP config alone' {
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $layouts.gemini.Mcp) | Out-Null
        Set-Content -Path $layouts.gemini.Mcp -Value '{ }'
        @(Get-AgentsOnDisk $layouts).Count | Should -Be 0
    }

    It 'lists the layouts in manifest order' {
        foreach ($key in 'cursor', 'claude') { New-PublishedSkill $layouts[$key].Skills }
        @(Get-AgentsOnDisk $layouts) | Should -Be @('claude', 'cursor')
    }
}

Describe 'Get-ShadowingEntries' {
    BeforeEach {
        $case = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $repo = Join-Path $case 'repo'
        $home_ = Join-Path $case 'home'
        $appData = Join-Path $case 'appdata'
        New-Item -ItemType Directory -Force -Path $repo, $home_, $appData | Out-Null
        $layouts = Get-AgentLayouts $AiDir $repo $home_
        $skills = [pscustomobject]@{ Skills = @{ 'acme-a' = $true } }
        $claudeJson = Join-Path $home_ '.claude.json'
    }

    It 'finds a personal skill named like a project one' {
        New-PublishedSkill $layouts.claude.Skills
        New-Item -ItemType Directory -Force -Path "$home_\.claude\skills\acme-a", "$home_\.claude\skills\own-skill" | Out-Null
        $found = @(Get-ShadowingEntries $layouts $home_ $appData $repo $skills @('azure-devops'))
        $found.Count | Should -Be 1
        $found[0].Kind | Should -Be 'skill'
        $found[0].Name | Should -Be 'acme-a'
    }

    It 'finds a local-scope Claude MCP server for this repository' {
        New-PublishedSkill $layouts.claude.Skills
        $key = $repo.ToUpperInvariant().Replace('\', '/') + '/'
        $json = @{ projects = @{ $key = @{ mcpServers = @{ 'Azure-DevOps' = @{ command = 'x' }; 'own' = @{ command = 'y' } } } } } | ConvertTo-Json -Depth 8
        [System.IO.File]::WriteAllText($claudeJson, $json)
        $found = @(Get-ShadowingEntries $layouts $home_ $appData $repo $skills @('azure-devops'))
        $found.Count | Should -Be 1
        $found[0].Kind | Should -Be 'mcp'
        $found[0].Hides | Should -BeTrue
    }

    It 'reads a .claude.json whose project keys differ only in case' {
        New-PublishedSkill $layouts.claude.Skills
        $key = $repo.Replace('\', '/')
        [System.IO.File]::WriteAllText($claudeJson, "{ ""projects"": { ""C:/Other"": { }, ""c:/other"": { }, ""$key"": { ""mcpServers"": { ""azure-devops"": { } } } } }")
        $found = @(Get-ShadowingEntries $layouts $home_ $appData $repo $skills @('azure-devops'))
        $found.Count | Should -Be 1
        $found[0].Kind | Should -Be 'mcp'
    }

    It 'reports a personal MCP config it cannot read, and does not throw' {
        New-PublishedSkill $layouts.claude.Skills
        [System.IO.File]::WriteAllText($claudeJson, '{ }')
        $lock = [System.IO.File]::Open($claudeJson, 'Open', 'Read', 'None')
        try { $found = @(Get-ShadowingEntries $layouts $home_ $appData $repo $skills @('azure-devops')) }
        finally { $lock.Dispose() }
        $found.Kind | Should -Be @('unreadable')
    }

    It 'skips an empty personal MCP config' {
        New-PublishedSkill $layouts.claude.Skills
        [System.IO.File]::WriteAllText($claudeJson, '')
        @(Get-ShadowingEntries $layouts $home_ $appData $repo $skills @('azure-devops')).Count | Should -Be 0
    }

    It 'ignores a user-scope Claude MCP server' {
        New-PublishedSkill $layouts.claude.Skills
        [System.IO.File]::WriteAllText($claudeJson, '{ "mcpServers": { "azure-devops": { "command": "x" } } }')
        @(Get-ShadowingEntries $layouts $home_ $appData $repo $skills @('azure-devops')).Count | Should -Be 0
    }

    It 'ignores the personal folders of an agent that is not set up here' {
        New-Item -ItemType Directory -Force -Path "$home_\.claude\skills\acme-a" | Out-Null
        [System.IO.File]::WriteAllText($claudeJson, '{ "mcpServers": { "azure-devops": { } }, "projects": { }, "x": 1 }')
        @(Get-ShadowingEntries $layouts $home_ $appData $repo $skills @('azure-devops')).Count | Should -Be 0
    }

    It 'reports a project server left in Antigravity''s global MCP config, not the one setup writes to the workspace' {
        New-PublishedSkill $layouts.gemini.Skills
        foreach ($f in $layouts.gemini.Mcp, "$home_\.gemini\config\mcp_config.json") {
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $f) | Out-Null
            [System.IO.File]::WriteAllText($f, '{ "mcpServers": { "azure-devops": { "command": "x" } } }')
        }
        $found = @(Get-ShadowingEntries $layouts $home_ $appData $repo $skills @('azure-devops'))
        $found.Count | Should -Be 1
        "$($found[0].Kind) $($found[0].Location) $($found[0].Hides)" | Should -Be "mcp $home_\.gemini\config\mcp_config.json True"
    }

    It 'ignores a personal server named like a project server the agent does not get (skipAgents)' {
        New-PublishedSkill $layouts.gemini.Skills
        New-Item -ItemType Directory -Force -Path "$home_\.gemini\config" | Out-Null
        [System.IO.File]::WriteAllText("$home_\.gemini\config\mcp_config.json", '{ "mcpServers": { "nx": { "command": "x" } } }')
        @(Get-ShadowingEntries $layouts $home_ $appData $repo $skills @('nx') @{ nx = @('gemini') }).Count | Should -Be 0
    }

    It 'reports a personal MCP config that is not valid JSON' {
        New-PublishedSkill $layouts.claude.Skills
        [System.IO.File]::WriteAllText($claudeJson, '{ "projects": ')
        $found = @(Get-ShadowingEntries $layouts $home_ $appData $repo $skills @('azure-devops'))
        $found.Count | Should -Be 1
        $found[0].Kind | Should -Be 'unreadable'
    }
}

Describe 'New-FolderLink' {
    BeforeEach {
        $case = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $target = Join-Path $case 'agents'
        New-Item -ItemType Directory -Force -Path "$target\one" | Out-Null
        Set-Content -Path "$target\one\x.md" -Value 'x'
        $link = Join-Path $case 'out\.claude\agents'
    }

    It 'creates a junction to the target' {
        New-FolderLink $target $link | Should -Be 'junction'
        (Get-Item $link -Force).LinkType | Should -Be 'Junction'
        Test-Path "$link\one\x.md" | Should -BeTrue
    }

    It 'replaces an existing junction without touching the target' {
        New-FolderLink $target $link | Out-Null
        New-FolderLink $target $link | Should -Be 'junction'
        Test-Path "$target\one\x.md" | Should -BeTrue
    }

    It 'replaces a plain folder left by an earlier copy, without following a junction inside it' {
        New-Item -ItemType Directory -Force -Path "$link\stale" | Out-Null
        New-Item -ItemType Junction -Path "$link\inner" -Value "$target\one" | Out-Null
        New-FolderLink $target $link | Should -Be 'junction'
        Test-Path "$link\stale" | Should -BeFalse
        Test-Path "$target\one\x.md" | Should -BeTrue
    }
}

Describe 'Remove-FolderSafely' {
    BeforeEach {
        $case = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $source = Join-Path $case 'source'
        New-Item -ItemType Directory -Force -Path "$source\a" | Out-Null
        Set-Content -Path "$source\a\SKILL.md" -Value 'x'
    }

    It 'removes a folder of junctions and leaves their targets alone' {
        $dir = Join-Path $case 'published'
        New-Item -ItemType Directory -Force -Path "$dir\deeper" | Out-Null
        New-Item -ItemType Junction -Path "$dir\a" -Value "$source\a" | Out-Null
        New-Item -ItemType Junction -Path "$dir\deeper\a" -Value "$source\a" | Out-Null
        Remove-FolderSafely $dir
        Test-Path $dir | Should -BeFalse
        Test-Path "$source\a\SKILL.md" | Should -BeTrue
    }

    It 'removes a junction itself, not its target' {
        New-Item -ItemType Junction -Path "$case\link" -Value $source | Out-Null
        Remove-FolderSafely "$case\link"
        Test-Path "$case\link" | Should -BeFalse
        Test-Path "$source\a\SKILL.md" | Should -BeTrue
    }

    It 'does nothing for a path that does not exist' {
        { Remove-FolderSafely "$case\nothing" } | Should -Not -Throw
    }
}

Describe 'Publish-Skills' {
    BeforeEach {
        $case = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $skillsDir = Join-Path $case 'repo\ai_tooling\skills'
        $all = @{}
        foreach ($rel in @('g\a', 'g\b', 'h\c')) {
            New-Item -ItemType Directory -Force -Path "$skillsDir\$rel" | Out-Null
            Set-Content -Path "$skillsDir\$rel\SKILL.md" -Value "---`nname: $(Split-Path -Leaf $rel)`n---"
            $all[(Split-Path -Leaf $rel)] = [pscustomobject]@{ Name = (Split-Path -Leaf $rel); Path = "$skillsDir\$rel" }
        }
        $junctions = @{ Skills = Join-Path $case 'out\.claude\skills'; SkillLinks = 'junction' }
        $copies = @{ Skills = Join-Path $case 'out\.agents\skills'; SkillLinks = 'copy' }
    }

    It 'publishes one junction per skill' {
        $r = Publish-Skills $junctions @($all.a, $all.c) $skillsDir
        $r.Junctions | Should -Be 2
        @(Get-ChildItem $junctions.Skills -Directory).Name | Should -Be @('a', 'c')
        (Get-Item "$($junctions.Skills)\a" -Force).LinkType | Should -Be 'Junction'
        @((Get-Item "$($junctions.Skills)\c" -Force).Target)[0] | Should -Be "$skillsDir\h\c"
    }

    It 'publishes one marked copy per skill where the agent needs copies' {
        $r = Publish-Skills $copies @($all.a, $all.b) $skillsDir
        $r.Copies | Should -Be 2
        (Get-Item "$($copies.Skills)\a" -Force).LinkType | Should -BeNullOrEmpty
        Test-Path "$($copies.Skills)\a\SKILL.md" | Should -BeTrue
        Get-Content "$($copies.Skills)\a\$SkillCopyMarker" -Raw | Should -BeLike "*$skillsDir\g\a*"
    }

    It 'removes what it published before and is no longer chosen, and reports it' {
        Publish-Skills $junctions @($all.a, $all.b, $all.c) $skillsDir | Out-Null
        Publish-Skills $copies @($all.a, $all.b) $skillsDir | Out-Null
        (Publish-Skills $junctions @($all.a) $skillsDir).Removed | Should -Be @('b', 'c')
        (Publish-Skills $copies @($all.a) $skillsDir).Removed | Should -Be @('b')
        @(Get-ChildItem $junctions.Skills -Directory).Name | Should -Be @('a')
        @(Get-ChildItem $copies.Skills -Directory).Name | Should -Be @('a')
        @(Get-ChildItem $skillsDir -Recurse -Filter SKILL.md).Count | Should -Be 3
    }

    It 'removes a junction whose skill no longer exists (a branch switch)' {
        Publish-Skills $junctions @($all.a, $all.c) $skillsDir | Out-Null
        Remove-Item "$skillsDir\h" -Recurse -Force
        (Publish-Skills $junctions @($all.a) $skillsDir).Removed | Should -Be @('c')
        Get-Item "$($junctions.Skills)\c" -Force -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
    }

    It 'refreshes a copy on every run' {
        Publish-Skills $copies @($all.a) $skillsDir | Out-Null
        Set-Content -Path "$skillsDir\g\a\SKILL.md" -Value 'changed'
        Publish-Skills $copies @($all.a) $skillsDir | Out-Null
        Get-Content "$($copies.Skills)\a\SKILL.md" -Raw | Should -BeLike 'changed*'
    }

    It 'switches a skill from a copy to a junction when the agent''s setting changes' {
        Publish-Skills $copies @($all.a) $skillsDir | Out-Null
        $layout = @{ Skills = $copies.Skills; SkillLinks = 'junction' }
        (Publish-Skills $layout @($all.a) $skillsDir).Junctions | Should -Be 1
        (Get-Item "$($copies.Skills)\a" -Force).LinkType | Should -Be 'Junction'
    }

    It 'takes over a junction into the ai_tooling\skills of a moved or other clone' {
        New-Item -ItemType Directory -Force -Path "$case\old\ai_tooling\skills\g\a", $junctions.Skills | Out-Null
        Set-Content -Path "$case\old\ai_tooling\skills\g\a\SKILL.md" -Value 'old'
        New-Item -ItemType Junction -Path "$($junctions.Skills)\a" -Value "$case\old\ai_tooling\skills\g\a" | Out-Null
        $r = Publish-Skills $junctions @($all.a) $skillsDir
        $r.Skipped | Should -BeNullOrEmpty
        @((Get-Item "$($junctions.Skills)\a" -Force).Target)[0] | Should -Be "$skillsDir\g\a"
        Test-Path "$case\old\ai_tooling\skills\g\a\SKILL.md" | Should -BeTrue
    }

    It 'leaves alone a junction into another ai_tooling\skills that is not named like a skill or points to another folder' {
        New-Item -ItemType Directory -Force -Path "$case\other\ai_tooling\skills\g\mine", "$case\other\ai_tooling\skills\g\x", $junctions.Skills | Out-Null
        New-Item -ItemType Junction -Path "$($junctions.Skills)\mine" -Value "$case\other\ai_tooling\skills\g\mine" | Out-Null
        New-Item -ItemType Junction -Path "$($junctions.Skills)\c" -Value "$case\other\ai_tooling\skills\g\x" | Out-Null
        $r = Publish-Skills $junctions @($all.a) $skillsDir @('a', 'b', 'c')
        $r.Removed | Should -BeNullOrEmpty
        (Get-Item "$($junctions.Skills)\mine" -Force).LinkType | Should -Be 'Junction'
        @((Get-Item "$($junctions.Skills)\c" -Force).Target)[0] | Should -Be "$case\other\ai_tooling\skills\g\x"
    }

    It 'leaves a junction at the skills folder alone when it points somewhere else, and publishes nothing there' {
        New-Item -ItemType Directory -Force -Path "$case\personal\mine", (Split-Path -Parent $junctions.Skills) | Out-Null
        New-Item -ItemType Junction -Path $junctions.Skills -Value "$case\personal" | Out-Null
        $r = Publish-Skills $junctions @($all.a) $skillsDir
        $r.Foreign | Should -Be "$case\personal"
        (Get-Item $junctions.Skills -Force).LinkType | Should -Be 'Junction'
        @(Get-ChildItem "$case\personal" -Directory).Name | Should -Be @('mine')
    }

    It 'leaves a junction at the skills folder alone also when it points into the tooling''s skills' {
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $junctions.Skills) | Out-Null
        New-Item -ItemType Junction -Path $junctions.Skills -Value $skillsDir | Out-Null
        $r = Publish-Skills $junctions @($all.a) $skillsDir
        $r.Foreign | Should -Be $skillsDir
        $r.Junctions | Should -Be 0
        (Get-Item $junctions.Skills -Force).LinkType | Should -Be 'Junction'
        Test-Path "$skillsDir\a" | Should -BeFalse
    }

    It 'leaves a developer''s own folders alone, and reports one named like a project skill' {
        New-Item -ItemType Directory -Force -Path "$($junctions.Skills)\mine", "$($junctions.Skills)\b" | Out-Null
        Set-Content -Path "$($junctions.Skills)\mine\SKILL.md" -Value 'mine'
        Set-Content -Path "$($junctions.Skills)\b\SKILL.md" -Value 'my b'
        $r = Publish-Skills $junctions @($all.a, $all.b) $skillsDir
        $r.Skipped | Should -Be @('b')
        $r.Junctions | Should -Be 1
        Get-Content "$($junctions.Skills)\mine\SKILL.md" -Raw | Should -BeLike 'mine*'
        Get-Content "$($junctions.Skills)\b\SKILL.md" -Raw | Should -BeLike 'my b*'
    }
}

Describe 'Local profile' {
    BeforeEach { $out = Join-Path $TestDrive ([guid]::NewGuid().ToString('N')) }

    It 'is default when none was saved' {
        Read-LocalProfile $out | Should -Be @('default')
    }

    It 'reads back what was saved' {
        Write-LocalProfile $out @('one', 'two')
        Read-LocalProfile $out | Should -Be @('one', 'two')
        [System.IO.File]::ReadAllText((Join-Path $out 'ai_tooling\localprofile')) | Should -Be "one,two`n"
    }
}

Describe 'Publish-ExternalSkillConfig' {
    BeforeEach {
        $case = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $src = Join-Path $case 'src'
        $out = Join-Path $case 'out'
        New-Item -ItemType Directory -Force -Path $src | Out-Null
        [System.IO.File]::WriteAllText("$src\issue-tracker.md", "# Issue tracker`n")
        [System.IO.File]::WriteAllText("$src\domain.md", "# Domain`n")
    }

    It 'writes a marked copy of every source file into docs\agents' {
        Publish-ExternalSkillConfig $src $out | Should -Be 2
        $copy = [System.IO.File]::ReadAllText("$out\docs\agents\issue-tracker.md")
        $copy | Should -BeLike '<!-- Generated by ai_tooling/setup.ps1 from ai_tooling/external-skill-config/issue-tracker.md.*'
        $copy | Should -BeLike "*`n# Issue tracker`n"
    }

    It 'removes a copy whose source is gone and leaves other files alone' {
        Publish-ExternalSkillConfig $src $out | Out-Null
        Remove-Item "$src\domain.md"
        [System.IO.File]::WriteAllText("$out\docs\agents\mine.md", "mine`n")
        Publish-ExternalSkillConfig $src $out | Should -Be 1
        Test-Path "$out\docs\agents\domain.md" | Should -BeFalse
        Test-Path "$out\docs\agents\mine.md" | Should -BeTrue
    }
}

Describe 'Remove-PathWhole' {
    BeforeEach { $dir = Join-Path $TestDrive ([guid]::NewGuid().ToString('N')) }

    It 'returns nothing for a path that is not there' {
        Remove-PathWhole (Join-Path $dir 'missing') | Should -BeNullOrEmpty
    }

    It 'removes a file, a folder and a junction without touching its target' {
        New-Item -ItemType Directory -Force -Path "$dir\folder\sub", "$dir\target" | Out-Null
        Set-Content -Path "$dir\file.txt" -Value 'x'
        Set-Content -Path "$dir\folder\sub\f.txt" -Value 'x'
        Set-Content -Path "$dir\target\keep.txt" -Value 'keep'
        New-Item -ItemType Junction -Path "$dir\link" -Value "$dir\target" | Out-Null
        $problems = @('file.txt', 'folder', 'link' | ForEach-Object { Remove-PathWhole "$dir\$_" } | Where-Object { $_ })
        $problems | Should -BeNullOrEmpty
        @(Get-ChildItem $dir -Force | ForEach-Object { $_.Name }) | Should -Be @('target')
        Test-Path "$dir\target\keep.txt" | Should -BeTrue
    }

    It 'renames a folder before removing it, and returns the problem when it is in use' {
        New-Item -ItemType Directory -Force -Path "$dir\folder" | Out-Null
        Set-Content -Path "$dir\folder\a.txt" -Value 'x'
        Set-Content -Path "$dir\folder\b.txt" -Value 'x'
        $lock = [System.IO.File]::Open("$dir\folder\a.txt", 'Open', 'Read', 'None')
        try {
            $problem = Remove-PathWhole "$dir\folder"
        } finally { $lock.Dispose() }
        $problem | Should -Not -BeNullOrEmpty
        # Removing in place would have deleted b.txt before it reached a.txt.
        (Test-Path "$dir\folder\a.txt") -and (Test-Path "$dir\folder\b.txt") | Should -BeTrue
    }

    It 'removes a <what> that is in use only for a moment' -TestCases @(
        @{ what = 'folder'; path = 'folder'; file = 'folder\a.txt' }, @{ what = 'file'; path = 'a.txt'; file = 'a.txt' }
    ) {
        # Antivirus can hold a freshly copied file open for a moment; the lock
        # is released from another thread while Remove-PathWhole is running.
        if (-not ('TestLockRelease' -as [type])) {
            Add-Type -TypeDefinition 'public static class TestLockRelease { public static void After(System.IDisposable d, int ms) { System.Threading.Tasks.Task.Delay(ms).ContinueWith(t => d.Dispose()); } }'
        }
        New-Item -ItemType Directory -Force -Path "$dir\folder" | Out-Null
        Set-Content -Path "$dir\$file" -Value 'x'
        $lock = [System.IO.File]::Open("$dir\$file", 'Open', 'Read', 'None')
        [TestLockRelease]::After($lock, 50)
        try { $problem = Remove-PathWhole "$dir\$path" } finally { $lock.Dispose() }
        $problem | Should -BeNullOrEmpty
        Test-Path "$dir\$path" | Should -BeFalse
    }
}

Describe 'Remove-LocalSourcesEntry' {
    BeforeEach {
        $out = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $file = Join-Path $out 'ai_tooling\localsources.json'
    }

    It 'drops only that agent''s entry' {
        Write-LocalSourcesFile $out @{ claude = @{ 'a' = '1' }; gemini = @{ 'b' = '2' }; cursor = @{ 'c' = '3' } } @('claude', 'gemini', 'cursor')
        Remove-LocalSourcesEntry $out 'gemini'
        $record = Read-LocalSources $out
        @($record.Keys | Sort-Object) | Should -Be @('claude', 'cursor')
        $record.cursor.c | Should -Be '3'
        # The agents stay in the order of the file.
        @((Read-Utf8 $file | ConvertFrom-Json).agents.PSObject.Properties.Name) | Should -Be @('claude', 'cursor')
    }

    It 'does nothing without the file or without the entry' {
        Remove-LocalSourcesEntry $out 'gemini'
        Test-Path $file | Should -BeFalse
        Write-LocalSourcesFile $out @{ claude = @{ 'a' = '1' } } @('claude')
        $before = Read-Utf8 $file
        Remove-LocalSourcesEntry $out 'gemini'
        Read-Utf8 $file | Should -Be $before
    }
}

Describe 'Remove-AgentLayout' {
    BeforeAll {
        $manifest = Read-SkillManifest $AiDir
        $coreNames = Resolve-SkillProfile $manifest @('default')
    }
    BeforeEach {
        $case = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $out = Join-Path $case 'out'
        $home_ = Join-Path $case 'home'
        New-Item -ItemType Directory -Force -Path $out, $home_ | Out-Null
        $layouts = Get-AgentLayouts $AiDir $out $home_
        $sources = Get-SetupSources $AiDir $out $home_ $manifest $coreNames
        # Fixture servers, so the tests do not depend on the project's own.
        $sources.Servers = '{ "web": { "transport": "http", "url": "https://example.test/mcp" }, "tool": { "transport": "stdio", "command": "node", "args": ["${REPO_ROOT}/ai_tooling/x.js"] } }' | ConvertFrom-Json
        # The MCP files an earlier setup version wrote (mcp.legacyFiles), as a project that moves its servers gets them.
        $layouts.gemini.McpLegacy = @("$home_\.gemini\config\mcp_config.json", "$home_\.gemini\antigravity-ide\mcp_config.json")
        Mock Write-Host { } -ModuleName AgentSetup
        Mock Write-Warning { } -ModuleName AgentSetup
    }

    It 'removes every file setup wrote for <key>' -TestCases @(
        @{ key = 'claude' }, @{ key = 'gemini' }, @{ key = 'copilot' }, @{ key = 'cursor' }
    ) {
        Publish-AgentLayout $layouts[$key] $sources
        $r = Remove-AgentLayout $layouts[$key] $sources $out $home_
        $r.Kept | Should -BeNullOrEmpty
        # Except a file of mcp.keepValid, which stays with an empty server list, and the folders it is in.
        $keepValid = @(foreach ($f in @($layouts[$key].McpKeepValid)) { $p = $f; while ($p -and ($p -ne $home_)) { $p; $p = Split-Path -Parent $p } })
        @(Get-ChildItem $out -Force) + @(Get-ChildItem $home_ -Recurse -Force | Where-Object { $keepValid -notcontains $_.FullName }) | Should -BeNullOrEmpty
    }

    It 'leaves a developer''s own skill, subagent and MCP server' {
        $layout = $layouts.claude
        New-Item -ItemType Directory -Force -Path $layout.Subagents, (Join-Path $layout.Skills 'my-skill') | Out-Null
        Set-Content -Path (Join-Path $layout.Subagents 'mine.md') -Value 'mine'
        Set-Content -Path (Join-Path $layout.Skills 'my-skill\SKILL.md') -Value 'mine'
        Publish-AgentLayout $layout $sources
        $cfg = Read-Utf8 $layout.Mcp | ConvertFrom-Json
        $cfg.mcpServers | Add-Member -NotePropertyName 'mine' -NotePropertyValue ([pscustomobject]@{ command = 'x' })
        Write-Utf8File $layout.Mcp ($cfg | ConvertTo-Json -Depth 8)

        Remove-AgentLayout $layout $sources $out $home_ | Out-Null

        $left = @{
            skill    = Test-Path (Join-Path $layout.Skills 'my-skill\SKILL.md')
            subagent = Test-Path (Join-Path $layout.Subagents 'mine.md')
            server   = (Read-Utf8 $layout.Mcp | ConvertFrom-Json).mcpServers.mine.command -eq 'x'
            others   = @(Get-ChildItem $layout.Skills -Force).Count -eq 1
        }
        @($left.Values | Where-Object { -not $_ }).Count | Should -Be 0
    }

    It 'reports a path in use and leaves it whole' {
        # Antigravity gets copies of the skills, not junctions.
        Publish-AgentLayout $layouts.gemini $sources
        $copy = Join-Path $layouts.gemini.Skills $coreNames[0]
        $lock = [System.IO.File]::Open((Join-Path $copy 'SKILL.md'), 'Open', 'Read', 'None')
        try {
            $r = Remove-AgentLayout $layouts.gemini $sources $out $home_
        } finally { $lock.Dispose() }
        @($r.Kept | ForEach-Object { $_.Path }) | Should -Contain ".agents\skills\$($coreNames[0])"
        Get-ChildItem $copy -Recurse -File -Force | ForEach-Object { $_.Name } | Should -Contain 'SKILL.md'
    }

    It 'removes only the managed entries from the workspace MCP config' {
        Publish-AgentLayout $layouts.gemini $sources
        $cfg = Read-Utf8 $layouts.gemini.Mcp | ConvertFrom-Json
        $cfg.mcpServers | Add-Member -NotePropertyName 'mine' -NotePropertyValue ([pscustomobject]@{ command = 'x' })
        Write-Utf8File $layouts.gemini.Mcp ($cfg | ConvertTo-Json -Depth 8)
        $r = Remove-AgentLayout $layouts.gemini $sources $out $home_
        @((Read-Utf8 $layouts.gemini.Mcp | ConvertFrom-Json).mcpServers.PSObject.Properties.Name) | Should -Be @('mine')
        $r.Edited | Should -Be @('.agents\mcp_config.json')
    }

    It 'removes the managed entries from an MCP config an earlier setup wrote (mcp.legacyFiles)' {
        # Written after the publish, which cleans it too (Clear-LegacyMcpConfigs).
        Publish-AgentLayout $layouts.gemini $sources
        $legacy = $layouts.gemini.McpLegacy[0]
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $legacy) | Out-Null
        Write-Utf8File $legacy '{ "mcpServers": { "web": { "command": "x" }, "mine": { "command": "y" } } }'
        $r = Remove-AgentLayout $layouts.gemini $sources $out $home_
        @((Read-Utf8 $legacy | ConvertFrom-Json).mcpServers.PSObject.Properties.Name) | Should -Be @('mine')
        $r.Edited | Should -Contain '~\.gemini\config\mcp_config.json'
    }

    It 'deletes an MCP config an earlier setup wrote when only its servers were in it' {
        Publish-AgentLayout $layouts.gemini $sources
        $legacy = $layouts.gemini.McpLegacy[1]
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $legacy) | Out-Null
        Write-Utf8File $legacy '{ "mcpServers": { "web": { "command": "x" } } }'
        $r = Remove-AgentLayout $layouts.gemini $sources $out $home_
        Test-Path $legacy | Should -BeFalse
        $r.Removed | Should -Contain '~\.gemini\antigravity-ide\mcp_config.json'
    }

    It 'keeps a file of mcp.keepValid with an empty server list when only its servers were in it' {
        Publish-AgentLayout $layouts.gemini $sources
        $global = $layouts.gemini.McpKeepValid[0]
        Write-Utf8File $global '{ "mcpServers": { "web": { "command": "x" } } }'
        $r = Remove-AgentLayout $layouts.gemini $sources $out $home_
        $cfg = Read-Utf8 $global | ConvertFrom-Json
        "$(@($cfg.PSObject.Properties.Name) -join ',') $(@($cfg.mcpServers.PSObject.Properties).Count)" | Should -Be 'mcpServers 0'
        $r.Edited | Should -Contain '~\.gemini\config\mcp_config.json'
    }

    It 'keeps an MCP config an earlier setup wrote while it is in use' {
        Publish-AgentLayout $layouts.gemini $sources
        $legacy = $layouts.gemini.McpLegacy[0]
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $legacy) | Out-Null
        Write-Utf8File $legacy '{ "mcpServers": { "web": { "command": "x" } } }'
        $lock = [System.IO.File]::Open($legacy, 'Open', 'Read', 'None')
        try { $r = Remove-AgentLayout $layouts.gemini $sources $out $home_ }
        finally { $lock.Dispose() }
        Test-Path $legacy | Should -BeTrue
        @($r.Kept | Where-Object { $_.Path -eq '~\.gemini\config\mcp_config.json' -and $_.Reason -like 'in use*' }).Count | Should -Be 1
    }

    It 'keeps an MCP config an earlier setup wrote that has comments and names a project server, and says why' {
        Publish-AgentLayout $layouts.gemini $sources
        $legacy = $layouts.gemini.McpLegacy[0]
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $legacy) | Out-Null
        $text = "{`n  // mine`n  ""mcpServers"": { ""web"": { ""command"": ""x"" } }`n}"
        Write-Utf8File $legacy $text
        $r = Remove-AgentLayout $layouts.gemini $sources $out $home_
        Read-Utf8 $legacy | Should -Be $text
        @($r.Kept | Where-Object { $_.Path -eq '~\.gemini\config\mcp_config.json' -and $_.Reason -like '*names web' }).Count | Should -Be 1
    }

    It 'publishing cleans an MCP config an earlier setup wrote' {
        $legacy = $layouts.gemini.McpLegacy[0]
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $legacy) | Out-Null
        Write-Utf8File $legacy '{ "mcpServers": { "web": { "command": "x" }, "mine": { "command": "y" } } }'
        Publish-AgentLayout $layouts.gemini $sources
        @((Read-Utf8 $legacy | ConvertFrom-Json).mcpServers.PSObject.Properties.Name) | Should -Be @('mine')
    }

    It 'keeps a stub changed by hand' {
        Publish-AgentLayout $layouts.claude $sources
        Set-Content -Path (Join-Path $out 'CLAUDE.md') -Value 'my own notes'
        $r = Remove-AgentLayout $layouts.claude $sources $out $home_
        @($r.Kept | Where-Object { $_.Path -eq 'CLAUDE.md' -and $_.Reason -eq 'changed by hand' }).Count | Should -Be 1
        Test-Path (Join-Path $out 'CLAUDE.md') | Should -BeTrue
    }

    It 'keeps a rule file it did not write, and the folder with it' {
        Publish-AgentLayout $layouts.cursor $sources
        Set-Content -Path (Join-Path $layouts.cursor.Rules 'mine.mdc') -Value 'mine'
        $r = Remove-AgentLayout $layouts.cursor $sources $out $home_
        Test-Path (Join-Path $layouts.cursor.Rules 'mine.mdc') | Should -BeTrue
        @($r.Kept | ForEach-Object { $_.Path }) | Should -Contain '.cursor\rules'
    }

    It 'removes a rule it wrote for a source that is gone since' {
        Publish-AgentLayout $layouts.cursor $sources
        Set-Content -Path (Join-Path $layouts.cursor.Rules 'old-stack.mdc') -Value "---`n---`n<!-- Generated by ai_tooling/setup.ps1. Edit the source, not this copy. -->`nold"
        Remove-AgentLayout $layouts.cursor $sources $out $home_ | Out-Null
        Test-Path $layouts.cursor.Rules | Should -BeFalse
    }

    It 'removes an Antigravity rule an earlier setup wrote as the bare source text (no marker)' {
        Publish-AgentLayout $layouts.gemini $sources
        $source = [System.IO.File]::ReadAllText((Join-Path $AiDir 'instructions\coding-principles.md'))
        [System.IO.File]::WriteAllText((Join-Path $layouts.gemini.Rules 'coding-principles.md'), $source)
        $r = Remove-AgentLayout $layouts.gemini $sources $out $home_
        $r.Kept | Should -BeNullOrEmpty
        Test-Path $layouts.gemini.Rules | Should -BeFalse
    }

    It 'keeps an Antigravity rule under a setup name whose text is neither setup''s output nor the source' {
        Publish-AgentLayout $layouts.gemini $sources
        $mine = Join-Path $layouts.gemini.Rules 'coding-principles.md'
        [System.IO.File]::WriteAllText($mine, "---`ndescription: mine`n---`n`nmine`n")
        $r = Remove-AgentLayout $layouts.gemini $sources $out $home_
        Test-Path $mine | Should -BeTrue
        @($r.Kept | ForEach-Object { $_.Path }) | Should -Contain '.agents\rules\coding-principles.md'
    }
}

Describe 'New-SubagentsLink' {
    BeforeEach {
        $case = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $target = Join-Path $case 'agents'
        New-Item -ItemType Directory -Force -Path $target | Out-Null
        Set-Content -Path "$target\acme-role-x.md" -Value 'x'
        $link = Join-Path $case 'out\.claude\agents'
    }

    It 'creates a junction to the target' {
        New-SubagentsLink $target $link $TestProject.Pattern | Should -Be 'junction'
        (Get-Item $link -Force).LinkType | Should -Be 'Junction'
    }

    It 'copies into a personal folder and leaves its files alone' {
        New-Item -ItemType Directory -Force -Path $link | Out-Null
        Set-Content -Path "$link\mine.md" -Value 'mine'
        New-SubagentsLink $target $link $TestProject.Pattern | Should -Be 'copied into the existing folder'
        Test-Path "$link\mine.md" | Should -BeTrue
        Test-Path "$link\acme-role-x.md" | Should -BeTrue
    }

    It 'removes project definitions the source no longer has, and only those' {
        New-Item -ItemType Directory -Force -Path $link | Out-Null
        Set-Content -Path "$link\mine.md" -Value 'mine'
        Set-Content -Path "$link\acme-role-old.md" -Value 'renamed away'
        Set-Content -Path "$link\acmego-gone.md" -Value 'deleted'
        New-SubagentsLink $target $link $TestProject.Pattern | Out-Null
        Test-Path "$link\acme-role-old.md" | Should -BeFalse
        Test-Path "$link\acmego-gone.md" | Should -BeFalse
        Test-Path "$link\mine.md" | Should -BeTrue
        Test-Path "$link\acme-role-x.md" | Should -BeTrue
    }
}

Describe 'Get-EnvValue' {
    It 'reads the process scope' {
        $env:AI_TOOLING_SETUP_TEST = 'from-process'
        try { Get-EnvValue 'AI_TOOLING_SETUP_TEST' | Should -Be 'from-process' }
        finally { Remove-Item Env:\AI_TOOLING_SETUP_TEST }
    }

    It 'returns nothing for an unset variable' {
        Get-EnvValue 'AI_TOOLING_SETUP_TEST_UNSET' | Should -BeNullOrEmpty
    }
}

Describe 'Remove-Frontmatter' {
    It 'removes the frontmatter and the blank lines after it (<name>)' -TestCases @(
        @{ name = 'LF'; text = "---`ndescription: x`n---`n`n# Title`n" }
        @{ name = 'CRLF'; text = "---`r`ndescription: x`r`n---`r`n`r`n# Title`r`n" }
    ) {
        (Remove-Frontmatter $text) | Should -BeLike '# Title*'
    }

    It 'leaves text without frontmatter alone' {
        Remove-Frontmatter "# Title`n---`nnot frontmatter`n---`n" | Should -Be "# Title`n---`nnot frontmatter`n---`n"
    }
}

Describe 'Rule writers' {
    BeforeAll {
        $source = "---`napplyTo: x`n---`n`n# Body`n"
        $scoped = @{ Name = 'base'; SourceFile = 'base.instructions.md'; Description = "it's"; Globs = @('a/**', 'b/**'); Text = $source; Marker = '<!-- m -->' }
        $always = @{ Name = 'permissions'; Description = 'Always'; AlwaysOn = $true; Text = "# Perm`n"; Marker = '<!-- m -->' }
    }

    It 'Copilot: *.instructions.md with description and applyTo, the source frontmatter replaced' {
        $r = ConvertTo-CopilotRule $scoped
        $r.File | Should -Be 'base.instructions.md'
        $r.Text | Should -Be "---`ndescription: 'it''s'`napplyTo: 'a/**,b/**'`n---`n`n<!-- m -->`n# Body`n"
    }

    It 'Copilot: an always-on rule applies to "**"' {
        (ConvertTo-CopilotRule $always).Text | Should -Be "---`napplyTo: `"**`"`n---`n`n<!-- m -->`n# Perm`n"
    }

    It 'Copilot: a rule without globs has no applyTo (on demand)' {
        $r = $scoped.Clone(); $r.Globs = @()
        (ConvertTo-CopilotRule $r).Text | Should -Not -Match 'applyTo'
    }

    It 'Cursor: *.mdc with quoted description and unquoted globs' {
        $r = ConvertTo-CursorRule $scoped
        $r.File | Should -Be 'base.mdc'
        $r.Text | Should -Be "---`ndescription: 'it''s'`nglobs: a/**, b/**`nalwaysApply: false`n---`n`n<!-- m -->`n# Body`n"
    }

    It 'Cursor: an always-on rule has alwaysApply: true' {
        (ConvertTo-CursorRule $always).Text | Should -Be "---`ndescription: Always`nalwaysApply: true`n---`n`n<!-- m -->`n# Perm`n"
    }

    It 'Cursor: warns about a glob unquoted YAML would misread' {
        Mock Write-Warning { } -ModuleName AgentSetup
        $r = $scoped.Clone(); $r.Globs = @('**/x')
        ConvertTo-CursorRule $r | Out-Null
        Should -Invoke Write-Warning -Times 1 -ModuleName AgentSetup
    }

    It 'Antigravity: an instruction file with another trigger as it is, under its own name' {
        $r = $scoped.Clone(); $r.Text = "---`ndescription: up`ntrigger: always_on`n---`n`n# Body`n"
        $out = ConvertTo-AntigravityRule $r
        $out.File | Should -Be 'base.instructions.md'
        $out.Text | Should -Be $r.Text
    }

    It 'Antigravity: an instruction file without trigger is rewritten as model_decision, under its own name' {
        $out = ConvertTo-AntigravityRule $scoped
        $out.File | Should -Be 'base.instructions.md'
        $out.Text | Should -Be "---`ndescription: 'it''s; read before working on files matching a/**, b/**'`ntrigger: model_decision`n---`n`n<!-- m -->`n# Body`n"
    }

    It 'Antigravity: an always-on rule has trigger: always_on' {
        (ConvertTo-AntigravityRule $always).Text | Should -Be "---`ntrigger: always_on`n---`n`n<!-- m -->`n# Perm`n"
    }

    It 'Antigravity: a scoped rule has trigger: model_decision and names its globs in the description' {
        $r = $scoped.Clone(); $r.Remove('SourceFile')
        $out = ConvertTo-AntigravityRule $r
        $out.File | Should -Be 'base.md'
        $out.Text | Should -Be "---`ndescription: 'it''s; read before working on files matching a/**, b/**'`ntrigger: model_decision`n---`n`n<!-- m -->`n# Body`n"
    }

    It 'Antigravity: an instruction file with trigger: glob is rewritten as model_decision, under its own name' {
        $r = $scoped.Clone(); $r.Text = "---`ndescription: up`ntrigger: glob`nglobs: `"**/x`"`n---`n`n# Body`n"
        $out = ConvertTo-AntigravityRule $r
        $out.File | Should -Be 'base.instructions.md'
        $out.Text | Should -Be "---`ndescription: 'it''s; read before working on files matching a/**, b/**'`ntrigger: model_decision`n---`n`n<!-- m -->`n# Body`n"
    }

    It 'Antigravity: a scoped rule without globs has no "read before" in its description' {
        $r = $scoped.Clone(); $r.Remove('SourceFile'); $r.Globs = @()
        (ConvertTo-AntigravityRule $r).Text | Should -Be "---`ndescription: 'it''s'`ntrigger: model_decision`n---`n`n<!-- m -->`n# Body`n"
    }

    It 'Antigravity: trigger: glob in the body, not the frontmatter, leaves the file as it is' {
        $r = $scoped.Clone(); $r.Text = "---`ntrigger: always_on`n---`n`ntrigger: glob`n"
        (ConvertTo-AntigravityRule $r).Text | Should -Be $r.Text
    }

    It 'Antigravity: an instruction file without frontmatter is rewritten as model_decision' {
        $r = $scoped.Clone(); $r.Text = "# Body`n"
        (ConvertTo-AntigravityRule $r).Text | Should -Be "---`ndescription: 'it''s; read before working on files matching a/**, b/**'`ntrigger: model_decision`n---`n`n<!-- m -->`n# Body`n"
    }

    It 'Antigravity: an empty trigger counts as none' {
        $r = $scoped.Clone(); $r.Text = "---`ntrigger:`n---`n`n# Body`n"
        (ConvertTo-AntigravityRule $r).Text | Should -Match 'trigger: model_decision'
    }

    It 'Antigravity: a quoted empty trigger counts as none' {
        $r = $scoped.Clone(); $r.Text = "---`ntrigger: ''`n---`n`n# Body`n"
        (ConvertTo-AntigravityRule $r).Text | Should -Match 'trigger: model_decision'
    }

    It 'Antigravity: a quoted glob trigger is rewritten as model_decision' {
        $r = $scoped.Clone(); $r.Text = "---`ntrigger: `"glob`"`n---`n`n# Body`n"
        (ConvertTo-AntigravityRule $r).Text | Should -Match 'trigger: model_decision'
    }

    It 'Antigravity: a quoted other trigger goes as it is' {
        $r = $scoped.Clone(); $r.Text = "---`ntrigger: 'always_on'`n---`n`n# Body`n"
        (ConvertTo-AntigravityRule $r).Text | Should -Be $r.Text
    }

    It 'Antigravity: a trigger in the body, not the frontmatter, does not count' {
        $r = $scoped.Clone(); $r.Text = "---`napplyTo: x`n---`n`ntrigger: always_on`n"
        (ConvertTo-AntigravityRule $r).Text | Should -Be "---`ndescription: 'it''s; read before working on files matching a/**, b/**'`ntrigger: model_decision`n---`n`n<!-- m -->`ntrigger: always_on`n"
    }

    It 'names the file <file> for <format>' -TestCases @(
        @{ format = 'copilot'; name = 'app-*'; file = 'app-*.instructions.md' }
        @{ format = 'cursor'; name = 'app-*'; file = 'app-*.mdc' }
        @{ format = 'antigravity'; name = 'app-*'; file = 'app-*.md' }
    ) {
        Get-RuleFileName $format $name | Should -Be $file
    }

    It 'gives <format> the filter <filter>' -TestCases @(
        @{ format = 'copilot'; filter = '*.instructions.md' }
        @{ format = 'cursor'; filter = '*.mdc' }
        @{ format = 'antigravity'; filter = '*.md' }
    ) {
        Get-RuleFilter $format | Should -Be $filter
    }

    It 'rejects an unknown format' {
        { ConvertTo-Rule 'codex' $scoped } | Should -Throw '*unknown rule format*'
    }

    It 'Write-Rule writes LF and no BOM into the rules folder' {
        $rules = Join-Path $TestDrive 'rules'
        New-Item -ItemType Directory -Force -Path $rules | Out-Null
        $file = Write-Rule @{ Rules = $rules; RuleFormat = 'cursor' } $scoped
        $path = Join-Path $rules $file
        Read-Utf8 $path | Should -Not -Match "`r"
        Test-Bom $path | Should -BeFalse
    }
}

Describe 'Write-McpConfig' {
    BeforeAll {
        $servers = @'
{
  "$comment": ["ignored"],
  "stdio-one": { "transport": "stdio", "command": "node", "args": ["${REPO_ROOT}/ai_tooling/x.js", "--flag"] },
  "web": { "transport": "http", "url": "https://example.test/mcp" },
  "not-for-gemini": { "transport": "stdio", "command": "dart", "args": ["mcp-server"], "skipAgents": ["gemini"] },
  "opt-in": { "transport": "stdio", "command": "cmd", "args": ["/c", "npx"], "envArgs": { "AI_TOOLING_TEST_OPT": ["--opt", "${VALUE}"] } }
}
'@ | ConvertFrom-Json
    }
    BeforeEach {
        $mcp = Join-Path $TestDrive "cfg\$([guid]::NewGuid().ToString('N'))\mcp.json"
        $claude = @{ Key = 'claude'; Mcp = $mcp; McpKey = 'mcpServers'; HttpUrlField = 'url'; HttpType = $true }
        $gemini = @{ Key = 'gemini'; Mcp = $mcp; McpKey = 'mcpServers'; HttpUrlField = 'serverUrl'; HttpType = $false }
        Mock Get-EnvValue { $null } -ModuleName AgentSetup
    }

    It 'translates stdio servers and replaces ${REPO_ROOT} with forward slashes' {
        Write-McpConfig $claude $servers 'C:\Repo\acme' | Should -Be 4
        $cfg = (Get-Content $mcp -Raw | ConvertFrom-Json).mcpServers
        $cfg.'stdio-one'.command | Should -Be 'node'
        $cfg.'stdio-one'.args | Should -Be @('C:/Repo/acme/ai_tooling/x.js', '--flag')
        $cfg.PSObject.Properties.Name | Should -Not -Contain '$comment'
    }

    It 'writes HTTP servers with type and url for Claude Code' {
        Write-McpConfig $claude $servers 'C:\Repo' | Out-Null
        $web = (Get-Content $mcp -Raw | ConvertFrom-Json).mcpServers.web
        $web.type | Should -Be 'http'
        $web.url | Should -Be 'https://example.test/mcp'
    }

    It 'writes HTTP servers as serverUrl without type for Antigravity, and honours skipAgents' {
        Write-McpConfig $gemini $servers 'C:\Repo' | Should -Be 3
        $cfg = (Get-Content $mcp -Raw | ConvertFrom-Json).mcpServers
        $cfg.web.serverUrl | Should -Be 'https://example.test/mcp'
        $cfg.web.PSObject.Properties.Name | Should -Not -Contain 'type'
        $cfg.PSObject.Properties.Name | Should -Not -Contain 'not-for-gemini'
    }

    It 'uses the agent''s top-level key' {
        $copilot = $claude.Clone(); $copilot.McpKey = 'servers'
        Write-McpConfig $copilot $servers 'C:\Repo' | Out-Null
        (Get-Content $mcp -Raw | ConvertFrom-Json).servers.web | Should -Not -BeNullOrEmpty
    }

    It 'appends envArgs only when the variable is set' {
        Write-McpConfig $claude $servers 'C:\Repo' | Out-Null
        (Get-Content $mcp -Raw | ConvertFrom-Json).mcpServers.'opt-in'.args | Should -Be @('/c', 'npx')

        Mock Get-EnvValue { 'azcli' } -ParameterFilter { $name -eq 'AI_TOOLING_TEST_OPT' } -ModuleName AgentSetup
        Write-McpConfig $claude $servers 'C:\Repo' | Out-Null
        (Get-Content $mcp -Raw | ConvertFrom-Json).mcpServers.'opt-in'.args | Should -Be @('/c', 'npx', '--opt', 'azcli')
    }

    It 'keeps servers added by hand and replaces the managed ones' {
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $mcp) | Out-Null
        '{ "mcpServers": { "mine": { "command": "x" }, "web": { "url": "https://old.test" } } }' | Set-Content $mcp
        Write-McpConfig $claude $servers 'C:\Repo' | Out-Null
        $cfg = (Get-Content $mcp -Raw | ConvertFrom-Json).mcpServers
        $cfg.mine.command | Should -Be 'x'
        $cfg.web.url | Should -Be 'https://example.test/mcp'
    }

    It 'rewrites a config that is not valid JSON' {
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $mcp) | Out-Null
        '{ not json' | Set-Content $mcp
        Write-McpConfig $claude $servers 'C:\Repo' | Should -Be 4
        (Get-Content $mcp -Raw | ConvertFrom-Json).mcpServers.web | Should -Not -BeNullOrEmpty
    }

    It 'leaves a home-folder config it cannot parse alone (comments): <text>' -TestCases @(
        @{ text = "{`n  // mine`n  ""mcpServers"": { ""mine"": { ""command"": ""x"" } }`n}" }, @{ text = '[ 1 ]' }
    ) {
        $home_ = $gemini.Clone(); $home_.McpInHome = $true
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $mcp) | Out-Null
        Write-Utf8File $mcp $text
        Write-McpConfig $home_ $servers 'C:\Repo' | Should -Be -1
        Read-Utf8 $mcp | Should -Be $text
    }

    It 'writes an empty home-folder config' {
        $home_ = $gemini.Clone(); $home_.McpInHome = $true
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $mcp) | Out-Null
        Write-Utf8File $mcp ''
        Write-McpConfig $home_ $servers 'C:\Repo' | Should -Be 3
    }

    It 'keeps the other top-level keys in their place' {
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $mcp) | Out-Null
        Write-Utf8File $mcp '{ "first": 1, "mcpServers": { "mine": { "command": "x" } }, "last": { "a": true } }'
        Write-McpConfig $claude $servers 'C:\Repo' | Out-Null
        $cfg = Get-Content $mcp -Raw | ConvertFrom-Json
        @($cfg.PSObject.Properties.Name) | Should -Be @('first', 'mcpServers', 'last')
        $cfg.last.a | Should -BeTrue
        $cfg.mcpServers.mine.command | Should -Be 'x'
    }

    It 'writes UTF-8 without a BOM' {
        Write-McpConfig $claude $servers 'C:\Repo' | Out-Null
        Test-Bom $mcp | Should -BeFalse
    }
}

Describe 'Test-JsonComment' {
    It 'finds a comment outside strings: <text>' -TestCases @(
        @{ text = "{ // mine`n ""a"": 1 }" }, @{ text = '{ /* mine */ "a": 1 }' }, @{ text = '{ "a": "x\"" // mine' + "`n}" }
    ) {
        Test-JsonComment $text | Should -BeTrue
    }

    It 'finds none in plain JSON, or in a string: <text>' -TestCases @(
        @{ text = '{ "url": "https://example.test/mcp" }' }, @{ text = '{ "a": "/*not*/", "b": "c\\" }' }, @{ text = '' }
    ) {
        Test-JsonComment $text | Should -BeFalse
    }
}

Describe 'Clear-LegacyMcpConfigs' {
    BeforeAll {
        $servers = '{ "web": { "transport": "http", "url": "https://example.test/mcp" }, "not-for-gemini": { "transport": "stdio", "command": "dart", "skipAgents": ["gemini"] } }' | ConvertFrom-Json
    }
    BeforeEach {
        $legacy = Join-Path $TestDrive "home\$([guid]::NewGuid().ToString('N'))\mcp_config.json"
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $legacy) | Out-Null
        $gemini = @{ Key = 'gemini'; McpKey = 'mcpServers'; McpLegacy = @($legacy) }
    }

    It 'takes the managed servers out and keeps the developer''s own' {
        Write-Utf8File $legacy '{ "mcpServers": { "web": { "httpUrl": "https://old.test" }, "mine": { "command": "x" }, "not-for-gemini": { "command": "y" } } }'
        Clear-LegacyMcpConfigs $gemini $servers | Should -Be @($legacy)
        @((Read-Utf8 $legacy | ConvertFrom-Json).mcpServers.PSObject.Properties.Name) | Should -Be @('mine', 'not-for-gemini')
    }

    It 'deletes a file left with nothing in it' {
        Write-Utf8File $legacy '{ "mcpServers": { "web": { "httpUrl": "https://old.test" } } }'
        Clear-LegacyMcpConfigs $gemini $servers | Should -Be @($legacy)
        Test-Path $legacy | Should -BeFalse
    }

    It 'keeps a file of mcp.keepValid left with nothing in it, with an empty server list' {
        $gemini.McpKeepValid = @($legacy)
        Write-Utf8File $legacy '{ "mcpServers": { "web": { "httpUrl": "https://old.test" } } }'
        Clear-LegacyMcpConfigs $gemini $servers | Should -Be @($legacy)
        $cfg = Read-Utf8 $legacy | ConvertFrom-Json
        "$(@($cfg.PSObject.Properties.Name) -join ',') $(@($cfg.mcpServers.PSObject.Properties).Count)" | Should -Be 'mcpServers 0'
    }

    It 'leaves a file without managed servers, an empty one, one that is not JSON and one with comments as they are: <text>' -TestCases @(
        @{ text = '{ "mcpServers": { "mine": { "command": "x" } } }' }, @{ text = '' }, @{ text = '{ not json' }
        @{ text = "{ // mine`n ""mcpServers"": { ""web"": { ""httpUrl"": ""https://old.test"" } } }" }
    ) {
        Mock Write-Host { } -ModuleName AgentSetup
        Write-Utf8File $legacy $text
        Clear-LegacyMcpConfigs $gemini $servers | Should -BeNullOrEmpty
        Read-Utf8 $legacy | Should -Be $text
    }

    It 'does nothing without the file' {
        Clear-LegacyMcpConfigs $gemini $servers | Should -BeNullOrEmpty
        Test-Path $legacy | Should -BeFalse
    }

    It 'warns about a file it cannot parse only when it names a managed server: <names>' -TestCases @(
        @{ names = 'web'; expected = 1 }, @{ names = 'not-for-gemini'; expected = 0 }, @{ names = 'mine'; expected = 0 }
    ) {
        Mock Write-Host { } -ModuleName AgentSetup
        Write-Utf8File $legacy "{ // mine`n ""mcpServers"": { ""$names"": { ""command"": ""x"" } } }"
        Clear-LegacyMcpConfigs $gemini $servers | Should -BeNullOrEmpty
        Should -Invoke Write-Host -ModuleName AgentSetup -Times $expected -Exactly -ParameterFilter { $Object -like '*WARN*names web: left alone*' }
    }

    It 'warns about a file in use and does not throw' {
        Mock Write-Host { } -ModuleName AgentSetup
        Write-Utf8File $legacy '{ "mcpServers": { "web": { "httpUrl": "https://old.test" } } }'
        $lock = [System.IO.File]::Open($legacy, 'Open', 'Read', 'None')
        try { $r = Clear-LegacyMcpConfigs $gemini $servers }
        finally { $lock.Dispose() }
        $r | Should -BeNullOrEmpty
        Test-Path $legacy | Should -BeTrue
        Should -Invoke Write-Host -ModuleName AgentSetup -ParameterFilter { $Object -like '*WARN could not take*' }
    }
}

Describe 'Repair-McpKeepValid' {
    BeforeEach {
        $file = Join-Path $TestDrive "home\$([guid]::NewGuid().ToString('N'))\config\mcp_config.json"
        $layout = @{ McpKey = 'mcpServers'; McpKeepValid = @($file) }
    }

    It 'writes an empty server list into a <case> file' -TestCases @(@{ case = 'missing'; text = $null }, @{ case = 'empty'; text = '' }, @{ case = 'blank'; text = " `n" }) {
        if ($null -ne $text) { New-Item -ItemType Directory -Force -Path (Split-Path -Parent $file) | Out-Null; Write-Utf8File $file $text }
        Repair-McpKeepValid $layout | Should -Be @($file)
        $cfg = Read-Utf8 $file | ConvertFrom-Json
        "$(@($cfg.PSObject.Properties.Name) -join ',') $(@($cfg.mcpServers.PSObject.Properties).Count)" | Should -Be 'mcpServers 0'
    }

    It 'leaves a file with content alone, comments included' {
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $file) | Out-Null
        $text = "{ // mine`n ""mcpServers"": { ""mine"": { ""command"": ""x"" } } }"
        Write-Utf8File $file $text
        Repair-McpKeepValid $layout | Should -BeNullOrEmpty
        Read-Utf8 $file | Should -Be $text
    }
}

Describe 'Write-LocalVersion' {
    BeforeEach {
        $src = Join-Path $TestDrive "src\$([guid]::NewGuid().ToString('N'))\ai_tooling"
        $out = Join-Path $TestDrive "out\$([guid]::NewGuid().ToString('N'))"
        New-Item -ItemType Directory -Force -Path $src | Out-Null
        $local = Join-Path $out 'ai_tooling\localversion'
        $layouts = Get-AgentLayouts $AiDir $out 'C:\Home'
        Mock Write-Host { } -ModuleName AgentSetup
    }

    It 'writes the number as digits, LF, no BOM, from "<raw>"' -TestCases @(
        @{ raw = "7`n" }, @{ raw = "7`r`n" }, @{ raw = " 7 " }, @{ raw = [char]0xFEFF + "7`n" }
    ) {
        [System.IO.File]::WriteAllText((Join-Path $src 'version'), $raw)
        Write-LocalVersion $src $out $AgentKeys $layouts
        [System.IO.File]::ReadAllBytes($local) | Should -Be ([byte[]](0x37, 0x0A))
    }

    It 'returns the number it recorded' {
        [System.IO.File]::WriteAllText((Join-Path $src 'version'), "7`n")
        Write-LocalVersion $src $out $AgentKeys $layouts | Should -Be 7
    }

    It 'leaves localversion alone when ai_tooling/version is not a whole number' {
        Mock Write-Warning { } -ModuleName AgentSetup
        [System.IO.File]::WriteAllText((Join-Path $src 'version'), "7.1`n")
        Write-LocalVersion $src $out $AgentKeys $layouts | Should -BeNullOrEmpty
        Test-Path $local | Should -BeFalse
        Should -Invoke Write-Warning -Times 1 -ModuleName AgentSetup
    }

    It 'does not record a run that left a layout on disk unrefreshed' {
        [System.IO.File]::WriteAllText((Join-Path $src 'version'), "7`n")
        New-PublishedSkill $layouts.cursor.Skills
        Write-LocalVersion $src $out @('claude') $layouts | Should -BeNullOrEmpty
        Test-Path $local | Should -BeFalse
    }
}

Describe 'Read-LocalVersion' {
    BeforeEach {
        $out = Join-Path $TestDrive "out\$([guid]::NewGuid().ToString('N'))"
        $local = Join-Path $out 'ai_tooling\localversion'
    }

    It 'returns nothing when localversion is missing' {
        Read-LocalVersion $out | Should -BeNullOrEmpty
    }

    It 'reads "<raw>" as 7' -TestCases @(
        @{ raw = "7`n" }, @{ raw = "7`r`n" }, @{ raw = " 7 " }, @{ raw = [char]0xFEFF + "7`n" }
    ) {
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $local) | Out-Null
        [System.IO.File]::WriteAllText($local, $raw)
        Read-LocalVersion $out | Should -Be 7
    }

    It 'returns nothing when localversion is not a whole number' {
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $local) | Out-Null
        [System.IO.File]::WriteAllText($local, "7.1`n")
        Read-LocalVersion $out | Should -BeNullOrEmpty
    }
}

Describe 'Get-ChangelogEntries' {
    BeforeAll {
        $changelog = Join-Path $TestDrive 'CHANGELOG.md'
        [System.IO.File]::WriteAllText($changelog, (@(
            '# Agent setup changelog', '', 'Intro, headed `## {version}`.', '',
            '## 3 - 2026-10-03 - US 3', '', '- three', '',
            '## 2 - 2026-10-02 - US 2', '', '- two', '  more', '',
            '## 1 - 2026-10-01 - US 1', '', '- one', ''
        ) -join "`r`n"))
        function Get-Headings($entries) { @($entries | ForEach-Object { ($_ -split "`n")[0] }) }
    }

    It 'returns the entries after <after> up to <upTo>, newest first' -TestCases @(
        @{ after = 1; upTo = 3; expected = @('## 3 - 2026-10-03 - US 3', '## 2 - 2026-10-02 - US 2') }
        @{ after = 0; upTo = 2; expected = @('## 2 - 2026-10-02 - US 2', '## 1 - 2026-10-01 - US 1') }
    ) {
        Get-Headings (Get-ChangelogEntries $changelog $after $upTo) | Should -Be $expected
    }

    It 'returns each entry whole, from its heading to the next, with LF line endings' {
        $entries = @(Get-ChangelogEntries $changelog 1 2)
        $entries | Should -Be @("## 2 - 2026-10-02 - US 2`n`n- two`n  more")
    }

    It 'returns only the newest entry up to <upTo> when there is no previous version' -TestCases @(
        @{ upTo = 3; expected = '## 3 - 2026-10-03 - US 3' }
        @{ upTo = 2; expected = '## 2 - 2026-10-02 - US 2' }
    ) {
        Get-Headings (Get-ChangelogEntries $changelog $null $upTo) | Should -Be @($expected)
    }

    It 'returns nothing when nothing is newer than <after>' -TestCases @(@{ after = 3 }, @{ after = 4 }) {
        Get-ChangelogEntries $changelog $after 3 | Should -BeNullOrEmpty
    }

    It 'returns nothing when the file is missing' {
        Get-ChangelogEntries (Join-Path $TestDrive 'missing.md') 1 3 | Should -BeNullOrEmpty
    }
}

Describe 'Write-WhatsNew' {
    BeforeAll {
        $src = Join-Path $TestDrive 'whatsnew\ai_tooling'
        New-Item -ItemType Directory -Force -Path $src | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $src 'CHANGELOG.md'),
            "# Changelog`n`n## 3 - d - US 3`n`n- three`n`n## 2 - d - US 2`n`n- two`n`n## 1 - d - US 1`n`n- one`n")
    }
    BeforeEach { Mock Write-Host { } -ModuleName AgentSetup }

    It 'prints the entries after the previous version up to the recorded one' {
        Write-WhatsNew $src 1 3
        Should -Invoke Write-Host -ModuleName AgentSetup -Times 1 -Exactly -ParameterFilter { "$Object" -like "What's new since setup version 1*" }
        Should -Invoke Write-Host -ModuleName AgentSetup -Times 1 -Exactly -ParameterFilter { "$Object" -like '## 3 *' }
        Should -Invoke Write-Host -ModuleName AgentSetup -Times 1 -Exactly -ParameterFilter { "$Object" -like '## 2 *' }
        Should -Invoke Write-Host -ModuleName AgentSetup -Times 0 -ParameterFilter { "$Object" -like '## 1 *' }
    }

    It 'prints the newest entry when there was no localversion' {
        Write-WhatsNew $src $null 3
        Should -Invoke Write-Host -ModuleName AgentSetup -Times 1 -Exactly -ParameterFilter { "$Object" -like "What's new in setup version 3*" }
        Should -Invoke Write-Host -ModuleName AgentSetup -Times 1 -Exactly -ParameterFilter { "$Object" -like '## 3 *' }
        Should -Invoke Write-Host -ModuleName AgentSetup -Times 0 -ParameterFilter { "$Object" -like '## 2 *' }
    }

    It 'prints nothing when <case>' -TestCases @(
        @{ case = 'no version was recorded'; previous = 1; current = $null }
        @{ case = 'nothing is newer'; previous = 3; current = 3 }
    ) {
        Write-WhatsNew $src $previous $current
        Should -Invoke Write-Host -ModuleName AgentSetup -Times 0
    }
}

Describe 'CHANGELOG.md' {
    It 'heads every entry with its version as a whole number, as Get-ChangelogEntries reads it' {
        $headings = @(Get-Content (Join-Path $AiDir 'CHANGELOG.md') -Encoding UTF8 | Where-Object { $_ -like '## *' })
        $headings.Count | Should -BeGreaterThan 0
        @($headings | Where-Object { $_ -notmatch '^## \d+ ' }) | Should -BeNullOrEmpty
    }
}

Describe 'Copied sources' {
    BeforeEach {
        # A small repository of its own: one skill, one instruction file, one app.
        $case = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $repo = Join-Path $case 'repo'
        $ai = Join-Path $repo 'ai_tooling'
        foreach ($d in @('skills\g\a\references', 'agents', 'instructions', 'manifest', 'external-skill-config', 'App1')) {
            New-Item -ItemType Directory -Force -Path (Join-Path $ai $d) | Out-Null
        }
        Move-Item (Join-Path $ai 'App1') (Join-Path $repo 'App1')
        Set-Content -Path "$ai\skills\g\a\SKILL.md" -Value 'a'
        Set-Content -Path "$ai\skills\g\a\references\r.md" -Value 'r'
        Set-Content -Path "$ai\agents\acme-x.md" -Value 'x'
        Set-Content -Path "$ai\instructions\i.md" -Value 'i'
        Set-Content -Path "$ai\manifest\instructions.json" -Value '{ "instructions": { "i.md": { "description": "d", "globs": ["App1/**"] } } }'
        Set-Content -Path "$ai\PERMISSIONS.md" -Value 'p'
        Set-Content -Path "$ai\external-skill-config\e.md" -Value 'e'
        Set-Content -Path "$ai\mcp-servers.json" -Value '{ "servers": {} }'
        Set-Content -Path "$ai\manifest\project.json" -Value '{ "name": "Acme", "skillPrefixes": ["acme"] }'
        Set-Content -Path "$repo\App1\AGENTS.md" -Value 'app'
        $manifest = [pscustomobject]@{ Skills = [ordered]@{ a = [pscustomobject]@{ Name = 'a'; Path = "$ai\skills\g\a" } } }
        $out = Join-Path $case 'out'
        $layouts = Get-AgentLayouts $AiDir $out (Join-Path $case 'home')
        $sources = Get-SetupSources $ai $out (Join-Path $case 'home') $manifest @('a')
        foreach ($l in $layouts.Values) { New-PublishedSkill $l.Skills }
    }

    It 'hashes a file, a folder without setup''s copy marker, and nothing for a missing path' {
        $file = Get-SourceHash "$ai\PERMISSIONS.md"
        $file | Should -Match '^[0-9a-f]{64}$'
        $folder = Get-SourceHash "$ai\skills\g\a"
        Set-Content -Path "$ai\skills\g\a\$SkillCopyMarker" -Value 'marker'
        Get-SourceHash "$ai\skills\g\a" | Should -Be $folder
        Set-Content -Path "$ai\skills\g\a\references\r.md" -Value 'changed'
        Get-SourceHash "$ai\skills\g\a" | Should -Not -Be $folder
        Get-SourceHash "$ai\missing.md" | Should -BeNullOrEmpty
    }

    It 'lists what each agent gets as a copy' {
        $claude = @((Get-CopiedSources $layouts.claude $sources).Keys)
        $claude | Should -Be @('ai_tooling/external-skill-config/e.md', 'ai_tooling/mcp-servers.json')
        $gemini = @((Get-CopiedSources $layouts.gemini $sources).Keys)
        $gemini | Should -Contain 'ai_tooling/skills/g/a'
        $gemini | Should -Contain 'ai_tooling/PERMISSIONS.md'
        $gemini | Should -Contain 'App1/AGENTS.md'
        # Antigravity's model_decision rules take their description and globs from it.
        $gemini | Should -Contain 'ai_tooling/manifest/instructions.json'
        $copilot = @((Get-CopiedSources $layouts.copilot $sources).Keys)
        $copilot | Should -Not -Contain 'ai_tooling/skills/g/a'
        $copilot | Should -Contain 'ai_tooling/manifest/instructions.json'
        $cursor = @((Get-CopiedSources $layouts.cursor $sources).Keys)
        $cursor | Should -Not -Contain 'App1/AGENTS.md'
        # The app folders give the globs of an allApps instruction file.
        $cursor | Should -Contain 'App1/'
        $gemini | Should -Contain 'App1/'
    }

    It 'lists a skill whose junction fell back to a copy' {
        @((Get-CopiedSources $layouts.claude $sources).Keys) | Should -Not -Contain 'ai_tooling/skills/g/a'
        New-Item -ItemType Directory -Force -Path (Join-Path $layouts.claude.Skills 'a') | Out-Null
        Set-Content -Path (Join-Path $layouts.claude.Skills "a\$SkillCopyMarker") -Value 'copy'
        @((Get-CopiedSources $layouts.claude $sources).Keys) | Should -Contain 'ai_tooling/skills/g/a'
    }

    It 'reports a new app folder for an agent that scopes rules by app, not an edit of its AGENTS.md' {
        Write-LocalSources $out $AgentKeys $layouts $sources
        Set-Content -Path "$repo\App1\AGENTS.md" -Value 'app, edited'
        New-Item -ItemType Directory -Force -Path "$repo\App2" | Out-Null
        Set-Content -Path "$repo\App2\AGENTS.md" -Value 'app2'
        $sources = Get-SetupSources $ai $out (Join-Path $case 'home') $manifest @('a')
        $r = @{}
        foreach ($x in Test-LocalSources $out $layouts $sources) { $r[$x.Key] = $x }
        $r.cursor.Changed | Should -BeNullOrEmpty
        $r.cursor.Added | Should -Be @('App2/')
        $r.copilot.Changed | Should -Be @('App1/AGENTS.md')
    }

    It 'lists the subagent definitions only where the subagents folder is a real folder' {
        New-Item -ItemType Junction -Path $layouts.claude.Subagents -Value "$ai\agents" | Out-Null
        @((Get-CopiedSources $layouts.claude $sources).Keys) | Should -Not -Contain 'ai_tooling/agents/acme-x.md'
        [System.IO.Directory]::Delete($layouts.claude.Subagents)
        New-Item -ItemType Directory -Force -Path $layouts.claude.Subagents | Out-Null
        @((Get-CopiedSources $layouts.claude $sources).Keys) | Should -Contain 'ai_tooling/agents/acme-x.md'
    }

    It 'finds nothing right after recording, and writes UTF-8 without a BOM' {
        Write-LocalSources $out $AgentKeys $layouts $sources
        Test-Bom (Join-Path $out "ai_tooling\$LocalSourcesName") | Should -BeFalse
        foreach ($r in Test-LocalSources $out $layouts $sources) {
            $r.Recorded | Should -BeTrue
            ($r.Changed + $r.Added + $r.Removed) | Should -BeNullOrEmpty
        }
    }

    It 'reports a changed source for the agents that copy it, and a new and a removed one' {
        Write-LocalSources $out $AgentKeys $layouts $sources
        Set-Content -Path "$ai\PERMISSIONS.md" -Value 'p2'
        Set-Content -Path "$ai\instructions\j.md" -Value 'j'
        Remove-Item "$ai\external-skill-config\e.md"
        $r = @{}
        foreach ($x in Test-LocalSources $out $layouts $sources) { $r[$x.Key] = $x }
        $r.claude.Changed | Should -BeNullOrEmpty
        $r.claude.Removed | Should -Be @('ai_tooling/external-skill-config/e.md')
        foreach ($k in @('gemini', 'copilot', 'cursor')) {
            $r[$k].Changed | Should -Be @('ai_tooling/PERMISSIONS.md')
            $r[$k].Added | Should -Be @('ai_tooling/instructions/j.md')
        }
    }

    It 'skips agents whose layout is not on disk, and reports one without a record' {
        Write-LocalSources $out @('claude') $layouts $sources
        Remove-Item $layouts.copilot.Skills -Recurse -Force
        $r = @(Test-LocalSources $out $layouts $sources)
        $r.Key | Should -Be @('claude', 'gemini', 'cursor')
        ($r | Where-Object Key -eq 'gemini').Recorded | Should -BeFalse
    }

    It 'keeps the record of agents a run with -Agent did not refresh' {
        Write-LocalSources $out $AgentKeys $layouts $sources
        Set-Content -Path "$ai\PERMISSIONS.md" -Value 'p2'
        Write-LocalSources $out @('gemini') $layouts $sources
        $r = @{}
        foreach ($x in Test-LocalSources $out $layouts $sources) { $r[$x.Key] = $x }
        $r.gemini.Changed | Should -BeNullOrEmpty
        $r.copilot.Changed | Should -Be @('ai_tooling/PERMISSIONS.md')
    }

    It 'refreshes the shared docs/agents sources in the record of an agent a run with -Agent did not refresh' {
        Write-LocalSources $out $AgentKeys $layouts $sources
        Set-Content -Path "$ai\external-skill-config\e.md" -Value 'e2'
        Set-Content -Path "$ai\external-skill-config\f.md" -Value 'f'
        Write-LocalSources $out @('claude') $layouts $sources
        Remove-Item "$ai\external-skill-config\e.md"
        Write-LocalSources $out @('claude') $layouts $sources
        $r = @{}
        foreach ($x in Test-LocalSources $out $layouts $sources) { $r[$x.Key] = $x }
        foreach ($k in $AgentKeys) {
            $r[$k].Recorded | Should -BeTrue
            ($r[$k].Changed + $r[$k].Added + $r[$k].Removed) | Should -BeNullOrEmpty
        }
    }

    It 'treats a record of "<content>" as no record, and setup writes it anew' -TestCases @(
        @{ content = '{ not json' }, @{ content = '' }, @{ content = '{}' }, @{ content = '{"agents":null}' },
        @{ content = '[]' }, @{ content = '"x"' }, @{ content = 'null' }
    ) {
        New-Item -ItemType Directory -Force -Path (Join-Path $out 'ai_tooling') | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $out "ai_tooling\$LocalSourcesName"), $content)
        (Read-LocalSources $out).Count | Should -Be 0
        { Write-LocalSources $out @('claude') $layouts $sources } | Should -Not -Throw
        (Read-LocalSources $out).Keys | Should -Be @('claude')
    }

    It 'leaves out an agent whose entry is not an object' {
        New-Item -ItemType Directory -Force -Path (Join-Path $out 'ai_tooling') | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $out "ai_tooling\$LocalSourcesName"), '{"agents":{"claude":null,"gemini":{"x":"1"}}}')
        (Read-LocalSources $out).Keys | Should -Be @('gemini')
    }

    It 'writes the sources of an agent it did not refresh in ordinal order' {
        Write-LocalSources $out $AgentKeys $layouts $sources
        Write-LocalSources $out @('claude') $layouts $sources
        $json = [System.IO.File]::ReadAllText((Join-Path $out "ai_tooling\$LocalSourcesName")) | ConvertFrom-Json
        $names = [string[]]@($json.agents.gemini.PSObject.Properties.Name)
        $sorted = [string[]]$names.Clone()
        [Array]::Sort($sorted, [StringComparer]::Ordinal)
        $names | Should -Be $sorted
    }
}

Describe 'Resolve-Root' {
    It 'returns the default when no root is given' {
        Resolve-Root '' 'C:\Default' | Should -Be 'C:\Default'
    }

    It 'resolves a relative path, drops a trailing slash and creates the folder' {
        Push-Location $TestDrive
        try {
            $r = Resolve-Root 'rel\out\' 'C:\Default'
            $r | Should -Be (Join-Path $TestDrive 'rel\out')
            Test-Path $r | Should -BeTrue
        } finally { Pop-Location }
    }
}

Describe 'Delivery table' {
    It 'has one column per agent and one row per source' {
        $table = Format-DeliveryTable (Get-AgentLayouts $AiDir 'C:\Out' 'C:\Home') 'C:\Out' 'C:\Home'
        $lines = $table -split "`n"
        $lines[0] | Should -Be '| Source | Claude Code | Gemini / Antigravity | GitHub Copilot | Cursor |'
        $lines.Count | Should -Be 9
        $table | Should -Match ([regex]::Escape('`.agents/mcp_config.json`'))
        $table | Should -Not -Match 'C:'
    }

    It 'replaces only the text between the markers' {
        $text = "a`n<!-- BEGIN generated: t -->`nold`n<!-- END generated: t -->`nb`n"
        Set-GeneratedSection $text 't' 'new' | Should -Be "a`n<!-- BEGIN generated: t -->`nnew`n<!-- END generated: t -->`nb`n"
    }

    It 'fails without the markers' {
        { Set-GeneratedSection 'no markers' 't' 'x' } | Should -Throw '*markers*'
    }
}

Describe 'setup.ps1 parameters' {
    It 'refuses -OutputRoot or -HomeRoot without -SkipTools (<name>)' -TestCases @(
        @{ name = '-OutputRoot'; extra = @('-OutputRoot') }
        @{ name = '-HomeRoot'; extra = @('-HomeRoot') }
    ) {
        $dir = Join-Path $TestDrive "refuse-$name"
        $log = Invoke-SetupChild (@('-Agent', 'claude') + $extra + $dir)
        $LASTEXITCODE | Should -Not -Be 0
        ($log -join "`n") | Should -BeLike '*need -SkipTools*'
        Test-Path $dir | Should -BeFalse
    }

    It 'refuses -Remove together with -Agent' {
        $dir = Join-Path $TestDrive 'remove-agent'
        $log = Invoke-SetupChild @('-Remove', 'cursor', '-Agent', 'claude', '-SkipTools', '-OutputRoot', $dir, '-HomeRoot', $dir)
        $LASTEXITCODE | Should -Not -Be 0
        ($log -join "`n") | Should -BeLike '*-Remove cannot be combined with -Agent or -Profile*'
    }

    It '-Remove takes a layout away for good' {
        $out = Join-Path $TestDrive 'remove-out'
        $home_ = Join-Path $TestDrive 'remove-home'
        Invoke-SetupChild @('-Agent', 'all', '-SkipTools', '-OutputRoot', $out, '-HomeRoot', $home_) | Out-Null
        $LASTEXITCODE | Should -Be 0
        Test-Path (Join-Path $out '.cursor\rules') | Should -BeTrue

        Invoke-SetupChild @('-Remove', 'cursor', '-SkipTools', '-OutputRoot', $out, '-HomeRoot', $home_) | Out-Null
        $LASTEXITCODE | Should -Be 0
        @('.cursor\skills', '.cursor\rules', '.cursor\mcp.json' | Where-Object { Test-Path (Join-Path $out $_) }) | Should -BeNullOrEmpty

        $log = Invoke-SetupChild @('-SkipTools', '-OutputRoot', $out, '-HomeRoot', $home_)
        $LASTEXITCODE | Should -Be 0
        ($log -join "`n") | Should -BeLike '*Configuring: claude, gemini, copilot  (set up in this clone*'
        Test-Path (Join-Path $out '.cursor') | Should -BeFalse
        Test-Path (Join-Path $out '.github\skills') | Should -BeTrue
        Remove-FolderSafely $out
    }

    It 'prints What''s new above the localversion it found, and nothing on the next run' {
        $out = Join-Path $TestDrive 'whatsnew-out'
        $home_ = Join-Path $TestDrive 'whatsnew-home'
        $current = [int]([System.IO.File]::ReadAllText((Join-Path $AiDir 'version')).Trim())
        New-Item -ItemType Directory -Force -Path (Join-Path $out 'ai_tooling') | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $out 'ai_tooling\localversion'), "$($current - 1)`n")

        $log = Invoke-SetupChild @('-Agent', 'claude', '-SkipTools', '-OutputRoot', $out, '-HomeRoot', $home_)
        $LASTEXITCODE | Should -Be 0
        ($log -join "`n") | Should -BeLike "*What's new since setup version $($current - 1)*## $current *"

        $log = Invoke-SetupChild @('-Agent', 'claude', '-SkipTools', '-OutputRoot', $out, '-HomeRoot', $home_)
        $LASTEXITCODE | Should -Be 0
        ($log -join "`n") | Should -Not -BeLike "*What's new*"
        Remove-FolderSafely $out
    }

    It '-Remove keeps a developer''s own skill, and the layout still stays away' {
        $out = Join-Path $TestDrive 'remove-own-out'
        $home_ = Join-Path $TestDrive 'remove-own-home'
        # The other layouts stay set up, so the last run refreshes them instead of detecting agents.
        Invoke-SetupChild @('-Agent', 'all', '-SkipTools', '-OutputRoot', $out, '-HomeRoot', $home_) | Out-Null
        New-Item -ItemType Directory -Force -Path (Join-Path $out '.claude\skills\my-skill') | Out-Null
        Invoke-SetupChild @('-Remove', 'claude', '-SkipTools', '-OutputRoot', $out, '-HomeRoot', $home_) | Out-Null
        Test-Path (Join-Path $out '.claude\skills\my-skill') | Should -BeTrue

        Invoke-SetupChild @('-SkipTools', '-OutputRoot', $out, '-HomeRoot', $home_) | Out-Null
        @(Get-ChildItem (Join-Path $out '.claude\skills')).Name | Should -Be @('my-skill')
        Remove-FolderSafely $out
    }

    It 'refuses an agent that is not in agents.json' {
        $dir = Join-Path $TestDrive 'unknown'
        $log = Invoke-SetupChild @('-Agent', 'codex', '-SkipTools', '-OutputRoot', $dir, '-HomeRoot', $dir)
        $LASTEXITCODE | Should -Not -Be 0
        ($log -join "`n") | Should -BeLike "*Unknown agent 'codex'*"
    }

    It 'refuses a profile that is not in skills.json, before writing any skill' {
        $dir = Join-Path $TestDrive 'unknown-profile'
        $log = Invoke-SetupChild @('-Agent', 'claude', '-Profile', 'nope', '-SkipTools', '-OutputRoot', $dir, '-HomeRoot', $dir)
        $LASTEXITCODE | Should -Not -Be 0
        ($log -join "`n") | Should -BeLike "*Unknown profile 'nope'*"
        Test-Path (Join-Path $dir '.claude\skills') | Should -BeFalse
    }

    It 'publishes the skills of a profile, remembers it, and goes back to default' -Skip:(-not $hasProfile) {
        $out = Join-Path $TestDrive 'profile-out'
        $manifest = Read-SkillManifest $AiDir
        $p = @($manifest.Profiles.Keys)[0]
        Invoke-SetupChild @('-Agent', 'claude', '-Profile', "$p,default", '-SkipTools', '-OutputRoot', $out, '-HomeRoot', $out) | Out-Null
        $LASTEXITCODE | Should -Be 0
        $expected = Resolve-SkillProfile $manifest @($p, 'default')
        @(Get-ChildItem (Join-Path $out '.claude\skills') -Directory).Count | Should -Be $expected.Count
        Get-Content (Join-Path $out 'ai_tooling\localprofile') | Should -Be "$p,default"

        Invoke-SetupChild @('-Agent', 'claude', '-SkipTools', '-OutputRoot', $out, '-HomeRoot', $out) | Out-Null
        @(Get-ChildItem (Join-Path $out '.claude\skills') -Directory).Count | Should -Be $expected.Count

        Invoke-SetupChild @('-Agent', 'claude', '-Profile', 'default', '-SkipTools', '-OutputRoot', $out, '-HomeRoot', $out) | Out-Null
        @(Get-ChildItem (Join-Path $out '.claude\skills') -Directory).Count | Should -Be (Resolve-SkillProfile $manifest @('default')).Count
        Remove-FolderSafely $out
    }

    It 'drops a saved profile that no longer exists and keeps the others' -Skip:(-not $hasProfile) {
        $out = Join-Path $TestDrive 'stale-profile'
        $p = @((Read-SkillManifest $AiDir).Profiles.Keys)[0]
        Write-LocalProfile $out @('gone', $p)
        $log = Invoke-SetupChild @('-Agent', 'claude', '-SkipTools', '-OutputRoot', $out, '-HomeRoot', $out)
        $LASTEXITCODE | Should -Be 0
        ($log -join "`n") | Should -BeLike "*'gone'*no longer exists*publishing '$p'*"
        Get-Content (Join-Path $out 'ai_tooling\localprofile') | Should -Be $p
        @(Get-ChildItem (Join-Path $out '.claude\skills') -Directory).Count | Should -Be (Resolve-SkillProfile (Read-SkillManifest $AiDir) @($p)).Count
        Remove-FolderSafely $out
    }

    It 'writes nothing outside -OutputRoot and -HomeRoot' {
        # Antigravity's global MCP config (kept valid) and its older place.
        $watched = @('.gemini\config\mcp_config.json', '.gemini\antigravity-ide\mcp_config.json') | ForEach-Object { Join-Path $env:USERPROFILE $_ }
        $before = @($watched | ForEach-Object { if (Test-Path $_) { (Get-Item $_).LastWriteTimeUtc } else { 'missing' } })
        $statusBefore = git -C $RepoRoot status --porcelain --ignored 2>$null

        $out = Join-Path $TestDrive 'iso-out'
        $home_ = Join-Path $TestDrive 'iso-home'
        Invoke-SetupChild @('-Agent', 'all', '-SkipTools', '-OutputRoot', $out, '-HomeRoot', $home_) | Out-Null
        $LASTEXITCODE | Should -Be 0

        $after = @($watched | ForEach-Object { if (Test-Path $_) { (Get-Item $_).LastWriteTimeUtc } else { 'missing' } })
        $after | Should -Be $before
        git -C $RepoRoot status --porcelain --ignored 2>$null | Should -Be $statusBefore
        Test-Path (Join-Path $out '.agents\mcp_config.json') | Should -BeTrue
        Remove-FolderSafely $out
    }
}

Describe 'mcp-servers.json' {
    BeforeAll {
        $schema = Get-Content (Join-Path $AiDir 'mcp-servers.schema.json') -Raw
        $defPath = Join-Path $AiDir 'mcp-servers.json'
    }

    It 'is valid JSON with a servers object (empty in a project without MCP servers)' {
        ($null -ne (Get-Content $defPath -Raw | ConvertFrom-Json).servers) | Should -BeTrue
    }

    It 'names only agents from agents.json in skipAgents' {
        $keys = @((Read-AgentManifest $AiDir).Keys)
        foreach ($server in (Get-Content $defPath -Raw | ConvertFrom-Json).servers.PSObject.Properties) {
            foreach ($a in @($server.Value.skipAgents | Where-Object { $_ })) { $keys | Should -Contain $a -Because "skipAgents of $($server.Name)" }
        }
    }

    It 'matches its schema' -Skip:(-not $canTestJson) {
        $r = Get-SchemaErrors (Get-Content $defPath -Raw) $schema
        $r.Ok | Should -BeTrue -Because ("mcp-servers.json does not match ai_tooling/mcp-servers.schema.json:`n" + ($r.Messages -join "`n"))
    }

    It 'names the offending field in the schema errors' -Skip:(-not $canTestJson) {
        $r = Get-SchemaErrors '{ "servers": { "x": { "description": "d", "transport": "http", "url": "https://x.test", "urll": "y" } } }' $schema
        $r.Ok | Should -BeFalse
        ($r.Messages -join "`n") | Should -Match 'urll'
    }

    It 'names the place of a broken rule built on not' -Skip:(-not $canTestJson) {
        $r = Get-SchemaErrors '{ "servers": { "x": { "description": "d", "transport": "stdio", "command": "node", "args": ["C:/Repo/x.js"] } } }' $schema
        $r.Ok | Should -BeFalse
        ($r.Messages -join "`n") | Should -Match 'args'
    }

    It 'does not blame a valid note next to the real error' -Skip:(-not $canTestJson) {
        $r = Get-SchemaErrors '{ "$comment": ["a", "b"], "servers": { "x": { "description": "d", "transport": "stdio", "command": "node", "args": ["C:/Repo/x.js"] } } }' $schema
        ($r.Messages -join "`n") | Should -Match 'args'
        ($r.Messages -join "`n") | Should -Not -Match '\$comment'
    }

    It 'names a broken rule built on not next to another error' -Skip:(-not $canTestJson) {
        $r = Get-SchemaErrors '{ "servers": { "x": { "description": "d", "transport": "stdio", "command": "node", "args": ["C:/Repo/x.js"], "urll": "y" } } }' $schema
        ($r.Messages -join "`n") | Should -Match 'urll'
        ($r.Messages -join "`n") | Should -Match 'args'
    }

    It 'takes a property named not for a name, not for the keyword' -Skip:(-not $canTestJson) {
        $r = Get-SchemaErrors '{ "not": 5 }' '{ "type": "object", "properties": { "not": { "type": "string" } } }'
        $r.Ok | Should -BeFalse
        ($r.Messages -join "`n") | Should -Match "at '/not'"
    }

    It 'rejects <name>' -Skip:(-not $canTestJson) -TestCases @(
        @{ name = 'a stdio server without command'; json = '{ "servers": { "x": { "description": "d", "transport": "stdio", "args": [] } } }' }
        @{ name = 'an HTTP server without url'; json = '{ "servers": { "x": { "description": "d", "transport": "http" } } }' }
        @{ name = 'an absolute path in args'; json = '{ "servers": { "x": { "description": "d", "transport": "stdio", "command": "node", "args": ["C:/Repo/ai_tooling/x.js"] } } }' }
        @{ name = 'skipAgents without skipReason'; json = '{ "servers": { "x": { "description": "d", "transport": "http", "url": "https://x.test", "skipAgents": ["gemini"] } } }' }
        @{ name = 'an unknown field'; json = '{ "servers": { "x": { "description": "d", "transport": "http", "url": "https://x.test", "urll": "y" } } }' }
    ) {
        $json | Test-Json -Schema $schema -ErrorAction SilentlyContinue | Should -BeFalse
    }
}

Describe 'Snapshot helpers' {
    It 'writes JSON in one fixed form' {
        ConvertTo-CanonicalJson ('{"a":[1,"x\"y"],"b":{},"c":[],"d":true,"e":null}' | ConvertFrom-Json) |
            Should -Be "{`n  `"a`": [`n    1,`n    `"x\`"y`"`n  ],`n  `"b`": {},`n  `"c`": [],`n  `"d`": true,`n  `"e`": null`n}"
    }

    It 'replaces the roots case-insensitively, in both slash forms' {
        $roots = @([pscustomobject]@{ Path = 'C:\Repo\x'; Token = '{REPO_ROOT}' })
        Get-NormalizedText "c:\repo\x\a and C:/Repo/x/b`r`n" $roots | Should -Be "{REPO_ROOT}\a and {REPO_ROOT}/b`n"
    }
}

Describe 'Read-ProjectManifest' {
    BeforeEach {
        $ai = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force -Path (Join-Path $ai 'manifest') | Out-Null
        $file = Join-Path $ai 'manifest\project.json'
    }

    It 'reads the name and the prefixes, and matches a name that starts with a prefix and a hyphen' {
        [System.IO.File]::WriteAllText($file, '{ "name": "Acme Shop", "skillPrefixes": ["acme", "acmego"] }')
        $p = Read-ProjectManifest $ai
        $p.Name | Should -Be 'Acme Shop'
        $p.Prefixes | Should -Be @('acme', 'acmego')
        'acme-x' | Should -Match $p.Pattern
        'acmego-role-y.md' | Should -Match $p.Pattern
        'acmex' | Should -Not -Match $p.Pattern
        'my-acme-x' | Should -Not -Match $p.Pattern
    }

    It 'refuses a project without manifest/project.json' {
        { Read-ProjectManifest $ai } | Should -Throw
    }

    It 'refuses a project without skill prefixes' {
        [System.IO.File]::WriteAllText($file, '{ "name": "Acme", "skillPrefixes": [] }')
        { Read-ProjectManifest $ai } | Should -Throw '*skillPrefixes*'
    }

    It 'holds a name and lowercase prefixes in this project' {
        $p = Read-ProjectManifest $AiDir
        $p.Name | Should -Not -BeNullOrEmpty
        foreach ($x in $p.Prefixes) { $x | Should -MatchExactly '^[a-z][a-z0-9]*$' }
    }

    It 'names this project''s project skills and subagents with its prefixes' {
        $p = Read-ProjectManifest $AiDir
        foreach ($s in @((Read-SkillManifest $AiDir).Skills.Values | Where-Object { $_.Source -eq 'project' })) { $s.Name | Should -Match $p.Pattern }
        foreach ($f in @(Get-ChildItem (Join-Path $AiDir 'agents') -Filter *.md -File)) { $f.Name | Should -Match $p.Pattern }
    }
}

Describe 'The tooling folder' {
    It 'is the folder the module''s lib folder is in' {
        $ToolingDirName | Should -Be (Split-Path -Leaf $AiDir)
    }
}

Describe 'Add-SkillBindingNote' {
    BeforeEach { $md = Join-Path $TestDrive "$([guid]::NewGuid().ToString('N')).md" }

    It 'puts the note after the frontmatter, one blank line on each side, without a BOM' {
        [System.IO.File]::WriteAllText($md, "---`nname: x`ndescription: d`n---`n`n`n# Body`n")
        Add-SkillBindingNote $md "> Note.`n" $null
        [System.IO.File]::ReadAllText($md).Replace("`r`n", "`n") | Should -BeExactly "---`nname: x`ndescription: d`n---`n`n> Note.`n`n# Body`n"
        Test-Bom $md | Should -BeFalse
    }

    It 'adds the extra note of a skill after the binding note' {
        [System.IO.File]::WriteAllText($md, "---`nname: x`n---`n# Body`n")
        Add-SkillBindingNote $md "> Note.`n" "> Extra.`n"
        [System.IO.File]::ReadAllText($md).Replace("`r`n", "`n") | Should -BeExactly "---`nname: x`n---`n`n> Note.`n`n> Extra.`n`n# Body`n"
    }

    It 'keeps text that is not ASCII' {
        [System.IO.File]::WriteAllText($md, "---`nname: x`n---`nAusf$([char]0xFC)hrung`n", (New-Object System.Text.UTF8Encoding $false))
        Add-SkillBindingNote $md "> Note.`n" $null
        [System.IO.File]::ReadAllText($md, [System.Text.Encoding]::UTF8) | Should -BeLike "*Ausf$([char]0xFC)hrung*"
    }

    It 'refuses a SKILL.md whose first line is not the frontmatter, even with a --- further down' {
        [System.IO.File]::WriteAllText($md, "# Title`n`n---`n`nBody`n")
        { Add-SkillBindingNote $md "> Note.`n" $null } | Should -Throw '*No frontmatter at the top*'
    }

    It 'drops a BOM of the source' {
        [System.IO.File]::WriteAllText($md, [char]0xFEFF + "---`nname: x`n---`n# Body`n")
        Add-SkillBindingNote $md "> Note.`n" $null
        Test-Bom $md | Should -BeFalse
        [System.IO.File]::ReadAllText($md) | Should -BeLike "---*> Note.*"
    }

    It 'refuses a SKILL.md without a frontmatter terminator' {
        [System.IO.File]::WriteAllText($md, "---`nname: x`n# Body`n")
        { Add-SkillBindingNote $md "> Note.`n" $null } | Should -Throw '*frontmatter terminator*'
    }
}

Describe 'Install-UpstreamSkillGroup' {
    BeforeAll {
        # A local git repository stands in for the upstream, so nothing goes over the network.
        $up = Join-Path $TestDrive 'upstream'
        foreach ($d in 'skills\foo-one\references', 'skills\foo-two', 'skills\foo-skip', 'rules', 'foo-root') { New-Item -ItemType Directory -Force -Path (Join-Path $up $d) | Out-Null }
        [System.IO.File]::WriteAllText("$up\skills\foo-one\SKILL.md", "---`nname: foo-one`ndescription: One. Use when testing.`n---`n`n# Foo one`n")
        [System.IO.File]::WriteAllText("$up\skills\foo-one\references\r.md", "ref`n")
        [System.IO.File]::WriteAllText("$up\skills\foo-two\SKILL.md", "---`nname: foo-two`ndescription: Two. Use when testing.`n---`n# Foo two`n")
        [System.IO.File]::WriteAllText("$up\skills\foo-skip\SKILL.md", "---`nname: foo-skip`ndescription: Skipped.`n---`n")
        [System.IO.File]::WriteAllText("$up\rules\foo-rule.md", "Always foo.`n")
        [System.IO.File]::WriteAllText("$up\foo-root\SKILL.md", "---`nname: foo-root`ndescription: At the root.`n---`n# Foo root`n")
        [System.IO.File]::WriteAllText("$up\LICENSE", "MIT`n")
        $ErrorActionPreference = 'Continue'
        git -C $up init -q 2>&1 | Out-Null
        git -C $up add -A 2>&1 | Out-Null
        git -C $up -c user.name=t -c user.email=t@example.invalid commit -q -m init 2>&1 | Out-Null
        git -C $up tag v1 2>&1 | Out-Null
        $upCommit = (git -C $up rev-parse HEAD).Trim()
        $ErrorActionPreference = 'Stop'
    }
    BeforeEach {
        $ai = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force -Path (Join-Path $ai 'manifest'), (Join-Path $ai 'instructions') | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $ai 'manifest\skills.json'), (@(
            '{', '  "groups": {',
            '    "upstream/foo": {', '      "description": "d",', '      "owner": "o",',
            '      "source": { "repo": "https://example.invalid/foo", "installer": "ai_tooling/update-foo-skills.ps1" },',
            '      "apps": [],', '      "default": true', '    }',
            '  },', '  "profiles": {},', '  "skills": { "foo-one": { "group": "upstream/foo" }, "foo-gone": { "group": "upstream/foo" } }', '}') -join "`n"))
        Mock Write-Host { } -ModuleName AgentSetup
        $names = Install-UpstreamSkillGroup -AiDir $ai -Group 'upstream/foo' -Repo $up -Ref 'v1' -Paths @('skills') -Skip @('foo-skip') `
            -Binding "> Binding.`n" -ExtraNotes @{ 'foo-two' = "> Extra.`n" } -CopyLicense -Instructions @{ 'rules/foo-rule.md' = 'foo-rule.md' }
        $group = Join-Path $ai 'skills\upstream\foo'
    }

    It 'installs every skill folder under the paths except the skipped ones, with their files' {
        @($names) | Should -Be @('foo-one', 'foo-two')
        @(Get-ChildItem $group -Directory | ForEach-Object { $_.Name }) | Should -Be @('foo-one', 'foo-two')
        Test-Path (Join-Path $group 'foo-one\references\r.md') | Should -BeTrue
        Test-Path (Join-Path $group 'foo-one\LICENSE') | Should -BeTrue
        Test-Path (Join-Path $group 'foo-one\.git') | Should -BeFalse
    }

    It 'binds every skill, and a skill with an extra note gets it too' {
        [System.IO.File]::ReadAllText((Join-Path $group 'foo-one\SKILL.md')).Replace("`r`n", "`n") | Should -BeExactly "---`nname: foo-one`ndescription: One. Use when testing.`n---`n`n> Binding.`n`n# Foo one`n"
        [System.IO.File]::ReadAllText((Join-Path $group 'foo-two\SKILL.md')) | Should -BeLike '*> Extra.*'
        [System.IO.File]::ReadAllText((Join-Path $group 'foo-one\SKILL.md')) | Should -Not -BeLike '*> Extra.*'
    }

    It 'copies the instruction files it is given' {
        [System.IO.File]::ReadAllText((Join-Path $ai 'instructions\foo-rule.md')).Replace("`r`n", "`n") | Should -Be "Always foo.`n"
    }

    It 'records the commit, the ref and the folder hash in the group''s source' {
        $source = ([System.IO.File]::ReadAllText((Join-Path $ai 'manifest\skills.json')) | ConvertFrom-Json).groups.'upstream/foo'.source
        $source.commit | Should -Be $upCommit
        $source.ref | Should -Be 'v1'
        $source.hash | Should -Be (Get-SkillGroupHash $group)
        (Test-UpstreamSkillHashes (Read-SkillManifest $ai) (Join-Path $ai 'skills')).Matches | Should -Be @('upstream/foo')
    }

    It 'names the skills.json entries to add and to remove' {
        Should -Invoke Write-Host -ModuleName AgentSetup -Times 1 -Exactly -ParameterFilter { "$Object" -like '*add to skills.json: "foo-two": { "group": "upstream/foo" }*' }
        Should -Invoke Write-Host -ModuleName AgentSetup -Times 1 -Exactly -ParameterFilter { "$Object" -like '*remove from skills.json*foo-gone*' }
    }

    It 'replaces the group folder wholesale on the next run' {
        Set-Content -Path (Join-Path $group 'stray.md') -Value 'stray'
        Install-UpstreamSkillGroup -AiDir $ai -Group 'upstream/foo' -Repo $up -Paths @('skills') -Skip @('foo-skip', 'foo-two') | Out-Null
        @(Get-ChildItem $group | ForEach-Object { $_.Name }) | Should -Be @('foo-one')
    }

    It 'throws for a path the upstream does not have, and leaves the installed group and skills.json alone' {
        $before = [System.IO.File]::ReadAllText((Join-Path $ai 'manifest\skills.json'))
        $hash = Get-SkillGroupHash $group
        { Install-UpstreamSkillGroup -AiDir $ai -Group 'upstream/foo' -Repo $up -Paths @('nope') } | Should -Throw "*no folder 'nope'*"
        [System.IO.File]::ReadAllText((Join-Path $ai 'manifest\skills.json')) | Should -Be $before
        Get-SkillGroupHash $group | Should -Be $hash
        @(Get-ChildItem (Split-Path -Parent $group) -Directory | ForEach-Object { $_.Name }) | Should -Be @('foo')
    }

    It 'refuses a group that is not in skills.json, or has no one-line source, before cloning' {
        { Install-UpstreamSkillGroup -AiDir $ai -Group 'upstream/nope' -Repo $up } | Should -Throw "*'upstream/nope' is not in skills.json*"
        # The source over two lines: the installer could not record the commit and hash.
        $json = [System.IO.File]::ReadAllText((Join-Path $ai 'manifest\skills.json')).Replace(', "installer"', ",`n        ""installer""")
        [System.IO.File]::WriteAllText((Join-Path $ai 'manifest\skills.json'), $json)
        { Install-UpstreamSkillGroup -AiDir $ai -Group 'upstream/foo' -Repo $up } | Should -Throw '*one-line*'
        Test-Path (Join-Path $group 'foo-one\SKILL.md') | Should -BeTrue
    }

    It 'throws for an instruction file the upstream does not have, before replacing the group' {
        $hash = Get-SkillGroupHash $group
        { Install-UpstreamSkillGroup -AiDir $ai -Group 'upstream/foo' -Repo $up -Instructions @{ 'rules/nope.md' = 'nope.md' } } | Should -Throw "*no file 'rules/nope.md'*"
        Get-SkillGroupHash $group | Should -Be $hash
    }

    It 'takes the skill folders at the repository root for the path "."' {
        @(Install-UpstreamSkillGroup -AiDir $ai -Group 'upstream/foo' -Repo $up -Paths @('.')) | Should -Be @('foo-root')
    }

    It 'leaves SKILL.md as upstream has it without a binding note' {
        Install-UpstreamSkillGroup -AiDir $ai -Group 'upstream/foo' -Repo $up -Paths @('skills') | Out-Null
        [System.IO.File]::ReadAllText((Join-Path $group 'foo-two\SKILL.md')).Replace("`r`n", "`n") | Should -BeExactly "---`nname: foo-two`ndescription: Two. Use when testing.`n---`n# Foo two`n"
    }
}

Describe 'Publish-ExternalSkillConfig without sources' {
    It 'writes no docs\agents folder when there is nothing to publish' {
        $case = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force -Path "$case\src" | Out-Null
        Publish-ExternalSkillConfig "$case\src" "$case\out" | Should -Be 0
        Test-Path "$case\out\docs\agents" | Should -BeFalse
    }
}

Describe 'Tool helpers' {
    BeforeEach {
        $ai = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force -Path $ai | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $ai 'mcp-servers.json'), '{ "servers": {
            "a": { "description": "d", "transport": "stdio", "command": "node", "args": ["${REPO_ROOT}/ai_tooling/npm-mcp.js", "@scope/a-mcp@1.2.3", "--flag"] },
            "b": { "description": "d", "transport": "stdio", "command": "node", "args": ["${REPO_ROOT}/ai_tooling/other.js"] },
            "d": { "description": "d", "transport": "stdio", "command": "node", "args": ["${REPO_ROOT}/ai_tooling/npm-mcp.js", "pkg-d@2.0.0"] },
            "c": { "description": "d", "transport": "http", "url": "https://example.test/mcp" } } }')
    }

    It 'reads the npm packages npm-mcp.js starts from mcp-servers.json' {
        @(Get-McpNpmPackages $ai) | Should -Be @('@scope/a-mcp@1.2.3', 'pkg-d@2.0.0')
    }

    It 'every package npm-mcp.js starts in this project pins an exact version' {
        foreach ($spec in @(Get-McpNpmPackages $AiDir)) { $spec | Should -Match '^(@[^/@]+/)?[^/@]+@\d+\.\d+\.\d+$' }
    }

    It 'setup-tools.ps1 installs the packages mcp-servers.json pins for npm-mcp.js' {
        $tools = Get-Content (Join-Path $AiDir 'scripts\setup-tools.ps1') -Raw
        $tools | Should -Match ([regex]::Escape('Install-McpNpmPackages $AiDir'))
    }

    It 'Install-McpNpmPackages runs no npm when every package is there' {
        foreach ($pkg in @(@('@scope\a-mcp', '@scope/a-mcp', '1.2.3'), @('pkg-d', 'pkg-d', '2.0.0'))) {
            $dir = Join-Path $ai "mcp-packages\node_modules\$($pkg[0])"
            New-Item -ItemType Directory -Force -Path $dir | Out-Null
            Set-Content (Join-Path $dir 'package.json') "{ ""name"": ""$($pkg[1])"", ""version"": ""$($pkg[2])"" }"
        }
        Mock Invoke-Npm { throw 'npm ran' } -ModuleName AgentSetup
        @(Install-McpNpmPackages $ai).Count | Should -Be 0
        Should -Invoke Invoke-Npm -Times 0 -ModuleName AgentSetup
    }

    It 'Install-McpNpmPackages installs all of them in one npm install, also those already there, and returns those still missing' {
        $dir = Join-Path $ai 'mcp-packages\node_modules\pkg-d'
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        Set-Content (Join-Path $dir 'package.json') '{ "name": "pkg-d", "version": "2.0.0" }'
        Mock Invoke-Npm { } -ModuleName AgentSetup
        @(Install-McpNpmPackages $ai) | Should -Be @('@scope/a-mcp@1.2.3')
        Should -Invoke Invoke-Npm -Times 1 -Exactly -ModuleName AgentSetup -ParameterFilter { "$args" -like '*install*@scope/a-mcp@1.2.3*pkg-d@2.0.0*--no-save*' }
    }

    It 'Install-McpNpmPackages does nothing without npm servers' {
        [System.IO.File]::WriteAllText((Join-Path $ai 'mcp-servers.json'), '{ "servers": {} }')
        Mock Invoke-Npm { throw 'npm ran' } -ModuleName AgentSetup
        @(Install-McpNpmPackages $ai).Count | Should -Be 0
    }

    It 'Test-McpNpmPackage accepts only the pinned version' {
        $dir = Join-Path $TestDrive 'mcp-packages\node_modules\@scope\pkg'
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        Set-Content (Join-Path $dir 'package.json') '{ "name": "@scope/pkg", "version": "1.2.3" }'
        Test-McpNpmPackage $TestDrive '@scope/pkg@1.2.3' | Should -BeTrue
        Test-McpNpmPackage $TestDrive '@scope/pkg@1.2.4' | Should -BeFalse
        Test-McpNpmPackage $TestDrive 'other@1.2.3' | Should -BeFalse
    }
}

Describe 'Agent layout: MCP files of an earlier setup version' {
    It 'resolves mcp.legacyFiles and keepValid against mcp.legacyRoot' {
        $entry = '{ "name": "X", "skills": ".x/skills", "mcp": { "root": "repo", "file": ".x/mcp.json", "key": "servers", "legacyRoot": "home", "legacyFiles": [".x/old.json"], "keepValid": [".x/global.json"] } }' | ConvertFrom-Json
        $l = Get-AgentLayout 'x' $entry 'C:\Out' 'C:\Home'
        $l.Mcp | Should -Be 'C:\Out\.x\mcp.json'
        $l.McpLegacy | Should -Be @('C:\Home\.x\old.json')
        $l.McpKeepValid | Should -Be @('C:\Home\.x\global.json')
    }
}
