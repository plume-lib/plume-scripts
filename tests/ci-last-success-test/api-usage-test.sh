#!/bin/sh

# Tests that `ci-last-success.py` bounds its use of the GitHub API:  it
# examines at most --max-commits commits, it authenticates when GITHUB_PAT or
# GH_TOKEN is set, and it retries a transient failure rather than either
# retrying forever or giving up immediately.
#
# The tests use a fake `requests` module (in ./fake-modules), so they make no
# network requests.

# Halt on error.
set -e

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)"
PROGRAM="${SCRIPT_DIR}/../../ci-last-success.py"

if [ -z "$(command -v python3 2> /dev/null)" ]; then
  echo "api-usage-test.sh: skipping, because python3 is not installed." >&2
  exit 0
fi

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT HUP INT TERM

# The default of --max-commits.  The repository has more commits than this, so
# that the default cap is what stops the search.
default_max_commits=100
repo_commits=105

git init -q "$tmpdir/repo"
cd "$tmpdir/repo"
git config user.email "ci-last-success-test@example.com"
git config user.name "ci-last-success test"
i=1
while [ "$i" -le "$repo_commits" ]; do
  git commit -q --allow-empty -m "Commit $i"
  i=$((i + 1))
done
head_sha="$(git rev-parse HEAD)"

status=0

# run_program RESPONSES TOKEN_VARIABLE_ASSIGNMENT ARG...:  run `ci-last-success.py`
# with the given canned responses and command-line arguments.  Its standard
# output, standard error, and exit status are left in $tmpdir, as is the log of
# the requests that it made.
# `env -i`, because the ambient environment might contain a real credential.
run_program() {
  responses="$1"
  token_assignment="$2"
  shift 2
  : > "$tmpdir/log.txt"
  program_status=0
  env -i \
    PATH="$PATH" \
    HOME="$tmpdir" \
    PYTHONPATH="${SCRIPT_DIR}/fake-modules" \
    FAKE_REQUESTS_LOG="$tmpdir/log.txt" \
    FAKE_REQUESTS_RESPONSES="$responses" \
    "$token_assignment" \
    python3 "$PROGRAM" "$@" an-organization a-repository \
    > "$tmpdir/out.txt" 2> "$tmpdir/err.txt" || program_status=$?
  requests_made="$(wc -l < "$tmpdir/log.txt" | tr -d ' ')"
}

fail() {
  echo "api-usage-test.sh: FAILED: $1" >&2
  echo "---------------- standard output" >&2
  cat "$tmpdir/out.txt" >&2
  echo "---------------- standard error" >&2
  cat "$tmpdir/err.txt" >&2
  echo "---------------- requests" >&2
  cat "$tmpdir/log.txt" >&2
  echo "----------------" >&2
  status=1
}

check_requests() {
  if [ "$requests_made" -ne "$1" ]; then
    fail "$2 made $requests_made requests, not $1"
  fi
}

# Test: the default cap stops the search before the end of the repository.
run_program pending UNUSED=
if [ "$program_status" -eq 0 ]; then
  fail "search with no successful job succeeded"
fi
check_requests "$default_max_commits" "the default cap"
if ! grep -q "No successful CI job found in the ${default_max_commits} commits" "$tmpdir/err.txt"; then
  fail "the default cap did not explain itself"
fi

# Test: --max-commits overrides the default cap.
run_program pending UNUSED= --max-commits 5
if [ "$program_status" -eq 0 ]; then
  fail "search with no successful job succeeded"
fi
check_requests 5 "--max-commits 5"

# Test: --max-commits=0 means no cap, so the search ends at the root commit.
run_program pending UNUSED= --max-commits 0
if [ "$program_status" -eq 0 ]; then
  fail "search with no successful job succeeded"
fi
check_requests "$repo_commits" "--max-commits 0"

