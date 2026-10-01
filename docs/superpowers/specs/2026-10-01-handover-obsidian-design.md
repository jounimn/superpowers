# Handover Log and Obsidian Context Vault — Design

Date: 2026-10-01
Status: design approved in-session by Nilson; spec pending review
Branch: `fork/local-skills` off `main` (v6.4.2) — fork-only, never sent upstream

## Goal

Two opt-in skills for this fork:

- **`handover`** keeps a `handover.md` log in which every agent that changes
  code records who it is, a summary, and what changed in each file — so the
  next agent (or person) can pick up the work.
- **`obsidian`** keeps an Obsidian vault inside the project with one
  architecture note and one note per source file, so future sessions can
  load context from notes instead of re-reading the codebase. Major code
  changes are reflected in the notes.

Both have a write side (after changing code) and a read side (before
changing code). The read side is what makes them pay off.

## Scope decisions (settled with Nilson)

- **Opt-in per project.** A project opts in when the skill is invoked there
  explicitly (`--init`). A project without `handover.md` / the vault is
  untouched; both skills do nothing there.
- **Both artifacts are git-ignored.** `handover.md` and `.obsidian-vault/`
  live at the root of the main checkout and are added to `.gitignore` on
  init.
- **Main checkout, not the worktree.** Superpowers work often happens in
  `.claude/worktrees/…`. A git-ignored path does not exist inside a
  worktree and would be lost when the worktree is removed, so both skills
  always resolve the main checkout root via
  `git rev-parse --path-format=absolute --git-common-dir` (its parent
  directory). Outside git, the current directory is the root.
- **Names are the ones Nilson chose** (`handover`, `obsidian`), not the
  repo's verb-first convention.
- **Plain markdown, zero dependencies.** The vault is a folder of `.md`
  files; no Obsidian plugin, CLI or MCP is required. Scripts use bash + git
  only, matching `subagent-driven-development/scripts/*`.

## Skill layout

```
skills/handover/
  SKILL.md
  agents/openai.yaml          # Codex packaging metadata
  scripts/handover-path       # resolve (and --init) handover.md
  scripts/handover-files      # changed-file list for an entry
skills/obsidian/
  SKILL.md
  note-templates.md           # file-note and Architecture.md templates
  agents/openai.yaml
  scripts/vault-path          # resolve (and --init) the vault
  scripts/vault-changes       # what changed since the last sync
  scripts/vault-mark-synced   # record the synced commit
```

Frontmatter (name + description only; descriptions are triggers, not
workflow summaries):

- `handover` — "Use when a project has a handover.md log (or your human
  partner asks to start one) and you are about to change code there or
  have just finished a change."
- `obsidian` — "Use when a project has an .obsidian-vault context vault (or
  your human partner asks to map a project into Obsidian) and you are
  starting work there or have just changed its structure or files."

## `handover`

### Scripts

`handover-path [--init]`
- Prints the absolute path of `<main root>/handover.md`.
- Exit 0 when the file exists. Exit 1 with nothing on stdout (message on
  stderr) when the project has not opted in.
- `--init`: creates the file with its header (below) when missing, appends
  `/handover.md` to `<main root>/.gitignore` unless `git check-ignore`
  already ignores it, and reports that `.gitignore` changed (uncommitted).

`handover-files [<base> [<head>]]`
- Prints one skeleton line per changed file, ready to be filled:
  `` - `path` (M) — `` ; renames as `` - `old` → `new` (R) — ``.
- Source: `git diff --name-status -M <base>..<head>`; when `<head>` is
  omitted, also uncommitted tracked changes and untracked, non-ignored
  files (marked `+ uncommitted`).
- Default `<base>`: the end commit of the latest entry in `handover.md` when
  that commit is an ancestor of `HEAD`; otherwise `HEAD` (uncommitted
  changes only) with a warning on stderr. This chains entries so every
  change is covered once.
- Never lists `handover.md` or anything under `.obsidian-vault/`.

### Log format

Header written by `--init`:

```markdown
# Handover log

Every agent that changes code in this project appends one entry at the
end (oldest first). Read the latest entries before changing code.
```

Entry (appended in a single write, never line by line):

