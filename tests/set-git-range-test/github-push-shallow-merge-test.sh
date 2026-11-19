#!/bin/sh

# Tests the commit range that `set-git-range` yields in a GitHub Actions job
# for a push to a branch other than the default branch, when the pushed commit
# merges the default branch into the branch.
#
# The `actions/checkout` step fetches only the pushed commit, to the depth that
# its `fetch-depth` gives, so the clone has no `origin/main`.  `set-git-range`
# then starts the range at the merge base of the merge commit's two parents.
# This test checks that it finds that merge base even when the clone lacks it,
# as when the merge brings in more commits of the default branch than the
# clone's depth.

set -eu

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)"
PLUME_SCRIPTS="$(CDPATH='' cd -- "${SCRIPT_DIR}/../.." && pwd -P)"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT HUP INT TERM

### The origin repository:  main, and a branch that forked from it and then
### merged many later commits of main.

git init -q -b main "$work/upstream"
cd "$work/upstream"
git config user.email test@example.com
git config user.name "Test User"
echo 0 > main.txt
git add main.txt
git commit -q -m "Fork point"
FORK_POINT="$(git rev-parse HEAD)"
git checkout -q -b feature
echo 1 > feature.txt
git add feature.txt
git commit -q -m "Feature commit"
git checkout -q main
i=1
while [ "$i" -le 10 ]; do
  echo "$i" > main.txt
  git commit -q -a -m "Main commit $i"
  i=$((i + 1))
done
git checkout -q feature
git merge -q --no-edit main > /dev/null
MERGE="$(git rev-parse HEAD)"
git checkout -q main
git clone -q --bare . "$work/origin.git"

### The test

status=0

# Make a clone the way that `actions/checkout` makes it for a push event.
clone="$work/clone"
git init -q -b main "$clone"
# A file:// URL, because `git fetch --depth` ignores the depth for a local path.
git -C "$clone" remote add origin "file://$work/origin.git"
git -C "$clone" fetch -q --depth=3 origin "+$MERGE:refs/remotes/origin/feature"
git -C "$clone" checkout -q --detach "$MERGE"
if git -C "$clone" merge-base "$MERGE^1" "$MERGE^2" > /dev/null 2>&1; then
  echo "FAIL: test setup: the clone contains the merge base"
  exit 1
fi

# Run with an empty environment except for the GitHub Actions variables, so
# that this test behaves the same whether or not it is itself running under CI.
run_status=0
# The inner script is single-quoted on purpose:  its arguments are passed
# positionally, so that this shell does not expand them into it.
# shellcheck disable=SC2016
actual="$(env -i PATH="$PATH" HOME="$HOME" \
  GITHUB_ACTIONS=true \
  GITHUB_EVENT_NAME=push \
  GITHUB_REF=refs/heads/feature \
  GITHUB_REF_NAME=feature \
  GITHUB_REPOSITORY=testorg/testrepo \
  GITHUB_SHA="$MERGE" \
  sh -c '
    cd "$1" || exit 2
    PLUME_SCRIPTS="$2"
    export PLUME_SCRIPTS
    . "$2/set-git-range" || exit 2
    printf "%s %s" "$CI_COMMIT_RANGE_START" "$CI_COMMIT_RANGE_END"
  ' sh "$clone" "$PLUME_SCRIPTS" 2> "$work/stderr")" || run_status=$?

description="a GitHub Actions push of a merge commit whose merge base is absent from the shallow clone"
expected="$FORK_POINT $MERGE"
if [ "$run_status" -ne 0 ]; then
  echo "FAIL: $description"
  echo "  exit status: $run_status"
  echo "  standard error:"
  sed 's/^/    /' "$work/stderr"
  status=1
elif [ "$actual" = "$expected" ]; then
  echo "PASS: $description"
else
  echo "FAIL: $description"
  echo "  expected start and end: $expected"
  echo "  actual start and end:   $actual"
  status=1
fi

exit "$status"
