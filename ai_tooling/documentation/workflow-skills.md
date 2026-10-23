# Watch Face Total View workflow skills

These skills in `ai_tooling/skills/custom/` are written for this project's GitHub process
rather than installed from upstream:

| Skill | Claude Code command | Purpose |
|-------|---------------------|---------|
| `custom-workitem-develop` | `/custom-workitem-develop <n>` | Take a GitHub issue (enhancement or bug) from analysis to pull request |
| `custom-pr-review` | `/custom-pr-review <n>` | Code-review a pull request |
| `custom-pr-respond` | `/custom-pr-respond <n>` | Work through the review comments on your own pull request |
| `custom-pipeline-edit` | `/custom-pipeline-edit` | Create or change a GitHub Actions workflow or reusable workflow |
| `custom-decision-council` | `/custom-decision-council <draft or link>` | Have three reviewers attack a decision draft before it goes out (command only) |

## Using them

Run `.\ai_tooling\setup.ps1` once after cloning (see the root [AGENTS.md](../../AGENTS.md)). The skills are then
published with all the others. They read and write GitHub through the GitHub CLI `gh`: sign in once with
`gh auth login` and check with `gh auth status` (a GitHub MCP server is used only where the project
declares one).

- **Claude Code**: a skill is its own slash command. Type `/custom-workitem-develop 123`
  or `/custom-pr-review 456`, or just say "we will work on the workitem 123" /
  "we will review the PR 456".
- **Gemini, Copilot, Cursor**: ask for the skill by name, or describe the task
  the same way. The agent loads the skill from its skills folder.

These skills follow [PERMISSIONS.md](../PERMISSIONS.md): they ask for your approval before every
GitHub write (comments, labels, assignees, branch, PR, reviewers, reviews, pushes) and show the
exact content first. Read-only queries run without asking.

The process facts that differ between GitHub repositories live in
`custom-workitem-develop`'s `references/project-facts.md`: issue types or labels, the project board's
Status values if one is used, where developer and release notes go, the PR title convention,
`CODEOWNERS`, required reviews and status checks, the merge method, and the reviewer list. That is the
place to adjust the issue and PR skills to this project's process. `custom-pipeline-edit` and
`custom-decision-council` have a short `## Project facts` section of their own; the project's CI
conventions are in `.github/workflows/README.md`.

### custom-workitem-develop

Analysis runs on `master`, then the skill moves to `feature/{n}` or `bug/{n}` (`{n}` the issue
number; `gh issue develop` creates the branch and links it to the issue). On the issue it keeps two
things in sync: a **Developer Notes** comment and a **Progress** comment table, each updated in place.
It finishes with the PR to `master` whose last line is `Closes #{n}` (it links and closes the issue only when the PR targets the repository's default branch; otherwise the PR is linked in the issue's Development section), the reviewers
(requested through `gh pr edit --add-reviewer`, with `CODEOWNERS` adding its own), the release notes,
and the move to the review state (by default the issue stays open until the PR merges).
Before the PR, a fresh verifier grades its findings with the reviewer's severities (Blocker to
Question), so you see what the review would report. When the reviewer comments, continue with
`custom-pr-respond`.

**Size first.** The session classes the issue as trivial, bounded or architectural and you confirm the
class. A trivial issue skips the developer notes, the Progress comment and the researcher; the
verifier still checks it. A bounded issue that adds or changes methods, and every architectural issue,
gets a design before any code: the call tree, the files, the signatures without bodies, the tests by
name, and a numbered list of the least confident decisions; the design later goes into the PR
description. Every plan step names its check, work goes in vertical slices of one to three, and when
the plan breaks mid-work the session stops and gets the changed plan approved again.

