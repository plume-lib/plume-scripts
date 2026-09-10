#!/bin/sh

# Tests that the scripts whose output the client `eval`s quote their values.
#
# A pull request's branch name is chosen by whoever opened the pull request,
# and git and GitHub permit `$`, backquote, `;`, `&`, `|`, and `'` in it (only
# a space and a few other characters are forbidden).  A value that the client's
# `eval` reads back unquoted is therefore a command injection into the client.
# Each script must instead emit a value that `eval` reads back as exactly one
# word, equal to the original.

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

# Shell metacharacters that git permits in a branch name.  Neither name
# contains a space, because git forbids that.  They are separate because an
# unquoted `'` makes the client's `eval` fail with a syntax error, which would
# hide whether the other metacharacters were executed.
BRANCH_METACHARACTERS="br\$(id)\`id\`;x&y|z"
BRANCH_APOSTROPHE="it's-a-branch"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT HUP INT TERM

### A repository whose current branch has a hostile name

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
git branch "$BRANCH_METACHARACTERS"
git branch "$BRANCH_APOSTROPHE"

### The test

status=0

# check SCRIPT BRANCH: checks out BRANCH, runs SCRIPT the way its
# documentation says to, and checks that the branch name survived the client's
# `eval` intact.
check() {
  script="$1"
  branch="$2"
  actual=""
  git checkout -q "$branch"
  # Run with an empty environment, so that this test behaves the same whether
  # or not it is itself running under CI.  The CI variables would send the
  # script down a different code path, one that makes a GitHub API request.
  if ! actual="$(
    # The inner script is single-quoted on purpose:  its arguments are passed
    # positionally, so that this shell does not expand them into it.
    # shellcheck disable=SC2016
    env -i PATH="$PATH" HOME="$HOME" sh -c '
      cd "$1" || exit 2
      eval "$("$2/$3" testorg 2> /dev/null)" || exit 2
      printf "%s" "$CI_BRANCH"
    ' sh "$work/repo" "$PLUME_SCRIPTS" "$script"
  )"; then
    echo "FAIL: $script: nonzero exit status with branch $branch"
    status=1
    return
  fi
  if [ "$actual" = "$branch" ]; then
    echo "PASS: $script with branch $branch"
  else
    echo "FAIL: $script did not quote CI_BRANCH"
    echo "  expected: $branch"
    echo "  actual:   $actual"
    status=1
  fi
}

for script in ci-info ci-org-and-branch git-changes; do
  check "$script" "$BRANCH_METACHARACTERS"
  check "$script" "$BRANCH_APOSTROPHE"
done

exit "$status"
