#!/bin/sh

# Tests that the scripts do not mistake a GitHub API error response for an
# answer.
#
# A GitHub API request can fail -- the pull request does not exist, the
# request was throttled, the token expired -- and the response is then a JSON
# object that lacks the requested field.  `jq` prints the string "null" for a
# missing field, so a script that does not ask for "// empty" sets
# CI_ORGANIZATION or CI_BRANCH to the string "null" and reports success.  The
# client then acts on "null" as if it were an organization or a branch name.
#
# Each script must instead treat the missing field as missing:  either fall
# back to a value it can determine locally, or fail.

set -eu

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)"
PLUME_SCRIPTS="$(CDPATH='' cd -- "${SCRIPT_DIR}/../.." && pwd -P)"

# The scripts need this, and skipping is better than failing:  a missing
# prerequisite is not a defect in the scripts.
if [ -z "$(command -v jq 2> /dev/null)" ]; then
  echo "$(basename -- "$0"): skipping, because jq is not installed."
  exit 0
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT HUP INT TERM

### A curl and a wget that answer every request the way GitHub answers a
### request for a pull request that does not exist.  They make this test
### independent of the network, and they let it provoke the error response
### without needing a repository that produces one.

mkdir "$work/bin"
cat > "$work/bin/curl" << 'EOF'
#!/bin/sh
printf '%s\n' '{"message":"Not Found","documentation_url":"https://docs.github.com/rest","status":"404"}'
EOF
cp "$work/bin/curl" "$work/bin/wget"
chmod +x "$work/bin/curl" "$work/bin/wget"

### A repository, with a local origin so that this test does not need the
### network.

git init -q -b main "$work/repo"
cd "$work/repo"
git config user.email test@example.com
git config user.name "Test User"
echo one > file.txt
git add file.txt
git commit -q -m "First commit"
echo two >> file.txt
git commit -q -a -m "Second commit"
git clone -q --bare . "$work/origin.git"
git remote add origin "$work/origin.git"
git fetch -q origin
git remote set-head origin main

### A GitHub Actions event payload for a pull request from a fork.  GitHub
### writes this file itself, so it is available even when the API request that
### asks the same question fails.  The organization in it differs from this
### clone's, so a script that falls back to the clone rather than to this file
### gives a visibly different answer.

cat > "$work/event.json" << 'EOF'
{
  "pull_request": {
    "head": {
      "sha": "0000000000000000000000000000000000000000",
      "ref": "feature",
      "repo": { "owner": { "login": "forkorg" } }
    }
  }
}
EOF

### The test

status=0

# check SCRIPT DESCRIPTION EXPECTED_ORGANIZATION EXPECTED_BRANCH VAR=VALUE...:
# runs SCRIPT the way its documentation says to, in a CI environment described
# by the VAR=VALUE arguments and with the fake curl and wget above, and checks
# that CI_ORGANIZATION and CI_BRANCH are the expected values.  An expected
# value of "-" means only that the value must not be the string "null"; it is
# for a value that this test cannot predict.
#
# SCRIPT must exit with status 0.  Accepting a nonzero status as evidence that
# the script detected the error response would make this check unfalsifiable:
# a script that fails for an unrelated reason -- or that stops reaching the
# `jq` call at all -- would report a pass while testing nothing.
#
# The values come back in a file rather than on standard output, because
# `ci-info` reports a diagnostic by emitting an `echo` command for the client
# to `eval`, which shares standard output with anything the values are printed
# on.
check() {
  script="$1"
  description="$2"
  expected_organization="$3"
  expected_branch="$4"
  shift 4
  # A script that fails before writing the file must not be judged on the
  # previous script's values.
  rm -f "$work/values"
  # Run with an empty environment, so that this test behaves the same whether
  # or not it is itself running under CI:  a CI variable of this test's own
  # would send the script down a different code path.
  if ! (
    # The inner script is single-quoted on purpose:  its arguments are passed
    # positionally, so that this shell does not expand them into it.
    # shellcheck disable=SC2016
    env -i PATH="$work/bin:$PATH" HOME="$HOME" "$@" sh -c '
      cd "$1" || exit 2
      eval "$("$2/$3" testorg 2> /dev/null)" > /dev/null 2>&1 || exit 2
      printf "%s\n%s\n" "$CI_ORGANIZATION" "$CI_BRANCH" > "$4/values"
    ' sh "$work/repo" "$PLUME_SCRIPTS" "$script" "$work"
  ); then
    echo "FAIL: $script under $description exited with a nonzero status"
    status=1
    return
  fi
  actual_organization="$(sed -n 1p "$work/values")"
  actual_branch="$(sed -n 2p "$work/values")"
  report "$script" "$description" CI_ORGANIZATION \
    "$expected_organization" "$actual_organization"
  report "$script" "$description" CI_BRANCH \
    "$expected_branch" "$actual_branch"
}

