#!/bin/sh

# Tests `is-ci.sh`:  it prints "yes" if any of a list of CI-specific
# environment variables is set and non-empty, and prints nothing otherwise.
#
# Each case runs under `env -i` so that the environment of whatever CI system
# is running this test suite does not determine the answer.

set -eu

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)"
IS_CI="$(CDPATH='' cd -- "${SCRIPT_DIR}/../.." && pwd -P)/is-ci.sh"

status=0

# Every environment variable that `is-ci.sh` tests.
CI_VARIABLES="CI APPVEYOR AZURE_HTTP_USER_AGENT TF_BUILD CIRCLECI \
  GITHUB_ACTIONS GITLAB_CI TRAVIS JENKINS_URL BUILDKITE TEAMCITY_VERSION \
  DRONE DRONE_BUILD_NUMBER BITBUCKET_BUILD_NUMBER"

# check_equal DESCRIPTION EXPECTED ACTUAL: reports whether two strings match.
check_equal() {
  if [ "$2" = "$3" ]; then
    echo "PASS: $1"
  else
    echo "FAIL: $1"
    echo "  expected: <<$2>>"
    echo "  actual:   <<$3>>"
    status=1
  fi
}

# Each recognized variable, on its own, means "we are under CI".
for var in $CI_VARIABLES; do
  check_equal "$var is recognized" "yes" "$(env -i "PATH=$PATH" "$var=true" "$IS_CI")"
done

# With none of them set, the output is empty.
check_equal "no CI variables" "" "$(env -i "PATH=$PATH" "$IS_CI")"

# An unrelated variable does not make it look like CI.
check_equal "an unrelated variable" "" "$(env -i "PATH=$PATH" NOT_A_CI_VARIABLE=true "$IS_CI")"

# A variable that is set but empty does not count; CI systems that do not
# apply set some of these to the empty string.
check_equal "an empty CI variable" "" "$(env -i "PATH=$PATH" CI= "$IS_CI")"

# The exit status is 0 either way, so that callers can use the output.
actual_status=0
env -i "PATH=$PATH" "$IS_CI" > /dev/null || actual_status=$?
check_equal "exits 0 when not under CI" "0" "$actual_status"
actual_status=0
env -i "PATH=$PATH" CI=true "$IS_CI" > /dev/null || actual_status=$?
check_equal "exits 0 when under CI" "0" "$actual_status"

exit "$status"
