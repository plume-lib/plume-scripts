#!/bin/sh

# Tests the commit range that `set-git-range` yields in an Azure Pipelines pull
# request job.
#
# Azure checks out a merge commit, refs/pull/N/merge, whose first parent is the
# target branch and whose second parent is the pull request's head.  The
# checkout step's `fetchDepth` limits how much history the clone has.  This test
# checks that:
#  * `git diff` can use the range even when the clone lacks the fork point of
#    the pull request's branch, as when the branch lags its target branch by
#    more commits than the clone's depth, and even when the clone lacks the
#    merge commit's parents, as with `fetchDepth: 1`.
#  * The range's line numbers are those of the checked-out files, not those of
#    the pull request's head, which differ when the target branch has changed
#    the same file.

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
printf '%s\n' 1 2 3 4 5 6 7 8 9 10 > shared.txt
git add shared.txt
git commit -q -m "Fork point"
git checkout -q -b feature
# The pull request changes line 8 of shared.txt.
sed 's/^8$/eight/' shared.txt > shared.tmp
mv shared.tmp shared.txt
git commit -q -a -m "Feature commit 1"
i=2
while [ "$i" -le 5 ]; do
  echo "$i" > feature.txt
  git add feature.txt
  git commit -q -m "Feature commit $i"
  i=$((i + 1))
done
PR_HEAD="$(git rev-parse HEAD)"
git checkout -q main
# The target branch inserts 3 lines at the top of shared.txt, so the pull
# request's change is at line 11 of the merged file.
{
  printf '%s\n' a b c
  cat shared.txt
} > shared.tmp
mv shared.tmp shared.txt
git commit -q -a -m "Main commit 1"
i=2
while [ "$i" -le 5 ]; do
  echo "$i" > main.txt
  git add main.txt
  git commit -q -m "Main commit $i"
  i=$((i + 1))
done
git merge -q --no-edit feature > /dev/null
MERGE="$(git rev-parse HEAD)"
git reset -q --hard HEAD^1
git clone -q --bare . "$work/origin.git"
# Like GitHub, keep the pull request's refs outside refs/heads/.
git -C "$work/origin.git" update-ref refs/pull/1/head "$PR_HEAD"
git -C "$work/origin.git" update-ref refs/pull/1/merge "$MERGE"
git -C "$work/origin.git" branch -q -D feature

### The test

status=0

# check DEPTH DESCRIPTION: makes a clone of depth DEPTH the way that the Azure
# checkout step makes it, sources `set-git-range` in it, and checks the diff of
# the resulting commit range.  DESCRIPTION is used for diagnostics.
check() {
  depth="$1"
  description="$2"
  clone="$work/clone-$depth"

  git init -q -b main "$clone"
  # A file:// URL, because `git fetch --depth` ignores the depth for a local path.
  git -C "$clone" remote add origin "file://$work/origin.git"
  git -C "$clone" fetch -q --depth="$depth" origin \
    '+refs/heads/*:refs/remotes/origin/*' \
    '+refs/pull/1/merge:refs/remotes/pull/1/merge'
  git -C "$clone" checkout -q --detach "$MERGE"
  if git -C "$clone" merge-base "$MERGE^1" "$PR_HEAD" > /dev/null 2>&1; then
    echo "FAIL: test setup for $description: the clone contains the fork point"
    status=1
    return
  fi

  # Run with an empty environment except for the Azure Pipelines variables, so
  # that this test behaves the same whether or not it is itself running under
  # CI.  AZURE_HTTP_USER_AGENT is unset, so that `set-ci-org-and-branch` makes
  # no GitHub API request.
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
      git diff -U0 "$CI_COMMIT_RANGE" -- shared.txt | sed -n "s/^\(@@ [^@]* @@\).*/\1/p" || exit 3
    ' sh "$clone" "$PLUME_SCRIPTS" 2> "$work/stderr")" || run_status=$?
  if [ "$run_status" -ne 0 ]; then
    echo "FAIL: $description"
    echo "  exit status: $run_status"
    echo "  standard error:"
    sed 's/^/    /' "$work/stderr"
    status=1
    return
  fi

  expected="feature.txt
shared.txt
@@ -11 +11 @@"
  if [ "$actual" = "$expected" ]; then
    echo "PASS: $description"
  else
    echo "FAIL: $description"
    echo "  expected changed files and shared.txt hunk header:"
    printf '%s\n' "$expected" | sed 's/^/    /'
    echo "  actual changed files and shared.txt hunk header:"
    printf '%s\n' "$actual" | sed 's/^/    /'
    status=1
  fi
}

check 3 "an Azure pull request whose fork point is absent from the shallow clone"
check 1 "an Azure pull request whose merge commit's parents are absent from the shallow clone"

exit "$status"
