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

# A hostile DEFAULT-ORGANIZATION, which exercises the quoting of
# CI_ORGANIZATION as the branch names above exercise the quoting of CI_BRANCH.
# Its `$(...)` and backquotes create ${CANARY} if the client's `eval` expands
# them; a canary is used rather than a comparison of values, because the
# scripts differ in when they use this argument and when they instead compute
# the organization from the clone's origin.  For the same reason, the check
# after the test loop requires that some case did use this argument:  a case
# that did not could not have created the canary no matter how the script
# quotes.  The value has no space in it, because it is passed through
# `env -i ... sh -c`.
CANARY="$work/canary"
# The `$(...)` is single-quoted on purpose:  this shell must not expand it.
# shellcheck disable=SC2016
HOSTILE_ORGANIZATION='org$(touch '"$CANARY"')`touch '"$CANARY"'`;x'

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

# Stubs that make the GitHub API request of the pull request test below fail,
# so that this test does not need the network.  Both tools are stubbed, because
# the scripts use whichever one they find.
mkdir "$work/bin"
for tool in curl wget; do
  printf '#!/bin/sh\nexit 1\n' > "$work/bin/$tool"
  chmod +x "$work/bin/$tool"
done

### The test

status=0

# Set when some case's CI_ORGANIZATION was the hostile argument, which is what
# makes the canary check below able to fail.  See the check after the loop.
organization_was_hostile=""

# report SCRIPT DESCRIPTION EXPECTED ACTUAL_BRANCH ACTUAL_ORGANIZATION: reports
# whether the branch name survived the client's `eval` intact, and whether the
# `eval` executed part of a value.
report() {
  script="$1"
  description="$2"
  expected="$3"
  actual="$4"
  actual_organization="$5"
  ok="true"
  if [ "$actual" != "$expected" ]; then
    echo "FAIL: $script did not quote CI_BRANCH with $description"
    echo "  expected: $expected"
    echo "  actual:   $actual"
    ok=""
  fi
  if [ -e "$CANARY" ]; then
    echo "FAIL: $script did not quote CI_ORGANIZATION with $description"
    echo "  the client's \`eval\` ran a command from the organization's name"
    ok=""
  fi
  if [ "$actual_organization" = "$HOSTILE_ORGANIZATION" ]; then
    organization_was_hostile="true"
  fi
  if [ -n "$ok" ]; then
    echo "PASS: $script with $description"
  else
    status=1
  fi
}

# The two runners below pass the values back in files rather than on standard
# output, because `ci-info` reports a diagnostic by emitting an `echo` command
# for the client to `eval`.  That diagnostic and the values would share standard
# output, and no parsing of the two could be trusted:  a branch name is chosen
# by whoever opened the pull request, so it can look like anything.  The
# `eval`'s standard output is discarded for the same reason:  this test checks
# values, not diagnostics.
#
# check SCRIPT BRANCH: checks out BRANCH, runs SCRIPT the way its
# documentation says to, and checks that the branch name survived the client's
# `eval` intact.
check() {
  script="$1"
  branch="$2"
  git checkout -q "$branch"
  # Remove any canary that a previous check created, so that one script's
  # failure is not reported again for the next script.
  rm -f "$CANARY"
  # Run with an empty environment, so that this test behaves the same whether
  # or not it is itself running under CI.  The CI variables would send the
  # script down a different code path, one that makes a GitHub API request.
  if ! (
    # The inner script is single-quoted on purpose:  its arguments are passed
    # positionally, so that this shell does not expand them into it.
    # shellcheck disable=SC2016
    env -i PATH="$PATH" HOME="$HOME" sh -c '
      cd "$1" || exit 2
      eval "$("$2/$3" "$4" 2> /dev/null)" > /dev/null || exit 2
      printf "%s" "$CI_BRANCH" > "$5/branch"
      printf "%s" "$CI_ORGANIZATION" > "$5/organization"
    ' sh "$work/repo" "$PLUME_SCRIPTS" "$script" "$HOSTILE_ORGANIZATION" "$work"
  ); then
    echo "FAIL: $script: nonzero exit status with branch $branch"
    status=1
    return
  fi
  report "$script" "branch $branch" "$branch" \
    "$(cat "$work/branch")" "$(cat "$work/organization")"
}

# check_pr SCRIPT BRANCH: runs SCRIPT the way its documentation says to, in a
# simulated GitHub Actions pull request whose head branch is BRANCH, and checks
# that the branch name survived the client's `eval` intact.  This is a
# different code path than `check` exercises:  in a pull request the scripts
# take the branch name from GITHUB_HEAD_REF, whose value is chosen by whoever
# opened the pull request.
check_pr() {
  script="$1"
  branch="$2"
  git checkout -q main
  rm -f "$CANARY"
  # Run with an empty environment except for the GitHub Actions variables, so
  # that this test behaves the same whether or not it is itself running under
  # CI.  Another CI service's variables would send the scripts down another
  # code path.
  if ! (
    # The inner script is single-quoted on purpose:  its arguments are passed
    # positionally, so that this shell does not expand them into it.
    # shellcheck disable=SC2016
    env -i PATH="$work/bin:$PATH" HOME="$HOME" \
      GITHUB_ACTIONS=true GITHUB_EVENT_NAME=pull_request \
      GITHUB_HEAD_REF="$branch" GITHUB_BASE_REF=main \
      GITHUB_REF_NAME=42/merge GITHUB_REPOSITORY=testorg/testrepo \
      GITHUB_SHA="$(git rev-parse HEAD)" \
      sh -c '
        cd "$1" || exit 2
        eval "$("$2/$3" "$4" 2> /dev/null)" > /dev/null || exit 2
        printf "%s" "$CI_BRANCH" > "$5/branch"
        printf "%s" "$CI_ORGANIZATION" > "$5/organization"
      ' sh "$work/repo" "$PLUME_SCRIPTS" "$script" "$HOSTILE_ORGANIZATION" "$work"
  ); then
    echo "FAIL: $script: nonzero exit status with pull request branch $branch"
    status=1
    return
  fi
  report "$script" "pull request branch $branch" "$branch" \
    "$(cat "$work/branch")" "$(cat "$work/organization")"
}

for script in ci-info ci-org-and-branch git-changes; do
  check "$script" "$BRANCH_METACHARACTERS"
  check "$script" "$BRANCH_APOSTROPHE"
  check_pr "$script" "$BRANCH_METACHARACTERS"
  check_pr "$script" "$BRANCH_APOSTROPHE"
done

# The canary check in `report` can only fail if the hostile argument reaches
# CI_ORGANIZATION in the first place.  Whether it does depends on the scripts:
# each one uses the argument only when it cannot determine the organization
# from the clone or from the CI service.  If it never reaches CI_ORGANIZATION,
# every canary check above is vacuous -- it passes no matter how the scripts
# quote, which is a silently disabled assertion rather than a passing test.
# So require that at least one case did use the argument.  This also catches a
# script that ignores its DEFAULT-ORGANIZATION argument altogether.
if [ -z "$organization_was_hostile" ]; then
  echo "FAIL: no case set CI_ORGANIZATION to the DEFAULT-ORGANIZATION argument,"
  echo "  so the CI_ORGANIZATION quoting checks above could not have failed."
  status=1
fi

exit "$status"
