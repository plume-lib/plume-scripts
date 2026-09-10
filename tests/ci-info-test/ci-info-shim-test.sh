#!/bin/sh

# Tests that `ci-info` reports exactly what `git-changes` does.
#
# `ci-info` used to be a copy of `git-changes` rather than a shim for it.  The
# two copies drifted apart:  a fix made in one of them was silently missing
# from the other.  This test fails if `ci-info` ever again computes anything
# for itself.

set -eu

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)"
PLUME_SCRIPTS="$(CDPATH='' cd -- "${SCRIPT_DIR}/../.." && pwd -P)"

# The scripts need these, and skipping is better than failing:  a missing
# prerequisite is not a defect in the scripts.
if [ -z "$(command -v jq 2> /dev/null)" ]; then
  echo "$(basename -- "$0"): skipping, because jq is not installed."
  exit 0
fi
if [ -z "$(command -v curl 2> /dev/null)" ] && [ -z "$(command -v wget 2> /dev/null)" ]; then
  echo "$(basename -- "$0"): skipping, because neither curl nor wget is installed."
  exit 0
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT HUP INT TERM

### A repository to run the scripts in

git init -q -b main "$work/repo"
cd "$work/repo"
git config user.email test@example.com
git config user.name "Test User"
echo one > file.txt
git add file.txt
git commit -q -m "First commit"
echo two >> file.txt
git commit -q -a -m "Second commit"
# The scripts ask origin for its default branch, so give this clone an origin.
# It is local, so that this test does not need the network.
git clone -q --bare . "$work/origin.git"
git remote add origin "$work/origin.git"
git fetch -q origin
git remote set-head origin main
git branch a-feature-branch

### The test

status=0

# run SCRIPT: runs SCRIPT the way its documentation says to, and writes what
# the client would `eval`.
run() {
  # Run with an empty environment, so that this test behaves the same whether
  # or not it is itself running under CI.  The CI variables would send the
  # script down a different code path, one that makes a GitHub API request.
  # The inner script is single-quoted on purpose:  its arguments are passed
  # positionally, so that this shell does not expand them into it.
  # shellcheck disable=SC2016
  env -i PATH="$PATH" HOME="$HOME" \
    sh -c 'cd "$1" && "$2/$3" testorg' sh "$work/repo" "$PLUME_SCRIPTS" "$1" \
    2> /dev/null
}

# check BRANCH: checks out BRANCH, then compares the two scripts' output.
check() {
  branch="$1"
  git checkout -q "$branch"
  run ci-info > "$work/ci-info.txt"
  run git-changes > "$work/git-changes.txt"
  if diff -u "$work/git-changes.txt" "$work/ci-info.txt" > "$work/diff.txt"; then
    echo "PASS: ci-info agrees with git-changes on branch $branch"
  else
    echo "FAIL: ci-info does not agree with git-changes on branch $branch"
    echo "  ('-' is git-changes, '+' is ci-info)"
    sed -e 's/^/  /' "$work/diff.txt"
    status=1
  fi
}

check main
check a-feature-branch

exit "$status"
