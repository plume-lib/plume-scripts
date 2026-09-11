#!/bin/sh

# Tests that `set-git-range` splits a whole CI_COMMIT_RANGE on its literal
# separator, "..." or "..", and that the range and its endpoints agree.
#
# When a CI service supplies the range but not its endpoints -- Travis CI is
# the one that does, via $TRAVIS_COMMIT_RANGE -- `set-git-range` splits the
# range itself.  It used to split on "." rather than on "...", so a range whose
# endpoints are refs that contain a dot, as tag names usually do, came apart in
# the wrong place:  "v1.2.3...v1.3.0" yielded the start "v1" and the end "0".
# Neither names a commit, so every client's `git diff` then failed or, worse,
# reported the diffs of some unrelated ref that happened to have that name.

set -eu

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)"
PLUME_SCRIPTS="$(CDPATH='' cd -- "${SCRIPT_DIR}/../.." && pwd -P)"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT HUP INT TERM

### A repository with dotted tag names

git init -q -b main "$work/repo"
cd "$work/repo"
git config user.email test@example.com
git config user.name "Test User"
echo one > file.txt
git add file.txt
git commit -q -m "First commit"
git tag v1.2.3
echo two > file.txt
git commit -q -a -m "Second commit"
echo three > file.txt
git commit -q -a -m "Third commit"
git tag v1.3.0
# The scripts ask origin for its default branch, so give this clone an origin.
# It is local, so that this test does not need the network.
git clone -q --bare . "$work/origin.git"
git remote add origin "$work/origin.git"
git fetch -q origin
git remote set-head origin main

FIRST="$(git rev-parse v1.2.3)"
SECOND="$(git rev-parse 'v1.3.0^1')"
THIRD="$(git rev-parse v1.3.0)"

### The test

status=0

# run RANGE: sources `set-git-range` in a simulated Travis CI job whose
# $TRAVIS_COMMIT_RANGE is RANGE, and prints the resulting start, end, and range.
run() {
  # Run with an empty environment except for the Travis CI variables, so that
  # this test behaves the same whether or not it is itself running under CI.
  # Other CI services' variables would send the script down other code paths.
  # The inner script is single-quoted on purpose:  its arguments are passed
  # positionally, so that this shell does not expand them into it.
  # shellcheck disable=SC2016
  env -i PATH="$PATH" HOME="$HOME" \
    TRAVIS=true TRAVIS_COMMIT_RANGE="$1" TRAVIS_BRANCH=main \
    TRAVIS_REPO_SLUG=testorg/testrepo \
    sh -c '
      cd "$1" || exit 2
      PLUME_SCRIPTS="$2"
      export PLUME_SCRIPTS
      . "$2/set-git-range" || exit 2
      printf "%s %s %s" "$CI_COMMIT_RANGE_START" "$CI_COMMIT_RANGE_END" "$CI_COMMIT_RANGE"
    ' sh "$work/repo" "$PLUME_SCRIPTS" 2> /dev/null
}

# check DESCRIPTION RANGE EXPECTED_START EXPECTED_END EXPECTED_RANGE: checks
# the endpoints, and the possibly-rewritten range, that `set-git-range`
# computes from the whole range RANGE.
check() {
  description="$1"
  range="$2"
  expected="$3 $4 $5"
  actual=""
  if ! actual="$(run "$range")"; then
    echo "FAIL: nonzero exit status for $description"
    status=1
    return
  fi
  if [ "$actual" = "$expected" ]; then
    echo "PASS: $description"
  else
    echo "FAIL: $description"
    echo "  input range:                   $range"
    echo "  expected start, end, and range: $expected"
    echo "  actual start, end, and range:   $actual"
    status=1
  fi
}

check "a three-dot range of dotted tags" "v1.2.3...v1.3.0" v1.2.3 v1.3.0 "v1.2.3...v1.3.0"
# A two-dot range is restated in three-dot form, so that a client that uses
# CI_COMMIT_RANGE sees the same diff as one that uses the two endpoints.
check "a two-dot range of dotted tags" "v1.2.3..v1.3.0" v1.2.3 v1.3.0 "v1.2.3...v1.3.0"
check "a three-dot range of commit ids" "$FIRST...$THIRD" "$FIRST" "$THIRD" "$FIRST...$THIRD"
check "a two-dot range of commit ids" "$FIRST..$THIRD" "$FIRST" "$THIRD" "$FIRST...$THIRD"
# Not a range but a single commit, which is what a client gets if a CI service
# ever supplies one.  The end is that commit and the start is its parent; that
# is the same treatment the script gives a range whose endpoints are equal.
check "a lone dotted tag" "v1.3.0" "$SECOND" v1.3.0 "$SECOND...v1.3.0"

exit "$status"
