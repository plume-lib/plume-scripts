#!/bin/sh

# Tests that a script that cannot find a file it needs makes the client fail,
# rather than silently succeeding with no values.
#
# `ci-org-and-branch` and `git-changes` source `eval-wrapper.sh`, which in turn
# sources a "set-" script.  `.` on a file that does not exist is an error in a
# special builtin:  the shell aborts at once, so the script writes nothing on
# standard output and the client's `eval` evaluates the empty string, which
# succeeds.  The client would then go on with a stale or unset CI_ORGANIZATION
# -- cloning a companion repository from the wrong organization, say -- with
# nothing to warn it.
#
# A client that copies individual scripts rather than cloning this repository
# can easily be missing one of them, and `eval-wrapper.sh` is new.

set -eu

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)"
PLUME_SCRIPTS="$(CDPATH='' cd -- "${SCRIPT_DIR}/../.." && pwd -P)"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT HUP INT TERM

status=0
case_number=0

# check DESCRIPTION EXPECTED_STATUS SCRIPT FILE...: copies SCRIPT and each FILE
# into a directory of their own, runs SCRIPT there the way a client does, and
# checks that the client's `eval` of its output exits with EXPECTED_STATUS.
# Whichever files SCRIPT needs are not listed among the FILEs are missing, and
# that is what each case is about.
#
# The status is the client's rather than SCRIPT's, because that is the one the
# client acts on:  the `eval` reports the status of the text it evaluated, so
# the only way for SCRIPT to fail the client is to write an `exit` command.
check() {
  description="$1"
  expected_status="$2"
  script="$3"
  shift 3
  case_number=$((case_number + 1))
  dir="$work/$case_number"
  mkdir "$dir"
  cp "$PLUME_SCRIPTS/$script" "$dir"
  for file in "$@"; do
    cp "$PLUME_SCRIPTS/$file" "$dir"
  done
  actual_status=0
  # Run with an empty environment, so that this test behaves the same whether
  # or not it is itself running under CI:  a CI variable of this test's own
  # would send the script down a different code path.  The working directory is
  # this repository, which is a git clone, so that the script can determine the
  # organization once it can read the files it needs.
  # The inner script is single-quoted on purpose:  its arguments are passed
  # positionally, so that this shell does not expand them into it.
  # shellcheck disable=SC2016
  env -i PATH="$PATH" HOME="$HOME" sh -c '
    cd "$1" || exit 125
    eval "$("$2/$3" testorg 2> /dev/null)" > /dev/null 2>&1
  ' sh "$PLUME_SCRIPTS" "$dir" "$script" || actual_status=$?
  if [ "$actual_status" -ne "$expected_status" ]; then
    echo "FAIL: $description: the client's eval exited with status $actual_status"
    echo "  expected: $expected_status"
    status=1
  else
    echo "PASS: $description: the client's eval exits with status $actual_status"
  fi
}

# With every file present the client's `eval` must succeed.  Without this case
# the others would be unfalsifiable:  a script that failed for some unrelated
# reason, or that was not run at all, would report a pass while testing
# nothing.
check "ci-org-and-branch with every file it needs" 0 \
  ci-org-and-branch eval-wrapper.sh set-ci-org-and-branch
check "git-changes with every file it needs" 0 \
  git-changes eval-wrapper.sh set-git-range set-ci-org-and-branch

check "ci-org-and-branch without eval-wrapper.sh" 2 \
  ci-org-and-branch set-ci-org-and-branch
check "git-changes without eval-wrapper.sh" 2 \
  git-changes set-git-range set-ci-org-and-branch

check "ci-org-and-branch without set-ci-org-and-branch" 2 \
  ci-org-and-branch eval-wrapper.sh
check "git-changes without set-git-range" 2 \
  git-changes eval-wrapper.sh set-ci-org-and-branch

exit "$status"