# report SCRIPT DESCRIPTION VARIABLE EXPECTED ACTUAL: reports whether ACTUAL is
# what EXPECTED calls for.  See `check` for the meaning of "-".
report() {
  script="$1"
  description="$2"
  variable="$3"
  expected="$4"
  actual="$5"
  if [ "$expected" = "-" ]; then
    if [ "$actual" = "null" ]; then
      echo "FAIL: $script under $description used a jq \"null\" as $variable"
      status=1
    else
      echo "PASS: $script under $description: $variable is not \"null\""
    fi
  elif [ "$actual" != "$expected" ]; then
    echo "FAIL: $script under $description set $variable to the wrong value"
    echo "  expected: $expected"
    echo "  actual:   $actual"
    status=1
  else
    echo "PASS: $script under $description: $variable is $actual"
  fi
}

# The environments below include everything that the scripts need in order to
# succeed once they have handled the error response.  Without GITHUB_SHA and
# GITHUB_BASE_REF, for example, `git-changes` fails before it ever asks the
# question this test is about.  GITHUB_EVENT_PATH is deliberately absent from
# these two cases, so that the scripts cannot fall back to the event payload
# and must fall back to the clone -- and, because this clone's origin is a
# local path rather than a GitHub URL, on to the DEFAULT-ORGANIZATION argument.
# That is why "testorg" is the expected organization:  it is the argument, and
# the string "null" would be the answer of a script that had this bug.  The
# case after them supplies GITHUB_EVENT_PATH.
#
# `ci-info` is obsolete.  It derives the organization from the leading
# components of the origin URL without checking that the URL names GitHub, so
# for this test's local origin it yields a fragment of a path rather than
# falling back to the argument.  This test asks only that the value not be
# "null", which is the bug it is about.
for script in ci-org-and-branch git-changes; do
  check "$script" "GitHub Actions" testorg feature \
    GITHUB_ACTIONS=true GITHUB_EVENT_NAME=pull_request \
    GITHUB_HEAD_REF=feature GITHUB_BASE_REF=main \
    GITHUB_REF_NAME=42/merge GITHUB_REPOSITORY=testorg/testrepo \
    GITHUB_SHA="$(git rev-parse HEAD)"
  check "$script" "Azure Pipelines" testorg main \
    AZURE_HTTP_USER_AGENT=VSTS_00000000-0000-0000-0000-000000000000 \
    BUILD_REASON=PullRequest BUILD_REPOSITORY_NAME=testorg/testrepo \
    SYSTEM_PULLREQUEST_PULLREQUESTNUMBER=42
done

# With the event payload available, the answer must come from it rather than
# from the clone:  for a pull request from a fork, the clone's origin is the
# base repository, and a client that clones a companion repository from the
# wrong organization has no way to notice.
for script in ci-org-and-branch git-changes ci-info; do
  check "$script" "GitHub Actions with an event payload" forkorg feature \
    GITHUB_ACTIONS=true GITHUB_EVENT_NAME=pull_request \
    GITHUB_HEAD_REF=feature GITHUB_BASE_REF=main \
    GITHUB_REF_NAME=42/merge GITHUB_REPOSITORY=testorg/testrepo \
    GITHUB_SHA="$(git rev-parse HEAD)" \
    GITHUB_EVENT_PATH="$work/event.json"
done

check ci-info "GitHub Actions" - feature \
  GITHUB_ACTIONS=true GITHUB_EVENT_NAME=pull_request \
  GITHUB_HEAD_REF=feature GITHUB_BASE_REF=main \
  GITHUB_REF_NAME=42/merge GITHUB_REPOSITORY=testorg/testrepo \
  GITHUB_SHA="$(git rev-parse HEAD)"
# `ci-info`'s Azure arm reports the bad response and gives up rather than
# falling back, so it sets neither variable.  Its `exit 2` does not reach the
# client, because the client's `eval` reports the status of the text it
# evaluated rather than the script's; that is one of the reasons `ci-info` is
# obsolete, and it is why the expected status here is still 0.
check ci-info "Azure Pipelines" "" "" \
  AZURE_HTTP_USER_AGENT=VSTS_00000000-0000-0000-0000-000000000000 \
  BUILD_REASON=PullRequest BUILD_REPOSITORY_NAME=testorg/testrepo \
  SYSTEM_PULLREQUEST_PULLREQUESTNUMBER=42

exit "$status"
