#!/bin/sh

# Tests that `ci-info` computes the start of the commit range from the default
# branch as it is in origin, not from a stale "origin/master" in the clone.
# CircleCI's checkout step leaves "origin/master" stale when it restores a clone
# from its cache, because it then fetches only the branch being built.  A stale
# start makes the range include commits of the default branch that the branch
# being built merged in, so linters that examine only the range blame it for
# those commits.

# Halt on error.
set -e

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)"
CI_INFO="${SCRIPT_DIR}/../../ci-info"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT HUP INT TERM

git init -q --bare --initial-branch=master "$tmpdir/origin.git"

# A clone in which to make commits and push them to origin.
git clone -q "$tmpdir/origin.git" "$tmpdir/dev" 2> /dev/null
cd "$tmpdir/dev"
git config user.email "ci-info-test@example.com"
git config user.name "ci-info test"
git switch -q -c master
echo one > file.txt
git add file.txt
git commit -q -m "First commit on master"
git push -q origin master

# The clone that CI tests.  It records "origin/master" now, and never again.
git clone -q "$tmpdir/origin.git" "$tmpdir/ci"
stale_master=$(git -C "$tmpdir/ci" rev-parse origin/master)

# The default branch advances, and a feature branch starts from it.
echo two > file.txt
git commit -q -a -m "Second commit on master"
git push -q origin master
fork_point=$(git rev-parse HEAD)
git switch -q -c feature
echo three > other.txt
git add other.txt
git commit -q -m "Commit on feature"
git push -q origin feature

# As CircleCI does with a clone restored from its cache, fetch only the branch
# being built.
cd "$tmpdir/ci"
git fetch -q origin "+refs/heads/feature:refs/remotes/origin/feature"
git switch -q -c feature origin/feature

# `env -i`, because the ambient environment might indicate a different CI
# platform.
range_start=$(env -i \
  PATH="$PATH" \
  HOME="$tmpdir" \
  CIRCLECI=true \
  CIRCLE_BRANCH=feature \
  CIRCLE_SHA1="$(git rev-parse HEAD)" \
  sh "$CI_INFO" an-organization 2> "$tmpdir/err.txt" \
  | sed -n "s/^CI_COMMIT_RANGE_START='\([0-9a-f]*\)'.*/\1/p")

if [ "$range_start" = "$fork_point" ]; then
  echo "test-stale-default-branch.sh: passed."
  exit 0
fi
echo "test-stale-default-branch.sh: FAILED: CI_COMMIT_RANGE_START is ${range_start:-empty}, expected the fork point ${fork_point}." >&2
if [ "$range_start" = "$stale_master" ]; then
  echo "test-stale-default-branch.sh: That is the stale origin/master." >&2
fi
cat "$tmpdir/err.txt" >&2
exit 1
