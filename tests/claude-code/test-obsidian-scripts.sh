#!/usr/bin/env bash
# Tests for the obsidian skill's helpers: scripts/vault-path resolves (and
# initializes) the git-ignored vault at the main checkout root;
# scripts/vault-changes lists the files whose notes need work (all eligible
# files on the first build, then only changes since .sync-state); and
# scripts/vault-mark-synced records HEAD.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
OB_SCRIPTS="$REPO_ROOT/skills/obsidian/scripts"

FAILURES=0
TEST_ROOT=""
REPO=""
GIT_ID=(-c user.email=t@example.com -c user.name=t -c commit.gpgsign=false)
TAB=$'\t'

pass() { echo "  [PASS] $1"; }
fail() {
    echo "  [FAIL] $1"
    FAILURES=$((FAILURES + 1))
}
expect_eq() {
    if [[ "$2" == "$3" ]]; then pass "$1"; else
        fail "$1"; echo "    expected:"; printf '%s\n' "$3" | sed 's/^/    | /'
        echo "    got:"; printf '%s\n' "$2" | sed 's/^/    | /'
    fi
}
expect_contains() {
    if [[ "$2" == *"$3"* ]]; then pass "$1"; else
        fail "$1"; echo "    expected to contain: $3"; printf '%s\n' "$2" | sed 's/^/    | /'
    fi
}
expect_not_contains() {
    if [[ "$2" != *"$3"* ]]; then pass "$1"; else
        fail "$1"; echo "    expected NOT to contain: $3"; printf '%s\n' "$2" | sed 's/^/    | /'
    fi
}
in_repo() { ( cd "$REPO" && "$@" ); }
commit_all() { ( cd "$REPO" && git add -A && git "${GIT_ID[@]}" commit -qm "$1" ); }
commit_staged() { ( cd "$REPO" && git "${GIT_ID[@]}" commit -qm "$1" ); }   # keeps untracked fixtures untracked
sorted() { printf '%s\n' "$1" | LC_ALL=C sort; }
note() { mkdir -p "$(dirname "$REPO/.obsidian-vault/files/$1.md")"; printf '# note\n' > "$REPO/.obsidian-vault/files/$1.md"; }

cleanup() {
    if [[ -n "$TEST_ROOT" && -d "$TEST_ROOT" ]]; then
        rm -rf "$TEST_ROOT"
    fi
}

