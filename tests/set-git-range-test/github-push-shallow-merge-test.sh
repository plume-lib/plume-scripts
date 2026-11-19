#!/bin/sh

# Tests the commit range that `set-git-range` yields in a GitHub Actions job
# for a push of a merge commit, in a shallow clone that lacks the merge base of
# the merge commit's parents.
#
# The `actions/checkout` step fetches only the pushed commit, to the depth that
# its `fetch-depth` gives.  This test checks that:
#  * For a push to a branch other than the default branch, the range is the
#    branch's changes relative to the default branch, even when the branch has
#    just merged in more commits of the default branch than the clone's depth.
#  * For a push to the default branch, the range starts at the merge base of
#    the merge commit's parents, even when the clone lacks that merge base.

set -eu

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)"
PLUME_SCRIPTS="$(CDPATH='' cd -- "${SCRIPT_DIR}/../.." && pwd -P)"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT HUP INT TERM

### The origin repository

# commit_files PREFIX COUNT: makes COUNT commits on the current branch, each of
# which changes file PREFIX.txt.
commit_files() {
  j=1
  while [ "$j" -le "$2" ]; do
    echo "$j" > "$1.txt"
    git add "$1.txt"
    git commit -q -m "$1 commit $j"
    j=$((j + 1))
  done
}

git init -q -b main "$work/upstream"
cd "$work/upstream"
git config user.email test@example.com
git config user.name "Test User"
echo 0 > base.txt
git add base.txt
git commit -q -m "Fork point"
FORK_POINT="$(git rev-parse HEAD)"

# The branch "feature" makes one commit, then merges in 10 commits of main.
git checkout -q -b feature
commit_files feature 1
git checkout -q main
commit_files main 10
MAIN_TIP="$(git rev-parse HEAD)"
git checkout -q feature
git merge -q --no-edit main > /dev/null
FEATURE_MERGE="$(git rev-parse HEAD)"

# The branch "long" forks from the fork point and makes 10 commits, then main
# merges it, after 5 more commits of main.
git checkout -q -b long "$FORK_POINT"
commit_files long 10
git checkout -q main
commit_files main2 5
git merge -q --no-edit long > /dev/null
MAIN_MERGE="$(git rev-parse HEAD)"

git branch -q -D long

# Two origin repositories:  one in which main has merged "long", and one in
# which main is as it was when "feature" merged it.
git clone -q --bare . "$work/origin-merged.git"
git reset -q --hard "$MAIN_TIP"
git clone -q --bare . "$work/origin.git"

### The test

status=0

# check ORIGIN BRANCH COMMIT EXPECTED_START EXPECTED_FILES DESCRIPTION: makes a
# clone of ORIGIN the way that `actions/checkout` makes it for a push of COMMIT
# to BRANCH, sources `set-git-range` in it, and checks the range's start and
# end and the files that its diff changes.  DESCRIPTION is used for
# diagnostics.
check() {
  origin="$1"
  branch="$2"
  commit="$3"
  expected_start="$4"
  expected_files="$5"
  description="$6"
  clone="$work/clone-$branch"

  git init -q -b main "$clone"
  # A file:// URL, because `git fetch --depth` ignores the depth for a local path.
  git -C "$clone" remote add origin "file://$origin"
  git -C "$clone" fetch -q --depth=3 origin "+$commit:refs/remotes/origin/$branch"
  git -C "$clone" checkout -q --detach "$commit"
  if git -C "$clone" merge-base "$commit^1" "$commit^2" > /dev/null 2>&1; then
    echo "FAIL: test setup for $description: the clone contains the merge base"
    status=1
    return
  fi

  # Run with an empty environment except for the GitHub Actions variables, so
  # that this test behaves the same whether or not it is itself running under
  # CI.
  run_status=0
  # The inner script is single-quoted on purpose:  its arguments are passed
  # positionally, so that this shell does not expand them into it.
  # shellcheck disable=SC2016
  actual="$(env -i PATH="$PATH" HOME="$HOME" \
    GITHUB_ACTIONS=true \
    GITHUB_EVENT_NAME=push \
    GITHUB_REF="refs/heads/$branch" \
    GITHUB_REF_NAME="$branch" \
    GITHUB_REPOSITORY=testorg/testrepo \
    GITHUB_SHA="$commit" \
    sh -c '
      cd "$1" || exit 2
      PLUME_SCRIPTS="$2"
      export PLUME_SCRIPTS
      . "$2/set-git-range" || exit 2
      echo "$CI_COMMIT_RANGE_START $CI_COMMIT_RANGE_END"
      git diff --name-only "$CI_COMMIT_RANGE" || exit 3
    ' sh "$clone" "$PLUME_SCRIPTS" 2> "$work/stderr")" || run_status=$?

  expected="$expected_start $commit
$expected_files"
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
    echo "  expected start and end, then changed files:"
    printf '%s\n' "$expected" | sed 's/^/    /'
    echo "  actual start and end, then changed files:"
    printf '%s\n' "$actual" | sed 's/^/    /'
    status=1
  fi
}

check "$work/origin.git" feature "$FEATURE_MERGE" "$MAIN_TIP" "feature.txt" \
  "a GitHub Actions push to a branch, of a merge of the default branch whose merge base is absent from the shallow clone"
check "$work/origin-merged.git" main "$MAIN_MERGE" "$FORK_POINT" "long.txt
main.txt
main2.txt" \
  "a GitHub Actions push to the default branch, of a merge whose merge base is absent from the shallow clone"

exit "$status"
