#!/bin/sh

# Tests that the scripts determine CI_BRANCH from GITHUB_REF_NAME in a GitHub
# Actions job that is not a pull request.
#
# GITHUB_REF_NAME is the name of the branch or tag being built, except in a
# pull request, where it is like "40/merge" and names no branch.  The scripts
# used to tell the two cases apart by asking `git branch --list` whether the
# name is a local branch.  That question has the wrong answer for a job that
# checked out a detached HEAD or a different `ref`, and for a tag; the scripts
# then requested
# `https://api.github.com/repos/OWNER/REPO/pulls/<branch or tag name>`, which
# 404s, and CI_BRANCH ended up empty.  The failure is silent:  the scripts exit
# 0, and `set-git-range` goes on to compute a commit range from the empty
# branch name.
#
# The pull request case, GITHUB_REF_NAME="40/merge", is not tested here,
# because determining its branch requires a GitHub API request.

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

### A repository that looks like a GitHub Actions checkout

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
git tag v1.0
# Branches that exist on origin but not in this clone, as when a workflow
# checks out something other than the branch that triggered it.
git -C "$work/origin.git" branch feature-branch main
git -C "$work/origin.git" branch release/merge main
# Detach HEAD, as `actions/checkout` does when given an explicit `ref`.
git checkout -q --detach main
SHA="$(git rev-parse HEAD)"

### The test

status=0

# run SCRIPT REF-NAME: runs SCRIPT the way its documentation says to, in a
# simulated GitHub Actions job that is not a pull request, and prints the
# resulting CI_BRANCH.
run() {
  script="$1"
  ref_name="$2"
  # Run with an empty environment except for the GitHub Actions variables, so
  # that this test behaves the same whether or not it is itself running under
  # CI.  Other CI services' variables would send the scripts down other code
  # paths.  GITHUB_HEAD_REF is unset, which is what makes this not a pull
  # request.
  # The inner script is single-quoted on purpose:  its arguments are passed
  # positionally, so that this shell does not expand them into it.
  # shellcheck disable=SC2016
  env -i PATH="$PATH" HOME="$HOME" \
    GITHUB_ACTIONS=true GITHUB_EVENT_NAME=push \
    GITHUB_REF_NAME="$ref_name" GITHUB_REPOSITORY=testorg/testrepo \
    GITHUB_SHA="$SHA" \
    sh -c '
      cd "$1" || exit 2
      if [ "$3" = "set-ci-org-and-branch" ]; then
        CI_DEFAULT_ORGANIZATION=testorg
        . "$2/$3" || exit 2
      else
        eval "$("$2/$3" testorg)" || exit 2
      fi
      printf "%s" "$CI_BRANCH"
    ' sh "$work/repo" "$PLUME_SCRIPTS" "$script" 2> /dev/null
}

# check DESCRIPTION REF-NAME EXPECTED: checks that every script sets CI_BRANCH
# to EXPECTED when GITHUB_REF_NAME is REF-NAME.
check() {
  description="$1"
  ref_name="$2"
  expected="$3"
  for script in ci-info ci-org-and-branch set-ci-org-and-branch; do
    actual=""
    if ! actual="$(run "$script" "$ref_name")"; then
      echo "FAIL: $script: nonzero exit status for $description"
      status=1
      continue
    fi
    if [ "$actual" = "$expected" ]; then
      echo "PASS: $script with $description"
    else
      echo "FAIL: $script with $description"
      echo "  GITHUB_REF_NAME: $ref_name"
      echo "  expected CI_BRANCH: $expected"
      echo "  actual CI_BRANCH:   $actual"
      status=1
    fi
  done
}

check "a tag push" v1.0 v1.0
check "a branch that is not checked out" feature-branch feature-branch
check "a branch whose name ends in /merge" release/merge release/merge
check "a branch that is checked out" main main

exit "$status"