main() {
    echo "=== Test: obsidian scripts ==="

    TEST_ROOT="$(mktemp -d)"
    trap cleanup EXIT
    git init -q -b main "$TEST_ROOT/repo"
    REPO="$(cd "$TEST_ROOT/repo" && git rev-parse --show-toplevel)"

    local rc out err head

    mkdir -p "$REPO/src" "$REPO/dist" "$REPO/docs"
    printf 'export const a = 1\n' > "$REPO/src/a.js"
    printf 'x\0y' > "$REPO/img.bin"
    : > "$REPO/empty.txt"
    printf '{}\n' > "$REPO/package-lock.json"
    printf 'x\n' > "$REPO/dist/app.min.js"
    printf 'x\n' > "$REPO/src/a.js.map"
    printf '<svg/>\n' > "$REPO/logo.svg"
    printf 'secret plan\n' > "$REPO/docs/private.md"
    printf 'keep\n' > "$REPO/c.txt"
    printf 'move\n' > "$REPO/d.txt"
    printf 'z\n' > "$REPO/z.txt"
    printf '*.log' > "$REPO/.gitignore"   # no trailing newline, on purpose
    commit_all fixture
    printf 'log\n' > "$REPO/debug.log"          # ignored
    printf 'untracked\n' > "$REPO/notes.txt"    # untracked, not ignored

    # --- argument validation and not opted in ---
    rc=0; in_repo bash "$OB_SCRIPTS/vault-path" --bogus >/dev/null 2>&1 || rc=$?
    expect_eq "vault-path rejects an unknown flag with exit 2" "$rc" "2"
    rc=0; in_repo bash "$OB_SCRIPTS/vault-changes" extra >/dev/null 2>&1 || rc=$?
    expect_eq "vault-changes rejects arguments with exit 2" "$rc" "2"
    rc=0; out="$(in_repo bash "$OB_SCRIPTS/vault-path" 2>/dev/null)" || rc=$?
    expect_eq "vault-path exits 1 when the project has not opted in" "$rc" "1"
    expect_eq "vault-path prints nothing on stdout when not opted in" "$out" ""
    rc=0; in_repo bash "$OB_SCRIPTS/vault-changes" >/dev/null 2>&1 || rc=$?
    expect_eq "vault-changes exits 1 without a vault" "$rc" "1"

    # --- init ---
    out="$(in_repo bash "$OB_SCRIPTS/vault-path" --init 2>/dev/null)"
    expect_eq "vault-path --init prints the vault path at the main root" "$out" "$REPO/.obsidian-vault"
    if [[ -d "$REPO/.obsidian-vault/files" ]]; then pass "--init creates files/"; else fail "--init creates files/"; fi
    expect_eq ".gitignore keeps its last pattern intact" "$(grep -c '^\*\.log$' "$REPO/.gitignore")" "1"
    in_repo bash "$OB_SCRIPTS/vault-path" --init >/dev/null 2>&1
    expect_eq "a second --init does not duplicate the ignore line" "$(grep -c '^/\.obsidian-vault/$' "$REPO/.gitignore")" "1"
    if in_repo git check-ignore -q .obsidian-vault/; then pass "the vault is git-ignored"; else fail "the vault is git-ignored"; fi
    in_repo git add .gitignore
    commit_staged "ignore vault"
    printf 'docs/private*\r\n# comment\r\n\r\n' > "$REPO/.obsidian-vault/.vaultignore"   # CRLF, on purpose

    # --- worktree resolution ---
    in_repo git worktree add -q ../wt -b wt
    out="$(cd "$TEST_ROOT/wt" && bash "$OB_SCRIPTS/vault-path")"
    expect_eq "vault-path in a linked worktree resolves the main checkout's vault" "$out" "$REPO/.obsidian-vault"

    # --- initial build: eligible files only ---
    out="$(in_repo bash "$OB_SCRIPTS/vault-changes" 2>"$TEST_ROOT/err")"
    err="$(cat "$TEST_ROOT/err")"
    expect_eq "the initial build lists exactly the eligible files" "$(sorted "$out")" \
        "$(sorted "A${TAB}.gitignore
A${TAB}c.txt
A${TAB}d.txt
A${TAB}notes.txt
A${TAB}src/a.js
A${TAB}z.txt")"
    expect_contains "the initial build reports its count on stderr" "$err" "initial build — 6 files"
    note src/a.js
    out="$(in_repo bash "$OB_SCRIPTS/vault-changes" 2>/dev/null)"
    expect_contains "an existing note turns A into M during the initial build" "$out" "M${TAB}src/a.js"

    # --- mark synced ---
    head="$(in_repo git rev-parse HEAD)"
    out="$(in_repo bash "$OB_SCRIPTS/vault-mark-synced")"
    expect_eq "vault-mark-synced prints HEAD" "$out" "$head"
    expect_eq ".sync-state holds HEAD" "$(tr -d '[:space:]' < "$REPO/.obsidian-vault/.sync-state")" "$head"
    out="$(in_repo bash "$OB_SCRIPTS/vault-changes")"
    expect_eq "right after a sync, only untracked files without notes are listed" "$out" "A${TAB}notes.txt"

    # --- incremental: M, A, D, R; nothing for note-less deletions or binaries ---
    note .gitignore; note c.txt; note d.txt; note notes.txt
    printf 'export const a = 2\n' > "$REPO/src/a.js"
    printf 'export const b = 1\n' > "$REPO/src/b.js"
    in_repo git rm -q c.txt z.txt
    in_repo git mv d.txt e.txt
    printf 'x\0z' > "$REPO/img.bin"
    in_repo git add src/a.js src/b.js img.bin
    commit_staged "changes"
    printf 'u\n' > "$REPO/u.txt"
    out="$(in_repo bash "$OB_SCRIPTS/vault-changes")"
    expect_eq "changes since the sync, resolved against existing notes" "$(sorted "$out")" \
        "$(sorted "A${TAB}src/b.js
A${TAB}u.txt
D${TAB}c.txt
M${TAB}src/a.js
R${TAB}d.txt${TAB}e.txt")"

    # --- from a linked worktree: that checkout's changes, the main vault's notes ---
    printf 'w\n' > "$TEST_ROOT/wt/w.txt"
    out="$(cd "$TEST_ROOT/wt" && bash "$OB_SCRIPTS/vault-changes")"
    expect_eq "vault-changes in a worktree lists that worktree's changes" "$out" "A${TAB}w.txt"

    # --- from a subdirectory: repo-relative output, the main vault's state ---
    local root_out
    root_out="$(in_repo bash "$OB_SCRIPTS/vault-changes")"
    out="$(cd "$REPO/src" && bash "$OB_SCRIPTS/vault-changes")"
    expect_eq "vault-changes from a subdirectory prints the same repo-relative lines" "$out" "$root_out"

    # --- synced in a worktree, checked in main: no false deletions ---
    printf 'y\n' > "$TEST_ROOT/wt/y.txt"
    ( cd "$TEST_ROOT/wt" && git add y.txt && git "${GIT_ID[@]}" commit -qm y )
    note y.txt
    ( cd "$TEST_ROOT/wt" && bash "$OB_SCRIPTS/vault-mark-synced" >/dev/null )
    out="$(in_repo bash "$OB_SCRIPTS/vault-changes" 2>"$TEST_ROOT/err")"
    err="$(cat "$TEST_ROOT/err")"
    expect_not_contains "a file added on another branch is not reported deleted" "$out" "D${TAB}y.txt"
    expect_contains "a .sync-state outside HEAD's history triggers a warning" "$err" "merge-base"
    expect_contains "…and this checkout's own changes are still listed" "$out" "M${TAB}src/a.js"

    # --- mark synced from a subdirectory: written in the main vault ---
    head="$(in_repo git rev-parse HEAD)"
    out="$(cd "$REPO/src" && bash "$OB_SCRIPTS/vault-mark-synced")"
    expect_eq "vault-mark-synced from a subdirectory prints HEAD" "$out" "$head"
    expect_eq "…and writes .sync-state in the main vault" "$(tr -d '[:space:]' < "$REPO/.obsidian-vault/.sync-state")" "$head"
    if [[ -e "$REPO/src/.obsidian-vault" ]]; then fail "no vault appears in the subdirectory"; else pass "no vault appears in the subdirectory"; fi

    # --- agent-tool state folders are excluded ---
    mkdir -p "$REPO/.claude-flow"
    printf '{"s":1}\n' > "$REPO/.claude-flow/state.json"
    out="$(in_repo bash "$OB_SCRIPTS/vault-changes")"
    expect_not_contains ".claude-flow files are never listed" "$out" ".claude-flow"

    # --- unknown commit in .sync-state ---
    printf 'deadbeef\n' > "$REPO/.obsidian-vault/.sync-state"
    rc=0; in_repo bash "$OB_SCRIPTS/vault-changes" >/dev/null 2>&1 || rc=$?
    expect_eq "an unknown commit in .sync-state exits 2" "$rc" "2"

    if [[ "$FAILURES" -gt 0 ]]; then
        echo "STATUS: FAILED ($FAILURES failure(s))"
        exit 1
    fi
    echo "STATUS: PASSED"
}

main "$@"
