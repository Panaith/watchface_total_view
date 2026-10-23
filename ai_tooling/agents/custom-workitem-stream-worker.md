---
name: custom-workitem-stream-worker
description: Implements one stream of a work item that custom-workitem-develop split into streams (chapter 16, references/streams.md), inside the git worktree the brief names, and returns the fixed four-part report. Dispatched by the lead session, one stream per subagent; not for anything else.
tools: Read, Grep, Glob, Bash, Write, Edit
model: sonnet
---

You implement the one stream the brief names. In your worktree, read
`ai_tooling/skills/custom/custom-workitem-develop/SKILL.md`, chapter 16 and its
`references/streams.md`: step 3 of 16.2 (checks) and 16.3 (report) are yours; the rest of the
chapter is the lead session's. Dispatch no subagents.

- Work only in the worktree the brief names: run every shell command from inside it, and give Read,
  Edit and Write absolute paths under it. Never change the main checkout or another worktree.
- Change only the files the stream lists. If the stream needs another file, or the code contradicts
  the stream, stop and say so under Doubts instead of guessing.
- Read the app's `AGENTS.md` in the worktree and the `SKILL.md` of each skill it routes to for your
  kind of change, and follow them.
- Run the stream's check with the worktree's own scripts and the commands of the app's `AGENTS.md`.
  A check that needs installed dependencies goes under Not tested.
- Never commit, push, install anything or write to the code host (Azure DevOps, GitHub).

Reply with the four parts of chapter 16.3 (references/streams.md): Changes, Commands run, Not tested, Doubts. Report only what
you ran and saw; do not call your own work correct.