**Split into streams.** When the plan has two or more parts that change separate apps and can all be
built in one round, the session plans and judges, and workers build the parts in parallel (at most 4
at a time). Each worker is the subagent `custom-workitem-stream-worker`, in its own git worktree next
to your repository (`../custom-worktrees/{id}-s{n}`, a folder next to the repository, outside the IDE's workspace so
its language servers leave it alone), branched from the issue branch. It returns a fixed report:
changes, commands run with their output, what it did not test, its doubts. The session accepts,
revises or escalates each report; it applies an accepted stream to the issue branch and commits
it with your approval.

- In Claude Code, grant the worktrees folder to the session when it asks, so the workers can read and
  edit there without a prompt each.
- A stream is never accepted without the checks its app's `AGENTS.md` names, run with a clean result.
- A worktree has no installed dependencies, so lint and tests that need them run in your checkout
  after the merge.
- Agents without subagent definitions start a fresh subagent with the worker's instructions; agents
  that cannot start subagents work through the streams one after another.
- Delete the worktrees folder any time no issue is split into streams.

### custom-pr-review

Loads the PR and the issues it closes or mentions, then diffs `origin/<target>...origin/pr/{id}` (the PR head fetched from `refs/pull/{id}/head`) locally
without checking anything out, and reviews against the requirements and each app's `AGENTS.md`. You
get findings ranked Blocker / Major / Minor / Nit / Question and a recommended review event
(`APPROVE`, `COMMENT` or `REQUEST_CHANGES`). Only the comments you pick are posted, as **one review**
with inline comments on the right line where possible (`gh api` on the pull request reviews
endpoint). Run it again on the same PR after the author responds: it re-reviews only what changed
since the last reviewed commit and proposes resolving the review threads that were fixed. A thread the
author resolved that the new code does not address gets a reply and is reopened, so the author's next
`custom-pr-respond` run picks it up.

GitHub refuses an approval or change request on your own PR, so the skill submits a plain comment
there and says so. It never pushes to, merges or closes the PR under review, unless you ask it to push
a fix (and approve that push).

The findings also name what the diff could not settle (runtime behaviour, data, a method outside the
diff) and what would: a test checkout, or a question to the author. Besides correctness,
requirements and conventions, the review looks for a **weakened bar** (a lowered threshold, a
skipped or deleted test, a silenced check, an empty `catch`), a refactor that only moves complexity,
a PR above about 1000 hand-written lines, and dependency upgrades without their changelog.

**Testing a PR yourself.** On request, the skill creates a *test checkout*: an independent copy of
your repository, switched to the merge result (the PR's source branch merged into the current
target), which you run like your normal repository in a second IDE window while your own setup keeps
running. How it stays separate:

- **Git**: the copy has its own `.git`. Your branch, changes and stashes are not in it, and nothing
  it does shows up in your repository.
- **Dependencies**: they come with the copy, or are installed there only where the dependency files
  differ from yours.
- **Data and ports**: anything the app keeps outside git (a data file, a settings folder, ports) is
  worked out by the agent from the app's overview, the "Commands" section of its `AGENTS.md` and its
  settings files, with ports shifted so both setups can run at once.
