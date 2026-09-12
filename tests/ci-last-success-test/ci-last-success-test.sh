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
CHECKRUNS_SKIPPED_SHA=6666666666666666666666666666666666666666
STATUS_FAILURE_SHA=7777777777777777777777777777777777777777
STATUS_FAILURE_CHECKRUNS_SUCCESS_SHA=8888888888888888888888888888888888888888
CHECKRUNS_PAGINATED_FAILURE_SHA=9999999999999999999999999999999999999999

status=0

tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' 0
STDERR="${tmpdir}/stderr"

# Arguments: responses file, SHA.  The SHA must be reported as successful.
expect_success() {
  STUB_RESPONSES="$1"
  export STUB_RESPONSES
  if ! out="$("${PROGRAM}" "${ORG}" "${REPO}" "$2")"; then
    echo "FAILED $(basename "$1"): exited with a nonzero status, expected \"$2\"" >&2
    status=1
    return
  fi
  if [ "${out}" != "$2" ]; then
    echo "FAILED $(basename "$1"): printed \"${out}\", expected \"$2\"" >&2
    status=1
  fi
}

# Arguments: responses file, SHA.  The SHA must not be reported as successful.
# Checks the exit status and the diagnostic, so that the test does not pass
# vacuously when the script crashes (which also yields a nonzero exit status).
expect_failure() {
  STUB_RESPONSES="$1"
  export STUB_RESPONSES
  out="$("${PROGRAM}" "${ORG}" "${REPO}" "$2" 2> "${STDERR}")" && exit_status=0 || exit_status=$?
  if [ "${exit_status}" -ne 1 ]; then
    echo "FAILED $(basename "$1"): exited with status ${exit_status}, expected 1" >&2
    sed 's/^/  /' "${STDERR}" >&2
    status=1
    return
  fi
  if [ -n "${out}" ]; then
    echo "FAILED $(basename "$1"): printed \"${out}\", expected no standard output" >&2
    status=1
  fi
  if ! grep -q "No successful CI job found at or before $2" "${STDERR}"; then
    echo "FAILED $(basename "$1"): standard error does not report \"No successful CI job found at or before $2\":" >&2
    sed 's/^/  /' "${STDERR}" >&2
    status=1
  fi
}

# Writes, to standard output, a responses file for a commit whose check runs do
# not fit on one page and whose last check run failed.  Reading only the first
# page of check runs would wrongly report the commit as successful.  This fixture
# is generated rather than stored because it contains 101 check runs.
paginated_failure_fixture() {
  prefix="https://api.github.com/repos/${ORG}/${REPO}/commits/${CHECKRUNS_PAGINATED_FAILURE_SHA}"
  printf '{\n'
  printf '  "%s/status": { "state": "pending", "statuses": [] },\n' "${prefix}"
  printf '  "%s/check-runs?per_page=100&page=1": {\n' "${prefix}"
  printf '    "total_count": 101,\n    "check_runs": [\n'
  i=1
  while [ "${i}" -le 100 ]; do
    if [ "${i}" -lt 100 ]; then comma=","; else comma=""; fi
    printf '      { "name": "job%d", "status": "completed", "conclusion": "success" }%s\n' "${i}" "${comma}"
    i=$((i + 1))
  done
  printf '    ]\n  },\n'
  printf '  "%s/check-runs?per_page=100&page=2": {\n' "${prefix}"
  printf '    "total_count": 101,\n    "check_runs": [\n'
  printf '      { "name": "job101", "status": "completed", "conclusion": "failure" }\n'
  printf '    ]\n  }\n'
  printf '}\n'
}

# All the check runs succeeded, but the commit has no commit statuses, so its
# combined commit status is "pending".  Consulting only the commit status (as
# this script used to do) reports every such commit as unsuccessful.
expect_success "${SCRIPTDIR}/checkruns-success.json" "${CHECKRUNS_SUCCESS_SHA}"

# A CI system that reports a commit status rather than check runs, such as Travis CI.
expect_success "${SCRIPTDIR}/status-success.json" "${STATUS_SUCCESS_SHA}"

expect_failure "${SCRIPTDIR}/checkruns-failure.json" "${CHECKRUNS_FAILURE_SHA}"
expect_failure "${SCRIPTDIR}/checkruns-incomplete.json" "${CHECKRUNS_INCOMPLETE_SHA}"
# A commit with no CI job at all is not a commit with a successful CI job.
expect_failure "${SCRIPTDIR}/no-ci.json" "${NO_CI_SHA}"
# Check runs that were all skipped or advisory mean that no CI job actually ran
# (job-level `if:` conditions and path filters produce such check runs), so the
# commit does not have a successful CI job either.
expect_failure "${SCRIPTDIR}/checkruns-skipped.json" "${CHECKRUNS_SKIPPED_SHA}"
# A failing commit status, as Travis CI reports it.
expect_failure "${SCRIPTDIR}/status-failure.json" "${STATUS_FAILURE_SHA}"
# A failing commit status is a failure even when every check run succeeded.
expect_failure "${SCRIPTDIR}/status-failure-checkruns-success.json" \
  "${STATUS_FAILURE_CHECKRUNS_SUCCESS_SHA}"
# A check run that failed on the second page of check runs is still a failure.
paginated_failure_fixture > "${tmpdir}/checkruns-paginated-failure.json"
expect_failure "${tmpdir}/checkruns-paginated-failure.json" "${CHECKRUNS_PAGINATED_FAILURE_SHA}"

if [ "${status}" -eq 0 ]; then
  echo "ci-last-success-test.sh: all tests passed"
fi
exit "${status}"