# Test: GITHUB_PAT and GH_TOKEN are used to authenticate, and are the only
# things that cause an Authorization header to be sent.
for variable in GITHUB_PAT GH_TOKEN; do
  run_program success "${variable}=a-fake-token"
  if [ "$program_status" -ne 0 ]; then
    fail "search with a successful job failed"
  fi
  if [ "$(cat "$tmpdir/out.txt")" != "$head_sha" ]; then
    fail "search with a successful job did not output $head_sha"
  fi
  # Two requests:  the first page of check runs, then the commit statuses.
  check_requests 2 "$variable"
  if ! grep -q "auth=.*a-fake-token" "$tmpdir/log.txt"; then
    fail "$variable did not authenticate the request"
  fi
done
run_program success UNUSED=
if ! grep -q "auth=NONE" "$tmpdir/log.txt"; then
  fail "a request was authenticated with no token set"
fi

# Test: a transient failure is retried.
run_program "503 success" UNUSED=
if [ "$program_status" -ne 0 ]; then
  fail "a transient failure was not retried"
fi
# Three requests:  the first page of check runs, which fails and is then
# retried successfully, and the commit statuses.
check_requests 3 "a transient failure"

# Test: a credential that may read the repository but not its check runs is
# tolerated; the commit statuses decide the commit, as they did before this
# script consulted check runs at all.
run_program "forbidden success" GITHUB_PAT=a-fake-token
if [ "$program_status" -ne 0 ]; then
  fail "a refusal to supply check runs was not tolerated"
fi
if [ "$(cat "$tmpdir/out.txt")" != "$head_sha" ]; then
  fail "a refusal to supply check runs did not fall back to the commit statuses"
fi
check_requests 2 "a refusal to supply check runs"

# Test: a rate limit that will not reset for an hour is reported rather than
# waited for, and with no token set, the report suggests setting one.
run_program ratelimit UNUSED=
if [ "$program_status" -eq 0 ]; then
  fail "an exhausted rate limit was treated as success"
fi
check_requests 1 "an exhausted rate limit"
if ! grep -q "Set environment variable GITHUB_PAT or GH_TOKEN" "$tmpdir/err.txt"; then
  fail "an exhausted rate limit did not suggest setting a token variable"
fi

# Test: if a token variable is set but GitHub applied the unauthenticated rate
# limit, the report names the variable and says it is not being respected,
# rather than suggesting that it be set.
for variable in GITHUB_PAT GH_TOKEN; do
  run_program ratelimit "${variable}=a-fake-token"
  if [ "$program_status" -eq 0 ]; then
    fail "an exhausted rate limit was treated as success"
  fi
  if ! grep -q "Environment variable ${variable} is set" "$tmpdir/err.txt"; then
    fail "an ignored $variable was not reported"
  fi
  if ! grep -q "not respecting it" "$tmpdir/err.txt"; then
    fail "an ignored $variable was not described as unrespected"
  fi
  if grep -q "Set environment variable" "$tmpdir/err.txt"; then
    fail "an exhausted rate limit suggested setting $variable, which is set"
  fi
done

# Test: if the token was honored and its (larger) rate limit is exhausted, the
# report does not claim that the token is being ignored.
run_program ratelimit-authenticated GITHUB_PAT=a-fake-token
if [ "$program_status" -eq 0 ]; then
  fail "an exhausted rate limit was treated as success"
fi
if ! grep -q "5000 requests per hour is exhausted" "$tmpdir/err.txt"; then
  fail "an exhausted authenticated rate limit did not report the limit"
fi
if grep -q "not respecting it" "$tmpdir/err.txt"; then
  fail "an honored GITHUB_PAT was described as unrespected"
fi

# Test: an expected failure is reported without a Python stack trace.
if grep -q "Traceback" "$tmpdir/err.txt"; then
  fail "an exhausted rate limit printed a stack trace"
fi

if [ "$status" -eq 0 ]; then
  echo "api-usage-test.sh: passed."
fi
exit "$status"
