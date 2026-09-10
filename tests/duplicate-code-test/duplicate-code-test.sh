#!/bin/sh

# Tests that `ci-org-and-branch` and `git-changes` do not duplicate code.
#
# The two scripts do the same thing except for which values they compute and
# which variables they print, and their code used to be duplicated verbatim.
# Duplicated code drifts:  the GitHub Actions code path once queried the GitHub
# API with CircleCI's variables, and the fix was applied to one copy and not
# the other, so one script kept the bug.  The shared code now lives in
# `eval-wrapper.sh` and in the two "set-" scripts, and this test keeps it
# there.
#
# The test compares code only, ignoring comments and blank lines.  Each
# script's documentation describes the same interface in the same words, so
# identical comment blocks are expected and are harmless.

set -eu

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)"
PLUME_SCRIPTS="$(CDPATH='' cd -- "${SCRIPT_DIR}/../.." && pwd -P)"

# The longest run of identical code lines that the two scripts may share.
# Each one names the directory that holds these scripts, sets two variables,
# and sources `eval-wrapper.sh`; only the first and last of those lines are
# the same in both, and they are not adjacent.  The limit leaves room for
# similar boilerplate to be added, while still catching the reappearance of a
# duplicated function or a duplicated argument-parsing loop.
MAX_COMMON_RUN=5

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT HUP INT TERM

# code FILE: copies FILE to standard output, omitting comment-only lines and
# blank lines.  A line whose first non-blank character is `#` is a comment; a
# `#` elsewhere in a line can be part of the code, as in `${var#prefix}`.
code() {
  sed -e '/^[[:space:]]*#/d' -e '/^[[:space:]]*$/d' "$1"
}

code "${PLUME_SCRIPTS}/ci-org-and-branch" > "$work/ci-org-and-branch"
code "${PLUME_SCRIPTS}/git-changes" > "$work/git-changes"

# Prints the length of the longest run of consecutive lines that appears in
# both files, followed by that run's lines.  The files are a few dozen lines
# long, so comparing every pair of starting positions is fast enough.
report="$(awk '
  NR == FNR {
    a[FNR] = $0
    na = FNR
    next
  }
  {
    b[FNR] = $0
    nb = FNR
  }
  END {
    best = 0
    best_i = 0
    for (i = 1; i <= na; i++) {
      for (j = 1; j <= nb; j++) {
        n = 0
        while (i + n <= na && j + n <= nb && a[i + n] == b[j + n]) {
          n++
        }
        if (n > best) {
          best = n
          best_i = i
        }
      }
    }
    print best
    for (k = 0; k < best; k++) {
      print a[best_i + k]
    }
  }
' "$work/ci-org-and-branch" "$work/git-changes")"

common_run="$(printf '%s\n' "$report" | sed -n '1p')"

if [ "$common_run" -gt "$MAX_COMMON_RUN" ]; then
  echo "FAIL: ci-org-and-branch and git-changes share ${common_run} consecutive"
  echo "  lines of code, more than the ${MAX_COMMON_RUN} that this test permits."
  echo "  Move the shared code into eval-wrapper.sh or into a \"set-\" script,"
  echo "  so that a fix to it cannot be applied to one script and not the other."
  echo "  The duplicated lines are:"
  printf '%s\n' "$report" | sed -e '1d' -e 's/^/    /'
  exit 1
fi

echo "PASS: ci-org-and-branch and git-changes share at most ${common_run} consecutive lines of code"
