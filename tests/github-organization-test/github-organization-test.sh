#!/bin/sh

# Tests that the scripts determine CI_ORGANIZATION from GITHUB_REPOSITORY in a
# GitHub Actions job that is not a pull request.
#
# The scripts had no GitHub Actions non-pull-request case for the
# organization, only for the branch, so the organization came from the
# fallback that reads the origin of the current directory.  That is the wrong
# answer for the client this information exists to serve:  `git-clone-related`
# clones a companion repository from ${CI_ORGANIZATION}, and a client may call
# it from a sibling clone of a different repository -- as the Checker
# Framework's `test-daikon-part1.sh` does, cloning Daikon while the current
# directory is the checker-framework clone.  The organization was then the one
# in that clone's origin, so a fork's push build silently tested against the
# upstream companion repository instead of the fork's.
#
# The pull request case is not tested here, because determining its
# organization requires a GitHub API request.

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

### A clone of some *other* repository, in some other organization
#
# This stands in for the sibling clone that a client calls the scripts from.
# Its origin URL names otherorg, so that reading the origin of the current
# directory gives a different answer than GITHUB_REPOSITORY does.  An
# `insteadOf` rewrite points the URL at a local repository, so that the
# scripts' `git ls-remote origin` needs no network.

git init -q -b main "$work/sibling"
cd "$work/sibling"
git config user.email test@example.com
git config user.name "Test User"
echo one > file.txt
git add file.txt
git commit -q -m "First commit"
git clone -q --bare . "$work/origin.git"
git config url."$work/origin.git".insteadOf "https://github.com/otherorg/otherrepo.git"
git remote add origin "https://github.com/otherorg/otherrepo.git"
git fetch -q origin
git remote set-head origin main

### The test

status=0

# run_raw SCRIPT REPOSITORY: runs SCRIPT the way its documentation says to, in
# a simulated GitHub Actions push job whose current directory is the sibling
# clone and whose $GITHUB_REPOSITORY is REPOSITORY.  Prints the resulting
# CI_ORGANIZATION and CI_BRANCH to standard output, and whatever the script
# reported to standard error.
run_raw() {
  script="$1"
  repository="$2"
  # Run with an empty environment except for the GitHub Actions variables, so
  # that this test behaves the same whether or not it is itself running under
  # CI.  Other CI services' variables would send the scripts down other code
  # paths.  GITHUB_HEAD_REF is unset, which is what makes this not a pull
  # request.  CI_DEFAULT_ORGANIZATION is a third name, distinct from both
  # testorg and otherorg, so that this test can tell the intended answer from
  # each of the two fallbacks.
  # The inner script is single-quoted on purpose:  its arguments are passed
  # positionally, so that this shell does not expand them into it.
  # shellcheck disable=SC2016
  env -i PATH="$PATH" HOME="$HOME" \
    GITHUB_ACTIONS=true GITHUB_EVENT_NAME=push \
    GITHUB_REF_NAME=feature-branch GITHUB_REPOSITORY="$repository" \
    sh -c '
      cd "$1" || exit 2
      if [ "$3" = "set-ci-org-and-branch" ]; then
        CI_DEFAULT_ORGANIZATION=defaultorg
        . "$2/$3" || exit 2
      else
        # The output that a client `eval`s may contain `echo` commands,
        # because ci-info has no other way to report anything.  Send what
        # they print to standard error, like the other two scripts, so that
        # standard output holds only the variables.
        eval "$("$2/$3" defaultorg)" >&2 || exit 2
      fi
      printf "%s %s" "$CI_ORGANIZATION" "$CI_BRANCH"
    ' sh "$work/sibling" "$PLUME_SCRIPTS" "$script"
}

# run SCRIPT REPOSITORY: prints the CI_ORGANIZATION and CI_BRANCH that SCRIPT
# computes.
run() {
  run_raw "$1" "$2" 2> /dev/null
}

# messages SCRIPT REPOSITORY: prints what SCRIPT reported, along with the
# variables.
messages() {
  run_raw "$1" "$2" 2>&1
}

for script in ci-info ci-org-and-branch set-ci-org-and-branch; do
  actual=""
  if ! actual="$(run "$script" testorg/testrepo)"; then
    echo "FAIL: $script: nonzero exit status"
    status=1
    continue
  fi
  # CI_BRANCH is checked too, so that a change to the organization does not
  # quietly break the branch in the same code path.
  if [ "$actual" = "testorg feature-branch" ]; then
    echo "PASS: $script in a sibling clone of another organization's repository"
  else
    echo "FAIL: $script in a sibling clone of another organization's repository"
    echo "  GITHUB_REPOSITORY: testorg/testrepo"
    echo "  origin of the current directory: https://github.com/otherorg/otherrepo.git"
    echo "  expected CI_ORGANIZATION and CI_BRANCH: testorg feature-branch"
    echo "  actual CI_ORGANIZATION and CI_BRANCH:   $actual"
    status=1
  fi
done

# A job that runs in a sibling clone of another organization's repository gets
# its companion clones from an organization that appears nowhere else in its
# log, so the scripts say which organization they chose and which they did not.
for script in ci-info ci-org-and-branch set-ci-org-and-branch; do
  if messages "$script" testorg/testrepo | grep -q 'not otherorg from the origin of this clone'; then
    echo "PASS: $script reports preferring GITHUB_REPOSITORY to this clone's origin"
  else
    echo "FAIL: $script does not report preferring GITHUB_REPOSITORY to this clone's origin"
    status=1
  fi
done

# An ordinary job -- one whose $GITHUB_REPOSITORY names the repository that this
# clone's origin names -- has nothing to disagree with, so it says nothing.
# "OtherOrg" is the same owner as "otherorg":  GitHub owner names are
# case-insensitive, so a difference in case is not a disagreement.
for repository in otherorg/otherrepo OtherOrg/otherrepo; do
  for script in ci-info ci-org-and-branch set-ci-org-and-branch; do
    if messages "$script" "$repository" | grep -q 'from the origin of this clone'; then
      echo "FAIL: $script reports a disagreement for GITHUB_REPOSITORY=$repository"
      echo "  origin of the current directory: https://github.com/otherorg/otherrepo.git"
      status=1
    else
      echo "PASS: $script is silent for GITHUB_REPOSITORY=$repository"
    fi
  done
done

# A runner, a container, or a tool such as `act` may set $GITHUB_ACTIONS and not
# $GITHUB_REPOSITORY.  There is then no organization in the environment to
# prefer, so the scripts use this clone's origin -- rather than an empty
# organization, or a claim not to be using the organization they then use.
for script in ci-info ci-org-and-branch set-ci-org-and-branch; do
  actual=""
  if ! actual="$(run "$script" "")"; then
    echo "FAIL: $script: nonzero exit status with GITHUB_REPOSITORY unset"
    status=1
    continue
  fi
  reported="$(messages "$script" "")"
  if [ "$actual" = "otherorg feature-branch" ] \
    && ! printf '%s\n' "$reported" | grep -q 'from the origin of this clone'; then
    echo "PASS: $script uses this clone's origin with GITHUB_REPOSITORY unset"
  else
    echo "FAIL: $script with GITHUB_REPOSITORY unset"
    echo "  expected CI_ORGANIZATION and CI_BRANCH: otherorg feature-branch"
    echo "  actual CI_ORGANIZATION and CI_BRANCH:   $actual"
    echo "  reported: $reported"
    status=1
  fi
done

exit "$status"
