# Issue tracker: GitHub Issues

> **External skill configuration.** This file is read by the upstream Matt Pocock skills, installed
> into `ai_tooling/skills/upstream/mattpocock/` by `ai_tooling/update-mattpocock-skills.ps1`.
> The project's own skills do not use it. Its source is `ai_tooling/external-skill-config/`;
> `ai_tooling/setup.ps1` writes the copy in `docs/agents/` that the skills read, so edit the
> source. Do not add files to either folder; see "Where things go" in the `custom-docs-update` skill.

Issues and specs for this repo live as GitHub issues in `Panaith/watchface_total_view`
(https://github.com/Panaith/watchface_total_view/issues). Use the GitHub CLI `gh` (check `gh auth status` first) and pass
`--repo Panaith/watchface_total_view` where a command could pick another repository. Every write (create, edit, comment,
label, link, close) needs the user's approval first, also for unattended ("AFK") work: see `PERMISSIONS.md`, section 1.

## Conventions

- **Issue kinds**: an issue labelled `enhancement` (or of the issue type Feature) for features and specs, `bug` for
  defects, a sub-issue or task-list item for an implementation slice. Branches are named `feature/{id}` or `bug/{id}`
  after the issue number.
- **Text is Markdown**: title, body and comments. Write placeholders as `{id}`, not as an HTML-like tag.
- **Create**: `gh issue create --repo Panaith/watchface_total_view --title "..." --body-file {file} --label enhancement`
  (use `--body-file` for anything longer than a line, so quoting cannot garble it).
- **Read**: `gh issue view {n} --comments` (body, labels, assignees, comments); `--json title,body,labels,state,comments`
  for structured output.
- **List/query**: `gh issue list --state open --label needs-triage --json number,title,labels`; `gh issue list --search
  "is:open label:needs-triage -label:needs-info"` for anything else. `gh api` covers what the subcommands do not.
- **Comment**: `gh issue comment {n} --body-file {file}`.
- **Apply / remove labels**: `gh issue edit {n} --add-label "a,b"` and `--remove-label "c"`. Labels are additive; no
  need to read the current list first. A label must exist: `gh label create {name} --description "..."` (a write).
- **Close**: `gh issue close {n} --reason completed` (`--reason "not planned"` for won't-fix), with a comment when the
  reason is not obvious. An issue closes by itself when a PR with `Closes #{n}` merges into the default branch.

## References in commits and PRs

A branch name (`feature/{id}`, `bug/{id}`) carries the issue number. Issues and PRs share one number space on GitHub.

Link a PR to the issue it finishes with `Closes #{n}` (or `Fixes #{n}`) in the PR description: the issue closes when the
PR merges. Apart from that, never write `#` followed by a number in a commit message, PR title or PR text: GitHub links
`#{number}` to the issue or PR with that number, so "#6" in a numbered list links issue 6 and notifies it. Number rows
and findings as "Nr. 6" or "Q6".

## Pull requests as a triage surface

**PRs as a request surface: no.** _(Set to `yes` to run GitHub pull requests through triage too; `/triage` reads this flag.)_

## When a skill says "publish to the issue tracker"

Create a GitHub issue (label `enhancement` unless it's a defect, then `bug`). If it is about the AI agent tooling
(anything under `ai_tooling/`, the skills, `PERMISSIONS.md`, an `AGENTS.md` or the MCP servers), put it where the
`custom-aitooling-maintain` skill says tooling work goes (section 8): a parent issue, label or milestone.

## When a skill says "fetch the relevant ticket"

Read the issue by number, including its comments: `gh issue view {n} --comments`.

## Wayfinding operations

Used by `/wayfinder`.

- **Map**: a single issue labelled `wayfinder:map`, holding Notes / Decisions-so-far / Fog in its body.
- **Child ticket**: an issue added to the map as a **sub-issue** (GitHub's sub-issues; `gh api` with the REST endpoint
  `repos/Panaith/watchface_total_view/issues/{map}/sub_issues`), or, where sub-issues are not available, a task-list line
  `- [ ] #{child}` in the map's body. Labelled `wayfinder:{type}` (`research`/`prototype`/`grilling`/`task`).
- **Blocking**: GitHub's "blocked by" relationship where available, otherwise a line `Blocked by: #{blocker}` in the
  child's body. A ticket is unblocked when every blocker is closed.
- **Frontier query**: the map's open children, minus any with an open blocker or an assignee; first in map order wins.
- **Claim**: `gh issue edit {n} --add-assignee @me`, the session's first write.
- **Resolve**: comment the answer, close the issue, then append a context pointer (gist + link) to the map's
  Decisions-so-far.
