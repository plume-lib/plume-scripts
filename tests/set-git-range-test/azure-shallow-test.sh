#!/bin/sh

# Tests that `set-git-range`, in an Azure Pipelines pull request job, yields a
# commit range that `git diff` can use even when the job's shallow clone does
# not contain the fork point of the pull request's branch.
#
# Azure checks out a merge commit, refs/pull/N/merge, whose first parent is the
# target branch and whose second parent is the pull request's head.  The
# checkout step's `fetchDepth` limits how much history the clone has.  When the
# pull request's branch lags its target branch by more commits than that, the
# fork point is absent, and `git diff START...END` fails with "no merge base".

set -eu

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)"
PLUME_SCRIPTS="$(CDPATH='' cd -- "${SCRIPT_DIR}/../.." && pwd -P)"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT HUP INT TERM

### The origin repository:  main, a pull request branch that forked from it
### long ago, and the merge commit that Azure would build.

git init -q -b main "$work/upstream"
cd "$work/upstream"
git config user.email test@example.com
git config user.name "Test User"
echo base > base.txt
git add base.txt
git commit -q -m "Fork point"
FORK_POINT="$(git rev-parse HEAD)"
git checkout -q -b feature
i=1
while [ "$i" -le 5 ]; do
  echo "$i" > feature.txt
  git add feature.txt
  git commit -q -m "Feature commit $i"
  i=$((i + 1))
done
PR_HEAD="$(git rev-parse HEAD)"
git checkout -q main
i=1
while [ "$i" -le 5 ]; do
  echo "$i" > main.txt
  git add main.txt
  git commit -q -m "Main commit $i"
  i=$((i + 1))
done
git merge -q --no-edit feature
MERGE="$(git rev-parse HEAD)"
git reset -q --hard HEAD^1
git clone -q --bare . "$work/origin.git"
# Like GitHub, keep the pull request's refs outside refs/heads/.
git -C "$work/origin.git" update-ref refs/pull/1/head "$PR_HEAD"
git -C "$work/origin.git" update-ref refs/pull/1/merge "$MERGE"
git -C "$work/origin.git" branch -q -D feature

### The CI job's clone, made the way that the Azure checkout step makes it.

git init -q -b main "$work/clone"
cd "$work/clone"
# A file:// URL, because `git fetch --depth` ignores the depth for a local path.
git remote add origin "file://$work/origin.git"
git fetch -q --depth=3 origin \
  '+refs/heads/*:refs/remotes/origin/*' \
  '+refs/pull/1/merge:refs/remotes/pull/1/merge'
git checkout -q --detach "$MERGE"

if git merge-base HEAD^1 "$PR_HEAD" > /dev/null 2>&1; then
  echo "FAIL: test setup: the clone is not shallow enough to omit the fork point"
  exit 1
fi

### The test

# Run with an empty environment except for the Azure Pipelines variables, so
# that this test behaves the same whether or not it is itself running under CI.
# AZURE_HTTP_USER_AGENT is unset, so that `set-ci-org-and-branch` makes no
# GitHub API request.
run_status=0
# The inner script is single-quoted on purpose:  its arguments are passed
# positionally, so that this shell does not expand them into it.
# shellcheck disable=SC2016
actual="$(env -i PATH="$PATH" HOME="$HOME" \
  BUILD_REASON=PullRequest \
  BUILD_SOURCEBRANCH=refs/pull/1/merge \
  BUILD_SOURCEVERSION="$MERGE" \
  SYSTEM_PULLREQUEST_TARGETBRANCH=main \
  SYSTEM_PULLREQUEST_SOURCEBRANCH=feature \
  SYSTEM_PULLREQUEST_SOURCECOMMITID="$PR_HEAD" \
  SYSTEM_PULLREQUEST_PULLREQUESTNUMBER=1 \
  sh -c '
    cd "$1" || exit 2
    PLUME_SCRIPTS="$2"
    export PLUME_SCRIPTS
    . "$2/set-git-range" || exit 2
    git diff --name-only "$CI_COMMIT_RANGE" || exit 3
  ' sh "$work/clone" "$PLUME_SCRIPTS" 2> "$work/stderr")" || run_status=$?
if [ "$run_status" -ne 0 ]; then
  echo "FAIL: an Azure pull request whose fork point is absent from the shallow clone"
  echo "  exit status: $run_status"
  echo "  standard error:"
  sed 's/^/    /' "$work/stderr"
  exit 1
fi

if [ "$actual" = "feature.txt" ]; then
  echo "PASS: an Azure pull request whose fork point is absent from the shallow clone"
else
  echo "FAIL: an Azure pull request whose fork point is absent from the shallow clone"
  echo "  expected changed files: feature.txt"
  echo "  actual changed files:   $actual"
  echo "  (fork point: $FORK_POINT)"
  exit 1
fi
