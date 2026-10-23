---
name: custom-workitem-develop
description: Takes a GitHub issue (work item: enhancement or bug) of the Watch Face Total View repo from analysis to pull request with the gh CLI. Use when the user runs /custom-workitem-develop <n>, says "we will work on the workitem <n>" or "we will work on issue <n>", or names an issue number to implement, fix or continue.
argument-hint: <issue number>
---

# Work on GitHub issue $ARGUMENTS

Repo: Watch Face Total View. GitHub repository `Panaith/watchface_total_view`. Use the GitHub CLI `gh` for every read and write and pass `--repo Panaith/watchface_total_view` where a command could pick another repository. Check once that it is signed in: `gh auth status`. Where the project declares a GitHub MCP server, it may be used instead; `gh` is the primary form here. "Work item" and "issue" mean the same in this skill.

If no issue number was given, ask for it before doing anything else.

The labels, fields, states and rules of the project's issue process are in [Project facts](references/project-facts.md). This skill refers to them by name ("the Developer Notes", "the review state").

## Workflow

Follow the chapters below in this order:

1. [Session name](#1-session-name)
2. [Work item type](#2-work-item-type)
3. [Apps](#3-apps)
4. [Analyze the work item](#4-analyze-the-work-item)
5. [Target branch](#5-target-branch)
6. [Read the apps](#6-read-the-apps)
7. [Root cause or implementation location](#7-root-cause-or-implementation-location)
8. [Plan](#8-plan)
9. [Review](#9-review)
10. [Developer Notes](#10-developer-notes)
11. [Progress comment](#11-progress-comment)
12. [Branch](#12-branch)
13. [Implementation](#13-implementation)
14. [Verification](#14-verification)
15. [Finalizing the work item](#15-finalizing-the-work-item)

When the plan has two or more parts that change separate apps and can all be built in one round, chapter 13 may run them as streams: [Split into streams](references/streams.md).

The [Approvals](#approvals) rules apply throughout.

## 1. Session name

Name this chat `workItem <n>`:

- If the agent has a tool to rename its own session, use it (in the Claude desktop app: `set_session_title` with `session_id: "self"`). When the user named the session themselves, the app asks them to approve the new name.
- If there is no such tool, or the rename is declined or refused (an unattended session), remind the user instead:
  - Claude Code terminal: run `/rename workItem <n>`;
  - Claude Code VS Code extension: hover over the session in the session list and use its rename action;
  - other agents: use the chat's own rename action.

Do this first: the rename, or the reminder at the top of the first reply, together with chapter 2.

## 2. Work item type

Look up issue $ARGUMENTS (`gh issue view $ARGUMENTS --repo Panaith/watchface_total_view`) and tell the user whether it is a bug or an enhancement (a feature, a user story), by the issue type or label that [Project facts](references/project-facts.md) names.

## 3. Apps

Ask which apps, and which repo-level areas outside the apps, we will work on. It is one multi-select list, split into parts asked in the same call, each part ending with "none of the above" (`PERMISSIONS.md`, "How to ask").

- The apps are the Apps table of the root `AGENTS.md`. Under each app, show its "What" column from that table. Put at most 3 apps in a part, plus "none of the above", and label the parts `Apps 1/{n}`, `Apps 2/{n}`, ... When an app is added to or removed from the table, regroup the parts.
- The last part, `Repo {n}/{n}`, holds the repo-level areas: `ai_tooling` (the agent tooling: skills, setup, `PERMISSIONS.md`, the `AGENTS.md` files; it is an app too), `.github/workflows/` (and `pipelines/` if the project has such a folder) if the project has CI, and the root docs (`README.md`, `documentation/`).
- The answer decides what chapter 6 reads: each selected app, plus the skill the root routing table names for a repo-level area (`custom-pipeline-edit` for the workflows, `custom-docs-update` for root docs); for `ai_tooling` its `AGENTS.md` names `custom-aitooling-maintain`.
- If every part comes back "none of the above", say so and ask what the issue changes.
- If `ai_tooling` is selected, check the issue's parent against the agent tooling parent in [Project facts](references/project-facts.md). If it has none, say so and offer to set it; setting it is a GitHub write and needs approval. As a sub-issue: `gh api --method POST repos/Panaith/watchface_total_view/issues/{parent number}/sub_issues -F sub_issue_id=$(gh api repos/Panaith/watchface_total_view/issues/$ARGUMENTS --jq .id)` (the REST field takes the issue's id, not its number); as a label or milestone: `gh issue edit`.

## 4. Analyze the work item

Read the issue with all its data and analyze every non-empty field, not only the body: `gh issue view $ARGUMENTS --repo Panaith/watchface_total_view --json number,title,body,state,stateReason,labels,assignees,author,milestone,projectItems,comments,issueType,parent,subIssues,blockedBy,closedByPullRequestsReferences,url` (`--comments` cannot be combined with `--json`; `comments` is a JSON field; if the installed `gh` lacks a field, `gh issue view --help` lists them, and `gh api` covers the rest). Also read the images and files linked inside the body and the comments (download them with `gh api` or the URL when the repository is private), the parent issue (title, body, acceptance criteria; the `parent` field, where the project uses sub-issues, or the issue a task list or reference names), and the title and state of every other linked issue and pull request (`gh api repos/Panaith/watchface_total_view/issues/$ARGUMENTS/timeline` lists the cross-references).

- The fields table in [Project facts](references/project-facts.md) says what each label, field and form answer changes in the later chapters. For one it does not list, read the issue form or template in `.github/ISSUE_TEMPLATE/` instead of guessing.
- Read the issue's edit history or the earlier pull requests only when the item failed testing before and the comments do not say why.
- In the analysis, list the fields that change something and what they change.

## 5. Target branch

The analysis must read the current code, so it runs on `master`.

- Check the current branch (`git branch --show-current`).
- If it is not `master`, tell the user which branch they are on and ask whether to check out `master`.
  - Warn first if there are uncommitted changes.
  - If the current branch is already the issue's branch (resumed work), say so and ask whether to stay on it instead.
- Run `git fetch origin master` and tell the user if the local `master` is behind `origin/master`.

## 6. Read the apps

Read the selected apps in the repo: their `documentation/overview.md` and `AGENTS.md` first, then the relevant code. Load the skills that the routing tables in the root and app `AGENTS.md` name for the kind of change.

## 7. Root cause or implementation location

**Size first.** Say which class the issue is, and why; revise it if an impact check (below) changes the picture:

- **trivial** - one obvious change in one place (a text, a constant, a one-line fix). Chapters 10 and 11 and the researcher of this chapter are skipped, and with them every later step that updates the Developer Notes or the Progress comment; the verifier of chapter 14 still runs, on a small diff, briefed with the plan from chapter 9.
- **bounded** - a known shape in known files, new or changed functions included. The full workflow.
- **architectural** - a new screen, endpoint or table, several apps, or a change many callers or entry points depend on. The full workflow, plus the design of chapter 8 and the reviewer of chapter 9.

The user confirms the class in chapter 9; a trivial item that grows during the work is re-classed, and the skipped chapters are caught up.

- Bug: find the root cause.
- Enhancement: find where the changes should be implemented.
- Reading legwork that spans more than a few files goes to a fresh `custom-role-researcher` (an agent without subagent definitions briefs a fresh subagent with the body of `ai_tooling/agents/custom-role-researcher.md`); a bounded change in known files is read by the session itself. Its brief asks what the code does today - which entry points, which data, which callers - and names the files to start from; it does not state the goal, so the answer describes the code rather than the wish.
- When the app's `AGENTS.md` routes to an impact or dependency check (who calls what, which entry points and data a change reaches), run it on every function, class or screen you plan to change. Put the entry points it reaches and the data written downstream into the plan and the Developer Notes as test hints; name a change that reaches very many entry points as a risk in the plan.

## 8. Plan

**Plan the work** needed to finish the issue. Every step ends on its check: `step - verify: {command or observation}`. For a bug, the first step reproduces it (the check fails on the old code), and the last re-runs that check.

When the change shows in the user interface (a dialog, a list, an alert) and the app's skills offer a way to capture it, that check is a capture run: for a bug the first step runs it on the old code, and the last makes the before/after picture once the fix is committed. Capture steps carry their own approvals. Ask the developer once whether a local environment with suitable test data is available; if not, the check becomes a manual test hint in the Developer Notes.

**Design** (bounded items that add or change functions, and every architectural item), as plain text in the plan and later in the Developer Notes (in a code block or with `{T}` instead of `<T>`, so no renderer swallows angle brackets):

- the call tree of the change: who calls what, down to the functions that change; from the impact check of chapter 7 where there is one;
- the file-tree diff: files added, changed, removed;
- the signatures without bodies (name, parameters, return type), and for a screen or endpoint its fields;
- the tests by name, each with the one assertion it makes;
- a numbered list of the **least confident decisions**: the choices the user should look at hardest.

If the plan has two or more parts that change separate apps and can all be built in one round (no part needs another's result), plan them as streams ([chapter 16](references/streams.md), 16.1). Parts in one app are built in this session, even when they change different files.

## 9. Review

Present the findings, the size class and the plan for review. Do not implement anything yet - wait for the user.

For an architectural item, ask now who will review the pull request (the reviewer list of chapter 15.1) and suggest walking the design through with that person before the first slice is written; what they change goes into the plan. Posting the design to them (an issue comment or a message) is a GitHub write (`PERMISSIONS.md`).

## 10. Developer Notes

Add all necessary information to the issue's **Developer Notes** (see [Project facts](references/project-facts.md#developer-notes)): root cause (bug) or where the change goes (enhancement), the fix, test status, and test prerequisites.

- If Project facts name a place other than a comment (for example a section of the issue body, or a project field): write it there, after reading its current content, and merge instead of overwriting if someone else changed it.
- Otherwise (the default): post an issue comment whose first line is the heading `Developer Notes` with `gh issue comment $ARGUMENTS --repo Panaith/watchface_total_view --body-file {file}`. Remember the comment id, read with `gh api repos/Panaith/watchface_total_view/issues/$ARGUMENTS/comments --jq '.[] | select(.body | startswith("Developer Notes")) | .id'` (do not parse it from the URL `gh issue comment` prints; if several comments match, take the newest, the last one listed), and update that same comment later: `gh api --method PATCH repos/Panaith/watchface_total_view/issues/comments/{comment id} -F body=@{file}`. Read the comment (`gh api repos/Panaith/watchface_total_view/issues/comments/{comment id}`) right before each update, compare its `updated_at` with the one you saw last, and merge changes by others.
- Either way the write needs its own approval. Show the exact text first; write it to a file in the temp folder and pass the path, so no shell quoting changes it.
- Keep it in sync as the plan progresses (for example, move test items from ⏳ to ✅).

## 11. Progress comment

Add a comment with the implementation progress.

- Title: `Progress` (first line of the comment, as a heading).
- Body: a table with these columns:
  - **Task**: every task that needs to be done, as planned in the analysis chapters.
  - **Apps**: the apps the task has to be implemented in.
  - **Progress**: percentage of finished implementation, given separately for each app (e.g. `app-a: 100%`, `app-b: 50%`, with the app's folder name).
  - In a row with several apps, separate them with `; ` (e.g. `app-a: 100%; app-b: 50%`). Markdown tables have no line break inside a cell that is safe everywhere, so `<br>` is not used.
- Post it with `gh issue comment` and remember the comment id as in chapter 10.
- Keep it in sync as the plan progresses: update that same comment (`gh api --method PATCH repos/Panaith/watchface_total_view/issues/comments/{comment id} -F body=@{file}`) instead of adding a new one each time.

## 12. Branch

Check whether a branch for the issue exists, locally and on the remote (`git branch --list`, `git ls-remote --heads origin`; `gh issue develop --list $ARGUMENTS --repo Panaith/watchface_total_view` lists the branches linked to the issue). The name follows the branch rule in the root `AGENTS.md` (by default `feature/{id}` for enhancements and `bug/{id}` for bugs, `{id}` the issue number), cut from `master`.

- If none exists, ask whether the user wants one created; if yes, create it and link it to the issue: `gh issue develop $ARGUMENTS --repo Panaith/watchface_total_view --name {branch} --base master` creates the branch on the remote from the tip of `master` and links it in the issue's Development section; then `git fetch origin` and `git checkout {branch}`. Tools that take a commit id (the git refs API through `gh api`) need the full 40-character id: `git rev-parse {ref}` after a fetch, and show it when asking for approval.
- If the current branch is a different one, check out the issue's branch (warn first if there are uncommitted changes).

## 13. Implementation

1. **State.** Before the first change, set the issue to the **work started state** of [Project facts](references/project-facts.md) (by default: assign yourself, `gh issue edit $ARGUMENTS --repo Panaith/watchface_total_view --add-assignee @me`, and set the project board's Status where the project uses one), unless it is already there or further along.
2. Implement the plan in **vertical slices**: each slice is one usable piece from entry point to data, one to three slices at a time, each its own row in the Progress comment. For an architectural item, show the first working slice before continuing. A plan with streams is implemented by [chapter 16](references/streams.md), 16.2 to 16.4. Keep the Developer Notes and the Progress comment in sync as slices are completed.
3. **Backtrack.** When a step cannot be done as planned (the code contradicts the plan, a check cannot pass, a decision of chapter 8 turns out wrong), stop: update the plan and the Developer Notes, and get the change approved as in chapter 9 before going on.

## 14. Verification

When the implementation is finished:

- make sure all relevant tests and checks pass (the app's `AGENTS.md` lists them: unit tests, lint, build, and the capture run planned in chapter 8), and show the developer the pictures of a capture run;
- update project documentation if needed (skill `custom-docs-update`);
- **review the implementation with a subagent**, a fresh `custom-role-verifier` that did not write the code (an agent without subagent definitions briefs a fresh subagent with the body of `ai_tooling/agents/custom-role-verifier.md`, or without subagents does the same review itself in a separate pass):
  - Give it the issue number, its acceptance criteria or repro steps, the apps, the decisions of chapters 8 and 9 as the Developer Notes record them (the plan's facts, not your reasoning), and the diff to review: `git diff origin/master...HEAD` plus any uncommitted changes (`git diff HEAD`). Write the diff and the brief to files in the temp folder and pass the paths; a brief that pastes them costs the same tokens twice.
  - After fixing its findings, send the fix diff and the findings back to the same verifier (where the agent can message a running subagent; otherwise a fresh verifier with the fix diff and the earlier findings); it re-checks those and their surroundings, not the whole change. After five such rounds, stop and show the user what is still open.
  - It reviews every changed file against the checklist in `custom-pr-review`, chapter 7 (correctness, requirements, security, conventions, documentation, tests, the app-specific traps), loading the skills the app's `AGENTS.md` names, and returns its findings with file and line, most severe first. Ask in the brief for a severity on every wrong item, from `custom-pr-review` chapter 10 (Blocker, Major, Minor, Nit, Question), so the findings read as the reviewer's would.
  - It only reads: no edits, no commits, no GitHub writes.
  - Verify each finding yourself before acting on it, fix the confirmed ones (re-running the affected checks), and tell the user which findings you fixed, which you rejected and why;
- report all of this to the user.

## 15. Finalizing the work item

1. **Pull request.** Push the branch (a push needs approval) and create a PR from it to `master` with `gh pr create --repo Panaith/watchface_total_view --base master --head {branch} --title {title} --body-file {file}`. Use `--draft` when the user wants it, and follow `.github/pull_request_template.md` where the repository has one.
   - If `master` is not the right target for any reason (for example, the branch was not cut from it), explain why and propose the alternative target branch before creating anything.
   - Link the PR to the issue: the last line of the description is `Closes #{n}` (or `Fixes #{n}`), `{n}` the issue number. GitHub links the PR and closes the issue on merge only when the PR targets the repository's default branch. If `master` is not the default branch, the keyword does nothing: link the PR in the issue's Development section by hand (or rely on the link `gh issue develop` made for the branch), and close the issue after the merge (`gh issue close $ARGUMENTS --repo Panaith/watchface_total_view`, a GitHub write that needs approval). The closing line is the only place where `#` and a number appear.
   - Ask for the reviewers with one multi-select list, split into parts of at most 3 people plus "none of the above", all parts asked in the same call (`PERMISSIONS.md`, "How to ask"). The candidates are the reviewer list in [Project facts](references/project-facts.md).
     - GitHub has no per-PR "required reviewer": which reviews are required comes from the branch protection or ruleset and the `CODEOWNERS` file ([Project facts](references/project-facts.md)). Reviewers from `CODEOWNERS` are requested automatically; do not add them twice. Tell the user which review is still required before the merge.
     - Before using them, check that they can be requested: `gh api repos/Panaith/watchface_total_view/collaborators/{login}` answers 204 for a collaborator. A team is written `Panaith/{team}`.
     - Add them with `gh pr edit {pr} --repo Panaith/watchface_total_view --add-reviewer {login},{login}` (or with `--reviewer` in `gh pr create`). Show the command as part of the PR approval; one approval covers that list. Afterwards check with `gh pr view {pr} --repo Panaith/watchface_total_view --json reviewRequests`.
   - PR title and description: the convention in [Project facts](references/project-facts.md#pull-request-title-and-description). The Fix section of an item with a design from chapter 8 holds that design as plain text (call tree, files, signatures) so the reviewer reads the structure before the diff.
   - No `#` followed by a number in the title, the description (except the closing line above) or a commit message: GitHub links every `#{number}` as an issue or PR, and a merge commit message or squash message can carry the PR title, the description or the commit list, depending on the repository's merge settings ([Project facts](references/project-facts.md#reviewers)). Number rows and findings as "Nr. 6" or "Q6".
2. **Release Notes.** If the project keeps them ([Project facts](references/project-facts.md): a section of the PR description, a label, or the GitHub release notes), write them once the PR is created. Text the product owner already wrote in the issue is extended, not replaced.
   - Style and the place: [Project facts](references/project-facts.md).
   - A change customers do not see (agent tooling, workflows, internal docs): mark it as not relevant where the project has a label or section for that, and still write one short internal line if the project requires a non-empty release note ([Required fields](references/project-facts.md#required-fields)).
3. **State.** Move the issue to the **review state** of [Project facts](references/project-facts.md) (by default: the issue stays open until the PR is merged; set the project board's Status to In Review where the project uses one). Do this together with the Release Notes write, as one list for approval.
4. **Review comments.** When the reviewer comments on the PR, continue with `custom-pr-respond` (`/custom-pr-respond {PR number}`), not by pasting the comments into a session.

## 16. Split into streams

Only when chapter 8 finds two or more parts that change separate apps and can all be built in one round. A normal run is the default; a split pays off only when the parts are truly independent and large.

You, the session model, are the **lead** (not the `custom-role-planner` subagent, which cannot dispatch): you plan the streams and judge the results, and workers write the code. Chapters 14 and 15 then run on the merged result as usual.

Plan, work, report and judge: [references/streams.md](references/streams.md)

## Field format

Issue bodies and comments are **Markdown** natively, so no format switch is needed.

- Write the text to a file and pass it with `--body-file` or `-F body=@{file}`, never inline in the shell: quoting, backticks and `$` in a command line change the text.
- Write placeholders as `{id}` and put code, signatures and generics in code spans or blocks, so angle brackets are not read as HTML.
- A `#` followed by a number links to that issue or PR: write "Nr. 6" or "Q6" instead (the closing line of chapter 15 is the one exception).
- Read the text back afterwards (`gh issue view`, or `gh api` for a comment) and check it.

## Approvals

`PERMISSIONS.md` applies throughout: how to ask, what needs approval, and what to do when a write fails (report it and stop; do not retry another way). Show the exact content before every write and post it only after approval.

The GitHub writes in this skill, each needing its own approval, are: creating or linking the branch (chapter 12), assigning the issue and setting the work started state (chapter 13), every Developer Notes and Progress comment write or update (chapters 10, 11, 13 and 16), every push (chapters 13 and 15), everything in chapter 15 (PR, reviewers, Release Notes, state), setting the parent in chapter 3, and creating a follow-up bug issue ([Required fields](references/project-facts.md#required-fields)). Commits need approval too (`PERMISSIONS.md`, section 4), the one per stream in chapter 16 included.
