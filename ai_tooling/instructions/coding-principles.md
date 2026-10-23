---
description: Coding principles for every change to app code - assumptions, scope, reuse, checking and reporting.
trigger: always_on
---

# Coding principles

- Before changing code, say what you assume. If the task has several readings, present them
  and let the user pick. If a simpler approach exists, say so. If something is unclear, stop
  and ask.
- Change only what the task needs: every changed line traces back to the request.
  No drive-by refactoring, renaming or reformatting. Match the surrounding style. Mention
  unrelated dead code; leave it in place. Remove only the orphans your own change created.
- Before writing new code, check in this order: is it needed at all, does the
  repo already have it, does the language or framework provide it, does an
  installed dependency provide it. Then write the smallest version that works: no
  configurability nobody asked for, no abstraction for single-use code, no handling of cases
  the internal flow cannot produce (validation at a system boundary stays).
- Decide how you will check the result before you start, then check it. For a bug, that check
  fails on the old code first. A test is never weakened, skipped or deleted to get green.
- Report only what you ran and saw: the command, its result, and what you did
  not test. Never "this should work". "Done" names its evidence: the diff for "implemented",
  the failing-then-passing run for "fixed", the checklist against the acceptance criteria for
  "requirements met".
- Lead with the answer or the next action. When work spans turns, say which step of how many
  is done. End with one concrete next step. Skip preamble and closers. An approval question
  keeps the format of `PERMISSIONS.md`, and a reply format a skill or role prescribes wins over
  this default.
- After three failed attempts at the same fix, stop: name the assumption that may be wrong and
  ask one diagnostic question.
