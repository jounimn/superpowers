#!/usr/bin/env bash
# Tests for the handover skill's helpers: scripts/handover-path resolves (and
# initializes) the git-ignored log at the main checkout root — from a
# subdirectory or a linked worktree too — and scripts/handover-files prints
# the git-derived part of an entry, chaining from the latest entry.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HO_SCRIPTS="$REPO_ROOT/skills/handover/scripts"

FAILURES=0
TEST_ROOT=""
REPO=""
GIT_ID=(-c user.email=t@example.com -c user.name=t -c commit.gpgsign=false)

pass() { echo "  [PASS] $1"; }
fail() {
    echo "  [FAIL] $1"
    FAILURES=$((FAILURES + 1))
}
expect_eq() {
    if [[ "$2" == "$3" ]]; then pass "$1"; else
        fail "$1"; echo "    expected: $3"; echo "    got:      $2"
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

cleanup() {
    if [[ -n "$TEST_ROOT" && -d "$TEST_ROOT" ]]; then
        rm -rf "$TEST_ROOT"
    fi
}

main() {
    echo "=== Test: handover scripts ==="

    TEST_ROOT="$(mktemp -d)"
    trap cleanup EXIT

    local rc out err base head mid

    # --- a repository without commits: clear error ---
    git init -q -b main "$TEST_ROOT/empty"
    rc=0
    err="$( (cd "$TEST_ROOT/empty" && bash "$HO_SCRIPTS/handover-files") 2>&1 >/dev/null)" || rc=$?
    expect_eq "handover-files in a repo without commits exits 2" "$rc" "2"
    expect_contains "…and says why" "$err" "bad BASE"

    git init -q -b main "$TEST_ROOT/repo"
    REPO="$(cd "$TEST_ROOT/repo" && git rev-parse --show-toplevel)"

    # --- argument validation ---
    rc=0; in_repo bash "$HO_SCRIPTS/handover-path" --bogus >/dev/null 2>&1 || rc=$?
    expect_eq "handover-path rejects an unknown flag with exit 2" "$rc" "2"
    rc=0; in_repo bash "$HO_SCRIPTS/handover-files" a b c >/dev/null 2>&1 || rc=$?
    expect_eq "handover-files rejects three arguments with exit 2" "$rc" "2"

    printf 'one\n' > "$REPO/a.txt"
    printf 'gone\n' > "$REPO/c.txt"
    printf 'move me\n' > "$REPO/d.txt"
    printf 'node_modules/' > "$REPO/.gitignore"   # no trailing newline, on purpose
    commit_all fixture
    base="$(in_repo git rev-parse HEAD)"

    rc=0; in_repo bash "$HO_SCRIPTS/handover-files" not-a-commit >/dev/null 2>&1 || rc=$?
    expect_eq "handover-files rejects an unknown BASE with exit 2" "$rc" "2"

    # --- not opted in ---
    rc=0; out="$(in_repo bash "$HO_SCRIPTS/handover-path" 2>/dev/null)" || rc=$?
    expect_eq "handover-path exits 1 when the project has not opted in" "$rc" "1"
    expect_eq "handover-path prints nothing on stdout when not opted in" "$out" ""

    # --- init ---
    out="$(in_repo bash "$HO_SCRIPTS/handover-path" --init 2>/dev/null)"
    expect_eq "handover-path --init prints the log path at the main root" "$out" "$REPO/handover.md"
    expect_eq "the new log starts with its header" "$(head -n 1 "$REPO/handover.md")" "# Handover log"
    expect_eq ".gitignore keeps its last pattern intact" "$(grep -c '^node_modules/$' "$REPO/.gitignore")" "1"
    in_repo bash "$HO_SCRIPTS/handover-path" --init >/dev/null 2>&1
    expect_eq "a second --init does not duplicate the ignore line" "$(grep -c '^/handover.md$' "$REPO/.gitignore")" "1"
    if in_repo git check-ignore -q handover.md; then pass "handover.md is git-ignored"; else fail "handover.md is git-ignored"; fi
    commit_all "ignore handover log"

    # --- from a subdirectory and from a linked worktree ---
    mkdir -p "$REPO/sub/dir"
    out="$(cd "$REPO/sub/dir" && bash "$HO_SCRIPTS/handover-path")"
    expect_eq "handover-path from a subdirectory resolves the root log" "$out" "$REPO/handover.md"
    in_repo git worktree add -q ../wt -b wt
    out="$(cd "$TEST_ROOT/wt" && bash "$HO_SCRIPTS/handover-path")"
    expect_eq "handover-path in a linked worktree resolves the main checkout's log" "$out" "$REPO/handover.md"
    if [[ -e "$TEST_ROOT/wt/handover.md" ]]; then fail "no handover.md appears inside the worktree"; else pass "no handover.md appears inside the worktree"; fi

    # --- an explicit committed range: M, A, D, R, odd paths ---
    printf 'one\ntwo\n' > "$REPO/a.txt"
    printf 'new\n' > "$REPO/b.txt"
    rm "$REPO/c.txt"
    in_repo git mv d.txt e.txt
    mkdir -p "$REPO/dir with space"
    printf 'acentos\n' > "$REPO/dir with space/ção.txt"
    commit_all change
    head="$(in_repo git rev-parse HEAD)"
    out="$(in_repo bash "$HO_SCRIPTS/handover-files" "$base" "$head")"
    expect_contains "the output starts with the Branch line" "$out" "**Branch:** main @ ${base:0:7}..${head:0:7}"
    expect_not_contains "a committed range is not marked uncommitted" "$out" "+ uncommitted"
    expect_contains "a modified file is listed as M" "$out" '- `a.txt` (M) — '
    expect_contains "an added file is listed as A" "$out" '- `b.txt` (A) — '
    expect_contains "a deleted file is listed as D" "$out" '- `c.txt` (D) — '
    expect_contains "a rename is listed as R with both paths" "$out" '- `d.txt` → `e.txt` (R) — '
    expect_contains "paths with spaces and accents come out verbatim" "$out" '- `dir with space/ção.txt` (A) — '
    expect_not_contains "the log itself is never listed" "$out" 'handover.md'

    # --- working tree changes, run from a subdirectory ---
    printf 'three\n' >> "$REPO/a.txt"
    printf 'u\n' > "$REPO/sub/u.txt"
    mkdir -p "$REPO/.obsidian-vault"
    printf 'note\n' > "$REPO/.obsidian-vault/n.md"   # not ignored here: the filter must drop it
    out="$(cd "$REPO/sub/dir" && bash "$HO_SCRIPTS/handover-files" "$head")"
    expect_contains "an uncommitted range is marked" "$out" "..${head:0:7} + uncommitted"
    expect_contains "an uncommitted modification is listed" "$out" '- `a.txt` (M) — '
    expect_contains "an untracked file is listed with its repo-relative path" "$out" '- `sub/u.txt` (A) — '
    expect_not_contains "vault files are never listed" "$out" '.obsidian-vault'
    rm -rf "$REPO/.obsidian-vault"
    commit_all more

    # --- default BASE chains from the latest entry ---
    mid="$(in_repo git rev-parse HEAD)"
    printf '\n## 2026-10-01 10:00 · main session · test-model\n**Branch:** main @ %s..%s\n**Summary:** fixture entry.\n\n- `a.txt` (M) — fixture\n' \
        "${base:0:7}" "${mid:0:7}" >> "$REPO/handover.md"
    printf 'f\n' > "$REPO/f.txt"
    commit_all "after entry"
    out="$(in_repo bash "$HO_SCRIPTS/handover-files")"
    expect_contains "the default BASE is the latest entry's end commit" "$out" "@ ${mid:0:7}.."
    expect_contains "a change after the latest entry is listed" "$out" '- `f.txt` (A) — '
    expect_not_contains "changes before the latest entry are not repeated" "$out" '`b.txt`'

    # --- latest entry not in HEAD's history: uncommitted changes only ---
    in_repo git switch -q -c side "$base"
    printf 's\n' > "$REPO/s.txt"
    err="$(in_repo bash "$HO_SCRIPTS/handover-files" 2>&1 >/dev/null)"
    expect_contains "a latest entry outside HEAD's history triggers a warning" "$err" "not in HEAD's history"
    out="$(in_repo bash "$HO_SCRIPTS/handover-files" 2>/dev/null)"
    expect_contains "the fallback lists the uncommitted change" "$out" '- `s.txt` (A) — '
    expect_not_contains "the fallback lists nothing committed" "$out" '`f.txt`'
    expect_not_contains "an un-ignored handover.md is still never listed" "$out" 'handover.md'

    # --- nothing changed ---
    rm "$REPO/s.txt"
    rc=0; out="$(in_repo bash "$HO_SCRIPTS/handover-files" HEAD 2>/dev/null)" || rc=$?
    expect_eq "no changes: exit 0" "$rc" "0"
    expect_eq "no changes: nothing on stdout" "$out" ""

    if [[ "$FAILURES" -gt 0 ]]; then
        echo "STATUS: FAILED ($FAILURES failure(s))"
        exit 1
    fi
    echo "STATUS: PASSED"
}

main "$@"
