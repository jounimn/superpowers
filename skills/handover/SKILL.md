---
name: handover
description: Use when a project has a handover.md log (or your human partner asks to start one) and you are about to change code there or have just finished a change
---

# Handover

## Overview

A handover log lets the next agent — or person — pick up where the last one
stopped: who changed what, why, and what is still open. It is `handover.md`
at the root of the main checkout, git-ignored, and every agent that changes
code appends one entry.

**Core principle:** the file list comes from git; the explanation comes from
you. An entry that relies on memory for which files changed is already
incomplete.

Run this skill's scripts from anywhere inside the project, as
`bash <this skill's directory>/scripts/<name>`.

## Is this project opted in?

`bash scripts/handover-path` prints the log's path and exits 0 when the
project keeps a log. Exit 1 means it does not: do nothing, and do not start
one unless your human partner asks. To start one when asked:
`bash scripts/handover-path --init` — it creates the log and git-ignores it;
tell your human partner `.gitignore` changed.

Inside a linked worktree the script still answers with the main checkout's
log. Never write a `handover.md` inside a worktree.

## Before changing code

Read the latest entries (the end of the file): what the previous agent
changed, what it left open, where it stopped. When an entry and the code
disagree, the code wins — say so in your own entry.

## After a change

Write one entry per coherent unit of change — a plan task, a fix round, or a
change your human partner would recognize as one piece of work — before you
claim it done.

1. `bash scripts/handover-files [BASE]` prints the entry's `**Branch:**` line
   and one skeleton line per changed file. BASE defaults to where the newest
   entry in this branch's history ended; pass the commit you started from
   when you know it (in a plan task: the task's BASE; in a fix round: the
   commit your previous entry ended at, so each change is covered once).
2. Fill every skeleton line with what changed in that file and why, and add
   the header and summary:

   ```markdown
   ## 2026-10-01 15:40 · implementer (Task 3) · claude-sonnet-5-5
   **Branch:** feature-x @ a1b2c3d..d4e5f6a
   **Summary:** What changed and why, in one to three sentences.
   **Open:** Anything unfinished or risky the next agent must know (omit when empty).

   - `src/router.ts` (M) — retries outbound calls with backoff
   - `src/retry.ts` (A) — new helper: exponential backoff, max 3 tries
   ```
3. Append the whole entry to the end of the log in one write, never line by
   line — parallel agents may be appending too.

**Agent name:** the name your harness gives you (a named agent or teammate);
otherwise your role — `main session`, `implementer (Task N)`, `fix round 2
(Task N)`, `parallel agent: <scope>` — always followed by your model id.
**Language:** the one your human partner uses.

If the project also keeps an Obsidian vault, update it now with the same file
list (superpowers:obsidian).

## In plans

superpowers:subagent-driven-development and superpowers:executing-plans call
for an entry after each task and each fix round. Implementer subagents get
the log path, BASE and these rules in their dispatch, because subagents do
not load skills on their own.

## Red Flags

| Thought | Reality |
|---------|---------|
| "I'll list the files from memory" | `handover-files` lists them from git. Memory drops the first file you touched. |
| "Small change, no entry needed" | Small changes are the ones the next agent can't reconstruct. One line per file is cheap. |
| "I'll write the entries at the end of the session" | Write each entry when its change is done; sessions end abruptly. |
| "I'm in a worktree, I'll create handover.md here" | Ignored files die with the worktree. Use the path the script prints. |
| "The summary covers it; the file lines can stay terse" | Each file line says what changed in that file and why. That is the handover. |
| "No log here, I'll start one anyway" | Opt-in only. Ask your human partner first. |
