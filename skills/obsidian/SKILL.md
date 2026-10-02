---
name: obsidian
description: Use when a project has an .obsidian-vault context vault (or your human partner asks to map a project into Obsidian) and you are starting work there or have just changed its files or structure
---

# Obsidian Context Vault

## Overview

The vault is a map of the project kept as Obsidian notes: one
`Architecture.md` and one note per source file. Later sessions read the map
instead of re-reading the codebase, and your human partner browses it in
Obsidian (graph view, backlinks). It is `.obsidian-vault/` at the root of the
main checkout, git-ignored.

**Core principle:** git says which notes are stale; you say what changed. A
map is only worth reading if every change that matters reaches it.

Run this skill's scripts from anywhere inside the project, as
`bash <this skill's directory>/scripts/<name>`.

## Is this project opted in?

`bash scripts/vault-path` prints the vault's path and exits 0 when the
project keeps one. Exit 1 means it does not: do nothing unless your human
partner asks. Inside a linked worktree the script still answers with the main
checkout's vault — never create a vault inside a worktree.

## Before changing code

Read `Architecture.md`, then the notes for the files you will touch. Notes
are context, not truth: when a note and the code disagree, the code wins and
you fix the note.

## Building the vault

1. `bash scripts/vault-path --init` creates the vault and git-ignores it;
   tell your human partner `.gitignore` changed.
2. `bash scripts/vault-changes` lists every eligible file and prints the
   count on stderr. Above about 200 files, report the count to your human
   partner and wait for a go-ahead.
3. Write one note per file at `files/<path>.md`, shaped as in
   [note-templates.md](note-templates.md). For a large project use
   superpowers:dispatching-parallel-agents: one agent per top-level
   directory, each given the template, the vault path and its slice of the
   list.
4. Write `Architecture.md` from the notes (template in the same file).
5. `bash scripts/vault-mark-synced`.

## Keeping it current

After each change — with the handover entry, when the project keeps a
handover log (superpowers:handover) — run `bash scripts/vault-changes` and
resolve every line:

| Line | Action |
|------|--------|
| `A path` | Write the note. |
| `M path` | Purpose, interface (exports, signatures, routes, schemas) or dependencies changed: rewrite those sections. Internal change only: add a History line. |
| `D path` | Delete the note. |
| `R old new` | Move the note to `files/<new>.md`, update its `source:`, and replace `[[files/<old>.md` with `[[files/<new>.md` across the vault. |

Update `Architecture.md` when files were added, removed or renamed, a
dependency appeared between modules, or an entry point or external service
changed. Then `bash scripts/vault-mark-synced`. Run vault-mark-synced from the
checkout whose changes you just synced.

History lines read `- <date> · <agent> · <model id> — <what changed>`: from the handover
entry when there is one, otherwise from the commit subjects.

**Before finishing a branch**, run the same pass as a sweep:
superpowers:finishing-a-development-branch calls for it.

## Red Flags

| Thought | Reality |
|---------|---------|
| "Internal refactor, the notes are fine" | Add the History line. Rewrite sections only when purpose, interface or dependencies changed. |
| "I'll fix the links after the rename later" | A rename without the link rewrite leaves dead links in the graph. Same pass. |
| "The note says X, so the code does X" | Notes are context. Read the code before relying on a claim. |
| "I'll mark it synced and catch up next time" | `vault-mark-synced` only after every line is resolved; it is the vault's claim to be current. |
| "A vault in the worktree is fine" | Ignored folders die with the worktree. Use the path the script prints. |
| "I'll paste the function into the note" | Notes summarize. Signatures at most, and never a secret value. |