- **Location**: the copy lives in `<parent>\custom_PR_branches\PR_{id}\`, next to your repository.
- **Local edits** to make the copy run are hidden from git (`skip-worktree`), so they can never be
  committed.

Copying a large repository takes minutes. Finalizing the review deletes the whole copy, and nothing
else needs cleaning up. To delete by hand, close everything that uses the folder, then run
`cmd /c rd /s /q "<folder>"`, not `Remove-Item -Recurse`, which can follow the agent junctions.

### custom-pr-respond

The author's side. It loads the review threads of your PR, judges every comment against the code
(holds, does not hold, unclear), asks you to settle the unclear ones before anything is changed,
fixes the agreed ones with the checks of `custom-workitem-develop` (commit and push with their own
approvals), and replies per thread with the file and line that changed or the line that shows the
comment does not hold. The replies and the thread resolves are approved as one list. If the
reviewer's re-review reopens a thread, run it again.

### custom-pipeline-edit

For any change to a GitHub Actions workflow or reusable workflow in `.github/workflows/`. It places the
change by the project's `.github/workflows/README.md`, runs a checklist per job (runner, `permissions`,
sparse checkout, actions pinned by commit SHA, artifacts, secrets), checks the change against a table
of known pitfalls, and recommends three PR validation jobs that protect the tooling (the source check
of `ai_tooling/verify-agent-setup.ps1`, the version and changelog check, the doc link check), with a
workflow sketch. Starting or re-running a workflow is a GitHub write and asks first.

### custom-decision-council

For a forecast, a staffing call or an architecture decision before it goes out. You start it by
typing it (`disable-model-invocation: true`, which hides it from Claude Code's own choice of skills),
with the draft as a file path, a link (web page, issue, wiki page) or pasted text. The session
asks before reading a draft that is not pasted, then lists at most ten items the draft's text links
to and asks once for those (public web pages only need the list), and reads nothing else. It then
starts three reviewers (`custom-decision-council-reviewer`), each alone and on its own model: a
skeptic (Fable), someone who thinks about customers and operations (Sonnet), and someone who has to
carry it out (Opus), and writes one result: recommendation, strongest objection, what would change
the decision, next step. A run costs four model calls (three reviewers and the chair) plus reading
the input. The input file and the result are saved in the agent's temp folder, never in the
repository; attaching the result to an issue asks first.

## Why these roles

The subagent roles (`custom-role-planner`, `-researcher`, `-writer`, `-verifier`, and the
specialised `custom-workitem-stream-worker`; models and tools in the `custom-aitooling-maintain`
skill) split work at a boundary: what crosses it, what is lost, what it buys, and whether one expert
session would do better. Subagents added later, such as `custom-decision-council-reviewer`, serve one
skill each.

- **Verifier** (the end of `custom-workitem-develop`): the one boundary every issue crosses. It
  loses the plan's reasoning on purpose and buys an unanchored check; against a cheaper writer model
  also a second model. The brief carries the decisions recorded in the developer notes, so it checks
  the plan's facts without the author's argument, and asks for a severity of `custom-pr-review` on
  every wrong item.
- **Stream worker**: loses the analysis and the ability to ask; buys parallelism and file isolation.
  Its judge is the session that wrote the streams, so the fresh check stays with the verifier. Worth
  it for issues that change several apps; for one app it shows no gain.
- **Researcher** (the reading step of `custom-workitem-develop`): buys a main context that stays free of
  the reading; loses nuance beyond its short reply, which is why a large reading job names an output
  file for it.
- **Planner and writer**: no skill dispatches them; they serve ad hoc work (a second opinion on an
  approach, a well-specified document).

A judgement, not a measurement: a worker's and a writer's re-reading of what the session already
knows is the main cost of a boundary. The brief is the only lever, which is why briefs and diffs go
over as files and the four roles reply with a status on the first line (the stream worker keeps its
four-part report).

## Editing them

Unlike the upstream skills, these are **edited directly** in
`ai_tooling/skills/custom/<name>/SKILL.md`. No update script touches them, so there is no binding
note and no installer string to change. The rules for editing any project skill (naming,
agent-neutral wording, no BOM, no restated permissions) are in the `custom-aitooling-maintain`
skill.

- The reviewer list in `custom-workitem-develop`'s `references/project-facts.md` is team data (GitHub
  logins and teams). Update it when the team changes, together with `CODEOWNERS`.

Claude Code gets a junction per skill, so an edit is live at once (a new session picks it up).
Antigravity and Cursor get copies, and so does Copilot wherever the Antigravity layout exists,
because it prefers `.agents/skills`: re-run `setup.ps1` to refresh them.

## Personal copies

If you had a copy in `~/.claude/skills/<name>/`, delete it. A personal skill takes precedence over a
project skill with the same name, so you would keep running the old copy and never see the team's
updates.