```markdown
## 2026-10-01 15:40 · implementer (Task 3) · claude-sonnet-5-5
**Branch:** feature-x @ a1b2c3d..d4e5f6a
**Summary:** What changed and why, in 1-3 sentences.
**Open:** (optional) anything unfinished, risky, or the next agent must know.

- `src/router.ts` (M) — what changed in this file and why
- `src/retry.ts` (A) — …
```

- **Agent name:** the name the harness gives the agent (named agent,
  teammate) if any; otherwise its role — `main session`, `implementer
  (Task N)`, `fix round 2 (Task N)`, `parallel agent: <scope>`. Always
  followed by the model id.
- **Range:** `<base7>..<head7>`, plus ` + uncommitted` when the entry covers
  working-tree changes.
- **Language:** entries are written in the language your human partner
  uses.
- **Completeness:** the file list comes from `handover-files`, so no file
  depends on the agent's memory; every skeleton line must be filled.

### When

- **Write:** after each coherent unit of change, before claiming it done —
  in plans, once per task (and once per fix round); outside plans, once per
  change your human partner would recognize as one piece of work.
- **Read:** before changing code in an opted-in project, read the latest
  entries (the end of the file). Treat them as context, and trust the code
  over the log when they disagree.

## `obsidian`

### Vault layout

```
<main root>/.obsidian-vault/
  Architecture.md          # project map (the entry point)
  files/<repo path>.md     # one note per source file, mirroring its path
  .sync-state              # the commit the vault was last synced to
  .vaultignore             # optional extra exclusions (glob per line)
```

A dot-folder also keeps the vault out of default agent searches
(ripgrep skips hidden and git-ignored paths), so notes cost context only
when read on purpose. Obsidian opens the folder as a vault directly and
creates its own `.obsidian/` config inside it.

### Which files get notes

Tracked files plus untracked, non-ignored files, text only (binary and
empty files are skipped), excluding by default: lockfiles
(`*.lock`, `package-lock.json`, `pnpm-lock.yaml`, `yarn.lock`), `*.min.*`,
`*.map`, `*.svg`, `handover.md`, `.superpowers/**`, the vault itself, and
any glob in `.vaultignore`.

### Notes

File note (`files/src/api/router.ts.md`):

```markdown
---
source: src/api/router.ts
synced: 2026-10-01
tags: [file]
---
# router.ts

## Purpose
One to three sentences: what this file is for.

## Key contents
- `createRouter()` — …

## Depends on
- [[files/src/lib/http.ts.md|http.ts]]

## History
- 2026-10-01 · implementer (Task 3) · claude-sonnet-5-5 — added retry
```

- Links always carry the explicit `.md` (a link to `http.ts` would resolve
  to the source file, not the note).
- No "Used by" section: Obsidian's backlinks pane derives it from
  "Depends on" links, and the graph view works from the same links.
- `History` lines come from the handover entry when the project also keeps
  a handover log; otherwise from the commit subjects that touched the file.

`Architecture.md`: purpose, stack, entry points, module map (one line per
module with links to its key file notes), data flow as a mermaid diagram
(Obsidian renders mermaid natively), external services and configuration,
conventions, last synced commit. Both templates live in
`note-templates.md`.

### Scripts

`vault-path [--init]` — same contract as `handover-path`, for
`<main root>/.obsidian-vault/`. `--init` creates the folder and `files/`,
and git-ignores `/.obsidian-vault/`.

`vault-changes`
- No `.sync-state`: prints every eligible file as `A<TAB>path` (initial
  build) and the count on stderr.
- Otherwise: `git diff --name-status -M <synced>` (commit vs working tree)
  filtered to eligible files, plus untracked eligible files that have no
  note yet.
- Output lines: `A path`, `M path`, `D path`, `R old new` (tab-separated).

`vault-mark-synced` — writes `git rev-parse HEAD` to `.sync-state` and
prints it. Uncommitted changes that were documented will show up again on
the next run; the agent sees the note is current and moves on. Known gap:
an untracked file that already has a note is not re-reported when edited
until it is committed.

### What counts as a major change

- **File note rewritten** when the file's purpose, interface (exports,
  signatures, routes, schemas) or dependencies changed.
