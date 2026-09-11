#!/bin/sh

# Tests for `ci-last-success.py`.
# These tests use a stub `requests` module (see `stub/requests.py`) that answers
# from a JSON file, so they need neither network access nor a GitHub API quota.

set -e

SCRIPTDIR="$(cd "$(dirname "$0")" > /dev/null 2>&1 && pwd -P)"
PROGRAM="${SCRIPTDIR}/../../ci-last-success.py"
PYTHONPATH="${SCRIPTDIR}/stub${PYTHONPATH:+:${PYTHONPATH}}"
export PYTHONPATH

ORG=plume-lib
REPO=plume-scripts

# These SHAs do not exist in any repository, so `git rev-parse SHA^` fails and
# `ci-last-success.py` stops rather than walking back through real history.
CHECKRUNS_SUCCESS_SHA=1111111111111111111111111111111111111111
CHECKRUNS_FAILURE_SHA=2222222222222222222222222222222222222222
CHECKRUNS_INCOMPLETE_SHA=3333333333333333333333333333333333333333
STATUS_SUCCESS_SHA=4444444444444444444444444444444444444444
NO_CI_SHA=5555555555555555555555555555555555555555

status=0

# Arguments: responses file, SHA.  The SHA must be reported as successful.
expect_success() {
  STUB_RESPONSES="${SCRIPTDIR}/$1"
  export STUB_RESPONSES
  if ! out="$("${PROGRAM}" "${ORG}" "${REPO}" "$2")"; then
    echo "FAILED $1: exited with a nonzero status, expected \"$2\"" >&2
    status=1
    return
  fi
  if [ "${out}" != "$2" ]; then
    echo "FAILED $1: printed \"${out}\", expected \"$2\"" >&2
    status=1
  fi
}

# Arguments: responses file, SHA.  The SHA must not be reported as successful.
expect_failure() {
  STUB_RESPONSES="${SCRIPTDIR}/$1"
  export STUB_RESPONSES
  if out="$("${PROGRAM}" "${ORG}" "${REPO}" "$2" 2> /dev/null)"; then
    echo "FAILED $1: exited with status 0 and printed \"${out}\", expected failure" >&2
    status=1
  fi
}

# All the check runs succeeded, but the commit has no commit statuses, so its
# combined commit status is "pending".  Consulting only the commit status (as
# this script used to do) reports every such commit as unsuccessful.
expect_success checkruns-success.json "${CHECKRUNS_SUCCESS_SHA}"

# A CI system that reports a commit status rather than check runs, such as Travis CI.
expect_success status-success.json "${STATUS_SUCCESS_SHA}"

expect_failure checkruns-failure.json "${CHECKRUNS_FAILURE_SHA}"
expect_failure checkruns-incomplete.json "${CHECKRUNS_INCOMPLETE_SHA}"
# A commit with no CI job at all is not a commit with a successful CI job.
expect_failure no-ci.json "${NO_CI_SHA}"

if [ "${status}" -eq 0 ]; then
  echo "ci-last-success-test.sh: all tests passed"
fi
exit "${status}"
