# Watch Face Total View Repository — AI Agent Instructions

## Permissions — read first
**Before doing anything else, read [PERMISSIONS.md](ai_tooling/PERMISSIONS.md) and follow it for the whole session.** It says which actions need the user's approval first, what is never done without an explicit request, and how to ask.

[@ai_tooling/PERMISSIONS.md](ai_tooling/PERMISSIONS.md)

## Agent setup version — check at session start
Once per session, before the first task, compare `ai_tooling/version` (committed) with `ai_tooling/localversion`
(gitignored, written by `setup.ps1`) as whole numbers.
- **`version` higher, or `localversion` missing**: tell the user both numbers and the `ai_tooling/CHANGELOG.md` entries above the local version
  (only the newest if `localversion` is missing), one line each. Ask, as one approval, to run `.\ai_tooling\setup.ps1` without
  `-Agent` (it refreshes every agent layout already on disk), then `.\ai_tooling\verify-agent-setup.ps1` (`PERMISSIONS.md`, section 5: setup installs the pinned MCP servers with npm and keeps Antigravity's MCP file in the home folder valid). Afterwards show the "What's new" section `setup.ps1`
  printed, as it is, report failed checks without fixing them unasked, and say that new MCP servers and rules load in a new session.
- **No `version`, or a PR test checkout** (under `custom_PR_branches`; `custom-pr-review`): do nothing, say nothing, whatever the numbers.
- **Otherwise, equal or lower**: run `.\ai_tooling\verify-agent-setup.ps1 -Quick` (copies against their sources, skill junctions; a second or two). If it fails or warns, tell the user what it reports and offer the re-run above; otherwise say nothing.

## Apps — before working on one, read its `documentation/overview.md` and `AGENTS.md`
| App | What | Docs |
|---|---|---|
| watchface | Wear OS digital watch face, declarative Watch Face Format, built with Gradle, no runtime code; short name `watchface` | [overview](watchface/documentation/overview.md), [AGENTS.md](watchface/AGENTS.md) |
| project in WatchFace Studio | The original Samsung Watch Face Studio project of the face (`.wfs` sources, assets), edited only in the WFS GUI; short name `wfs` | [overview](project%20in%20WatchFace%20Studio/documentation/overview.md), [AGENTS.md](project%20in%20WatchFace%20Studio/AGENTS.md) |
| ai_tooling | AI agent tooling: skills, permissions, MCP servers, setup for every agent (not deployed) | [overview](ai_tooling/documentation/overview.md), [AGENTS.md](ai_tooling/AGENTS.md) |

For people: [documentation/overview.md](documentation/overview.md).
GitHub: repository `Panaith/watchface_total_view`. Use the GitHub CLI `gh`: run `gh auth status` first, and pass `--repo Panaith/watchface_total_view` to every `gh`
command that could pick another repository. Tools that take a commit id (the git refs API through `gh api`) need the full 40-character id
(`git rev-parse {ref}` after a fetch); show the full id when asking for approval.

## Skills — load the one the task needs
| When you ... | Load |
|---|---|
| work on an issue ("we will work on the workitem {id}") | [`custom-workitem-develop`](ai_tooling/skills/custom/custom-workitem-develop/SKILL.md) |
| review a pull request ("we will review the PR {id}"), or respond to the review comments on your own PR | [`custom-pr-review`](ai_tooling/skills/custom/custom-pr-review/SKILL.md), [`custom-pr-respond`](ai_tooling/skills/custom/custom-pr-respond/SKILL.md) |
| change a GitHub Actions workflow (`.github/workflows/`) | [`custom-pipeline-edit`](ai_tooling/skills/custom/custom-pipeline-edit/SKILL.md) |
| decide where a new document or agent content goes, move or delete one, or finish any change | [`custom-docs-update`](ai_tooling/skills/custom/custom-docs-update/SKILL.md) |
| change `ai_tooling/`, `PERMISSIONS.md` or an `AGENTS.md`, or create a new skill | [`custom-aitooling-maintain`](ai_tooling/skills/custom/custom-aitooling-maintain/SKILL.md) |
| work in one app, or change its conventions and standards | the skills its `AGENTS.md` (Apps table) routes to: a standard goes into that skill |

Upstream skills are found by their descriptions; read the **Watch Face Total View binding note** after each one's frontmatter. Where a project skill covers the same task, it wins.

## Rules for every change
- **Isolation**: each app is versioned on its own, with its own build; apps share no source files and no imports. Exception: `ai_tooling` writes generated, gitignored files into app folders, and app `AGENTS.md` files import its files. Run an app's commands from inside its folder.
- **Where things go**: before creating any documentation file, rule or agent content, load `custom-docs-update`; never create a new folder or kind of file without asking.
- **Branches** `feature/{id}` for enhancements and `bug/{id}` for bugs (`{id}`: the issue number), from `master`; one-line Conventional Commits messages in the imperative, scoped by app or area (`feat(wff): ...`, `docs: ...`), focused and atomic; never `#` with a number in a commit message, PR title or description (GitHub links it to that issue or PR: write "Nr. 6" or "Q6"); the one exception is `Closes #{n}` as the last line of a PR description, which links and closes the issue only if the PR targets the default branch (else link it in the issue's Development section); documentation in the same commit as the code.
- **Subagents**: use a role (`custom-role-planner`, `-researcher`, `-writer`, `-verifier`) unless a skill names its own; an agent without subagent definitions briefs a fresh subagent with the body of `ai_tooling/agents/{role}.md`. Before handing over a deliverable (code, a document, issue or PR text), have a fresh `custom-role-verifier` check it against its sources; answers in the chat need none.

## Never
- Never put shared agent instructions into a `CLAUDE.md`, `GEMINI.md` or `.github/copilot-instructions.md`: they are generated per developer.
- Never generate or commit Android Studio / JetBrains files (`.idea/`, `*.iml`) or their caches.