- **History line only** for internal changes.
- **Architecture.md updated** when files are added, removed or renamed, a
  dependency appears between modules, or an external service or entry
  point changes.
- `D` → delete the note. `R` → move the note, update its `source:`, and
  rewrite links `[[files/<old>.md` → `[[files/<new>.md` across the vault.

### When

- **Initial build** (`--init`, then `vault-changes`): report the file count
  to your human partner and wait for a go-ahead above ~200 files. Large
  projects use superpowers:dispatching-parallel-agents, one agent per
  top-level directory writing file notes; the coordinating agent then
  writes `Architecture.md` and runs `vault-mark-synced`.
- **Incremental:** together with each handover entry (its file list is the
  work list), or after any change when only the vault is opted in.
- **Sweep:** before finishing a branch, run `vault-changes`, resolve every
  line, update `Architecture.md` if structure changed, `vault-mark-synced`.
- **Read:** before changing code, read `Architecture.md` and the notes for
  the files you will touch. Code beats notes; fix a note that disagrees.

## Integration with existing skills

| Where | Change |
|---|---|
| `subagent-driven-development/implementer-prompt.md` | Optional "Context upkeep" block the controller includes only when the project opted in: the absolute `handover.md` / vault paths, BASE, and the instruction to append its entry (via `handover-files BASE`) and update notes for the files it changed, then say so in its report. Subagents do not load skills on their own, so the brief carries the instructions. |
| `subagent-driven-development/SKILL.md` › 5. Complete the task | Before the ledger line: confirm the entry for Task N exists (fix rounds add their own). |
| `subagent-driven-development/SKILL.md` › Finish | Before the workspace is deleted: the vault sweep (or dispatch it). |
| `executing-plans/SKILL.md` › per-task completion and Finish | The executor writes its own entry and updates notes after each task; sweep at Finish. |
| `finishing-a-development-branch/SKILL.md` | After Step 1 (verify tests), before presenting options: the vault sweep if opted in. The options menu is untouched. |
| `verification-before-completion/SKILL.md` › Common Failures | Row: change done in a project with `handover.md` → an entry covering every changed file → "the code works" is not enough. |
| `hooks/session-start` | When `handover.md` or `.obsidian-vault/` exists at the main root of `${CLAUDE_PROJECT_DIR:-$PWD}`, append one reminder line each to the injected context (read before changing code; append/update after). Guarded so a git failure never breaks the hook. Harnesses that bootstrap without this hook rely on the skill descriptions. |
| `.muse-plugin/plugin.json` | Two entries in the static skill list. |
| `README.md` › Skills Library | Two entries. |

## Testing

- **Structure tests** — `tests/handover/test-skill-structure.sh` and
  `tests/obsidian/test-skill-structure.sh`, modeled on
  `tests/diagnosing-superpowers/test-skill-structure.sh` (name matches
  directory, description starts "Use when", ≤1024 chars, referenced files
  exist, no "the user").
- **Script tests** — `tests/claude-code/test-handover-scripts.sh` and
  `tests/claude-code/test-obsidian-scripts.sh`, each building a temp git
  repo: init creates the file/folder and git-ignores it; resolution from a
  linked worktree returns the main root; `handover-files` reports A/M/D/R
  and untracked files and chains from the last entry; `vault-changes`
  lists only eligible text files, honors `.vaultignore`, and reports
  M/D/R after `vault-mark-synced`. Registered in
  `tests/claude-code/run-skill-tests.sh`.
- **Hook test** — `hooks/session-start` output is valid JSON with and
  without the reminders, and the reminders appear only when the files
  exist.
- **Behavior check (writing-skills RED/GREEN, light)** — one scenario per
  skill with a subagent in a scratch repo: baseline without the skill vs
  with it. Pass when, with the skill, the entry lists every changed file
  with a filled description, and the vault gains correct notes plus an
  updated `Architecture.md` for a structural change.

## Out of scope

- Rotating or archiving a long `handover.md`.
- Syncing the vault across machines, or Obsidian plugins (Dataview etc.).
- A session-start reminder for harnesses that do not run `hooks/session-start`.
- Any upstream PR (AGENTS.md rejects tool-specific and fork-specific skills).
