#!/bin/sh

# Tests that `set-git-range` does not treat a job whose branch it could not
# determine as a job on the default branch.
#
# A CI service does not always supply a branch name:  CircleCI sets no
# $CIRCLE_BRANCH for a build of a tag, and a GitHub Actions job whose branch
# comes from a throttled API request gets none either.  $CI_BRANCH is then
# empty, and the empty string compares equal to an empty
# $CI_DEFAULT_BRANCH_NAME -- as happens when `git ls-remote` cannot ask origin
# for its default branch.  `set-git-range` used to take that comparison as
# "this job is on the default branch" and compute a commit range covering only
# the last commit, silently omitting the rest of the branch's commits.  When
# the default branch name was known, the same code instead ran
# `git rev-parse ""`, leaving the end of the range empty and making the script
# report that it cannot determine the commit range at all.

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

### A repository with a tag on a branch other than the default branch

git init -q -b main "$work/repo"
cd "$work/repo"
git config user.email test@example.com
git config user.name "Test User"
echo one > file.txt
git add file.txt
git commit -q -m "First commit"
# The scripts ask origin for its default branch, so give this clone an origin.
# It is local, so that this test does not need the network.
git clone -q --bare . "$work/origin.git"
git remote add origin "$work/origin.git"
git fetch -q origin
git remote set-head origin main
# Two commits on a branch, so that a range covering only the last commit is
# distinguishable from one covering the whole branch.
git checkout -q -b feature-branch
echo two >> file.txt
git commit -q -am "Second commit"
echo three >> file.txt
git commit -q -am "Third commit"
git tag v1.0
# A build of a tag checks out a detached HEAD.
git checkout -q --detach v1.0

MAIN_TIP="$(git rev-parse main)"
HEAD_SHA="$(git rev-parse HEAD)"
PREVIOUS_COMMIT="$(git rev-parse HEAD^1)"

### The test

status=0

# run: sources `set-git-range` in a simulated CircleCI build of a tag, which
# supplies no branch name.  Writes "STATUS CI_COMMIT_RANGE" on standard output
# and the scripts' diagnostics on standard error.
run() {
  # Run with an empty environment except for the CircleCI variables, so that
  # this test behaves the same whether or not it is itself running under CI.
  # Other CI services' variables would send the scripts down other code paths.
  # CIRCLE_PR_NUMBER is unset, which is what makes this not a pull request, and
  # CIRCLE_BRANCH is unset, which is what a build of a tag looks like.
  # The inner script is single-quoted on purpose:  its arguments are passed
  # positionally, so that this shell does not expand them into it.
  # shellcheck disable=SC2016
  env -i PATH="$PATH" HOME="$HOME" \
    CIRCLECI=true CIRCLE_TAG=v1.0 CIRCLE_SHA1="$HEAD_SHA" \
    CIRCLE_PROJECT_USERNAME=testorg CIRCLE_PROJECT_REPONAME=testrepo \
    sh -c '
      cd "$1" || exit 2
      PLUME_SCRIPTS="$2"
      CI_DEFAULT_ORGANIZATION=testorg
      set_git_range_status=0
      . "$2/set-git-range" || set_git_range_status=$?
      printf "%s %s" "$set_git_range_status" "$CI_COMMIT_RANGE"
    ' sh "$work/repo" "$PLUME_SCRIPTS"
}

# check DESCRIPTION EXPECTED-RANGE: checks that `set-git-range` succeeds with
# EXPECTED-RANGE and warns that it does not know the branch.
check() {
  description="$1"
  expected="0 $2"
  actual=""
  if ! actual="$(run 2> "$work/stderr")"; then
    echo "FAIL: $description: the test harness could not run set-git-range"
    status=1
    return
  fi
  if [ "$actual" != "$expected" ]; then
    echo "FAIL: $description"
    echo "  expected status and range: $expected"
    echo "  actual status and range:   $actual"
    sed 's/^/  stderr: /' "$work/stderr"
    status=1
    return
  fi
  # The range is a guess, so the client's log must say that it is one.
  if ! grep -q "set-git-range.*cannot determine the branch" "$work/stderr"; then
    echo "FAIL: $description: no warning that the branch is unknown"
    sed 's/^/  stderr: /' "$work/stderr"
    status=1
    return
  fi
  echo "PASS: $description"
}

# The whole branch, because the tag is not on the default branch.  Before the
# fix, `git rev-parse ""` left the end of the range empty and the script failed.
check "a tag build when the default branch is known" \
  "${MAIN_TIP}...${HEAD_SHA}"

# Make origin unreachable and forget its default branch, as when the network is
# down or origin needs credentials that this checkout does not have.  Both
# branch names are then unknown.
git remote set-url origin "$work/nonexistent.git"
git symbolic-ref -d refs/remotes/origin/HEAD
git branch -q -r -d origin/main

# Only the last commit, because nothing names the default branch; but the
# script must say that it guessed.  Before the fix, it said nothing.
check "a tag build when neither branch is known" \
  "${PREVIOUS_COMMIT}...${HEAD_SHA}"

exit "$status"
